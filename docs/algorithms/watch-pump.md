> Part of `docs/algorithms.md`. Engine 0.23.0.

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
*Takeoff analysis* already stated. The one constant with no lab counterpart is
`ATTEMPT_JOIN_GRACE_MS` (6.5 s), which exists because the watch has to decide *now* whether an
effort is over while the burst that would join it is still forming — row 5a below.

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
| 5a | two bursts are one episode when `first - prev_end < takeoffAttemptWindow` — measured to the next burst's **first** stroke | identical, live: the merge test reads `_burstStartMs`, and `_expire` will not declare an effort failed while a burst that began inside the window is younger than `ATTEMPT_JOIN_GRACE_MS` (6.5 s = the 4.5 s a legal `pumpMinStrokes` burst may take to form + the 1 s FIR group delay + the 1 Hz tick its last stroke arrives in) | without both halves the 10 s silence expires *between* a joining burst's first and fourth stroke, and one long bout is counted as several attempts — see below |
| 6 | `ON_FOIL` is the exact flight boundary | the `STATE_OFF→STATE_ON` transition, backdated by `entryHoldS` | that is the instant the FlightDetector backdates its own accounting to |
| 7 | success = a flight starts inside the window | the flight must also be **confirmed** (`minFlight`, up to 5 s later); an effort whose window expires while the rider is ON foil is held pending until the flight is confirmed or collapses | nothing shorter than `minFlight` counts as a flight anywhere else either |
| 8 | `unknown` episodes are excluded from every tally | a GPS gap drops the open effort silently | identical outcome, same reason |
| 9 | `pumps_to_takeoff` = strokes in the run (speed rise ∪ lead burst) | strokes in the effort's **lead burst** alone | the watch has no walk-back over past speed, but it can hold the current burst apart from the rest of the effort — and must, now that an effort may span half a minute of thrashing (row 5a). A takeoff with no qualifying burst reports 0 = free takeoff, which is what the lab reports when the run holds no strokes |
| 10 | `takeoff_successes` = flights · `takeoff_attempts` = flights + failed efforts | identical, counted live | — |
| 11 | the **session total**'s three tests, applied to the whole burst after the fact | the same three, applied as the burst forms: `MIN_STROKES`, a running maximum against `BURST_PEAK_G`, and `MIN_SPEED_KMH` read from the last 1 Hz tick. A burst is credited *retroactively* the moment it first qualifies — its earlier strokes included — and per stroke after that | a completed burst therefore contributes exactly what the lab gives it. Two live-only deviations: the speed is up to 1 s stale (the lab interpolates the Doppler channel at the stroke's own instant), and a GPS gap leaves the last speed standing rather than interpolating across it. **No unit conversion is involved** — `_y1` is the output of the identical 51-tap band-pass over |a| already normalised to g, so `pumpBurstPeakG` crosses over as `BURST_PEAK_G = 0.8` unchanged |

The raw peak train is still counted, as `PumpDetector.peaks` — a diagnostic, and what
`strokes` meant before device app 0.8.0's engine. It is not written to the FIT.

**The watch has no in-flight stroke metric** and engine 0.8.1 therefore does not touch it.
`PumpDetector.inFlightStrokes` is a second diagnostic — peaks that arrived while `_flying` —
read by no page, no FIT field and no summary; the phone's `inFlightStrokes` is a different
quantity (bursts re-formed inside each flight window, then gated), and the watch never forms
those windows because it cannot see a flight's end until it has happened.

Expected drift: the watch counts **slightly more** attempts than the phone — it cannot merge a
bout across a burst it did not resolve the same way, and it has no walk-back — and its stroke
total should sit within a few percent of the phone's. Anything larger is the divergence check's
business (below) — filed against the session fixture, since a tuning difference is not a bug.

**Until the next watch release ships, installed watches disagree with the phone about
`total_pump_strokes`** — they write the old raw peak count into FIT session field 38 while the
phone reports the gated one. The divergence banner will say so on every class-(a) import from
an un-updated watch; that is expected, not a regression, and it ends with the release that
carries this detector.

Row 5a is measured, not asserted. `lab/tools/watch_pump_replica.py` (a tuning harness, not
engine code) replays this detector offline against a fixture FIT and is calibrated against the
watch's own `takeoff_pack`: on 2026-08-29 the watch recorded 86 attempts / 31 successes / 14.7
avg pumps and the replica reproduces 83 / 31 / 15.0. Before row 5a the replica fragmented ten
of the phone's 69 episodes into extra failed attempts; with it, three. Replica vs the phone's
authoritative count, on the two `ciq` fixtures:

| fixture | before | after | phone |
|---|---|---|---|
| 2026-08-07 | 41 attempts / 23 / 11.6 pumps | 40 / 23 / 9.9 | 37 / 23 / 9.0 |
| 2026-08-29 | 83 attempts / 31 / 15.0 pumps | 75 / 31 / 12.0 | 69 / 31 / 10.3 |

Successes are exact by construction (every confirmed flight is one). The residual is not
segmentation: it is three qualifying 4-stroke bursts per session that the causal filter finds
and the zero-phase one does not, plus three merges the watch's own stroke train cannot see.
Buying those back needs a merge window of 16–20 s, which trades three real boundaries away for
six wrong merges — a better number for a worse rule, so it was not taken.

Phone metrics beyond the watch's: time-to-takeoff, HR cost (HR rise over attempt +30 s, only
over valid HR spans — see *HR cost* below), in-flight pump episodes (v2).

