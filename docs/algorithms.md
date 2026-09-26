# Canonical Algorithm Parameters (contract)

Single source of truth for detection/metric parameters. Three implementations follow this table:
`lab/src/wingfoil_lab/*` (tuning ground), `ios/WingFoilKit/Sources/AnalysisEngine/*`
(authoritative), `garmin/source/{detectors,metrics}/*` (live approximation). Defaults get
re-tuned in lab notebooks against the labeled fixture corpus; changed defaults are updated HERE
first, with the tuning notebook referenced in the commit.

`ENGINE_VERSION`: **0.25.0** (bump on any change that alters outputs; triggers phone re-analysis)

This file is an index. Every threshold, clock and verdict lives in the topic files under
`docs/algorithms/`; each one carries a one-line header naming this file and the engine
version it is stamped for.

## Topics

- [`algorithms/disciplines.md`](algorithms/disciplines.md) — one engine, three rigs: how a
  discipline preset changes which numbers apply, never a stage of the engine itself.
- [`algorithms/flight.md`](algorithms/flight.md) — the hysteresis state machine that decides
  flying vs not, and its three clocks.
- [`algorithms/hygiene.md`](algorithms/hygiene.md) — speed sample hygiene on the phone; the
  watch uses its quality gate only.
- [`algorithms/imports.md`](algorithms/imports.md) — recordings the importer refuses, and the
  GPX, TCX and Strava import classes, and the dedupe key: one afternoon, one session.
- [`algorithms/records.md`](algorithms/records.md) — speed records, the GP3S set and the
  plausibility gate for an uncertified short window.
- [`algorithms/turns.md`](algorithms/turns.md) — turn detection & classification: the
  glossary, the aborted turn, 360 spins, the watch approximation.
- [`algorithms/pumping.md`](algorithms/pumping.md) — pumping (accelerometer): the stream,
  session and in-flight stroke counts, turn outcome, submersions.
- [`algorithms/not-a-session.md`](algorithms/not-a-session.md) — when a recording is not a
  session at all.
- [`algorithms/rates.md`](algorithms/rates.md) — session rates: duration, average speed,
  turns/jibes/clean-jibes/wet per hour, window rates.
- [`algorithms/wind.md`](algorithms/wind.md) — wind axis estimation on the phone.
- [`algorithms/watch-pump.md`](algorithms/watch-pump.md) — pump / takeoff detection live, on
  the watch.
- [`algorithms/takeoff.md`](algorithms/takeoff.md) — takeoff analysis on the phone: pumps-to-
  takeoff, attempts, in-flight pumping.
- [`algorithms/hr-cost.md`](algorithms/hr-cost.md) — HR cost: what an attempt costs in
  heartbeats.
- [`algorithms/divergence.md`](algorithms/divergence.md) — the divergence check, for source
  class (a) recordings only.
- [`algorithms/jumps.md`](algorithms/jumps.md) — jumps: theoretical, uncalibrated.
