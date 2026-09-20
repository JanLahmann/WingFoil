# The direct transfer — wire format and protocol (dev2)

The watch sends the recording to the phone over the Connect IQ link, in pages, after the
probe of 19 September 2026 fixed the rules (docs/direct-transfer.md §5): **pages of at most
8 000 payload bytes, exactly one in flight, the next from `onComplete`, an app-level ACK,
the phone app open.** This file is the contract both ends are tested against. The third
statement of the bytes, in plain Python, is `lab/tools/cjr_ref.py`; its worked example is
quoted below and pinned by `--check`, by the kit's `DirectStreamTests`, and by the watch's
`WingfoilTests` (`directStreamMatchesTheReference`).

Everything is **little-endian**, stated rather than inherited, as `WatchSessionContainer`
already does for the Apple Watch's `.cjw`.

## 1 · Streams and pages

A session is one or more **streams**. Stream 0 is the record stream, one record per GPS
fix, encoding `rec.v1` (§2). Stream 1 will be the wrist magnitudes (dev3) and gets its own
encoding then; the page header already carries the stream number so dev3 adds no message.

A stream is cut into **pages** of at most `PAGE_BYTES` = 8 000 payload bytes. A page never
splits a record, and **every page opens with a keyframe**, so each page decodes on its own
and a page that never arrives costs its seconds, not the session. Page 0 of a stream starts
with the 16-byte stream header (§2.1); the archive of a stream is the concatenation of its
pages in order, nothing added.

## 2 · Stream 0 — `rec.v1`

### 2.1 Stream header (20 B, page 0 only)

| offset | type | field |
|---|---|---|
| 0 | `char[4]` | magic `CJR1` |
| 4 | `uint8` | schema, **2** |
| 5 | `uint8` | stream, 0 |
| 6 | `uint16` | app version, `minor << 8 \| fitSchema`, as `SES_APP_VERSION` |
| 8 | `uint32` | session start, epoch seconds — the card's `KEY_START` |
| 12 | `int16` | wind direction the rider set, 0..359, −1 unset |
| 14 | `uint8` | discipline, 0 = wingfoil |
| 15 | `uint8` | flags, 0 |
| 16 | `int16` | the watch's clock offset at start, minutes east of UTC; `0x7FFF` = none |
| 18 | `uint16` | reserved, 0 |

Schema 1 (19 September 2026, the first field test) had the 16-byte header without the
offset and is still read; the phone then guesses the zone from longitude, which is the solar
offset and an hour out under summer time — exactly what the first direct session showed.

### 2.2 Records

Two record shapes, told apart by the first byte: `0xFF` is a keyframe, anything else is the
`dt` of a delta record (1..254).

**Keyframe, 22 B**

| type | field |
|---|---|
| `uint8` | `0xFF` |
| `uint32` | `t`, epoch seconds |
| `int32` | latitude, 1e-7 degrees |
| `int32` | longitude, 1e-7 degrees |
| `uint16` | Doppler speed, cm/s |
| `int16` | altitude, metres, `0x7FFF` = none |
| `uint8` | heart rate, 0 = none |
| `uint8` | `REC_FOIL_STATE` |
| `uint8` | `REC_PUMP_CADENCE` |
| `uint8` | `REC_TURN_MARKER` |
| `uint8` | `REC_TICK` |

**Delta, 13 B**

| type | field |
|---|---|
| `uint8` | `dt`, seconds since the previous record, 1..254 |
| `int16` | Δ latitude, **1e-6** degrees |
| `int16` | Δ longitude, 1e-6 degrees |
| `uint16` | Doppler speed, cm/s, absolute |
| `int8` | Δ altitude, metres |
| `uint8` | heart rate, absolute |
| `uint8` | foil state |
| `uint8` | pump cadence |
| `uint8` | turn marker |
| `uint8` | tick |

The encoder keeps its position in 1e-7 units and moves it by `Δ × 10`; the decoder does the
same, so both hold the identical quantised state. The four developer fields are the FIT
record's, byte for byte, so `FitSchema` stays the one definition of what they mean.

**Rounding is half away from zero, everywhere, and is spelled out rather than taken off a
library.** Python's `round` rounds half to even, Swift's `rounded()` rounds half away from
zero and Monkey C follows C, and three implementations that disagree about one ten-millionth
of a degree produce a delta that is off by one for the rest of the page. So:

* degrees → units is `int(deg × scale ± 0.5)` **truncated**, scale 1e7 for a keyframe and
  1e6 for a delta (`_q` in `cjr_ref.py`, `DirectStream.quantise` in the kit);
* the 1e-6 base a delta is measured from is `(q7 ± 5) / 10` with **C-style (truncating)**
  integer division, never a floor (`_base6`, `DirectStream.base6`).

**The position budget.** A delta lands the position on the 1e-6 grid, half a micro-degree of
error, and the keyframe it was measured from sat on the 1e-7 grid, whose last digit rides
along unchanged for the rest of the run. So **one micro-degree in the worst case, about
eleven centimetres**, and bounded rather than accumulating: the carried digit is a constant,
not a sum. Both ends hold the identical integers, which is the property that matters.

**When a keyframe is written**: the first record of a stream, the first record of every
page, every 60th record, and whenever a delta cannot express the step — a gap over 254 s
(a pause), a position jump beyond ±0.032°, an altitude jump beyond ±127 m, or altitude
appearing or disappearing. At one fix a second a two-hour session is about 97 KB, thirteen
pages, about 26 s at the measured rate.

### 2.3 Worked example

Header `stream 0, app 0x0902, start 1756556820, wind 200, wingfoil, clock +120 min`, then three fixes one
second apart at Lake Garda (45.871°, 10.863°), speeds 0 / 3.10 / 6.40 m/s, altitude 66, 66,
65 m, heart rate 98, 101, 104, foil state 0, 1, 2, cadence 0, 0, 12, marker 0, 0, 3, tick
0, 1, 2. Encoded, 68 bytes:

```
434a5231 02 00 0209 14eeb268 c800 00 00 7800 0000              header
ff 14eeb268 f05b571b f08f7906 0000 4200 62 00 00 00 00        keyframe
01 0500 0c00 3601 00 65 01 00 00 01                           delta
01 0600 0d00 8002 ff 68 02 0c 03 02                           delta
```

`python3 lab/tools/cjr_ref.py` prints these bytes; `--check` re-derives them and decodes
them back.

## 3 · Messages

All messages are Connect IQ dictionaries with string keys and integer values, except the
page bytes.

**Page, watch → phone**

| key | value |
|---|---|
| `cjr` | 1, the message schema |
| `sid` | session start, epoch seconds (the card's `KEY_START`; with `dur` it is the dedupe key of ADR-013) |
| `st` | stream number |
| `p` | page index, from 0 |
| `n` | page count, or 0 while the stream is still being recorded |
| `e` | 1 on the last page of the stream, absent otherwise |
| `b` | the page bytes: `ByteArray` on API ≥ 6.0.0, `Array<Number>` (one byte per Number, 0..255) below it — dev3 packs four per Number |

**ACK, phone → watch** — flat: three keys, three integers

| key | value |
|---|---|
| `cjrAck` | page index |
| `cjrSid` | session start, epoch seconds |
| `cjrSt` | stream number |

**Need, phone → watch** — sent **always** once the page with `e = 1` has arrived

| key | value |
|---|---|
| `cjrNeed` | the missing pages as one comma-joined string, `"1,4"`; at most 32; `""` when nothing is missing |
| `cjrSid`, `cjrSt` | as above |

The empty string is the watch's signal that the stream is whole and its buffers can be
freed. The phone sends the list again whenever the missing set changes, and not otherwise. A
page that arrives twice is **acknowledged again and stored once**.

**Why flat.** The first shape was `cjrAck: [sid, st, p]`. On the field test of 19 September
2026 every page reached the phone and no acknowledgement ever reached the watch: Garmin's
phone SDK does not carry a nested array in a message to a device app, and the failure came
back as a result the phone swallowed. Nothing phone → watch nests anything now; the wind and
the map never did, which is why they always worked. The watch still reads the array shape.

The card (`PhoneLink.summary`) is sent as before, its own message after save, and can arrive
before, between or after the pages. It is told from a page by its key, and the two paths
never take each other's messages.

**The card gained a key on 20 September 2026: `cx`, the crash count** (`CrashBreadcrumb`,
docs/testing.md "The watch's crash hunt"). Connect IQ has no crash reporting, so the number of
runs that never reached `onStop` on that watch is only ever visible on the watch itself unless
something carries it off; the card is the only channel there is. Always present, `0` on a watch
that has never lost a run. Twenty-two keys now, 201 B of the 1024 B budget
(`phoneLinkPayloadFitsBudget`). **The phone reads it since 20 September 2026.**
`CompanionSummary` takes `cx` off the card as the one **optional** key on it — absent,
unreadable or past 999 all decode to nil, and never to a refused card, because a watch older
than 0.9.14-dev6 or newer than this app still has a session to land. `SessionIngestor` keeps
the number on the session the card wrote (`SessionRow.watchCrashes`, GRDB **v18**; a card
that says nothing leaves the last number standing), and the beta feedback mail prints it
under the phone's own "Recent crashes": *Watch app: 3 runs ended without a save*, or *Watch
app: no crashes reported* for a watch that has lost none, and no line at all when no card
ever carried the key — nil and 0 are different claims and the mail says them differently.
`CrashDigestTests` holds the three states, `CompanionTests` the three shapes of the key.
There is no Settings row and no screen: one reader, the mail.

**What the stream itself carries of the session block is the wind axis**: the header's
`wind_dir` lands in `RawTrack.watchSummary.windDirUserDeg`, where the FIT parser puts
`SES_WIND_DIR`, so the turn namer and the wind estimator read one channel whichever door a
session came through. Attaching the rest of the **card** to the direct row as a
`watchSummary` — which is what the divergence banner compares against — is not built:
`SessionIngestor.ingest(card:)` and `ingest(fitData:)` are two paths and the card's twenty
integers do not cross between them today. Until they do, a direct session shows no divergence
banner, which is the honest answer rather than an empty one.

## 4 · The watch

- **Recording.** Every fix in `STATE_RECORDING` is one record. Pages close when the next
  record would not fit; the closed page goes on the send queue. The record stream lives in
  memory (a page is 8 KB; a two-hour session's thirteen pages are 104 KB of the 786 KB
  heap) and acknowledged pages are freed.
- **Sending.** One page in flight. Sent when the phone is reachable, nothing is in flight,
  and the queue is not empty — checked after every page closes, on save, on the link's
  connected edge (`PhoneLink.pollLink`), and at app start. `onComplete` starts a 6 s ACK
  timer; the ACK clears the page. No ACK, or `onError`: retry the same page up to three
  times, then wait for the next connected edge. A `cjrNeed` re-queues the pages named.
- **Save.** `finishSave` closes the last page with `e = 1` and `n` set, sends the card as
  today, and keeps sending while the SAVED screen is up. **Exit** persists what is still
  unacknowledged to Storage (`cjr.idx` plus `cjr.p<i>`, 8 KB a value, at most **ten pages**;
  older pages beyond that are dropped and the index says so), and the next app start
  re-queues it. A session longer than ten pages is sent whole only while the app is open.
- **Dev only, and no new switch.** `(:dev)` annotated, and gated on the **existing
  `phonePush`** setting — the card's switch. A rider who lets the watch talk to the phone
  gets the recording as well as the card; a rider who does not gets neither. Nothing new
  appears in Garmin Connect's settings and nothing new appears in the app.
- **Sizes.** `PhoneLink.estimateBytes` is not the ceiling for pages; the measured ceiling
  is. A page message is never larger than 8 000 payload bytes plus its five keys.

## 5 · The phone (dev build)

- `ConnectIQCompanionLink.receivedMessage` hands a `cjr` message to `DirectTransferInbox`,
  which writes the page to `Application Support/GarminInbox/<sid>/<st>/p<i>.bin` and
  answers `cjrAck` at once; a repeat of a stored page is acknowledged again, not stored.
- When the page with `e = 1` has arrived and `n` is known, the inbox checks 0..n−1 and sends
  `cjrNeed` — the gaps, or the empty list. When none are missing the pages are concatenated
  into `<sid>.cjr` in the inbox, the page files are deleted, and the file is imported through
  `SessionIngestor` with a new `ImportSource.watchDirect`, `TrackFormat.direct` (`cjr`,
  sniffed by the magic) and `DirectStreamParser` → `RawTrack`: `capabilities.hasSpeed`,
  `hasPosition`, `hasDevFields`, `hasHR` as the data says, `hasAccel` false, `sampleRateHz`
  1. The class follows `SourceCapabilities.sourceClass`; nothing here invents a letter
  (pattern L). The stream carries the four record developer fields, so that letter is **a** —
  the same one the FIT of the same afternoon gets, written by the same detectors. A class-(a)
  recording without a wrist stream is already the ordinary case, because `accelLogging` is
  off by default on the watch.
- **Dedupe** is the card's: start epoch ± 60 s (`SessionIngestor`), and the intervals.icu
  copy, when it arrives, replaces the row in place (ADR-013). A card that arrived first left
  a provisional row; the direct session fills it. The direct row is **not** provisional — it
  has a real analysis behind it and counts from the moment it lands — but it does step aside
  for a FIT of the same afternoon, because the FIT carries the laps, the wrist stream and the
  local clock that the stream does not (`SessionIngestor.yields`).
- A stream that never completes stays in the inbox; after 24 h without a page it is
  assembled up to its first gap and imported as far as it goes. **It is marked cut short on
  the transfer's receipt and not on the session row**: the library has no such column, and
  adding one for a dev door would be a schema migration every channel then carries. Settings
  → Garmin watch says "cut short" beside that transfer. A `cutShort` column is the right
  answer the day the door moves up a channel.
- **What the rider sees.** Nothing new to switch on. Settings → Garmin watch shows the last
  direct session (start, pages, seconds) under the link probe row; the session appears in
  the list with the watch source, "Garmin watch, direct".

## 6 · What dev3 changes

Stream 1, the 25 Hz wrist magnitudes, sent after stream 0 as a whole: same page message,
`st = 1`, its own encoding. The phone re-derives the session when the stream completes.
The fenix 5 Plus family's `Array<Number>` pages pack four payload bytes per Number
(`flags` bit 0 in the stream header says so). Neither changes §3.
