> Part of `docs/algorithms.md`. Engine 0.23.0.

## Pumping (accelerometer)

Phone-side twin of the watch `PumpDetector`, and the only consumer of the raw SensorLogging
stream so far. A wing pump is a whole-body oscillation the wrist sees as a large swing in |a|;
wing trim and arm drift are slower or smaller.

**Chop is not faster and smaller — it is the same speed and only somewhat smaller.** That
sentence stood here until engine 0.8.0 and the corpus does not support it. Measured on the
2026-08-30 example (band-passed |a|, Welch over the flights and over the ten seconds before
each `ON_FOIL`):

| | dominant | rms, band-passed | raw \|a\| σ | detected strokes |
|---|---|---|---|---|
| on foil, cruising | **0.98 Hz** | 0.18 g | 0.30 g | median peak 0.35 g |
| pumping onto the foil | **1.76 Hz** | 0.42 g | — | median peak 0.65 g |

Chop plus the arm riding it sits *below* pumping cadence, dead centre in the pass band, and
its crests clear `pumpStrokeAmp` — so the peak picker fires roughly once per crest for the
whole flight. Amplitude, not frequency, is what separates the two, and only by about 2×.

| param | default | units | notes |
|---|---|---|---|
| `pumpBandLo` / `pumpBandHi` | 0.5 / 2.5 | Hz | pumping cadence band |
| `pumpResampleHz` | 25 | Hz | |a| box-averaged onto a uniform grid (anti-alias + gap bookkeeping); the band ends at 2.5 Hz so 25 Hz is ample, and it matches the watch's rate so the two implementations can be compared sample-for-sample |
| `pumpFilterSpan` | 2 | s | FIR length (Hamming-windowed sinc difference) = two full slow cycles |
| `pumpStrokeAmp` | 0.25 | g | band-passed peak height that counts as a stroke |
| `pumpRefractory` | 0.4 | s | dead time after a stroke (a human cannot pump at >2.5 Hz) |
| `pumpStrokeMaxInterval` | 1.5 | s | strokes closer than this belong to the same burst |
| `pumpMinStrokes` | 4 | | burst length that means "the rider was pumping" |
| `pumpBurstPeakG` | 0.8 | g | **PROVISIONAL** — a burst's tallest stroke must reach this for the burst to be *counted*: the session total (engine ≥ 0.8.0) and `inFlightStrokes` (engine ≥ 0.8.1). The corroborating metrics never read it |
| `pumpMinSpeedKmh` | 3.0 | km/h | speed at a stroke below which it is a swim stroke, not a pump. Session total only (engine ≥ 0.8.0) |

The stream is orientation-free by construction (magnitude, not axes — the wrist rotates
constantly through a jibe). Empty grid bins are held at the session mean so the FIR does not
ring on sensor dropouts and are then discarded, so a SensorLogging gap contributes no
strokes rather than a burst of edge artifacts.

`pumpMinStrokes` sits in a wide gap, not on a knife edge: on 2026-08-07 the longest burst
inside a turn's outcome window is ≤2 for every jibe the speed channels called successful except
the two pump-outs, which score 6 and 7, and the verdict is unchanged at `pumpStrokeAmp`
0.20–0.30 g. Garmin writes `calibrated_accel_*` in milli-g although the FIT profile names
the unit "g"; the parser sniffs the scale from the resting magnitude rather than assuming.

### Reading the stream — `accelerometer_data`, and the devices that give it no clock

`parse.py` · `FitImport/FitAccelReader.swift`. One message per ~25 samples: `timestamp` +
`timestamp_ms` give the batch's base second and `sample_time_offset` (ms) times each sample
inside it. The frame is returned on the *records'* time base, because it is two orders of
magnitude longer than the 1 Hz record frame and belongs to a different clock.

**Not every device gives that stream a clock** (engine ≥ 0.23.0, ADR-030). A tester's
fenix 5 Plus writes one batch after each 1 Hz record and stamps every one of them with a
handful of constant `timestamp`s *days* either side of the session, with
`sample_time_offset` flat at zero — 4 312 batches × 25 samples, in file order. Read
literally that is a stream fifty days long starting before the ride: the lab produced
`t = −138 457 s` and NaNs and the pump resampler died on `int(floor(nan))`; the kit, whose
grid is bounded, silently returned no pump channel at all.

**The clock is condemned by either of two tests**, and then rebuilt from file order:

| test | what it catches |
|---|---|
| fewer than half the batch bases fall inside the records' own span (±1 s) | a device reusing stale `timestamp`s. Our own recordings pass it outright — 2 580 of 2 580 and 16 588 of 16 588 on the two corpus fixtures that carry the channel |
| no batch of two or more samples has any spread in its `sample_time_offset` | twenty-five samples at offset 0 are twenty-five samples with one time, which is not a time |

Rebuilt, **a batch starts at the last `record` seen before it and lasts one second**, its
`n` samples spread evenly across it (sample `i` at `i/n` s). It is monotonic: several
batches written after the same record queue up behind it rather than landing on one instant.
The result is good to **±1 s against GPS**, which is ample for a 0.5–2.5 Hz band and not
ample for aligning a sample with a wave — so the fact is recorded rather than hidden:
`capabilities.accelClockReconstructed`, in the document and in `SourceCapabilities`, is
**false on every fixture in the corpus** and true only where the engine had to do this.

**And the pump grid trusts none of it.** Its length comes out of a file, so a non-finite time
or magnitude is dropped, an unsorted stream is sorted, and a grid longer than four hours of
25 Hz samples (`MAX_PUMP_BINS` / `PumpAnalyzer.maxBins`) is refused. The answer is `nil` —
the same state a source with no accelerometer is already in — so every consumer degrades the
way it always has instead of through a second code path.

### The second source of the same channel — the direct transfer's stream 1 (dev)

A Garmin session that arrives over the Connect IQ link rather than as a FIT carries the same
magnitudes in a second stream, `wrist.v1` (docs/transfer-format.md §2b, ADR-031). Three
things about it, and none of them is a new rule:

* **It is already the 25 Hz grid.** The watch feeds it from `PumpDetector._pushGrid`, the one
  point every grid sample of its own band-pass passes — same decimation, same milli-g sniff.
  So `PumpAnalyzer` bins a stream that was already binned, and `resampleHz` stays 25 because
  the source is 25.
* **It carries real per-sample times**, off that grid and anchored to each 1 Hz fix. Nothing
  is reconstructed from file order, so `accelClockReconstructed` is **false** — the state
  every corpus fixture is in.
* **It covers only the stretches the watch flagged**, because two hours at 25 Hz fits the
  memory of no watch in the manifest. Every second between two windows is **an empty bin**:
  held at the mean so the FIR does not ring, `valid` false, no stroke picked there — which is
  exactly what a `SensorLogging` hole already is. No consumer is told anything new, and a
  windowed stream and a gappy FIT degrade through the same single path.

What it does **not** reach is *Jumps* below: that estimator wants 100 Hz and collapses at 25
(`s = 0.7`: 0–6 % detection), and 25 Hz is all the watch's own listener has. A wrist stream
over this link will never feed a jump height; ADR-031 says what would.

### The session total — `summary.takeoff.totalPumpStrokes` (engine ≥ 0.8.0)

The last two rows exist for **one** metric, and the reason is worth writing down. Every other
pump number in the engine is gated by `pumpMinStrokes`; the session total was not, so it
reported the raw output of the peak picker — which, given the table above, is mostly chop.
On the bundled 2026-08-30 example it read **286** against a hand count of about **26**: 213
of those 286 were logged *in flight* at ~20 km/h, and 196 of them were singletons or pairs.

A counted stroke must now pass all three tests:

1. **in a burst** of at least `pumpMinStrokes` — the engine's own definition of pumping
   (286 → 90 on the example);
2. **its burst is tall enough**: the burst's *maximum* band-passed peak reaches
   `pumpBurstPeakG`. Per burst, not per stroke — a rider's fourth pump is smaller than his
   first and belongs to the same effort (90 → 31);
3. **it moved the board**: speed at the stroke is at least `pumpMinSpeedKmh`, which is what
   keeps a swimmer's arms out of the tally (31 → 31 here; −36 and −6 on the two longer
   sessions).

`pumpBurstPeakG` is marked **PROVISIONAL** deliberately. On 2026-08-30 the sixteen qualifying
bursts peak at 0.35–0.64 g (thirteen of them), then 0.73, 0.86, 1.41, 1.45 — 0.8 g lands
*between* 0.73 and 0.86, not in a wide gap, and no session in the corpus carries a logged
stroke count to check it against. The on-water protocol now asks for one
(`fixtures/README.md`); the day it exists, this is the number to re-tune.

### In-flight strokes — `takeoffs[].inFlightStrokes` (engine ≥ 0.8.1)

`inFlightStrokes` counts pumping *during* a flight: working the foil to hold or extend a
glide. As shipped in 0.8.0 it applied the burst-length rule alone, which left the bundled
2026-08-30 example reporting a session total of **31** beside an in-flight **60** — a part
larger than its whole, and on a panel that stacks the two labels it reads as an arithmetic
error. It is also the count the chop hurts most, because the wrist is on foil for the whole
window by definition.

Engine 0.8.1 gives it the **same two burst-level tests** the session total applies: a burst
of at least `pumpMinStrokes` whose tallest band-passed peak reaches `pumpBurstPeakG`. The
total is a superset of it again, and provably so — restricting a burst to a flight window can
only drop strokes, so a sub-burst that passes both tests sits inside a session burst that
passes them too, and every stroke on foil clears `pumpMinSpeedKmh` besides.

It does **not** take the total's third test, `pumpMinSpeedKmh`: the window is a flight, so
every stroke in it is already far above 3 km/h. The gate could never fire, and one that
cannot fire reads as though it might.

On the corpus: **60 → 5** (2026-08-30), 293 → 127 (2026-08-07), 430 → 153 (2026-08-29). The
bursts are re-formed inside each flight window, as they always have been, so the number is
not the same as "session-qualifying strokes that happen to fall in a flight" (9 / 139 / 201
on those three) — a burst straddling a flight boundary is judged on the part inside it.

**Nothing else moves.** Peak picking, `pumps_to_takeoff`, `avgPumpsToTakeoff`,
`takeoffs[].pumps`, `pumpEpisodes` and `is_pumping` — the corroboration the turn and
flight-end ladders read — are all untouched. Those ask *was he working here*, a question a
short or gentle burst still answers truthfully, and plumbing the amplitude rule into
`is_pumping` drops real, speed-corroborated pump-outs from the turn outcomes. An in-flight
*episode* is therefore still detected and still classified `in_flight` when the pumping is
gentle; only its stroke tally is now zero.

### Turn outcome (primary, rider-facing) — `flew_through` · `touchdown` · `fell_in`

Score%/success stay as the *secondary*, continuous metric: outcome says what happened,
score says what the turn cost. Every turn gets an outcome, bear-aways included — and since
engine 0.21.0 this ladder is also what *decides whether a sweep is a turn at all* in one case:
an **aborted turn** is kept only where the ladder below says `fell_in` ("The aborted turn").

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
   a sample that far below the line the altimeter had settled on is *proof* the rider was in
   the water: it is never flying, and its presence in the window makes the turn `fell_in`
   outright, whatever the stop measured. Positive-only evidence — on 2026-08-07 exactly 3 of
   18 falls dunked the wrist (−236 m, −105 m, −347 m; the deepest reading on any other turn
   is −9 m, so the threshold has two orders of magnitude of margin), and the silence of the
   other 15 means nothing. Sources without a barometer just skip it.

   **The line is local and causal, not the session's median** (engine ≥ 0.22.0, ADR-029).
   A **baseline** starts at the first finite altitude sample, **restarts** at every sample a
   recording gap precedes, and otherwise walks towards each dry sample with a time constant
   of `BARO_TAU_S` = **50 s**. A sample is wet when it sits `turnBaroDrop` below *that* line.
   While a sample reads wet the baseline **holds** — a swim must not be able to re-baseline
   itself dry — with one release: when the last `BARO_SETTLE_S` = **20 s** of samples (no gap
   inside, all finite) are within `BARO_SETTLE_M` = **±5 m** of this one, the level is
   accepted as the new baseline and the sample is dry. *A dunk is a spike; a level is not a
   dunk.* The three numbers are **code constants, not tuning parameters** (like
   `CLEAN_QUIET_OFF_FOIL_S`): they describe the altimeter, not the riding.

   The median modelled one watch. Jan's fenix 8 drops ~250 m on a dunk and crawls back to the
   *same* level, so one line for the afternoon fitted it. **A tester's fenix 5X Plus, 20 Sep
   2026, dunks the same way and then re-anchors**: −65/−34/−73 m in three consecutive seconds
   at 12 km/h, exactly at his falls, and afterwards a *new* reference. That session's baseline
   sat at −30, −93, −30, +150, +130, +105, +73, +24, −60, −75 and −190 m in successive
   stretches — 370 m of wander at sea level — and against a fixed median of −33 m every
   stretch below −58 m read "wrist under": 43 of 85 turns flagged wet and 33 of 70 jibes
   "fell in" while their flights ran straight on through, seven of them jibes the rider had
   named as smooth. With the local line, 11 turns flag, 6 jibes fall in, the seven flew
   through, and three flight ends the median had *missed* — dunks from a +150 m stretch — are
   read as falls. The watch's own live test already worked this way in the pressure domain
   ("Watch divergences"), so this also ends a disagreement between the wrist and the phone.

   **On the corpus** the change is confined to the barometer's own evidence. No ciq or
   windsurf-native fixture moves by a single verdict; `other-apps/2026-08-05-…_foilmotion.fit`
   moves two turns and nothing else moves at all — the jibe at `ts` 3852 goes `fell_in` →
   `touchdown` (its window's wet samples were a re-anchor, and the stop is what is left), and
   the **aborted** turn at `ts` 7907 stops being a turn, because an aborted sweep is kept only
   where the ladder calls it a fall. A naive index-by-index diff of that fixture's turn list
   shows four moves; three of them are the list closing up behind the turn that left it.
   Across all 19 goldens: counted turns 569 → 568, jibes 565 → 564, turn `fell_in` 50 → 48,
   turn `touchdown` 208 → 209, **clean jibes 161 → 161**, straight-line falls 44 → 44 and no
   rate numerator moved except the one the freed jibe added. Submersion *episodes* fall
   95 → 37 over the same corpus, which is the re-anchored stretches leaving the map.
3. **Did he have to pump it out? (accelerometer — class (a) only, corroborating)** Pump
   strokes per *Pumping (accelerometer)* below. The rider pumps a wing for many reasons, so
   this never decides an outcome alone: a pump burst turns a fly-through into a `touchdown`
   only when the speed channels *also* saw the foil go marginal — below
   **`turnPumpedMarginalSpeed`** (engine ≥ 0.18.0; it was hard-wired to `foilEntrySpeed` until
   0.17.0) — somewhere in the same window, and only while `turnPumpedOutIsTouchdown` is set.
   Speed says the foil stopped carrying, accel says he had to pump it back; either alone is not
   enough. It can only ever promote `flew_through` → `touchdown`, never touch a fall.

   **This rung is retired at the published defaults, and step 3 no longer fires.** The
   corroborating speed used to be `foilEntrySpeed`, 12 km/h — the speed at which a *flight
   starts*. That is the wrong question: the speed below which the foil stops carrying is the
   exit speed, 8 km/h, and Jan put it plainly on 7 Sep 2026 — *"change to '…below min foil
   speed…'"*. His **Jibe 50** of 4 Sep 07:58 sagged to 5.5 kn = 10.2 km/h, below entry and
   comfortably above exit, and was called a touchdown by this rung alone — no off-foil sample,
   no stop, no wrist under. He flew it. Working the wing through a soft patch is riding.

   At `turnPumpedMarginalSpeed`'s default of **8.0** the rung is **unreachable by
   construction**, and that is the point rather than an accident: step 1 defines *flying* as in
   a flight, not submerged, and above `foilExitSpeed`, so on the only branch step 3 lives on —
   no non-flying sample anywhere in the window — every sample is already above 8 km/h. The band
   step 3 judges is `(foilExitSpeed, turnPumpedMarginalSpeed]`, and at the default that band is
   empty.

   **It is a parameter rather than a reference to `foilExitSpeed`, so the retirement is a
   setting somebody can disagree with.** Raise it and the rule comes back over the band it
   opens; at **12.0** it is exactly the 0.17.0 reading, restored — which is what
   `test_jibe_50_flew_through_and_the_old_speed_takes_it_back` asserts, in both directions, on
   the recording the change came from. `turnPumpedOutIsTouchdown` sits beside it as the gate,
   kept **on**, because the two answer different questions: the switch is whether the rung is
   asked at all, the speed is what it asks. Either way `pumped` is still set, the "pumped out ·
   N strokes" chip still prints, and a stored document from an older engine still decodes its
   verdict.

   Over the 21-session corpus the rung was the sole reason for **13 of 270 jibe touchdowns**
   (3 of which held their speed): jibes 493 → 506 flew through, 270 → 257 touched down, 55 fell
   in unchanged, and clean jibes 263 → 266. The watch never had the rung, so at these defaults the two agree — see
   *Watch divergences*.
4. **Stopped how long?** The off-foil run is followed until foiling resumes (capped by
   `turnOutcomeWindow`) and the longest contiguous spell below `turnStopSpeedFloor` is
   measured, on `min(Doppler, positional)`. Both channels *over*-read at rest — wrist
   Doppler picks up swim strokes, positional picks up GPS jitter — and neither under-reads,
   so the lower of the two is the better stop evidence, and using both bridges single-sample
   dropouts in either. An interval counts only when both end samples are below the floor and
   no recording gap separates them, the same "hold" convention flight segmentation uses.
5. Spell > `turnFallStop` ⇒ `fell_in`; otherwise `touchdown`, flagged `borderline` when the
   spell exceeds `turnTouchdownMaxStop`.

### Why — `turn.outcomeReason` (engine ≥ 0.18.0)

Jan, 7 Sep 2026: *"Can we add a short comment for the user why a jibe is a touchdown or a
fall?"* Every number was already on the page — `stoppedS`, `offFoilS`, a wrist-under chip —
and the rider was left to assemble the verdict out of them. The turn record now carries the
rung that decided it, as a **code**; the words are presentation's
(docs/presentation/turn-detail.md, "Why it ended that way"), so the engine never chooses a sentence and
the phone and the web cannot word one fact two ways.

| code | set by | means |
|---|---|---|
| `stop` | step 5 | a stop past `turnTouchdownMaxStop` (a *borderline* touchdown) or past `turnFallStop` (a fall) |
| `off_foil` | step 5 | off the foil, with no stop long enough to be worth naming — the ordinary short touch |
| `submerged` | step 2 | the wrist went under, **and that is what decided the fall**. It wins the wording wherever it fires, because step 2 is tested first and is proof of a swim on its own — even where the stop would have carried the verdict anyway |
| `pumped_marginal` | step 3 | the pump rung fired. Unreachable at the published defaults (above); present in a document written by an engine before 0.18.0, or in one analysed with `turnPumpedMarginalSpeed` raised above `foilExitSpeed` |
| **null** | — | a `flew_through`. Nothing happened, so there is nothing to explain — the fourth state, and the common one |

The invariant, asserted on every fixture by `verify_presentation.py` §6 and by `GoldenTests`:
a reason is present on exactly the touchdowns and the falls, and on nothing else.

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

### Positions-only recordings and touchdowns — what class (c) really loses

Jan, 17 September 2026: *the same session imported from intervals.icu and from Strava gives
fewer touchdowns on the Strava copy.* The hypothesis was that speed differentiated from
positions is smoothed and hides the short dips step 1 keys on. **It is not what happens**, and
the verdict that actually goes missing is the *fall*, not the touchdown.

The experiment is `lab/tools/strava_vs_icu.py`: five fixture sessions read twice, once as the
FIT (class (a)/(b)) and once as what a Strava export carries — latitude, longitude, elevation
and a clock, rounded to Strava's own 1e-6 deg and re-read through the class (c) door. The
Strava copy of 2026-08-30 14:07 was checked against the real thing through the activity-stream
API: 646 samples at a flat 1 Hz, no gaps, six decimals. Cadence and coverage are not where the
two copies differ.

| session | turns | flew through | touchdown | fell in | clean |
|---|---|---|---|---|---|
| 2026-08-07 am (ciq) | 30 → 28 | 11 → 12 | 12 → 14 | **7 → 2** | 3 → 3 |
| 2026-08-29 pm (ciq) | 56 → 54 | 42 → 43 | 8 → 7 | **6 → 4** | 25 → 26 |
| 2026-08-30 pm (ciq) | 10 → 10 | 8 → 8 | 0 → 1 | 2 → 1 | 5 → 5 |
| 2026-08-04 pm (native) | 60 → 58 | 39 → 38 | 20 → 19 | 1 → 1 | 16 → 15 |
| 2026-08-05 am (native) | 22 → 22 | 15 → 13 | 5 → 7 | 2 → 2 | 6 → 4 |
| **corpus** | **178 → 172** | 115 → 114 | **45 → 48** | **18 → 10** | 55 → 53 |

Touchdowns are a wash (45 → 48 on turns, 53 → 52 on the session split that adds the
straight-line losses); **falls drop 44 %** (18 → 10 on turns, 34 → 28 on the split). 14 of the
172 paired turns (8.1 %) get a different verdict, in both directions — 5 `fell_in` → `touchdown`,
1 `fell_in` → `flew_through`, 3 `touchdown` → `flew_through`, 5 `flew_through` → `touchdown`.
A further **6 turns of 178 are not detected at all** on the positional copy, and they are the
slowest ones (minima 1.60, 2.00, 2.17, 3.37, 3.77 kn) — four touchdowns and two falls that no
verdict is ever written for.

**The cause is step 4, not step 1, and it is the loss of the `min`.** `min(Doppler, positional)`
has no second channel to take a minimum with on class (c), because there `doppler_mps` *is* the
positional channel. Step 1's exit test barely notices: samples below `foilExitSpeed` fall by
0–4 % across the five sessions. The **stop** measure collapses: samples below
`turnStopSpeedFloor` fall by 9–23 %, because a stop interval needs both end samples below the
floor and a single jitter sample above it cuts the run in two. On the 23 turns with a stop of
at least a second, the longest stop reads **4.96 s** on `min(Doppler, positional)` and
**3.22 s** on the positional channel alone — and the positional channel alone, computed on the
*FIT's own* track, reproduces the Strava copy's stop to within 1 s on **22 of 23** turns. The
two channels' jitter is independent and the minimum bridges each one's dropouts, exactly as
step 4 claims; with one channel there is nothing to bridge, and `turnFallStop` (5 s) sits in
the middle of the 3.2 → 5.0 s gap.

Three candidate causes were tested and are **not** it: the spike filter (`max_accel_1hz = inf`
leaves every verdict unchanged), the sampling (1 Hz, gap-free, confirmed against Strava), and
position precision (7 decimals instead of 6 moves one clean-jibe count and nothing else).

**No per-class exit rule.** Nothing on the positional path restores the stop the two channels
measured together. Raising `turnStopSpeedFloor` for class (c) buys the corpus total and loses
the individual turn: at 1.4 m/s the mean stop reads 4.70 s and 9 of the 23 cross `turnFallStop`
(against 4.96 s and 10), but the mean per-turn error is still 1.30 s, and over whole sessions
it restores 2 of 5 falls on 2026-08-07, does nothing at all on 2026-08-29, and turns
2026-08-04's one fall into three. Absorbing single excursions above the floor (a 3- or 5-tap
majority on the below-mask) reaches 3.52 s and 3.87 s and closes none of it. A second channel
cannot be manufactured from the positions that produced the first one.

**So class (c) is labelled, not corrected** (docs/presentation.md, the Strava surfaces): *"Without
the watch's own speed, a fall can read as a touchdown."* It sits beside the uncertified mark the
speed records already wear, and it is the same kind of statement: a fact about the source, not a
number the engine pretends to.

Two further class (c) facts the same run measured. **The barometer is the other half of the
fall.** If the Strava copy's elevation is DEM-corrected rather than the device's own — the
`noele` variant, no `<ele>` at all — step 2 never fires and corpus falls go 18 → 5 while
touchdowns go 45 → 52. And **an uncertified record can be badly wrong, not slightly**:
2026-08-29's best 2 s reads 13.21 kn on the Doppler channel and **31.77 kn** differentiated from
the same positions, 2.4×, off one bad fix. That one is no longer reported. Unlike the fall,
the short speed record *has* a second measurement of the same motion to check itself against —
the same track's best 10 s, which ten fixes carry and one cannot move — and since engine 0.20.0
it is checked: 31.77 → 13.13 kn (docs/algorithms/records.md, "The plausibility gate"). The fall has no
such second channel, which is the difference between labelling a class and gating a number.

### Submersion episodes — `submersions` (engine ≥ 0.16.0)

The barometer's submersion mask (step 2 above) is computed over the **whole track** and has
always been read in exactly two places: inside a turn's outcome window, and inside a flight
end's. That is the right input for a *verdict* — "did the wrist go under while this maneuver
was being judged" — and the wrong shape for a *map*. A rider asking "do we see all my
wrist-under events?" (Jan, 7 Sep 2026) got four marks on an afternoon the mask fired 35
times, and each of the four sat at its turn's start rather than at the dip.

So the same mask is now also serialized as **events**: `submersions`, a list beside `turns`
and `flightEnds`, one entry per spell under water.

* **A run is a maximal contiguous true-run of the mask, within one gap-free segment.** A
  recording gap always breaks a run — the samples either side of one are not evidence about
  each other, the rule every other window in `evidence.py` obeys — so a Smart-Recording hole
  mid-dunk yields two episodes rather than one three-minute swim.
* **Runs less than `2 s` apart are merged** (`SUBMERSION_MERGE_S`, not a tunable in `config`).
  One dunk and the wave right after it are one event to the rider, and a slew-limited
  altimeter can cross the threshold twice on the way back up. On the present corpus this
  merges nothing at all — the closest two runs are 11 s apart since engine 0.22.0 (3 s
  before it), and every source but one is 1 Hz, where two runs cannot be closer than 2 s —
  so it is a guard for the 4 Hz sources rather than a correction to today's numbers.
* `durationS` is the gap-aware elapsed time from the first submerged sample to the last, the
  same clock every other span in the engine is measured on. A single-sample run is `0`.
* `dropM` is the deepest sample of the run below **the same line the mask itself crossed** —
  the local baseline in force at the run's *first wet sample* (`submerged_trace` returns the
  mask and that baseline together, so the two cannot drift). It is therefore always at least
  `turnBaroDrop`, and on the corpus it runs 26–224 m: the wrist altimeter's rendering of
  30 cm of water is a ~250 m "drop". Before engine 0.22.0 the line was the session median and
  the range read 26–343 m; the deepest readings it used to report were the distance from a
  re-anchored stretch back to the median, not the depth of any dunk.
* **Attribution, first match wins**, in this order: a *counted* turn whose outcome window
  (`ts` → `endTs + outcomeWindowS`) the run overlaps ⇒ `turnIndex`; failing that a *drawn*
  flight end (no turn owns it, the recording did not stop) whose window (`ts` → `ts +
  windowS`) it overlaps ⇒ `flightEndIndex`; failing that neither, which means the rider was
  already off the foil when he went under. That is a real answer and the map says it
  ("while off foil"), not a missing one. The windows are rebuilt from what each record
  already carries, so an episode is never attributed to a window a verdict was not read from.
* **The verdict flags do not move.** `turns[].submerged` and `flightEnds[].submerged` are the
  outcome ladder's inputs and are computed exactly as before, from the same mask at the same
  threshold. The episodes are presentation evidence laid over them, and the relationship is
  one-way: every flagged turn or end has at least one episode overlapping its window, while
  an episode need not belong to any: over the committed goldens 14 of 38 do not, and that
  ratio is itself a reading of engine 0.22.0 — it was 72 of 97 while the reference was the
  session median, because a re-anchored stretch belongs to no maneuver at all.
* **A source with no barometer gets an empty list.** Nothing is invented from GPS altitude:
  the episodes are the mask's runs and the mask is all-false without a finite altitude
  channel, and flat below `turnBaroDrop` of variation. Of the nineteen fixtures, **fourteen**
  have no episodes at all since engine 0.22.0 — four more than before, because a channel that
  merely *steps* is now a new baseline rather than an afternoon under water. The one converted GPX is the interesting case — it carries the FIT's own
  `<ele>`, so it reproduces that session's single episode to the metre, which is the same
  parity every other channel on that pair shows.

**The watch computes none of this.** Its swim detection was withdrawn in 0.9.2 (drift reads
as swim) and `garmin/` has no submersion channel at all; the episodes are a phone/web
analysis of a recorded barometer trace, and nothing in this section has a live approximation.

### Turn streaks — `longestDryStreak` · `longestFlewStreak`

A tally says how the session went; a streak says how it *felt*. That makes a streak a claim
about **the rider**, not about the turn channel — so it cannot be read from turn outcomes
alone. A swim in a straight line ends a run of clean jibes exactly as a botched jibe does,
and the rider remembers it that way.

**One merged event list**, in time order, from both outcome channels:

* every **counted turn**, at its `endTs`, carrying its turn outcome; plus
* every **flight end that no counted turn owns** — straight-line ends, and ends owned by a
  rejected sweep — at its `ts`, carrying its flight-end outcome.

A flight end a counted turn *does* own is excluded: that turn's own outcome already speaks
for it (docs "Flight-end outcome" → **Ownership**), and counting both would charge one swim
twice. Truncated ends are dropped outright — the recording stopped, which is not evidence
that anything happened to the rider.

Only a counted turn can *lengthen* a run. A non-turn event can only cut one short:

| event | `longestDryStreak` | `longestFlewStreak` |
| --- | --- | --- |
| counted turn, `flew_through` | +1 | +1 |
| counted turn, `touchdown` (incl. `borderline`) | +1 | reset |
| counted turn, `fell_in` | reset | reset |
| non-turn end, `fell_in` | reset | reset |
| non-turn end, `touchdown` | — | reset |
| non-turn end, `glide_out` / `unknown` / truncated | — | — |

Dry counts *staying out of the water*, so a touchdown pumped straight back out never ends
it, from either channel. Flew is the strict run: every maneuver carried clean, and any wet
event anywhere resets it. `longestFlewStreak ≤ longestDryStreak` always, both are `0` with
no counted turns, and at an identical timestamp the non-turn event is applied first — the
conservative reading, though the ownership window makes that tie unreachable in practice.

**Rejected sweeps are still not maneuvers**, but their *consequences* are. A bear-away
neither extends nor breaks a streak as a turn — it is not something the rider attempted, and
counting it either way would make a streak depend on how much he bore away between jibes. A
fall that a bear-away owns is a different matter entirely: he swam. It enters as a non-turn
event, which is exactly how the flight-end channel already reports it.

That distinction is what the first cut of this metric got wrong, and the corpus says so
loudly. On 2026-08-29 the turn-only rule read **12 dry / 10 flew**; the merged rule reads
**11 / 5**. The 10-run was never real — it spans a fall inside a bear-away at 3551 s (flight
end owned by turn 33, `bear_away`) and a straight-line fall at 3790 s, two swims the turn
channel cannot see because neither happened in a counted turn. The scale of the blind spot
is the reason: that session has **25 falls, and only 8 of them are in a counted turn**. The
other 17 arrive as non-turn events — 13 straight-line, 4 owned by bear-aways — alongside one
straight-line touchdown, 18 events in all. Read through the turn channel alone a streak
misses two thirds of the session's swims, which is precisely how a run of 10 survived two of
them. 2026-08-07 moves **5 / 2 → 6 / 2** on the same rule.

The two numbers still say what the tallies cannot. 2026-08-29 (51 counted turns, 35 flew /
12 touchdown / 4 fell) reads 11 / 5; 2026-08-07 (30 counted, 9 / 14 / 7) reads 6 / 2. The
first rider strung his good turns together and the second did not, and that is the whole
point of carrying the streaks beside the counts.

**On the watch, live** (device app ≥ 0.8.0). `WingFoilCore.TurnDetector` carries
`dryStreak`/`bestDryStreak` and `flewStreak`/`bestFlewStreak`; the current dry run and the
session best are the bottom row of the main screen, and the best is on the post-save Turns
page. Counted turns move them in `_resolve()`, the one place a turn outcome is decided — so a
rejected sweep increments nothing by construction, since `KIND_REJECT` returns before the
outcome window ever opens.

The **non-turn channel** is the half the watch has to approximate, because it has no
flight-end classifier of its own. `_flightEndTick` is a small one: on the flying→not-flying
edge, *and only while the turn state machine is idle*, it opens a `turnLookahead`-long window
and collects the same evidence `_track` collects for a turn — barometric submersion, and the
longest spell below `turnStopSpeedFloor` on the same both-ends-qualify clock — then applies
the table above's non-turn rows. It touches nothing else: no counter, no event, no FIT marker.
A GPS gap closes the window unjudged rather than calling it a fall, on the same principle that
drops an unjudgeable takeoff effort. Falls owned by a bear-away arrive through this path
too — a rejected sweep leaves the state machine idle, so the swim after one is an unowned
flight end, which is exactly the classification the merged rule wants.

Two drifts from the engine, both in the conservative direction and both from having only live
evidence:

- **ownership** is "is a turn window open right now" rather than the engine's retrospective
  `ownedByTurn`, so a fall a few seconds after a turn has already resolved reads as
  straight-line on the watch and as turn-owned on the phone. The streak effect is identical;
  only the attribution differs.
- an end whose evidence only arrives after the window closes — a very slow sink — is a
  glide-out to the watch. The phone, seeing the whole track, calls it what it was.

The phone remains authoritative and recomputes both numbers on import.
`garmin/barrel/WingFoilCore/tests/CoreTests.mc` asserts the watch rules:
`turnStreaksFollowTheOutcomeLadder`, `rejectedSweepsAreInvisibleToStreaks`,
`straightLineFallsBreakTheStreaks`, `aFallBetweenTwoFlewTurnsResetsBothStreaks` and
`anUnjudgeableFlightEndDoesNotBreakAStreak`.


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
- **`unknown` is not pedantry.** Before engine 0.23.0, 2026-08-04 pm segmented into 429
  gap-free runs and 111 of its 130 "flights" ended at a segment boundary with the rider still
  doing 4–5 m/s. Classified on visible evidence they all read `glide_out`, and the session
  would have claimed 111 straight-line glide-outs that never happened. Since 0.23.0 a Smart
  Recording cadence is no longer a boundary ("A cadence is not a hole"), and the same session
  has 40 flights of which **3** end unknown — so the rung now does what it was built for, a
  rare honest silence, instead of absorbing an artifact. Class-(a) CIQ recording is a steady
  1 Hz and is unchanged at 2 of 23.

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

