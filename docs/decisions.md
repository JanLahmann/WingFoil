# Decision Log (ADR-style)

Newest first. One paragraph each: context → decision → consequence.

## ADR-017 · The complication is a **launcher**, the Siri intents live in the app, and neither detects anything
ADR-016 declined a complication on the grounds that it would be "a fourth surface making claims
about a session". That reasoning was about *claims*, and it survives intact — what it did not
cover is the gesture. Between a watch face and a running recording there were five steps (crown,
find the app in a grid of forty, launch, wait, START), performed in knee-deep water by a rider
holding a wing overhead with wet hands, and every one of them is a chance to start the session
two minutes late or not at all. Decision: **one complication whose entire job is to start the
session**, plus Siri phrases that do the same thing hands-free. `accessoryCircular`,
`accessoryCorner` and `accessoryRectangular` carry the brand mark and a `widgetURL` of
`cleanjibe://start`; the app answers it through `SessionRecorder.startFromOutside()`, which is
also the door `StartSessionIntent` comes through. One entry point, so a session begun from a face
is not a second kind of session — same `HKWorkoutSession`, same water lock, same files — and the
UI follows without a tap because `phase` is what `RootView` switches on.
**The complication is a separate target because WidgetKit demands one; the intents are not,
because nothing demands it.** A complication is a WidgetKit extension — its own process, its own
`@main`, its own bundle id — and there is no way to render one from an app target, which is why
`WingFoilWatchWidgets` (`de.lahmann.wingfoil.watchkitapp.widgets`) exists at all. App Intents are
under no such constraint, and an intents *extension* would have been actively worse: the thing
this intent moves is a state machine that owns an `HKWorkoutSession`, which exists in the app
process and nowhere else, so an extension would have to message the app to do the work — the app
doing the work, with a round trip in front of it. `openAppWhenRun` says "run me in the app" and is
also the honest answer, because the rider who says it out loud wants to see his watch recording.
No new entitlement: no app group, no HealthKit in the extension, nothing but the URL.
**It still claims almost nothing, and that is ADR-016 holding rather than being softened.** The
watch cannot print a clean-jibe count or a foil percentage, because under ADR-016 it does not
compute them — those exist only after the phone has analysed the recording, and a face that
guessed at them would be the exact second answer that ADR forbids. The rectangular family
therefore shows either "Start session" or the three facts the watch measured itself (date,
duration, distance), through a ~200-byte `WatchLastSessionStore` snapshot written *after* the
`.cjw` container is safely assembled — never before, so a face cannot advertise a session that
failed to save. That store has the same app-group shape, and the same missing entitlement, as
`WidgetSnapshotStore`: the manual App Store profiles do not carry `group.de.lahmann.wingfoil`, so
today the write is a no-op and every face reads "Start session". Which costs nothing that matters,
because the launcher — the whole point — needs no group at all.
Consequences: `SessionRecorder` becomes a singleton (there is one workout session on a wrist, and
two things outside the view tree now have to reach it); `startFromOutside` waits on the HealthKit
prompt before starting, because a Siri start may be the first thing a cold process does and
`WorkoutBridge.start` throws if Health has not answered; the two constants both targets must agree
on live in `ios/WatchShared/`, outside either target's source tree, for the XcodeGen path-collision
reason `Views/WatchBrand.swift` already documents; and `ios/ExportOptions.plist` needs a fourth
profile, three bundles deep. **iPhone-side intents were considered and dropped**: the phone cannot
start a watch workout without `HKHealthStore.startWatchApp(with:)` and a WatchConnectivity handoff,
which is a feature and not a trivial re-export, so "Start a CleanJibe session" is a watch phrase.

## ADR-016 · The Apple Watch recorder is class (b) and **certifies**, and it detects nothing
An Apple Watch is the one recording device a rider already owns that can reach the library
without an account, a cable or anybody's cloud: the watch writes a file, `WCSession.transferFile`
queues it, the phone imports it. That removes the Garmin→Connect→intervals.icu chain from the
funnel entirely, so the MVP's job is to be a **recorder** and nothing else — GPS, heart rate, and
the wrist accelerometer at 50 Hz, into a versioned `.cjw` container (docs/watch-session-schema.md)
that `TrackParser` recognises by its first four bytes exactly as it already recognises a GPX.
Nothing downstream of `RawTrack` + `SourceCapabilities` learns that an Apple Watch exists.
**No detection on the wrist.** ADR-005 says the watch approximates and the phone is
authoritative, and that division earns its keep on Garmin because the Garmin watch is also the
*display* — a rider mid-session wants a flight count on his wrist. Here it buys nothing: the
recording reaches the phone in seconds, so a second implementation of flight, turn and record
detection would be a second answer to every question with no way to tell which one the app meant.
Phase 2 can add it; the MVP declines it on purpose, and `hasDevFields` is false because there
genuinely are none.
**Class (b), certified, and no new letter.** The rule in docs/presentation.md is about
*provenance* — a speed record is trustworthy when it came off the receiver's Doppler channel —
and `CLLocation.speed` is exactly that, the GNSS chip's own solution rather than a difference of
positions. A GPX is class (c) because the file cannot prove where its speed came from; this
container can, because we write it and it carries speed and position as two separate channels.
That is the same claim already made for a native Garmin FIT, and it is **not** a GP3S validity
claim, which this app has never made for any source. A dedicated letter was considered and
rejected: (d) is spoken for by ADR-009, so a watch class would be (e), and it would have to be
taught to six Swift switch sites, `web/js/render.js`'s letter dictionary, `HelpCatalog`'s
three-case prose and `lab/parse.py` — to express a distinction `certified` does not draw.
Provenance survives in `session.importSource` (`applewatch`) instead.
Consequence: the letter now understates one source, and two places had to learn that. A watch
session has class (b)'s Doppler **and** class (a)'s accelerometer, so pump strokes and takeoff
effort are all present — the pipeline degrading on capabilities rather than on formats, which is
what that design was always for. `SessionDisplay.sourceClassNote` therefore reads `importSource`
as well as the class, because the standard class-(b) line ("everything except pump and takeoff
effort") would otherwise print over a session that visibly has a pump chart.
**`.surfingSports`, and the phone stands down from Health.** HealthKit has no wingfoil type;
`HealthWriter` already chose `.surfingSports` and the watch matches it, or a rider's Health
timeline would name one sport two ways. Because the watch saves the workout live — with the
heart-rate samples and ring credit an after-the-fact `HKWorkoutBuilder` stub cannot give —
`SessionStore.writeNewSessionsToHealth` skips rows tagged `applewatch`; nothing downstream would
have collapsed the duplicate, since `HKMetadataKeyExternalUUID` carries the watch's session id on
one copy and the library's row id on the other.

## ADR-015 · The library backup restores through the **ingest path**, never as a file copy
The library lives in Application Support, so an iPhone migration and an iCloud device backup
already carry it and nothing here replaces that. What neither covers is a *fresh* start — a
phone set up as new, the app deleted and reinstalled — and the loss is asymmetric: the
recordings can be re-fetched from intervals.icu with some pain, but `customTitle`, `shareNote`,
the rider attribution, the gear links, the spot names and the tombstones exist in one SQLite
file on one phone and nowhere else. Decision: **one zip** — `manifest.json`, `library.sqlite`,
`Sessions/<uuid>/{original.fit|gpx,analysis.json}` — written to `tmp/` and handed to the share
sheet, so the rider picks the destination (iCloud Drive being the obvious one) and the app never
writes to his storage on its own.
Two decisions inside that carry the weight. **The database snapshot is `VACUUM INTO`, not a
file copy.** Copying a live SQLite file is the classic way to ship a corrupt backup: the `-wal`
and `-shm` sidecars hold committed pages the main file has not absorbed, and copying all three
is not atomic either. `VACUUM INTO` runs on GRDB's serialized writer connection inside SQLite's
own read transaction, so it sees one consistent snapshot with the WAL folded in, writes a single
sidecar-free file, and compacts on the way — `DatabasePool.backup(to:)` plus the compaction, and
unlike `PRAGMA wal_checkpoint(TRUNCATE)` + copy it cannot race a writer that commits between the
two steps. **And restore never puts that file back.** Copying it over the live database would
delete every session imported since the backup, undo every rename since, and resurrect
everything deleted since. Instead the snapshot is opened *beside* the live library, migrated
forward by the ordinary `AppDatabase.migrator` when it is older, and read as a source of facts:
each session goes back in through `SessionIngestor.ingest` — the same door icu, GDPR and AirDrop
use, same ±60 s dedupe key — and the metadata is merged with one rule, *fill what is missing,
never overwrite what is there*. Gear merges by natural key (kind + name, case-insensitive) so a
second restore does not double the kit list; spots carry over only a name the rider typed, onto
a live spot still auto-named within the backup spot's radius; tombstones union by id.
Consequences, all of them deliberate. **Restore is idempotent by construction** rather than by a
"already restored" flag — the second pass finds every session by dedupe key and every field
already filled, and writes nothing (asserted). **It never resurrects a session deleted since the
backup**: a live tombstone is the newer instruction, and those are counted and reported rather
than silently obeyed or silently overruled. **A provisional row cannot be restored** — the
watch's BLE card carries no recording, and inventing a session row from summary columns is the
blind copy this whole design avoids. **A future schema is refused by name**, because a backup
from a newer build can hold columns this one has never heard of; an older one is the ordinary
case and is migrated. Size is stated before the work starts and warns above 200 MB naming the
accelerometer, which is ~95 % of any CIQ recording that has one. ZIPFoundation was already a
dependency for the GDPR nested-ZIP reader, so the write path cost nothing new; unlike the import
side it opens the archive **by URL** rather than from `Data`, because a season's backup is
gigabytes and the GDPR reader's whole-file-in-memory shape does not survive that.

## ADR-014 · The device list stops at CIQ ≥ 5.x sports watches (Tier A), and stops there on purpose
The app shipped on the fenix 8 and fenix 7 families and nothing else, which is a small slice of
the watches that could run it. A survey of the whole SDK device catalogue against the built
app's own footprint (the scratchpad's `device-table.txt` / `app-headroom.txt`) sorted the rest
into tiers, and 0.9.4 takes the top one whole. Decision: **Tier A** is every remaining CIQ ≥ 5.x
round sports watch — epix 2 and epix 2 Pro (42/47/51 mm), Forerunner 255/265/570 (42/47 mm)/955/
965/970, MARQ 2 and MARQ 2 Aviator, Enduro 3, D2 Mach 1 and Mach 2, Descent Mk3 43 mm — because
each of them runs the *current* code unchanged: ≥ 524 KB of watch-app memory against a 67 KB
build, a 100 Hz accelerometer, a round glass at one of the four sizes the layout suite measures,
and the same `has`-guarded GNSS fallback the fenix 7 already exercises. Everything below that
line stays out, and each for its own reason: the **128 KB fenix 5/6 and Enduro 1 bases** would
need the app cut roughly in half (a 108 KB build against a 131 KB ceiling was the survey's
finding — buildable, but with nothing left for a session); the **Instinct family** is a 1 bpp
semi-octagon with a second sub-screen, which is a different UI, not a rescaled one; and the
**rectangles** (Venu X1, epix Gen 1) would need every round-display fitter in `RecordingView`
replaced, since the whole layout suite measures chords. Venu 3 and Vivoactive 5 are excluded on
top of that as non-sports watches. Consequence: 30 products across the app, the field and the
barrel, all four `.iq` exports green with the compiler's per-device memory gate passing; two
real layout bugs surfaced on the way in (see `docs/testing.md` — a digits-only vector face and
the Forerunner font metrics), both fixed for every watch including the ones already shipped.

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

**Pictures, added later, on the same terms.** Some help topics describe a *screen* rather
than a number, and those are the ones that are genuinely hard to follow in words — the
session page's key-metrics block, the turn list, the replay, the share composer, the map's
layer chips. A topic may therefore carry one optional `HelpImage`: an **asset name** and a
one-line caption, nothing else. The kit has no image bundle of its own, so `HelpView`
resolves the name in the app's catalogue
(`ios/WingFoil/Resources/Assets.xcassets/Help/`) and draws it between the summary and the
prose — one `Image`, fit to the width, rounded, no lightbox and no carousel. The cost of
keeping only a name in the kit is that a typo draws *nothing*, silently, in a screen nobody
re-reads; so `PresentationTests` walks the checked-in image sets on disk and fails on a name
that has no `.imageset`, on an `.imageset` with no PNG, and on a caption that is a stub.
A second test pins **which** topics are allowed a picture, because the rule is the decision:
a screenshot of a number does not explain a definition, and a decorative image in a
reference work is a tax on every reader who came for the sentence. The images are captured
from the simulator with the `UI_*` hooks (`docs/testing.md`), cropped to the region the
caption talks about, and kept under 150 KB each — full colour where the budget allows,
because on the two legend shots a shifted chip colour would be a wrong answer rather than a
compression artefact.

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
