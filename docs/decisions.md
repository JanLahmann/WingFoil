# Decision Log (ADR-style)

Newest first. One paragraph each: context → decision → consequence.

## ADR-013 · The companion link carries a **card**, not data — and reuses the import dedupe rule
Phase 5 asks for a session summary on the phone before the FIT has finished its trip through
Garmin Connect. The channel for that is `Communications.transmit` to a companion app over BLE,
which is shared with the whole Garmin ecosystem and is documented by Garmin itself as a place
to send as little as possible. Decision: the payload is a **notification, never a source of
truth** — integers only, short keys, and only the numbers the card actually shows (measured:
**192 bytes, 21 keys** for a 2-hour session against a 1 KB budget). The FIT still arrives
later and the phone still re-derives everything from it; the card is replaced by real analysis
when it does.
Reconciliation is the part that could have gone wrong twice. The dedupe key is **session start
epoch + elapsed seconds, meaning exactly what the FIT's session start and `total_elapsed_time`
mean**, so the card goes through the SAME `SessionIngestor` rule that already dedupes imports
(±60 s on both), instead of a second mechanism that would drift from the first. The card lands
as a **provisional** row (schema v4 `isProvisional`); the FIT replaces it in place, same row id,
sources merged. A provisional row whose FIT never arrives stays — it is a real session the rider
did, and its absence from Garmin Connect is information too. Provisional rows are excluded from
the library aggregates and from `reanalyzeStale`, which would otherwise announce a re-derive on
every launch for ever.
When the phone is unreachable — the normal case, not the error case — the watch keeps **one
pending slot, newest wins**. Three sessions recorded away from the phone should produce the
newest card on reconnect, not three stale ones replayed in order.
The SDK boundary: `connectiq-companion-app-sdk-ios` 1.8.0 is an SPM **binary** target (ObjC
xcframework) and it goes into the **app target only**, behind a `CompanionLink` protocol
declared in WingFoilKit. WingFoilKit never imports it, so the package keeps building and
testing on any machine with no framework and no watch in the room, and the wire contract stays
unit-testable (17 tests) against a fake.
Two fenix 7 platform traps found the hard way, both now in `PhoneLink.mc`'s header because
neither is discoverable from the docs: **`registerForPhoneAppMessageErrors` bricks the fenix 7
family** — the app does not start, with no exception and no log — and `Communications has
:registerForPhoneAppMessageErrors` returns **true** there, so a capability guard does not save
you. It is not called at all; the failure that matters (a summary that did not land) arrives
through `ConnectionListener.onError`, which is what preserves the pending slot. And a
`Lang.Method` bound to a **module** rather than a class wedges the same call: compiles clean,
works on fenix 8, hangs on fenix 7.
Consequence to be honest about: **the BLE hop itself is unverified.** Everything either side of
`transmit` is unit-tested; the hop needs a paired watch, GCM and a real iPhone. So does the
assumption underneath the dedupe key — that `Activity.Info.elapsedTime` equals the FIT's
`total_elapsed_time` — which needs one real session **with a pause** compared against its synced
FIT before the key can be trusted.

## ADR-012 · Invite testers get a **public** listing with an obfuscation-grade lock
A Connect IQ "beta app" listing is visible only to the developer account, so the one thing it
cannot do is reach a tester. The only channel to a friend's watch is a **public** store
listing — which anyone can install. Decision: a third build channel, `manifest-invite.xml` +
`monkey-invite.jungle` (own UUID, "WingFoil - Invite Beta"), identical code to the public app
except that it starts locked. `LockGate` derives an 8-character **request code** from
`System.getDeviceSettings().uniqueIdentifier` (present on fenix847mm per the SDK 9.2
`api.debug.xml`; per-app, per-device, stable across uninstall, and null-guarded by a
first-run random id in `Storage`), the lock screen shows it, Jan runs
`lab/tools/make_unlock.py <code>` and mails back an 8-character **unlock key**, the tester
types it into the app's Garmin Connect settings, `onSettingsChanged` re-validates and the
app opens for good on that watch. Codes are Crockford base32 (no I/L/O/U) because they are
read off round glass and typed on a phone; the watch folds the look-alikes back anyway.
The honest part: the check is `key == B32_40(FNV1a64(pepper || request_code))`, computed the
same way on both sides, so the 8-byte **pepper** compiled into the invite build is the entire
secret and anyone who unpacks the `.prg` can mint keys. That is not a shortcut, it is the
shape of the problem — offline per-device verification means the watch must hold whatever it
verifies against, and an HMAC secret would be no less extractable (and CIQ has no crypto
primitives to compute one with anyway). Truncated-HMAC key generation was the first design
and was dropped for exactly this reason: it would have looked cryptographic while being
unverifiable on-watch, and the two sides would have had to disagree. So the gate is a
"please don't", sized for a handful of invited testers on a free hobby app, and this ADR
says so rather than the code implying otherwise.
Mechanics that keep the secret out of git: `UNLOCK_SECRET` lives in the gitignored `lab/.env`;
`make_unlock.py --emit-pepper` derives the pepper and writes `garmin/gen/UnlockPepper.mc`,
which `.gitignore` covers (`garmin/gen/` **and** `garmin/source/gen/`, so the file cannot be
moved under the shared source path by accident). Exactly one directory supplies module
`UnlockPepper` per build: `garmin/source-nopepper/` (all zeros ⇒ `LockGate.enabled()` false
⇒ the public app and the beta build never reach the lock screen, verified by a unit test and
by their settings JSON not carrying `unlockKey`) or `garmin/gen/` (invite only). Building the
invite jungle without the generated file fails loudly on an undefined `UnlockPepper` rather
than silently shipping an open lock. Consequence: three channels to keep straight
(public / beta / invite), one gitignored generated file to re-emit on a fresh clone — from
the same secret, so keys already issued keep working — and a per-tester step for Jan that is
two lines of mail. Parity between the Python and Monkey C implementations is held by three
shared test vectors hard-coded in both suites; the 64-bit FNV state is carried as two 32-bit
halves on both sides so nothing depends on Monkey C's undocumented `Long` overflow behaviour.

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
