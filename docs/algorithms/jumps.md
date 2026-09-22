> Part of `docs/algorithms.md`. Engine 0.23.0.

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
