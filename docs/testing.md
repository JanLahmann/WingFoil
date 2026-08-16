# Testing & Verification

## Golden files

`fixtures/goldens/<fixture>.expected.json` — written by `lab` (`wingfoil_lab.goldens`) once a
notebook result is human-validated; asserted by Python `pytest` (self-check) and Swift
`WingFoilKitTests` (cross-check). Schema (versioned via `engineVersion`):

```json
{
  "engineVersion": "0.3.0",
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
  "pumpEpisodes": [ { "startTs": 0, "endTs": 0, "strokes": 0,
                      "outcome": "success|failed|recovery|in_flight|unknown",
                      "bursts": 1, "flightIndex": null, "turnIndex": null,
                      "lookaheadS": 0.0 } ],
  "hr":      { "hasHR": true,
               "takeoffEvents": [ { "kind": "takeoff|swim", "index": 0, "ts": 0,
                                    "approximate": false, "strokes": null,
                                    "baselineBpm": null, "peakBpm": null, "costBpm": null,
                                    "peakLagS": null, "baselineCoverage": 0.0,
                                    "peakCoverage": 0.0, "recoveryHalfS": null,
                                    "recoveryCensored": false } ],
               "swimEvents": [],
               "bins": [ { "startTs": 0, "endTs": 0, "attempts": 0, "successes": 0,
                           "failed": 0, "successPct": null, "avgCostBpm": null,
                           "medianCostBpm": null, "costValid": 0, "costTotal": 0,
                           "avgBaselineBpm": null, "avgPumps": null, "meanBpm": null } ],
               "summary": { "usablePct": null, "avgTakeoffCostBpm": null,
                            "takeoffCostValid": 0, "takeoffCostTotal": 0,
                            "pumpCruise": { "pumpingBpm": null, "cruisingBpm": null,
                                            "deltaBpm": null, "...": "" }, "...": "" } },
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
`unknown` and takeoff runs `truncated`, both excluded from the tallies. The `hr` block
(docs/algorithms.md "HR cost") is written for **every** source: a session with no heart-rate
channel gets `hasHR: false` beside empty lists and null averages, never a missing block —
"this source had no HR" and "this golden predates the block" must not look the same. Inside
it, an unmeasurable window is null throughout (`baselineBpm`, `costBpm`, `avgTakeoffCostBpm`,
`bpmPerStroke`, …) and never 0.0, which would read as "this attempt was free"; the
`<name>Valid`/`<name>Total` pair beside each average is the `n valid / n total` that says how
much of the session it actually speaks for. `pumpEpisodes` (engine 0.3.0, docs/algorithms.md
"Takeoff analysis") carries **every** classified pumping effort, not only the failed ones: the
`summary.takeoff` tallies count the five buckets, and this list is the same classification with
its *instants* attached, which is what lets iOS place a failed attempt on the map instead of
apologizing for it. It degrades like `turns` — a source with no accelerometer has no bursts to
classify and gets `[]`, written rather than omitted.

## Presentation goldens

`fixtures/presentation/<fixture>.expected.json` — the second golden set, one per analysis
golden, generated by `web/tools/make_presentation_goldens.py` (`--check` fails when stale).
They carry no metric: only what a session-detail screen is *allowed to draw* from the
analysis of the same name — markers per layer, the takeoff layer's pumped/free/failed
split, the splash count, pump-burst spans, the achieved record windows and the full
3 × 3 turn-filter grid (type × entry side, with the flew-through numerator).

The rules they apply are `docs/presentation.md` "Marker eligibility", and both sides assert
them: Swift in `PresentationTests.presentationGoldensPinEveryMarkerAndFilterCount` (through
`PresentationFacts`, the kit-side home of the rules that `SessionDetail`'s builders
iterate), Python in `web/tools/verify_presentation.py`, which re-derives every count a
second way and then re-runs the engine through `web_entry` on the CIQ fixture to prove the
numbers survive the path the browser actually takes. A count that differs between the two
is a failing test, not a bug report.

The presentation *values* — colours and glyph names — are enforced separately, by
`design/tokens.json` plus `design/check_tokens.py --check` (CI: `.github/workflows/tokens.yml`
and the Pages deploy).

## Tolerances (Swift & Python vs goldens)

| quantity | tolerance |
|---|---|
| counts (flights, turns, attempts, strokes) | exact |
| verdicts (turn type/outcome, flight-end outcome, ownership) | exact |
| pump episodes (list length **and order**, outcome, strokes, bursts, flightIndex/turnIndex) | exact; their `startTs`/`endTs`/`lookaheadS` ± 1 s |
| timestamps | ± 1 s |
| speeds (records, turn entry/minimum) | ± 0.05 kn (alpha ± 0.1 kn) |
| angles (wind direction/axis, turn net sweep) | ± 1° |
| percentages (turn success, takeoff success, HR coverage/usable share) | ± 0.5 |
| heart rates and coverage shares (HR cost, baseline, peak, pumping/cruising) | ± 0.05 bpm |
| bpm per stroke (a ratio of two of the above) | ± 0.005 |
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
   - `PresentationTests` — the phase-5 UI layer's *logic*, which is exactly the code whose
     mistakes are invisible in a screenshot. Help-catalogue completeness (every
     `HelpTopicID` case has written content, no duplicate or dangling topic links, search
     hits body and item text); the share card's content (always four stat cells, "—" rather
     than a fabricated 0.00 kn, the uncertified disclaimer); thumbnail geometry (aspect
     preserved — a straight-line track must land in a band, not stretched over the box; runs
     split at the phase change and share a vertex; the sparkline bucketed by **max** so a
     single fast reach survives thinning; each half degrades on its own; a degenerate track
     stays finite; the on-disk cache round-trips and a version bump invalidates it); PB
     detection (float noise is not a record, the *first* import celebrates nothing, an
     uncertified source never celebrates); the tappable map legend's visibility model
     (everything visible by default and after an unreadable or unknown stored value;
     toggling one chip touches only that category; the round trip through `UserDefaults`,
     including turning categories back **on**; a hidden *line* category degrades to the
     neutral route rather than erasing the track, while the other phase keeps its tint; a
     category with no instances in the session is not a toggle); and the widget snapshot
     (7-day window, the
     `foilTimeS`→`foilPct` fallback for pre-v2 rows, encode/decode round-trip, and the
     invariant that the store never claims the shared container it does not have).
   - `GdprImportTests` — a synthetic Garmin export (ZIP of ZIPs holding two fixture FITs, a
     gzipped member, JSON noise, `__MACOSX` junk and one unreadable FIT): every session
     imported exactly once, incremental progress callbacks, `import_log` rows, a **re-run
     that imports nothing** (the phase-4 acceptance criterion), the depth limit, and
     streaming-vs-collecting walker agreement.
   - `ExampleSessionTests` — the session bundled with the app so a fresh install has
     something to explore (`ExampleSession`, kit resource `Resources/ExampleSession.fit`).
     Three obligations, all asserted against the **bundled bytes** rather than the repo
     copy, because what ships is what matters: the scrub (no `serial_number` field
     survives; the strings `Lahmann` / `AirPods` and the watch serial in both byte orders
     are absent from the raw file; it still parses as class (a)); the analysis (it still
     yields ≥ 20 flights, ≥ 25 jibes, > 10 kn best-2 s, HR, accel-derived pump strokes, a
     wind estimate and a GPS start fix, with `flight`/`turn`/`record_effort` filled); and
     the `isExample` flag (set on import, round-tripped through SQLite, deletable, and
     invisible to `records()`, `trend()`, `sessions()`, `weeks()` and the gear rollups
     while a real session next to it still reaches all of them). Plus the v3 migration
     (column added, pre-v3 rows default to *not* an example) and the written copy.
   - `OnboardingTests` — the intervals.icu first run, which by definition is walked once
     per install and never again: `IcuSetupGuide` is four numbered, written steps (the Help
     topic and the empty-library setup card render the *same* array, asserted, so the
     manual and the wizard cannot drift); the failure→cause mapping behind every message
     the card can show (401/403 ⇒ "regenerate the key", `URLError`/transport ⇒ network and
     explicitly *not* the key, other HTTP ⇒ status only — **the response body never reaches
     the screen**, and no message, hint or crumb may contain the key itself); a sync that
     returned nothing ⇒ "connect Garmin in intervals.icu" rather than silence; the key
     check against a stubbed transport (counts activities *and* watersports, and a valid
     key with no watersports reports the caveat instead of claiming success); and
     `IcuOnboarding.state` (empty + no key ⇒ setup card, key + stored problem ⇒ that cause,
     key + nothing yet ⇒ waiting, any session at all ⇒ never onboarding), with the problem
     round-tripping through JSON so the card still names the cause after a relaunch.

   iOS screenshot hooks (DEBUG **and** simulator only, passed as `SIMCTL_CHILD_…`
   environment variables to `xcrun simctl launch`): `UI_RESET=1` restores the fresh-install
   state — keychain key, sync history, PB snapshot, database and FIT archive all removed —
   and `UI_ICU_KEY=…` seeds a key through the real keychain path afterwards, so the
   first-run setup card and the "key stored, sync rejected" card can both be captured
   without reinstalling. `UI_IMPORT_FIXTURES=1`, `UI_OPEN_SESSION=latest|<name>`,
   `UI_TAB=records|trends|gear`, `UI_SHEET=help|settings` and
   `UI_HELP_TOPIC=<HelpTopicID>` park the app on a given screen, since `simctl` cannot tap.
   `UI_LOAD_EXAMPLE=1` taps the setup card's "Load an example session first" button, and
   `UI_SCROLL_TO=setup` parks the (screen-and-a-half tall) onboarding card on its bottom
   edge — the only way to photograph that button, which lives below the key field.
   On the Trends tab `UI_SCROLL_TO=sideSuccess` parks the screen on the port/starboard
   turn-success chart. On the session page,
   `UI_SCROLL_TO=<anchor>` (`chart` for the speed chart, `replay`, `summary`, `turns` for
   the turn cards and the drill-in row, `takeoff`, `hr` for the HR-cost card, `gear`),
   `UI_PLAYHEAD=0.0…1.0`,
   `UI_FULLSCREEN_MAP=1` and `UI_HIDE_LAYERS=<MapLayer,…>` stage the session detail page:
   the last one starts with those legend chips switched off (e.g. `fellIn,courseChange`,
   or one of the layers added later — `pumping`, `takeoff`, `splash`, `direction`), which
   is the only way to photograph a filtered map without a finger. It is applied *after* the stored
   preference and never written back — the override stages a screenshot, it does not edit
   the setting. `UI_RECORD=<window key>` (`best10s`, `best250m`, `bestNm`, …) preselects a
   non-default GP3S window so the map glow and the chart shading can be photographed on
   something other than the best 2 s. `UI_OPEN_TURNS=1` pushes the turns drill-in page and
   `UI_TURN_FILTER=<jibes|tacks|both>,<port|starboard|both>` engages its two segmented
   filters (e.g. `jibes,starboard`), which `simctl` likewise cannot tap.
   Two more exist because the zoom features are *gestures*, and `simctl` has no fingers to
   pinch with. `UI_CHART_ZOOM=<factor>` opens the speed chart already zoomed by that factor
   (e.g. `8`), centred on `UI_PLAYHEAD` when one is set — pair the two to photograph a
   deliberately busy stretch with its markers legible, rather than whatever happens to sit
   mid-session. `UI_MAP_ZOOM=<factor>` tightens both maps' opening camera by that factor
   about the same centre; it is the only way to check the direction chevrons at a second
   scale, since their spacing is measured in screen points and therefore *changes* with the
   camera. Both are staging-only, transient, and never written back to any preference.
3. **Monkey C units (Toybox.Test)** — the core suite lives in the `WingFoilCore` barrel
   (`garmin/barrel/WingFoilCore/tests/`) and is therefore compiled into **both** consumers'
   `--unit-test` builds: `bin/WingFoilTests.prg` (device app: 16 tests) and
   `bin/WingFoilFieldTests.prg` (data field: those 16 plus the field's own schema/feed/layout
   tests). Contents: RingBuffer math; FlightDetector/TurnDetector fed synthetic
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

## The bundled example session

A fresh install has an empty library, an empty Records screen and no reason to trust any of
it. So one real recording ships inside the app —
`ios/WingFoilKit/Sources/WingFoilKit/Resources/ExampleSession.fit`, a **kit** resource
rather than an app resource so `Bundle.module` reaches it from both the shipping app and
the test suite (no `project.yml` change is needed; Xcode embeds the SPM resource bundle).

**Source and scrub.** It is Jan's 2026-08-07 Nago-Torbole CIQ session, donated with the HR
stream, run through `lab/tools/scrub_fit.py`:

```
cd lab
uv run python tools/scrub_fit.py \
    ../fixtures/sessions/ciq/2026-08-07-0754_nago-torbole-windsurfen_ciq.fit \
    ../ios/WingFoilKit/Sources/WingFoilKit/Resources/ExampleSession.fit
```

The tool does **not** re-encode — no encoder in the lab round-trips 14 developer fields, a
`developer_data_id`, 16 588 batched `accelerometer_data` messages and a dozen Garmin-private
global message numbers. It walks the FIT record stream itself (definition messages, normal
and compressed-timestamp data records, developer field blocks), drops selected messages,
overwrites selected fields in place with their base type's *invalid* pattern, and recomputes
`data_size`, the header CRC and the file CRC. Every surviving byte came from the original.

| what | action | why |
|---|---|---|
| `file_id.serial_number`, `device_info.serial_number` (×5) | → 0 (uint32z invalid) | unique watch id |
| `user_profile` (global 3) | dropped | name, weight, height, gender, language |
| global 147 | dropped | paired-accessory BLE address + its name |
| global 79, global 140 | dropped | Garmin-private lifetime totals / physiological metrics |
| GPS, HR, developer fields, laps, session, 100 Hz accel | **kept** | that is the whole point |

Verification is built into the tool (`--verify`, default): it re-runs the full lab analysis
on both files and asserts the golden JSON is **identical**. It is — so the scrub is provably
invisible to the engine. Size 6 184 873 → 6 184 526 bytes; under the 8 MB bundle budget, so
the accelerometer stream stays and the phone's pump recompute works on the example.
(`--drop-accel` produces the stripped variant if that ever changes; the summary then keeps
the watch's packed pump/takeoff fields and `SourceCapabilities` reports `hasAccel: false`.)

**Provenance flag.** Sessions imported from it carry `session.isExample` (schema v3) and
`importSource = "example"`. They are shown in the library — badged `EXAMPLE`, openable,
deletable — and excluded from every aggregate that speaks for the rider: `LibraryStore`
filters them in `clause()` (Records, Trends, week buckets) and in the gear rollups, the
widget snapshot drops them, and they are never given the default gear combo nor written to
Apple Health.

**Dedupe decision.** The example is a *real* recording, so its owner will one day import it
for real and land on the ±60 s dedupe key. That resolves **in favour of the real import**:
`SessionIngestor.note` clears `isExample`, merges the sources (`"example+icu"`) and the row
rejoins Records and Trends — the alternative would permanently exclude the rider's own
session because a demo got there first. The reverse never fires: loading the example when
that ride is already in the library returns `.duplicate` and leaves the real row alone.
Note that the *archived* FIT stays whichever arrived first; since the analysis output is
byte-identical, the only difference is the scrubbed ids.

## On-water protocol (Jan, < 5 min per session)

Before: set wind-direction guess (watch menu or phone) + gear.
After, into `fixtures/README.md` ground-truth table: jibes attempted/made · tacks
attempted/made · takeoff attempts (approx) · crashes · "longest flight felt like" · wind
direction/strength · gear · anything odd (GPS, HR, app). Compare with app output; every
discrepancy becomes a tuning issue referencing the session file. Every session grows the corpus.
