# Canonical Algorithm Parameters (contract)

Single source of truth for detection/metric parameters. Three implementations follow this table:
`lab/src/wingfoil_lab/*` (tuning ground), `ios/WingFoilKit/Sources/AnalysisEngine/*`
(authoritative), `garmin/source/{detectors,metrics}/*` (live approximation). Defaults get
re-tuned in lab notebooks against the labeled fixture corpus; changed defaults are updated HERE
first, with the tuning notebook referenced in the commit.

`ENGINE_VERSION`: **0.1.0** (bump on any change that alters outputs; triggers phone re-analysis)

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
| `turnSuccessPct` | 70 | % | success ⇒ minSpeed/entrySpeed ≥ this AND speed never ≤ `foilExitSpeed` |
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

## Pump / takeoff detection

Watch (live, conservative): accel magnitude at `getMaxSampleRate()` (~25 Hz) → FIR band-pass
0.5–2.5 Hz → peak pick.

| param | default | units | notes |
|---|---|---|---|
| `pumpBandLow` / `pumpBandHigh` | 0.5 / 2.5 | Hz | wing-pump stroke band |
| `pumpMinProminence` | TBD (lab) | m/s² | tune on wrist-accel corpus first |
| `pumpRefractory` | 400 | ms | max ~2.5 strokes/s |
| `pumpArmed` | OFF_FOIL only (watch) | | chop/arm-swing rejection; phone also analyzes in-flight pumping from raw accel |
| `attemptSuccessWindow` | 5 | s | ON_FOIL within this after last stroke ⇒ attempt succeeded |
| `attemptFailSilence` | 10 | s | no strokes for this ⇒ attempt failed |
| `freeTakeoff` | < 3 strokes | | flight with takeoff_pumps < 3 counts as "free" (enough wind) |

Phone metrics: pumps-to-takeoff, time-to-takeoff, cadence, HR cost (HR rise over attempt +30 s,
only over valid HR spans), attempts/successes, in-flight pump episodes (v2).

## Divergence check (phone, source class (a) only)

Banner when watch session fields vs phone recompute differ by: foil time > 5 % · any speed
record > 0.3 kn · flight/turn/attempt counts off by > 1. Divergences are tuning issues, not bugs
by definition — file them against the session fixture.
