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

## 2 · The options

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
| **f** | **a relay server** — the watch POSTs, the phone fetches, the relay deletes (§4) | yes | 87 KB of base64 = **87–174 s**, same BLE hop | a server, a changed promise, a 24 h TTL that can eat a session | the same as (a), later |

**Ranking: a > b > f > c > d = e.** (a) and (b) share one transport and one wire format; (a) only
moves *when* the bytes go, and it is the only option the wrist stream could ride on — 50 B/s
live is 5–10 % of the link, 360 KB as a burst is 6–12 minutes.

## 3 · Recommendation

**Build (a), with (b) as its tail.** (f) is feasible and is ranked above the three that are not,
but it does not change the hop that costs the time — §4 does the arithmetic. One ring buffer,
one chunk encoder, one receiver. The
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

## 4 · D in detail — the relay

Issue #14 calls it **D**; this file's table spends `d` on USB, so it enters as **f**: an
endpoint the watch POSTs to, the phone fetches from, the relay deletes on pickup.

### The transport is the same BLE hop, plus a third

`makeWebRequest` appears **nowhere** in `garmin/source` today — `Communications.transmit` is the
only radio call the app makes. The `Communications` permission is already in both manifests, so
no new permission is needed.

What SDK 9.2's `api.debug.xml` allows:

| | |
|---|---|
| request body | `parameters` is a **Dictionary**, and the only two request content types that exist are `REQUEST_CONTENT_TYPE_JSON` and `REQUEST_CONTENT_TYPE_URL_ENCODED`. **No byte body.** A blob rides as base64 (`StringUtil.convertEncodedString`, `REPRESENTATION_STRING_BASE64`): 65 KB → **87 KB**, +33 %, ~2× that in heap as a String |
| transport | HTTPS only; the cert must chain to a CA the watch knows (fenix 7 / epix had a TLS-cert bug) |
| per-request ceiling | `BLE_REQUEST_TOO_LARGE` −102 fires on the **outgoing** side and is a RAM error, not a size constant — one developer took −102 on a **140-byte** URL. Undocumented and heap-bound, exactly like `transmit` |
| response ceiling | `NETWORK_RESPONSE_TOO_LARGE` −402, `NETWORK_RESPONSE_OUT_OF_MEMORY` −403; developers hit −402 between **17 and 44 KB**, Garmin's guidance is **~8 KB** of JSON. Our response is only an ack, so this binds nothing |
| from a background service | allowed, but `compiler.json` `appTypes.background.memoryLimit` is **65 536 B** on fenix 8 and fenix 7, **32 768 B** on fenix 5 Plus, for code *and* data — a session cannot fit one wake. `registerForTemporalEvent`: **no closer than 5 minutes**, one event at a time. 8 KB a wake ⇒ 9 wakes ⇒ **45 minutes** per session |

**Throughput: unchanged, then worse.** GCM does the wide-area half over Wi-Fi/LTE for free, but
the watch→phone half is the *same* BLE link at the same **0.5–1 KB/s**. 87 KB of base64 is
**87–174 s** against **65–130 s** for the same session over `transmit()`.

**Wi-Fi: no, not from `makeWebRequest`.** fenix 7/8 have Wi-Fi, but a web request does not raise
it. Garmin staff: *"If you want to use WiFi, you really should be using the
`Communications.SyncDelegate`"*, and the fenix 6x *"should only enable WiFi when a
`Communications::SyncDelegate` is active"*. `Communications.startSync` **exits the app and
relaunches it in sync mode** (@since 3.1.0) — the only door to the watch's own radio, and the
only place (f) beats (a).

### Privacy: the crypto exists, the promise does not survive

**CIQ does have crypto, on the whole fleet.** `Toybox.Cryptography` is @since **3.0.0**, the
app's `minApiLevel` is **3.3.3**: `Cipher` with `CIPHER_AES128`/`CIPHER_AES256`, `MODE_CBC` and
`MODE_CUSTOM` (**no CTR, no GCM, no AEAD**), HMAC with `HASH_SHA256`, ECDH over
secp224r1/secp256r1, and `randomBytes`. AES-256-CBC + HMAC-SHA256, encrypt-then-MAC, is real
end-to-end encryption and builds on every watch the app ships to. (ADR-012's aside that *"CIQ
has no crypto primitives"* is true of an offline unlock check and wrong as a general statement;
narrow it when next touched.)

**No PIN, no keyboard, no QR — the channel is already there.** `PhoneLink.Callbacks` registers
`registerForPhoneAppMessages`, and `applyMessage` already takes the phone→watch push that carries
the 8 000 B map mask. A 32-byte key is **0.4 %** of it: the phone draws it from
`SecRandomCopyBytes`, pushes it once, the watch keeps it in `Storage`. Nothing is typed on round
glass. But that push needs the phone **in BLE range** — the condition the relay was sold as
removing.

**What the relay would hold:** an opaque blob under a 128-bit random id, ≤256 KB, TTL 24 h,
deleted on first GET; no account, no listing, no log beyond the host's edge.

**What the promise becomes.** Today: *"there is no CleanJibe server that your sessions are sent
to — because there is no CleanJibe server at all"* (privacy) and *"Nothing is uploaded, because
there is nowhere to upload it to"* (App Store). Both become false as written, and the replacement
is longer, not shorter — *one server, a locker, encrypted, gone in 24 h* — against the privacy
page's own rule that *"a privacy promise with an unnamed exception in it is not a promise"*.
**GDPR**: a German controller holding pseudonymous location data needs an Art. 30 record, an
Art. 13 notice, a processor contract and a position on edge logs. Hetzner Falkenstein keeps it in
Germany; free Cloudflare Workers carries no EU-residency guarantee.

### Hosting

100 riders × 3 sessions/week × 100 KB = **30 MB/week up**, the same down: ≈ **260 MB and ~2 600
requests a month**.

| | cost | fit | effort |
|---|---|---|---|
| **Cloudflare Workers + KV** | **€0** | free tier: 100 000 reads and **1 000 writes/day** (we need ~43), 1 GB, **25 MB/value**, native TTL. R2 instead of KV if blobs grow: 10 GB-month, zero egress | ~1 day; no EU residency on free |
| **Hetzner CX22, Falkenstein** | **≈ €3.79/month**, 20 TB | German soil; Caddy, ~50 lines, a sweep timer | ~1 day, then **forever**: patches, uptime, certs |
| GitHub Pages | — | **cannot**: static, no POST. cleanjibe.org is on Pages, so this is new infrastructure, not an extension | |

Abuse: 256 KB body cap, unguessable ids, no listing endpoint, ~10 uploads/hour/IP, delete on
pickup.

### The rider, end to end, and where it breaks

Pair once with the watch in range. A background wake every ≥5 min then pushes a page while the
phone is in range with internet; the phone polls when CleanJibe opens — no APNs, so a silent push
would mean a *second* server. Breaks: relay down ⇒ nowhere to put pages; the app not opened
inside 24 h ⇒ the blob expires and the FIT is the only copy, so the relay can never be the only
path; partial pages ⇒ the phone holds fragments and must expire them.

### Against (a), plainly

The relay **does not change the watch→phone hop**. Same BLE, same 0.5–1 KB/s, 33 % more bytes,
through GCM instead of our companion app. Two honest gains: no companion registration (the
*"multiple companion apps"* trap and the BLE-priority worry go away), and CleanJibe need not be
open at pickup. Against that: a server, a rewritten promise, GDPR paperwork, base64
overhead and a 45-minute background clock. **That trade is not worth it.**

**The one scenario where it wins:** the watch on its own Wi-Fi with **no phone present at all** —
the rider's phone is at home and the session is there before he is. That needs `SyncDelegate`,
which exits the app, and nobody has publicly shown a fenix *watch app* POSTing a body that way.

**Ranking: a > b > f > c > d = e.** (f) is feasible where (c), (d) and (e) are not, and sits below
(a) and (b) because it buys nothing on the hop that matters. **Recommendation unchanged: build
(a), with (b) as its tail.** Park (f) behind one experiment.

**The experiment that decides (f)** — one afternoon, before any server exists. A dev-build
BACK-menu item calls `Communications.startSync` with a `SyncDelegate` that POSTs 2 700 B to a
throwaway Worker, **with the phone's Bluetooth off** and the watch on home Wi-Fi. If it lands,
(f) has the one reason to exist that (a) cannot supply, and the design is `POST /b` → `{id}`
(≤256 KB base64, AES-256-CBC + HMAC-SHA256, per-session nonce, key from the PhoneLink push),
`GET /b/{id}` → blob then delete, `DELETE /b/{id}`, nothing else. If it does not, (f) is closed
and this section is its epitaph.

## 5 · The first experiment

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
