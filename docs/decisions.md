# Decision Log (ADR-style)

Newest first. One paragraph each: context → decision → consequence.

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
