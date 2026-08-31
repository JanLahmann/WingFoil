# Fixtures — session corpus & ground truth

Naming: `YYYY-MM-DD-HHMM_<spot>_<source>.fit` (e.g. `2026-08-05-1356_garda_foilmotion.fit`;
start time disambiguates multiple sessions per day).
Sources: `native` (Fenix 8 Windsurf profile) · `wingfoil` (our CIQ app) · `foilmotion` ·
`wingfoiling` (the CIQ app that produced "<location> Wingfoiling" activities) · `gpx`.

- `sessions/windsurf-native/` — Jan's native Windsurf-profile FITs (source class b)
- `sessions/ciq/` — our app's recordings (class a; grows from phase 1)
- `sessions/other-apps/` — FoilMotion / "Wingfoiling" FITs (Walk-typed; parser contrast cases)
- `sessions/gpx/` — GPX imports (class c)
- `sessions/accel/` — sessions that include a SensorLogging accelerometer stream
- `clips/` — 60–180 s FIT cuts around labeled events, for simulator replay (`lab/tools/clip_fit.py`)
- `goldens/` — `<fixture>.expected.json` (schema in `docs/testing.md`)
- `speedreader/` — GPS-Speedreader result exports for the same files (GP3S cross-validation)

## Provenance

Every FIT here is one of Jan's own recordings, kept as it came off the watch — with one
deliberate exception:

| file | provenance |
|---|---|
| `sessions/ciq/2026-08-30-1407_nago-torbole-windsurfen_ciq.fit` | 10 m 45 s early-afternoon Ora, **scrubbed** with `lab/tools/scrub_fit.py` (serials zeroed; `user_profile`, paired-accessory and Garmin-private lifetime blobs dropped; GPS, HR, accelerometer and all 14 developer fields kept, analysis provably identical). This is the file the iOS app and the web app ship as **the bundled example** — `ios/WingFoilKit/…/Resources/ExampleSession.fit` and `web/example/ExampleSession.fit` are byte-identical copies of it. See docs/testing.md, "The bundled example session". |

## Ground-truth table

One row per session, filled by Jan right after the session (< 5 min). This is the labeled
dataset all detectors are tuned against — approximate honesty beats precise guessing; use `?`
where unsure.

| file | spot | wind dir/strength | gear (wing/board/foil) | jibes att/made | tacks att/made | takeoff attempts | pump strokes | crashes | longest flight felt | notes |
|---|---|---|---|---|---|---|---|---|---|---|
| _example:_ 2026-08-07_garda_wingfoil.fit | Garda (Torbole) | N ~18 kn | 4.5 m / 95 L / 1100 cm² | 8/5 | 4/2 | ~12 | ~40 | 3 | ~90 s | HR dropouts mid-session |
| 2026-08-30-1407_nago-torbole-windsurfen_ciq.fit | Nago-Torbole | S (Ora) | ? | ?/10 | 0/0 | 4 | **~26** † | 2 | ~6 min | the bundled example; 10 m 45 s |

† **Not observed — derived.** Nobody counted these on the water; ~26 is what the 2026-08-30
accelerometer trace supports once chop is excluded by hand (the three real bouts of pumping
in the session), and it is the number that exposed the engine's 286 as an artifact
(docs/algorithms.md "The session total"). It is the tuning target for `pumpBurstPeakG`, which
is why that parameter is still marked PROVISIONAL — **a counted-on-the-water number for any
session would replace it.** The on-water protocol (docs/testing.md) now asks for one:
a rough count of how many times you pumped the wing, per takeoff or for the session.
