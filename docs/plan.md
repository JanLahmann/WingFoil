# WingFoil — Garmin Fenix 8 watch app + iPhone companion: Product & Implementation Plan

## Context

Jan wants a wingfoil tracking system built around his hardware: **Garmin Fenix 8** (records on the water) and **iPhone 17 Pro Max** (pre/post-session analysis). Repo `/Users/majl/GitHub/WingFoil` is empty — greenfield.

Facts from his live data (intervals.icu, native Garmin sync):
- Active wingfoiler, currently at Lake Garda (Nago-Torbole, daily sessions Jul 31–Aug 6 2026); 11 wing/windsurf sessions in the past year; typical session 40–145 min, 8–33 km.
- Records today with the native Fenix 8 **Windsurf** profile (syncs as `Windsurf`) and has tried CIQ apps **FoilMotion** and one auto-named **"Wingfoiling"** — both land downstream as type **`Walk`** (they record a generic/walking FIT sport code).
- **Garmin → intervals.icu auto-sync already active** → ready-made FIT bridge, no Garmin API approval needed.

## Product decisions (user-confirmed)

- **Distribution:** personal first, store-ready architecture. Sideload CIQ app; iOS via Xcode/TestFlight. Personal API keys OK; integrations swappable for a later store release.
- **Metric priorities:** (1) Foil time & runs, (2) Jibe/tack analysis, (3) Speed & GP3S records, (4) **Pumping/takeoff analysis** (user-added differentiator: pumps-to-takeoff, takeoff success rate, pumping effort/efficiency). Jumps explicitly deprioritized (validated: Hoolan disables jump detection for wing by default — too noisy).
- **Sequencing:** both tracks in parallel; analysis engine starts immediately on the 11 existing sessions.

## 1. Competitive landscape (summary)

| App | Platform | Foil time | Transition success % | GP3S speed records | Pump metrics | Phone analysis | Price |
|---|---|---|---|---|---|---|---|
| **Hoolan** (top free pick) | CIQ+AW+phone | – | ✅ (their differentiator) | – | – | ✅ | Free |
| **FoilMotion** (Jan tried) | CIQ+AW+iPhone | ✅ | graded turns (radius/speed/G) | pace splits only | ✅ (pumpfoil-focused) | ✅ 3D "Session Story" | $30/yr |
| **Waterspeed** (390k dl) | iOS/AW+CIQ+web | ✅ +"foiling efficiency" | ✅ | 2s+10s only | – | ✅ best-in-class | $30–60/yr |
| **Surfr** | CIQ+AW+phone | – | – | – | – | ✅ jumps/3D | ~€55/yr |
| **WindsportTracker** | phone (FIT/GPX import) | ✅ (~9.7 km/h threshold) | ✅ + port/starboard | partial | – | ✅ | $27/yr |
| **Foil Sessions** | iPhone/AW | ✅ foil/glide/pump | ✅ w/ angles | – | ✅ (2026) | ✅ | $20/yr |
| **APPro Windsurf** | CIQ | – | – | ✅ full + GP3S-certified auto-sync | – | GC only | paid |
| **JMG Wind-Kite Pro** | CIQ | – | per-jibe score | ✅ incl. Alpha500 | – | GC graphs | $18 once |
| **Pumpfoilytics** | CIQ | ✅ | – | – | ✅ m/stroke (pumpfoil) | GC | free-ish |
| **Garmin native Windsurf** | built-in | – | – | SpeedPro=5×10s only | – | – | – |

Key market facts:
- **No native Garmin wingfoil profile** exists (years-old ignored forum requests). No wingfoil sport code exists in FIT-as-exposed-to-CIQ, Garmin Connect, Strava, or intervals.icu.
- **The "Walk" problem:** CIQ apps recording generic/walking sport land as Walk. Fix: record **`Activity.SPORT_WINDSURFING` (43)** → lands as Windsurf in GC/Strava/intervals.icu; Windsurf is also the profile with the **least Garmin GPS filtering and true Doppler speed** (per Hoolan docs + logiqx).
- **The COROS gap:** COROS ships native live 2s/10s/5×10s/NM/Alpha-500 (co-developed with GP3S); **no Garmin app combines the GP3S metric set with a foil/transition model** (APPro = speed only; Hoolan = foil model only). A dedicated wingfoil ranking site (**gps-wingfoiling.com**) exists; Garmin multiband watches are GP3S-approved (1 s recording, All-Systems+Multiband, no SatIQ).
- Detection prior art: Surf Tracker DF run recipe (entry ≥9 km/h, ≥6 s, peak ≥13 km/h, user-configurable — the shape to copy); Hoolan transition success = held speed through turn; naive heading-delta jibe counters false-positive on bear-aways → wind-axis-aware classification needed; nobody publishes their foil-detection parameters (we will, user-tunable).
- **Pumping:** FoilMotion/Pumpfoilytics do pump metrics for *pumpfoiling*; **nobody does wing-specific takeoff analysis** — Jan's idea stays a differentiator.

**Our differentiation:** correct sport plumbing (43) · full GP3S set live on Fenix 8 · published tunable foil detection · foil-native flight model (flights/touchdowns/longest) · wind-axis-aware turn classification with port/starboard asymmetry · takeoff/pump analysis · first-class iPhone replay · gear correlation.

## 2. Research findings that constrain the design

### Data pipeline (settled)
- **Garmin Connect Developer Program: off the table** (business-only, rejected individuals, and paused to new applicants in 2026). Unofficial Garmin APIs: hostile since Mar 2026 (Cloudflare TLS fingerprinting, account-level bans) — never in-app. HealthKit: no `HKWorkoutRoute` from Garmin → not a source (optional write target later). Strava: no original FIT via API + restrictive ToS → export target at most.
- **✅ Chosen pipeline:** CIQ app writes FIT + developer fields → auto-upload Garmin Connect → auto-sync intervals.icu → iOS app polls with personal API key (HTTP Basic, user `API_KEY`): `GET /api/v1/athlete/0/activities` + **`GET /api/v1/activity/{id}/file`** = original FIT, dev fields intact (gzip). Limits 5k/day. OAuth2 path exists for store phase. **Backfill:** Garmin GDPR "Export Your Data" ZIP (nested ZIPs of original FITs) via Files picker; single sessions via GC web "Export Original".
- **Parsing:** `roznet/FitFileParser` (MIT, dev-field support) primary; `garmin/fit-swift-sdk` for encode/cross-check; `vincentneo/CoreGPX`; Python `fitdecode` in the lab.
- **Wind:** Open-Meteo (free, keyless, CC-BY attribution) — Historical Forecast API (~1–2 km, ≥2021) for enrichment, Forecast API pre-session; model wind = prior, reconciled with track-derived estimate.

### CIQ platform (Fenix 8)
- Target **device app** (not data field): 768 KB RAM, `ActivityRecording` + 256 B/message dev-field budget (data fields: no recording, 32 B, 128 KB). **minApiLevel 5.0.0** (all shipped F8 firmware; SDK ≥7.4.3 to sideload). One binary covers 416/454 AMOLED + 260/280 MIP variants.
- `createSession({:sport=>43, :name=>"Wingfoil"})`; `save()` auto-syncs; `addLap()` per flight (+free per-lap max/avg speed via timer events). GPS: `CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1_L5`, **1 Hz hard ceiling**, `Position.Info.speed` = firmware GNSS (Doppler-based) speed. Accel via `registerSensorDataListener` ~25 Hz (query `getMaxSampleRate()`), `Math.FirFilter`, one listener max. `SensorLogging` writes accel into the FIT (designed for simulator replay — rate to verify on first build). Optical HR in water: expect gaps.
- Strava drops custom dev fields; intervals.icu ingests record-level ones (needs Custom Streams for its own UI — irrelevant, we parse the original FIT). Session-level dev fields: for our parser + GC summary only.
- UX: **button-first** (no water-lock/touch-disable API; swallow stray taps; destructive actions on buttons/hold). `Attention.vibrate` = primary alert channel. No forced backlight on AMOLED (`BacklightOnTooLongException`). No native post-activity summary for CIQ sessions → own summary view. Flashlight API available (dusk safety).
- Dev loop: VS Code Monkey C + simulator (FIT-activity replay only, **realtime, no fast-forward** → unit tests + short clips); sideload `.prg` → `GARMIN/APPS/` via MTP (**macOS: OpenMTP, quit Garmin Express**); **Beta App upload (alternate UUID) early** — only way to test GCM settings UI + dev-field rendering in Garmin Connect. Battery: multiband ≈30 h → sessions cost 7–13%.
- Phone link (phase 5): CIQ Mobile SDK iOS (SPM, ObjC-shaped); GCM needed for pairing only; ≤ ~10 KB per transmit, not a bulk channel; Info.plist traps documented (`-ObjC`, URL scheme, `gcm-ciq`, `CFBundleDisplayName`, BLE background mode). Hoolan proves this stack.

### Algorithms (reusable prior art)
- GP3S metrics: port `Logiqx/gps-wizard` (alpha-500 pseudo-code, filtering: HDOP ≤5, sats ≥5, 1 Hz accel-spike ≤4 m/s²; Pythagoras on local meters; candidate pruning ≥250 m + ≥90° COG) + `vvidovic/gps-stats` reference. **Doppler speed for records; positional/hybrid speed for turn minima** (Doppler smoothed ~3–4 s — Richterich's gotcha). Alpha implementations differ between packages; validate vs GPS-Speedreader on identical files.
- Turns: COG rate ~30–40°/s over ~4 s; score = min/entry speed (≥~70% ⇒ carried through); tack vs jibe via wind axis.
- Wind axis: circular COG histogram over foiling samples (≥2 m/s) → bimodal bisector; 180° resolved by up/downwind speed asymmetry → Open-Meteo prior → user input. Template: `mkobetic/gpx`; polars: `hrosailing`.

## 3. Architecture

**Governing rule:** the watch captures maximum-fidelity data plus robust live approximations; the phone re-derives everything from the original FIT and is authoritative. Watch-vs-phone divergence is surfaced, as a standing tuning/regression signal.

```
Fenix 8 CIQ app ──FIT(+dev fields, laps, accel)──> Garmin Connect ──auto──> intervals.icu
      │                                                                        │ /file (original FIT)
      └──(phase 5: BLE summary ≤10 KB)──> iPhone app  <──poll/import──────────┘
                                             │ also: Files/share-sheet, GDPR bulk ZIP
                                             └─> GRDB + immutable FIT archive + analysis engine
```

### 3.1 Repo layout (monorepo)

```
WingFoil/
├── docs/            plan.md · fit-schema.md (dev-field contract) · algorithms.md (canonical
│                    thresholds all 3 impls follow) · testing.md · decisions.md (ADRs)
├── garmin/          CIQ apps (Monkey C, minApiLevel 5.0.0)
│   ├── barrel/WingFoilCore/  shared detection core as a Monkey Barrel (Config ·
│   │                RingBuffer · SpeedRecords · FlightDetector · TurnDetector + its tests),
│   │                linked by both apps via barrelPath
│   ├── field/       WingFoil Field — CIQ data field (type datafield, own UUID + beta):
│   │                runs inside the native Windsurf activity, compact FIT schema
│   │                (docs/fit-schema.md "class d"), no laps/accel
│   ├── manifest.xml · monkey.jungle    (the device app, type watch-app)
│   ├── resources/   settings/ · fitcontributions/fit_contributions.xml · strings/ · layouts/
│   ├── source/      WingfoilApp.mc · session/SessionController.mc ·
│   │                metrics/{MetricsEngine,AlphaLite}.mc ·
│   │                (RingBuffer/SpeedRecords/FlightDetector/TurnDetector live in the barrel;
│   │                 detectors/PumpDetector.mc stays app-only — accel is device-app-only) ·
│   │                fit/FitFields.mc · ui/{PageSpeed,PageFlight,PageRecords,PageTurnsPump,
│   │                RecordingDelegate,SummaryView,WindMenu}.mc · alerts/AlertManager.mc ·
│   │                settings/AppSettings.mc · comm/PhoneLink.mc (phase-5 companion link)
│   └── tests/       Toybox.Test units
├── ios/
│   ├── WingFoil.xcodeproj (xcodegen from project.yml — edit THAT, not the pbxproj)
│   ├── WingFoil/    thin SwiftUI app target: Features/{Library,SessionDetail,Records,Trends,
│   │                Gear,Spots,Import,Settings,Companion} · Companion/ (the repo's ONLY
│   │                `import ConnectIQ` — see ADR-013)
│   └── WingFoilKit/ local SPM package: Models · FitImport (FitFileParser) · GPXImport (CoreGPX)
│                    · AnalysisEngine (pure Swift, incl. HrCost) · IcuClient · WindKit
│                    · Persistence (GRDB) · Presentation · Companion (SDK-free wire contract)
│                    · Tests (golden-file tests vs ../../fixtures)
├── lab/             Python (uv): src/wingfoil_lab/{parse,filters,flight,turns,wind,gp3s,pump,
│                    goldens,hrcost,jump}.py · tools/{clip_fit,make_goldens,make_unlock,
│                    scrub_fit,hr_report,jump_report}.py · notebooks/ · tests/
└── fixtures/        sessions/{windsurf-native,ciq,other-apps,gpx,accel}/ · clips/ (60–180 s
                     simulator-replay cuts) · goldens/*.expected.json · speedreader/ exports ·
                     README.md (provenance + Jan's per-session ground-truth table)
```

### 3.2 CIQ app design

**Modules:** `SessionController` (state machine IDLE→GPS_WAIT→RECORDING⇄PAUSED→SAVING→SUMMARY; owns session, laps, SensorLogger) · `MetricsEngine` (1 Hz tick from position callback; gates samples on `Position.Quality`; feeds buffers/detectors/FIT/UI) · `RingBuffer` (O(1) windowed sums: 2 s, 10 s, ~900-sample cumDist, ~180-sample local-XY) · `SpeedRecords` (live best 2s/10s/5×10s greedy top-5, 500 m/NM two-pointer) · `AlphaLite` (approximate alpha-500: armed for 120 s after a ≥90° turn, per-second two-pointer proximity ≤50 m test; displayed `~`-prefixed) · `FlightDetector` (hysteresis: entry ≥ `foilEntrySpeed` for `entryHold` s → ON; exit ≤ `foilExitSpeed` for `exitHold` s → OFF; < `minFlight` s discarded; emits laps) · `TurnDetector` (unwrapped 1 Hz COG: net ≥60° within ≤8 s, peak ≥25°/s, only on/near foil; score = minSpeed/entrySpeed; success = score ≥70% AND stayed above exit speed; tack/jibe only when wind axis known) · `PumpDetector` (25 Hz accel magnitude → FIR band-pass ~0.5–2.5 Hz → peak pick w/ prominence + 400 ms refractory; **live counter armed only while OFF_FOIL** for chop rejection — in-flight pumping analyzed later on the phone from the raw accel stream; attempt = strokes until ON_FOIL within 5 s (success) or 10 s silence/speed collapse (fail)) · `FitFields` (sole `setData` caller) · `AlertManager` (vibe profiles, 5 s debounce) · `AppSettings` (hot-reload via `onSettingsChanged`).

**Live on watch:** speed/distance/HR/GPS-quality, foil state + foil time/% + flight count/timer/longest, best 2s/10s/5×10s/500 m (+NM flag-gated), turn count + last score (+T/J when wind set), pump strokes + attempts/successes, ~alpha, **takeoff HR cost** (last takeoff, +bpm — published when the 30 s peak window closes, not at takeoff, because optical HR trails the effort by ~20 s; absent rather than 0 when HR is missing or the rise is under 5 bpm). **Deferred to phone:** exact alpha/1 h/full GP3S filtering, wind estimation + turn re-classification + port/starboard, turn minima on hybrid speed, full pump/takeoff analysis from raw accel, and the full HR-cost model (per-takeoff events, fatigue bins, pumping-vs-cruising, recovery half-times, each with its coverage).

**FIT developer-field schema** (contract in `docs/fit-schema.md`; speeds uint16 cm/s):
- **RECORD (6 B/s):** `foil_state`(0: uint8 enum off/pumping/flying, chart) · `flight_index`(1: uint16) · `pump_cadence`(2: uint8 spm, chart) · `turn_marker`(3: uint8 enum) · `tick`(4: uint8 rolling — forces 1 Hz records if smart recording interferes).
- **LAP (11 B; laps alternate flight/off-foil):** `lap_type`(10) · `flight_num`(11) · `takeoff_pumps`(12) · `takeoff_time`(13 s) · `pump_strokes`(14) · `turn_count`(15) · `best_turn_score`(16 %). Native lap distance/avg/max speed come free.
- **SESSION (~57 B):** `discipline`(20: string "wingfoil" — disambiguates from real windsurf) · `foil_time`(21)/`foil_pct`(22)/`flight_count`(23)/`longest_flight_s`(24)/`longest_flight_m`(25) · `best_2s`(26)/`best_10s`(27)/`best_5x10s`(28)/`best_500m`(29)/`best_nm`(30)/`alpha500_lite`(31) · `tack_count`(32)/`jibe_count`(33)/`turn_success_pct`(34) · `takeoff_attempts`(35)/`takeoff_successes`(36)/`avg_pumps_to_takeoff`(37, ×0.1)/`total_pump_strokes`(38) · `wind_dir_user`(39) · `cfg_entry_speed`(40)/`cfg_exit_speed`(41)/`cfg_min_flight`(42) (echo thresholds used) · `app_version`(43). Headline fields get `displayInActivitySummary`/`displayInActivityLaps`/`displayInChart` for Garmin Connect.

**Pages** (button-cycled; dark AMOLED UI) — **configurable, native-style**: up to 6 pages, each a *layout* + up to 5 *metric slots*, driven entirely from GCM (`pg<N>Layout`, `pg<N>s<M>`) and rebuilt on `onSettingsChanged` (`source/ui/PageModel.mc`). Layouts: `hero` (giant number + unit line + two rows) · `grid4` (optional giant + 2×2 label/value cells) · `cells2` · `records` · `turns` · `clock` (+1 cell) · `timeline` · `map`. Metric catalog: speed, foil %, flight count, current-flight timer, foil time, longest flight, distance, session timer, HR, best 2s, best 10s, turn count, last turn score, time of day, battery. **Defaults reproduce the five shipped screens:** 1 hero (speed / flight timer / HR + foil-state ring) · 2 grid4 (foil % giant + foil time / longest / km / flights) · 3 records · 4 turns · 5 clock + session timer · 6 off. `timeline` and `map` are opt-in.
- **timeline** = the session story: foil-fraction bars (30 s slots, halved in place when the 256-slot buffer fills, `source/metrics/SessionHistory.mc`), a max-speed sparkline with the best-2s reference line, and the last turns as green/amber/red dots.
- **map** = `WatchUi.MapTrackView` (**not** a `Toybox.Map` module — the map API lives in `Toybox.WatchUi`: `MapView`/`MapTrackView`/`MapPolyline`/`MapMarker`, API 3.0.0, and all five fenix 8 products in the manifest support it). It is a whole View, so paging onto it swaps views (`PageNav`); the breadcrumb is a decimated 128-point lat/lon buffer in `MetricsEngine`, only filled when a map page is configured. Runtime-gated on `WatchUi has :MapTrackView`.
- **Fonts are fitted, not fixed.** Round glass clips at the corners: every giant number and cell value picks the largest font in its ladder that still clears the chord at its own row depth, and cell columns split the chord available at their row. The layout unit tests drive the same fitters at worst-case content on a buffered-bitmap Dc, so clipping is a test failure, not a screenshot surprise.
- **Glyphs, not words, wherever a symbol is faster to read** (`source/ui/Glyphs.mc`, drawn with Dc primitives — no bitmap resources, so they recolour and rescale for free). Each cell's XTINY label row is now the metric's glyph (wing / stopwatch / ruler / heart / bolt / u-turn / pump / battery) plus the word, and the GCM toggle `showLabels` (default on) drops the word to leave the glyph alone. The Turns page shows the last outcome as a check / triangle / cross beside the score instead of FLEW / TOUCH / SWIM. Both blocks are measured against the chord by the same layout tests as everything else.
- **Foil % also reads as a bezel arc.** Any page whose slots include foil % draws it as a green arc from 12 o'clock clockwise over a dark-gray track, just inside the glass (`BEZEL_PEN` 6 px) — including the default grid page. On a `hero` page the flight-state ring steps inside so the two never overlap. Two primitive calls, no allocation per draw.
- **A new best-2s PB flashes the screen** (`source/ui/PbFlash.mc`): 7 × 100 ms frames of alternating green over whatever page is up, with the new number on it, alongside the existing PB vibe. One Timer, allocated once and re-armed; it auto-clears, and the PAUSED banner is drawn *after* it with an opaque background so a pause mid-celebration is never hidden.
- **The map breadcrumb is tinted by foil state**: green while flying, dark gray otherwise. `MapPolyline` carries one colour for a whole connected line, so the track is split into one polyline per run of equal state (`TrackTint` in `MapPageView.mc`) and the runs are added with `setPolyline()` after `clear()`. A minimum run length grows until the run count fits `MAX_RUNS` (32), which absorbs single-point flicker — at ~1 decimated point per minute that is the honest resolution anyway.
- **Launcher icons ship at each product's native size** (`compiler.json` `launcherIcon`: 65 px for fenix 8 47 mm / 8 Pro, 60 px for 43 mm, 40 px for both Solars and for the whole fenix 7 family). `resources/` holds the 65 px source and `resources-icon60` / `resources-icon40` override it through per-product `resourcePath` lines in every jungle (app and field, release and beta). Exports build with zero rescale warnings.
- **The fenix 7 family is in the product list** (all eight: `fenix7`/`7s`/`7x`, `7pro`/`7pronowifi`, `7spro`, `7xpro`/`7xpronowifi`) — added primarily so the *public invite-beta* listing has fenix 7 testers. They are CIQ 5.2.0, the same 768 KB watch-app budget and 100 Hz accelerometer as fenix 8, so nothing in the engine changes; the differences are all display. The barrel manifest carries the same list, because monkeyc requires a barrel's products to be a superset of every consumer's. Base `fenix7`/`7s`/`7x` have no multiband GNSS — `SessionController`'s existing `has`-guarded L1/L5 → L1 → GPS fallback covers it and compiles clean on all eight.
- **The layout tests measure the device's real glass, not 454 px.** They used to build their buffered-bitmap Dc at a hard-coded 454, which made every assertion vacuous on any smaller variant; `screenPx()` now reads `System.getDeviceSettings().screenWidth`. Turning that on surfaced three genuine defects on narrow MIP glass, all fixed: the Turns page's tack/jibe split count now walks the `NUMBER_FONTS` ladder instead of pinning `FONT_NUMBER_HOT` (it overflowed a 240 px chord); the Timeline's 44 px/96 px bands are authored for the fenix 8 family and scale below 416 px, since taken literally they filled 86 % of a 240 px screen and collapsed the chord under every band; and the lock screen's request code now treats the bitmap ladder as a floor the vector font must beat, because the widest vector size that fits an 8-character code on fenix 7 is *shorter* than that variant's `FONT_LARGE`. **The two 260/280 px fenix 8 Solar variants are MIP too and get the same Timeline fix** — the 416/454 px AMOLED faces are untouched.
- **Three build channels, not two** (ADR-012): public (`monkey.jungle`) · developer beta (`monkey-beta.jungle`) · **invite beta** (`monkey-invite.jungle`, own UUID, "WingFoil - Invite Beta"). CIQ beta listings are developer-only, so external testers need a *public* listing that starts **locked**: `source/lock/LockGate.mc` shows an 8-character request code derived from the device id, `lab/tools/make_unlock.py <code>` mints the matching key, and the tester enters it in the app's Garmin Connect settings (`unlockKey`, invite-only resource). The gate is armed by an 8-byte pepper that only the invite jungle compiles in (`garmin/gen/UnlockPepper.mc`, generated from `UNLOCK_SECRET` in `lab/.env`, gitignored); the other two channels compile the all-zero stub in `source-nopepper/` and never reach the lock screen. Obfuscation-grade by design, not DRM — see the ADR.

Alerts via vibration: 2s PB, longest flight, turn success/fail, takeoff success, optional time/distance interval. Summary view after save.

**Settings (GCM):** `foilEntrySpeed` 12 km/h · `foilExitSpeed` 8 · `entryHold` 2 s · `exitHold` 3 s · `minFlightDuration` 5 s · `speedUnit` km/h|kn · `sport` 43|44|other · `windDirection` · `gnssMode` · `turnSuccessPct` 70 · `pumpDetection` on · `rawAccelLogging` on · per-alert toggles · `alertIntervalMin`/`alertIntervalKm` (0 = off) · `autoPause` (off) + `autoPauseDelayS` 5 s · `showLabels` (on — off leaves cells showing the glyph alone) · `phonePush` (on — the phase-5 summary to the companion app) · the 36 data-screen keys above. Recording: 1 s, multiband, never SatIQ; document watch "Data Recording = Every Second".

**Auto-pause** (`source/session/AutoPause.mc`, off by default): speed under 1.0 m/s for `autoPauseDelayS` → `session.stop()` + PAUSED banner; the first sample at or above 1.0 m/s resumes. It only ever undoes a pause it caused — a manual pause calls `reset()` and stays put.

### 3.3 iOS app design

- **Persistence: GRDB + immutable archive** (not SwiftData — workloads are SQL aggregations, background imports, migration control; no CloudKit need). `Sessions/<uuid>/original.fit` immutable + `analysis.json` (versioned `SessionAnalysis`; engine bump ⇒ lazy re-analysis) + `wingfoil.sqlite`: `session` (denormalized summary cols), `flight`, `turn`, `takeoff_attempt`, `record_effort` (PB history), `gear`, `spot`, `import_log`. Dedupe key = startDate ±60 s + duration ±60 s (same session may arrive via icu, GDPR bulk, AirDrop).
- **Analysis pipeline** (pure functions, golden-tested): parse (FIT/GPX → RawTrack + `SourceCapabilities`) → clean (GP3S gates where channels exist, local-meter projection, hybrid speed channels, gap marking) → segment flights (same semantics as watch; watch laps = hints, phone wins) → detect turns → estimate wind (histogram + prior + user override) → classify turns (tack/jibe, bear-away rejection, port/starboard) → GP3S records (with window provenance for map highlighting) → takeoff/pump analysis (incl. in-flight pumping; degrades by source) → summarize (+watch-vs-phone divergence report).
- **Input classes:** (a) our CIQ FITs = everything; (b) native Windsurf FITs (Jan's 9) = all but pump (speed-pattern-only/omitted); (c) GPX = degraded, records badged "uncertified".
- **Features:** Library (rows carry a cached track thumbnail + speed sparkline + outcome tally) · Session Detail (MapKit track colored by phase/speed, record-window glow, Swift Charts speed timeline w/ flight bands + turn markers + pump subchart, divergence banner, **replay scrubber** whose playhead is shared by chart and map so tapping either moves both, **share card** composer) · Records (all-time/per-spot/per-gear, kn; medal by record freshness, confetti + haptic on a new all-time PB) · Trends (foil %, longest flight, turn success, pumps-to-takeoff, port/starboard) · Gear · Spots (auto-cluster + wind roses) · Import (icu polling w/ Keychain key; Files/share-sheet FIT/GPX/ZIP; GDPR nested-ZIP backfill with sport sniff + dedupe + progress) · Wind (Open-Meteo enrich + estimator reconcile) · **Help** (plain-language explanation of every metric, deep-linked from a `?` on the card that shows it) · **Widgets** (last session + weekly foil time; see ADR-011 on the app group) · Settings (thresholds mirroring `docs/algorithms.md`, re-analyze button, attribution).
- **Phase 5 companion link (BUILT, BLE hop unverified — ADR-013):** watch→phone one-shot summary, measured **192 B / 21 keys** against a 1 KB budget (the ≤10 KB ceiling was never the target); a newest-wins pending slot when the phone is unreachable; the card lands as a **provisional** session row that the FIT later replaces in place, through the ingestor's existing ±60 s dedupe rule; phone→watch wind push is a **manual** action for now. SDK (`connectiq-companion-app-sdk-ios` 1.8.0, SPM binary target) lives in the app target only, behind `CompanionLink` in WingFoilKit, so the kit builds and tests with no framework present. Two fenix 7 traps documented in `PhoneLink.mc`: `registerForPhoneAppMessageErrors` bricks those devices despite `has` returning true, and a `Lang.Method` bound to a module wedges the same call.

### 3.4 Algorithm strategy

Tune in Python on real data → port to Swift (authoritative) → approximate in Monkey C. Parameters defined once in `docs/algorithms.md`. Corpus = Jan's existing FITs (pull originals via intervals.icu) + FoilMotion/"Wingfoiling" FITs + every new session from the phase-1 build (**which is the accel-capture vehicle**, SensorLogging on). Ground truth: Jan logs per session (jibes attempted/made, tacks, takeoff attempts, wind, gear) into `fixtures/README.md`. Goldens: human-validated notebook results → `fixtures/goldens/*.expected.json` (shared schema); Swift asserts same goldens (counts exact, speeds ±0.05 kn, times ±1 s, foil time ±2%); Monkey C tested via unit tests fed recorded 1 Hz/25 Hz arrays + simulator replay of 60–180 s clips with documented expected outcomes; GP3S numbers cross-validated against GPS-Speedreader exports on identical files (`compare_speedreader.py`, CI-run).

## 4. Roadmap (W=watch, P=phone, L=lab; algorithms flow L→P→W)

- **Phase 0 — Scaffold (1–2 days):** repo layout; lab env; pull existing FITs into fixtures + archive GPS-Speedreader outputs; Xcode + WingFoilKit parsing one fixture; CIQ hello-world sideloaded (OpenMTP). *Accept: pytest green; Swift record-count matches Python; `.prg` runs on the watch.*
- **Phase 1 — Garda-week watch MVP + first analysis:** **W1 in:** sport 43 "Wingfoil", multiband, button-only start/pause/save, FlightDetector w/ tunable thresholds, per-flight laps, record fields 0+4, session fields 20–29, SensorLogging accel ON, Pages 1+2, live 2s/10s + PB buzz. **W1 out:** turns, pump UI, 5×10s/500 m/alpha live, wind entry, pages 3/4, phone link. **P1:** parse→clean→flights→records for classes (a)+(b); Files import + icu polling; Library + Session Detail (phase-colored map, flight-band chart). **L1:** hysteresis tuning + GP3S validation vs Speedreader; first goldens. *Accept: a real Garda session recorded with W1 lands in GC as **Windsurf**, syncs to intervals.icu, iOS pulls the original FIT, dev fields + laps parse, **accel stream present at expected rate (if absent/too coarse: re-scope phase 3 to on-watch pump metrics only)**, foil % plausible vs feel; all existing sessions imported + matching goldens.*
- **Phase 2 — Turns & wind (needs P1/L1):** L turn+wind tuning on labeled sessions; P stages 4–6 + Open-Meteo + turn UI; W TurnDetector, wind menu, transition alerts, Page 4. *Accept: counts within ±1 of Jan's logs on 3+ sessions; wind axis ±20°; scores match feel.*
- **Phase 3 — Records complete + takeoff/pump (needs phase-1 accel fixtures):** L pump detection on wrist-accel corpus; P full GP3S (alpha/NM/1 h) + takeoff analysis + UI; W PumpDetector live, 5×10s/500 m/NM/AlphaLite, Page 3, remaining session fields. *Accept: pumps-to-takeoff ±2 strokes on ≥80% of verified attempts; alpha/500 m within tolerance of Speedreader; watch live within ±0.2 kn of phone.*
- **Phase 4 — Library depth (needs P1, independent of W):** gear, spots, trends, PB history, GDPR bulk backfill, divergence banner, optional Apple Health write. *Accept: full-history backfill clean, zero duplicates; all-time PBs across source classes.*
- **Phase 5 — Companion link — BUILT, acceptance PENDING on hardware:** instant summary card + wind push. Everything either side of the BLE hop is unit-tested (watch 54/54, kit 181); the hop itself needs a paired watch, GCM and a real iPhone. *Accept (still to prove on the water): card <60 s after save, numbers match the later full analysis, wind set on the phone shows on the watch, and `Activity.Info.elapsedTime` equals the FIT's `total_elapsed_time` on a session WITH a pause — the dedupe key rests on that.*
- **Phase 6 — Store-readiness (optional):** Beta App → store listing, intervals.icu OAuth2, MIP-variant QA, DE localization, pricing decision.

## 5. Verification

- Monkey C unit tests (RingBuffer, detectors fed synthetic + recorded arrays, SpeedRecords vs hand-computed) — simulator replay only for integration smoke on ≤3 min clips (realtime-only constraint).
- MonkeyGraph preview of dev-field charts; **Beta App upload in phase 1–2** to verify GCM settings + Garmin Connect rendering early.
- Swift golden-file tests (tolerance table above) + parser fail-soft tests + synthetic nested-GDPR-ZIP importer test.
- CI cross-validation vs GPS-Speedreader on every fixture.
- Watch-vs-phone auto-check on every class-(a) import (banner at >5% foil time / >0.3 kn / ±1 counts) — standing field-regression alarm.
- On-water protocol (<5 min/session): pre — wind guess + gear; post — jibes/tacks/attempts/crashes/felt-longest into `fixtures/README.md`; discrepancies become tuning issues.

## 6. Risks & mitigations (top)

| Risk | Mitigation |
|---|---|
| Foil detection at 1 Hz (taxi overlap, chop) | Tunable hysteresis + holds + min duration; labeled-corpus tuning; phone authoritative; divergence banner |
| Pump false positives (chop, arm swing) | Armed only OFF_FOIL live; band-pass + prominence + refractory; phone refines from raw stream |
| Wet-touch chaos | Button-first; swallow taps; destructive = hold/menu; glove test at Garda |
| Optical HR gaps in water | Null-guard; HR metrics only over valid spans; chest strap works via firmware if wanted |
| intervals.icu single sync point | Convenience not dependency: Files/AirDrop/GDPR/Export-Original always work; importer behind protocol |
| FIT parsing edge cases | `SourceCapabilities` fail-soft; foreign-app fixtures; fit-swift-sdk cross-check; failed parses archived |
| CIQ memory/CPU ceilings | O(1)-amortized per tick; accel per-batch; NM/AlphaLite feature-flagged; profile each phase |
| Lap flood / FIT bloat | Min-flight gate; ~200-lap cap (then dev-fields only); 6 B/s record budget |
| Smart recording <1 Hz | Document Every-Second setting; `tick` field workaround; verify cadence in first sideload FIT |
| SensorLogger rate/format uncertainty | Phase-1 acceptance gate verifies the accel stream before phase 3 depends on it |
| Simulator realtime friction | Logic in unit-testable state machines; clips ≤3 min; Beta App early |

## First implementation steps (phase 0 kickoff)

1. `docs/fit-schema.md` + `docs/algorithms.md` (the two contracts everything references).
2. `garmin/` skeleton → hello-world `.prg` sideloaded to the Fenix 8.
3. `lab/` env; download Jan's existing session FITs via intervals.icu `/file` into `fixtures/sessions/windsurf-native/` (verify one against GC "Export Original" byte-for-byte); run GPS-Speedreader, archive exports.
4. `ios/` project + `WingFoilKit` with FitFileParser; decode one fixture; GRDB schema v1.
