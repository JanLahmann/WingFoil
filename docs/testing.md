# Testing & Verification

## Golden files

`fixtures/goldens/<fixture>.expected.json` — written by `lab` (`wingfoil_lab.goldens`) once a
notebook result is human-validated; asserted by Python `pytest` (self-check) and Swift
`WingFoilKitTests` (cross-check). Schema (versioned via `engineVersion`):

```json
{
  "engineVersion": "0.8.1",
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
               "summary": { "usablePct": null, "avgTakeoffCostBpm": null,
                            "takeoffCostValid": 0, "takeoffCostTotal": 0,
                            "pumpCruise": { "pumpingBpm": null, "cruisingBpm": null,
                                            "deltaBpm": null, "...": "" }, "...": "" } },
  "summary": { "foilTimeS": 0, "foilPct": 0.0, "flightCount": 0, "longestFlightS": 0,
               "longestFlightM": 0.0, "distanceKm": 0.0,
               "durationS": 0.0, "avgSpeedKmh": null, "turnsPerHour": null,
               "jibesPerHour": null, "wetPerHour": null,
               "windowRates": { "windowMin": 15, "bestJph": null, "bestJphStartTs": null,
                                "bestWph": null, "bestWphStartTs": null,
                                "series": [ { "ts": 0, "jph": 0.0, "wph": 0.0 } ] },
               "turns":       { "tacks": 0, "jibes": 0, "unclassified": 0, "rejected": 0,
                                "turnsCounted": 0, "turnsSuccessful": 0, "successPct": 0.0,
                                "port": 0, "starboard": 0,
                                "longestDryStreak": 0, "longestFlewStreak": 0,
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
classify and gets `[]`, written rather than omitted. The **session rates** (engine 0.6.0,
docs/algorithms.md "Session rates") share the same never-a-flattering-zero rule: `durationS`
is the elapsed span of the cleaned track, gaps included, and when it is ≤ 0 all four derived
rates are explicit **null** — "there is no hour to divide by", not "he did nothing in one".
`wetPerHour` is every `fell_in` *flight end*, straight-line and turn-owned alike, which is a
different (and on this corpus a much larger) number than the turn ladder's fallen turns;
`jibesPerHour` is the **dry** jibes only (engine 0.7.0) — `jibes - jibeOutcomes.fellIn` —
because a rate a rider can raise by falling more often is not a measure of his afternoon.
`windowRates` (engine 0.7.0) is the same two event channels over a rolling 15-minute window:
a 60 s series of full windows, and the two exact sliding peaks, which are anchored on the
events and so are never below the series they sit beside. Its peaks obey the **mirror** of
the zero rule — never a flattering *peak*: only windows lying wholly inside the session
count, and a session shorter than the window reports its own whole-session rate over the span
it lasted rather than a fragment scaled up to the hour.

## Presentation goldens

`fixtures/presentation/<fixture>.expected.json` — the second golden set, one per analysis
golden, generated by `web/tools/make_presentation_goldens.py` (`--check` fails when stale).
They carry no metric: only what a session-detail screen is *allowed to draw* from the
analysis of the same name — markers per layer, the takeoff layer's pumped/free/failed
split, the splash count, pump-burst spans, the achieved record windows and the full
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
| session duration (`durationS`) | ± 0.1 s |
| session rates (`avgSpeedKmh`, `turnsPerHour`, `jibesPerHour`, `wetPerHour`) | ± 0.05 |
| window rates (`windowRates` peaks and every series `jph`/`wph`) | ± 0.05 |
| window starts (`bestJphStartTs`, `bestWphStartTs`, series `ts`) | ± 0.1 s |
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
     hits body and item text); the share card's content — its `complete` preset is the
     **key-metrics block, cell for cell** (same keys, same order, same labels, same strings,
     the tally's three counts kept as counts), `lean` a strict *subset* of it that may only
     remove entries, no flight count on either, "—" rather than a fabricated 0.00 kn, the
     uncertified disclaimer, and the preset preference round-tripping through
     `UserDefaults` with an unknown stored value degrading to `complete`; thumbnail geometry
     (aspect preserved — a straight-line track must land in a band, not stretched over the
     box; `contentBox` reports the band rather than the square, which is what lets the card
     fill its box; runs split at the phase change and share a vertex; the outcome/splash
     marks come off the shared presentation rules — counted turns only, both splash
     channels — land on the outline's own projection, and are dropped when no fix is within
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

   iOS screenshot hooks (DEBUG **and** simulator only, passed as `SIMCTL_CHILD_…`
   environment variables to `xcrun simctl launch`): `UI_RESET=1` restores the fresh-install
   state — keychain key, sync history, PB snapshot, database and FIT archive all removed —
   and `UI_ICU_KEY=…` seeds a key through the real keychain path afterwards, so the
   first-run setup card and the "key stored, sync rejected" card can both be captured
   without reinstalling. `UI_IMPORT_FIXTURES=1`, `UI_OPEN_SESSION=latest|<name>`,
   `UI_TAB=records|trends|gear`, `UI_SHEET=help|settings` and
   `UI_HELP_TOPIC=<HelpTopicID>` park the app on a given screen, since `simctl` cannot tap.
   **Since the session page became a four-way switcher** (`SessionSection`,
   docs/presentation.md "Sections"), every session hook that names a place also **selects
   the section that place lives on** — `UI_SCROLL_TO` through `SessionSection.section(owning:)`,
   and `UI_OPEN_TURNS=1`, which used to push a page, by selecting `Turns`. A scroll to an
   anchor on an unselected section reaches nothing at all, silently, and produces a
   screenshot of the wrong screen; `PresentationTests.everyScrollAnchorResolvesToExactlyOneSection`
   is what stops an anchor being renamed out from under a hook.
   `UI_LOAD_EXAMPLE=1` taps the setup card's "Load an example session first" button, and
   `UI_SCROLL_TO=setup` parks the (screen-and-a-half tall) onboarding card on its bottom
   edge — the only way to photograph that button, which lives below the key field.
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
   something other than the best 2 s. `UI_OPEN_TURNS=1` selects the **Turns** section (it
   pushed a page until the drill-in was folded inline, app-ui-review.md §2.1) and
   `UI_TURN_FILTER=<jibes|tacks|both>,<port|starboard|both>` engages its two segmented
   filters (e.g. `jibes,starboard`), which `simctl` likewise cannot tap.
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
   In the share sheet (`UI_SHEET=share`), `UI_SHARE=fit` flips to the recording tab,
   `UI_SHAPE=portrait|square|landscape` picks the aspect and `UI_STATS=lean|complete` picks
   the stat preset — three controls `simctl` likewise cannot tap. The last one sets the same
   state the picker does but, unlike a tap on the picker, does **not** write the rider's
   stored choice.
   The **cinema replay** (`ReplayCinemaView`, the full-screen replay a clip is recorded from)
   opens with `UI_REPLAY_CINEMA=<rate>` — `10`, `30` or `60` — which stands in for the record
   button plus the setup sheet. `UI_REPLAY_SETUP=1` opens that sheet instead, which is the
   only screen the photo picker lives on. `UI_REPLAY_RECORD=0` stages the other mode, the
   plain full-screen replay a rider gets when the recorder is unavailable or the permission
   was refused: no countdown, no clip, the transport says "Done".
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
   size, share link, discard — gets driven on a Mac. The one thing only a device can settle
   is whether the *first recorded frame* is the title card: the countdown is removed, a
   `titleSettleS` beat passes and only then is `startRecording` awaited, and there is no
   simulator capture to check it against.
   Orientation is the one thing no hook stages: `simctl` cannot rotate a simulator and
   Simulator.app's Rotate menu is not reachable from a headless run. To photograph the
   landscape frame, temporarily cut `UISupportedInterfaceOrientations` in `ios/project.yml`
   down to `UIInterfaceOrientationLandscapeRight`, `xcodegen generate`, build, shoot, and put
   it back.
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
   monkeyc -f garmin/monkey.jungle -d fenix847mm -y garmin/developer_key.der \
       -o /tmp/wft.prg --unit-test
   connectiq &                      # the simulator must be up; monkeydo attaches to it
   monkeydo /tmp/wft.prg fenix847mm -t
   ```

   Run it on **two** glasses at least — one AMOLED (`fenix847mm`, 454 px) and one 8 bpp MIP
   (`fenix8solar47mm`, 260 px, or `fenix7s`, 240 px, the narrowest shipped). The layout suite
   reads its canvas from `System.getDeviceSettings().screenWidth`, so the same assertions are
   genuinely different measurements per device, and every finding that has ever come out of
   this suite came from the narrow ones. Start one simulator per run and kill it afterwards:
   two `monkeydo` processes against one simulator hang rather than fail.

   **Round-display layout tests.** Six pages plus the summary are measured against the chord
   at each row's own depth, at worst-case content, with the device's real font metrics:
   `mainPageFitsRoundDisplay`, `heroPageFitsRoundDisplay`, `gridAndCellsPagesFitRoundDisplay`,
   `recordsPageFitsRoundDisplay`, `turnsPageFitsRoundDisplay`, `clockPageFitsRoundDisplay`,
   `timelinePageFitsRoundDisplay`, `startPageFitsRoundDisplay`, `lockScreenFitsRoundDisplay`,
   `summaryPagesFitRoundDisplay` and `pausedBannerStaysInsideTheRings`. They assert against
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

   Known failure: `lockScreenFitsRoundDisplay` fails on `fenix7s` (240 px) and has since
   before 0.8.0 — the invite-beta lock screen's rows 1/2 collide on the narrowest glass. It is
   pre-existing and unrelated to the recording UI.
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
through, 2 fallen, 5 port / 5 starboard — **44.7 JPH** and **11.2 WPH**, best 2 s
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
