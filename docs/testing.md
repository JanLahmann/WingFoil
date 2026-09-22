# Testing & Verification

## Getting started on a second machine

Every check in this file is reachable from the `Makefile` at the repository root, and every
recipe in it is a command written down here or in `web/README.md`. `make -n <target>` prints
the command without running it, which is the fastest way to see what a target really does.

```sh
make all            # lab-test, kit-test, web-verify, ios-build — everything unattended
make lab-test       # cd lab && uv run pytest -q
make kit-test       # cd ios/WingFoilKit && swift test
make ios-build      # xcodegen, then the three channels with signing off
make web-verify     # bundle_lab --check, verify_links, check_release_copy, check_voice
make web-bundle     # regenerate web/lab_bundle after an engine change
make garmin-package # garmin/tools/package.sh, the three .iq files
```

The toolchain the repo pins, and what a second machine therefore needs: Xcode 26.6 (the
project asks for Swift 6.0 and iOS 18.0), XcodeGen 2.46.0 and at least 2.42.0
(`minimumXcodeGenVersion` in `ios/project.yml`), uv 0.11.19, Python 3.12 and at least 3.11
(`requires-python` in `lab/pyproject.toml`), and Connect IQ SDK 9.2 for the watch. `uv`
creates `lab/.venv` itself on the first `make lab-test`.

**Two things a clean checkout cannot do, and why `make all` leaves them out.**
`garmin-package` signs with `garmin/developer_key.der`, which is Jan's and is not in the
repo, so it would fail through no fault of the checkout. And three of the web checks need
that lab venv plus the fixture corpus rather than the stdlib, so they are run by hand from
`lab/.venv/bin/python` when the engine moves: `web/tools/verify_web_entry.py`,
`verify_library.py` and `verify_presentation.py`. `web/README.md` "Verification" lists all
thirteen web checks and says which of them `verify_links.py` already runs for you.

**The turn drawing has one of its own**, `web/tools/verify_turn_figure.py`, and it is
stdlib plus `node`. The turn page and the flight-end page draw one maneuver at its own
scale, and everything about that picture that can be wrong is arithmetic: the projection
into local metres, the bearing on each vertex, the wind-up rotation, the padded frame, the
three speed marks, the speed ramp, the scale bar, the angle series and the foil spans. The
kit holds those rules in `TurnSliceTests`; this runs the browser's port of them
(`web/js/maneuverfigure.js`, through `web/tools/turn_figure.mjs`) over a synthetic quarter
circle and re-derives every number from the Swift. The session is synthetic because it has
to be: an analysis golden carries the turn records but not the positional view the browser
draws from, so there is no reachable JSON of one real turn's drawn extents.

## Golden files

`fixtures/goldens/<fixture>.expected.json` — written by `lab` (`wingfoil_lab.goldens`) once a
notebook result is human-validated; asserted by Python `pytest` (self-check) and Swift
`WingFoilKitTests` (cross-check). Schema (versioned via `engineVersion`):

```json
{
  "engineVersion": "0.15.0",
  "config": { "foilEntrySpeed": 12.0, "...": "params actually used" },
  "capabilities": { "hasDoppler": true, "hasDevFields": false, "hasWatchLaps": false,
                     "hasAccel": false, "hasHR": true, "sampleRateHz": 1 },
  "flights": [ { "startTs": 0, "endTs": 0, "distM": 0.0, "maxKn": 0.0, "takeoffPumps": null } ],
  "turns":   [ { "ts": 0, "endTs": 0, "minTs": 0,
                 "type": "jibe|tack|turn|bear_away|round_up",
                 "counted": true, "entryKn": 0.0, "minKn": 0.0, "exitKn": 0.0, "score": 0.0,
                 "success": false, "clean": false, "side": "port|starboard|unknown",
                 "direction": "port|starboard", "netDeg": 0.0, "peakRateDegS": 0.0,
                 "twaInDeg": null, "twaOutDeg": null,
                 "axisTs": null, "axisBeforeDeg": null, "axisAfterDeg": null,
                 "arcM": 0.0, "radiusM": 0.0,
                 "outcome": "flew_through|touchdown|fell_in", "borderline": false,
                 "offFoilS": 0.0, "stoppedS": 0.0, "pumped": false, "submerged": false,
                 "outcomeWindowS": 0.0 } ],
  "flightEnds": [ { "flightIndex": 0, "ts": 0, "borderline": false,
                    "outcome": "glide_out|touchdown|fell_in|unknown", "offFoilS": 0.0,
                    "stoppedS": 0.0, "minKn": null, "pumped": false, "submerged": false,
                    "windowS": 0.0, "truncated": false, "ownedByTurn": null } ],
  "submersions": [ { "ts": 0, "endTs": 0, "durationS": 0.0, "dropM": 0.0,
                     "turnIndex": null, "flightEndIndex": null } ],
  "records": { "best2sKn": 0.0, "best10sKn": 0.0, "best5x10sKn": 0.0, "best100mKn": 0.0,
               "best250mKn": 0.0, "best500mKn": 0.0, "bestNmKn": 0.0, "bestHourKn": 0.0,
               "alpha500Kn": 0.0, "windows": { "best2s": {"startTs": 0, "durS": 2} } },
  "wind":    { "dirDeg": 0, "confidence": 0.0, "source": "estimate|openmeteo|user",
               "axisDeg": 0, "axisConfidence": 0.0, "ambiguityMargin": 0.0,
               "separationDeg": 0.0, "lobesDeg": [0, 0], "lobeMass": [0.0, 0.0],
               "speedAsymmetry": 0.0, "turnTypeMargin": 0.0, "turnTypeDirDeg": null,
               "turnTypeVotes": 0, "priorFlipped": false,
               "distanceM": 0.0, "usable": true },
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
               "summary": { "usablePct": null,
                            "avgTakeoffCostBpm": null, "medianTakeoffCostBpm": null,
                            "takeoffCostValid": 0, "takeoffCostTotal": 0,
                            "approximateTakeoffs": 0, "medianPeakLagS": null,
                            "bpmPerStroke": null, "medianBpmPerStroke": null,
                            "bpmPerStrokeValid": 0, "bpmPerStrokeTotal": 0,
                            "pumpCruise": { "pumpingBpm": null, "cruisingBpm": null,
                                            "deltaBpm": null,
                                            "pumpingSpans": 0, "cruisingSpans": 0,
                                            "pumpingCoveredS": 0.0, "pumpingSpanS": 0.0,
                                            "cruisingCoveredS": 0.0, "cruisingSpanS": 0.0 },
                            "medianTakeoffRecoveryS": null,
                            "takeoffRecoveryValid": 0, "takeoffRecoveryTotal": 0,
                            "medianSwimRecoveryS": null,
                            "swimRecoveryValid": 0, "swimRecoveryTotal": 0,
                            "avgSwimCostBpm": null,
                            "swimCostValid": 0, "swimCostTotal": 0 } },
  "summary": { "foilTimeS": 0, "foilPct": 0.0, "flightCount": 0, "longestFlightS": 0,
               "maxFlightM": 0.0, "distanceKm": 0.0,
               "durationS": 0.0, "timerTimeS": 0.0,
               "avgSpeedKmh": null, "turnsPerHour": null,
               "jibesPerHour": null, "cleanJibesPerHour": null, "wetPerHour": null,
               "windowRates": { "windowMin": 15, "bestJph": null, "bestJphStartTs": null,
                                "bestWph": null, "bestWphStartTs": null,
                                "series": [ { "ts": 0, "jph": 0.0, "wph": 0.0 } ] },
               "turns":       { "tacks": 0, "tacksSuccessful": 0,
                                "jibes": 0, "jibesSuccessful": 0,
                                "unclassified": 0, "rejected": 0,
                                "turnsCounted": 0, "turnsSuccessful": 0, "successPct": 0.0,
                                "port": 0, "starboard": 0, "unknownSide": 0,
                                "longestDryStreak": 0, "longestFlewStreak": 0,
                                "outcomes":     { "flewThrough": 0, "touchdown": 0,
                                                  "fellIn": 0, "borderline": 0 },
                                "tackOutcomes": { "flewThrough": 0, "touchdown": 0,
                                                  "fellIn": 0, "borderline": 0 },
                                "jibeOutcomes": { "flewThrough": 0, "touchdown": 0,
                                                  "fellIn": 0, "borderline": 0 } },
               "flightEnds":  { "all":      { "glideOut": 0, "touchdown": 0, "fellIn": 0,
                                              "unknown": 0, "borderline": 0 },
                                "straight": { "glideOut": 0, "touchdown": 0, "fellIn": 0,
                                              "unknown": 0, "borderline": 0 },
                                "inTurn":   { "glideOut": 0, "touchdown": 0, "fellIn": 0,
                                              "unknown": 0, "borderline": 0 } },
               "outcomeSplit": { "turnFalls": 0, "straightFalls": 0, "turnTouchdowns": 0,
                                 "straightTouchdowns": 0, "glideOuts": 0, "unknownEnds": 0 },
               "takeoff":     { "takeoffAttempts": 0, "takeoffSuccesses": 0,
                                "successPct": null, "failedAttempts": 0,
                                "unknownAttempts": 0, "recoveryEpisodes": 0,
                                "inFlightEpisodes": 0, "inFlightPumpStrokes": null,
                                "runsJudged": 0, "runsTruncated": 0,
                                "freeTakeoffs": 0, "pumpedTakeoffs": 0,
                                "avgPumpsToTakeoff": null, "medianPumpsToTakeoff": null,
                                "avgPumpsWhenPumped": null, "totalPumpStrokes": null,
                                "avgTakeoffS": null, "medianTakeoffS": null } }
}
```

`wind` is `null` when the COG distribution yields no usable axis. Source capabilities
degrade the schema, they never omit it: without an accelerometer every stroke count
(`takeoffPumps`, `takeoffs[].pumps`, `totalPumpStrokes`) and `takeoff.successPct` is an
explicit **null** — "unknown", not zero, and not a flattering 100 %. Without a barometer
no turn or flight end is ever `submerged` and `submersions` is empty. Smart-Recording
truncation leaves flight ends
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
classify and gets `[]`, written rather than omitted. The **session rates** (engine 0.6.0,
docs/algorithms.md "Session rates") share the same never-a-flattering-zero rule: `durationS`
is the elapsed span of the cleaned track, gaps included, and when it is ≤ 0 all five derived
rates are explicit **null** — "there is no hour to divide by", not "he did nothing in one".
`wetPerHour` is every `fell_in` *flight end*, straight-line and turn-owned alike, which is a
different (and on this corpus a much larger) number than the turn ladder's fallen turns;
`jibesPerHour` is the **dry** jibes only (engine 0.7.0) — `jibes - jibeOutcomes.fellIn` —
because a rate a rider can raise by falling more often is not a measure of his afternoon, and
`cleanJibesPerHour` (engine 0.10.0) is the strict reading of the same set, `jibesSuccessful`
over the same hour — the one the key-metrics block prints.
`windowRates` (engine 0.7.0) is the same two event channels over a rolling 15-minute window:
a 60 s series of full windows, and the two exact sliding peaks, which are anchored on the
events and so are never below the series they sit beside. Its peaks obey the **mirror** of
the zero rule — never a flattering *peak*: only windows lying wholly inside the session
count, and a session shorter than the window reports its own whole-session rate over the span
it lasted rather than a fragment scaled up to the hour.
The five per-turn fields added in engine 0.11.0 — `minTs`, `exitKn`, `peakRateDegS`,
`twaInDeg`, `twaOutDeg` — are all things the detector had computed since 0.1.0 and thrown
away, so **no existing number on any fixture moves**; the whole of the change is that a turn
now records its shape and not only its two endpoints. `minTs` is on the session clock like
`ts`/`endTs`; `exitKn` is the maneuver channel at the first sample at or after `endTs`, the
same channel and scale as `minKn`, so entry → min → exit reads as one line;
`peakRateDegS` is **signed** with `netDeg`'s convention (+ = clockwise). The TWA pair obeys
the same never-a-flattering-zero rule as everything else here: without a usable wind axis it
is explicit **null**, because a 0.0 would read as "dead upwind", which is a claim.

Engine 0.12.0 adds one per-turn key, `clean`, and is the first bump in this schema that
**moves numbers on purpose**. A *clean jibe* is now `counted && type == "jibe" && success &&
outcome == "flew_through"` (docs/algorithms.md, glossary) rather than `success` alone, so
`turns.jibesSuccessful` — and therefore `summary.cleanJibesPerHour` — fell on eleven of the
seventeen fixtures. `success` is unchanged and still per turn; `tacksSuccessful`,
`turnsSuccessful` and `successPct` still read it, so those did not move, and neither did any
parameter, score, outcome or streak. Exactly four things changed on any fixture: the
`engineVersion` stamp, the new `clean` key on every turn, `turns.jibesSuccessful`, and
`summary.cleanJibesPerHour`. The Swift cross-check asserts `clean` per turn *and* re-derives
it from the four fields, so a golden that carries the key cannot carry a wrong one.

Engine 0.13.0 moves four things at once, and every number in `summary` with them.
`summary.timerTimeS` is a **new key** (T2: the sum of the non-gap steps) and it is now the
denominator of `avgSpeedKmh` and of all four per-hour rates; `summary.durationS` (T1, the
elapsed cleaned span) keeps its meaning and is what every surface still *displays*, so the
two clocks are two named keys and the null-on-no-duration rule reads `timerTimeS <= 0`.
`turnsPerHour` counts **dry** counted turns (`turnsCounted − turns.outcomes.fellIn`), the
rule JPH has used since 0.7.0. `turnClassifyMinAngle` (90°) joins the config echo and files
every sweep narrower than it as an uncounted course change, wind axis or not — five sweeps
in a thousand on the corpus, and no clean jibe moved. `turnOutcomeWindow` drops 60 s → 12 s,
which is where most of the movement is: a fall a quarter of a minute past a sweep is now a
straight-line fall, so the jibe ladder's `fellIn` collapses into `touchdown` (106 → 32 and
128 → 197 across the seventeen fixtures) and the HR block's swim events move with it. And
`summary.longestFlightM` is renamed **`maxFlightM`** — same value, honester name: it is the
largest distance any one flight covered and never was the longest flight's own. The rolling
`windowRates` are deliberately untouched and stay on the elapsed clock.

Engine 0.14.0 moves **one** threshold: `turnPeakRate` 25 → **18 °/s**, so the carved jibes
the peak gate rejected are counted (a carve at 11 kn holds a steady ~13 °/s and never spikes
the way a pivot does). Across the seventeen fixtures jibes go 499 → 538, clean jibes
152 → **160**, course changes 99 → 147 and straight-line falls 58 → 45 — every number a
rider reads moves the right way, and no session loses a clean jibe.

`turnMaxDuration` was measured at 12 s in the same pass and **kept at 8 s**: on top of the
new floor it buys 6 jibes and costs 26 clean ones, because a longer sweep pulls the slow
exit into the scored minimum. A carve running past 8 s is reported as its first 8 s, so a
10 s 150° jibe is counted as a 135° one — still a jibe, which is the verdict that matters.

Turn counts, outcomes, streaks, all four session rates, `windowRates` and the HR block's swim
events move with the new floor; **`flights`, `records`, `wind`, `takeoffs` and `pumpEpisodes`
are byte-identical**, which is the check that says the change is confined to the turn channel.

Engine 0.15.0 makes the **wind-axis crossing** an event and **moves no number at all**. Three
keys join each entry of `turns` — `axisTs`, `axisBeforeDeg`, `axisAfterDeg` (docs/algorithms.md,
"The crossing, as an event") — and two join `config`: `turnAxisBeforeDeg` and
`turnAxisAfterDeg`, both **0**, i.e. off. The diff between a 0.14.0 golden and a 0.15.0 one is
therefore exactly the `engineVersion` stamp, the two config keys and the three per-turn keys,
and nothing else on any of the seventeen fixtures — which is the check that says the crossing is
a measurement being *recorded* rather than a threshold being moved. The three obey the
never-a-flattering-zero rule the TWA pair does: explicit **null** on a course change, on an
unclassified turn and on a session with no usable wind axis, because 0° before the axis would
read as "he started dead downwind".

Engine 0.16.0 gives **the wrist going under** a list of its own and **moves no number** either.
One top-level key joins the document — `submersions` (docs/algorithms.md, "Submersion
episodes") — and no config key at all, because the run rule and its 2 s merge are not tunables.
The diff between a 0.15.0 golden and a 0.16.0 one is exactly the `engineVersion` stamp and that
block, on all seventeen fixtures: the mask, the threshold and every `submerged` flag read from
it are untouched, which is the check that says the episodes are the same evidence *listed*
rather than a verdict being re-decided. Ten fixtures get an empty list (no barometer, or a
channel that never moves), and the one converted GPX reproduces its FIT's single episode to the
metre, because a GPX carries the FIT's own `<ele>`. The presentation goldens' `splash` moves
with it — same key, and it now counts episodes rather than the turns and ends the mask was
flagged on (29 Aug: **7 → 35**), which is the whole point of the change.

Engine 0.17.0 gives **the clean jibe a quiet tail**, and it is the first golden diff since
0.14.0 that moves a number the rider reads. `turnCleanQuietS` (**10 s**) joins `config` and
`cleanBlockedBy` joins each entry of `turns` (docs/algorithms.md, "The quiet tail"): a counted
jibe is clean only if the ten seconds after its sweep carry no touchdown/fell-in flight end, no
off-foil spell of 1 s or more and no submerged sample. Across the seventeen fixtures **ten
`clean` flags flip to false and nothing else changes** — `jibesSuccessful` and
`cleanJibesPerHour` follow them, 160 → 150 clean jibes, and every other key in every golden is
byte-identical, `success` and the outcome ladder included. That is the check that says this is
a `clean` change: the diff is the version stamp, the two new keys, ten booleans and the two
numbers derived from them. The presentation goldens move only in `cleanJibes` (the star layer),
by the same ten. Over the 21-session corpus it reads 278 → 263.

Engine 0.18.0 **retires the pump rung of the outcome ladder and gives every touchdown and fall
a reason**. `turnPumpedOutIsTouchdown` (**true**) and `turnPumpedMarginalSpeed` (**8.0**) join
`config`, and `outcomeReason` joins each entry of `turns` (docs/algorithms.md, "Turn outcome" /
"Why"; ADR-022). The rung's corroborating speed moves from a hard-wired `foilEntrySpeed` to
that parameter, whose default is the exit speed — and since `flying` already requires speed
above the exit speed, that makes the rung unreachable, deliberately. Across the
seventeen fixtures **six jibe touchdowns become fly-throughs** (289 → 295 flew through,
212 → 206 touched down, 37 fell in unchanged) and one more jibe is clean (150 → 151); the
`longestFlewStreak` on 2026-08-07 moves with them, and every other key is otherwise identical
but for the new reason on each turn. The presentation goldens move only where a turn changed
rung. Over the 21-session corpus: 493 → 506 flew through, 270 → 257 touched down, clean
263 → 266, and Jan's Jibe 50 of 2026-09-04-0758 reads `flew_through` — and clean.

The reason itself is checked twice over. `GoldenTests` asserts Swift's `outcomeReason` against
the lab's turn by turn, and that one is present on exactly the touchdowns and falls;
`verify_presentation.py` §6 re-derives the *sentence* the reason becomes, in Python, and
compares it with what `web/js/viz.js` actually produces over every turn of every fixture —
plus the shapes the corpus cannot supply, the retired rung above all.

**And the retirement is asserted in both directions**, because a rule that can only be shown
not to fire has not been shown to have been about anything.
`test_jibe_50_flew_through_and_the_old_speed_takes_it_back` reads the 4 Sep morning, finds the
jibe at `start_t` 3480 s, and asserts it flew through with no reason at the defaults *and* comes
back as a `pumped_marginal` touchdown with `turnPumpedMarginalSpeed` at 12.0 — the 0.17.0
reading, restored through the parameter. That recording lives under `fixtures/footage/` and is
not committed, so the test is `skipif`-guarded and skips in CI; the repo-only half of the same
argument is `test_raising_the_marginal_speed_revives_the_rung`, on a synthetic jibe, which runs
everywhere.

Engine 0.19.0 **says whether a recording is a session at all** — `summary.isSession` and
`summary.notASessionReason` (docs/algorithms.md, "Not a session"). **No number in any golden
moves**: the diff on all 21 is the version stamp and the two new keys, and every one of them
reads `true` / `null`, which is the point — the rule is not allowed to reach a recording the
project already calls a session. The presentation goldens move in their version stamp alone.

It is checked from four sides, because a rule that only ever *fails* to fire has not been
shown to be about anything.

1. **The rule itself**, on the boundary and on both sides of it, in all three implementations:
   `test_the_not_a_session_rule` (lab), `SessionVerdictTests` (kit),
   `test_the_not_a_session_rule_is_the_engines_and_this_module_repeats_it` (`library.py`, run
   from `lab/tests/test_library.py`). Each pins **120 s and 200 m** explicitly, so the three
   cannot drift apart in silence. Each also asserts the case the conjunction exists for: a
   *skunked* afternoon — 0 s on the foil, 80 minutes, 2.1 km — is a session.
2. **The corpus is untouched**: `test_every_corpus_golden_is_a_session` and
   `SessionVerdictTests.everyCorpusGoldenIsASession` sweep `fixtures/goldens/*.expected.json`
   and require `isSession` true and the reason null on every one.
3. **The one fixture that would fail it.** `smoke-60s` is 59.0 s long — *inside* the 120 s
   floor — and is a session only because 30 of those 59 seconds were spent flying.
   `test_the_smoke_fixture_would_fail_the_duration_floor_without_its_foil_time` asserts both
   halves: that the fixture is a session, and that the same numbers with the foil time taken
   away come back `(False, "too_short")`. That is the corpus proving the first conjunct is
   what protects a real session, rather than the thresholds happening to miss it.
4. **The exclusion actually excludes.** `verify_library.py` §1c and
   `test_a_recording_that_is_not_a_session_counts_in_nothing` put one junk row beside one real
   one and check the aggregate, the totals, the trend stamps, a month and a typed range all
   report one; the kit's `LibraryTests` do the same through `LibraryStore.clause`.

Storage moves with it: GRDB **v16** (`isSession`, `notASessionReason`) and digest **schema
10**. Both *seed* rather than wait — the migration re-derives the rule from
`foilTimeS`/`rateDurationS`/`distanceKm`, and `library.entry_is_session` does the same for a
stored row written before schema 10 — so a library's junk leaves the totals immediately
rather than whenever re-analysis reaches that row. A row or document carrying **none** of
those three numbers is not judged at all and reads as a session: an absence is not a verdict,
the same rule the four session rates keep.

Engine 0.21.0 adds **the aborted turn** — a sweep that was still turning when the rider went
in (docs/algorithms.md, "The aborted turn"; ADR-028). `turnAbortMinAngle` (**45**) joins
`config` and `aborted` joins each entry of `turns`. It is the second golden diff since 0.14.0
that moves a number the rider reads, and it moves them in one direction only: over the 18
committed session fixtures counted turns go 560 → 569, tacks 2 → 4, jibes 558 → 565, course
changes 147 → 140, turn `fell_in` 41 → 50 and straight-line falls 45 → 44, while **clean jibes
stay at 161 and not one rate numerator moves on any fixture** — the pass can only ever add a
turn that fell in, and JPH/TPH/CPH all count *dry* turns. Seven of the nine are course changes
the page already drew and could not name, so `rejected` falls by seven; two are sweeps no
version of the scan had ever seen. **Five** fixtures move at all — the three 1 Hz sources
and two of the ten ragged native ones; the other sixteen goldens (the discipline pair and the
smoke fixture included) carry the version stamp, the config key and one `false` per turn and
nothing else. The presentation goldens follow in their
outcome markers and their course-change layer (2026-08-07: `fellIn` 11 → 13, `courseChange`
6 → 4) and in no other layer — `cleanJibes` is unchanged everywhere.

It is checked from four sides:

1. **The rule, on both sides of the fall**, in the lab (`lab/tests/test_turns.py`, "the aborted
   turn") and the kit (`AbortedTurnTests`) on the same two constructed tracks: a 75° luff-up
   that ends in a swim is a **tack** that fell in, counted, not successful, not clean; the same
   75° luff ridden out of stays the uncounted round-up it always was. Both also assert the
   before-picture with `turnAbortMinAngle` at 0, so the diff the corpus shows is reproduced on
   a track whose geometry is known to the degree.
2. **The guard**, in both: a straight-line fall with no heading change in it is not a turn, and
   neither is 20° of wobble before a swim. That is the half Jan set the corpus as judge for —
   a straight fall must stay a straight fall.
3. **Turn by turn across the corpus**, `GoldenTests`: Swift's `aborted` is asserted against the
   lab's on every turn of every fixture, and an aborted turn is required to carry the four
   things it means (counted, `fell_in`, not successful, not clean). A sweep one engine read
   backwards from a fall and the other did not would be two detectors.
4. **The rates do not move**, `test_jibes_per_hour_counts_only_the_jibes_he_sailed_out_of`:
   2026-08-29 gained one jibe *and* one swum jibe, and `jibesPerHour` reads 26.7 as it did
   before — the arithmetic the pass was built to leave alone, asserted on the session where it
   actually happened.

Engine 0.22.0 makes **the wet test read the drop, not the level** (docs/algorithms.md, "Turn
outcome" step 2; ADR-029). No config key joins the document and no per-turn key does either:
the only stamp in the diff is `engineVersion`, and everything else that moves is the barometer's
own evidence. The mask's line stops being the session median and becomes a causal local
baseline, so the check that says this is a correction rather than a re-tuning is **how little
moves**: not one ciq fixture and not one windsurf-native fixture changes by a single verdict
(two carry a one-second `offFoilS`, which is the flying mask losing a wet sample), and
`other-apps/2026-08-05-…_foilmotion` is the only golden whose turns move at all — the jibe at
`ts` 3852 goes `fell_in` → `touchdown`, and the **aborted** turn at `ts` 7907 leaves the list,
because an aborted sweep is kept only where the ladder calls it a fall. A diff that walks the
two turn lists side by side reports four moves on that fixture; three of them are the list
closing up behind the turn that left it, which is why the numbers below are counted and not
zipped. Across the 19 goldens: counted turns 569 → 568, jibes 565 → 564, turn `fell_in`
50 → 48, turn `touchdown` 208 → 209, **clean jibes 161 → 161**, straight-line falls 44 → 44,
and the one rate that moves is the foilmotion fixture's JPH/TPH, 24.5 → 24.9, because the freed
jibe is a dry one. The `submersions` block falls 95 → 37 episodes with four more fixtures going
empty, and `dropM`'s corpus range narrows 26–343 m → 26–224 m: the deep readings it used to
report were the distance from a re-anchored stretch back to the median and not the depth of any
dunk. The presentation goldens follow in `splash` (the episode count) on nine fixtures and, on
the foilmotion one, in its outcome markers and two turn-filter counts — no other layer moves,
`cleanJibes` included.

It is checked from three sides:

1. **The rule, on the four traces it was written from**, in the lab
   (`lab/tests/test_submersion.py`) and the kit (`SubmersionTests`): a fenix-8-style dunk that
   crawls back over minutes flags the whole way up; a fenix-5X-Plus-style dunk that re-anchors
   100 m lower flags the spike and the 20 s the level needs to hold, and is dry for the rest of
   the session; a 100 m drift over ten minutes is never a dunk; a recording gap restarts the
   baseline; an all-NaN channel is all-false. Both suites assert the same shapes, so a
   divergence between the two engines is a failing test rather than a bug report.
2. **The two halves are separate decisions.** A gap now makes the *mask* dry by construction,
   so `submersion_runs`' own gap rule can no longer be reached from a real altitude series —
   both suites therefore assert it on a mask written by hand, rather than quietly losing the
   case.
3. **Episode by episode across the corpus**, `GoldenTests.checkSubmersions`: Swift's list is
   asserted against the lab's, `dropM` included, so a baseline that walked differently on the
   two implementations would show up as a metre of disagreement on some fixture.

Engine 0.23.0 stops reading a **Smart Recording cadence as a hole** (docs/algorithms.md, "A
cadence is not a hole"; ADR-030), and it is the largest golden diff since the corpus was
frozen — which is the shape the change predicts rather than a surprise. **The split is the
check**: every fixture whose median dt is above 1.5 s moves and every 1 Hz fixture does not
move by a digit. The eleven that move are the ten `…_native` and the 0.5 Hz
`other-apps/…_wingfoiling`; the eight that do not are the three `ciq`, the `foilmotion`, the
GPX, the two TCX and the synthetic, whose entire diff is the version stamp and the schema
keys. Those keys are the other half of the diff and reach **every** golden: `smartGapS`,
`smartMedianDtS` and `spikeMaxDtS` join `config`, `windMaxLobeSeparation` leaves it (the
parameter is retired), and `accelClockReconstructed` joins `capabilities` — false on every
fixture in the corpus, because every one of them was timed by the device that wrote it.
Across the eleven: distance 151.8 → 184.4 km (the files' own session totals sum to 184.2),
timer time 43 508 → 60 387 s, flights 825 → 346, counted turns 369 → 378, clean jibes 81 → 69,
`unknown` flight ends 668 → 37 and `fell_in` flight ends 69 → 201 — the last two being one
fact, since an end at a fake boundary had no evidence after it and most of them turn out to
have been swims. `submersions` moves by a single episode, 37 → 38. The corpus gains its first
**best hour** (`2026-08-03-1440`, 6.746 kn): an hour is a long time to record without a real
hole, and no native used to run one gap-free.

It is checked from four sides:

1. **The rule, on synthetic cadences**, in the lab (`test_filters.py`) and the kit
   (`Engine023Tests`): a median-2 track bridges a 5 s and an 8 s step and cuts a 17 s one; a
   1 Hz track keeps its 3 s threshold; a 20 s cadence keeps the dt rule, because the floor
   only ever lifts the threshold; and `smartGapS = 0` reproduces the pre-0.23.0 rule exactly,
   which is how the before column of the table in algorithms.md was measured.
2. **The spike half separately**, same two files: a 16 m/s step over 7 s is a spike at
   `spikeMaxDtS` 3 s and is not one with the cap removed. It moves no golden, so the test is
   the only thing that holds it.
3. **The whole corpus, both engines**, `test_corpus.py` and `GoldenTests`: the goldens are the
   regenerated ones, and the Swift kit reproduces them turn by turn as always. A cleaner that
   segmented differently on one implementation would show up as a different flight list.
4. **The presentation goldens follow**, regenerated from the analysis goldens: markers,
   tallies and filter counts move on the eleven and on none of the eight.

Engine 0.23.0 also **retires the opposed-lobe refusal** in the wind estimator and **rebuilds a
clockless accelerometer stream from file order** (ADR-030). Neither moves a golden — no corpus
session has lobes past 179° and no corpus recording fails the accel clock's two tests — so
both are held by unit tests alone, in the lab (`test_wind.py`, `test_parse.py`, `test_pump.py`)
and in the kit (`Engine023Tests`): synthetic lobes at 179.2° and at exactly 180°, the
half-angle bisector against the circular mean wherever both are defined, batches with flat
offsets, batches stamped days off the session, batches queued behind one record, and a pump
grid handed NaNs and a fifty-day span.

### Fixture provenance — the converted recordings, and why

Every fixture in `fixtures/sessions/**` is one of Jan's own recordings kept as it came off
the watch. The exceptions are all the same afternoon: the bundled example is *scrubbed*
(see below), and **three are not recordings at all**.
`fixtures/sessions/gpx/2026-08-30-1407_nago-torbole.gpx` is that same 2026-08-30 CIQ
session converted by `lab/tools/fit_to_gpx.py`
(track points, `<ele>`, `<time>`, and heart rate in Garmin's `TrackPointExtension`; the
speed channel, the accelerometer, the developer fields, the laps and the session summary
deliberately not carried, because no GPX carries them).

A real GPX from some other afternoon would have tested the parser and proved nothing about
the **degradation**, because there would have been no FIT to compare it against. Converting
one fixture makes the comparison exact — same positions, same clock, same rider — so every
difference between the two goldens is the source class and nothing else. On this pair:
flights 2/2, longest flight 392.0 s both, all ten turns with identical type, side and
outcome, wind axis to the degree; foil % 67.9 → 67.3; speed records within 0.18 kn (2 s
13.472 → 13.655 — positional differentiation reads *high*, which is the whole reason those
records are marked uncertified); every pump field null and `pumpEpisodes` empty. This pair is
also the one the **plausibility gate** (engine 0.20.0, docs/algorithms.md) has to leave alone:
its `best2s / best10s` is 1.05, well under K, so the gate proves itself here by moving
nothing. The case where it *fires* has no committed fixture — the session that produces it is
a raw FIT read through the positional arm — so it is pinned by unit test instead, the same
constructed track in the lab (`test_gate_*`) and the kit (`plausibilityGate*`) asserting the
same three numbers.

**The TCX pair, and the element between them.** The other two converted fixtures are
`fixtures/sessions/tcx/2026-08-30-1407_nago-torbole-{speed,nospeed}.tcx`, the same afternoon
again through `lab/tools/fit_to_tcx.py`. They exist because a TCX is the one format that is
not one input class (docs/algorithms.md, "TCX import"): with `Extensions/TPX/Speed` it is
class (b) and its speed records certify, without it class (c) like a GPX. The pair differs
by **exactly that element**, which is what makes it an experiment rather than two fixtures —
and both ends of it land where they should. `-speed` reproduces the CIQ FIT's own numbers
(2 s 13.472 kn, foil 67.9 %, `hasDoppler` true, class b); `-nospeed` reproduces the GPX
golden's to the digit (13.655 kn, 67.3 %, class c), because it is differentiated by the same
shared arithmetic. `TcxParseTests` asserts the second of those directly, sample by sample:
two XML parsers disagreeing about the same metres is the bug that pairing exists to catch.

`fixtures/README.md` carries the rows; `make_goldens.py` picks up `.fit`, `.gpx` and `.tcx`
alike and `analyze` routes on the file itself, so nothing in the tooling needs to know which
is which.

## Presentation goldens

`fixtures/presentation/<fixture>.expected.json` — the second golden set, one per analysis
golden, generated by `web/tools/make_presentation_goldens.py` (`--check` fails when stale).
They carry no metric: only what a session-detail screen is *allowed to draw* from the
analysis of the same name — markers per layer, the takeoff layer's pumped/free/failed
split, the wrist-under episode count, pump-burst spans, the achieved record windows and the full
3 × 3 turn-filter grid (type × entry side, with the flew-through numerator) — plus the
**flight-count invariants**: `flightCount`, and a `flightEnds` block split into the three
buckets the marker rules distinguish (`drawn` + `ownedByTurn` + `truncated`). One takeoff
starts every flight and one end stops it, so `takeoff.pumped + takeoff.free ==
flightCount == flightEnds.total` on every fixture, with a `failed` attempt deliberately
outside both sums. That arithmetic is what the tap-only pairing lines are written from: a
takeoff with no flight to name would print a wrong number in a callout long before any
tally looked odd.

The rules they apply are `docs/presentation.md` "Marker eligibility", and both sides assert
them: Swift in `PresentationTests.presentationGoldensPinEveryMarkerAndFilterCount` (through
`PresentationFacts`, the kit-side home of the rules that `SessionDetail`'s builders
iterate), Python in `web/tools/verify_presentation.py`, which re-derives every count a
second way and then re-runs the engine through `web_entry` on the CIQ fixture to prove the
numbers survive the path the browser actually takes. A count that differs between the two
is a failing test, not a bug report.

`verify_presentation.py` also owns the **share card's content contract** (§5). A card is a
PNG in somebody else's chat thread — no re-render, no correction, nothing beside it to check
against — so it may not name a different number for a session than the key-metrics block on
the page does. The *drawing* cannot be golden-tested; the *derivation* is a pure function and
therefore is. `web/tools/card_parity.mjs` runs `keyMetrics` and `cardStats` under Node over
every analysis golden and dumps three lists per fixture — the rendered block parsed back out
of its own HTML, `complete`, and `lean` — and §5 asserts that `complete` **is** the rendered
block (same entries, same order, same labels, same strings), that `lean` is that list filtered
by the four contract keys and nothing else, that no tile-only cell (flight count, foil %,
longest flight) ever reaches a card, that the tally's three counts are the golden's own, and —
in a third spelling of the same rules, written in Python — that the value strings themselves
are right. It needs `node` on PATH and skips itself with a note when there is none.

`web/tools/card_text.mjs` covers the other half of the same card — the **rider's own title and
caption** (§5b, schema v9). A rider can name the session and add one line for whoever he sends
the picture to; on iOS the title is a *rename* that writes to the session row, and in the
analyzer, which has no session record to rename, both fields are transient and remembered per
session in `localStorage`. What the dialog itself does cannot be driven from a test (it is a
`<dialog>` with a canvas in it), so what is asserted is everything the dialog *calls*: the two
normalizers (one trimmed, capped line; blank means none), the per-session key — re-derived from
`meta` and required to equal the Python digest's own `_session_id`, so a document opened out of
the library and the same document freshly analysed remember one caption between them — the
storage round trip including every way `localStorage` fails (a private window, somebody else's
JSON under the key, no storage at all: all of them read as "nothing remembered" and none of them
throws), the header's height with and without a caption (**absent must be the 42 pt header the
card has always had**), and — the one that matters most — that a caption never becomes a *cell*:
§5 proves the card's cells are the block's cells, and §5b proves the caption did not quietly
join them. Same `node` requirement, same skip.

`web/tools/clock_note.mjs` is the same trick for the **header's clock note** (§4, engine
0.9.1): it runs `render.js`'s own `clockNoteFor` over one `meta` per rung of the UTC-offset
ladder — `activity`, `icu`, `longitude`, `device`, plus a document with no source at all —
and §4 asserts the six sentences against a second copy of the contract written in Python.
That note is the only place the page tells a reader whether to *trust* a clock, and until
0.9.1 it said "times as recorded on the water" over an offset that could be a solar guess
from longitude, an hour out under DST. Same `node` requirement, same skip.

The presentation *values* — colours and glyph names — are enforced separately, by
`design/tokens.json` plus `design/check_tokens.py --check` (CI: `.github/workflows/tokens.yml`
and the Pages deploy).

## The copy contract — `docs/copy/`

Two commands, and both have to be green before a wording change is finished:

```sh
cd ios/WingFoilKit && swift test --filter CopyContractTests   # the kit against docs/copy
python3 docs/copy/check_release_copy.py                        # the release copy's three rules
```

The first asserts every kit constant that more than one surface says equals its JSON in
`docs/copy/`: `ChannelFeatures` (the beta and dev rows, and the section title),
`RecordingClass`, `MetricGlossary`, `FeedbackReport.Prompt` and `FeedbackInvitation.sentence`,
`IcuSetupGuide`'s steps and its Save & check label, `Branding.callToAction`,
`ShareCaption.offer`, `WelcomeGuide.headline` and `.promise`, and `NotASessionNote`'s tag and
two page lines. It also greps the kit's `Presentation/` and `Help/` **string literals** for
the banned vocabulary and fails naming the file, the line and the word. So a kit edit that
moves a fact fails here until `docs/copy` moves with it; the web verifier is the other half
of the pin, and the website then has to catch up before the check goes green.

Regenerate the kit-owned keys after a deliberate rewording, from `ios/WingFoilKit`:

```sh
COPY_WRITE=1 swift test --filter CopyContractTests
```

The hand-authored keys — the forbidden lists, the lexicon, the two store names — are left
exactly as they were, and the output is deterministic, so a regeneration that changes nothing
produces no diff.

The second runs three rules over the store copy and the kit's rider-facing literals: no
release text may contain a door the release lacks (`channels.json` → `forbiddenInRelease`),
no rider-facing text may say what Strava has or has not reviewed (`phrases.json` →
`stravaForbidden`, docs/channels.md), and nothing may use the banned vocabulary
(`phrases.json` → `lexicon.banned`). One line of PASS/FAIL per target, and every exemption it
honours is printed with the reason it exists. It is the same check `docs/testing.md`'s "Three
channels" section runs over the *binary* (`strings` on the archive), run over the copy —
adding a target is one entry in its `TARGETS` list, which is how `web/**.html` joins it.

**The web's half of the same pin** is `python3 web/tools/verify_copy.py`, which
`web/tools/verify_links.py` runs the way it runs `make_start.py --check` and
`make_devices.py --check`: a page that has drifted from the copy contract is a link to a
promise nobody made, and it fails with the links. It reads the JSON at run time and never
retypes a sentence — the hero's promise, the card CTA and the caption offer composed out of
`js/cardstats.js`'s own parts, the Strava sentence and the five phrases that may not
accompany it, the Connect IQ listing name, the beta and dev lists and the section title on
`/invite/` — the one page that prints them since 15 September 2026 — the four
recording-class names and lines in `/start/#watches`, likewise the one table that carries
them, the glossary entries on `/help/`, the three feedback prompts in every `mailto:` body
and the
invitation in every *Tell us* block, and the four intervals.icu step titles and the
**Save & check** label on `/start/` outside the generated guide block. Pages carry
`data-copy` marks so the check is exact rather than a guess at the surrounding prose;
`data-copy="aside"` is what lets a row carry a trailing pill and still *be* the JSON's
sentence, and `data-copy="beta-door"` is what lets a page name a door the release lacks
without the release-copy rule firing. One line per pin on success, the page, the key and the
nearest snippet on a miss. `web/tools/make_copy_js.py --check` runs beside it, for the four
sentences the analyzer renders at run time (`web/js/copy.js`). The exemptions for the
forbidden-door rule are not written twice: `verify_copy.py` reads
`check_release_copy.py`'s own `allow` map for the same page.

**And the sentences nobody owns.** `python3 web/tools/verify_unique.py`, added 15 September
2026 and run by `verify_links.py` as a fourth sub-check, is the half no pin could reach: the
site's own prose, written once and then written again on another page — the Android install
steps twice at 110 and 95 words, the recording classes in two tables, the feedback doors on
two pages. It reads `<main>` of `/`, `/start/`, `/help/` and `/invite/`, normalises whitespace with
`verify_copy.py`'s own helpers and the typographic apostrophe the generators render, skips
everything
between the guide markers and every string `docs/copy` owns, and **fails on any remaining
sentence of eight words or more that is on two pages**. Threshold zero, with an `ALLOW` list
of `{prefix, pages, why}` printed on every run — the same culture as `check_release_copy.py`'s
exemptions, because an exemption that is not read becomes the rule. Its second half is a
**word budget per page** (`/` 550, `/start/` 1700, `/help/` 900, `/invite/` 1500, each with
ten per cent of slack), counted the way a reader meets the page: everything inside a
`<details>` but its `<summary>` is left out. The numbers moved on 19 September 2026 because
the pages did: `/start/` absorbed `/watches/`, `/invite/` absorbed `/whats-new/`, and
`/help/` is the app's whole help catalogue behind ten folds, which is why a reference work
of forty pages fits inside 900 visible words. That is what
stops `/start/` walking back to 3500 words one honest paragraph at a time, which is exactly
how it got there the first time.

**And the words under the numbers.** `python3 web/tools/verify_glossary.py`, added 20
September 2026 and run by `verify_links.py` as a sub-check of its own, is the browser's twin
of the kit's `GlossaryLintTests`: **every metric label the app's JavaScript prints is a
spelling in `docs/copy/glossary.json`**, which is `MetricGlossary` exported. The case was a
tester who compared three screens about one afternoon and read *Turn success 29 %* in Garmin
Connect, *93 % flew through* on the site and 44 % on the phone — three measurements, two of
them sharing a word, spelled in files that never met. It scans five regions rather than five
whole files, because a JavaScript file is mostly strings and few of them are names: the
key-metrics block in `js/cardstats.js` (which *is* the share card — one list, two readers),
the tiles and the takeoff rows in `js/render.js`, `ROW_METRICS` in `js/library.js`,
`renderTotals` in `js/trends.js`, and the watch-vs-phone rows in `js/log.js`. A cell's
caption is cut at `CAPTION_SEP` — "of 55 jibes" qualifies the number, it does not name it.
A label that is a unit, a clock, a plain measure or a maneuver noun goes on an `ALLOWED` map
with its reason, printed on every full run, the same culture as `verify_unique.py`'s; a
region that cannot be found fails loudly, so a renamed function cannot quietly stop the
check. What it deliberately does **not** read is the aggregate labels the digest authors
(`lab_bundle/library.py`: the records table, the chart titles, the period block) — they are
the engine's output, mirrored from `lab/`, and each is a superlative over a term that is in
the glossary.

`verify_links.py` also compares the **footer** block between `<!-- sitefoot:begin -->` and
`<!-- sitefoot:end -->` byte for byte across all seven reader documents, the way it has always
compared the site nav: one link set, every page, no `aria-current`.

**The voice** (docs/voice.md, 15 Sep 2026): `python3 docs/copy/check_voice.py` measures every
rider sentence on every surface — the kit's Help and Presentation literals, the app's Features,
the watch's pages, alerts and strings.xml, the seven prose pages of the site, and (advisory,
while a version is in review) the two store descriptions — against the rules a machine can
hold: no dash, semicolon or parenthesis inside a rider sentence, no sentence over 20 words,
mean under 14, none of the banned shapes. `--report` prints the numbers without failing.
Exemptions live in `docs/copy/voice-exemptions.json` as `{path, text, why}` and are printed
on every run.

**Paragraph budgets are strict** since the second voice pass (pattern I). A paragraph is one
authored block — a `+` chain of literals, cut again at every line break inside it — and
carries 40 words, or 25 in a Settings or Import footer, which are targets of their own. A
help summary's 20 and a help body's 120 stay in `HelpBudgetTests`, where the text is a field
rather than a literal, and the two numbers match this lint's. The website keeps the sentence
rules and no paragraph budget here: what the extractor calls a paragraph on a page is a run
of visible text between two blank lines of markup, and the page's own budget is
`verify_unique.py`'s. The way under a budget is to **split, never to compress** — every cut
fact keeps a home (docs/voice.md, rule 10).

**One sentence, one home, inside the app**: `python3 docs/copy/check_duplicates.py` (pattern
F) splits the kit's `Help/` and `Presentation/` and the app's `Features/` into sentences and
fails on any of eight words or more with two homes. `docs/copy/duplicate-exemptions.json` is
empty on purpose. A line two screens both say lives in `WingFoilKit`'s `Copy` enum and is
referenced from both; sentences `docs/copy/*.json` owns are the contract's and are skipped.

Both lints run from three places, so neither can drift unnoticed: by hand, from
`web/tools/verify_links.py` beside the web checks, and from `CopyLintTests` in the kit, which
runs them from the repository root during `swift test` and skips with a message on a machine
without python3.

## Tolerances (Swift & Python vs goldens)

| quantity | tolerance |
|---|---|
| counts (flights, turns, attempts, strokes) | exact |
| verdicts (turn type/outcome, flight-end outcome, ownership) | exact |
| pump episodes (list length **and order**, outcome, strokes, bursts, flightIndex/turnIndex) | exact; their `startTs`/`endTs`/`lookaheadS` ± 1 s |
| timestamps | ± 1 s |
| speeds (records, turn entry/minimum/exit) | ± 0.05 kn (alpha ± 0.1 kn) |
| angles (wind direction/axis, turn net sweep, turn `twaInDeg`/`twaOutDeg`) | ± 1° |
| turn peak COG rate (`peakRateDegS`, **signed**) | ± 1 °/s |
| percentages (turn success, takeoff success, HR coverage/usable share) | ± 0.5 |
| heart rates and coverage shares (HR cost, baseline, peak, pumping/cruising) | ± 0.05 bpm |
| bpm per stroke (a ratio of two of the above) | ± 0.005 |
| foil time | ± 2 % |
| session duration (`durationS`) | ± 0.1 s |
| session rates (`avgSpeedKmh`, `turnsPerHour`, `jibesPerHour`, `cleanJibesPerHour`, `wetPerHour`) | ± 0.05 |
| window rates (`windowRates` peaks and every series `jph`/`wph`) | ± 0.05 |
| window starts (`bestJphStartTs`, `bestWphStartTs`, series `ts`) | ± 0.1 s |
| watch live vs phone recompute | ± 0.2 kn, counts exact on clean clips |

Non-qualifying records (no window of the required length/shape exists — e.g. 1 h in a short
session, alpha with no qualifying loop): goldens serialize **0.0**, the Swift model uses
**nil**; comparisons treat any value < 0.05 kn as "absent" and the two as equivalent.

## Layers

1. **lab pytest** — regenerate goldens, assert self-consistency (guards refactors). A
   `compare_speedreader.py` that diffed the GP3S numbers against GPS-Speedreader exports was
   planned (`docs/plan.md`) and never written; `fixtures/speedreader/` is still empty. The
   GP3S rules are held by the goldens and by `web/tools/verify_presentation.py` instead, so
   this is a gap in the *cross-validation* against a second implementation, not in coverage.
2. **WingFoilKitTests (Swift Testing)** — full pipeline on fixtures vs the same goldens;
   parser fail-soft tests (missing channels, truncated FIT, foreign-app FITs); importer test with
   a synthetic nested GDPR ZIP.

   **The crash hunt** — `SyncCrashHuntTests`, `MutationFuzzTests`, `FitFactory`,
   `DegenerateFits`. The corpus is sixteen recordings from two devices; the first sync from a
   stranger's intervals.icu account is seventy-odd files of shapes nobody here has produced,
   and that is the one road into the app where a bad file is not a bad row but a dead
   process. Three families, and the assertion in all of them is the same: *finish, or throw
   — never trap*.
   - **named shapes** — `FitFactory` is a small FIT *writer* (tests only; nothing in
     CleanJibe writes a FIT) so `DegenerateFits` can build the twenty-two shapes no device
     Jan owns produces: no records, one record, two on the same second, no position, no
     speed, speed zero throughout, one enormous spike, timestamps going backwards, a 24 h
     gap, a 30 h session, a session entirely on land, running and cycling that slipped the
     name filter, a sport code the profile has no name for, no `activity` message, laps of
     zero duration, HR only, another app's float developer fields carrying NaN and ±∞, a
     **broken clock** (complete, correct CRC, forty years between two records) and a
     **truncated** file. Each prints its own wall time; a shape that takes a minute is not a
     crash, but it is what a tester reports as one.
   - **mutation fuzz** — bytes flipped inside the data section of every corpus FIT, seeded
     so any failure reproduces. Two families, because they test different doors:
     *damaged* (CRC left alone) must be **refused**, every one; *repaired* (CRC recomputed)
     is well-formed and merely strange, reaches the decoder and must be read or refused.
     The committed run is a regression guard and costs about fifty seconds: six mutants from
     **one recording per corpus family** (native, CIQ, other-apps, synthetic — the ten native
     files ask the same question ten times), every mutant parsed, one per source analysed.
     Four switches open it up for a deliberate hunt: `FUZZ_MUTANTS=n` per source, `FUZZ_ALL=1`
     for every recording, `FUZZ_DEEP=1` to analyse every mutant and not just the first, and
     `FUZZ_TRACE=1` to print each attempt before it runs — which is the only trace left when
     a mutant crashes instead of failing. Worth a run under
     `swift test --sanitize=address` after any change to the FIT front end; that is how the
     segfault was caught rather than merely observed.
   - **a stranger's whole account** — seventy-four activities through the real `IcuClient`
     and `IcuSyncService`, with a fake transport serving a good FIT, an HTTP 502 error page,
     zero bytes, HTML, a download that throws, a ZIP, a gzip stub and every degenerate shape
     above. The sync must return a summary: one bad activity may not stop the other
     seventy-three, and each failure names its activity. `FUZZ_BIG=1` adds the 30 MB case.
   - **memory** — seventy-four imports back to back with `mach_task_basic_info` either side.
     On the corpus the process grows ~25 MB, which is the answer to "is it jetsam": on this
     corpus, no.

   This is how the importer's refusals were found (docs/algorithms.md, "Recordings the importer
   refuses"). A truncated FIT took **198 seconds** and built a 24.6-million-point rate series;
   a mutated one **segfaulted** the test process several files after the mutant that did the
   damage. Both shapes were in the App Store build (1.0.0, build 60) —
   `ios/WingFoilKit/Sources/WingFoilKit/FitImport/` had not changed since it was cut.

   **One residual, outside our code, and it is the open end of this hunt.** A FIT that is
   whole, correct-CRC and framable can still trap *inside* FitFileParser 1.5.2:
   `rzfit_swift_map.swift:1030-1048` (`rzfit_swift_string_for_type`) narrows a `FIT_UINT32`
   raw value into `FIT_ENUM` / `FIT_UINT8` / `FIT_UINT16` with the **exact** initializer, so a
   value wider than the profile's type dies on "Not enough bits to represent the passed
   value" — uncatchable, inside `FitFile.init`, before a line of ours runs. (`FitMessage.swift:146`
   has the same shape.) Reproduce it with
   `FUZZ_MUTANTS=12 swift test --filter repairedMutantsNeverTrap`: the mutant is
   `2026-08-03-1440_nago-torbole-windsurfen_native.fit` seed 8, which is why the committed
   budget is six. No gate of ours can see it — the file is structurally valid — and the fix
   is one word upstream (`truncatingIfNeeded:`) or a pinned fork. Until then it is a known
   way for a stranger's recording to kill the app on the first sync.
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
     hits body and item text); the share card's content — its `complete` preset is the
     **key-metrics block, cell for cell** (same keys, same order, same labels, same strings,
     the tally's three counts kept as counts), `lean` a strict *subset* of it that may only
     remove entries, no flight count on either, "—" rather than a fabricated 0.00 kn, the
     uncertified disclaimer, and the preset preference round-tripping through
     `UserDefaults` with an unknown stored value degrading to `complete`; thumbnail geometry
     (aspect preserved — a straight-line track must land in a band, not stretched over the
     box; `contentBox` reports the band rather than the square, which is what lets the card
     fill its box; runs split at the phase change and share a vertex; the outcome and
     wrist-under marks come off the shared presentation rules — counted turns only, one
     diamond per submersion episode — land on the outline's own projection, and are dropped when no fix is within
     30 s; the sparkline bucketed by **max** so a
     single fast reach survives thinning; each half degrades on its own; a degenerate track
     stays finite; the on-disk cache round-trips and a version bump invalidates it); PB
     detection (float noise is not a record, the *first* import celebrates nothing, an
     uncertified source never celebrates); the tappable map legend's visibility model
     (everything visible by default and after an unreadable or unknown stored value;
     toggling one chip touches only that category; the round trip through `UserDefaults`,
     including turning categories back **on**; a hidden *line* category degrades to the
     neutral route rather than erasing the track, while the other phase keeps its tint; a
     category with no instances in the session is not a toggle); the **phase cut**
     (`TrackPhaseCut`, docs/presentation.md "Phase tints") — a boundary inside a sample
     interval cuts on an interpolated point that lies on the line the map already draws, a
     boundary exactly *on* a fix cuts there without duplicating the vertex (the corpus case:
     both fixes either side of a landing are inside a flight, so per-sample tinting sees no
     change at all), an off-foil span covering several missing samples is one stub, a flight
     shorter than one sample interval still draws, and a recording gap breaks the line
     everywhere *except* across a cut; the **pairing** lines (`FlightPairing`) — the four
     exact strings the contract writes, the absent-never-zero rule for a source with no
     accelerometer, "recording ended" rather than a verdict for a truncated end, the
     web-compatible `m:ss`/`h:mm:ss` clock, and a takeoff resolving its flight by the instant
     they share (an unresolvable one gets no line rather than a wrong number); the flight
     **focus** window (a tapped flight framed with a margin, clamped at both session edges,
     and a two-second hop still opening a readable window); and the widget snapshot
     (7-day window, the
     `foilTimeS`→`foilPct` fallback for pre-v2 rows, encode/decode round-trip, and the
     invariant that the store never claims the shared container it does not have).
   - `SessionPagingTests` — which way a flick turns the session page (`SessionPaging`). The
     finger drags the content, so left is the **next** session in the list's order and right
     is the previous one, mirrored at every distance that commits. A short drag stays, a
     short drag *thrown* hard turns, a flick that reverses mid-drag stays, and a drag that is
     not much flatter than it is tall belongs to the inline map. Plus the rubber band: the
     page follows the finger the way it went, never past the limit, and barely at all where
     there is no session to turn to.
   - `RowMetricTests` — the three numbers a library row carries (`RowMetric`). Every case has
     a word and a glyph and no two share a word (pattern H), the default triple is foil ·
     jibes · best 2 s, each case spells its value the way the rest of the app spells it, an
     unfilled row prints "—" rather than a zero, and the rider's choice round-trips —
     including the half-written and unknown values, which fill from the default rather than
     leaving the row a cell short. `TrackTileRegionTests` beside it pins the map behind the
     track: the region is the square the inset leaves, widened to the tile's own shape, and
     an inset that eats the tile yields no region at all.
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
     are absent from the raw file; it still parses as class (a); and the bundle stays under
     1.5 MB, which is how a longer session swapped in for this short one gets caught); the
     analysis (2 flights, 10 jibes, > 13 kn best-2 s, HR, a wind estimate and a GPS start
     fix, with `flight`/`turn`/`record_effort` filled, and `hasAccel == true` /
     `totalPumpStrokes == 31` because this example ships whole); and
     the `isExample` flag (set on import, round-tripped through SQLite, deletable, and
     invisible to `records()`, `trend()`, `sessions()`, `weeks()` and the gear rollups
     while a real session next to it still reaches all of them). Plus the v3 migration
     (column added, pre-v3 rows default to *not* an example) and the written copy.
   - `OnboardingTests` — the intervals.icu first run, which by definition is walked once
     per install and never again: `IcuSetupGuide` is four numbered, written steps (the Help
     topic and Settings → intervals.icu render the *same* array, asserted, so the manual
     and the walkthrough cannot drift; the empty library stopped rendering them on dev 70);
     the failure→cause mapping behind every message the app can show (401/403 ⇒ "regenerate the key", `URLError`/transport ⇒ network and
     explicitly *not* the key, other HTTP ⇒ status only — **the response body never reaches
     the screen**, and no message, hint or crumb may contain the key itself); a sync that
     returned nothing ⇒ "connect Garmin in intervals.icu" rather than silence; the key
     check against a stubbed transport (counts activities *and* watersports, and a valid
     key with no watersports reports the caveat instead of claiming success); and
     `IcuOnboarding.state` (empty + no key ⇒ the ways in, key + stored problem ⇒ that cause,
     key + nothing yet ⇒ waiting, any session at all ⇒ never onboarding), with the problem
     round-tripping through JSON so the empty library still names the cause after a relaunch.
   - `WelcomeTests` — the screen in *front* of that card (`WelcomeView`, raised by
     `RootView`): that `WelcomeGuide` is actually written rather than stubbed, that it
     speaks the app's own vocabulary (foil, flight, touchdown, jibe, streak, record, and
     the three verdicts in the ladder's order) and that its two offers name what is behind
     them; then the show-once rule, `WelcomePrompt`. A fresh install is welcomed; `hasSeen`
     ends it for ever; an install with **any** session or a stored key is treated as
     already welcomed — that is the upgrade path, and it also spends the flag silently
     (`shouldMarkSeenSilently`) so that emptying the library years later cannot make the
     app introduce itself to its oldest user; and a busy screen *defers* rather than
     refusing, exactly as `NewActivityPrompt` does, without spending anything. The app
     half adds one guard the predicate cannot: nothing is decided until the library has
     actually been read (`SessionStore.hasLoadedLibrary`), because an empty `sessions` at
     launch means "still loading", not "no sessions".
   - `TombstoneTests` — deleting a synced session has to *stick*. Two pure rules, tested
     apart because they fail differently. The **matcher** (`SessionTombstones.blocks`) decides
     whether an incoming intervals.icu activity is one the rider threw away: by activity id
     when the deleted row carried one, otherwise by the library's own ±60 s dedupe key with
     the same **one-sided** duration comparison `NewActivityWatch.isInLibrary` uses (icu
     reports moving time, the library stored elapsed time), which is what catches a session
     that arrived through a Garmin GDPR ZIP, carries no icu id, and is on intervals.icu all
     the same. The **gate** (`shouldOfferReAdd`) decides whether the rider is ever asked:
     only on a second *manual* sync within `reAddWindowS` — ten seconds, measured to the
     moment the second sync began — never on a background wake, never on the first sync of an
     install, and not again for the same window after a "Keep deleted". Plus the arrangement
     the picker needs (`candidates`: newest session first, and a "only this day" shortcut
     that appears only when the list is long enough *and* spans more than one day, grouped by
     the **session's** day rather than the deletion's), the v6 migration, and one round trip
     through GRDB asserting that deleting writes a tombstone, that restoring forgets it, and
     that the bundled example gets none — it is not the rider's session and no sync was ever
     going to bring it back.
   - `LibraryBackupTests` — the library leaves the phone in one zip and comes back into a
     *different* store, with its own archive root, because "it worked where it was written"
     is the one thing a backup may not be (ADR-015). The round trip builds a real library
     from two corpus FITs — one renamed and captioned, one credited to a friend, a wing and
     a board linked, a spot named by hand, one session deliberately deleted — packs it,
     unpacks it into an empty store and asserts the columns nothing can re-derive:
     `customTitle`, `shareNote`, `rider`, the unioned `importSource`, the UTC offset and its
     provenance, the gear combo by name, the spot's rider-given name, the tombstone and its
     title — plus that the recording came back **byte for byte** and was analysed by *this*
     build's engine. Then the four rules that decide whether it is safe to run twice, or on
     a phone in use: **idempotency** (a second restore reports nothing and the rows, gear,
     spots and tombstones compare equal, object for object); **never overwrite a newer local
     edit** (a locally-renamed session keeps its name and gains only the caption it never
     had; a locally-chosen wing survives while the empty board slot is filled); **a session
     deleted since the backup stays deleted** (a live tombstone is the newer instruction);
     **a row with no recording is counted in the manifest and skipped on the way in**
     (a provisional watch card has nothing to re-ingest, and a session row invented from
     summary columns is the blind copy this design avoids); and **a future schema is
     refused** with the sentence the rider reads, leaving no rows,
     no archive directories and no import-log entry behind. An **older** backup is the
     ordinary case and gets its own test: a hand-built schema-v6 database, packed with a
     manifest that says 6, restores through the migrator — the v9 columns come back nil
     rather than invented, and the offset v6 could not store is re-read from the recording.
     Plus the pure rules on their own — the size warning's 200 MB threshold and its
     accelerometer sentence, the provenance union, `example` winning the primary-source
     pick, gear's case-insensitive natural key, and `AppDatabase.schemaVersion` pinned to
     the migration list so the manifest's number cannot drift from the schema it describes.
   - `HealthImportTests` — a workout recorded with **Apple's own Workout app** and read back
     out of Health (ADR-017). **Nothing here touches HealthKit**, which is the point: the kit
     has no Health database, no entitlement and no watch in the room, so `HealthImport` takes
     plain value types and every fixture is a synthetic thirty minutes — a slow start, a
     straight run east, a 180° turn over six seconds, the run back, a two-minute stop, a
     missing minute, and one more ride. The engine finds ≥ 2 flights and ≥ 1 turn in it,
     which is the whole claim: an Apple Watch workout analyses like a native Garmin file.
     Then the honest capabilities — `hasSpeed` (CoreLocation's Doppler channel ⇒ **class (b),
     certified**), `hasHR`, and `hasAccel` **false**, so the letter is plain (b) and the
     standard class-(b) sentence is the right one; heart rate joined onto the record timeline
     inside the ±5 s tolerance, and readings from outside the route's own span dropped; the
     missing minute marked `gapBefore` exactly once; CoreLocation's negative "no reading"
     sentinels turning into nil rather than into a speed record; an empty (or wholly
     unusable) route rejected by name instead of imported as an empty session. Two suites of
     invariants beyond the mapping: the **clock** — an offset is claimed as rung 1 only when
     the workout stated one (`HKMetadataKeyTimeZone`), otherwise the ladder answers
     `longitude` like a GPX, and a container written *without* the new `utcOffsetKnown` flag
     still means rung 1, which is what keeps every watch container ever written correct — and
     the **round trip**: `HealthImport.container` re-parses to the same track the mapper
     produced, sample for sample, because a session whose numbers changed at the next engine
     bump would be the archive silently lying. Finally the whole integration: the bytes go
     through `SessionIngestor.ingestContainer` (the door a *file* comes through), land as
     `importSource == "applehealth"` with `sourceClass "b"`, re-analyse from the archive, and
     a second import of the same workout is one duplicate rather than a second session.
   - `ShareTextTests` — the message that travels with a shared file (`ShareText`). Every one
     of the three leads with where and when, off the share card's own `dateLine`, because the
     receiver is usually the friend who was on the water at the same time and could not
     otherwise tell which afternoon he had been sent. The FIT keeps the analyzer invitation
     (it is the one attachment the receiver can actually do something with); the clip and the
     card do not.
   - `ReplayPacingTests` — the setup sheet asks for a **length**, not a rate, and the length
     it asks for is the length that comes out. Pinned on the 30 Aug Torbole fixture: 10 / 25 /
     60 s of replay come out at 10.00 / 25.00 / 60.00 s, solved to 99.02× / 38.82× / 13.78×,
     off a script cut to 4 / 8 / 12 lines (`ReplayCommentary.budget`) — the ease costs about a
     second per milestone, so twelve of them would otherwise make a ten-second clip
     impossible. Pinned again on a **synthetic two-hour afternoon with thirty milestones**,
     which is the session that produced the bug report: 10 s of replay at 1107.69×, four lines
     kept, 16.5 s of video. "Full detail" is still the old constant 10× and still lands on the
     77.70 s `ReplayDriverTests` pins. There is only one saturation left — a session shorter
     than the target plays in real time; the old 250× ceiling is gone, because it was what
     turned a ten-second choice into a forty-second clip.
   - `ReplayStageTests` — where the clip is on the glass and where that lands in the recorded
     file (`ReplayStage`, `ReplayClipCropper`). The box arithmetic on screen sizes that exist,
     the points→pixels mapping done as a **fraction of the frame** rather than `× scale` (the
     recorder reports the file's dimensions, not the panel's), even numbers for H.264, and a
     real crop of a real synthetic movie written with `AVAssetWriter` — the one part of the
     recording path a Mac can settle.
   - `ReplayClipSoundtrackTests` — how the rider's own track is cut to fit a clip whose length
     he did not choose (`ReplayClipSoundtrack`, `ReplayClipCropper.export`). The schedule is
     pure and pinned: a long track is trimmed to one piece, a short one repeats from the top
     with the last copy cut mid-phrase, an exact fit stays one piece, the pieces tile the clip
     with no gap and no overlap on six track/clip pairs, anything under a second is refused
     outright, and the 0.8 s / 1.5 s fades shrink together — never overlapping — on a clip too
     short to hold them. Then the same two-layer trick `ReplayStageTests` uses: a synthetic
     `AVAssetWriter` movie plus a 440 Hz tone written with `AVAudioFile`, muxed for real, and
     the exported file asserted to have exactly one audio track as long as the video — with a
     crop and without one. A file that is not audio at all leaves the clip silent rather than
     failing the export, which is the trade the whole path is built on: the recording took as
     long to make as it lasts, and a bad pick must not cost it.
   - `CrashDigestTests` — what a MetricKit diagnostic payload means, from
     `fixtures/crash/metrickit-payload.json`, which is Apple's own `jsonRepresentation()`
     layout with one crash, one hang and one disk-write exception in it. The frame walk is
     the part worth a fixture: the tree's *root* frame is the outermost one and `subFrames`
     descends towards the crash site, so the line worth printing is the deepest frame of the
     **attributed** thread — the fixture carries a nested chain under `dyld` and a second,
     unattributed thread that must not be the one that is read. Then the block as the mail
     prints it, line for line at a fixed zone: where it came from, the counts by kind, up to
     eight crashes by name, and the tally of what was left out. A build number is named only
     when the crash happened on an older one. Nothing in the suite imports MetricKit, which
     is why the parsing lives in the kit at all.

   iOS screenshot hooks (DEBUG **and** simulator only, passed as `SIMCTL_CHILD_…`
   environment variables to `xcrun simctl launch`): `UI_RESET=1` restores the fresh-install
   state — both keychain items, the whole defaults domain and the app group's, and
   everything in Application Support, Caches, tmp and Documents (database, FIT archive,
   replay-music copy, widget snapshot) — and `UI_ICU_KEY=…` seeds a key through the real
   keychain path afterwards, so the first-run empty library and the "key stored, sync
   rejected" state can both be captured without reinstalling. It runs in `WingFoilApp.init`, before the
   store reads the keychain, and the wipe it runs is `StartOver.wipe` — the same one
   **Settings → Beta → Start over** runs, so there is one wipe and not two
   (docs/presentation.md, "Start over"). `UI_START_OVER=1` is its in-process twin: it waits
   for the first library read and then calls `SessionStore.startOver()`, the very method the
   button calls, so a screenshot taken after it is the real result of the real door rather
   than of a launch-time shortcut. Beta and dev channels only have the button; the hook
   compiles in any DEBUG build. `UI_IMPORT_FIXTURES=1`, `UI_OPEN_SESSION=latest|<name>`,
   `UI_TAB=records|trends|gear`, `UI_SHEET=help|settings|import|tuning|discipline` and
   `UI_HELP_TOPIC=<HelpTopicID>` park the app on a given screen, since `simctl` cannot tap.
   `UI_SYNC_CONTAINER=<path>` points the dev build's iCloud Drive sync at a plain directory
   instead of the ubiquity container, so two simulators can share one library
   ("Two devices, one library", below).

   **A screenshot in km/h** needs no hook of its own. Settings → Units is a tap `simctl`
   cannot make, but the choice is an ordinary stored default, so passing it as a launch
   argument puts it in the argument domain and `SessionStore.init` reads it exactly as it
   reads a tapped one — before anything renders a speed:
   `xcrun simctl launch <dev> de.lahmann.wingfoil.dev -speedUnit.v1 kmh` (`knots` is the
   default and the other value). Per launch, and it leaves the simulator as it found it.
   Worth photographing after any change to a chart, a records table or a narrated sentence:
   every speed on iOS follows the picker, the four chart axes included
   (docs/presentation.md, "Units"). On the Trends tab pair it with
   `UI_SCROLL_TO=best2s`, the page's second anchor: the speed line is the one chart there
   that the picker moves, and it sits below the fold.

   `UI_TEXT_SIZE=xxxl|ax1|ax2|ax3|ax4|ax5` sets the **whole app's Dynamic Type size** for
   that launch (`ScreenshotTextSize`, applied at `RootView`'s root so every sheet raised
   from it inherits it). The rest of the ladder is accepted too — `xs`, `s`, `m`, `l`, `xl`,
   `xxl` — and an unknown value overrides nothing, which is what an unknown value means
   everywhere else in the family. The size a rider actually reads at lives in iOS Settings →
   Accessibility → Display & Text Size, which is three taps `simctl` cannot make and a
   setting that then leaks into every other shot on that simulator; this is per-launch and
   leaves the simulator as it found it. Pair it with any other hook — one launch per size is
   how the five accessibility sizes get photographed:
   `SIMCTL_CHILD_UI_TEXT_SIZE=ax3 SIMCTL_CHILD_UI_SHEET=help xcrun simctl launch <dev> de.lahmann.wingfoil.dev`.
   On the **Sessions** tab, `UI_GROUP_BY=none|month|year|spot` and `UI_FILTER_SOURCE=<raw>`
   (`icu`, `file`, `gdpr`, `airdrop`, `fixtures`, `example`, `watch`, `applewatch`,
   `applehealth`, `strava`) stage the list's two controls (docs/presentation.md, "Session
   list"): a segmented control and a toolbar menu are both taps `simctl` cannot make, and
   the grouped headings and the chip row are the whole point of the screenshot. `UI_GROUP_BY`
   writes the stored preference exactly as a tap would; the source filter is per-visit, like
   the control it stands in for. Pair either with `UI_IMPORT_FIXTURES=1`, since the rules
   want a library with more than one month and more than one door in it.
   `UI_SHEET=discipline` raises the post-import review sheet over whatever is in the library
   (docs/presentation.md, "Confirming the discipline on import"): the sheet the import itself
   raises has usually been and gone by the time a screenshot is taken, and the banner that
   brings it back is a tap `simctl` cannot make. Pair it with `UI_RESET=1 UI_IMPORT_FIXTURES=1`,
   since a session already in the library has been through the migration and counts as settled.
   `UI_DISCIPLINE=windsurfFoil|windsurfFin` re-analyses the session `UI_OPEN_SESSION` picked
   under that preset (docs/algorithms.md "Disciplines") **before** the page opens — `simctl`
   cannot tap a segmented control, and setting it afterwards would photograph the wingfoil
   reading with a windsurf chip on it.
   `UI_SHEET=tuning` needs the **dev** build (`TUNING`, below) — it opens Settings → Tuning
   as a sheet of its own rather than "Settings, then push", because `simctl` cannot tap the
   row either. On the public build the value is simply unknown and nothing opens.
   `UI_TUNING_DISCIPLINE=wingfoil|windsurfFoil|windsurfFin` picks which of the page's three
   sets it opens on (docs/presentation.md "Tuning") — same reason as `UI_DISCIPLINE` above,
   a segmented control is a tap `simctl` cannot make. Dev build only, like the page itself.
   **Since the session page became a four-way switcher** (`SessionSection`,
   docs/presentation.md "Sections"), every session hook that names a place also **selects
   the section that place lives on** — `UI_SCROLL_TO` through `SessionSection.section(owning:)`,
   and `UI_OPEN_TURNS=1`, which used to push a page, by selecting `Turns`. A scroll to an
   anchor on an unselected section reaches nothing at all, silently, and produces a
   screenshot of the wrong screen; `PresentationTests.everyScrollAnchorResolvesToExactlyOneSection`
   is what stops an anchor being renamed out from under a hook.
   `UI_LOAD_EXAMPLE=1` makes the same call the empty library's "Try the example session"
   button makes, and `UI_SCROLL_TO=setup` parks the empty state — the promise row and the
   ways-in card under it (`LibraryView.waysInCard`) — on its bottom edge. Both hooks
   outlived the four-step setup card the empty library carried until dev 70: the example
   hook never tapped anything, it called `loadExampleSession` directly, and the anchor is
   still on the empty state itself. The empty state is now about a screen tall rather than
   a screen and a half, so a plain launch with an empty library photographs most of it.
   `UI_WELCOME=1` raises the **welcome screen** (`WelcomeView`, the full-screen cover a
   first launch opens on) whatever the library and the `welcomeShown.v1` flag say — any
   machine that has ever run the app has already spent the one launch that shows it. It
   presents the same screen by the same route and never writes the flag, so it stages the
   state without spending it. It fires **once per launch**, deliberately: the decision is
   re-asked on every library change, and re-raising would drop the screen back on top of
   the session its own "Try the example session" button just opened. `UI_RESET=1` clears
   `welcomeShown.v1` along with everything else, so a reset alone also produces the screen —
   `UI_WELCOME=1` is for photographing it on a simulator with a library in it. The three
   buttons cannot be tapped by `simctl`; the primary one's destination is the ordinary
   session page, reachable with `UI_LOAD_EXAMPLE=1 UI_OPEN_SESSION=example`.
   On the Trends tab `UI_SCROLL_TO=sideSuccess` parks the screen on the port/starboard
   turn-success chart, and `UI_SCROLL_TO=best2s` on the speed line — the one chart on that
   page the Units picker moves, which is why it has an anchor of its own. On the session page,
   `UI_SCROLL_TO=<anchor>` (`chart` for the speed chart, `replay`, `summary`, `turns` for
   the turn cards and the drill-in row, `takeoff`, `takeoffsMap` / `takeoffList` for the
   attempt map and its rows, `hr` for the HR-cost card, `gear`, and `wind` / `recording` /
   `divergence` for the Details section's three cards),
   `UI_PLAYHEAD=0.0…1.0`,
   `UI_FULLSCREEN_MAP=1` and `UI_HIDE_LAYERS=<MapLayer,…>` stage the session detail page:
   the last one starts with those legend chips switched off (e.g. `fellIn,courseChange`,
   or one of the layers added later — `pumping`, `takeoff`, `splash` ("wrist under"),
   `direction`), which
   is the only way to photograph a filtered map without a finger. It is applied *after* the stored
   preference and never written back — the override stages a screenshot, it does not edit
   the setting. `UI_MAP_STYLE=standard|muted|satellite|hybrid` does the same for the **ground**
   the track is drawn on (`MapStyleChoice`, docs/presentation.md "Map style"): the control is a
   menu, which `simctl` can no more open than it can tap a chip, and the two photographic
   styles are where the track's halo and its flipped inks are worth looking at. It reaches all
   four map surfaces at once, so one launch photographs the inline map, `UI_FULLSCREEN_MAP=1`
   the big one and `UI_SCROLL_TO=turnsMap` the Turns tab's. Same rules as the layer override:
   applied after the stored preference, never written back. `UI_RECORD=<window key>` (`best10s`, `best250m`, `bestNm`, `bestHour`, …) preselects a
   non-default GP3S window so the map glow and the chart shading can be photographed on
   something other than the best 2 s. All nine kinds since 21 September 2026 — `bestHour`
   is the one whose glow covers half the track, and `2026-08-03-1440` is the fixture that
   has one. `UI_OPEN_TURNS=1` selects the **Turns** section (it
   pushed a page until the drill-in was folded inline, app-ui-review.md §2.1) and
   `UI_TURN_FILTER=<jibes|tacks|both>,<port|starboard|both>` engages its two segmented
   filters (e.g. `jibes,starboard`), which `simctl` likewise cannot tap.
   `UI_TAKEOFF_FILTER=<all|success|failed|free>` does the same for the **Takeoffs** section's
   one segmented filter, so the attempt map can be photographed showing only the attempts
   that did not get up. Both are data filters and are unrelated to `UI_HIDE_LAYERS`, which is
   the layer legend — and note that the three maps now keep **separate** visibility sets, so
   the layer override is applied to every scope that draws the named layer.
   `UI_MAP_CALLOUT=takeoff|failed|end|flight` opens the track callout on the first mark of
   that kind, because the pairing line (docs/presentation.md, "Pairing") is deliberately
   *tap-only* and `simctl` has no finger to tap with. It opens exactly the card a tap opens
   — nothing is staged that a rider could not produce — and `flight` also frames that flight
   in the speed chart, which is the other half of what tapping a flown stretch of track does.
   Two more exist because the zoom features are *gestures*, and `simctl` has no fingers to
   pinch with. `UI_CHART_ZOOM=<factor>` opens the speed chart already zoomed by that factor
   (e.g. `8`), centred on `UI_PLAYHEAD` when one is set — pair the two to photograph a
   deliberately busy stretch with its markers legible, rather than whatever happens to sit
   mid-session. `UI_MAP_ZOOM=<factor>` tightens both maps' opening camera by that factor
   about the same centre; it is the only way to check the direction chevrons at a second
   scale, since their spacing is measured in screen points and therefore *changes* with the
   camera. Both are staging-only, transient, and never written back to any preference.
   `UI_FEEDBACK=fallback` opens the beta feedback mail's **fallback sheet** from the Sessions screen (only the library menu's *Support & ideas* composer answers the hook; the page footers and the session share sheet use the same composer but stay quiet — the hook sat on Settings → Send feedback until that row moved into the menu on 15 Sep 2026) —
   the report in full, with the copy button. It is the only one of the three routes a
   simulator can photograph: `MFMailComposeViewController` refuses to appear where no mail
   account exists, and `simctl` cannot tap the row in any case.
   In the share sheet (`UI_SHEET=share`), `UI_SHARE=fit` flips to the recording tab,
   `UI_SHAPE=portrait|square|landscape` picks the aspect and `UI_STATS=lean|complete` picks
   the stat preset — three controls `simctl` likewise cannot tap. The last one sets the same
   state the picker does but, unlike a tap on the picker, does **not** write the rider's
   stored choice. `UI_TITLE=…` and `UI_CAPTION=…` (schema v9) fill the composer's two text
   fields, which `simctl` cannot type into: they seed the drafts *and* the committed values,
   so the sheet photographs a named session without renaming the one in the library.
   `UI_MAP=1|0` flips the card's **map background** — the `MKMapSnapshotter` ground under the
   track — which is off by default and, like `UI_STATS`, is set here without writing the
   rider's stored choice. It is drawn on whatever `UI_MAP_STYLE` selected, so the two hooks
   pair: `UI_MAP=1 UI_MAP_STYLE=satellite` photographs the case the scrim was tuned against.
   A simulator with no network renders the plain card instead, silently, which is exactly what
   a rider on a beach gets.
   The **cinema replay** (`ReplayCinemaView`, the full-screen replay a clip is recorded from)
   opens with `UI_REPLAY_LENGTH=10|25|60|full`, which stands in for the record button plus the
   setup sheet's own length picker: the setup sheet asks for a **target length** and
   `ReplayPacing` solves the rate, the ease and *which milestones the clip has room for* from
   it, so a hook that named a raw rate would no longer stage the control that exists. At
   `UI_REPLAY_LENGTH=10` the Torbole example runs at 99× and says four things — session start,
   "Flying! · Longest flight · 6:32", "Top speed · 13.47 kn over 2 s", session end — each with
   a dwell long enough to read. `UI_REPLAY_CINEMA=<rate>` still takes a bare multiplier for
   checking the pacing itself, and deliberately does **not** budget the script: at
   `UI_REPLAY_CINEMA=700` on the same 645 s example the map still draws correctly (the track is
   static and the dot is a lookup, so nothing about the drawing is a function of the rate) but
   the captions pile up two deep, which is the artefact the budget exists to remove.
   `UI_REPLAY_FRAMING=portrait|square|landscape|fullScreen` stages the clip's **shape**: the
   replay draws inside a 9:16 / 1:1 / 16:9 box with the rest of the glass painted black, which
   is what the rider composes against and what the finished video is cropped to
   (`ReplayStage`). Since ReplayKit writes nothing in the Simulator, the *staging* is what a
   Mac can check and the *crop* is not — see `ReplayStageTests`, which exports a synthetic
   `AVAssetWriter` movie and asserts the cropped file's pixel dimensions, and the device note
   below. `UI_REPLAY_SETUP=1` opens the setup sheet instead, which is the only screen the
   photo picker and the two pickers live on. On that sheet `UI_REPLAY_MUSIC=<path>` stages the
   **Music** row: the document picker runs out of process, exactly like `PhotosPicker`, so
   `simctl` can no more tap it than it can pick a photo. The path is read by the same code a
   picked file goes through — copied into `Application Support/ReplayMusic/`, measured, refused
   if it turns out not to be audio — so the row it fills in is the real one, not a mock. Put
   the file inside the app's own container first
   (`xcrun simctl get_app_container booted de.lahmann.wingfoil data`), since the simulator's
   sandbox does not reach an arbitrary host path. Both states are worth a look: with the hook,
   the chosen row (name, length, "repeats to fill the 32 s clip"); without it after a clip has
   been started with one, the "Use last: <name>" offer, which is how the remembered track
   comes back — the sheet deliberately opens **silent** every time, because a clip that quietly
   arrived with a song under it is a surprise the rider would find out about in somebody else's
   chat. `UI_REPLAY_RECORD=0` stages the other mode, the
   plain full-screen replay a rider gets when the recorder is unavailable or the permission
   was refused: no countdown, no clip, the transport says "Done".
   **`SIMCTL_CHILD_…` really does mean the environment of `simctl` itself**, not an argument
   after the bundle id: `xcrun simctl launch <dev> <bundle> UI_TAB=records` passes a launch
   *argument* the app never reads, and every hook silently does nothing. Export them, or
   prefix the command:
   `SIMCTL_CHILD_UI_OPEN_SESSION=latest xcrun simctl launch <dev> de.lahmann.wingfoil`.
   A clip is five things in a row — title card, replay, spliced photos, leftover photos,
   outro card — and the two cards are on screen for 2.5 s and 4 s inside a run `simctl`
   cannot pause, so `UI_REPLAY_STAGE=title|outro` parks the run on one of them and leaves it
   there. **Photos cannot be staged**: `PhotosPicker` runs out of process and the placement
   rule is EXIF-driven, so the splice/slideshow split is covered by
   `ReplayStoryboardTests` in the kit and by hand on a phone. The camera gestures are also
   unstageable for the usual reason — pinch and drag on the cinema map are MapKit's own
   (`interactionModes: [.pan, .zoom]`), and `simctl` has no fingers; the "Fit track" pill
   beside "Stop" appears on the same tap and is the only one that is tappable.
   **The Simulator lies about screen recording** — on iOS 26 `RPScreenRecorder.isAvailable`
   is `true` there, the whole flow runs, and the file that comes out is zero bytes, which
   `ReplayRecorder.Failure.empty` turns into an honest alert. So the capture itself is
   device-only; everything around it is not. `UI_REPLAY_CLIP=stub` short-circuits ReplayKit
   and writes a placeholder file with bytes in it, which is how the clip sheet — player,
   size, share link, **Save to Photos**, discard — gets driven on a Mac. (The stub file is
   not a playable movie, so "Save to Photos" on it exercises the add-only authorization and
   then fails at the library, which is exactly the failure alert and the settings deep link
   worth photographing. A successful save is device-only.)
   **Four things only a device can settle.** Whether the *first recorded frame* is the title
   card: the countdown is removed, a `titleSettleS` beat passes and only then is
   `startRecording` awaited, and there is no simulator capture to check it against. Whether
   the **crop lands on the staged box**: the arithmetic and the export are covered by
   `ReplayStageTests` against a synthetic movie, but only a phone produces a recording *of the
   staged screen* to crop. Whether the **music sounds right on the finished clip** — that it is
   there at all, that the fades land, that the loop seam is not audible, and that the preview
   in the clip sheet plays out loud with the ring switch on silent (the sheet claims
   `AVAudioSession.playback` for exactly that, and a Mac has no ring switch to check it
   against); `ReplayClipSoundtrackTests` settles the schedule and the mux, not the listening.
   And whether a clip actually reaches the camera roll.
   **The session video is the opposite case, and that is the point.** The reel
   (`ReelRenderer`, docs/presentation.md "Session video") never touches ReplayKit: it draws
   1080 × 1920 frames into a `CVPixelBuffer` with Core Graphics and writes them through an
   `AVAssetWriter`, so it produces a real, playable .mp4 **on a Mac**. `UI_EXPORT_REEL=1`
   renders one headlessly — no taps, no sheet — and leaves `reel.mp4` in the app's Documents
   directory, with `UI_EXPORT_REEL_LENGTH=15|20|30` picking the cut. It prints one line naming
   the frame count, the staging and encode times and the file size, so a failed render says so
   in the log rather than silently writing nothing.

   ```sh
   SIMCTL_CHILD_UI_IMPORT_FIXTURES=1 SIMCTL_CHILD_UI_OPEN_SESSION=latest \
   SIMCTL_CHILD_UI_EXPORT_REEL=1 xcrun simctl launch <device> de.lahmann.wingfoil
   ffmpeg -ss 2 -i "$(xcrun simctl get_app_container <device> de.lahmann.wingfoil data)"/Documents/reel.mp4 \
       -frames:v 1 frame.png
   ```

   Pulling three frames out — early, mid-cut, and inside the last three seconds — is the check
   that actually finds things, and it found the two worth naming: `CGContext.draw(_:in:)` puts a
   bitmap in *unflipped* space, so a frame drawn top-left like the rest of the app comes out
   with the map and the end card upside down under a correctly placed track; and a semantic ink
   resolved against the wrong appearance disappears, because off-foil grey resolved dark is
   invisible on the light standard map the snapshot is deliberately taken on. Neither is
   catchable in a unit test and both are obvious in one frame.
   `ReelPlanTests` covers the half that is arithmetic — the moments, the warp's monotonicity
   and its two exact endpoints, the round trip, the callout window and the running tally.
   **Apple Health has no hook, and cannot have one** (ADR-017). Every other staging hook fills
   in state the app owns; a workout lives in a database the app is only a *reader* of, and
   writing one to stage a screenshot would mean shipping a code path that puts fake workouts in
   the rider's Health. So the mapping is settled by `HealthImportTests` on synthetic samples,
   and the three things around it are settled by hand, in rising order of effort:
   * **A simulator with nothing in Health** — the honest empty state, and the one worth
     photographing. `UI_SHEET=import`, tap "Import from Health…", tap "Allow CleanJibe to read
     workouts", accept the system sheet. The list comes back empty with the sentence naming
     both possibilities (no workouts, or permission refused) and pointing at Health → Sharing →
     Apps → CleanJibe. **Deny** the system sheet on a second run: it looks identical, which is
     the point — HealthKit refuses to reveal a read denial, so the copy names both.
   * **A simulator with a workout in it.** The Health app on a simulator has no "add workout"
     UI, so there are two ways to get one. Either run **our own watchOS app** on a paired watch
     simulator and record a session — it saves an `HKWorkout` with a live route, and then
     confirms the *skip* rule instead of the import, because it is written by
     `de.lahmann.wingfoil.watchkitapp` and must never be offered (that is the assertion worth
     making). Or write one from a scratch app with HealthKit share permission
     (`HKWorkoutBuilder` + `HKWorkoutRouteBuilder.insertRouteData` with a run of `CLLocation`s
     carrying a positive `speed`); a foreign bundle id is what makes it importable.
   * **A phone, an Apple Watch, and one real session.** The only way to settle the whole path:
     record ten minutes of Surfing with Apple's Workout app, end it, wait for the watch to hand
     the route over, then Import → Apple Health. What to check afterwards, in the session the
     import produced — the track has GPS in it (not an empty map), the speed records are
     **not** marked uncertified (`CLLocation.speed` is the Doppler channel, ADR-016's argument),
     heart rate is present, the pump and takeoff cards say *unavailable* rather than zero, and
     the session's clock is right for where you were. Then import it a second time: it must
     report a duplicate and the library must still hold one session. Then turn on "Import new
     Health workouts automatically", record another, and reopen the app — the banner should say
     "1 session imported from Apple Health" without a tap. Background delivery is the one thing
     that may not fire at all; see ADR-017 on the entitlement, and treat the foreground sweep
     as the behaviour under test.

   **The Help pictures are made with these hooks** (ADR-010). Five topics carry a
   screenshot, and each one is a crop of one staged launch on the `iPhone 17 Pro Max`
   simulator with the bundled example session loaded — so the picture is of a session every
   reader can open for themselves, and nothing in it is Jan's data:

   | asset | launch | crop |
   |---|---|---|
   | `help-session-detail` | `UI_LOAD_EXAMPLE=1 UI_OPEN_SESSION=example` | header + key-metrics block |
   | `help-turn-list` | `UI_OPEN_SESSION=example UI_SCROLL_TO=turnList` | the turn rows |
   | `help-replay` | `UI_OPEN_SESSION=example UI_REPLAY_LENGTH=60 UI_REPLAY_RECORD=0` | track + commentary bubble + progress bar |
   | `help-share-composer` | `UI_OPEN_SESSION=example UI_SHEET=share UI_SHAPE=portrait UI_STATS=complete` | the whole sheet |
   | `help-map-layers` | `UI_OPEN_SESSION=example UI_FULLSCREEN_MAP=1 UI_HIDE_LAYERS=fellIn` | track + both chip rows |

   Two traps found while making them. `UI_SHEET=help` and `UI_HELP_TOPIC=…` are **mutually
   exclusive** — the first raises `HelpView`, the second raises a `HelpTopicSheet` directly,
   and UIKit drops the second of two sheets presented on the same turn; pass `UI_HELP_TOPIC`
   alone to photograph one topic. And `UI_SCROLL_TO` on an anchor that lives on a *different*
   tab now scrolls twice, once immediately and once 400 ms after the tab switch, because the
   anchor does not exist on the first turn of the runloop — before that fix `turnList` and
   `tally` silently produced a shot of the top of the page.

   **Three pictures are still owed, and only Jan can take them** — the intervals.icu setup
   guide's steps happen inside someone else's website and behind his account
   (`scratchpad/copy-review/pictures.md` §H5). The slots, in the order the guide reads:
   (1) intervals.icu → Settings with the Developer Settings / API key section circled;
   (2) the copy-key state; (3) CleanJibe's own Settings with a key pasted and the check
   green. Number 3 needs a live key and a successful call, so it cannot be staged with
   `UI_ICU_KEY` alone. Until they exist, `IcuSetupGuide` stays text-only — the catalogue
   names no asset it does not have, and `PresentationTests` would fail if it did.

   Orientation is the one thing no hook stages: `simctl` cannot rotate a simulator and
   Simulator.app's Rotate menu is not reachable from a headless run (`osascript` clicks it and
   nothing turns — the app has no device window when the device was booted by `simctl` alone,
   and none at all while the Mac is locked). To photograph the landscape frame, temporarily cut
   `UISupportedInterfaceOrientations` — or `…~ipad`, for an iPad — in `ios/project.yml` down to
   `UIInterfaceOrientationLandscapeRight`, `xcodegen generate`, build, shoot, and put it back.

   **The iPad is the same recipe with a different `-destination`.** The app ships for both
   families (docs/presentation.md, "iPad and Mac"), and everything that is iPad-specific about
   the layout — the 740 pt column, the taller figures, the page-sized sheets, the wider record
   columns — only exists when *both* size classes are regular, which no phone simulator ever
   reports. So it is only ever seen by shooting one:

   ```sh
   xcrun simctl list devices available | grep -i ipad     # or `create` an iPad Pro 13-inch
   xcrun simctl boot <ipad>
   cd ios && xcodegen generate
   xcodebuild -project WingFoil.xcodeproj -scheme "WingFoil Dev" -configuration "Dev Debug" \
       -destination "platform=iOS Simulator,id=<ipad>" -derivedDataPath /tmp/dd build
   xcrun simctl install <ipad> "/tmp/dd/Build/Products/Dev Debug-iphonesimulator/WingFoil.app"
   SIMCTL_CHILD_UI_IMPORT_FIXTURES=1 xcrun simctl launch <ipad> de.lahmann.wingfoil
   xcrun simctl io <ipad> screenshot library.png
   ```

   Every hook above works there unchanged, and the screens worth a look are the ones whose
   shape the size class actually changes: the library, all four session sections, the turn and
   flight-end sheets, Records (the speed table's fixed columns), Trends, Gear & spots,
   Settings, Tuning, Help and both card composers. The fixture import is the slow part — about
   75 s — and it only has to happen on the run that passes `UI_IMPORT_FIXTURES=1`; every later
   launch on the same simulator opens in a few seconds against the library already there.
   **The app's own tests — `WingFoilTests`** (`ios/WingFoilTests`, target and scheme wiring
   in `ios/project.yml`). The kit's suite holds everything that can be stated without an app
   around it; this holds the three rules that cannot. It is hosted by the `WingFoil` target
   under `Dev Debug`, hangs off the **WingFoil Dev** scheme only, and is DEBUG-only — no
   Release or archive action builds it.

   ```sh
   cd ios && xcodegen generate
   xcodebuild test -project WingFoil.xcodeproj -scheme "WingFoil Dev" \
       -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
   ```

   - `HelpButtonTests` — **every `?` in the app opens something.** `HelpCatalog.topic(_:)`
     traps rather than returning nil, so a card pointing at a topic nobody wrote is a crash
     on the tap. The topics are read out of the app's own sources (`AppSources`, the same
     `#filePath` trick `CopyLintTests` uses in the kit): every `.case` token on a line that
     names `HelpButton`, `HelpSectionHeader`, `HelpTopicSheet`, `helpTopic` or `help:` that
     is a real `HelpTopicID`, asserted to resolve to a written title, summary and body in
     this build's channel — and the same for every id in every topic's `related` list. The
     scan asserts its own floor first (≥ 20 distinct topics), so a pattern that silently
     matched nothing fails rather than passes.
   - `SessionTitleTests` — **a session is never called by its identifier.** The Apple Watch
     app filed its containers under the recording's UUID until 0.9.13 and a tester read
     "EE94C0B1 359A 4FED …" off his own library; `SessionDisplay.title` is what all eleven
     surfaces call, and four shapes of identifier filename come out as `Wingfoil` instead.
     The other half of the rule is pinned beside it, so it cannot be satisfied by calling
     everything Wingfoil: a real filename still becomes its own name, and the rider's own
     title still wins.
   - `CrashDiagnosticsTests` — the feedback mail carries the **Recent crashes** block when
     the phone has kept one, the file survives the launch that wrote it, a re-delivered
     payload is still one crash, and a phone that has never crashed says nothing at all.
     What a MetricKit payload *means* is the kit's (`CrashDigestTests`); this is the file
     and the mail. The `UI_TEXT_SIZE` ladder is pinned here too, being the one part of that
     hook that can be read without a launch.

3. **Monkey C units (Toybox.Test)** — the core suite lives in the `WingFoilCore` barrel
   (`garmin/barrel/WingFoilCore/tests/`) and is therefore compiled into **both** consumers'
   `--unit-test` builds: `bin/WingFoilTests.prg` (device app) and `bin/WingFoilFieldTests.prg`
   (data field: the core tests plus the field's own schema/feed/layout tests). Contents:
   RingBuffer math; FlightDetector/TurnDetector fed synthetic + recorded 1 Hz speed/COG arrays
   (extracted from fixtures by lab) asserting exact transition ticks, including the turn
   **streaks** — dry survives a touchdown and dies on a fall; a rejected sweep neither extends
   nor breaks a run; and a swim that no turn explains breaks both runs through the watch's own
   flight-end approximation, while a GPS gap during one breaks neither; PumpDetector fed
   recorded 25 Hz batches, including the attempt **join grace** (a breather mid-bout is one
   attempt, not a failure plus a success); SpeedRecords vs hand-computed windows.

   **AutoWind** (device app ≥ 0.9.0) is tested on both halves. Synthetic histograms in the
   barrel suite cover the axis, the two sample gates, the two-evaluation confirmation, the
   hysteresis, the default-turn-type prior (including `balanced` refusing to resolve a coin
   flip) and the one-shot backfill. The real-data half is `autoWindReplayFixtures` in
   `garmin/tests/WingfoilTests.mc`: it replays the recorded 1 Hz cog/speed/foil-state stream
   of **both `ciq` fixtures** — `garmin/tests/AutoWindFixtures.mc`, regenerated by
   `cd lab && uv run python tools/make_autowind_arrays.py` (`--check` fails when stale) — and
   asserts the estimator locks, lands within **±20°** of the phone engine's `wind.dirDeg` for
   that session, and never flips after locking. The generator is a test-data tool, not engine
   code; it carries a Python transcription of `AutoWind.mc` the way
   `tools/watch_pump_replica.py` carries one of `PumpDetector.mc`. Its arrays are
   `(:debug)`-annotated rather than `(:test)`, because the unit-test runner treats every
   `(:test)` function as a test case; `--release` strips `(:debug)` just the same (verified:
   the 0.9.0 release `.prg` is 83 kB and contains none of the 14 kB of fixture strings).

   Running them:

   ```
   The compiler is a JVM without an `-Xmx` of its own; run it with
   `JAVA_TOOL_OPTIONS=-Xmx2g` in the environment (package.sh exports it) or three parallel
   builds sit at 7 GB each on a 32 GB Mac (21 Sep 2026; a device build peaks at 0.6 GB pinned).
   monkeyc -f garmin/monkey.jungle -d fenix847mm -y garmin/developer_key.der \
       -o /tmp/wft.prg --unit-test
   connectiq &                      # the simulator must be up; monkeydo attaches to it
   monkeydo /tmp/wft.prg fenix847mm -t
   ```

   Run it on **four** glasses at least, one per family the product list now spans:

   | device | glass | why it is in the matrix |
   |---|---|---|
   | `fenix847mm` | 454 px AMOLED | the widest glass and Jan's own watch |
   | `fenix7s` | 240 px MIP | the narrowest shipped |
   | `epix2pro42mm` | 390 px AMOLED | the size added with Tier A (0.9.4) — also marq2, marq2aviator, descentmk343mm, fr57042mm |
   | `fr255` | 260 px MIP | the smallest memory tier (524 KB) **and** the Forerunner font set |
   | `venu3` | 454 px AMOLED, Venu font set | 0.9.10: the Venu / vivoactive / Instinct 3 AMOLED families — touch-first, two buttons, their own fonts. Their first run found the hero fitter's half-pixel rounding. Also worth a run: `venu2s` (360 px, the smallest AMOLED glass shipped) |

   **Every family, photographed** (0.9.13). The unit suite asserts rows from font heights,
   and a font set can break the assumption the rows were stacked on: the fenix 5 Plus
   family's number fonts have no leading (ascent = line), so bands built on "ink is 3/4 of
   the line" were a quarter of a number line short there — the clock on the giant's unit,
   PAUSED as six empty boxes, SAVED on the verdict — and the suite was green (a store user
   on a fenix 5X Plus found it, 17 Sep 2026). `RecordingView.inkH` is the firmware's ascent
   for a number font now, floored at the old 3/4; but the rule that a layout is verified
   only by looking at it stands. `garmin/screenshots/` is the harness: `ShotsApp.mc`
   (throwaway, never committed) cycles the 22 screens on a real session every 3 s, and
   `screenshots/tools/capture.sh <device> <outdir>` starts a fresh simulator, runs it,
   photographs the device window once a second by its window id and tiles the distinct
   frames into `<outdir>.png`. Compile the harness for the device first
   (`monkeyc -f garmin/screenshots/monkey.jungle -d <device> -y garmin/developer_key.der
   -o garmin/bin/shots-<device>.prg`; the harness manifest lists the products it may be built
   for, add one per family). Run it once per family in the product list before a store upload
   that touches a page, and read every sheet against the overlap list: clock/giant, caption/
   digits, eyebrow/giant, pair halves, the PAUSED word. Run on 19 September 2026 across all
   27 device ids the harness manifest lists, one per family: no overlap on any of them. The
   Mac has to be unlocked and its display awake for the run (the script asserts user activity
   per cycle and refuses a locked screen).

   **The rule is a gate, and a locked Mac is not an exemption.** 0.9.16 changed the page
   layouts (a second page SET, the foil table's title row, the SAVED pill's lift), so it owed
   the sheets before any upload. They were **not run on 20 September 2026**: the Mac was
   locked (`CGSSessionScreenIsLocked = Yes`) for the whole session and `capture.sh` refuses
   that by design — `screencapture` cannot read a window behind the lock screen and returns
   blank frames rather than failing, which is the one failure mode a screenshot harness must
   never have. The unit suite carries the geometry in the meantime; it does not carry what a
   frame looks like. **Run on 21 September 2026** once Jan unlocked the Mac: 29 sheets, one
   per family the harness manifest lists (the fenix 5 Plus family included), each read against
   the overlap list — clock/giant, caption/digits, eyebrow/giant, pair halves, the PAUSED
   word — and the round's three new pairs: the large set's word against its giant, the foil
   table's `foil · 31` against the shares row under it, and the lifted SAVED pill against both
   the phone line under it and the verdict's digits. No overlap on any of the 29; the one gap
   found is the harness's own (its story page feeds no speed samples, so the top-speed
   sparkline is empty on every family), not the app's. Only then went 0.9.16 to the listings.
   The harness cycles **22 screens** since 0.9.18 — start, the 8 standard pages, the **5**
   large-text pages and the 8 summary pages; it was 24 between 0.9.17 and 0.9.18, when the
   large set still carried a clock and a best-2s screen. At 3 s a screen that is a 66 s cycle,
   so `capture.sh` photographs **95 frames** at 0.8 s (76 s, one whole pass with ten seconds
   of margin) inside a 240 s `caffeinate` window.

   **Run on 21–22 September 2026 for 0.9.18** (Jan's layout review), on the short set — the
   six glasses below — with the two principles of that round added to the overlap list: the
   widest line on each page is on the equator, and no word is drawn as large as the number
   beside it. Three rounds of sheets, because the first two each found something, and read
   clean on all six at the third. **What the sheets caught that the unit suite did not:**

   - the post-save **Takeoffs** page's HR line was being shed on **every** glass. Jan's sketch
     put the two smaller facts on one row with a separator, and "4.3 pumps each · last +19 bpm"
     is 28 characters — 560 px against a 406 px chord on a fenix 8 — so the half the page never
     drew was the half nobody could have noticed was missing. Two narrow rows now, and the
     test asserts each fits its own row at its own worst case.
   - the post-save **Track** page was still drawing its distance in FONT_SMALL with a space in
     it while the live Map page had moved to the bigger form — a unification leaking at its one
     remaining seam. One renderer draws that odometer now.
   - the large set's **outcome row** was fitted from the NUMBER ladder and banded on a TEXT
     font, because the constant meant one array and was read as the other. On a 454 px glass
     the chord stepped the row down far enough to hide it; on a 390 px **Instinct 3 AMOLED**
     the word under the giant was drawn straight through the digits. This is the one that
     justifies the whole ritual: the unit suite was green on every glass, and it was green
     because it was asking the same wrong question the renderer was.

   None of the three is a geometry the row-stack assertions could see. The first is a string
   measured against a chord, the second is two pages agreeing about a font, and the third is a
   band and a ladder indexing two different arrays — which is now asserted outright (the row's
   own ink must fit the band it was stacked with).

   **The short set (Jan, 21 Sep 2026: "we don't need to review all families every time").**
   A change to a page's *content* — a new page, a row added or reworded, a number moved
   between rows — owes six sheets, one per glass the row stack has to fit, and they are read
   against the same overlap list: `fenix5xplus` (240 px MIP, the Chronos number fonts with no
   leading — the 0.9.13 family), `fr255` (260 px MIP), `venu2s` (360 px AMOLED, the icon54
   cut), `epix2pro42mm` and `instinct3amoled45mm` (390 px AMOLED, two font families),
   `fenix847mm` (454 px AMOLED). `SHEET_DEVICES="fenix5xplus fr255 venu2s epix2pro42mm
   instinct3amoled45mm fenix847mm" sheets.sh <outdir>` runs exactly those. The full 29 are
   owed only when the *layout engine* moves — the row stack, the fitter, the ink bands, a font
   choice — or when a family joins the manifest. 0.9.17 (a page added, no engine change) was
   read on the short set, and so was 0.9.18: it moved a great deal of page CONTENT and the one
   thing it added to the fitter — the large giant's vector-font probe — has the bitmap ladder
   as its floor by construction and is asserted to never come out narrower, so no family can
   be worse off than the sheet before it.

   The layout suite reads its canvas from `System.getDeviceSettings().screenWidth`, so the same
   assertions are genuinely different measurements per device, and every finding that has ever
   come out of this suite came from the narrow ones — with one lesson added by Tier A: **the
   screen size is not the whole device**. The Forerunners carry a different font set from the
   fenix at the *same* resolution (on 260 px glass `FONT_NUMBER_MILD` is 45 px on an fr255
   against 58 on a fenix 8 Solar; on 416 px glass `FONT_LARGE` is 67 px on an fr265 against 61
   on an epix 2), and both of the layout findings behind 0.9.4 came from that, not from the new
   390 px size, which passed the whole suite unchanged. So a new *family* earns a run even when
   its resolution is already covered. Start one simulator per run and kill it afterwards: two
   `monkeydo` processes against one simulator hang rather than fail.

   **The watch's crash hunt** (0.9.14, `fuzz*` / `crashBreadcrumb*` in
   `garmin/tests/WingfoilTests.mc`). The phone's hunt exists because a stranger's FIT is a
   door nobody here has walked through; the watch's exists because **a Connect IQ device has
   no crash reporting at all**. An unhandled exception drops the rider to the watch face and
   writes `GARMIN/APPS/LOGS/CIQ_LOG.YML` onto a watch on a beach, and the session goes with
   it. Three doors are fuzzed, and the bar is the phone hunt's — *finish, or throw something
   named; never trap*.

   **Four ways to die on this runtime are NOT catchable**, which is why every fix in this
   round is a guard and never a `catch` (measured on fenix847mm, SDK 9.2, each inside a
   `try`/`catch` that did not fire):

   | expression | what happens |
   |---|---|
   | `1.0 / 0.0` | `Error: Invalid Value`, uncaught — the Float division itself, not `.toNumber()` |
   | `0.0 / 0.0` | the same |
   | `5 / 0` | the same |
   | `a[past the end]` | `Error: Array Out Of Bounds`, uncaught |

   Two that *are* survivable and worth knowing: `null > 0` throws a catchable
   `UnexpectedTypeException`, and `Float.toNumber()` **saturates** at ±2147483647 rather than
   trapping. `Properties.setValue` accepts a String, a Float or a null into a property
   declared `number` and hands it straight back, so a settings type check is not paranoia.

   - **the sensor door** — `fuzzSensorDoorSurvivesEveryDegenerateFix` drives twenty fix
     shapes five ticks each through `SessionController.onPosition`: no position, no speed, no
     heading, no altitude, no accuracy, `QUALITY_NOT_AVAILABLE`, an accuracy outside the enum,
     speed 0 all session, 300 m/s, negative, a Number where a Float belongs, a heading of
     ±1e9 rad, an altitude of 1e9 m, the poles, the antimeridian, an Info with every member
     null, and a null fix. `fuzzTheClockRunsBackwardsAndWraps` adds a 30 s gap, a sample that
     arrives before the one before it, and the `System.getTimer` wrap (~24.8 days of uptime,
     which a watch that is never rebooted reaches). The drive loops move the clock through
     `MetricsEngine.clockMsOverride`, a test seam: `tick()` reads dt from `System.getTimer()`,
     so twenty thousand calls in a loop would all see dt ≈ 0 and exercise nothing.
   - **the settings door** — `fuzzSettingsClampWhateverTheStoreSays` writes 0, −1, a huge
     Number, a Float, a String and null into fourteen properties in turn and asserts that
     every threshold still lands inside docs/algorithms.md and that the rider is never left
     with a blank watch. `AppSettings.load` clamps to the same min/max
     `resources/settings/settings.xml` declares; Garmin Connect enforces those on the slider
     and nothing enforces them on the value that arrives.
   - **the phone door** — `fuzzPhoneMessagesNeverThrow` puts twenty-six malformed messages
     through `PhoneLink.applyMessage`: not a dictionary, empty, wind as a Float / a String /
     −2 / 360 / null / 20 KB, a snapshot with the wrong schema, a 0×0 grid, a 100000×100000
     one, a 20 KB name, and `cjrAck`/`cjrNeed` in every shape `DirectSend` can be handed. It
     also plants a half-written map slot in Storage — the shape an older build leaves — and
     asserts the draw path refuses it rather than dividing by its grid.
   - **the accelerometer door** — `fuzzAccelBatchesSurviveEveryShape`: null arrays, an empty
     batch, one sample, a hundred, a ragged trio, **nulls inside the arrays**, saturated
     magnitudes, and the timer wrap between two batches.
   - **six hours at 1 Hz** — `fuzzSixHoursAtOneHertzHoldItsMemory` drives 21 600 ticks with
     `System.getSystemStats()` either side.

   | device | used before → after | growth | 14 direct-stream pages held → freed |
   |---|---|---|---|
   | `fenix847mm` | 284 248 → 287 344 B | **+3 096 B** | 275 304 → 383 872 → 275 384 B (+80 B) |
   | `fenix7s` | 284 136 → 287 232 B | **+3 096 B** | 275 192 → 383 760 → 275 272 B (+80 B) |
   | `fenix5plus` | 345 952 → 349 048 B | **+3 096 B** | 337 008 → 445 576 → 337 088 B (+80 B) |

   The same number on all three is what a chain with no per-tick allocation looks like — the
   track buffer, the timeline and the sweep log are fixed arrays, and the breadcrumb's stride
   doubles rather than the buffer growing. **These are the SIMULATOR's numbers**: it reports
   an 8 MB heap where a fenix 8 gives the app 786 KB, so what the run proves is the growth and
   not the device's headroom. The free-memory floor the test asserts (> 100 KB) is a smoke
   alarm. Six hours takes about a minute per device.

   **The crash breadcrumb** (`CrashBreadcrumb`, `crashBreadcrumbCountsAnUnclosedRun`). Three
   Storage keys stand in for the crash reporting the platform does not have: `runOpen` is set
   in `onStart` and cleared in `onStop`, so finding it at the next start means the previous
   run never closed; `crashCount` counts those; `lastView` is the screen it was on, written
   by the views' `onShow` and **deduped**, one write per view change and never per frame. The
   count rides to the phone on the summary card as `cx` — twenty-two keys, 201 B of the
   1024 B budget, so it fits with room to spare — and the dev build also writes
   `crashes N (last: view)` onto the link probe's Results page at start. **The phone's half**
   is three suites in the kit: `CompanionTests` (a card with `cx`, without it, and with an
   unreadable one — only the first carries a number and none of the three is refused),
   `MigrationTests.v18AddsTheWatchCrashCountAndLeavesOldRowsUnanswered` (the column, and every
   older row NULL), and `CrashDigestTests` (the mail's three states). It cannot see *why*,
   and a battery pulled mid-session counts as a crash; what it buys is a number a tester can
   read and a page name to look at first.

   Running the hunt: it is part of the suite, so `monkeydo <prg> <device> -t` runs it —
   `-t` with no argument runs everything. Latest, 0.9.18-dev1: `monkey-dev.jungle`
   **136/136** and `monkey.jungle` **126/126**, both on fenix847mm, fenix5xplus and fr255,
   0 failed. The ten-test gap is the `(:test :dev)` cases the beta and the release exclude
   (`excludeAnnotations = dev`), less the one `(:test :notdev)` mirror. The five newest are
   the wrist stream's and the packed page's — `directWristStreamMatchesTheReference`,
   `directWristWindowOpensWithASecondOfLookBack`, `directWristHoldsItsBudget`,
   `directWristRidesAfterTheRecordStream`, `directPagesPackFourBytesPerNumber`.

   **One simulator per run**, started and killed around each `monkeydo`: two against one
   simulator hang rather than fail. And `JAVA_TOOL_OPTIONS=-Xmx2g` in the environment for
   every `monkeyc`, with `pgrep -fl Monkeybrains` empty at the end of the round.

   **Round-display layout tests.** Six pages plus the summary are measured against the chord
   at each row's own depth, at worst-case content, with the device's real font metrics:
   `mainPageFitsRoundDisplay`, `heroPageFitsRoundDisplay`, `gridAndCellsPagesFitRoundDisplay`,
   `recordsPageFitsRoundDisplay`, `turnsPageFitsRoundDisplay`, `clockPageFitsRoundDisplay`,
   `timelinePageFitsRoundDisplay`, `startPageFitsRoundDisplay`, `lockScreenFitsRoundDisplay`,
   `summaryPagesFitRoundDisplay` and `pausedBannerStaysInsideTheRings` — and since 0.9.16
   `largePagesFitRoundDisplay` (the LARGE page set: the giant against the chord, the word
   never below FONT_SMALL, and the giant never *smaller* than the same value on a hero page,
   which is the claim the whole set exists to make), `largePageSetIsFivePagesOfOneNumber`
   (five pages, one metric each, no map, and the standard set restored on the way back),
   `foilTitleCarriesTheFlightCount` and `phoneProgressLineNeverTouchesWhatMatters`.

   Two of those measure a **conditional** layout and say so in their debug line rather than
   asserting one answer, because the answer is a property of the font set:

   - the direct transfer's status line on the SAVED screen is drawn at the top on
     `fenix847mm` (pill 70 → 33, line 70, digits 92) and `fenix7s` (39 → 20, 39, 50), and
     **dropped on the fenix 5 Plus family** — its hero block starts 16 px higher than
     everyone else's (the 0.9.13 finding), so `savedY` is already pinned against the verdict's
     digits at y 27 and the bottom band's fallback slot at 194 runs into the hero block at
     198. The renderer and the assertion ask the one predicate, so a font set that would
     overprint the verdict fails here rather than on a wrist.
   - `standardPagesTextHeadroom` is a **diagnostic, not a gate**: for every caption pinned at
     FONT_XTINY it logs whether the next rung up fits the chord *and* whether the row stack
     still holds it. Measured 20 Sep 2026: chord yes / stack **no** on fenix847mm and
     fenix7s for all three rows tested (hero unit line, records labels, foil column headers),
     chord yes / stack **yes** on fenix5plus. A rung taken on that evidence would be two page
     geometries per font set, so none was taken on the standard pages and the rung went to
     the large set instead (docs/presentation.md). They assert against
   `RecordingView.fitRadius(dc, ring, arc)` — the *page's* radius, not the glass, because a
   page that paints the flight ring or the foil-% arc has already spent the outer 10–16 px of
   every radius on it. Two rules they exist to keep:

   - **A row's pitch is never smaller than its line height.** The pre-0.8.0 summary advanced
     32 px at a font whose line height is 53, so consecutive rows overlapped by 7 px of ink.
     Every stack is now built from `dc.getFontHeight()` and asserted.
   - **A value never degrades to a label font.** `FONT_XTINY`/`FONT_TINY` are ~21–27 px of
     digit, below what is readable at arm's length in spray; rows that cannot fit drop
     *content* (the tally sheds its verdict, then its separators) rather than size. The one
     documented exception is a GRID4 value cell on the 240–280 px MIP variants, where a
     giant + a 2×2 + the bezel arc genuinely does not fit and the floor is `FONT_SMALL`.

   **No known failures since 0.9.4.** The suite is green on all 30 products in the manifests.
   The long-standing `lockScreenFitsRoundDisplay` failure on `fenix7s` (240 px) went with the
   0.9.4 lock-screen fix below. It was never the row collision it was filed as: the fenix 7s
   carries the same digits-only `BionicBold` cut, the fitter measured the code at **0 px** wide
   and took an 84 px face on a 240 px glass, and the rows collided because of it. (Verified by
   putting the old `LockView.mc` back: `row 2 y=108 0x84`.)

   **0.9.5: 92/92 on all four glasses** (`fenix847mm`, `fenix7s`, `epix2pro42mm`, `fr255`),
   three tests added — `cleanJibeBuzzReplacesTheFlyThroughTick`,
   `cphIsNullBeforeAMinuteAndAValueAfter` and, in the barrel,
   `cleanJibesAreSuccessfulJibesAndNothingElse`. The release earned its own entry in the
   list of findings this suite has produced, and it is the usual one: the Turns page gained a
   **sixth row** (the clean jibes and their CPH), and because the stack is centred, the band
   that row reserves pushes every row under it deeper into the arc. At `FONT_MEDIUM` on a
   454 px glass that cost the verdict row its port/starboard split by **six pixels** — 304 px
   of ink into a 298 px budget — which is the one number on the page a rider can act on
   tomorrow, and it would have been invisible in a screenshot of a session with a wind axis
   nobody looked twice at. Pinning the new row at the `FONT_SMALL` floor (`CLEAN_FROM`) buys
   it back with room over: the split is on again at 454 px and 390 px, and the 240 px fenix 7s
   drops it exactly as it did in 0.9.4, for the same reason. *(That row and its rate are gone
   since 0.9.18 — the clean count joined the ladder row it refines and CPH left the watch — and
   the split now fits at the floor font on **every** glass, which the test asserts outright
   rather than only on the AMOLED ones.)*

   **0.9.18: 131 dev / 126 release / 126 beta, on nine glasses** (`fenix847mm`, `fenix843mm`,
   `fenix5xplus`, `fr255`, `venu2s`, `venu3`, `epix2pro42mm`, `instinct3amoled45mm`,
   `fenix7s`) — and **136 / 126** from 0.9.18-dev1, whose five new cases are all
   `(:test :dev)`. The layout round's own numbers were: 127 dev / 122 release / 122 beta, on
   eight glasses (`fenix847mm`, `fenix5xplus`,
   `fr255`, `venu2s`, `venu3`, `epix2pro42mm`, `instinct3amoled45mm`, `fenix7s`), for Jan's
   layout review. Four tests are new and each of them guards something the round could get
   wrong in a way no sheet would show:
   - `WingFoilCore.perKindOutcomesAddUpToTheKind` — the six per-kind counters' arithmetic:
     per kind, `flew + touch + fell` is that kind's count for every turn typed after the axis
     holds, and at most it after an auto-wind backfill, which adds kinds and no outcomes. A
     row that does not add up to the number above it is a page arguing with itself.
   - `aShrunkPageSetNeverStrandsAnIndex` — the large set went from seven screens to five and a
     page index does not go with it (`PageNav.index` outlives any rebuild). An out-of-bounds
     read is **not catchable on this runtime**, so "we would see it throw" is not a thing that
     happens here: it asserts `BIG_SLOT` is at least `BIG_PAGES` long, and that every accessor
     a frame calls wraps a stale index rather than clamping and hoping.
   - `takeoffPageSaysWhatItCounts` — the rewritten S6, including the claim that each of its two
     detail lines fits its own row at its own worst case, which is exactly what the one-row
     version failed.
   - `mapOdometerAndWindMarkAreBigEnoughToRead` — the map caption is above the floor it used to
     be pinned at, its unit is smaller than its digits, and the wind mark does not borrow the
     outcome ladder's ink.

   **0.9.18's second and third rounds** added four more, for the show/hide switches and the
   tack/jibe rebuild:
   - `hidingAPageTakesItsTwinsWithIt` — the seven switches' MAPPING, one switch at a time and
     asserted on page ids rather than on a count, because what goes wrong here is a switch
     wired to its neighbour and no test that turns them off together would see it. The
     Tacks & jibes switch takes BOTH large-text kind screens; the Foil switch takes S·Takeoffs.
   - `aSwitchThrownMidSessionNeverStrandsTheRider` — a rider standing on the Map page when its
     switch goes off. An index past the end of the page list is an uncatchable error on this
     runtime, so this is not a glitch test.
   - `theSheetHarnessIgnoresTheShowSwitches` — a sheet photographs every page the app can draw
     whatever the simulator's property store says (`PageModel.showAll`).
   - `WingFoilCore.autoWindOpposedLobesStillResolve` — one beam reach and its reciprocal, at
     exactly 180°, in two passes: the axis is computed (the 179° refusal is gone) and with a
     cone to decide on it comes out on the PERPENDICULAR, never on a lobe.

   ...and `WingFoilCore.perKindOutcomesAddUpToTheKind` tightened from `<=` to `==`, which is
   the whole point of the rebuild: all eleven per-kind counters are recomputed together from
   the turn log, so a kind's count and its rungs can no longer come from different populations.

   **The data field's own layout suite** (`garmin/field/tests/FieldTests.mc`) is the same idea
   on a canvas nobody chose: a data field is handed whatever rectangle the rider's activity
   layout leaves it, so `layoutRowsNeverClip` walks the *measured* cell rectangles of all
   twelve Garmin layouts (read off the simulator with `garmin/field/screenshots` running — it
   prints `CELL wxh flags n` on every change) and asserts every row of every cell sits inside
   its cell, clear of its neighbour, and inside the chord at its own depth. 0.9.5 added four
   more: `fullScreenCarriesTheAppMainPage` (the 1-field page really does carry the device
   app's Main composition — a NUMBER-font giant, the two-line caption beside it and a dot
   ladder with room for a double-figure run of turns), `summaryPagesFitTheFullScreenCell`
   (both paused pages, every row labelled), `configuredSlotsNeverClip` (the same never-clip
   loop run once per metric in the settings list, with that metric in every configurable slot
   at once — 18 metrics x 33 cells on a fenix 8) and `slotDefaultsAreTheOldRows` (the promise
   that an install which never opens the settings page sees what it saw in 0.9.4).

   0.9.6 added three more, all about the clean jibe: `cphIsARatePerHourWithAMinuteFloor` (the
   division and, more to the point, the 60 s floor — below it there is no rate and the row
   prints `--`, at exactly 60 s there is, and a zero *above* the floor is a real observation
   that must not be dashed away), `cleanMetricsReadTheDetectorAndTheTimer` (the count comes off
   `TurnDetector.cleanJibeCount` and the denominator is the engine's timer, not foil time — the
   divergence recorded in algorithms.md) and `cleanRowsBudgetTheStarAsOneCharacter` (the star
   is not text, so the worst-case tables spend `FieldLayout.STAR_STANDIN` on it and the drawing
   code reserves a box exactly that wide; if the two ever disagreed the fitter would be sizing
   a row the field does not draw). Counts: **61/61** on `fenix847mm`, `fr255`, `epix2pro42mm`
   and `fenix7s` — the four-glass matrix above, run for 0.9.6 because the new content lands on
   the row that was already the widest on the Main page.

   That row is also where 0.9.6's one layout finding came from, and it is the same lesson as
   0.9.5's: **a caption is width taken out of the value's window.** Putting the star, the count
   and CPH beside the outcome tally made the Main page's row 3 434 px wide in a 405 px window
   on a 454 px fenix 8 — of which "outcomes" was 142 — so `fitCell` dropped the captions from
   the *whole page* and `fullScreenCarriesTheAppMainPage` failed, which is exactly what it is
   for. The fix was to spend the word where it is load-bearing: the caption is now `cph` (55
   px), because a bare "4.5" beside two counts means nothing, while the clean count is named by
   the star in front of it and the three outcome counts by the three inks they are drawn in.
   346 px in 405 on the fenix 8, 314 in 342 on an epix 2 Pro 42 mm, 170 in 233 on an fr255,
   170 in 207 on a fenix 7S.

   `configuredSlotsNeverClip` deliberately does **not** assert the tabled SIZE per cell: a
   wider metric legitimately steps a cell down, and pinning the size would pin the
   configuration rather than the invariant. What it does pin is that both halves of the
   caption trade happen somewhere on the glass — 197 captioned / 379 bare on a fenix 8, 239 /
   211 on an fr255 — because a rule that never fires is a rule nobody is testing.

   **Two simulator facts 0.9.5 had to establish by experiment**, neither documented anywhere:

   - A data field's `compute()` and `onUpdate()` run whether or not an activity is recording,
     and `Activity.Info.timerState` is the only thing that says which is happening. With no
     activity started the simulator reports **0** (`TIMER_STATE_OFF`) and still draws every
     second — which is what the paused summary face hangs off. The harness prints
     `TIMERSTATE n` on every change so this stays checkable.
   - On an AMOLED product the simulator renders the display's **black as transparent**, so the
     watch-body art underneath (bezel, tick marks, the 50/40/20 numerals) shows through every
     pixel a dark app paints — and a store screenshot cropped straight out of the window has a
     fenix bezel drawn across it. The capture script therefore shoots one extra frame per
     layout with the field cleared and nothing else on it, and composites: a pixel that still
     equals that frame is one the field left black, a pixel that differs is ink. It also
     calibrates the crop rather than hard-coding it (a white background makes the display disc
     the one bright thing in the window), because the simulator's zoom of the watch image is
     not stable between launches.

   Three things the Tier A pass found, all worth knowing before touching the code they live in:

   - **A vector font will happily measure glyphs it does not have.** On the epix 2 / epix 2 Pro
     / MARQ 2 / Descent Mk3 families the face named `BionicBold` is `Bionic_Bold_Number_Only`,
     digits only. `dc.getTextWidthInPixels("WWWWWWWW", vf)` answers **0** there, which every
     width test in a fitter reads as "fits comfortably" — so the lock screen's fitter took the
     largest size on its list and would have drawn the tester's request code with its letters
     missing. `LockView.coversAlphabet` now asks each candidate face for every character of
     `LockGate.ALPHABET` and rejects the first one that comes back empty, and faces are tried
     one at a time rather than as a preference list so a number-only cut falls through to
     `RobotoCondensedBold` instead of poisoning the whole size.
   - **The GRID4 giant band is no longer exactly one `FONT_NUMBER_MILD` line.**
     `RecordingView.giantBand(dc, paired)` lends the *paired* band one more pixel on the
     fr255/fr955, whose MILD line (45 px) is one pixel short of a caption plus `FONT_MEDIUM`'s
     ink (46 px). Every other watch is untouched, and the unit test asserts that.
   - **"The shipped session's six numbers are FONT_LARGE" is now asserted as "the largest rung
     the column can hold".** On the fr265 that rung is `FONT_MEDIUM`: its `FONT_LARGE` "63:24"
     is 142 px in a 136 px column, and the page's one lever — shortening the row keys — buys
     only 2 px there, because "max" is nearly as wide as "total" on that face.
4. **Simulator integration smoke** — FIT replay of `fixtures/clips/` (60–180 s cuts around
   labeled events; replay is realtime-only, keep clips ≤ 3 min) with a documented expected
   checklist per clip: flights detected, laps emitted, PB alert fired. Plus MonkeyGraph preview
   of dev-field charts.
5. **Beta App upload (phase 1–2)** — alternate-UUID listing; the only way to verify GCM settings
   UI and `fitContributions` rendering in Garmin Connect. Do early.
6. **Watch-vs-phone divergence banner** — standing field-regression alarm on every class-(a)
   import (thresholds in `algorithms.md`).

## The direct transfer — `DirectStreamTests` and the pinned 64 bytes

`docs/transfer-format.md` is the contract, and **three implementations encode those bytes**:
the watch in Monkey C, `lab/tools/cjr_ref.py` in Python, and `DirectStreamEncoder` in the kit.
Nothing keeps three encoders in step by being read, so all three are held against one hex
string — the worked example of §2.3, three fixes a second apart at Lake Garda, **64 bytes**.
`python3 lab/tools/cjr_ref.py --check` re-derives it and decodes it back, the watch's
`WingfoilTests` does the same, and the kit's `DirectStreamTests` carries it copied character
for character out of the document. A change to those bytes is a change to the format and has
to be made in four places on purpose.

`fixtures/direct/example.cjr` **is** those 64 bytes, committed, so a decoder in any language
can be pointed at a file instead of at a hex string. It is not a recording and is not derived
from one; `fixtures/direct/README.md` says how to regenerate it.

**The same arrangement for stream 1** (`wrist.v1`, 0.9.18-dev1, §2b): **38 bytes**, one
window of five 25 Hz samples, pinned by `cjr_ref.py --check`, by the watch's
`directWristStreamMatchesTheReference`, by the kit's `DirectWristTests` and by
`fixtures/direct/example-wrist.cjr`. Four places again, and on purpose again.

`lab/tests/test_cjr_ref.py` is the reference's own suite — 21 tests. It imports `cjr_ref.py`
**by path** (it lives under `tools/`, not in the package, and has no dependency beyond the
stdlib) and covers: the two worked examples against their hex; a 2 000-record session with a
pause, an altitude that disappears and returns, and a position jump, round-tripped with every
field exact and the positions inside a micro-degree; 200 wrist windows over several pages,
each page opening with a window header; the escape at every boundary; every cut length of a
torn wrist stream raising rather than guessing; and the packed page round-tripping at every
remainder, including the word whose high bit makes a Monkey C Number negative.

What `DirectWristTests` covers beyond the pin: windows becoming `AccelSample`s on the
records' own clock, 40 ms apart and time-sorted; `hasAccel` turning on while `sourceClass`
stays `a`; **the seconds between two windows behaving as an ordinary sensor gap** — `valid`
false, no stroke picked — which is the property the whole windowed design rests on; the
sidecar landing beside the archived original so `SessionArchive.rawTrack` and every later
re-analysis see it; a sidecar refused where it has nothing to attach to; and 200 rounds of
random bytes after a valid header never trapping the decoder.

`directWristHoldsItsBudget` on the watch is the memory guarantee: two hours of covered riding
fed at 25 Hz, then the assertion that what is held is **under the budget** and that every
page still opens with a window header. On all three devices it settles at 9 pages, 58 725 B
of 60 000, thinned to one window in four. The budget is picked off
`System.getSystemStats().totalMemory`, which is the app's own limit on a watch and the
**simulator's 8 MB** in the simulator — so every simulated device takes the 60 000 B budget
and only a real fr255 takes 24 000. The ceiling is what the suite proves and it holds at
either value; on a device the wrist encoder's whole footprint is the budget plus one 8 000 B
page buffer plus a 768 B window scratch — about **69 kB** on a big-heap watch and **33 kB**
on the fr255, against 388 kB free there.

What `DirectStreamTests` covers beyond the pin: rounding half away from zero at both scales
and in both signs, and the truncating delta base; a 7 300-record synthetic session with a
400 s pause, a position jump, an altitude gap and a heart rate that appears part way, encoded
to pages and decoded back with every field exact and the positions inside a micro-degree;
every page opening with a keyframe and decoding on its own with page 0's header in front of
it; keyframes landing on each trigger §2.2 lists; a torn record throwing rather than trapping
at every cut length; the page message decoding from a `ByteArray` and from an `Array<Number>`
and being refused whole when it cannot be vouched for; the stream becoming a `RawTrack` the
engine analyses into flights; and the three dedupe stories of ADR-013 — a card's provisional
row filled by the stream, a later FIT replacing the direct row in place, and the same stream
twice being an ordinary duplicate.

**The cross-check that actually proves the two encoders agree** is worth running by hand after
any change to the arithmetic: encode the same synthetic session with `DirectStreamEncoder` and
with `cjr_ref.Encoder` and compare the hex. At 2 000 records with a pause, a jump and an
altitude gap that is 26 349 bytes over four pages, byte for byte identical (19 September 2026).

## Three channels — release, beta and dev

`docs/channels.md` is the contract: which feature ships in which channel, and the four rules a
feature meets before it moves up one. This section is how the three are **built**, and the one
check that proves a channel is what it claims to be.

| | scheme | configuration | flags | bundle id | device | group |
|---|---|---|---|---|---|---|
| **release** | `WingFoil Release` | `Release` | none | `de.lahmann.wingfoil` | iPhone | external (beta review) |
| **beta** | `WingFoil Beta` | `Beta Release` | `BETA` | `de.lahmann.wingfoil` | iPhone | external (beta review) |
| **dev** | `WingFoil Dev` | `Dev Release` | `BETA DEV TUNING` | `de.lahmann.wingfoil.dev` | iPhone + iPad | internal (no review) |

Release and beta are two targets over **one set of sources**: `WingFoilRelease` and `WingFoil`
both compile `ios/WingFoil/`, and everything that separates them is a compile flag, an
Info.plist and an entitlements file. The release target embeds no watch app and no widget
extension, links no ConnectIQ, has no HealthKit entitlement, and declares FIT and zip and
nothing else on its share sheet. The dev channel is a **second app**: its own bundle id,
display name "CleanJibe Dev", its own BGTask identifier (`$(CJ_BUNDLE_ID).refresh`, read back
in Swift from `Bundle.main.bundleIdentifier`) and its own Garmin callback scheme
(`wingfoil-ciq-dev`, read back from the Info.plist key `CJUrlSchemeCIQ`), so it installs
beside the release one instead of over it.

**Gates in code.** `#if BETA` is true in beta and dev; `#if DEV` only in dev; `#if TUNING`
stays what it always was and is defined wherever `DEV` is. The kit (`WingFoilKit`) compiles
everything in every channel — the gating is in the app, its Info.plist and its entitlements,
so a door a channel lacks has no UI, no document type, no usage string and no entitlement.
`#if !BETA` marks the one thing only the App Store build has: the "Coming in a future
release" section's How to join the beta step with the TestFlight link.

**The flag check** (run it before archiving). Release must print nothing but the inherited
defaults; beta `BETA`; dev `BETA DEV TUNING`:

```sh
cd ios
xcodebuild -project WingFoil.xcodeproj -scheme "WingFoil Release" -configuration Release \
  -showBuildSettings | grep SWIFT_ACTIVE_COMPILATION_CONDITIONS      # (nothing)
xcodebuild -project WingFoil.xcodeproj -scheme "WingFoil Beta" -configuration "Beta Release" \
  -showBuildSettings | grep SWIFT_ACTIVE_COMPILATION_CONDITIONS      # BETA
xcodebuild -project WingFoil.xcodeproj -scheme "WingFoil Dev" -configuration "Dev Release" \
  -showBuildSettings | grep SWIFT_ACTIVE_COMPILATION_CONDITIONS      # BETA DEV TUNING
```

**And the plist check**, which is the other half and catches what a flag cannot — a usage
string or a document type left in the release channel's Info.plist. After `xcodegen generate`
it must print `0`:

```sh
cd ios && xcodegen generate
grep -c "NSHealth\|NSLocation\|NSBluetooth\|gpx\|tcx" WingFoil/Info-Release.plist   # 0
```

**And the mark check.** Each channel wears its own cut of the brand mark (docs/channels.md,
"Telling the channels apart"), picked per configuration; the same `-showBuildSettings` lines
with `grep "APPICON_NAME\|CJ_SPLASH_MARK"` must print `AppIcon` / `SplashMark` for the release,
`AppIcon-Beta` / `SplashMark-Beta` for the beta and `AppIcon-Dev` / `SplashMark-Dev` for dev,
and a built app's Info.plist says the same under `CFBundleIconName`. The watch app follows
its phone (`-target WingFoilWatch`). After touching `brand/`, rerun
`brand/tools/make_channel_marks.py` and `garmin/tools/make_brand_mark.py` and commit what
they write.

**All four checks in one command.** `make release-check` (`tools/check_release.py`) runs the
flag, plist and mark checks above against `ios/project.yml` and the generated Info.plist, and
asserts the version sites agree — the iPhone's build number at every site, the watch's three
manifests, and the engine version across the lab, the kit, the web bundle,
`docs/algorithms.md` and `docs/channels.md`. Add `BINARY=<path>` after an export for the
fourth check, the `strings` one:

```sh
make release-check BINARY=ios/build/exportRelease/WingFoil.app/WingFoil
```

It is the first thing `make all` runs and a job in CI, so the three commands below start from
a tree whose versions already agree.

**The three archive commands.** Same commit, same `MARKETING_VERSION`; bump
`CURRENT_PROJECT_VERSION` in `ios/project.yml` (all four targets) and re-run `xcodegen
generate` between them. **The App Store build takes the lowest number**, and that is the point
of the order: a build number is what a reviewer and an external tester see beside the version,
and the canonical build of a release is the one that ships. The internal group has automatic
distribution on, so every processed build of the release record reaches Jan's phone by itself
whichever number it carries.

```sh
cd ios

# 1. release channel — build N, App Store
xcodegen generate
xcodebuild -project WingFoil.xcodeproj -scheme "WingFoil Release" \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/WingFoilRelease.xcarchive archive
xcodebuild -exportArchive -archivePath build/WingFoilRelease.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/exportRelease

# 2. bump CURRENT_PROJECT_VERSION to N+1, then the beta channel
xcodegen generate
xcodebuild -project WingFoil.xcodeproj -scheme "WingFoil Beta" \
  -configuration "Beta Release" -destination 'generic/platform=iOS' \
  -archivePath build/WingFoilBeta.xcarchive archive
xcodebuild -exportArchive -archivePath build/WingFoilBeta.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/exportBeta

# 3. bump to N+2, then the dev channel — a different app record
xcodegen generate
xcodebuild -project WingFoil.xcodeproj -scheme "WingFoil Dev" \
  -configuration "Dev Release" -destination 'generic/platform=iOS' \
  -archivePath build/WingFoilDev.xcarchive archive \
  -allowProvisioningUpdates \
  -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_HZT9694JZ4.p8 \
  -authenticationKeyID HZT9694JZ4 \
  -authenticationKeyIssuerID b9e6ccaa-e24a-4d37-bc1d-87f5be210572
xcodebuild -exportArchive -archivePath build/WingFoilDev.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/exportDev
```

`ios/ExportOptions.plist` carries all eight bundle ids — four release/beta, four dev — in one
`provisioningProfiles` map. An entry for a bundle id an archive does not contain is ignored,
so the release export reads the first line and nothing else.

Two traps met on 14 September 2026. **A stale local profile**: regenerating a profile through
the API (after adding a capability such as App Groups) leaves the copy under
`~/Library/Developer/Xcode/UserData/Provisioning Profiles` as it was, and the archive fails
with "doesn't include the App Groups capability" although the portal's profile does. The
`-allowProvisioningUpdates` line with the API key, shown on the dev archive above, makes
Xcode fetch the current one; it is harmless on the other two archives. **The export is the
upload**: `destination: upload` in ExportOptions.plist means `-exportArchive` sends the build
to App Store Connect itself, and without the same three authentication flags it fails with
"Failed to Use Accounts" — there is no separate altool step.

Upload each (Transporter or `xcrun altool`), then attach it to its group. `--app` names the
App Store Connect record: `release` (the default) is the App Store app, which holds both the
release and the beta channel's builds; `dev` is the separate "CleanJibe Dev" record
(`de.lahmann.wingfoil.dev`, app id 6811840646). `CJ_DEV_APP_ID` in the environment overrides
that id if the record is ever recreated.

```sh
uv run --with pyjwt --with cryptography --with requests \
  python ios/tools/testflight_publish.py N   --group external --wait
uv run --with pyjwt --with cryptography --with requests \
  python ios/tools/testflight_publish.py N+1 --group external --wait
uv run --with pyjwt --with cryptography --with requests \
  python ios/tools/testflight_publish.py N+2 --group internal --app dev --wait
```

Our internal group has automatic distribution on (`hasAccessToAllBuilds`), so **every**
processed build — the public N included — reaches internal testers by itself, and Apple
refuses a manual assignment to that group (build 29: 422 "Builds cannot be assigned to this
internal group"). The script sees the flag and skips the assignment; it still sets What to
Test. `--group internal` therefore mainly **skips the beta-review submission** —
internal testers need no review, and submitting a build we never intend to ship would put it
in front of Apple's reviewers ahead of the one we do. `--group external` is the default and
is unchanged: attach, set What to Test, submit for beta review (the lesson of builds 6–15,
which sat unreviewed for weeks because attaching is not submitting).

**And then tag it.** `make tag-ios` writes `ios/<MARKETING_VERSION>-<CURRENT_PROJECT_VERSION>`
at the commit the archives came from, so a rider's report six weeks later maps to a tree.
It refuses on a dirty tree and runs `tools/check_release.py` first. The rule, the other two
tag shapes (`garmin/0.9.13`, `web/v76`) and the list of tags that should exist retrospectively
are in docs/engineering.md, "Tags". Pushing a tag is Jan's, like every other push here.

**Release and beta share a bundle id**, so a phone holds one of them and TestFlight swaps
them in place with the library kept. **Dev is a second app** beside either, with a library of
its own — which is the one behavioural difference from the old two-variant arrangement, where
the dev build read and wrote the public build's library. A phone that ran the *old* dev build
still has a library stamped `0.15.0+tuned.…`; the release build's own `reanalyzeStale()` sweep
re-derives it on the published defaults at the first launch, because the stamped version does
not match.

### A library from a newer build — how to see the refusal

The three channels are cut from one commit but not on one day, so the case that matters is an
older build put back on a phone whose library a newer beta has already migrated. `AppDatabase`
reads `PRAGMA user_version` and the `grdb_migrations` list **before** it migrates anything and
throws `LibraryNewerThanApp` rather than opening a schema it does not know;
`LibraryNewerThanAppTests` covers all four shapes — one version ahead, the `user_version = 99`
recipe below, an unknown migration identifier, and the two that must still open (a library
from before the stamp existed, and a half-migrated `upTo: "v1"` one).

To see the **screen**, raise it on a simulator against a library that is really there:

```sh
xcrun simctl terminate booted de.lahmann.wingfoil                       # or …wingfoil.dev
DIR=$(xcrun simctl get_app_container booted de.lahmann.wingfoil data)
sqlite3 "$DIR/Library/Application Support/wingfoil.sqlite" "PRAGMA user_version=99;"
xcrun simctl launch booted de.lahmann.wingfoil
```

The app opens on *This library was last used by a newer CleanJibe* with **Open TestFlight**
and **Restore from backup**, and nothing behind it. Put it back with
`sqlite3 … "PRAGMA user_version=15;"` — the number is `AppDatabase.schemaVersion`, which every
successful open stamps for itself, so any value at or below it simply opens. Restoring instead
moves the too-new file aside to `wingfoil.sqlite.v99.newer` and builds a fresh one from the
backup; the aside file is never deleted, so the recipe is reversible by hand.

### The beta's update reminder — pointing a build at a file of your own

The switch is one static file on the website (`web/app/version.json`, docs/presentation.md
"The beta's update reminder"), so testing it means serving a file of your own and telling the
build to read that one instead. `UI_VERSION_URL` does exactly that, in **DEBUG only** — the
shipped build reads one URL and cannot be told otherwise.

```sh
mkdir -p /tmp/cjver && cd /tmp/cjver
cat > version.json <<'JSON'
{"channels": {
  "beta": {"minBuild": 999, "message": "Build 999 fixes the thing you just reported.",
           "level": "remind", "url": "https://testflight.apple.com/join/nygqGGcn"},
  "dev":  {"minBuild": 999, "message": "Build 999 fixes the thing you just reported.",
           "level": "remind", "url": "itms-beta://"}
}}
JSON
python3 -m http.server 8765        # leave it running
```

Then run the beta or dev scheme with `UI_VERSION_URL=http://localhost:8765/version.json` in
the scheme's environment (Product → Scheme → Edit Scheme → Run → Arguments), or from the
command line against a booted simulator:

```sh
SIMCTL_CHILD_UI_VERSION_URL=http://localhost:8765/version.json \
  xcrun simctl launch booted de.lahmann.wingfoil.dev
```

(`SIMCTL_CHILD_…` is the environment of `simctl` itself rather than an argument to it — the
same spelling every other hook in this file uses.) A `file://` URL works too and needs no
server at all — `UI_VERSION_URL=file:///tmp/cjver/version.json` — because the reader only
insists on a 200 when the answer came over HTTP.

`minBuild: 999` is above anything we build, so the reminder fires at once. What to look for:

* **`remind`** — one line at the top of the library with the message, *Update* and a ✕. The ✕
  takes it away and keeps it away; **raise `minBuild` to 1000 in the file** (the server serves
  the new bytes immediately) and it comes back on the next foregrounding, which is the whole
  of the dismissal rule (`UpdateVerdict`, `UpdateVerdictTests`).
* **`insist`** — change `level` and foreground the app: one full screen with the message and
  *Update*, in front of the tabs, with no way past it. Set `minBuild` back to `1` to get out.
* **Silence** — stop the server, or delete the channel's entry: nothing appears, nothing is
  said, and the last answer is kept. Settings → Beta → *Check for a newer build now* is the
  one place that shows what happened; it prints the running build, the verdict and the clock.
* **The 24-hour rule** — the second launch says nothing new because the file is not read
  again; the Settings row ignores that and reads it now. To start from nothing, *Start over*
  (Settings → Beta) clears the three keys with everything else, or
  `xcrun simctl spawn booted defaults delete de.lahmann.wingfoil.dev update.lastCheck.v1`.

**`UI_VERSION_URL` is the one `UI_` hook that switches the feature *on*.** Every other one
switches it off: a banner at the top of the library would change every screenshot, so the
reminder stays silent whenever any `UI_…` variable is set and this one is not — the same rule,
and the same reason, as `Usage.askIsDue`.

**And the release check.** The whole feature is `#if BETA`, so the App Store binary must not
contain the URL at all:

```sh
strings ios/build/.../WingFoil.app/WingFoil | grep -c version.json    # 0
```

### Two devices, one library — the iCloud Drive sync

The dev build's **Settings → iCloud Drive** merges this phone's library with a folder in the
rider's iCloud Drive (issue #7, ADR-026). The rules are kit-side and tested there
(`LibrarySyncTests`: the per-field merge, the tombstones, the folder round-trip and the
dedupe through `SessionIngestor`); what follows is how to drive the *app* side without two
phones and without an iCloud account.

**`UI_SYNC_CONTAINER=<path>`** replaces the ubiquity container with a plain directory, exactly
as the kit tests do. Two simulators pointed at one path are two devices sharing one library,
and the folder is then readable in Finder while the test runs — which is the point, because
`Sessions/<uuid>/meta.json` is where a merge either happened or did not.

```sh
CONTAINER=/tmp/cleanjibe-sync
rm -rf "$CONTAINER"

# device A: a library with something in it
xcrun simctl launch --console booted de.lahmann.wingfoil.dev \
  UI_RESET=1 UI_IMPORT_FIXTURES=1 UI_SYNC_CONTAINER="$CONTAINER"
# turn the switch on in Settings → iCloud Drive, then Sync now

# device B: an empty library, same folder
xcrun simctl launch --console <second-udid> de.lahmann.wingfoil.dev \
  UI_RESET=1 UI_SYNC_CONTAINER="$CONTAINER"
# switch on, Sync now — the sessions arrive and are analysed here
```

Four things to check by hand, in this order, because each one is a rule that only a second
device can break:

1. **Nothing doubles.** Sync both ways twice. The library count does not move and
   `ls "$CONTAINER/Sessions" | wc -l` equals the session count — the folder is keyed by the
   device that wrote it first, and a second folder for one afternoon is the bug ADR-026's
   ±60 s lookup exists to prevent.
2. **A rename crosses, and survives.** Rename on B, sync B, sync A: the name is on A. Then
   sync B again — the name is still there, and did not revert to the folder's older copy.
3. **A delete sticks.** Delete on A, sync both: the session is gone on B and
   `Settings → Deleted sessions` says 1, not 2. Drop the same FIT into B by hand afterwards:
   it is refused, not imported.
4. **Both edit one session.** Rename on A and caption on B before either syncs, then sync
   both: both survive. Rename the *same* session on both: the one that synced later wins.

The status line is a dry run (`LibrarySyncEngine.plan`) and writes nothing, so reading it is
always safe: "In iCloud Drive: 41 sessions · Pending: 2".

**And the release check.** The whole door is `#if DEV`, so neither the App Store nor the beta
binary may carry a word of it. Xcode 16 links the app's own code into `WingFoil.debug.dylib`
beside the stub, so the debug builds are read there:

```sh
strings ios/build/.../WingFoil.app/WingFoil.debug.dylib \
  | grep -c "Sync the library with iCloud Drive"     # dev 1, release 0
```

The kit is not part of that check and must not be: `WingFoilKit` compiles `LibrarySync.swift`
in every channel by design, so its container ids are in every binary. What a channel lacks is
the **door**, and the door is the switch's own wording.

### Ground-truth labels — the CSV the dev build exports

The dev build lets Jan label a counted turn with what actually happened — *I flew · I touched ·
I fell* — and scores those labels against the engine (docs/presentation.md, "The dev workbench").
The labels live on the phone, outside the analysis; **Settings → Tuning → Labels → Export labels
as CSV** is how they leave it, and this is the format the lab reads them back in.

One header row, then one row per **paired** label — a label whose turn is not in the session's
current analysis any more is counted on the page and left out of the file, because the row could
not name a verdict to sit beside. Ordered **oldest session first**, then by turn index.
UTF-8, `\n`, RFC 4180 quoting on the two free-text columns only.

```
session_id,session_title,session_start,turn_index,turn_ts_s,turn_type,label,verdict,clean,agrees
1F2A…,Nago-Torbole 07:54,2026-08-07T07:54:12+02:00,12,1483.0,jibe,touched,fell_in,0,0
```

| column | what it is |
|---|---|
| `session_id` | the library's own row id — the join key, verbatim |
| `session_title` | what the app calls the session, for a human reading the file |
| `session_start` | ISO-8601 with offset, the session's own zone |
| `turn_index` | index into that session's `analysis.turns` — the same identity the app, the map pins and the turn sheet use |
| `turn_ts_s` | the sweep's start, seconds from the session's start |
| `turn_type` | `jibe` \| `tack` \| `turn` (counted turns only; a course change cannot be labelled) |
| `label` | the rider's verdict: `flew` \| `touched` \| `fell` |
| `verdict` | the engine's, in **its own spelling** — `flew_through` \| `touchdown` \| `fell_in`, so the file reads beside `analysis.json` |
| `clean` | the engine's `clean` flag, `1`/`0` |
| `agrees` | `1` when `label` and `verdict` are the same event — the column the agreement percentage sums |

The pairing `flew ↔ flew_through`, `touched ↔ touchdown`, `fell ↔ fell_in` is the whole of the
scoring, and it is spelled once (`TurnLabel.verdict`). `clean` is carried but never scored: the
rider is asked what happened, not whether a jibe met a threshold he cannot see from the water.

## The bundled example session

A fresh install has an empty library, an empty Records screen and no reason to trust any of
it. So one real recording ships inside the app —
`ios/WingFoilKit/Sources/WingFoilKit/Resources/ExampleSession.fit`, a **kit** resource
rather than an app resource so `Bundle.module` reaches it from both the shipping app and
the test suite (no `project.yml` change is needed; Xcode embeds the SPM resource bundle).

**Source and scrub.** It is Jan's 2026-08-30 early-afternoon Nago-Torbole CIQ session — ten
minutes and forty-five seconds of Ora, donated with the HR stream — run through
`lab/tools/scrub_fit.py`:

```
cd lab
uv run python tools/scrub_fit.py \
    <the unscrubbed recording>.fit \
    ../fixtures/sessions/ciq/2026-08-30-1407_nago-torbole-windsurfen_ciq.fit
cp ../fixtures/sessions/ciq/2026-08-30-1407_nago-torbole-windsurfen_ciq.fit \
   ../ios/WingFoilKit/Sources/WingFoilKit/Resources/ExampleSession.fit
cp ../fixtures/sessions/ciq/2026-08-30-1407_nago-torbole-windsurfen_ciq.fit \
   ../web/example/ExampleSession.fit
```

The scrubbed file *is* the corpus fixture: unlike its predecessor, this example ships whole,
so there is no second, richer copy to keep beside it. The three files are byte-identical
(sha256 `7eee8888…`), which is what the dedupe tests rely on.

The tool does **not** re-encode — no encoder in the lab round-trips 14 developer fields, a
`developer_data_id`, the batched `accelerometer_data` messages and a dozen Garmin-private
global message numbers. It walks the FIT record stream itself (definition messages, normal
and compressed-timestamp data records, developer field blocks), drops selected messages,
overwrites selected fields in place with their base type's *invalid* pattern, and recomputes
`data_size`, the header CRC and the file CRC. Every surviving byte came from the original.

| what | action | why |
|---|---|---|
| `file_id.serial_number`, `device_info.serial_number` (×2) | → 0 (uint32z invalid) | unique watch id |
| `user_profile` (global 3) | dropped | name, weight, height, gender, language |
| global 147 | dropped | paired-accessory BLE address + its name |
| global 79, global 140 | dropped | Garmin-private lifetime totals / physiological metrics |
| `accelerometer_data` (global 165), GPS, HR, developer fields, laps, session | **kept** | that is the whole point |

The result is **964 281 bytes** across 49 definition messages and 5 320 data records — the
*whole* recording, accelerometer stream and all. That is affordable only because the session
is short, and that is why a short session was chosen: the predecessor was a two-hour
afternoon whose 100 Hz stream was 96 % of a 10.5 MB file, and shipping it meant `--drop-accel`
and a demo that had to report its pump figures as unknown. Ten minutes buys the pump trace
back for under a megabyte, which is the better trade for a first run.

Verification is built into the tool (`--verify`, default) and, with nothing dropped, it is
the strong form: the golden JSON of the scrubbed file is asserted **identical** to the
original's, byte for byte of meaning. Nothing degrades, so there is no degradation table —
`hasDoppler`, `hasDevFields`, `hasWatchLaps`, `hasAccel` and `hasHR` are all true and
`sourceClass` is **(a)**.

What the example therefore shows: 645 s elapsed, **67.9 %** on foil (431 s), **2** flights
(the long one 392 s / 2 222 m), **2.559 km**, **10** counted jibes and no tacks — 8 flown
through, 2 fallen, 5 clean, 5 port / 5 starboard — **44.7 JPH**, **27.9 CPH** and
**11.2 WPH**, best 2 s
**13.47 kn**, alpha 500 **11.70 kn**, wind from **196°** at full confidence, 4 takeoff
attempts of which 2 succeeded on **31** pump strokes (286 before engine 0.8.0 taught the
total to reject chop — docs/algorithms.md "The session total") of which **5** in flight (60
before 0.8.1 put the same amplitude gate on that count — "In-flight strokes"), and an average
takeoff HR cost of **16.5 bpm**. Being shorter than the 15-minute rate window, it is also the corpus's worked
example of the "no flattering peak" rule: `windowRates` reports one point, the whole-session
rate over the span it actually lasted.

**Provenance flag.** Sessions imported from it carry `session.isExample` (schema v3) and
`importSource = "example"`. They are shown in the library — badged `EXAMPLE`, openable,
deletable — and excluded from every aggregate that speaks for the rider: `LibraryStore`
filters them in `clause()` (Records, Trends, week buckets) and in the gear rollups, the
widget snapshot drops them, and they are never given the default gear combo nor written to
Apple Health.

**On the web.** The same file, and the same rule with a smaller mechanism: the "try the
example session" button flags what it fetched, `js/store.js` writes `example: true` on the
library entry, and `library.counts_towards_records` keeps it out of the one place the web app
aggregates (`library.aggregate` — Records, Trends and the totals block are all downstream of
it). The row is badged *Example*. A session someone else rode is the same problem from the
other direction and gets the same treatment: the web save asks *Whose session is this?* and
stores a `rider` name, which excludes it identically. An entry saved before either field
existed has neither, and missing reads as *mine, not example*.

**Dedupe decision.** The example is a *real* recording, so its owner will one day import it
for real and land on the ±60 s dedupe key. That resolves **in favour of the real import**:
`SessionIngestor.note` clears `isExample`, merges the sources (`"example+icu"`) and the row
rejoins Records and Trends — the alternative would permanently exclude the rider's own
session because a demo got there first. The reverse never fires: loading the example when
that ride is already in the library returns `.duplicate` and leaves the real row alone.
The *archived* FIT stays whichever arrived first, and since the bundle is the whole
recording that no longer costs anything: the two copies differ only in the identifiers the
scrub removed, so whichever one the archive kept produces the same numbers.

## On-water protocol (Jan, < 5 min per session)

Before: set wind-direction guess (watch menu or phone) + gear.
After, into `fixtures/README.md` ground-truth table: jibes attempted/made · tacks
attempted/made · takeoff attempts (approx) · **pump strokes (approx — how many times you
pumped the wing, per takeoff or for the whole session; this is the one column the corpus has
no observed value for at all, and it is what `pumpBurstPeakG` is waiting on)** · crashes ·
"longest flight felt like" · wind direction/strength · gear · anything odd (GPS, HR, app).
Compare with app output; every
discrepancy becomes a tuning issue referencing the session file. Every session grows the corpus.
