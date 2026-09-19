# Direct transfer — a Garmin session to the iPhone without intervals.icu or Strava

Research spike for [issue #14](https://github.com/JanLahmann/WingFoil/issues/14). Nothing is
built. Numbers are measured in this repo, read out of Connect IQ SDK 9.2 on disk, or linked.

## 1 · What the link carries today, and what a recording weighs

The watch sends a **card**: 21 integer keys, **192 B** measured, against
`PhoneLink.BUDGET_BYTES` = 1024 (ADR-013). The other way carries the map mask,
`WatchMapMask.maxBytes` = **8 000 B**. That is the whole channel.

A recording is three orders bigger. Measured on this app's own FITs (`fixtures/sessions/ciq/`,
`fitdecode`, raw chunk bytes):

| stream | 1 h 57 m session (7 029 s) | per second | share |
|---|---|---|---|
| `accelerometer_data` (25 samples × 4 msg/s = 100 Hz) | 10 035 984 B | 1 428 B | 95.8 % |
| `record` (1 Hz, 4 dev fields) | 235 720 B | 33.5 B | 2.2 % |
| `gps_metadata` + `unknown_534` + `unknown_233` | 179 855 B | 25.6 B | 1.7 % |
| **whole FIT** | **10 480 917 B** | 1 491 B | |
| **FIT minus the wrist stream** | **≈ 445 000 B** | 63 B | |

The wrist stream is already a switch — `accelLogging`, default **false** in `properties.xml` —
so most riders' FITs are the 445 KB shape. And we need not ship FIT at all: `RawTrack.Sample`
takes lat, lon, speed, altitude, heart rate and the four dev fields, and nothing else reaches
the engine.

| our own wire format, 2 h at 1 Hz | B/s | 2 h |
|---|---|---|
| fixed (lat/lon int32, speed + alt uint16, HR uint8, dev pack uint16) | 15 | 108 000 B |
| delta-coded, int16 position deltas, keyframe every 60 s | **9** | **≈ 67 000 B (65 KB)** |
| wrist, 25 Hz magnitude only (what `PumpDetector` eats) | 50 | 360 000 B |
| wrist, 25 Hz three axes int16 | 150 | 1 080 000 B |

## 2 · The five options

Platform facts first.

| fact | source |
|---|---|
| **`transmit()` has no documented size limit.** The cap is heap: the payload lives as a Monkey C object and is serialized at ~2×. Errors: `BLE_QUEUE_FULL` −101, `BLE_REQUEST_TOO_LARGE` −102, `BLE_CONNECTION_UNAVAILABLE` −104 | [Communications](https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html) |
| **Throughput is 0.5–1 KB/s**, 1–2 s per message, **at most 3 transfers in flight** — wait for `onComplete` or take −101 | Garmin staff, [thread 2444](https://forums.garmin.com/developer/connect-iq/f/discussion/2444/communications-transmit-queue-full), [thread 1675](https://forums.garmin.com/developer/connect-iq/f/discussion/1675/makejsonrequest-response-size-limit) |
| **ByteArray only since API 6.0.0**: fenix 8 / fr970 / enduro 3 yes; fenix 7 (5.2.0) and fenix 5 Plus (3.3.3) no | same page; `ConnectIQ/Devices/*/compiler.json` |
| watch-app heap: fenix 5 Plus **1 310 720 B**, fenix 8 and the whole 5.x/6.x fleet **786 432 B**. fenix 8's `:extendedCode` adds 16 MB of *code* paging, not heap | same files, [System 8](https://forums.garmin.com/developer/connect-iq/b/news-announcements/posts/system-8-beta-now-available) |
| `Application.Storage`: **8 KB per value, ~100–128 KB per app**; the API page says 32 KB per value and "varies between devices" — design to the smaller | [Persisting Data](https://developer.garmin.com/connect-iq/core-topics/persisting-data/) |
| **A CIQ app cannot read the FIT it recorded.** Garmin staff: *"There is no way to get access to the FIT files stored on the device from ConnectIQ."* `PersistedContent` is courses and workouts, `FitContributor` is write-only, there is no `File` module | [forum 4697](https://forums.garmin.com/developer/connect-iq/f/discussion/4697/upload-workout-fit-files-with-connect-iq-possible) |
| `BluetoothLowEnergy` is **central-only**, 20-byte MTU, no long reads or writes ⇒ 90–120 B/s. Garmin: *"the phone must be the end that advertises"*; Apple hides a backgrounded iPhone's UUIDs in a proprietary overflow area | [Characteristic](https://developer.garmin.com/connect-iq/api-docs/Toybox/BluetoothLowEnergy/Characteristic.html), [forum 235496](https://forums.garmin.com/developer/connect-iq/f/discussion/235496/send-live-activity-data-to-a-smartphone-through-ble) |
| `makeWebRequest` takes a URL-encoded or JSON **Dictionary** only — no byte stream | [HTTPS](https://developer.garmin.com/connect-iq/core-topics/https/) |
| On iOS the companion app owns the BLE link; GCM only discovers and installs. Background needs *Uses Bluetooth LE accessories* + a `stateRestorationIdentifier`, and Garmin warns that backgrounded apps get *"extremely low BLE priority"* | [iOS SDK](https://developer.garmin.com/connect-iq/core-topics/mobile-sdk-for-ios/) |
| Garmin Connect's **iOS app exports no file** — its share sheet gives an image or a link. *Export Original* (a zip holding the .fit) is a **web** route; the GDPR export is a whole-account zip with no committed turnaround | [Strava](https://support.strava.com/en-us/articles/15402167-exporting-files-from-garmin-connect), [export data](https://www.garmin.com/en-US/account/datamanagement/exportdata/) |
| The Activity API serves FIT, but the Developer Program is **business-only, with its application form down through 2026**, and §5.2(e) forbids deriving income from the API | [FAQ](https://developer.garmin.com/gc-developer-program/program-faq/), [the5krunner](https://the5krunner.com/2026/09/14/garmin-developer-api-access-paused/); ADR-003 |

At 0.5–1 KB/s: the whole FIT is **3–6 hours**, the FIT without the wrist **7–15 min**, our
delta stream **65–130 s**. But the delta stream is only **9 B/s while riding** — about 1–2 %
of the link. That asymmetry is the whole answer.

| | option | feasible | cost of moving 2 h | failure modes | what the rider sees |
|---|---|---|---|---|---|
| **a** | **stream while riding**, flush the rest on save | yes | 9 B/s live, ~1–2 % duty; the tail is seconds | out of range an hour ⇒ ~32 KB held on a 768 KB watch; app killed loses the unsent tail | it is on the phone before he leaves the water |
| **b** | **send after save** from kept samples | yes, needs a store the app lacks | one 65 KB burst = **65–130 s** | Storage is 8 KB/value and ~100 KB total, so a 3 h ride overflows; nothing survives a crash before save | a 1–2 minute wait, then done |
| **c** | **pull the FIT from Garmin Connect** | no | — | no open API; no export in the iOS app; the web route and the GDPR zip are both manual | the chain #14 wants removed |
| **d** | **watch writes FIT, phone reads it over USB** | no | — | fenix 7/8 offer MTP only, never mass storage; iOS Files mounts neither without MFi | nothing |
| **e** | **raw BLE from the CIQ app** | no | 90–120 B/s ⇒ hours | central-only, and a backgrounded iPhone cannot be discovered | nothing |

**Ranking: a > b > c > d = e.** (a) and (b) share one transport and one wire format; (a) only
moves *when* the bytes go, and it is the only option the wrist stream could ride on — 50 B/s
live is 5–10 % of the link, 360 KB as a burst is 6–12 minutes.

## 3 · Recommendation

**Build (a), with (b) as its tail.** One ring buffer, one chunk encoder, one receiver. The
watch flushes a chunk while the link is up and flushes the rest on save; if the phone was
never in range, the same buffer is the after-save send. No second mechanism.

**On the watch.** Acknowledged chunks are freed, so a few KB stay resident. The binding heap
is the **fenix 8's 768 KB**, not the 5 Plus's 1.25 MB — the newer watch is the smaller one.
The 5 Plus has the other problem: **CIQ 3.3.3 cannot transmit a ByteArray**, so it sends
`Array<Number>`, four payload bytes per 32-bit Number, which `PhoneLink.estimateBytes` prices
at 5 wire bytes. Ship the 6.0.2 watches first. Three transmits may be in flight, so the flush
loop gates on `onComplete`; and — [SetSync](https://github.com/domingoruizb/setsync) learned
this in the field — a transmit success only means the phone's *stack* took it, so chunks need
an app-level ACK and `System.exit()` must block until the last settles. `PhoneLink.Radio`, the
pending slot (now a queue), `pollLink` and the two fenix 7 traps are reused whole.

**On the phone.** `ConnectIQCompanionLink` gains a chunk assembler writing a `.cjr` container
into an inbox directory, exactly as `WatchSessionReceiver` already does for the Apple Watch's
`.cjw`. New: `UIBackgroundModes: bluetooth-central` (today `ios/project.yml` has only `fetch`)
and a `stateRestorationIdentifier` on `ConnectIQ.initialize`; both Bluetooth usage strings say
*session summary* and must say what now crosses. One trap: *"multiple companion apps should
never register to receive messages from the same app"* — a tester holding the dev and beta
apps at once gets undefined delivery. **Dedupe is already solved**: the container carries the
card's key, start epoch plus elapsed seconds, so it takes the same `SessionIngestor` ±60 s
rule and the intervals.icu copy replaces the row in place (ADR-013).

**What the rider sees.** Settings → Garmin watch, one switch:

> **Send sessions straight to the phone**
> Your session arrives while you are still on the beach. No account needed.

**Which class.** The stream carries Doppler speed as its own channel, the positions and the
four developer fields: class A minus the wrist. So **class B at first, class A once the 25 Hz
magnitudes ride along**. No new letter (pattern L).

## 4 · The first experiment

**Transmit the last five minutes and time it.** Five minutes of delta stream is 2 700 B — one
message, no assembler, no container, nothing rider-facing. A hidden BACK-menu item on the dev
build encodes the tail and calls the existing `PhoneLink.Radio`; log `onComplete` against
`System.getTimer()`. Measure on Jan's fenix 8 first, a fenix 5 Plus second:

| | why |
|---|---|
| wall clock for 2 700 B, ten runs, watch on the wrist, phone in a pocket | says whether 0.5–1 KB/s holds here; 65 KB is 65–130 s if it does |
| the same at 1, 4, 8, 16 KB, and where −102 starts | finds the real per-message ceiling, which is undocumented and is heap, not size |
| two sends back to back, then three, watching for −101 | confirms the three-in-flight gate |
| the same transfer backgrounded, and again after force-quit | the one thing nobody has answered publicly in seven years |
| watch battery over 2 h with a flush every 90 s vs. the card alone | the cost the rider pays |
| fenix 5 Plus: the `Array<Number>` encoder at the same payload | confirms or kills the pre-6.0.0 fleet |

If 2 700 B lands in under 5 s, (a) is a transfer measured in seconds and worth building. If
backgrounded delivery never happens, (a) still works — the rider has the watch app open while
he rides — and (b) becomes a 1–2 minute wait he watches.
