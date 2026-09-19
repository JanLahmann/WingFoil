# Direct transfer — a Garmin session to the iPhone without intervals.icu or Strava

Research spike for [issue #14](https://github.com/JanLahmann/WingFoil/issues/14). Nothing is
built. Second pass. Jan's verdict on the first: *"streaming while riding is not feasible. The
phone will not be in the water, just the watch. The transfer has to happen when back on
land."* So the constraint is fixed and the question is narrower: **the rider walks up the
beach, the phone is in the car or the drybag, and the session has to land.** Numbers are
measured here, read out of Connect IQ SDK 9.2 on disk, or linked.

## 1 · What a recording weighs, and what the app already spends

The link carries a **card** today: 21 integer keys, **192 B** measured, against
`PhoneLink.BUDGET_BYTES` = 1024 (ADR-013). The other way carries the map mask,
`WatchMapMask.maxBytes` = **8 000 B**.

Measured on this app's own FITs (`fixtures/sessions/ciq/`, `fitdecode`, raw chunk bytes):

| stream | 1 h 57 m session (7 029 s) | per second |
|---|---|---|
| `accelerometer_data` (25 samples × 4 msg/s) | 10 035 984 B | 1 428 B |
| `record` (1 Hz, 4 dev fields) | 235 720 B | 33.5 B |
| `gps_metadata` + `unknown_534` + `unknown_233` | 179 855 B | 25.6 B |
| **whole FIT** | **10 480 917 B** | 1 491 B |
| **FIT minus the wrist stream** | **≈ 445 000 B** | 63 B |

We need not ship FIT. `RawTrack.Sample` takes lat, lon, speed, altitude, heart rate and the
four dev fields, and nothing else reaches the engine:

| our own wire format, 1 Hz | B/s | 2 h | 3 h |
|---|---|---|---|
| fixed (lat/lon int32, speed + alt uint16, HR uint8, dev pack uint16) | 15 | 108 000 B | 162 000 B |
| **delta-coded, int16 deltas, keyframe every 60 s** | **9** | **65 000 B** | **97 000 B** |
| a 10 s spine only (delta lat/lon, speed, flags) | 0.6 | 4 320 B | 6 480 B |
| wrist, 25 Hz magnitude only (what `PumpDetector` eats) | 50 | 360 000 B | 540 000 B |

**New this pass — the app's real footprint, built here** (`monkeyc -r -O 3z`, release jungle,
SDK 9.2, against each device's `watchApp` `memoryLimit` in `ConnectIQ/Devices/*/compiler.json`):

| device | code+resources | app memory | free for data |
|---|---|---|---|
| **fr255** (the binding one) | **104 892 B** | 524 288 B | **419 396 B** |
| fenix 5 Plus | 125 244 B | 1 310 720 B | 1 185 476 B |
| fenix 8 47 mm | 142 860 B | 786 432 B | 643 572 B |

Live data today is an estimate, not a simulator reading: the 2 × 128 track floats, the
256-slot `SessionHistory`, a 120 × 120 `BufferedBitmap`, the detectors' rings and one accel
batch come to roughly **40–60 KB**. So **~360 KB is free on the worst watch we ship to**, and
a 65 KB buffer is 18 % of it. Memory is not what decides this.

**The fleet is.** `manifest.xml` ships **42 products** and **30 of them are pre-6.0.0** —
fenix 5 Plus (3.3.3), the whole fenix 7 / epix 2 / fr255 / fr265 / venu / MARQ 2 family (5.x).
`transmit()` accepts a `ByteArray` only since 6.0.0. The fallback is not an edge case; it is
71 % of the watches. Costed in §5.

## 2 · Platform facts

| fact | source |
|---|---|
| `Application.Storage`: **"Keys and values are limited to 8 KB each, and a total of 128 KB of storage is available."** The API page says 32 KB per value and "varies between devices" — design to 8 KB / 128 KB | SDK 9.2 `doc/docs/Core_Topics/Persisting_Data.html`, [Persisting Data](https://developer.garmin.com/connect-iq/core-topics/persisting-data/) |
| Storage is **writable from a background service since API 3.2.0**; the foreground gets `AppBase.onStorageChanged()` | same page |
| **`Toybox.Communications` runs in a Background context.** Its runtime-context list is *Audio Content Provider, **Background**, Data Field, Glance, Watch App, Widget*, and `transmit()` carries no narrower list. **A background service can transmit to the companion app** | SDK `doc/Toybox/Communications.html`, [Communications](https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html), [forum 6168](https://forums.garmin.com/developer/connect-iq/f/discussion/6168/background-module---is-companion-app-communication-supported-in-the-background) |
| **`Background.registerForPhoneAppMessageEvent()` (3.2.0) wakes the service when the phone sends a message** | SDK `doc/docs/Core_Topics/Backgrounding.html` |
| A background service is **killed if it does not exit within 30 s**, and sooner to free memory for the foreground | same |
| Background pool: **65 536 B** on every 5.x/6.x product we ship to, **32 768 B** on fenix 5 Plus. Code counts against it, hence `(:background)` | `compiler.json` |
| Temporal events cannot recur faster than **5 minutes**; `Background.exit(data)` throws above **≈ 8 KB**; `Background.requestApplicationWake(msg)` shows a dialog asking the rider to open the app | `Background.html` |
| `SECURE_CONNECTION_REQUIRED` = **−1001**. `makeWebRequest` takes a **Dictionary**, never a byte stream | `Communications.html`, [HTTPS](https://developer.garmin.com/connect-iq/core-topics/https/) |
| Throughput **0.5–1 KB/s**, at most **3 transfers in flight** (−101 `BLE_QUEUE_FULL`, −102 `BLE_REQUEST_TOO_LARGE`, often a disguised out-of-memory) | [thread 2444](https://forums.garmin.com/developer/connect-iq/f/discussion/2444/communications-transmit-queue-full) |
| **No file leaves a CIQ app.** No `File` module; `PersistedContent` is inbound; `FitContributor` write-only. *"There is no way to get access to the FIT files stored on the device from ConnectIQ."* | [forum 4697](https://forums.garmin.com/developer/connect-iq/f/discussion/4697/upload-workout-fit-files-with-connect-iq-possible) |

## 3 · The options

### A · Hold the compact stream, send it on land — and let the phone wake the watch

The first pass wrote off the after-save send because "the send needs the app open". **That is
wrong**, and the correction is the whole of this pass:

> The rider walks up the beach with the watch asleep and the app closed. He opens CleanJibe on
> the phone. The phone sends one small message to the watch app id. The watch's background
> service wakes, reads page 0 out of Storage, transmits it, exits inside 30 s. The phone acks
> and asks for page 1. Nine wakes later the session is on the phone. Nobody touched the watch.

| | number |
|---|---|
| RAM while riding | 12 pre-allocated 8 192 B pages = **98 304 B**, never grown, never concatenated (a `ByteArray` `+` doubles peak) — 23 % of fr255's measured 419 KB free |
| Storage at save | 12 page keys + a header ≈ **100 KB** against 128 KB, minus MapSnapshot's 2 × 8 KB and the card. It fits, with nothing to spare |
| a 3 h session | 97 KB = 12 pages. **Halve the cadence in place** when page 12 opens: 1 Hz for the recent hour, 0.5 Hz before — what `SessionHistory` already does to its slots. Never drop HR, it is one byte a second and the cost tracker wants it |
| on the wire | 65 KB at 0.5–1 KB/s = **65–130 s**, or 3–5 back-to-back wakes |
| per wake | 30 s × 1 KB/s ≈ 30 KB ceiling; one 8 KB page is comfortable, three is the in-flight cap |
| class | Doppler speed as its own channel, the positions, the four dev fields, and pump strokes and takeoffs as the watch's **own** counts (`PumpDetector` runs on the wrist). **Class a**, with the raw 25 Hz stream absent rather than the results. Pattern **L**: no new letter, a column at most |
| dedupe | the header carries start epoch + elapsed, so it takes the existing `SessionIngestor` ±60 s rule; the intervals.icu FIT later replaces the row in place (ADR-013) |

Failure modes, each with an answer. App closed before the phone is near: **Storage keeps it**.
Service killed at 30 s: **one page per wake, the phone asks for the next**. Two wakes fail:
**`requestApplicationWake("Send your session?")`** — one tap opens the full app with 400 KB of
heap and no 30 s clock. A transmit "succeeds" but never arrives: **an app-level ack per page**,
the lesson [SetSync](https://github.com/domingoruizb/setsync) learned in the field. fenix
5 Plus's 32 KB background pool: **4 KB pages there**, or foreground only on that family.

### B · The watch posts HTTP to the phone

- **https is required** (−1001). Community consensus: **`http://` is tolerated for loopback
  only**; anything else needs a certificate the *phone* trusts
  ([420764](https://forums.garmin.com/developer/connect-iq/f/discussion/420764/guidance-on-connect-iq-networking-http-vs-https-and-certificate-handling)).
  No Garmin statement either way.
- iOS **ATS does not apply to an IP-address literal**, so `http://127.0.0.1:8080` from GCM's
  own `URLSession` is not blocked by Apple. Any blocker is Garmin's.
- A **LAN** target works only with a root CA installed and fully trusted on the iPhone
  ([291012](https://forums.garmin.com/developer/connect-iq/f/discussion/291012/makewebrequest-for-internal-networks)).
  An iOS app cannot install one. Dead for riders. The watch's own **Wi-Fi** is reachable only
  in sync mode (`startSync`/`SyncDelegate`) and `checkWifiConnection()` tests for an
  *internet-enabled* access point, so the hotspot idea does not escape the cert problem either.
- **The bytes still cross the same BLE pipe to GCM at 0.5–1 KB/s.** B buys no speed. It works
  from a background service — but so does A now. iOS would need an `NWListener`, alive in the
  foreground or ~30 s of a background task.

**No advantage over A on the axis that matters, and one more moving part.** One hour as an
experiment (§6), not a build.

### C · Garmin Connect → Apple Health

**Dead, and now sourced.** Garmin's own FAQ: *"Workouts (activities uploaded to Garmin
Connect — associated GPS track are **not** written to Apple Health)."* Garmin Connect does not
appear under Health → Workouts → Workout Route Data Sources
([forum 352961](https://forums.garmin.com/apps-software/mobile-apps-web/f/garmin-connect-mobile-ios/352961/garmin-connect-does-not-sync-workout-routes-i-e-gps-data-to-apple-health-app));
HealthFit and RunGap exist *because* of this, and RunGap logs into the Garmin account rather
than reading HealthKit. The write also needs GCM in the **foreground**, and the
windsurf → `HKWorkoutActivityType` mapping is undocumented. Re-confirms **ADR-003**, costs no
work. `HealthImporter` stays the Apple Watch's own recordings.

### D · A relay we host

The only option that could ever carry the wrist stream at speed: a real domain is the only way
to a certificate GCM trusts, and that is the only way to the watch's Wi-Fi. A signed-URL
endpoint and an object store, delete after pickup, ~€5/month.

The real cost is not money. `docs/channels.md` and the privacy page say the app talks to
intervals.icu, Strava and Apple Health, and to no CleanJibe server. One relay changes: the App
Store privacy labels (a track is location data), a privacy-page section, a retention rule
written down and honoured, a store-review answer, and a single point of failure a rider cannot
route around. **Not for the release promise.** Name it only if the wrist stream becomes the
thing a rider waits for.

### E · Everything else

| idea | verdict |
|---|---|
| **The card grows a spine** — a 10 s track, 720 points × 6 B = **4 320 B**, one message, ~5 s on the link | **Take it.** `transmit` has no documented size cap; 1024 B is *our* budget. Every session then arrives with a map even when the full stream never goes. A subset of A's encoder, shippable on its own |
| `Communications.openWebPage(url)` | a `cleanjibe://` scheme would let the *watch* launch the phone app. UNVERIFIED whether GCM honours a custom scheme |
| Garmin **Share** (device to device, 3 m, PIN) | courses, workouts, saved locations. **Not activities** ([manual](https://www8.garmin.com/manuals/webhelp/GUID-25E3235D-44D2-4384-A591-DD1D71BEBCB1/EN-US/GUID-B822FF6C-0DAB-45EB-95CC-BB9023E3961B.html)) |
| Garmin Messenger file transfer | no evidence it exists. UNCONFIRMED |
| Garmin Connect **iOS** export / share sheet | still none in 2025–2026 release notes; *Export Original* stays a web route |
| FIT dev-field tricks, `PersistedContent`, "Files"; USB/MTP; raw BLE | unchanged: inbound or write-only; MTP is not mountable by iOS without MFi; BLE central-only gives 90–120 B/s |

## 4 · Ranking, and the build

**A > E-spine > B > D > C = the file routes.** A and the spine share one encoder, so the spine
is A's first commit, not a rival.

**On the watch.** Twelve pre-allocated pages, filled by the same 1 Hz `onPosition` tick that
already feeds the engine. At save: pages to Storage as `cjs0`…`cjsB`, plus `cjsH` (schema,
start epoch, elapsed, page count, bytes in the last page, cadence, and the card itself, so the
header alone is a usable session). State machine beside the pending card:
`IDLE → OFFER(header) → SENDING(page i) → ACK → … → DONE → clear`, gated on `onComplete`
**and** the phone's ack, three in flight at most. `(:background)` goes on the app class, the
service delegate, `PhoneLink` and the page reader, and on nothing else, or fenix 5 Plus's
32 KB pool overflows. `registerForPhoneAppMessageEvent()` at app exit. Summary page, BACK menu
→ **Send to phone**, with a percentage and a Retry; `pollLink` already fires on the connected
edge and gets the same call.

**On the phone.** `ConnectIQCompanionLink` gains a page assembler writing a `.cjr` container
into the same `WatchInbox` directory `WatchSessionReceiver` already owns, then the existing
ingest path. After the header it sends `{"go": n}` per page — that pull drives the background
wakes. `UIBackgroundModes: bluetooth-central` and a `stateRestorationIdentifier` are new
(`ios/project.yml` has only `fetch`), and both Bluetooth usage strings must say what now
crosses. Trap: two companion apps registered for one CIQ app id (a tester holding dev and
beta) gives undefined delivery. Provenance line: **"From your watch, over Bluetooth."**

**What the rider sees** (docs/voice.md, registers 1 and 3):

> Settings → Garmin watch → **Send sessions to the phone**
> *Your session goes straight from the watch. No account needed. Open CleanJibe on the beach.*

Watch: **Send to phone** · **Sending 43%** · **On your phone.** · **No phone. Try again on the
beach.**

**Which channel.** Dev. Rule 2 of `docs/channels.md` holds the Garmin link in dev until the
link has real sessions behind it, and this is that link carrying more. It moves to beta on
rule 1 — ten sessions, two riders, no open report — plus a help topic and a privacy line.

## 5 · The pre-6.0 fallback, costed

30 of 42 products cannot `transmit` a `ByteArray`.

| encoding | wire bytes per 8 192 B page | RAM per page | 65 KB session |
|---|---|---|---|
| `ByteArray` (≥ 6.0.0, 12 products) | 8 192 | 8 192 B | 65–130 s |
| **`Array<Number>`, 2 048 entries** | 10 240 (`estimateBytes` prices a Number at 5 B) | ~8–12 KB | **81–162 s** |
| base64 in a `String` | ~10 900 | ~11 KB | 87–174 s |

**Take `Array<Number>`**: the same expansion as base64 on the wire, less in RAM, no encoder.
The 12-page buffer becomes 100–144 KB, still inside fr255's 419 KB and fenix 5 Plus's 1.18 MB.
The choice is forced only in the **background** service on fenix 5 Plus: 32 768 B total means
a 4 KB page there, or foreground only on that family.

## 6 · The first experiment — *one page, timed, then nine*

A hidden BACK-menu item on the dev build encodes one 8 192 B page from the last session and
calls the existing `PhoneLink.Radio`; log `onComplete` against `System.getTimer()`. Jan's
**fenix 8 47 mm** first, a **fenix 5 Plus** second — the pre-6.0 half of the fleet.

| measure | why | pass |
|---|---|---|
| wall clock for one 8 192 B page, ten runs, watch on the wrist, phone in a pocket | the one unknown that decides everything | median ≤ 20 s |
| 1, 2, 4, 8, 16 KB in one transmit, and where −102 starts | the per-message ceiling is undocumented, and is heap, not size | 8 KB lands on both |
| nine pages back to back with the app open, each acked | the real 65 KB end-to-end time | ≤ 3 min |
| the same driven by `registerForPhoneAppMessageEvent`, app closed | whether the background path exists at all — nobody has published this | one page per wake, exits inside 30 s |
| the background image on fenix 5 Plus after `(:background)` scoping, and `requestApplicationWake` on both watches | 32 768 B is a hard wall; the wake dialog is the fallback | builds, runs, dialog appears |
| a 2 KB POST to `http://127.0.0.1:8080`, phone app foregrounded | option B, answered in an hour | 200, or −1001 and B is closed |
| battery over 2 h recording plus one 65 KB send | the cost the rider pays | ≤ 2 % over the card alone |

If a page lands in under 20 s, A is a two-minute transfer the rider watches finish and it is
worth building. If the background wake never fires, A still works — the rider taps **Send to
phone** on the summary page — and the 4 KB spine in the card covers every session he forgets
to send.
