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

## Ground-truth table

One row per session, filled by Jan right after the session (< 5 min). This is the labeled
dataset all detectors are tuned against — approximate honesty beats precise guessing; use `?`
where unsure.

| file | spot | wind dir/strength | gear (wing/board/foil) | jibes att/made | tacks att/made | takeoff attempts | crashes | longest flight felt | notes |
|---|---|---|---|---|---|---|---|---|---|
| _example:_ 2026-08-07_garda_wingfoil.fit | Garda (Torbole) | N ~18 kn | 4.5 m / 95 L / 1100 cm² | 8/5 | 4/2 | ~12 | 3 | ~90 s | HR dropouts mid-session |
