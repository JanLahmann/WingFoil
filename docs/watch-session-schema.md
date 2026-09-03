# Watch Session Container (`.cjw`) — contract

**Single source of truth** for the file the CleanJibe watchOS app writes and the iPhone app
reads. One implementation on each side of the transfer, and they are **the same file**:
`ios/WingFoilKit/Sources/WingFoilKit/WatchImport/WatchSessionContainer.swift` is compiled into
both WingFoilKit and the `WingFoilWatch` target (see `ios/project.yml`), exactly the way
`WidgetSnapshot.swift` is shared with the widget. A writer and a reader that cannot disagree
is worth more here than a tidier module graph.

- `CONTAINER_VERSION`: **1** (the envelope — magic, header, stream table)
- `SCHEMA`: **1** (the meaning of the fields, carried in `meta.schema`)
- Extension: `.cjw` · `TrackFormat.watch` · archived as `original.cjw`
- Endianness: **little-endian IEEE 754 throughout**, stated rather than inherited
- Producer: `ios/WingFoilWatch/` · Consumer: `WingFoilKit/WatchImport/WatchSessionParser.swift`

## Why a binary container and not JSON

A two-hour session is ~7 200 position fixes, ~2 500 heart-rate readings and **~360 000
accelerometer samples**. As JSON that is roughly 12 MB to serialise on a watch, hand to
`WCSession.transferFile` and re-parse on a phone. Packed it is **2.9 MB**, and the packing is
eight lines of arithmetic. The header stays JSON because it is small, self-describing, and the
only part a human ever has to read.

The streams are flat runs of fixed-width records with no framing, which is what makes them
**appendable**: the recorder writes each sensor straight to its own file as samples arrive and
the container is assembled at stop by concatenation. Nothing that grows with session length is
ever only in memory, and an interrupted session leaves partial stream files that are still
individually valid — see "Crash recovery" below.

## Layout

```
offset  size   contents
0       4      magic "CJWS"
4       4      uint32  container version (1)
8       4      uint32  header length H
12      H      header JSON (UTF-8)
12+H    ...    payload: the streams, concatenated in header order
```

Stream offsets in the header are **relative to the start of the payload**, not to the start of
the file, so a header that grows by one character does not move every stream.

`TrackParser.format` recognises the container by the first four bytes. It cannot collide with
the other two inputs: a FIT carries `.FIT` at byte 8, a GPX starts with `<`.

## Header

```json
{
  "meta": {
    "schema": 1,
    "sessionId": "UUID the watch minted",
    "startEpoch": 1756000000.0,
    "utcOffsetS": 7200,
    "durationS": 3612.4,
    "activityType": "surfingSports",
    "discipline": "wingfoil",
    "locationRateHz": 1,
    "accelRateHz": 50,
    "producer": "CleanJibe watchOS 0.12.0 (14)",
    "device": "Apple Watch",
    "systemVersion": "26.5"
  },
  "streams": [
    { "name": "track", "encoding": "track.v1", "recordBytes": 40, "count": 7200, "offset": 0, "length": 288000 },
    { "name": "heart", "encoding": "heart.v1", "recordBytes": 12, "count": 2500, "offset": 288000, "length": 30000 },
    { "name": "accel", "encoding": "accel.v1", "recordBytes": 8, "count": 360000, "offset": 318000, "length": 2880000 }
  ]
}
```

`meta` is **additive-only**: a reader must tolerate keys it does not know (`JSONDecoder` does),
and a writer must never remove one without bumping `CONTAINER_VERSION`. A stream whose
`encoding` tag the reader does not recognise is **skipped, not fatal** — that is the promise
that lets a future watch add a fourth stream without breaking every phone in the field.

`meta.utcOffsetS` is the offset the watch was wearing at start, DST included. It is rung 1 of
the UTC-offset ladder (`SessionIngestor.resolveUtcOffset`, docs/algorithms.md): *the recording
said so itself*. A watch session therefore never falls through to the longitude guess a GPX has
to use, and every surface may state its clock as fact.

`meta.utcOffsetKnown` (optional, added with ADR-017) is the escape hatch for a **second writer**
of this format: `HealthImport`, which maps a workout recorded with Apple's own Workout app and
read back out of Health into the same container. Such a workout usually carries no
`HKMetadataKeyTimeZone` at all, and a device-zone guess handed over wearing rung 1's provenance
would license every surface to state a clock the app does not know. **Absent means true** — every
container the watch app writes, now and later, omits it — and `false` means *ignore
`utcOffsetS`*: `WatchSessionParser` claims nothing and the ladder answers, usually with the
longitude rung. Nothing else about the format changes for that writer: `meta.producer` says who
filled it in (`"CleanJibe iOS 0.14.0 (Apple Health)"`), the `accel` stream is empty, and
`TrackFormat.watch` keeps naming a *packed track layout* rather than a device.

## Record encodings

### `track.v1` — 40 bytes, nominally 1 Hz

| offset | type | field | notes |
|---|---|---|---|
| 0 | f64 | `t` | seconds from session start; the clock every stream shares |
| 8 | f64 | `lat` | degrees |
| 16 | f64 | `lon` | degrees |
| 24 | f32 | `speedMps` | `CLLocation.speed` — **Doppler**, see "Source class" |
| 28 | f32 | `horizontalAccuracyM` | `CLLocation.horizontalAccuracy` |
| 32 | f32 | `altitudeM` | |
| 36 | u32 | `flags` | bit 0 = `gapBefore`; bits 1–31 reserved, must be written 0 |

A missing float is **NaN**, never a magic number: NaN is the one value that cannot be mistaken
for a reading and survives any arithmetic a careless reader does to it. CoreLocation's own
convention — a *negative* speed or accuracy means "no reading" — is normalised away by the
encoder, so a `-1 m/s` can never reach the analysis engine as a real number.

`flags` bit 0 is the recorder saying **it stopped here**: the rider paused, or the workout was
interrupted. It is the same claim a GPX `<trkseg>` boundary makes and it reaches `TrackCleaner`
by the same door (`RecordSample.gapBefore`), which ORs it into the dt-aware gap rule.

### `heart.v1` — 12 bytes, irregular (~every 1–5 s)

| offset | type | field |
|---|---|---|
| 0 | f64 | `t` |
| 8 | f32 | `bpm` |

Heart rate gets its own stream rather than a column in the track because the sensor reports
when it has something, not on the second. `WatchSessionParser` joins it onto the 1 Hz records
by nearest reading within **5 s**; beyond that the record simply has no heart rate, because a
stale reading stretched to cover a gap is a worse answer than an honest absence.

### `accel.v1` — 8 bytes, 50 Hz

| offset | type | field |
|---|---|---|
| 0 | f32 | `t` |
| 4 | f32 | `magnitudeG` |

**Magnitude only, gravity included** — a resting wrist reads about 1.0 g. Same signal the
Garmin app records (`AccelSample`), and what `PumpAnalyzer` expects: the detector band-passes
0.5–2.5 Hz, which removes the DC gravity term as a matter of arithmetic, and it is
orientation-free by construction because a wingfoiler's wrist rotates constantly
(docs/algorithms.md "Pumping"). Three axes would triple the largest stream in the file to carry
information nothing reads.

**50 Hz** because `PumpConfig.resampleHz` is 25: exactly 2×, so the box-average gets two
samples a bin, and the 2.5 Hz band edge sits well clear of Nyquist. Sampling at 25 Hz would
put it uncomfortably close.

`t` is **single-precision here and nowhere else**, because this is the stream that is 50× the
others and the only one where the width shows up in the transfer. The cost is bounded and
known: near t = 7 200 s consecutive `Float` values are 2⁻¹⁰ s ≈ 0.49 ms apart, against a 20 ms
sampling interval. Rounding is monotone, so the stream stays sorted, and `PumpAnalyzer` box-
averages onto a 25 Hz grid anyway — two samples that collided land in one bin and are averaged,
which is what that code does with every bin regardless.

## Clocks

Two clocks, anchored at the same instant:

- **track** and **heart** are on the wall clock — `location.timestamp` and the HealthKit
  statistics interval end, both minus `startDate`.
- **accel** is on the device's monotonic uptime clock, rebased by subtracting the uptime
  captured at start.

They agree at `t = 0` and can only diverge by whatever NTP steps the watch mid-session, which
is milliseconds against a 0.4 s pump refractory. The accelerometer gets the monotonic clock
because it is the stream where a wall-clock step would corrupt a *rate*, and rate is the whole
measurement.

## Source class — (b), certified

A watch session is **input class (b)** and its speed records **certify**. Both halves are
deliberate, and the rule they are read by is unchanged: `LibraryQueries.certified` is
`sourceClass != "c"`, and `sourceClass` is derived from `SourceCapabilities` exactly as before.

`hasSpeed = true`, and this is **not** the GPX situation. docs/presentation.md's rule is about
*provenance*: "a speed record is only trustworthy when it came off the receiver's Doppler
channel". `CLLocation.speed` is exactly that — the GNSS chip's own Doppler solution, reported
per fix, not differentiated from the positions afterwards. A GPX is class (c) because the file
cannot prove where its speed came from; this container can, because we write it, and it writes
the speed channel and the positions as two separate things.

It is **not** a claim of GP3S submission validity. The app has never made that claim for any
source — docs/plan.md's "GP3S-approved" is a property of a *receiver* (1 Hz, All-Systems +
Multiband, no SatIQ), and Apple publishes no equivalent spec. `certified` has only ever meant
"the speed was measured, not inferred", and by that meaning this qualifies.

`hasDevFields = false`, and that is honest too. The MVP watch app **records; it does not
detect**. There is no on-wrist foil state, no flight index, no turn marker and no watch
summary, so there is nothing to claim class (a) with — and `WatchSummary` comes back empty.

**No new letter.** Class (d) is already reserved for the Garmin data-field variant
(docs/decisions.md ADR-009), so a watch class would be (e), and it would have to be taught to
six Swift switch sites, `web/js/render.js`'s letter dictionary, `HelpCatalog`'s three-case
prose and `lab/parse.py` — for a distinction the certification rule does not actually make.
Provenance is not lost by declining: `session.importSource` carries `applewatch`, which is what
the session note and the HealthKit guard read.

### But the capabilities carry more than the letter does

A watch session has class (b)'s Doppler **and** class (a)'s accelerometer. So `PumpTrack`,
`TakeoffAnalyzer` and the accel-corroborated flight-end and turn rules all run — analysis a
native Garmin FIT cannot have. This is the architecture working as designed: *the pipeline
degrades on capabilities, not on formats* (docs/plan.md §3.3).

It is also why `SessionDisplay.sourceClassNote` consults `importSource` as well as the class.
The standard class-(b) sentence is "Standard Garmin recording — everything except pump and
takeoff effort", and printing that over a session that visibly has a pump chart would read as a
bug. A watch session gets its own line instead.

## Capability mapping

| `SourceCapabilities` | value | from |
|---|---|---|
| `hasSpeed` | true | any record with a non-NaN `speedMps` |
| `hasPosition` | true | the track stream exists |
| `hasHR` | stream non-empty | |
| `hasAccel` | stream non-empty | ⇒ pump + takeoff analysis run |
| `hasDevFields` | **false** | ⇒ `sourceClass == "b"` |
| `hasWatchLaps` | false | no laps in the MVP |
| `sampleRateHz` | median dt⁻¹ ≈ 1 | median, so one pause does not report 0.2 Hz |
| `sport` | `"surfingSports"` | the HealthKit type the workout was really filed under |
| `discipline` | `"wingfoil"` | authoritative — this app records one thing |

`discipline` is also what gets a watch session past `SessionIngestor.isWatersport`, which a GPX
can never pass. `distanceM` is left **nil** on every record: the watch carries no odometer, and
a second, worse distance in the same column would only ever disagree with the engine's own.

## HealthKit

The workout is saved on the **watch**, live, as `HKWorkoutActivityType.surfingSports` with
`.outdoor` location — the same choice `ios/WingFoil/App/HealthWriter.swift` already made, for
the same reasons (HealthKit has no wingfoil type; `.surfingSports` is board-riding rather than
boat-sailing, is what Apple's own watchOS Surfing workout uses, and renders with the surf icon).
The two had to agree, or a rider's Health timeline would name the same sport two ways.

Because the watch saves it, **the phone must not save it again**:
`SessionStore.writeNewSessionsToHealth` skips rows whose `importSource` names `applewatch`. The
watch's copy has the live heart-rate samples and the ring credit that an after-the-fact
`HKWorkoutBuilder` stub cannot give, and nothing would collapse the duplicate —
`HKMetadataKeyExternalUUID` carries the watch's session id on one and the library's row id on
the other.

## Transfer and dedupe

`WCSession.transferFile`, and no retry logic of our own. The system's queue already survives
the watch going out of range, the phone being off, both apps being killed and a night on the
charger; anything written on top of it would be a worse version of it, and it would be the
version that loses a session when the phone is in a drybag on the beach.

On the phone, `WatchSessionReceiver` copies the file out of the delivery location
**synchronously** (it is deleted when the delegate returns, and iOS may have launched the app
in the background purely to take it) into `Application Support/WatchInbox/`. The import sweeps
that directory at launch and on arrival, tagging `ImportSource.appleWatch`, and deletes each
file only *after* `importFiles` returns.

Dedupe is the library's existing rule and there is no second one: start within ±60 s **and**
duration within ±60 s (`SessionIngestor.duplicate`). That is what makes double-queuing a
transfer harmless, which is what lets the recovery paths be generous.

## Crash recovery

`meta.json` is written into the recording directory at **start**, not at stop. watchOS kills
apps for memory, batteries go flat, and a rider who spent two hours on the water should not
lose them to either. On the next launch `SessionRecorder.recoverInterruptedSessions` finds the
directory, derives the duration from how much of `track.bin` was written, assembles a container
and puts it in the outbox; a single sweep then queues it.

The decoder is fail-soft in exactly one direction, matching the FIT and GPX parsers: a
*structurally* broken file throws, because a half-read session would be a lie with a map on it;
a stream **shorter than the header promised** is read as far as it goes, because a transfer
that was cut off still contains real minutes of real riding. `assemble` derives stream counts
from byte lengths, so a record that was half-written when the app died loses its ragged tail
rather than being promised in the header.

## Not in the MVP

Deliberately deferred, and each would change this contract:

- **On-wrist detection** (flight, turn, records, pump counting). Phase 2. It would add a
  `WatchSummary`-shaped block to `meta` and, if it wrote developer-field-equivalents per
  record, a fourth stream — at which point the source-class question genuinely reopens.
- **Laps.** `hasWatchLaps` stays false; there is no lap stream.
- **Barometer.** `OffFoilEvidence` uses submersion evidence on Garmin; the watch has the
  sensor and does not record it yet. It would be a fifth stream.
- **Complications, widgets, standalone operation.** `WKRunsIndependentlyOfCompanionApp` is
  false: the recording has nowhere to go without the phone.
- **Sharing a `.cjw`.** `SessionStore.shareableFIT` refuses any non-FIT original, so a watch
  session cannot be shared as a file — the same degradation a GPX already has.
