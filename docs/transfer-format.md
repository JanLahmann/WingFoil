# The direct transfer — wire format and protocol (dev3)

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
fix, encoding `rec.v1` (§2). Stream 1 is the wrist magnitudes, `wrist.v1` (§2b), and rides
after stream 0 has crossed whole. The page message carries the stream number, so the second
stream added no message.

A stream is cut into **pages** of at most `PAGE_BYTES` = 8 000 payload bytes. A page never
splits a record, and **every page opens with a keyframe** — a window header in stream 1 — so
each page decodes on its own and a page that never arrives costs its seconds, not the
session. Page 0 of a stream starts with the 20-byte stream header (§2.1); the archive of a
stream is the concatenation of its pages in order, nothing added.

## 2 · Stream 0 — `rec.v1`

### 2.1 Stream header (20 B, page 0 only)

| offset | type | field |
|---|---|---|
| 0 | `char[4]` | magic `CJR1` |
| 4 | `uint8` | schema, **2** |
| 5 | `uint8` | stream, 0 or 1 |
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

## 2b · Stream 1 — `wrist.v1` (0.9.18-dev1)

The 25 Hz wrist magnitudes, **inside the windows the watch flagged and nowhere else**. Two
hours at 25 Hz is 180 000 samples and about 180 KB after delta coding, which fits the memory
of no watch in the manifest; ADR-031 has the arithmetic and the three forms that were weighed.

### 2b.1 Stream header

The 20 bytes of §2.1 with **`stream` = 1**. Schema is unchanged — the header did not move, so
nothing bumps. The wind axis and the discipline repeat stream 0's rather than being zeroed,
so a wrist stream that arrives on its own still says which afternoon and which sport it is.

**Page 0 of stream 1 is that header alone — twenty bytes and one message.** Stream 1's pages
are dropped under budget pressure on the watch (§4) and are only numbered at save, so the
header cannot ride on a page that might not survive.

### 2b.2 Windows

The magnitudes are `|a|` in **centi-g, gravity included** — a resting wrist reads about 100 —
quantised half away from zero. Resolution is 0.01 g against a measured per-sample σ of
0.114 g, so the quantum is a tenth of the noise. Samples inside a window are exactly
**40 ms apart** (`WRIST_HZ` = 25, `WRIST_STEP_MS` = 40) and carry no time of their own.

Two record shapes, told apart by the first byte.

**Window header, 9 B** — `0xFF`

| type | field |
|---|---|
| `uint8` | `0xFF` |
| `uint32` | `t`, epoch seconds of the first sample |
| `uint16` | `ms`, milliseconds within that second, 0..999 |
| `uint16` | `n`, samples in this window, 1..250 |

then exactly `n` magnitude codes:

* **escape** — `0xFE` followed by a `uint16` absolute magnitude, 3 B. The **first code of a
  window is always an escape**, so a window decodes with nothing in front of it.
* **delta** — one byte `v` in `0x00..0xFD`, meaning `v − 126` centi-g against the previous
  sample: **−126 to +127**. `0xFE` and `0xFF` are the two tags and are therefore not deltas.

A window is capped at **250 samples (10 s)**; a longer flagged stretch becomes consecutive
windows, each with its own header and its own absolute first sample. Typical cost is
`n + 11` bytes, about **26 B per covered second**, and ±1.26 g between two 25 Hz samples is
far outside real wrist motion, so escapes are the landing spikes and almost nothing else.

**Every window carries one second of lead-in and one second of tail beyond the flagged
span** — 25 samples each side. That is the phone's 51-tap band-pass group delay: without it
the first and last second of every window are attenuated and the strokes at a window's edge
are the ones the phone would miss.

### 2b.3 What the seconds between windows are

**Sensor gaps, and nothing new.** `PumpAnalyzer` / `pump.py` bin the whole session at 25 Hz,
hold empty bins at the session mean so the FIR does not ring on them, mark them `valid =
false` and pick no stroke there. That is exactly what a `SensorLogging` hole already is
(docs/algorithms.md, "Reading the stream"). So a windowed stream needs no new capability, no
new channel and no new source letter (pattern L): `SourceCapabilities.hasAccel` goes true,
`accelClockReconstructed` stays **false** because these are real per-sample times off the
watch's own grid, and the uncovered stretches behave the way an accelerometer hole has always
behaved.

**What the stream is not.** `sourceClass` is `a` on developer fields, `b` on speed, `c`
otherwise — `hasAccel` is not one of its inputs, so a direct session was already class (a)
and stays class (a). What stream 1 buys is the *analysis*: the phone runs the lab's own pump
chain over real magnitudes instead of reading the watch's live approximation off the
`pump_cadence` column (ADR-005), and `pumpsToTakeoff`, the failed-attempt count, the pump
rung of the touchdown ladder and the pump-versus-cruise HR split stop reading nil.

### 2b.4 Worked example

Header `stream 1, app 0x0902, start 1756556820, wind 200, wingfoil, clock +120 min`, then one
window of five samples opening 1.4 s into the session: 1.00, 1.03, 0.99, 4.00, 3.98 g — a
resting wrist, two small steps, a landing spike no 8-bit delta can say, and a step back down.
Encoded, **38 bytes**:

```
434a5231 02 01 0209 14eeb268 c800 00 00 7800 0000      header (page 0, alone)
ff 15eeb268 9001 0500                                  window: t+1 s, 400 ms, 5 samples
fe 6400 81 7a fe 9001 7c                               100, +3, −4, 400, −2
```

`python3 lab/tools/cjr_ref.py` prints these bytes too; `--check` re-derives them and decodes
them back, `lab/tests/test_cjr_ref.py` fuzzes them, the kit's `DirectWristTests` and the
watch's `directWristStreamMatchesTheReference` pin the same string.

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
| `b` | the page bytes: `ByteArray` on API ≥ 6.0.0, `Array<Number>` below it |
| `f` | flags, **bit 0 = the payload is packed four bytes per Number**. Absent means zero |
| `bl` | with `f & 1`, the payload's true length in bytes. **Required there**, meaningless otherwise |

**The packed page** (0.9.18-dev1). `Communications.transmit` takes a `ByteArray` only from
Connect IQ 6.0.0 — the fenix 8, the fr970 and the enduro 3 have it, the fenix 7 (5.2.0) and
the fenix 5 Plus (3.3.3) do not — so 30 of the 42 products we ship send an `Array<Number>`.
One byte per Number is what 0.9.14-dev2 sent, and `PhoneLink.estimateBytes` prices a Number
at **five wire bytes**: an 8 000 B page cost 40 KB and the pre-6.0.0 fleet was never going to
carry one. Four bytes per Number costs the same five for four, so the page costs 10 KB.

Bytes go **little-endian within the 32-bit word**: byte `4w + j` sits at bits `8j` of word
`w`. The last word is zero-filled, which is why `bl` exists. A Monkey C Number is **signed**,
so a word whose top byte is ≥ 0x80 arrives negative; the bit pattern is what matters and both
signs give the same one. A `bl` that is not within one word of what the array can hold is a
page lying about its size and is refused, not padded.

**Why the flag is on the message and not in the stream header's `flags` byte**, where an
earlier sketch of this section put it: the header is *inside* the payload. A phone that had
to read the header first could not unpack the page the header is in. `f` and `bl` are flat
integers, like everything else the two ends exchange.

A watch that packs a page the phone was not told about is **refused whole** rather than
truncated into nonsense: without `f`, a Number outside 0..255 is not a byte.

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
- **The wrist ring.** `PumpDetector._pushGrid` is the single point every 25 Hz grid
  magnitude passes, so that is where stream 1 is fed from — the phone is handed exactly the
  numbers the watch's own band-pass read, decimated and milli-g-sniffed the same way, not a
  second reading of the sensor. `SessionController` raises the window flag once a second
  when the rider is **off the foil**, a **turn window is open**, or the live detector picked
  a **stroke in the last ten seconds** (`pump.cadence > 0`). No pump detection means no wrist
  stream at all and no buffers for one.
- **The budget.** Stream 1 may hold **60 000 B** of closed page (about 38 minutes of covered
  riding, eight pages), or **24 000 B** where `System.getSystemStats().totalMemory` is under
  700 KB — the fr255's 508 KB. When the budget bites, half the pages already held are dropped
  and the encoder admits half as many windows from then on, so a long session is **thinner
  rather than shorter**. Geometric: a six-hour session thins four times and stops. The
  simulator reports its own 8 MB heap, so every simulated device takes the big budget and
  only a real fr255 takes the small one; the ceiling is what the suite proves, and it holds
  at either value.
- **Sending.** One page in flight. Sent when the phone is reachable, nothing is in flight,
  and the queue is not empty — checked after every page closes, on save, on the link's
  connected edge (`PhoneLink.pollLink`), and at app start. `onComplete` starts a 6 s ACK
  timer; the ACK clears the page. No ACK, or `onError`: retry the same page up to three
  times, then wait for the next connected edge. A `cjrNeed` re-queues the pages named.
  **Stream 0 first, whole, then stream 1** — Jan's call, 19 September 2026: *"Send it later,
  not first."* The empty `cjrNeed` for stream 0 is what starts stream 1.
- **Save.** `finishSave` closes the last page with `e = 1` and `n` set, sends the card as
  today, and keeps sending while the SAVED screen is up. **Exit** persists what is still
  unacknowledged to Storage (`cjr.idx` plus `cjr.p<i>`, 8 KB a value, at most **ten pages**;
  older pages beyond that are dropped and the index says so), and the next app start
  re-queues it. A session longer than ten pages is sent whole only while the app is open.
  The index names its **stream**, and what is persisted is the stream the sender was working
  on: two streams of ten pages would be twice the Storage this app has, and a wrist stream
  whose record stream never landed has nothing to attach to anyway.
- **What the rider sees while it happens.** `DirectSend.statusLine()` — `phone 4/13` while
  the recording crosses, `wrist 2/8` while the wrist stream follows, `phone ok` when
  everything is across, nothing when there is nothing to say. Drawn under the SAVED pill and
  on the START screen (docs/presentation.md), and one short buzz when the **last** stream is
  whole, because that is when the rider can walk away. A device app has no notification API;
  the page is the notification.
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
  `hasPosition`, `hasDevFields`, `hasHR` as the data says, `sampleRateHz` 1, and `hasAccel`
  true only where the wrist sidecar (§6) is already on disk beside it. The class follows
  `SourceCapabilities.sourceClass`; nothing here invents a letter
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

## 6 · The wrist stream on the phone (0.9.18-dev1)

Stream 1's pages arrive through the same inbox as stream 0's — the same page files under
`GarminInbox/<sid>/1/`, the same `cjrAck`, the same `cjrNeed`, the same 24-hour sweep. What
is different is what it becomes when it is whole.

- **It is not a recording and never becomes a row of its own.** The assembled archive lands
  as `<sid>.cjrw`, an extension `DirectTransferInbox.pending()` does not pick up, so no
  importer can ever mistake it for a session.
- **It is matched to the session it belongs to** by start epoch within ±60 s — the same key
  the rest of the direct transfer uses (ADR-013), asked without a duration because a wrist
  stream carries none. A stream whose session is not in the library yet is **left in the
  inbox**, not refused: the pages may simply have outrun the record stream's import, and the
  next launch tries again.
- **It is filed as a sidecar**, `wrist.cjr` beside the session's archived `original.cjr`.
  `SessionArchive.storeOriginal` keeps exactly one original per session, and the wrist stream
  is not an original — it is a second channel of the one already there. `rawTrack(for:)`
  attaches it whenever the original beside it is a `.cjr`, which is what makes **every** later
  re-analysis see it, with no second ingest path.
- **The session is re-derived in place.** `SessionIngestor.attachWristStream` files the
  sidecar and calls `reanalyze` — the same call a moved tuning slider makes. The row keeps
  its id, its gear, its name and its note; `hasAccel` becomes true and the pump, takeoff,
  turn-pump and HR-cost answers that read nil start reading numbers.
- **The class letter does not move and was never going to.** `sourceClass` is `a` on the
  developer fields with or without a wrist stream (§2b.3).
- A sidecar that cannot be decoded, or one for a session that did not come over the link, is
  **refused rather than filed**: a sidecar that was filed would be re-read and re-refused at
  every re-analysis for ever.

Settings → Garmin watch names the stream on the page line (`wrist page 3 of 8`) and on the
receipt, so a tester can see which of the two is crossing.
