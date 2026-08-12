"""HR cost of pumping: what every takeoff attempt cost in heartbeats, and how that drifts.

Contract: docs/algorithms.md "HR cost". Jan's question is simple -- *"my HR goes up when I
pump"* -- and the session data can answer four versions of it:

1. **per takeoff**: the HR rise from the start of the pumping effort to the peak reached
   within `hrCostPeakWindow`;
2. **pumping vs cruising**: mean HR while a burst is being pumped against mean HR on the foil
   with a quiet wrist;
3. **fatigue**: how the per-takeoff cost and the attempt success rate move over the session;
4. **recovery**: how long HR takes to fall halfway back after a takeoff and after a swim.

This is a *separate module* rather than more of `takeoff.py` on purpose. Takeoff analysis is
a frozen golden contract read off the speed and accelerometer channels; HR is a third channel
with entirely different failure modes, it is read from `RawTrack.records` (the cleaner drops
it -- it is not a speed channel), and it is joined to takeoffs, flight ends *and* turns. Wiring
it into the takeoff dataclasses would have made one contract answer to two sensors.

**Optical HR is not a measurement until it is proved to be one.** A wrist sensor under a
wetsuit sleeve, in cold water, on an arm that is being thrown around, drops out, sticks and
lies. Three guards, all of them per sample, decide what may be read:

``plausible``   `hrMinBpm`..`hrMaxBpm`; anything outside is sensor garbage, not a heart rate.
``not stale``   a run of *identical* bpm longer than `hrFlatlineMax`, measured inside one
                gap-free stretch, is a frozen sensor rather than a steady heart. The whole run
                is dropped, not just its tail.
``recorded``    the interval leading to the sample is not a recording gap.

Everything above is then expressed as one number per window: **coverage**, the share of the
window's seconds carried by intervals whose *both* end samples survive all three guards -- the
same both-ends-qualify convention flight segmentation and the stop measure use. A window below
`hrMinCoverage` yields `None`, never a number. Every aggregate reports `n valid / n total`
beside it, so a summary can never quietly average three takeoffs and call it a session.

**Lag is real and is not corrected away.** Optical HR trails effort by 10-20 s (physiology
plus the sensor's own smoothing), and pump bursts last 5-15 s, so a mean taken over the exact
burst seconds mostly measures the HR the rider *arrived* with. `hrLag` shifts the
pumping/cruising *classification windows* forward by that much and, for the same reason,
`hrCostPeakWindow` is 30 s rather than the burst length: the peak is looked for well past the
effort. The per-takeoff cost is deliberately *not* lag-shifted -- its baseline is read before
the effort and its peak after it, so the lag is inside the measurement rather than beside it.

**Sources without an accelerometer still get a figure.** The exact cost is anchored on the
pump burst that produced the flight; native sessions have no bursts, so the anchor falls back
to the start of the speed rise (flight segmentation alone) and the event is flagged
`approximate`. A truncated run has neither, and anchors on the flight start itself -- the HR
delta across the off-foil -> on-foil transition, which is a rough figure and says so.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from .flight import FlightResult
from .flightend import FELL_IN, FlightEnd
from .parse import RawTrack
from .pump import PumpTrack
from .takeoff import FAILED, TakeoffAnalysis
from .turns import Turn

TAKEOFF = "takeoff"
SWIM = "swim"
EVENT_KINDS = (TAKEOFF, SWIM)


@dataclass
class HrConfig:
    """docs/algorithms.md "HR cost" defaults."""

    peak_window_s: float = 30.0        # hrCostPeakWindow: peak searched this far past the anchor
    baseline_window_s: float = 10.0    # hrBaselineWindow: median of the samples before it
    min_coverage: float = 0.6          # hrMinCoverage: usable share a window needs to be read
    flatline_max_s: float = 60.0       # hrFlatlineMax: identical bpm for longer = stuck sensor
    min_bpm: float = 30.0              # hrMinBpm
    max_bpm: float = 220.0             # hrMaxBpm
    lag_s: float = 10.0                # hrLag: optical HR trails effort by this much
    recovery_window_s: float = 120.0   # hrRecoveryWindow: cap on the half-decay search
    min_rise_bpm: float = 5.0          # hrMinRise: below this there is no rise to recover from
    bin_minutes: float = 20.0          # hrBinMinutes: fatigue-curve bin width
    max_sample_gap_s: float = 10.0     # hrMaxSampleGap: longer between samples = an HR hole


@dataclass
class HrTrack:
    """The HR channel on the records' time base, with the usability mask already applied."""

    t: np.ndarray                      # sample times (whole track, gaps included)
    bpm: np.ndarray                    # heart rate, NaN where the sample is unusable
    usable: np.ndarray                 # bool: plausible, not stale (module docstring)
    gap: np.ndarray                    # bool: an HR hole precedes this sample (hrMaxSampleGap)
    config: HrConfig

    def __len__(self) -> int:
        return len(self.t)

    def coverage(self, a: float, b: float) -> float:
        """Share of [a, b] carried by intervals whose both end samples are usable."""
        span = b - a
        if span <= 0:
            return 0.0
        return min(self.recorded_s(a, b) / span, 1.0)

    def recorded_s(self, a: float, b: float) -> float:
        """Usable, gap-free seconds inside [a, b] (both-ends-qualify convention)."""
        if len(self) < 2 or b <= a:
            return 0.0
        t, ok = self.t, self.usable
        lo = np.maximum(t[:-1], a)
        hi = np.minimum(t[1:], b)
        keep = (~self.gap[1:]) & ok[:-1] & ok[1:]
        return float(np.clip(hi - lo, 0.0, None)[keep].sum())

    def values(self, a: float, b: float) -> tuple[np.ndarray, np.ndarray]:
        """(times, bpm) of the usable samples in [a, b]."""
        lo = int(np.searchsorted(self.t, a, "left"))
        hi = int(np.searchsorted(self.t, b, "right"))
        ok = self.usable[lo:hi]
        return self.t[lo:hi][ok], self.bpm[lo:hi][ok]

    def mean_bpm(self, spans: list[tuple[float, float]]) -> tuple[float | None, float, float]:
        """Time-weighted mean bpm over `spans`; also (usable seconds, total span seconds).

        Weighted by *recorded* time rather than by sample count so that a 1 Hz stretch and a
        2 s Smart-Recording stretch of the same duration count the same.
        """
        total = float(sum(max(b - a, 0.0) for a, b in spans))
        if len(self) < 2 or not spans:
            return None, 0.0, total
        t, bpm, ok = self.t, self.bpm, self.usable
        keep = (~self.gap[1:]) & ok[:-1] & ok[1:]
        mid = (bpm[:-1] + bpm[1:]) / 2.0
        w_sum = 0.0
        acc = 0.0
        for a, b in spans:
            w = np.clip(np.minimum(t[1:], b) - np.maximum(t[:-1], a), 0.0, None) * keep
            w_sum += float(w.sum())
            acc += float(np.nansum(w * np.nan_to_num(mid)))
        return (acc / w_sum if w_sum > 0 else None), w_sum, total


@dataclass
class HrEvent:
    """One anchored HR measurement: a takeoff effort or a swim, and what HR did around it."""

    kind: str                          # takeoff | swim
    index: int                         # takeoff index / flight-end index (turn index for swims
                                       #   a turn owns, see `swim_events`)
    t: float                           # the anchor: start of the effort, or the fall
    approximate: bool = False          # anchored on speed/flight evidence, not on a pump burst
    strokes: int | None = None         # pumps in the run (takeoffs, accel sources only)
    baseline_bpm: float | None = None  # median over `hrBaselineWindow` before the anchor
    peak_bpm: float | None = None      # max over `hrCostPeakWindow` after it
    cost_bpm: float | None = None      # peak - baseline; negative is reported, not clamped
    peak_lag_s: float | None = None    # anchor -> peak
    baseline_coverage: float = 0.0
    peak_coverage: float = 0.0
    recovery_half_s: float | None = None   # peak -> halfway back to baseline
    recovery_censored: bool = False    # the rise was real but the decay left the window/gap

    @property
    def valid(self) -> bool:
        return self.cost_bpm is not None


@dataclass
class Coverage:
    """`n valid / n total` for one metric -- printed beside every aggregate."""

    valid: int = 0
    total: int = 0

    @property
    def pct(self) -> float | None:
        return 100.0 * self.valid / self.total if self.total else None

    def __str__(self) -> str:
        pct = self.pct
        return f"{self.valid}/{self.total}" + (f" ({pct:.0f}%)" if pct is not None else "")


@dataclass
class PumpCruiseHr:
    """Mean HR while pumping against mean HR cruising on the foil, both `hrLag`-shifted."""

    pumping_bpm: float | None = None
    cruising_bpm: float | None = None
    delta_bpm: float | None = None
    pumping_spans: int = 0
    cruising_spans: int = 0
    pumping_covered_s: float = 0.0
    pumping_span_s: float = 0.0
    cruising_covered_s: float = 0.0
    cruising_span_s: float = 0.0

    @property
    def pumping_coverage(self) -> float | None:
        return self.pumping_covered_s / self.pumping_span_s if self.pumping_span_s else None

    @property
    def cruising_coverage(self) -> float | None:
        return self.cruising_covered_s / self.cruising_span_s if self.cruising_span_s else None


@dataclass
class FatigueBin:
    """One time slice of the session: what he attempted in it, and what it cost him."""

    start_t: float
    end_t: float
    attempts: int = 0                  # successes + failed episodes anchored in the bin
    successes: int = 0
    failed: int = 0
    success_pct: float | None = None
    avg_cost_bpm: float | None = None
    median_cost_bpm: float | None = None
    cost_coverage: Coverage = field(default_factory=Coverage)
    avg_baseline_bpm: float | None = None   # HR he *started* the attempts of this bin at
    avg_pumps: float | None = None
    mean_bpm: float | None = None      # mean HR over the whole bin (usable time only)


@dataclass
class HrSummary:
    """Session-level HR-cost metrics. Every average carries its coverage."""

    has_hr: bool = False
    usable_pct: float | None = None        # usable HR share of the recorded session
    avg_takeoff_cost_bpm: float | None = None
    median_takeoff_cost_bpm: float | None = None
    takeoff_cost_coverage: Coverage = field(default_factory=Coverage)
    approximate_takeoffs: int = 0          # of the valid ones, those not burst-anchored
    median_peak_lag_s: float | None = None
    bpm_per_stroke: float | None = None    # pooled: sum(cost) / sum(strokes)
    median_bpm_per_stroke: float | None = None   # median of the per-takeoff ratios
    bpm_per_stroke_coverage: Coverage = field(default_factory=Coverage)
    pump_cruise: PumpCruiseHr = field(default_factory=PumpCruiseHr)
    median_takeoff_recovery_s: float | None = None
    takeoff_recovery_coverage: Coverage = field(default_factory=Coverage)
    median_swim_recovery_s: float | None = None
    swim_recovery_coverage: Coverage = field(default_factory=Coverage)
    avg_swim_cost_bpm: float | None = None
    swim_cost_coverage: Coverage = field(default_factory=Coverage)


@dataclass
class HrAnalysis:
    """Everything the HR channel had to say about this session."""

    hr: HrTrack | None = None
    takeoff_events: list[HrEvent] = field(default_factory=list)
    swim_events: list[HrEvent] = field(default_factory=list)
    bins: list[FatigueBin] = field(default_factory=list)
    summary: HrSummary = field(default_factory=HrSummary)

    @property
    def has_hr(self) -> bool:
        return self.hr is not None


# --- building the channel -------------------------------------------------------------------

def hr_track(track: RawTrack, config: HrConfig | None = None) -> HrTrack | None:
    """Build an `HrTrack` from a parsed source, or None when it carries no HR channel.

    Read straight from `RawTrack.records`, not from the `CleanTrack`: HR lives in the record
    messages, and a row the cleaner dropped for a missing or spiky *fix* still carries a
    perfectly good heart rate. It also keeps its own continuity rule -- see `hrMaxSampleGap`.
    """
    cfg = config or HrConfig()
    df = track.records
    if df.empty or "t" not in df.columns or "heart_rate" not in df.columns:
        return None
    sub = df[["t", "heart_rate"]].dropna(subset=["t"]).sort_values("t")
    sub = sub[~sub["t"].duplicated(keep="first")]
    if sub.empty or not sub["heart_rate"].notna().any():
        return None
    return hr_track_from_arrays(sub["t"].to_numpy(float),
                                sub["heart_rate"].to_numpy(float), cfg)


def hr_track_from_arrays(t, bpm, config: HrConfig | None = None) -> HrTrack | None:
    """HrTrack from raw (time, bpm) samples -- unit tests and non-FIT sources.

    The continuity rule is `hrMaxSampleGap`, **not** the cleaner's dt-aware speed rule. That
    rule exists to protect speed integration and calls anything past ~4 s a gap; Garmin Smart
    Recording writes native sessions at 1-9 s and would lose most of its HR to it, for no
    reason -- HR is a slow channel and two samples 6 s apart bracket it perfectly well. A hole
    can only hide a *higher* peak than the one observed, so a windowed cost read across one is
    biased low, never high.
    """
    cfg = config or HrConfig()
    t = np.asarray(t, float)
    bpm = np.asarray(bpm, float)
    if t.size == 0:
        return None
    gap = np.zeros(t.size, dtype=bool)
    if t.size > 1:
        gap[1:] = np.diff(t) > cfg.max_sample_gap_s

    usable = np.isfinite(bpm) & (bpm >= cfg.min_bpm) & (bpm <= cfg.max_bpm)
    usable &= ~_stale_mask(t, bpm, gap, cfg.flatline_max_s)
    return HrTrack(t=t, bpm=np.where(usable, bpm, np.nan), usable=usable, gap=gap, config=cfg)


def _stale_mask(t: np.ndarray, bpm: np.ndarray, gap: np.ndarray, max_s: float) -> np.ndarray:
    """Samples inside a run of identical bpm longer than `max_s`, measured across no gap.

    A frozen optical sensor repeats its last value; a heart does too, briefly. The line is
    drawn on duration, and the *whole* run is dropped rather than its tail, because there is
    no way to tell which end of it was still the rider. Runs are cut at recording gaps: a
    session paused for eleven minutes at 90 bpm and resumed at 90 bpm is not a stuck sensor.
    """
    stale = np.zeros(t.size, dtype=bool)
    if t.size == 0:
        return stale
    same = np.zeros(t.size, dtype=bool)
    if t.size > 1:
        same[1:] = (bpm[1:] == bpm[:-1]) & ~gap[1:]
    starts = np.flatnonzero(~same)
    ends = np.append(starts[1:], t.size) - 1
    for a, b in zip(starts, ends):
        if b > a and t[b] - t[a] > max_s:
            stale[a:b + 1] = True
    return stale


# --- events ----------------------------------------------------------------------------------

def analyze_hr(track: RawTrack, flights: FlightResult, takeoffs: TakeoffAnalysis,
               flight_ends: list[FlightEnd] | None = None,
               pump: PumpTrack | None = None,
               turns: list[Turn] | None = None,
               config: HrConfig | None = None) -> HrAnalysis:
    """The whole HR-cost picture for one session (see the module docstring).

    Every argument past `takeoffs` is optional evidence: without `flight_ends`/`turns` there
    are no swim events, without `pump` the pumping/cruising split has no pumping side and the
    takeoff anchors degrade to `approximate`.
    """
    cfg = config or HrConfig()
    hr = hr_track(track, cfg)
    if hr is None:
        return HrAnalysis()
    events = takeoff_events(hr, takeoffs, cfg)
    swims = swim_events(hr, flight_ends or [], turns or [], cfg)
    bins = fatigue_curve(hr, takeoffs, events, cfg)
    return HrAnalysis(hr=hr, takeoff_events=events, swim_events=swims, bins=bins,
                      summary=summarize_hr(hr, events, swims,
                                           pump_vs_cruise(hr, pump, flights, cfg), cfg))


def takeoff_events(hr: HrTrack, takeoffs: TakeoffAnalysis,
                   config: HrConfig | None = None) -> list[HrEvent]:
    """One HR event per takeoff, anchored on the effort that produced the flight.

    The anchor is the takeoff *run* start -- the first stroke of the burst that led into the
    flight, or the start of the speed rise when it began earlier. That is the moment the work
    started, and it is the only anchor for which "the HR rise this attempt cost" means
    anything: anchoring on `ON_FOIL` would begin measuring after the pumping was over.

    `approximate` marks the two degraded anchors: no strokes in the run (no accelerometer, or
    a genuinely free takeoff -- the rise start is all there is), and a truncated run, where
    the record does not reach back over the effort at all and the anchor falls to the flight
    start, i.e. the HR delta across the off-foil -> on-foil transition alone.
    """
    cfg = config or HrConfig()
    out = []
    for i, k in enumerate(takeoffs.takeoffs):
        pumped = bool(k.pumps_to_takeoff)
        anchor = k.t if k.truncated else k.run_start_t
        ev = HrEvent(kind=TAKEOFF, index=i, t=float(anchor),
                     approximate=k.truncated or not pumped, strokes=k.pumps_to_takeoff)
        out.append(_measure(hr, ev, cfg))
    return out


def swim_events(hr: HrTrack, flight_ends: list[FlightEnd], turns: list[Turn],
                config: HrConfig | None = None) -> list[HrEvent]:
    """One HR event per swim, anchored on the moment the foil was lost.

    Swims are read off the flight ends (`fell_in`), plus any turn that fell in without a
    flight end inside its outcome window -- the same ownership rule `flightend.py` uses, so a
    jibe that ended in a swim yields exactly one event however many channels saw it.
    """
    cfg = config or HrConfig()
    ends = [e for e in flight_ends if e.outcome == FELL_IN]
    out = [_measure(hr, HrEvent(kind=SWIM, index=e.flight_index, t=float(e.t)), cfg)
           for e in ends]
    for k, turn in enumerate(turns):
        if turn.outcome != FELL_IN:
            continue
        window_end = turn.end_t + turn.outcome_window_s
        if any(turn.start_t <= e.t <= window_end for e in ends):
            continue
        out.append(_measure(hr, HrEvent(kind=SWIM, index=k, t=float(turn.end_t)), cfg))
    return sorted(out, key=lambda e: e.t)


def _measure(hr: HrTrack, ev: HrEvent, cfg: HrConfig) -> HrEvent:
    """Baseline / peak / cost / half-recovery around one anchor, or `None`s and a coverage."""
    a0, a1 = ev.t - cfg.baseline_window_s, ev.t
    p0, p1 = ev.t, ev.t + cfg.peak_window_s
    ev.baseline_coverage = hr.coverage(a0, a1)
    ev.peak_coverage = hr.coverage(p0, p1)
    _, base = hr.values(a0, a1)
    pt, peak = hr.values(p0, p1)
    if (ev.baseline_coverage < cfg.min_coverage or ev.peak_coverage < cfg.min_coverage
            or base.size == 0 or peak.size == 0):
        return ev

    ev.baseline_bpm = float(np.median(base))
    j = int(np.argmax(peak))
    ev.peak_bpm = float(peak[j])
    ev.peak_lag_s = float(pt[j] - ev.t)
    ev.cost_bpm = ev.peak_bpm - ev.baseline_bpm
    if ev.cost_bpm >= cfg.min_rise_bpm:
        ev.recovery_half_s, ev.recovery_censored = _half_recovery(
            hr, float(pt[j]), ev.peak_bpm - 0.5 * ev.cost_bpm, cfg)
    return ev


def _half_recovery(hr: HrTrack, peak_t: float, target: float,
                   cfg: HrConfig) -> tuple[float | None, bool]:
    """Seconds from the peak until HR first reaches `target`, or (None, censored).

    The search runs forward over usable samples and **stops at a recording gap**, the same
    rule the outcome windows use: a heart rate that was 120 before an eleven-minute gap and
    88 after it did not decay in that window, and reporting the gap as a fast recovery would
    be the most flattering possible lie. Running past `hrRecoveryWindow` without reaching the
    target is `censored` -- the decay is real but slower than the window, which is a fact
    about the window, not about the rider.
    """
    lo = int(np.searchsorted(hr.t, peak_t, "right"))
    for i in range(lo, len(hr)):
        if hr.gap[i] or hr.t[i] > peak_t + cfg.recovery_window_s:
            break
        if not hr.usable[i]:
            continue
        if hr.bpm[i] <= target:
            return float(hr.t[i] - peak_t), False
    return None, True


# --- pumping vs cruising -----------------------------------------------------------------

def pump_vs_cruise(hr: HrTrack, pump: PumpTrack | None, flights: FlightResult,
                   config: HrConfig | None = None) -> PumpCruiseHr:
    """Mean HR while pumping against mean HR cruising on the foil.

    Both families are shifted forward by `hrLag`, because that is where the HR belonging to a
    given second of effort actually shows up. The cruising side additionally *excludes* a
    +/-`hrLag` guard band around every shifted burst: the seconds either side of a pump are
    exactly the ones whose HR is ambiguous, and letting them into the cruising mean would
    close the gap the metric is trying to measure.

    Bursts are taken over the whole session -- takeoff runs, failed attempts, recovery pumping
    and in-flight pumping alike. They are all the same physical act, and the takeoff/in-flight
    split is already reported by `takeoff.py`.
    """
    cfg = config or HrConfig()
    out = PumpCruiseHr()
    if hr is None or len(hr) == 0 or not flights.flights:
        return out
    lag = cfg.lag_s
    spans: list[tuple[float, float]] = []
    if pump is not None:
        spans = [(float(b[0]) + lag, float(b[-1]) + lag)
                 for b in pump.bursts(float(hr.t[0]), float(hr.t[-1]))
                 if len(b) >= pump.config.min_strokes]
    guard = [(a - lag, b + lag) for a, b in spans]
    cruise = _subtract([(f.start_t + lag, f.end_t + lag) for f in flights.flights], guard)

    out.pumping_spans = len(spans)
    out.cruising_spans = len(cruise)
    out.pumping_bpm, out.pumping_covered_s, out.pumping_span_s = hr.mean_bpm(spans)
    out.cruising_bpm, out.cruising_covered_s, out.cruising_span_s = hr.mean_bpm(cruise)
    if out.pumping_bpm is not None and out.cruising_bpm is not None:
        out.delta_bpm = out.pumping_bpm - out.cruising_bpm
    return out


def _subtract(spans: list[tuple[float, float]],
              cuts: list[tuple[float, float]]) -> list[tuple[float, float]]:
    """`spans` minus every interval in `cuts` (both may overlap; output is sorted, disjoint)."""
    out = []
    merged = _merge(cuts)
    for a, b in spans:
        cur = a
        for c, d in merged:
            if d <= cur or c >= b:
                continue
            if c > cur:
                out.append((cur, min(c, b)))
            cur = max(cur, d)
            if cur >= b:
                break
        if cur < b:
            out.append((cur, b))
    return [(a, b) for a, b in out if b > a]


def _merge(spans: list[tuple[float, float]]) -> list[tuple[float, float]]:
    out: list[tuple[float, float]] = []
    for a, b in sorted(spans):
        if out and a <= out[-1][1]:
            out[-1] = (out[-1][0], max(out[-1][1], b))
        else:
            out.append((a, b))
    return out


# --- fatigue curve --------------------------------------------------------------------------

def fatigue_curve(hr: HrTrack, takeoffs: TakeoffAnalysis, events: list[HrEvent],
                  config: HrConfig | None = None,
                  bin_minutes: float | None = None,
                  n_bins: int | None = None) -> list[FatigueBin]:
    """Takeoff cost and attempt success over session time, in `hrBinMinutes` slices.

    Pass `n_bins` instead for equal slices (thirds are the readable default for a short
    session). Attempts are counted where the *effort* happened: a flight is credited to the
    bin its takeoff started in, a failed episode to the bin of its first stroke -- so a bin's
    success rate is about what he tried in those minutes, not about where a flight ended up.
    """
    cfg = config or HrConfig()
    if hr is None or len(hr) < 2:
        return []
    t0, t1 = float(hr.t[0]), float(hr.t[-1])
    edges = _edges(t0, t1, cfg, bin_minutes, n_bins)
    by_index = {e.index: e for e in events if e.kind == TAKEOFF}
    failed = [ep.start_t for ep in takeoffs.episodes if ep.outcome == FAILED]

    out = []
    for a, b in zip(edges[:-1], edges[1:]):
        row = FatigueBin(start_t=a, end_t=b)
        row.failed = sum(1 for t in failed if a <= t < b)
        costs, bases, pumps = [], [], []
        for i, k in enumerate(takeoffs.takeoffs):
            if not (a <= k.t < b):
                continue
            row.successes += 1
            row.cost_coverage.total += 1
            ev = by_index.get(i)
            if ev is not None and ev.cost_bpm is not None:
                row.cost_coverage.valid += 1
                costs.append(ev.cost_bpm)
                bases.append(ev.baseline_bpm)
            if k.pumps_to_takeoff is not None and not k.truncated:
                pumps.append(k.pumps_to_takeoff)
        row.attempts = row.successes + row.failed
        if row.attempts:
            row.success_pct = 100.0 * row.successes / row.attempts
        row.avg_cost_bpm = _mean(costs)
        row.median_cost_bpm = _median(costs)
        row.avg_baseline_bpm = _mean(bases)
        row.avg_pumps = _mean(pumps)
        row.mean_bpm = hr.mean_bpm([(a, b)])[0]
        out.append(row)
    return out


def _edges(t0: float, t1: float, cfg: HrConfig, bin_minutes: float | None,
           n_bins: int | None) -> list[float]:
    if n_bins:
        step = (t1 - t0) / n_bins
        return [t0 + i * step for i in range(n_bins)] + [t1]
    minutes = cfg.bin_minutes if bin_minutes is None else bin_minutes
    step = max(minutes, 1e-6) * 60.0
    n = max(int(np.ceil((t1 - t0) / step)), 1)
    return [t0 + i * step for i in range(n)] + [t1]


# --- summary ---------------------------------------------------------------------------------

def summarize_hr(hr: HrTrack | None, takeoff_evs: list[HrEvent], swim_evs: list[HrEvent],
                 pump_cruise: PumpCruiseHr | None = None,
                 config: HrConfig | None = None) -> HrSummary:
    """Session tallies. Nothing is averaged without its `n valid / n total` beside it."""
    cfg = config or HrConfig()
    s = HrSummary(pump_cruise=pump_cruise or PumpCruiseHr())
    if hr is None or len(hr) == 0:
        return s
    s.has_hr = True
    span = float(hr.t[-1] - hr.t[0])
    s.usable_pct = 100.0 * hr.recorded_s(hr.t[0], hr.t[-1]) / span if span > 0 else None

    valid = [e for e in takeoff_evs if e.valid]
    s.takeoff_cost_coverage = Coverage(len(valid), len(takeoff_evs))
    s.avg_takeoff_cost_bpm = _mean([e.cost_bpm for e in valid])
    s.median_takeoff_cost_bpm = _median([e.cost_bpm for e in valid])
    s.approximate_takeoffs = sum(1 for e in valid if e.approximate)
    s.median_peak_lag_s = _median([e.peak_lag_s for e in valid])

    # bpm per stroke: only takeoffs whose run has both a measured cost and counted strokes.
    # The pooled ratio is the headline -- dividing a 3 bpm cost by 4 strokes one takeoff at a
    # time turns sensor noise into a wide spread of ratios; the median of those is reported
    # beside it so the spread is visible rather than hidden.
    rated = [e for e in valid if e.strokes]
    s.bpm_per_stroke_coverage = Coverage(len(rated), len(takeoff_evs))
    if rated:
        s.bpm_per_stroke = sum(e.cost_bpm for e in rated) / sum(e.strokes for e in rated)
        s.median_bpm_per_stroke = _median([e.cost_bpm / e.strokes for e in rated])

    s.median_takeoff_recovery_s, s.takeoff_recovery_coverage = _recovery(takeoff_evs, cfg)
    s.median_swim_recovery_s, s.swim_recovery_coverage = _recovery(swim_evs, cfg)
    swim_valid = [e for e in swim_evs if e.valid]
    s.swim_cost_coverage = Coverage(len(swim_valid), len(swim_evs))
    s.avg_swim_cost_bpm = _mean([e.cost_bpm for e in swim_valid])
    return s


def _recovery(events: list[HrEvent], cfg: HrConfig) -> tuple[float | None, Coverage]:
    """Median half-decay over the events that actually rose; total = those, not all events."""
    rose = [e for e in events if e.cost_bpm is not None and e.cost_bpm >= cfg.min_rise_bpm]
    got = [e.recovery_half_s for e in rose if e.recovery_half_s is not None]
    return _median(got), Coverage(len(got), len(rose))


def _mean(values) -> float | None:
    return float(np.mean(values)) if len(values) else None


def _median(values) -> float | None:
    return float(np.median(values)) if len(values) else None


__all__ = ["EVENT_KINDS", "SWIM", "TAKEOFF", "Coverage", "FatigueBin", "HrAnalysis",
           "HrConfig", "HrEvent", "HrSummary", "HrTrack", "PumpCruiseHr", "analyze_hr",
           "fatigue_curve", "hr_track", "hr_track_from_arrays", "pump_vs_cruise",
           "summarize_hr", "swim_events", "takeoff_events"]
