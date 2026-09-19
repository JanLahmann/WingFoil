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

### 2.1 Stream header (16 B, page 0 only)

| offset | type | field |
|---|---|---|
| 0 | `char[4]` | magic `CJR1` |
| 4 | `uint8` | schema, 1 |
| 5 | `uint8` | stream, 0 |
| 6 | `uint16` | app version, `minor << 8 \| fitSchema`, as `SES_APP_VERSION` |
| 8 | `uint32` | session start, epoch seconds — the card's `KEY_START` |
| 12 | `int16` | wind direction the rider set, 0..359, −1 unset |
| 14 | `uint8` | discipline, 0 = wingfoil |
| 15 | `uint8` | flags, 0 |

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
same, so both hold the identical quantised state and the error never exceeds 0.5e-6 degrees,
about 5 cm. The four developer fields are the FIT record's, byte for byte, so
`FitSchema` stays the one definition of what they mean.

**When a keyframe is written**: the first record of a stream, the first record of every
page, every 60th record, and whenever a delta cannot express the step — a gap over 254 s
(a pause), a position jump beyond ±0.032°, an altitude jump beyond ±127 m, or altitude
appearing or disappearing. At one fix a second a two-hour session is about 97 KB, thirteen
pages, about 26 s at the measured rate.

### 2.3 Worked example

Header `stream 0, app 0x0902, start 1756556820, wind 200, wingfoil`, then three fixes one
second apart at Lake Garda (45.871°, 10.863°), speeds 0 / 3.10 / 6.40 m/s, altitude 66, 66,
65 m, heart rate 98, 101, 104, foil state 0, 1, 2, cadence 0, 0, 12, marker 0, 0, 3, tick
0, 1, 2. Encoded, 64 bytes:

```
434a5231 01 00 0209 14eeb268 c800 00 00                        header
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

**ACK, phone → watch**

| key | value |
|---|---|
| `cjrAck` | `[sid, st, p]` |

**Need, phone → watch** — sent once after the last page arrived, listing gaps

| key | value |
|---|---|
| `cjrNeed` | `[sid, st, [p, p, …]]`, at most 32 pages |

The card (`PhoneLink.summary`) is sent as before, its own message after save. The phone
attaches it to the direct session as `watchSummary` so the divergence banner works; the
card can arrive before, between or after the pages.

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
- **Dev only.** `(:dev)` annotated, `directSend` defaults to true in the dev stream; the
  switch reaches the beta with the promotion.
- **Sizes.** `PhoneLink.estimateBytes` is not the ceiling for pages; the measured ceiling
  is. A page message is never larger than 8 000 payload bytes plus its five keys.

## 5 · The phone (dev build)

- `ConnectIQCompanionLink.receivedMessage` hands a `cjr` message to `DirectTransferInbox`,
  which writes the page to `Application Support/GarminInbox/<sid>/<st>/p<i>.bin` and
  answers `cjrAck` at once; a repeat of a stored page is acknowledged again, not stored.
- When the page with `e = 1` has arrived and `n` is known, the inbox checks 0..n−1; gaps go
  out once as `cjrNeed`. When none are missing the pages are concatenated into
  `<sid>.cjr` in the inbox and imported through `SessionIngestor` with a new
  `ImportSource.watchDirect`, `TrackFormat.direct` (`cjr`, sniffed by the magic) and
  `DirectStreamParser` → `RawTrack`: `capabilities.hasSpeed`, `hasPosition`,
  `hasDevFields`, `hasHR` as the data says, `hasAccel` false, `sampleRateHz` 1. The class
  follows `SourceCapabilities.sourceClass`; nothing here invents a letter (pattern L).
- **Dedupe** is the card's: start epoch ± 60 s (`SessionIngestor`), and the intervals.icu
  copy, when it arrives, replaces the row in place (ADR-013). A card that arrived first left
  a provisional row; the direct session fills it.
- A stream that never completes stays in the inbox; after 24 h without a page it is
  imported as far as it goes and marked cut short (`cutShort`, as a recording the watch
  stopped early is today).
- **What the rider sees.** Nothing new to switch on. Settings → Garmin watch shows the last
  direct session (start, pages, seconds) under the link probe row; the session appears in
  the list with the watch source, "Garmin watch, direct".

## 6 · What dev3 changes

Stream 1, the 25 Hz wrist magnitudes, sent after stream 0 as a whole: same page message,
`st = 1`, its own encoding. The phone re-derives the session when the stream completes.
The fenix 5 Plus family's `Array<Number>` pages pack four payload bytes per Number
(`flags` bit 0 in the stream header says so). Neither changes §3.
