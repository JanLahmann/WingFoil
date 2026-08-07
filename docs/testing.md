# Testing & Verification

## Golden files

`fixtures/goldens/<fixture>.expected.json` — written by `lab` (`wingfoil_lab.goldens`) once a
notebook result is human-validated; asserted by Python `pytest` (self-check) and Swift
`WingFoilKitTests` (cross-check). Schema (versioned via `engineVersion`):

```json
{
  "engineVersion": "0.2.0",
  "config": { "foilEntrySpeed": 12.0, "...": "params actually used" },
  "capabilities": { "hasDoppler": true, "hasDevFields": false, "hasWatchLaps": false,
                     "hasAccel": false, "hasHR": true, "sampleRateHz": 1 },
  "flights": [ { "startTs": 0, "endTs": 0, "distM": 0.0, "maxKn": 0.0, "takeoffPumps": null } ],
  "turns":   [ { "ts": 0, "endTs": 0, "type": "jibe|tack|turn|bear_away|round_up",
                 "counted": true, "entryKn": 0.0, "minKn": 0.0, "score": 0.0,
                 "success": false, "side": "port|starboard|unknown",
                 "direction": "port|starboard", "netDeg": 0.0, "arcM": 0.0, "radiusM": 0.0,
                 "outcome": "flew_through|touchdown|fell_in", "borderline": false,
                 "offFoilS": 0.0, "stoppedS": 0.0, "pumped": false, "submerged": false,
                 "outcomeWindowS": 0.0 } ],
  "flightEnds": [ { "flightIndex": 0, "ts": 0, "borderline": false,
                    "outcome": "glide_out|touchdown|fell_in|unknown", "offFoilS": 0.0,
                    "stoppedS": 0.0, "minKn": null, "pumped": false, "submerged": false,
                    "windowS": 0.0, "truncated": false, "ownedByTurn": null } ],
  "records": { "best2sKn": 0.0, "best10sKn": 0.0, "best5x10sKn": 0.0, "best100mKn": 0.0,
               "best250mKn": 0.0, "best500mKn": 0.0, "bestNmKn": 0.0, "bestHourKn": 0.0,
               "alpha500Kn": 0.0, "windows": { "best2s": {"startTs": 0, "durS": 2} } },
  "wind":    { "dirDeg": 0, "confidence": 0.0, "source": "estimate|openmeteo|user",
               "axisDeg": 0, "axisConfidence": 0.0, "ambiguityMargin": 0.0,
               "separationDeg": 0.0, "lobesDeg": [0, 0], "lobeMass": [0.0, 0.0],
               "speedAsymmetry": 0.0, "distanceM": 0.0, "usable": true },
  "takeoffs": [ { "startTs": 0, "runStartTs": 0, "pumps": null, "success": true,
                  "timeToFoilS": 0.0, "speedRiseS": 0.0, "entryKn": 0.0,
                  "cadenceSpm": null, "inFlightStrokes": null, "free": false,
                  "truncated": false, "preWindowS": 0.0 } ],
  "summary": { "foilTimeS": 0, "foilPct": 0.0, "flightCount": 0, "longestFlightS": 0,
               "longestFlightM": 0.0, "distanceKm": 0.0,
               "turns":       { "tacks": 0, "jibes": 0, "unclassified": 0, "rejected": 0,
                                "turnsCounted": 0, "turnsSuccessful": 0, "successPct": 0.0,
                                "port": 0, "starboard": 0,
                                "outcomes": { "flewThrough": 0, "touchdown": 0,
                                              "fellIn": 0, "borderline": 0 },
                                "tackOutcomes": {}, "jibeOutcomes": {} },
               "flightEnds":  { "all": { "glideOut": 0, "touchdown": 0, "fellIn": 0,
                                         "unknown": 0, "borderline": 0 },
                                "straight": {}, "inTurn": {} },
               "outcomeSplit": { "turnFalls": 0, "straightFalls": 0, "turnTouchdowns": 0,
                                 "straightTouchdowns": 0, "glideOuts": 0, "unknownEnds": 0 },
               "takeoff":     { "takeoffAttempts": 0, "takeoffSuccesses": 0,
                                "avgPumpsToTakeoff": null, "totalPumpStrokes": null,
                                "successPct": null, "failedAttempts": 0, "...": "" } }
}
```

`wind` is `null` when the COG distribution yields no usable axis. Source capabilities
degrade the schema, they never omit it: without an accelerometer every stroke count
(`takeoffPumps`, `takeoffs[].pumps`, `totalPumpStrokes`) and `takeoff.successPct` is an
explicit **null** — "unknown", not zero, and not a flattering 100 %. Without a barometer
no turn or flight end is ever `submerged`. Smart-Recording truncation leaves flight ends
`unknown` and takeoff runs `truncated`, both excluded from the tallies.

## Tolerances (Swift & Python vs goldens)

| quantity | tolerance |
|---|---|
| counts (flights, turns, attempts, strokes) | exact |
| verdicts (turn type/outcome, flight-end outcome, ownership) | exact |
| timestamps | ± 1 s |
| speeds (records, turn entry/minimum) | ± 0.05 kn (alpha ± 0.1 kn) |
| angles (wind direction/axis, turn net sweep) | ± 1° |
| percentages (turn success, takeoff success) | ± 0.5 |
| foil time | ± 2 % |
| watch live vs phone recompute | ± 0.2 kn, counts exact on clean clips |

Non-qualifying records (no window of the required length/shape exists — e.g. 1 h in a short
session, alpha with no qualifying loop): goldens serialize **0.0**, the Swift model uses
**nil**; comparisons treat any value < 0.05 kn as "absent" and the two as equivalent.

## Layers

1. **lab pytest** — regenerate goldens, assert self-consistency (guards refactors);
   `compare_speedreader.py` diffs GP3S numbers vs `fixtures/speedreader/` exports on every
   fixture (drift > tolerance fails).
2. **WingFoilKitTests (Swift Testing)** — full pipeline on fixtures vs the same goldens;
   parser fail-soft tests (missing channels, truncated FIT, foreign-app FITs); importer test with
   a synthetic nested GDPR ZIP.
   Library-depth suites (phase 4, all on real fixture FITs):
   - `MigrationTests` — a database migrated only `upTo: "v1"` is filled the way the v1 app
     did (raw rows + archived FITs), then opened as the current `AppDatabase`. Asserts the
     v2 tables/columns exist, that every v1 row comes out **stale** (`engineVersion` NULL,
     the same trigger an engine bump uses), that `reanalyzeStale()` re-derives them exactly
     once and fills `flight`/`turn`/`takeoff_attempt`/`record_effort`/`spot`, and that
     deleting a session cascades.
   - `LibraryTests` — the ±60 s/±60 s dedupe key under jitter (45 s ⇒ duplicate, 120 s ⇒
     new session); spot clustering on synthetic fixes *and* on the corpus (Nago-Torbole vs
     Rheinstetten), rename-survives-recluster, offline naming fallback; the `record_effort`
     PB history (all-time max, chronological series, strictly increasing PB step curve,
     per-spot/per-gear filtering, no duplicate efforts after re-analysis); gear combos
     (default = last used, one slot per kind, per-gear aggregates); zero-filled week buckets.
   - `GdprImportTests` — a synthetic Garmin export (ZIP of ZIPs holding two fixture FITs, a
     gzipped member, JSON noise, `__MACOSX` junk and one unreadable FIT): every session
     imported exactly once, incremental progress callbacks, `import_log` rows, a **re-run
     that imports nothing** (the phase-4 acceptance criterion), the depth limit, and
     streaming-vs-collecting walker agreement.
3. **Monkey C units (Toybox.Test)** — RingBuffer math; FlightDetector/TurnDetector fed synthetic
   + recorded 1 Hz speed/COG arrays (extracted from fixtures by lab) asserting exact transition
   ticks; PumpDetector fed recorded 25 Hz batches; SpeedRecords vs hand-computed windows.
4. **Simulator integration smoke** — FIT replay of `fixtures/clips/` (60–180 s cuts around
   labeled events; replay is realtime-only, keep clips ≤ 3 min) with a documented expected
   checklist per clip: flights detected, laps emitted, PB alert fired. Plus MonkeyGraph preview
   of dev-field charts.
5. **Beta App upload (phase 1–2)** — alternate-UUID listing; the only way to verify GCM settings
   UI and `fitContributions` rendering in Garmin Connect. Do early.
6. **Watch-vs-phone divergence banner** — standing field-regression alarm on every class-(a)
   import (thresholds in `algorithms.md`).

## On-water protocol (Jan, < 5 min per session)

Before: set wind-direction guess (watch menu or phone) + gear.
After, into `fixtures/README.md` ground-truth table: jibes attempted/made · tacks
attempted/made · takeoff attempts (approx) · crashes · "longest flight felt like" · wind
direction/strength · gear · anything odd (GPS, HR, app). Compare with app output; every
discrepancy becomes a tuning issue referencing the session file. Every session grows the corpus.
