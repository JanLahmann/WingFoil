# Canonical Algorithm Parameters (contract)

Single source of truth for detection/metric parameters. Three implementations follow this table:
`lab/src/wingfoil_lab/*` (tuning ground), `ios/WingFoilKit/Sources/AnalysisEngine/*`
(authoritative), `garmin/source/{detectors,metrics}/*` (live approximation). Defaults get
re-tuned in lab notebooks against the labeled fixture corpus; changed defaults are updated HERE
first, with the tuning notebook referenced in the commit.

`ENGINE_VERSION`: **0.2.0** (bump on any change that alters outputs; triggers phone re-analysis)

## Flight (foil) detection — hysteresis state machine

States: `OFF_FOIL → (entry) → ON_FOIL → (exit) → OFF_FOIL`. A third derived state `PUMPING`
(off-foil + active takeoff attempt) exists for display/record `foil_state` only.

| param | default | units | notes |
|---|---|---|---|
| `foilEntrySpeed` | 12.0 | km/h | speed ≥ entry … |
| `entryHold` | 2 | s | … sustained this long ⇒ ON_FOIL (flight start backdated to first qualifying sample) |
| `foilExitSpeed` | 8.0 | km/h | speed ≤ exit … |
| `exitHold` | 3 | s | … sustained this long ⇒ OFF_FOIL (flight end backdated to first sub-exit sample) |
| `minFlightDuration` | 5 | s | shorter flights discarded (no lap, not counted) |
| `touchdownMergeGap` | 0 (off) | s | phone-only: merge flights separated by ≤ gap as one flight + touchdown event (v2) |

Prior art anchors: WindsportTracker wingfoil threshold ≈ 9.7 km/h; Surf Tracker run recipe
(9 km/h entry / 6 s / 13 km/h peak). Our entry is higher because takeoff pumping produces
9–12 km/h taxi speeds. User-tunable on watch (GCM settings) and phone; thresholds used are
echoed in session fields 40–42.

## Speed sample hygiene (phone; watch uses quality gate only)

| param | default | notes |
|---|---|---|
| `maxHdop` | 5.0 | GP3S standard (when channel present) |
| `minSatellites` | 5 | when present |
| `maxAccel1Hz` | 4.0 m/s² | spike filter (Logiqx 1 Hz value) |
| `gapInterpolateMax` | 2 s | linear-interpolate gaps ≤ this; longer ⇒ hard segment break |
| `speedChannelRecords` | doppler | FIT `speed`/`enhanced_speed` (device Doppler) for all speed records |
| `speedChannelManeuvers` | hybrid | positional speed (local-meter projection) for turn minima — Doppler is ~3–4 s smoothed |
| watch gate | `Position.Quality ≥ USABLE` | below ⇒ sample not fed to detectors/records; timers freeze; FIT keeps raw |
| `odoMaxStep` | 3 × Doppler distance + 10 m/s × dt | watch odometer guard, see below |
| `maxSpeedMps` | 40.0 m/s (144 km/h) | watch plausibility band; outright sailing record is 33.7 m/s |

**An implausible speed sample is treated exactly like an unusable fix**
(`garmin/barrel/WingFoilCore/source/Sanity.mc`): speed forced to 0, no distance, and
`onGap()` on records/turns/pump so no window straddles it. One bad sample otherwise survives
the whole session, because records latch the best value ever seen and distance integrates.
Symptom that found it: the simulator emits `speed = 20 037 508 m/s` — the Web-Mercator
half-circumference — when FIT playback hiccups, which latched a **50 675 121 km/h** best-2 s.

**Watch distance is a sum of validated odometer steps, never the odometer reading**
(`garmin/barrel/WingFoilCore/source/Odometer.mc`, shared by the device app and the data field).
`Activity.Info.elapsedDistance` is a reading, and it teleports: a fix recovered far from where
it was lost books the whole gap into one tick. A step above `odoMaxStep` is replaced by the
Doppler integral over the same tick, which is bounded by construction; the first reading of a
session only sets the origin, so joining an odometer that already reads 9 km adds nothing.
Symptom that found it: the simulator's FIT replay opens at the default location and jumps to
the clip's, which showed **37 986 km** on the session page.

## Speed records (GP3S set)

2 s peak · 10 s peak · 5×10 s (mean of best 5 **disjoint** 10 s windows) · 100 m · 250 m ·
500 m · nautical mile (1852 m) · 1 h · alpha 500 · session distance.

| param | default | notes |
|---|---|---|
| `alphaProximity` | 50 m | endpoint-to-startpoint (Pythagoras on local meters) |
| `alphaMaxDistance` | 500 m | total path length |
| `alphaCandidatePrune` | ≥250 m path AND ≥90° COG spread | gps-wizard optimization |
| `alphaBoundary` | interpolate | fractional samples at window edges (phone only) |
| `hourSearch` | forward + backward | avoids the classic missing-samples bug |
| `minSpeedFilter` | none | GPSResults-style 5 kn floors distort results — never applied |
| watch live set | 2 s, 10 s, 5×10 s, 500 m, NM (flag), alpha-lite | alpha-lite: armed 120 s after a ≥90° turn, 1 Hz two-pointer, `~`-labeled |

## Turn detection & classification

| param | default | units | notes |
|---|---|---|---|
| `turnMinAngle` | 60 | deg | net unwrapped COG change |
| `turnMaxDuration` | 8 | s | window for the net change |
| `turnPeakRate` | 25 | deg/s | at ≥1 sample (Richterich: jibes ~30–40°/s for ~4 s) |
| `turnContext` | ON_FOIL or ≤3 s after | | turns while swimming don't count |
| `turnCogSpeedFloor` | 2.0 | m/s | COG geometry read only from steps above this (same COAPS caveat as wind); a capsize below it otherwise reads as a multi-turn spin |
| `turnMinArc` | 12 | m | **spatial gate**: path length travelled across the COG sweep |
| `turnMinRadius` | 6 | m | **spatial gate**: effective radius = arc ÷ swept angle in radians |
| `turnContinueRate` | 5 | deg/s | edge trim: shrink the detected span to the actually-turning part |
| `entrySpeedWindow` | 3 | s | entry speed = max over window before turn start |
| `minSpeedLag` | 2 | s | minimum searched to `turnEnd + lag` (the collapse of a botched turn lands just past the COG sweep) |
| `turnSuccessPct` | 70 | % | success ⇒ minSpeed/entrySpeed ≥ this AND speed never ≤ `foilExitSpeed`. Both halves are read over the **scored window only** — `turnStart` … `turnEnd + minSpeedLag` — never over the outcome window: a turn carried cleanly through the sweep stays successful even when the foil is lost later in the recovery tail (that is what the outcome says) |
| `turnStopSpeedFloor` | 1.0 | m/s | "stopped": below this the rider is not making way |
| `turnTouchdownMaxStop` | 3 | s | longest stop still called a touchdown |
| `turnFallStop` | 5 | s | stop longer than this ⇒ fell in |
| `turnOutcomeLookahead` | 12 | s | **cap** on the tail past the COG sweep the outcome is judged over. A stalling foil bleeds from foiling speed to a standstill in roughly 10 s, so a shorter cap (the 5 s this started at) systematically misses the mush-out and scores it a fly-through |
| `turnRecoverPct` | 70 | % | of entry speed: back above this ⇒ flying again ⇒ the turn is over and its window closes early. Floored at `foilEntrySpeed` — nothing below that is flying, however slowly the turn was entered |
| `turnRecoverHold` | 2 | s | recovery must hold this long, same both-ends-qualify convention as flight `entryHold` |
| `turnBaroDrop` | 25 | m | apparent altitude below the session median that means the wrist is under water |
| `turnOutcomeWindow` | 60 | s | cap on following the recovery, so a turn taken before a break does not absorb it |
| classification | | | tack = COG crosses wind axis through upwind; jibe = through downwind; requires wind axis; bear-away/round-up (no axis crossing) excluded from counts |
| port/starboard | | | side before the turn, from sign of TWA |

Entry/minimum speeds come from `speedChannelManeuvers` (positional); the "never dropped off
foil" half of the success test stays on Doppler so it agrees with flight segmentation.
Overlapping candidates are non-maximum-suppressed by net angle, widest sweep wins.

### Spatial gate — "real movement around the curve" (Jan)

A COG sweep is not a maneuver. A rider swimming beside the board, or drifting while he sorts
the wing out, produces heading flips that are indistinguishable from a jibe *in angle terms*
while covering almost no water. `turnCogSpeedFloor` catches the slowest of these but not all
— a 2–3 m/s drift clears it. So a candidate must also have **carved an arc**: `turnMinArc`
metres of path across the sweep **and** an effective radius `arc ÷ |Δheading in rad|` of at
least `turnMinRadius`. Failures are **dropped**, not flagged: unlike a bear-away they are not
course changes at all, so they never reach the `rejected` count.

The gate is deliberately *geometric*, not another speed floor. Two sweeps at 4.0 m/s for 3 s
cover the same 16 m of water; the 180° one pivots inside a 5 m radius (dropped), the 90° one
carves 10 m (kept). No speed test can separate those.

**Corpus calibration.** Over the 116 candidates in the three reference sessions (2026-08-07
ciq, 2026-08-05 am, 2026-08-04 pm) the tightest genuine turn measures arc 14.4 m / radius
8.7 m, and the slowest sweeps 4.06 m/s — there is no low-radius population to cut, so at
12 m / 6 m the gate removes **nothing**, with 1.2× margin on arc and 1.45× on radius. That
is intended: it is a guard for future sessions with more swimming, not a correction to these.
That it *works* was verified by disabling `turnCogSpeedFloor`, which lets the drift rotations
back in (arc 1.3–11 m, radius 0.9–5 m, sweep speed 0.7–2.2 m/s, nearly all inside a swim):
the geometric gate removes 18 of the 33 that reappear, and the 15 it keeps are genuine turns
at 3.5–6.5 m/s that the speed floor had been over-rejecting. Radius is the discriminating
half — arc alone cannot separate a slow 8 s wallow (16 m) from a tight real turn.

Stricter settings cost real turns and were rejected: 15 m/6 m kills the 2026-08-07 06:32:50
round-up (14.4 m of arc at 4.8 m/s), 18 m/8 m kills two more 2026-08-04 jibes, and 25 m/6 m
kills 10 including five ground-truthed jibes.

### Watch approximation (garmin/source/detectors/TurnDetector.mc)

The watch runs the same parameters in one forward pass with bounded work per 1 Hz tick and no
allocation, so it necessarily differs from the lab pass. The phone recompute is authoritative;
these are the known divergences, all of them conservative (the watch under-counts rather than
inventing turns):

- **No non-maximum suppression.** The first sweep that clears the gates opens a candidate and
  the detector then *follows* the rotation while it keeps turning (`turnContinueRate`, capped
  at `turnMaxDuration`), so classification still sees the whole sweep. The lab instead scores
  every candidate and keeps the widest. Two turns inside one 8 s window merge into one.
- **Edge trim is the scan itself.** Walking back from the newest sample stops at the first
  step below `turnContinueRate`, which trims both edges greedily. A genuine turn containing a
  ≤5 °/s lull is split at the lull rather than spanning it.
- **No re-detection during the outcome window.** A second turn started before the first one's
  outcome resolves is not detected at all.
- **Doppler only.** There is no positional speed channel live, so the sharp `min(Doppler,
  positional)` test degrades to the firmware's ~3–4 s smoothed Doppler: short touchdowns the
  positional channel would expose can read as fly-throughs on the watch.
- **The outcome window is the judging window.** The lab follows an off-foil run past the
  window to `turnOutcomeWindow` (60 s) to measure the stop; the watch measures the stop inside
  the recovery-gated window only, capped at `turnOutcomeLookahead`. A stop long enough to be a
  fall still exceeds `turnFallStop` well inside that cap, so the verdict agrees; `stopped_s`
  itself is not reported by the watch.
- **Recovery is searched from the sweep end**, not from the speed minimum, and the entry speed
  is the max over `entrySpeedWindow` of the *Doppler* history.
- **Submersion is read in the pressure domain.** `turnBaroDrop` (25 m of apparent altitude) is
  converted once to a ~300 Pa rise in `rawAmbientPressure` against a slow (~50 s) baseline that
  refuses to adapt while a spike is in progress. Same positive-only semantics.
- **No pump corroboration** (step 3 of the ladder): the watch cannot promote a fly-through to a
  touchdown on accel evidence, so it reports slightly more fly-throughs than the phone.
- **Bear-aways are dropped, not carried.** They increment a `rejected` counter and are not
  given an outcome, so the watch has no equivalent of the lab's bear-away outcome window.
- **Wind is manual only** and classification is not retroactive: turns detected before the
  rider sets the axis stay generic for the rest of the session.
- **GPS below `Position.QUALITY_USABLE` freezes the detector**, including any open outcome
  window, matching how the other watch detectors treat a gap.

## Pumping (accelerometer)

Phone-side twin of the watch `PumpDetector`, and the only consumer of the raw SensorLogging
stream so far. A wing pump is a whole-body ~1 Hz oscillation the wrist sees as a large swing
in |a|; chop is faster and smaller, wing trim and arm drift are slower or smaller.

| param | default | units | notes |
|---|---|---|---|
| `pumpBandLo` / `pumpBandHi` | 0.5 / 2.5 | Hz | pumping cadence band |
| `pumpResampleHz` | 25 | Hz | |a| box-averaged onto a uniform grid (anti-alias + gap bookkeeping); the band ends at 2.5 Hz so 25 Hz is ample, and it matches the watch's rate so the two implementations can be compared sample-for-sample |
| `pumpFilterSpan` | 2 | s | FIR length (Hamming-windowed sinc difference) = two full slow cycles |
| `pumpStrokeAmp` | 0.25 | g | band-passed peak height that counts as a stroke |
| `pumpRefractory` | 0.4 | s | dead time after a stroke (a human cannot pump at >2.5 Hz) |
| `pumpStrokeMaxInterval` | 1.5 | s | strokes closer than this belong to the same burst |
| `pumpMinStrokes` | 4 | | burst length that means "the rider was pumping" |

The stream is orientation-free by construction (magnitude, not axes — the wrist rotates
constantly through a jibe). Empty grid bins are held at the session mean so the FIR does not
ring on sensor dropouts and are then discarded, so a SensorLogging gap contributes no
strokes rather than a burst of edge artifacts.

`pumpMinStrokes` sits in a wide gap, not on a knife edge: on 2026-08-07 the longest burst
inside a turn's outcome window is ≤2 for every jibe the speed channels called clean except
the two pump-outs, which score 6 and 7, and the verdict is unchanged at `pumpStrokeAmp`
0.20–0.30 g. Garmin writes `calibrated_accel_*` in milli-g although the FIT profile names
the unit "g"; the parser sniffs the scale from the resting magnitude rather than assuming.

### Turn outcome (primary, rider-facing) — `flew_through` · `touchdown` · `fell_in`

Score%/success stay as the *secondary*, continuous metric: outcome says what happened,
score says what the turn cost. Every turn gets an outcome, bear-aways included.

0. **How long is the turn on the hook?** The outcome window runs from the turn start until
   the rider is *demonstrably flying again* — Doppler back above `turnRecoverPct` of the
   entry speed (never below `foilEntrySpeed`) for `turnRecoverHold` — capped at
   `turnOutcomeLookahead` and ended early by a recording gap. This replaces a fixed tail and
   is the single biggest correctness fix in the outcome logic: a jibe exited at marginal
   speed keeps bleeding off for 6–12 s before the foil finally stalls, and that mush-out is
   the jibe's fault; a jibe the rider powers straight out of closes its window in a second or
   two and therefore *cannot* absorb an unrelated touchdown later in the run. The window
   stops at a gap because flights hard-break there, so every post-gap sample reads "not
   flying" until a new flight is established — following across would invent a loss out of
   missing data.
1. **Lost the foil? (speed — always available, the primary detector)** A sample counts as
   flying only when it is inside a flight **and** `min(Doppler, positional)` is above
   `foilExitSpeed` **and** the wrist is not submerged (step 2). Two tests are load-bearing
   here. Flight exit needs `exitHold` (3 s) of sub-exit speed, so a 1–2 s touchdown never
   breaks the flight and segments alone would call it a fly-through. And the *Doppler alone*
   is not enough either: the firmware smooths it over 3–4 s, which averages a short
   touchdown away entirely, while the positional channel is a plain 2 s central difference
   and shows it — 2026-08-07 #11 sits at 3.6 m/s on Doppler while the track says 0.5 m/s.
   No non-flying sample in the window ⇒ `flew_through` (unless step 3 fires).
2. **Wrist under water? (barometer — when the source has an altitude channel)** 30 cm of
   water is ~30 hPa, which a wrist altimeter renders as a ~250 m drop, and its slew limiter
   then crawls back over minutes. Nothing on a lake moves an altimeter by `turnBaroDrop`, so
   a sample that far below the session's median altitude is *proof* the rider was in the
   water: it is never flying, and its presence in the window makes the turn `fell_in`
   outright, whatever the stop measured. Positive-only evidence — on 2026-08-07 exactly 3 of
   18 falls dunked the wrist (−236 m, −105 m, −347 m; the deepest reading on any other turn
   is −9 m, so the threshold has two orders of magnitude of margin), and the silence of the
   other 15 means nothing. Sources without a barometer just skip it.
3. **Did he have to pump it out? (accelerometer — class (a) only, corroborating)** Pump
   strokes per *Pumping (accelerometer)* below. The rider pumps a wing for many reasons, so
   this never decides an outcome alone: a pump burst turns a fly-through into a `touchdown`
   only when the speed channels *also* saw the foil go marginal — below `foilEntrySpeed` —
   somewhere in the same window. Speed says the foil stopped carrying, accel says he had to
   pump it back; either alone is not enough. It can only ever promote `flew_through` →
   `touchdown`, never touch a fall.
4. **Stopped how long?** The off-foil run is followed until foiling resumes (capped by
   `turnOutcomeWindow`) and the longest contiguous spell below `turnStopSpeedFloor` is
   measured, on `min(Doppler, positional)`. Both channels *over*-read at rest — wrist
   Doppler picks up swim strokes, positional picks up GPS jitter — and neither under-reads,
   so the lower of the two is the better stop evidence, and using both bridges single-sample
   dropouts in either. An interval counts only when both end samples are below the floor and
   no recording gap separates them, the same "hold" convention flight segmentation uses.
5. Spell > `turnFallStop` ⇒ `fell_in`; otherwise `touchdown`, flagged `borderline` when the
   spell exceeds `turnTouchdownMaxStop`.

**The 3–5 s band is kept as two tunables, not collapsed to one threshold.** Over the corpus
(116 detected turns on 2026-08-07 ciq + 2026-08-05 am + 2026-08-04 pm) the measured stops are
0 s for every fly-through and 0×17, 1, 1, 4, 4, 5, 5, 6, 8, 9, 9, 11, 13, 13, 14, 15×4, 16,
17, 17, 21×3, 23, 28, 29, 30, 31, 33, 34×3, 44 s otherwise: the band holds 4 of 116 turns
(3.4 %), so a single threshold anywhere in it would score almost identically — but those 4
are genuine ambiguities (a rider drifting at ~1 m/s for a minute), and `borderline` surfaces
them for review instead of silently deciding. Collapse the pair only if the flag stays this
rare on a larger corpus. The 17 zero-length stops are the pump-corroborated and short
touchdowns: losing the foil and stopping are different events, and only the second is timed.

**Ground truth (2026-08-07, Jan).** The first cut of this logic — Doppler-only mask, fixed
5 s tail, no baro, no accel — read 17 fly-throughs / 6 touchdowns / 7 falls out of 30 jibes,
and Jan's verdict was that 17 was far too high: more jibes were pumped out, and a few more
swum. The evidence ladder above reads 9 / 9 / 12, and every turn it moved has a named cause
(five gradual mush-outs recovered by the window rule, one wrist submersion, two pump-outs).
The same code with no accel and no barometer still moves 2026-08-05 am from 15/1/1 to 12/2/3
and 2026-08-04 pm from 42/7/5 to 35/11/8, so the correction is not an artifact of the one
session that has extra channels.

### Flight-end outcome — `glide_out` · `touchdown` · `fell_in` · `unknown`

Turn outcomes only explain the losses that happen *in a maneuver*. Sessions also lose the
foil in a straight line — a gust dies, the foil ventilates, he catches a tip on a reach — and
those were previously invisible: flight segmentation said "a flight ended" and nothing said
whether he swam, pumped straight back up, or simply settled onto the board and kept moving.
**Every** flight end is now classified, with the *same* ladder as the turns (steps 0–4 above,
`evidence.py` is shared code). Only the leaves differ, because a flight end is already off
the foil — there is no `flew_through`:

| outcome | test |
|---|---|
| `fell_in` | stop > `turnFallStop`, or the barometer says the wrist went under |
| `touchdown` | the speed reached `turnStopSpeedFloor` at all; `borderline` when the stop exceeds `turnTouchdownMaxStop` |
| `glide_out` | never reached the stop floor — came off the foil and kept making way (taxi/slog, or a deliberate stop-riding) |
| `unknown` | the **recording** ended, not the flight: the last sample is the last of a gap-free segment, so there is zero evidence. Flagged `truncated`, excluded from every tally |

Thresholds are the turn ones, re-declared in `FlightEndConfig` so one end can be re-tuned
without the other. One physical question ("did he stop, and for how long") deserves one set
of numbers however the loss started.

Three details are load-bearing:

- **A dip must actually break the flight to be a flight end at all.** Exit needs `exitHold`
  (3 s) below `foilExitSpeed`; shorter touchdowns stay inside the flight and belong to the
  turn channel. The two channels therefore see genuinely different events and their counts
  are *not* redundant.
- **`glide_out` vs `touchdown` is drawn on whether the rider ever stopped, not on a stop
  duration above zero.** Smart Recording samples at ~2 s and the stop measure needs two
  consecutive sub-floor samples, so a real 3 s standstill can measure `stopped_s == 0` —
  2026-08-04 pm has flight ends touching 0.5 m/s that a duration test called glide-outs.
  `stopped_s` still decides `fell_in`/`borderline`, where 5 s and 3 s are resolvable.
- **`unknown` is not pedantry.** 2026-08-04 pm segments into 429 gap-free runs and 111 of its
  130 "flights" end at a segment boundary with the rider still doing 4–5 m/s. Classified on
  visible evidence they all read `glide_out`, and the session would claim 111 straight-line
  glide-outs that never happened. Class-(a) CIQ recording is a steady 1 Hz and loses 2 of 23.

**Ownership.** A flight end inside a detected turn's outcome window (`start` →
`end + outcomeWindow`) is *that turn's* event, already counted there: it is flagged
`owned_by_turn` and kept out of the straight-line tallies. Without this every jibe ending in
a swim is counted twice — once as a `fell_in` jibe, once as a fall. Ownership is tested
against **every** detected turn, bear-aways included: a fall inside a bear-away's window is
still explained by that course change. The session split that falls out — falls in turns vs
straight-line falls, same for touchdowns — is the rider-facing summary (`split_outcomes`).

Pump corroboration carries over unchanged: accel promotes `glide_out` → `touchdown` only when
the speed channels also went marginal. At a flight end that test is near-vacuous (the flight
ended *because* speed fell below `foilExitSpeed`), and that is intended — a rider who has to
pump a burst out of it did not glide out by choice.

## Wind axis estimation (phone)

1. Foiling samples only, speed ≥ 2 m/s (COG≠heading below that — COAPS caveat).
2. Weighted circular histogram of COG (10° bins, weight = distance) → two dominant modes
   (reaches) → axis = bisector.
3. 180° ambiguity: **no-go zone** — of the two axis ends, the one whose ±45° cone holds
   (almost) no distance is where the wind comes from; margin = relative cone asymmetry
   (`fullMargin` 0.4 ⇒ certain, both cones empty ⇒ unresolved) → else Open-Meteo prior →
   else user value.
4. Confidence ∈ [0,1] = axis confidence (lobe mass × lobe balance × mode separation) ×
   ambiguity margin; `< 0.5` ⇒ turns labeled `turn`, not tack/jibe, unless user set wind
   manually (manual always wins).

The **speed** asymmetry originally specified for step 3 is not used: across the whole
fixture corpus mean speed rises as the course turns *toward* the wind (a foil loses
apparent wind deep downwind), i.e. the opposite of the displacement-sailing rule it was
taken from. It is kept as a diagnostic only. The no-go-zone rule matches Garda's diurnal
pattern (morning Peler from N, afternoon Ora from S) on every corpus session.
Degenerate case: exactly opposed lobes (pure beam-reach out-and-back) put the true axis
perpendicular to the lobes where no bisector can find it — rejected, no estimate.

## Pump / takeoff detection (watch, live) — `garmin/source/detectors/PumpDetector.mc`

The watch runs the **same chain on the same numbers** as *Pumping (accelerometer)* above and
*Takeoff analysis* below — there is no second parameter set and nothing was re-tuned for the
port. `PumpDetector` consumes `Toybox.Sensor` accelerometer batches on the 25 Hz grid, and
every threshold (`pumpStrokeAmp` 0.25 g · `pumpRefractory` 0.4 s · `pumpStrokeMaxInterval`
1.5 s · `pumpMinStrokes` 4 · `takeoffAttemptWindow` 10 s · `freeTakeoff` < 3) is the tuned lab
default, compiled in rather than exposed in GCM: they were tuned on the corpus, and a rider
guessing at them would only break the comparison against the phone. What the rider does get is
two switches: `pumpDetection` (default on) and `alertTakeoff` (default on). The watch's old
`attemptSuccessWindow` (5 s) is gone — `takeoffAttemptWindow` plays both roles, as
*Takeoff analysis* already stated.

It lives in the **device app, not the WingFoilCore barrel**: every `Toybox.Sensor` entry point
crashes a data field (docs/fit-schema.md, source class d), so the shared core must not even
reference one. It is also the *second* consumer of the accelerometer — `SensorLogging` keeps
writing the raw stream into the FIT for the phone and the lab (`accelLogging`, default **on**,
the validation vehicle), while this listener hands the same motion to the live detector. Only
one sensor-data listener may exist per app, so registration is attempted once per session
inside a `try`: any refusal leaves the pump counters at zero and raw logging untouched.

Live output: `pump_cadence` (FIT record 2, strokes/min over the last 10 s), FIT session fields
35–38, three metric-catalog entries (pump strokes · `attempts>made` · last pumps-to-takeoff),
and one vibe when a pumped effort gets the rider up.

### Watch approximation — where the live detector differs from the lab

The lab sees the whole session at once and may classify a burst after the fact; the watch has
to answer while the rider is still on the water. The deviations, all deliberate:

| # | lab | watch | why it is acceptable |
|---|---|---|---|
| 1 | zero-phase `mode="same"` convolution | causal FIR, 51 taps, **1 s group delay** | stroke *timestamps* are corrected by the delay, so every window measured against GPS events is right; only the vibe is ~1 s late |
| 2 | empty grid bins held at the **session mean** | 20 s EMA level, subtracted per sample | the band-pass kills DC anyway and the EMA sits far below `pumpBandLo`; it makes the watch *more* conservative under a slow body lean (0.1 Hz at 1 g: lab 0 bursts, watch 0 strokes) |
| 3 | box-average onto a uniform grid | the sensor **is** the grid (25 Hz requested); a faster device is decimated onto it, a slower one leaves the detector unavailable rather than mis-banded | fenix 8 delivers exactly 25 Hz |
| 4 | gaps bookkept, their bins discarded | a late or short batch **restarts the filter**, and nothing is emitted for the 51-sample warmup | same intent: a dropout contributes no strokes rather than a burst of edge artifacts |
| 5 | episodes classified afterwards, ladder in_flight → success → recovery → unknown → failed | the same ladder, decided **when the burst qualifies**: one that starts while `STATE_ON` is in-flight pumping and never opens an effort; a turn window open during *any* stroke marks the effort as recovery (the lab asks whether the whole episode lies inside the window) | the watch cannot see the future; both approximations only ever *remove* attempts, so the live count is a floor and the phone stays authoritative |
| 6 | `ON_FOIL` is the exact flight boundary | the `STATE_OFF→STATE_ON` transition, backdated by `entryHoldS` | that is the instant the FlightDetector backdates its own accounting to |
| 7 | success = a flight starts inside the window | the flight must also be **confirmed** (`minFlight`, up to 5 s later); an effort whose window expires while the rider is ON foil is held pending until the flight is confirmed or collapses | nothing shorter than `minFlight` counts as a flight anywhere else either |
| 8 | `unknown` episodes are excluded from every tally | a GPS gap drops the open effort silently | identical outcome, same reason |
| 9 | `pumps_to_takeoff` = strokes in the run (speed rise ∪ lead burst) | strokes in the **effort** alone | the watch has no walk-back over past speed; a takeoff with no qualifying burst reports 0 = free takeoff, which is what the lab reports when the run holds no strokes |
| 10 | `takeoff_successes` = flights · `takeoff_attempts` = flights + failed efforts | identical, counted live | — |

Expected drift: the watch counts **fewer or equal** attempts, and its stroke total should sit
within a few percent of the phone's. Anything larger is the divergence check's business
(below) — filed against the session fixture, since a tuning difference is not a bug.

Phone metrics beyond the watch's: time-to-takeoff, HR cost (HR rise over attempt +30 s, only
over valid HR spans — see *HR cost* below), in-flight pump episodes (v2).

## Takeoff analysis (phone) — pumps-to-takeoff · attempts · in-flight pumping

The flight-**start** analogue of *Flight-end outcome*, and the differentiator metric set
(docs/plan.md §1). Flight segmentation says a flight began; this says what it cost to get
there, and — the part no summary built from flights alone can ever contain — how often he
pumped and *did not* get up. Feeds FIT session fields 35–38 and lap fields 12–13.

| param | default | units | notes |
|---|---|---|---|
| `takeoffMaxRun` | 30 | s | cap on the pre-flight window searched back from `ON_FOIL` |
| `takeoffRiseSlack` | 0.3 | m/s | walking back, a sample still belongs to the speed rise while it is no more than this above the slowest sample seen so far (monotone enough to be a takeoff, loose enough for a real water start) |
| `takeoffRestSpeed` | 1.0 | m/s | walking back, the first sample at or below this *is* the run start — he was sitting on the board. Without it a slack-tolerant walk-back swallows the whole rest, because a flat trace is "non-increasing" too (= `turnStopSpeedFloor`) |
| `takeoffAttemptWindow` | 10 | s | an attempt stays open this long past its last stroke: `ON_FOIL` inside the window ⇒ that attempt succeeded and its burst is the flight's takeoff run; silence past it ⇒ the attempt failed. Also the silence that separates two attempts |
| `takeoffMinPreWindow` | 3 | s | less gap-free record than this before a flight start ⇒ the run is not in the data (`truncated`) |
| `freeTakeoff` | < 3 strokes | | got up on wind alone — a fact about the conditions, not about his pumping, so the two are separated in every average |

Bursts, cadence and `pumpMinStrokes` come from *Pumping (accelerometer)* unchanged; turn
ownership uses the same window as *Flight-end outcome* (`start` → `end + outcomeWindow`).

**The takeoff run** is the contiguous pre-flight window of rising speed *plus* the pump burst
that led into it, whichever started earlier — so `pumps_to_takeoff` counts the strokes of the
effort that actually produced the flight, and `duration_s ≥ speed_rise_s` always. The rise is
read on the Doppler channel, the one that defined the flight boundary, so run and flight agree
on where the takeoff ended. The walk-back also stops at a recording gap and at the previous
flight's end: a run cannot reach back through the flight before it.

`takeoffAttemptWindow` deliberately **replaces the watch's 5 s `attemptSuccessWindow`** rather
than mirroring it. On 2026-08-07 the qualifying burst ends 0.1–2.5 s before `ON_FOIL` for 20 of
23 takeoffs, but 6.2 s, 8.0 s and 8.7 s before it for three, where the board kept accelerating
after he stopped pumping; at 5 s those three lose their run (and one reads as a *free* takeoff
that was nothing of the sort). 10 s costs nothing and matches the watch's `attemptFailSilence`,
so one number plays both roles and there is no dead zone in which an attempt is neither.

**Every pumping burst is classified exactly once** — the ownership discipline of the flight
ends, for the same reason. Bursts less than `takeoffAttemptWindow` apart are first chained into
one **episode** (one continuous effort: four bursts inside a minute of thrashing are one failed
attempt, not four), then:

| outcome | test | counted as |
|---|---|---|
| `in_flight` | the episode lies wholly inside a flight | `in_flight_strokes` — pumping to hold or extend a glide, never a takeoff |
| `success` | a flight starts between the first stroke and `takeoffAttemptWindow` after the last | nothing extra: it *is* that flight's takeoff run, already counted as a flight |
| `recovery` | the episode lies inside a detected turn's outcome window | the turn's `touchdown`, already scored there |
| `failed` | none of the above | a failed takeoff attempt |
| `unknown` | the record does not run gap-free for `takeoffAttemptWindow` past the last stroke | nothing — excluded from every tally |

`takeoff_attempts` = flights + failed attempts, `takeoff_successes` = **flights**: a flight
demonstrably happened, so it succeeded even when its run was truncated; truncation only removes
it from the pumps/duration averages. Sources without an accelerometer report the speed-only run,
`None` stroke counts and — because their failures are invisible — a `None` success rate rather
than a flattering 100 %.

**Corpus (defaults above).** 2026-08-07 ciq: 23 takeoffs, all judged, 14 failed attempts ⇒ 37
attempts at 62 % success; 9.0 pumps to takeoff on average (median 7, range 4–21), 8.7 s average
run (median 8.0), 0 free takeoffs, 1341 strokes of which 293 in flight across 36 in-flight
episodes. The native sessions have no accel and lose most runs to Smart Recording: 2026-08-05 am
9 of 52 runs judged (6.8 s average), 2026-08-04 pm 23 of 130 (7.6 s) — the same truncation that
costs 111 of its 130 flight *ends*. **Unvalidated:** the failed-attempt count has no ground
truth yet (fixtures/README.md logs takeoff attempts per session — 2026-08-07 is still blank),
and it is the one number here that moves with `takeoffAttemptWindow`: 15 failures at 8 s, 14 at
10 s, 10 at 12 s, 9 at 15 s (56 %/62 %/70 %/72 % success). Everything else is flat from 10 s up.

## HR cost (phone) — what an attempt costs in heartbeats

Jan's question: *"my HR goes up when I pump."* `lab/src/wingfoil_lab/hrcost.py` answers four
versions of it — per-takeoff cost, pumping vs cruising, fatigue over the session, and recovery
— from the FIT `heart_rate` channel joined to the takeoff runs, the flight ends and the turns.

**Exploratory (phase 3.5).** Not in the golden schema and not counted by `ENGINE_VERSION` yet:
these numbers move with the definitions below, and freezing them before the Swift port would
freeze the wrong ones. `tools/hr_report.py` reproduces everything in this section.

| param | default | units | notes |
|---|---|---|---|
| `hrCostPeakWindow` | 30 | s | peak searched this far past the anchor. Not the burst length: optical HR trails effort by 10–20 s (measured median peak lag 20.5 s on 2026-08-07), so a window as short as the effort measures the HR he *arrived* with |
| `hrBaselineWindow` | 10 | s | baseline = **median** (not mean — one spike must not move it) of the usable samples in the window ending at the anchor |
| `hrMinCoverage` | 0.6 | | a window below this share of usable seconds yields `None`, never a number |
| `hrMaxSampleGap` | 10 | s | longer between two samples ⇒ an HR hole. Deliberately **not** the cleaner's dt-aware speed rule (~4 s here): that rule protects speed integration, and HR is a slow channel two samples 6 s apart bracket perfectly well. Smart Recording writes 1–9 s cadences (2026-08-05: 985 intervals, 5 of them ≥10 s; 2026-08-04 pm: 3745, 13 of them) so 10 s sits in a real valley of the distribution. Under the speed rule the natives lose 93–94 % of their takeoff costs to "gaps" that are nothing of the sort (3/52 and 9/130 measurable, against 52/52 and 129/130 here) |
| `hrFlatlineMax` | 60 | s | identical bpm for longer, inside one gap-free stretch ⇒ stuck sensor, whole run dropped. Corpus longest identical runs: 21 s (ciq), 17 s / 27 s (natives), so at 60 s the guard removes **nothing** today — it is there for a future dropout, where an optical sensor holds one value for minutes, and it must not fire on a genuinely steady resting heart |
| `hrMinBpm` / `hrMaxBpm` | 30 / 220 | bpm | outside this is sensor garbage, not a heart rate |
| `hrLag` | 10 | s | pumping/cruising **classification** windows are shifted forward by this, and cruising additionally excludes a ±`hrLag` guard band around every burst. Without it the metric mostly compares the HR he brought into each burst |
| `hrRecoveryWindow` | 120 | s | cap on the half-decay search; running past it is `censored`, a fact about the window |
| `hrMinRise` | 5 | bpm | below this there was no rise to recover from — no recovery is measured, and the attempt is not in the recovery denominator |
| `hrBinMinutes` | 20 | min | fatigue-curve bin width (equal thirds also available for short sessions) |

**Validity, and why nothing is ever fabricated.** A wrist sensor under a wetsuit sleeve, in
cold water, on an arm being thrown around, drops out and sticks. Three per-sample guards —
plausible, not stale, not across a hole — collapse into one number per window: **coverage**,
the share of the window's seconds carried by intervals whose *both* end samples survive all
three (the same both-ends-qualify convention flight segmentation and the stop measure use).
Below `hrMinCoverage` the metric is `None`. Every aggregate is printed as `n valid / n total`,
so a summary can never quietly average three takeoffs and call it a session. A hole *inside* a
covered window can only hide a **higher** peak than the one observed, so a cost read across
one is biased low, never high.

**The anchor is the start of the effort**, i.e. the takeoff *run* start (`takeoff.py`) — the
first stroke of the burst that produced the flight, or the start of the speed rise when that
came earlier. Anchoring on `ON_FOIL` instead would measure a different thing entirely: its
baseline is read *during* the pumping (already elevated) and its window runs 30 s into the
flight, so on 2026-08-07 it reports a *larger* number, 7.9 bpm against 6.9, made of the rise
that the attempt had already produced plus whatever the first half-minute of flying added.
The run anchor is the one for which "what this attempt cost" is the thing being measured. Two
degraded anchors are flagged
`approximate`: no strokes in the run (no accelerometer, or a genuinely free takeoff), and a
truncated run, which anchors on the flight start itself and so measures the HR delta across
the off-foil → on-foil transition alone. That fallback is what gives native sessions a figure.

| metric | definition |
|---|---|
| takeoff HR cost | peak − baseline around the anchor. **Negative values are reported**, not clamped: "he was still recovering when he started" is a different fact from "this cost nothing" |
| pumping vs cruising | time-weighted mean HR over the `hrLag`-shifted burst spans (all of them — takeoff, failed, recovery, in-flight: one physical act) against the same over on-foil time outside the guard bands |
| bpm per stroke | **pooled** Σcost ⁄ Σstrokes over the takeoffs that have both. The median of the per-takeoff ratios is reported beside it, because dividing a 3 bpm cost by 4 strokes one takeoff at a time turns sensor noise into a wide spread |
| fatigue curve | per bin: attempts (flights started in the bin + failed episodes whose first stroke is in it), success rate, avg/median cost, **avg baseline**, mean HR, avg pumps, and the cost coverage |
| recovery | seconds from the peak until HR first falls halfway back to the baseline. The search stops at a hole — HR 120 before an eleven-minute gap and 88 after it did not decay in that window, and calling it a fast recovery would be the most flattering possible lie |

**Corpus (defaults above).** 2026-08-07 ciq: cost 6.9 bpm avg / 7.0 median over **23/23**
takeoffs, all burst-anchored; pumping 101.6 vs cruising 96.0 bpm (**+5.6**, coverage 1.00 on
both sides); 0.76 bpm per stroke; half-recovery 12 s (14/15) after takeoffs, 18 s (4/7) after
swims. The two native sessions have no strokes and every anchor `approximate`, yet land on the
same cost: 2026-08-05 am 6.1 bpm avg (52/52), 2026-08-04 pm 7.2 bpm (129/130) — a real
cross-source check on the fallback anchor, since nothing about it is shared with the class-(a)
path. Usable HR: 76 % / 98 % / 86 % of the session span (the ciq loss is three genuine
breaks totalling 22 min).

**Fatigue: half the hypothesis held, and the other half is a warning about the metric.**
2026-08-07 in thirds — 67 % / 69 % / **44 %** success (12 / 16 / 9 attempts), with four of the
last third's five failed attempts in the 1:17–1:23 cluster. The *success* collapse is real and
the 20-minute bins bracket it the same way: 64 / 75 / 69 / 50 / **33 %**. The **cost** does the
opposite
of the prediction: 7.3 / 9.3 / **−0.5** bpm by thirds. It is not that the late attempts were
cheap, it is that there was no headroom left to rise into — mean attempt baseline 92 → 100 → 99
bpm across the thirds (89 → 103 across the 20-minute bins), and the session's last three
takeoffs read −1 / +1 / −9 bpm off baselines of 113 / 103 / 103 against a session maximum of
126. A rise measured against a drifting baseline is not a fatigue metric on its own; that is
why `avg_baseline_bpm` sits beside `avg_cost_bpm` in every bin, and why the honest late-session
statement is *"attempts starting 8–14 bpm higher, success rate down 25 points, rise exhausted"*.
Normalising the cost against the range still available to the session maximum is the obvious
next tuning step, and needs a session where he actually reached his max.

## Divergence check (phone, source class (a) only)

Banner when watch session fields vs phone recompute differ by: foil time > 5 % · any speed
record > 0.3 kn · flight/turn/attempt counts off by > 1. Divergences are tuning issues, not bugs
by definition — file them against the session fixture.

---

## Jumps (theoretical, uncalibrated)

> **Nothing in this section has ever been checked against a jump.** Jan does not jump (yet),
> so the corpus contains no labelled jump and no calibration exists. Every accuracy figure
> below was measured against a synthetic generator built from the physics we assume — it
> validates the *maths*, not the water. Lab-only: `lab/src/wingfoil_lab/jump.py`, reproduced
> by `uv run python lab/tools/jump_report.py`. It feeds no golden, no watch field, no phone
> metric, and `ENGINE_VERSION` is untouched. The day a real jump is recorded, every threshold
> here is a starting point to be re-tuned, not a setting to be trusted.

### The physics — why hang time alone lies

The textbook formula `h = g·T²/8` assumes an unsupported ballistic body. A wingfoiler is not
one: **the wing is loaded through the whole jump**, lifting on the way up and parachuting on
the way down, so vertical acceleration is smaller than `g` in *both* phases. Same airtime,
much less height — and applied naively the formula therefore **overestimates**.

An accelerometer measures *specific force*, not acceleration: ~0 g in free fall, ~1 g fully
supported. During the airborne phase it reads the **support fraction** `s(t) = |a|(t)/g`
directly, i.e. exactly the quantity the naive formula assumes is zero. The sensor that gives
us the airtime also tells us how wrong the airtime is. With support the equation of motion is

```
z''(t) = −(1 − s(t))·g          s ∈ [0,1], measured per sample
```

integrated over the airborne window `[t0,t1]` with `z(t0) = z(t1) = 0` — he left the water and
came back to it, which **pins the initial vertical velocity** rather than leaving it free.
The whole estimate then follows from two measured quantities: the airtime and the support
profile. Three estimators are reported side by side, deliberately:

| estimator | formula | role |
|---|---|---|
| `integrated` | simulate `z'' = −(1−s(t))g` over the measured profile, report peak `z` | **primary** |
| `closed_form` | `(1 − s_mean)·g·T²/8` | comparison; provably identical to `integrated` for constant `s` |
| `naive` | `g·T²/8` | **comparison only, never a metric** |

**Wrist vs centre of mass.** `s(t)` is measured at the wrist — the hand holding the loaded
wing, the part of the body most directly coupled to the lifting surface, and not the centre of
mass. Arm flex, sheeting and the wing's own swing add wrist-specific force the trunk never
feels, in either direction: pulling the wing down loads the wrist above body support, letting
it float unloads it below. The estimator treats wrist support as a proxy for body support, and
the **±0.1 support-profile term dominates the error budget precisely to cover that proxy
error** (97 % of the variance — see the budget table). A chest or waist sensor would remove the
caveat; a wrist watch cannot.

### Parameters

| param | default | units | notes |
|---|---|---|---|
| `jumpSmooth` | 0.06 | s | **median** filter span on \|a\| before thresholding |
| `jumpAirborneMaxG` | 0.75 | g | \|a\| below this is "airborne". A **hard ceiling on visible support** — see below |
| `jumpBridge` / `jumpBridgeMaxG` | 0.10 / 0.95 | s / g | a noise excursion shorter than this, staying under this, does not end the window |
| `jumpMinAirtime` | 0.4 | s | shorter is chop or a pump trough, not a jump |
| `jumpMaxAirtime` | 4.0 | s | longer is a dropout. 4.0 s covers a 5 m jump at s = 0.7 (T = 3.69 s) |
| `jumpTakeoffMinG` | 1.8 | g | pop spike required in the 0.5 s before the window |
| `jumpImpactMinG` | 2.5 | g | landing spike required in the 0.5 s after it |
| `jumpSpikeWindow` | 0.5 | s | search span for both spikes |
| `jumpRefractory` | 2.0 | s | dead time after an accepted jump |
| `jumpMaxGap` | 0.1 | s | a sensor hole inside the window voids it |
| `jumpSupportSigma` | 0.1 | | assumed error on the support profile (the wrist-vs-COM term) |
| `jumpBaroContext` | 5.0 | s | baseline span each side of the window for the template fit |
| `jumpBaroMinSamples` | 2 | | fewer in-window altitude samples ⇒ "insufficient samples", no number |

A **median** filter, not the box average `pump.py` uses: a box drags the tail of the takeoff
spike into the first samples of the airborne window and shortens the measured airtime by ~4 %,
and `h` goes as `T²`. The median rejects the spike and preserves the step edge. Window edges
are then refined by linear interpolation of the `jumpAirborneMaxG` crossing — at 25 Hz a
half-sample is already 7 % of the height of a 0.6 s jump.

### Noise model — measured from the real corpus, not assumed

From `2026-08-07-0754_..._ciq.fit`: accel **0.114 g** per-sample σ (quietest quartile of 1 s
blocks inside the 23 flights, 611 blocks; mean 1.019 g), 100 Hz; altitude **0.189 m** detrended
σ at rest, **0.20 m** quantum, 1 Hz. These are the numbers the synthetic generator uses, so
"does this survive the sensor" is answered with the sensor we actually have.

### The headline — the naive formula overshoots by exactly 1/(1−s)

Jan's claim, made quantitative. 80 Monte-Carlo reps per cell, 100 Hz, measured noise:

| s (support fraction) | 1/(1−s) predicted | **naive / true measured** | integrated / true | closed-form / true |
|---|---|---|---|---|
| 0.0 | 1.00x | **1.01x** | 0.985 | 0.982 |
| 0.2 | 1.25x | **1.25x** | 1.002 | 0.997 |
| 0.4 | 1.67x | **1.66x** | 0.997 | 0.993 |
| 0.6 | 2.50x | **2.47x** | 0.986 | 0.983 |
| 0.7 | 3.33x | **3.07x** | 0.928 | 0.928 |

Concretely: a 1 m jump with a wing carrying 40 % of the rider's weight hangs for 1.17 s, and
`g·T²/8` calls that **1.67 m**. At s = 0.7 it calls a 1 m jump **3.3 m**. That is the entire
argument for this module, and it is not a small correction — it is most of the number. (The
s = 0.7 row falls slightly short of 3.33x only because those windows are partly clipped by the
detection ceiling; the noise-free grid returns 3.31–3.33x across every height.)

### Full grid, measured noise, 100 Hz, constant support (80 reps/cell)

Bias is `(mean estimate − truth)/truth`; `±` is the spread over reps.

| h_true (m) | s | airtime (s) | det | integrated (m) | closed-form (m) | naive (m) | naive/true |
|---|---|---|---|---|---|---|---|
| 0.5 | 0.0 | 0.64 | 100 % | 0.49 ± 0.01 (−1.5 %) | 0.49 ± 0.01 (−2.1 %) | 0.50 ± 0.00 | **1.01x** |
| 0.5 | 0.2 | 0.71 | 100 % | 0.50 ± 0.01 (+0.7 %) | 0.50 ± 0.01 (−0.2 %) | 0.63 ± 0.00 | **1.26x** |
| 0.5 | 0.4 | 0.82 | 100 % | 0.50 ± 0.01 (−0.1 %) | 0.50 ± 0.01 (−1.0 %) | 0.83 ± 0.00 | **1.67x** |
| 0.5 | 0.6 | 1.01 | 100 % | 0.49 ± 0.02 (−2.7 %) | 0.48 ± 0.02 (−3.4 %) | 1.22 ± 0.02 | **2.44x** |
| 0.5 | 0.7 | 1.17 | 95 % | 0.44 ± 0.09 (−12.4 %) | 0.44 ± 0.09 (−12.3 %) | 1.45 ± 0.28 | **2.91x** |
| 1 | 0.0 | 0.90 | 100 % | 0.99 ± 0.01 (−1.0 %) | 0.99 ± 0.01 (−1.4 %) | 1.01 ± 0.00 | **1.01x** |
| 1 | 0.2 | 1.01 | 100 % | 1.00 ± 0.02 (+0.2 %) | 1.00 ± 0.02 (−0.4 %) | 1.25 ± 0.00 | **1.25x** |
| 1 | 0.4 | 1.17 | 100 % | 1.00 ± 0.02 (−0.3 %) | 0.99 ± 0.02 (−0.9 %) | 1.66 ± 0.00 | **1.66x** |
| 1 | 0.6 | 1.43 | 100 % | 0.98 ± 0.03 (−1.8 %) | 0.98 ± 0.03 (−2.0 %) | 2.46 ± 0.02 | **2.46x** |
| 1 | 0.7 | 1.65 | 80 % | 0.91 ± 0.13 (−9.4 %) | 0.91 ± 0.13 (−9.3 %) | 2.99 ± 0.41 | **2.99x** |
| 2 | 0.0 | 1.28 | 100 % | 1.97 ± 0.01 (−1.7 %) | 1.96 ± 0.01 (−1.9 %) | 2.01 ± 0.00 | **1.00x** |
| 2 | 0.2 | 1.43 | 100 % | 2.00 ± 0.03 (+0.0 %) | 1.99 ± 0.03 (−0.3 %) | 2.50 ± 0.00 | **1.25x** |
| 2 | 0.4 | 1.65 | 100 % | 1.99 ± 0.04 (−0.4 %) | 1.99 ± 0.03 (−0.7 %) | 3.32 ± 0.01 | **1.66x** |
| 2 | 0.6 | 2.02 | 100 % | 1.97 ± 0.05 (−1.3 %) | 1.97 ± 0.04 (−1.7 %) | 4.94 ± 0.03 | **2.47x** |
| 2 | 0.7 | 2.33 | 66 % | 1.91 ± 0.17 (−4.5 %) | 1.91 ± 0.16 (−4.5 %) | 6.31 ± 0.45 | **3.15x** |
| 3 | 0.0 | 1.56 | 100 % | 2.96 ± 0.02 (−1.5 %) | 2.95 ± 0.02 (−1.7 %) | 3.02 ± 0.00 | **1.01x** |
| 3 | 0.2 | 1.75 | 100 % | 3.00 ± 0.04 (+0.1 %) | 3.00 ± 0.03 (−0.1 %) | 3.75 ± 0.00 | **1.25x** |
| 3 | 0.4 | 2.02 | 100 % | 2.99 ± 0.05 (−0.2 %) | 2.99 ± 0.04 (−0.5 %) | 4.98 ± 0.01 | **1.66x** |
| 3 | 0.6 | 2.47 | 100 % | 2.98 ± 0.07 (−0.7 %) | 2.97 ± 0.06 (−0.9 %) | 7.46 ± 0.04 | **2.49x** |
| 3 | 0.7 | 2.86 | 49 % | 2.86 ± 0.21 (−4.6 %) | 2.86 ± 0.21 (−4.6 %) | 9.52 ± 0.74 | **3.17x** |
| 5 | 0.0 | 2.02 | 100 % | 4.90 ± 0.03 (−1.9 %) | 4.89 ± 0.03 (−2.2 %) | 5.01 ± 0.01 | **1.00x** |
| 5 | 0.2 | 2.26 | 100 % | 4.99 ± 0.06 (−0.2 %) | 4.98 ± 0.05 (−0.4 %) | 6.25 ± 0.01 | **1.25x** |
| 5 | 0.4 | 2.61 | 100 % | 4.98 ± 0.07 (−0.4 %) | 4.97 ± 0.06 (−0.6 %) | 8.32 ± 0.01 | **1.66x** |
| 5 | 0.6 | 3.19 | 100 % | 4.98 ± 0.11 (−0.4 %) | 4.96 ± 0.10 (−0.7 %) | 12.44 ± 0.06 | **2.49x** |
| 5 | 0.7 | 3.69 | 51 % | 4.75 ± 0.43 (−5.1 %) | 4.73 ± 0.42 (−5.4 %) | 15.63 ± 1.39 | **3.13x** |

**Noise-free, the same grid is flat to ±1.3 % in every cell at 100 % detection** — so the
residual bias above is the sensor's, not the algorithm's. The remaining structure is all one
effect: at `s = 0.7` the signal sits 0.05 g below the 0.75 g threshold against ~0.06 g of
filtered noise, so windows fragment, detection falls to 49–95 % and the survivors are the ones
whose noise happened to run low — which truncates the window and reads the height short.

### Time-varying support — and where the two corrected estimators finally part

For **constant** `s` the integrated and closed-form estimators are the same estimator (a
theorem, and the grid confirms it to <0.5 % everywhere). Symmetric ramps (`s_mean ± 0.15`
across the flight) do not separate them either, because a ramp's effect on the double integral
nearly cancels about the midpoint:

| profile | s_mean | integrated err | closed-form err | naive/true | det |
|---|---|---|---|---|---|
| `ramp_up` | 0.2 | +0.3 % | −0.3 % | 1.25x | 100 % |
| `ramp_up` | 0.4 | +0.0 % | −0.6 % | 1.66x | 100 % |
| `ramp_up` | 0.6 | −6.2 % | −6.5 % | 2.30x | 98 % |
| `ramp_up` | 0.7 | −31.4 % | −31.2 % | 2.06x | 35 % |
| `ramp_down` | 0.2 | +0.0 % | −0.5 % | 1.25x | 100 % |
| `ramp_down` | 0.4 | −0.1 % | −0.7 % | 1.66x | 100 % |
| `ramp_down` | 0.6 | −7.1 % | −7.5 % | 2.28x | 98 % |
| `ramp_down` | 0.7 | −30.3 % | −30.0 % | 2.10x | 34 % |

The ramp rows at `s_mean` 0.6–0.7 are **not an estimator failure**: a ±0.15 ramp about 0.7
peaks at 0.85 g, above `jumpAirborneMaxG`, so half the window is literally invisible and the
airtime is measured short. It is the detection ceiling again, wearing a different hat.

The case that *does* separate them is the physically expected one — **support concentrated in
the descent** (wing sheeted out for the pop, parachuting the landing). The mean support is
unchanged, so the closed form cannot see the difference:

| s_mean | s during descent | **integrated err** | closed-form err | naive/true |
|---|---|---|---|---|
| 0.1 | 0.2 | **−0.5 %** | −1.1 % | 1.12x |
| 0.2 | 0.4 | **−1.0 %** | −2.6 % | 1.24x |
| 0.3 | 0.6 | **−0.7 %** | −4.2 % | 1.39x |
| 0.35 | 0.7 | **−5.1 %** | −10.0 % | 1.38x |

That is why the integrated estimator is primary: it costs nothing when support is symmetric
and it is the only one that stays honest when support is not.

### Per-jump uncertainty — systematics-limited, not noise-limited

`h_true` = 1 m, `s` = 0.3, 100 Hz. Sensitivity is `dh/ds = −g·T²/8` for the support terms and
`dh/dT = 2h/T` for timing; the three combine in quadrature.

| term | σ (m) | share of variance |
|---|---|---|
| accel noise (0.114 g, ~100 samples, median efficiency √(π/2)) | 0.019 | 2 % |
| **support profile ±0.1 (the wrist-vs-COM proxy)** | **0.142** | **97 %** |
| timing ±1 sample | 0.018 | 2 % |
| **combined** | **±0.14 m on h = 0.97 m** | |

**A better accelerometer would buy nothing.** The error is dominated by not knowing how well
the wrist represents the body, and the only fixes are a torso-mounted sensor or a real
calibration against measured jumps.

### `jumpAirborneMaxG` is a hard ceiling, and 0.75 g is where the trade-off sits

A jump whose support never drops below the threshold is not badly estimated — it is
**structurally invisible**. Detection rate against support fraction:

| `jumpAirborneMaxG` | s=0.0 | s=0.2 | s=0.4 | s=0.6 | s=0.7 | candidates on the real session |
|---|---|---|---|---|---|---|
| 0.60 g | 100 % | 100 % | 100 % | 18 % | 0 % | 1 |
| **0.75 g** | 100 % | 100 % | 100 % | 100 % | 75 % | **5** |
| 0.90 g | 100 % | 100 % | 100 % | 100 % | 100 % | 151 |

The 0.6 g starting suggestion is not viable: it makes any jump on a well-loaded wing
undetectable. 0.9 g sees everything and drowns in false positives — because at 0.9 g the
trough of a normal 1 Hz pump stroke stays sub-threshold for 0.44 s, clearing `jumpMinAirtime`.
**0.75 g is the value at which a 1 Hz ±0.5 g pump is sub-threshold for only 0.33 s** and is
rejected by the airtime floor alone, before any spike gate is consulted, while still covering
support up to 0.7. That coincidence is the reason for the default, and `test_jump.py` asserts
both halves of it.

### Sample rate — 100 Hz matters

The same grid at 25 Hz costs 3–6 % of bias at low support and collapses above it (s = 0.7:
0–6 % detection; s = 0.6: 60–96 %). The fenix 8 logs accel at **100 Hz**, which is what the
defaults assume; a downsampled stream should not use this estimator above s ≈ 0.4.

### Baro secondary — honest about when it cannot answer

The airborne window is handed to the barometer by the accelerometer, not searched for, so a
1 Hz channel has just one interesting free parameter. A unit-peak parabolic rise-fall template
is least-squares fitted against a local baseline + drift over `jumpBaroContext` either side.
Below `jumpBaroMinSamples` = 2 in-window samples it reports **`insufficient_samples`** and no
number rather than inventing a height from one point:

| h_true (m) | airtime (s) | fit rate | fitted height (m) |
|---|---|---|---|
| 0.5 | 0.87 | 2 % | 0.21 ± 0.63 |
| 1 | 1.23 | 23 % | 0.91 ± 0.33 |
| 2 | 1.74 | 68 % | 2.00 ± 0.23 |
| 3 | 2.13 | 84 % | 3.01 ± 0.20 |
| 5 | 2.75 | 100 % | 5.02 ± 0.19 |

So the barometer is useless below ~1 m and a genuine independent check above ~2 m — **and even
that is an upper bound**, because the simulated barometer samples true altitude at 1 Hz with
only the measured noise and quantisation, whereas Garmin's real channel is explicitly filtered
(see the CIQ finding below). Expect the real thing to be worse; it has never been tested
against a real jump either.

### Can Connect IQ deliver pressure at high rate on fenix 8? **No.**

Checked against SDK 9.2.0 (`connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2`), because it decides
whether the baro channel could ever move on-watch.

- **`Toybox.SensorLogging.SensorLogger`** accepts exactly `:accelerometer`, `:gyroscope`,
  `:magnetometer` (+ `:synchronous`). `getStats2` returns stats for those three and no others.
  There is no pressure channel, and the logging rate is not developer-controllable
  ("the logger will always record at a standard rate", *Core_Topics/Sensors.html*).
- **`Sensor.registerSensorDataListener`** options are exactly `:period` (max 4 s),
  `:synchronous`, `:accelerometer`, `:gyroscope`, `:magnetometer`, `:heartBeatIntervals`. Only
  the three IMU sensors take `:sampleRate`. `Sensor.SensorData` carries only
  `accelerometerData` / `gyroscopeData` / `magnetometerData` / `heartRateData`.
  `getMaxSampleRateForSensorType` documents its "allowed symbols are `accelerometer`,
  `gyroscope`, and `magnetometer`" — **pressure is not even a queryable sensor type**.
- **The only pressure access** is `Activity.Info.rawAmbientPressure` (least processed),
  `Activity.Info.ambientPressure` ("smoothed by a two-stage filter"), `Sensor.Info.pressure`,
  and `SensorHistory.getPressureHistory` (fenix 8: one sample per **120 s**). Every documented
  delivery path is **1 Hz** — `Sensor.enableSensorEvents` ("at a rate of 1 Hz"),
  `DataField.compute` ("called once per second"). Polling `Activity.getActivityInfo()` faster
  from a Timer is undocumented and unverified; repeated identical values are the expected
  outcome.
- **fenix 8 device profile** (`simulator.json`, all variants): `maxAccelRate` 100,
  `maxGyroRate` 100, `maxMagRate` 50 — **no pressure rate key of any kind**. The device
  reference pages carry no sensor inventory at all; barometer presence is established only
  indirectly, via the `Supported Devices` list on `Activity.Info.ambientPressure`.

**Consequence:** the baro secondary is a phone/lab-side estimator against the 1 Hz
`enhanced_altitude` already in the FIT. It can never be improved on-watch, and the only
high-rate vertical signal available on fenix 8 is the 100 Hz IMU — which is what the primary
estimator uses.

### Corpus sweep — nothing found, which is the expected result

Detection run over all 14 fixtures at the defaults. The 12 native/other-app files carry no
accelerometer stream and are **skipped** (`detect_jumps` returns `None`, as everywhere else in
the lab); so is the synthetic smoke fixture. Only the class-(a) ciq session has accel.

On `2026-08-07-0754_..._ciq.fit` (414,700 samples, 100 Hz), **five candidates — none of them a
jump**, and they are all labelled `candidate` because there is nothing here to classify:

| t (s) | airtime | min \|a\| | status | note |
|---|---|---|---|---|
| 1082.7 | 0.43 s | 0.24 g | gated out, `gap_in_window` | off-foil, speed rising 4→8 kn |
| 2378.1 | 0.50 s | 0.47 g | gated out, `no_takeoff_spike` | 7 s before a `fell_in` flight end |
| 3167.5 | 0.44 s | 0.44 g | gated out, `no_takeoff_spike` | 6 s before a `fell_in` flight end |
| **3329.6** | **0.43 s** | — | **passed every gate** | pop 2.1 g, impact 4.9 g, s_mean 0.63 → **0.09 ± 0.02 m** (naive: 0.23 m) |
| 4149.9 | 0.43 s | 0.52 g | gated out, `no_takeoff_spike` | 0.1 s before a `fell_in` flight end |

**The one candidate that passed every gate estimates to 9 cm** — chop, not air, and the
estimator says so. The important structural finding is the other four: **three of them sit
within 7 s of a `fell_in` flight end**, and the fourth of an `unknown` one. That is not a
coincidence — *a fall has the same shape as a jump through this sensor*: the wrist unweights as
the rider drops off the foil, then the water delivers a 5 g impact. Falls are the dominant
false-positive class, and the obvious next gate is a cross-check the lab already has: **a jump
must be followed by continued flight, a fall is followed by a flight end.** Worth wiring in
before this is ever shown to a rider.

### Status and what would change it

| | |
|---|---|
| validated against | a synthetic generator built from the assumed physics — **nothing else** |
| never validated against | a real jump, at any height, by anyone |
| accuracy claim | ±1.3 % noise-free, ±2 % with measured noise, for s ≤ 0.6 at 100 Hz — **of the model** |
| honest per-jump uncertainty | ±0.14 m on a 1 m jump, 97 % of it the wrist-vs-COM proxy |
| what would make it real | a session with jumps, each height independently measured (video against a fixed reference, or a second IMU on the torso). Ten labelled jumps would settle `jumpAirborneMaxG`, the true `s` range, and whether the wrist proxy holds at all |
