# Decision Log (ADR-style)

Newest first. One paragraph each: context → decision → consequence.

## ADR-011 · Widgets ship without an app group, and say so
The WidgetKit extension (`de.lahmann.wingfoil.widgets`, embedded in the app) needs the app's
data, and a widget process cannot open the GRDB library — different container, 30 MB memory
limit. The app therefore publishes a small denormalized `WidgetSnapshot` (last session +
this week's foil time) after every library change, and the widget only decodes it. The
transport **would** be `UserDefaults(suiteName: "group.de.lahmann.wingfoil")`, but the
existing manual "WingFoil App Store" provisioning profile does not carry that group, and
requesting an entitlement a profile does not grant fails the archive — which would break
Jan's TestFlight path for a home-screen widget. Decision: no app-group entitlement in
either target; `WidgetSnapshotStore` probes for the shared container at runtime with
`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` — the *only* honest
test, since `UserDefaults(suiteName:)` returns a usable-looking object without the
entitlement and a write/read round-trip through it succeeds against a plist that lives
inside the app's own container and is invisible to the widget. Consequence: with today's
profile the widget installs, archives and renders a "finish setting up" state; the app
always writes a local copy so its own read-back never depends on the entitlement. Turning
the widget on for real is **configuration, not code** — add the App Groups capability to
both app ids, regenerate the profiles, add `com.apple.security.application-groups` to both
`entitlements` blocks in `ios/project.yml`, and add the widget's bundle id to
`ios/ExportOptions.plist` (which currently carries only the app, so a *manual* export of an
archive containing the extension needs that entry, or an automatic-signing export).
Second consequence: the snapshot *format* is compiled into the widget as shared source
(`WidgetSnapshot.swift`) rather than by linking `WingFoilKit`, so an extension whose job is
to decode a few hundred bytes of JSON does not carry GRDB, the FIT parser and ZIPFoundation;
the half that reads library rows lives in `WidgetSnapshot+Library.swift`, which only the app
compiles.

## ADR-010 · Metric explanations are kit data, not view code
Every number the app shows needs a plain-language explanation, and the explanations have to
be reachable from the card that shows the number — a glossary nobody opens is not
documentation. `HelpCatalog` lives in `WingFoilKit` as pure data keyed by a `HelpTopicID`
**enum**, so a card's `?` button cannot link to a topic that does not exist (compile-time),
and one test asserts the other half: that no case ships without written content. Wording is
derived from `docs/algorithms.md`, and where it quotes a threshold it says it is a default
rather than a law. Consequence: adding a metric to the UI forces a `HelpTopicID` case, which
fails the test until it is actually written — the glossary cannot silently rot behind the
app. Same reasoning put the share-card content (`ShareCardStats`), the list-row thumbnail
geometry (`TrackThumbnail`), PB detection and the widget snapshot in the kit: they are the
parts of a UI change whose mistakes are invisible in a screenshot — a card that prints
"0.00 kn" where it means "unknown", a thumbnail that silently stretches, a confetti burst on
the first import.

## ADR-009 · Data-field companion **in addition to** the device app, sharing a barrel
ADR-002 chose a device app and that stands — it is the only way to control recording, laps and
the accelerometer. But it forces an either/or on the water: launching it means *not* using the
native Windsurf profile Jan already records with. The **WingFoil Field** data field
(`garmin/field/`, own UUID + beta UUID, type `datafield`) removes that choice: it runs inside
the native activity and contributes the same metrics as developer fields. Its costs are real
and permanent — no `ActivityRecording` control, **no `addLap()`**, 128 KB, 32 B *and* 16
developer fields per message, and every `Toybox.Sensor` entry point crashes a data field
outright (verified in the fenix 8 `api.debug.xml`), so **no accelerometer and no pump metrics,
ever**. Barometric submersion evidence and `Activity.Info.track` (COG) *are* available, so
flight and turn detection survive intact. Consequence: a new FIT source class (d) — compact
session schema, packed fields, no laps of ours (docs/fit-schema.md).
Layout: `garmin/field/` and `garmin/barrel/WingFoilCore/` sit *inside* `garmin/` rather than as
top-level `garmin-field/`. Jungles name paths relative to their own directory, so nesting keeps
every barrel reference short and symmetrical (`barrel/WingFoilCore/barrel.jungle` from the app,
`../barrel/WingFoilCore/barrel.jungle` from the field), lets both apps share one
`developer_key.der` and one `bin/`, and keeps everything Garmin under one root — while the
projects stay fully independent, since a jungle's `sourcePath` is explicit and never inherits a
sibling's sources.

## ADR-008 · Detection core extracted into the `WingFoilCore` Monkey Barrel
Two apps computing "a flight" from two copies of the same state machine is how the watch and
the field would silently disagree by next season. `RingBuffer`, `SpeedRecords`,
`FlightDetector`, `TurnDetector` and a new `Config` moved into `garmin/barrel/WingFoilCore/`,
linked by both apps as a barrel *project* dependency (`base.barrelPath = .../barrel.jungle`) so
there is no export step between editing the core and rebuilding either app. The detectors used
to read the device app's `AppSettings` module directly; they now take a `Config` object in
`initialize()`, and each app fills one from its own GCM properties. The barrel carries its own
`tests/`, so **both** apps' `--unit-test` builds run the same 16 core tests against the same
sources. Barrel constraints learned: every symbol must live inside the barrel's module (a test
function at file scope fails `barrelbuild`), and class-level `const`s are instance-scoped, so
shared tables like `COMPASS` belong at module scope.

## ADR-007 · Pump detector armed only while off-foil (watch); in-flight pumping on phone
Wrist accel while flying is polluted by chop and steering inputs. The live watch counter arms
only in `OFF_FOIL` (takeoff attempts — the priority metric); raw accel is logged regardless, so
the phone can analyze in-flight pumping (lulls, downwind) later without on-watch false positives.

## ADR-006 · GRDB + immutable file archive, not SwiftData
Workloads are SQL aggregations (all-time records, per-gear/spot rollups), heavy background
imports, and schema migrations; no CloudKit requirement (local-first). Original FIT files are
immutable under `Sessions/<uuid>/`; analysis is a versioned derived artifact (`analysis.json`),
so the engine can always re-run. iCloud Drive folder sync is the later path, not CloudKit.

## ADR-005 · Watch approximates, phone is authoritative
1 Hz + 768 KB on-watch vs unlimited offline compute: the watch ships robust approximations
(hysteresis flight detection, greedy 5×10s, alpha-lite) and maximal raw capture (1 s records,
laps, accel); the phone re-derives everything from the original FIT. Divergence is surfaced as a
tuning signal, never silently reconciled.

## ADR-004 · Record FIT sport 43 (windsurfing), discipline tag in a dev field
No wingfoil sport exists in FIT-as-exposed-to-CIQ/GC/Strava/intervals.icu. Sport 43 lands as
"Windsurf" everywhere (vs the "Walk" mis-typing of FoilMotion et al.) and gets Garmin's
least-filtered Doppler speed path. Session dev field `discipline="wingfoil"` (not the sport
code) is our authoritative discipline marker. Sport user-overridable in settings.

## ADR-003 · Data pipeline via intervals.icu personal API, not Garmin APIs
Garmin Connect Developer Program is business-only and paused (2026); unofficial APIs are
Cloudflare-blocked with account-ban risk; HealthKit carries no Garmin GPS routes; Strava API has
no original FIT + restrictive ToS. Jan's Garmin→intervals.icu sync is active; `GET
/api/v1/activity/{id}/file` returns the original FIT (dev fields intact). Fallbacks that always
work: Files/AirDrop import, GC "Export Original", GDPR bulk ZIP. Importer sits behind a protocol
so an OAuth2 intervals.icu client (or future Garmin API) can swap in for a store release.

## ADR-002 · CIQ device app, not data field
Data fields cannot record activities, get 32 B/message dev-field budget and 128 KB RAM on
Fenix 8. Device app: 768 KB, 256 B/message, full UI/input/alerts, `Communications` for the
phase-5 companion link. minApiLevel 5.0.0 (all shipped Fenix 8 firmware).

## ADR-001 · Monorepo with a Python lab and golden-file contract
Detection algorithms are tuned in `lab/` (fitdecode + scipy) against real labeled sessions,
frozen as golden JSONs, then ported: Swift (authoritative) and Monkey C (live approximation)
assert against the same goldens/clips. Parameters live once in `docs/algorithms.md`.
