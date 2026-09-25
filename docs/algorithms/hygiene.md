> Part of `docs/algorithms.md`. Engine 0.25.0.

## Speed sample hygiene (phone; watch uses quality gate only)

| param | default | notes |
|---|---|---|
| `maxHdop` | 5.0 | GP3S standard (when channel present) |
| `minSatellites` | 5 | when present |
| `maxAccel1Hz` | 4.0 m/s² | spike filter (Logiqx 1 Hz value), measured against the last good sample |
| `spikeMaxDtS` | 3 s | the spike rule's budget stops growing here (engine ≥ 0.23.0). `maxAccel1Hz` is a **1 Hz** value, and `\|dv\| ≤ maxAccel1Hz × dt` stretches it: over a 7 s Smart Recording step it permits 28 m/s, which is what a receiver emits when it reacquires after a hole. Until 0.23.0 no step that long was judged here at all — anything past the 4 s threshold started a new segment and was accepted unconditionally — so raising the threshold without this cap would hand those samples to the speed records. At 1 Hz no step inside a segment reaches three seconds, so **no committed golden moves for it** |
| `gapMinS` · `gapFactor` · `smartGapS` · `smartMedianDtS` | 3 s · 2 · **10 s** · **1.5 s** | the hard-gap rule: **gap iff dt > max(`gapMinS`, `gapFactor` × median dt, and `smartGapS` when the median dt is above `smartMedianDtS`)**. The third term is engine ≥ 0.23.0 — see "A cadence is not a hole" below. `smartGapS` = 0 switches it off |
| `gapInterpolateMax` | 2 s | linear-interpolate gaps ≤ this; longer ⇒ hard segment break |
| `speedChannelRecords` | doppler | FIT `speed`/`enhanced_speed` (device Doppler) for all speed records |
| `speedChannelManeuvers` | hybrid | positional speed (local-meter projection) for turn minima — Doppler is ~3–4 s smoothed |
| watch gate | `Position.Quality ≥ USABLE` | below ⇒ sample not fed to detectors/records; timers freeze; FIT keeps raw |
| `odoMaxStep` | 3 × Doppler distance + 10 m/s × dt | watch odometer guard, see below |
| `maxSpeedMps` | 40.0 m/s (144 km/h) | watch plausibility band; outright sailing record is 33.7 m/s |

### A cadence is not a hole (engine ≥ 0.23.0, ADR-030)

Garmin **Smart Recording** writes a sample when the track changes, not on a clock: 1–9 s
apart, median 2 s. Under `max(gapMinS, gapFactor × median)` alone the threshold on such a
track is **4 s**, which sits inside the recorder's own normal spacing — so a native
afternoon was cut into 124–497 gap-free segments, and a segment boundary is a hard break
everywhere downstream. The cost was not subtle: **session distance** (the per-segment
Doppler trapezoid) ran 11–27 % short of the file's own `total_distance` on every corpus
native, and **timer time** — the denominator of foil % and of all four per-hour rates —
lost the same fifth of the session to steady reaches the watch had simply not needed to
sample. Above `smartMedianDtS` the threshold is therefore floored at `smartGapS` = **10 s**,
the same valley `hrMaxSampleGap` already sits in (below, and for the same distribution). A
long Smart Recording step *is* a steady reach — which is precisely why the watch skipped
samples through it — so bridging it is physically sound. **A 1 Hz track never reaches the
floor** and keeps its 3 s threshold to the digit; a `gap_before` the *source* declared (a
timer stop, a GPX `<trkseg>` seam) still cuts, because that is evidence the clock does not
carry.

**What it did to the corpus.** The eleven Smart Recording fixtures (ten `…_native`, plus the
0.5 Hz `…_wingfoiling` one); FIT session totals in brackets, `0.22.0 → 0.23.0`:

| fixture | segments | distance km (FIT says) | timer s (FIT says) | foil % | flights | counted turns | clean jibes | ends unknown | ends fell in |
|---|---|---|---|---|---|---|---|---|---|
| `2026-06-13-1558` | 497 → **13** | 17.51 → **22.41** (22.58) | 4712 → **7549** (7754) | 60.1 → **44.0** | 101 → **54** | 47 → **49** | 3 → **4** | 87 → **5** | 9 → **36** |
| `2026-07-31-1451` | 177 → **15** | 11.12 → **12.47** (12.57) | 3011 → **3939** (4188) | 60.9 → **50.8** | 40 → **25** | 22 → **23** | 2 → **0** | 30 → **4** | 4 → **16** |
| `2026-08-01-0804` | 254 → **12** | 13.62 → **16.80** (16.81) | 3381 → **4782** (4953) | 69.2 → **58.2** | 81 → **37** | 46 → **47** | 17 → **14** | 72 → **6** | 2 → **20** |
| `2026-08-02-0748` | 390 → **17** | 17.91 → **21.56** (21.45) | 5423 → **7549** (7779) | 53.0 → **42.8** | 74 → **42** | 36 → **36** | 9 → **7** | 55 → **7** | 10 → **23** |
| `2026-08-03-0741` | 288 → **9** | 20.41 → **23.59** (23.36) | 5258 → **6862** (6953) | 64.8 → **55.1** | 93 → **47** | 47 → **49** | 16 → **14** | 64 → **3** | 13 → **29** |
| `2026-08-03-1440` | 355 → **7** | 12.67 → **17.54** (17.39) | 4020 → **6015** (6094) | 54.3 → **49.2** | 111 → **21** | 16 → **17** | 0 → **0** | 97 → **1** | 6 → **11** |
| `2026-08-04-0822` | 174 → **5** | 7.97 → **9.79** (9.72) | 2282 → **3286** (3336) | 66.0 → **55.6** | 48 → **22** | 27 → **27** | 4 → **3** | 40 → **1** | 4 → **13** |
| `2026-08-04-1411` | 429 → **16** | 21.97 → **26.78** (26.67) | 6498 → **8860** (9105) | 62.0 → **54.1** | 130 → **40** | 60 → **62** | 16 → **16** | 111 → **3** | 7 → **22** |
| `2026-08-05-0827` | 135 → **5** | 6.46 → **8.31** (8.36) | 1708 → **2451** (2524) | 71.1 → **63.0** | 52 → **12** | 22 → **23** | 6 → **4** | 45 → **1** | 4 → **10** |
| `2026-08-06-1359` | 124 → **5** | 9.33 → **10.66** (10.69) | 2787 → **3456** (3509) | 56.0 → **49.6** | 40 → **17** | 14 → **13** | 2 → **2** | 28 → **1** | 4 → **7** |
| `2026-08-06-0757` | 226 → **16** | 12.77 → **14.49** (14.54) | 4428 → **5638** (5852) | 49.0 → **41.9** | 55 → **29** | 32 → **32** | 6 → **5** | 39 → **5** | 6 → **14** |
| **total** | — | 151.8 → **184.4** | 43 508 → **60 387** | — | 825 → **346** | 369 → **378** | 81 → **69** | 668 → **37** | 69 → **201** |

Read it in this order:

* **Distance lands on the file's own answer.** 11–27 % short before, −0.8 % to +1.0 % after.
  Four Smart Recording sessions from a tester's fenix 5 Plus, outside the corpus, move from
  21–31 % short to within 0.4 %.
* **Timer time lands within 0.2–5.9 %** of the FIT's `total_timer_time`. The residual is the
  file's own timer running through holes the engine still cuts, which is the honest gap.
* **Foil % *falls*** — 5 to 16 points — and that is the correction, not a regression. It is
  `foilTimeS ÷ timerTimeS`, and the old denominator was missing a fifth of the session that
  the rider spent on the water; flights spanning a fake boundary were also cut short.
* **Flights collapse, 825 → 346**, because a flight never spans a gap: most of those were one
  reach reported as three.
* **Turns rise slightly, 369 → 378.** A sweep cut in half by a fake boundary reaches neither
  `turnMinAngle` nor `turnAbortMinAngle`; bridged, it is a turn. Nine appear across eleven
  sessions and none disappears except on `2026-08-06-1359`, where two short sweeps merge
  into one.
* **`unknown` flight ends nearly vanish, 668 → 37, and `fell_in` ends rise 69 → 201.** These
  are the same fact: an end at a segment boundary has no evidence after it and is flagged
  `truncated` and kept out of every tally (`flightend.py`). Judged instead of truncated, most
  of them turn out to be swims — which they always were.
* **Clean jibes fall, 81 → 69.** The quiet tail now sees the ten seconds after a sweep
  instead of running into a boundary, and a fall in that tail blocks the verdict.
* **No 1 Hz golden moves by a digit** (the three `ciq`, `foilmotion`, both TCX, the GPX, the
  synthetic): their median dt is 1 s, below `smartMedianDtS`. Their diff is the version stamp
  and the schema keys alone.
* **A best hour exists in the corpus for the first time** (`2026-08-03-1440`, 6.746 kn): an
  hour is a long time to record without a real hole, and before this no native ran one
  gap-free.

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

