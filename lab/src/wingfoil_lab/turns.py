"""Turn detection, scoring and wind-axis classification.

Contract: docs/algorithms.md "Turn detection & classification". Per gap-free segment the
unwrapped COG is scanned for a net change of at least `turnMinAngle` inside at most
`turnMaxDuration` seconds containing a `turnPeakRate` spike; candidates are then
non-maximum-suppressed, trimmed to the actually-turning part, and kept only when they
touch a flight (`turnContext`).

Scoring uses the *maneuver* speed channel (positional, `filters.hybrid_speed`) because the
device Doppler is smoothed over ~3-4 s and would hide the turn minimum; the "stayed on
foil" half of the success test stays on Doppler so it agrees with flight segmentation.

Classification needs a wind axis. With TWA = wrap180(cog - windFrom) (0 = straight upwind,
+-180 = straight downwind, positive = wind over the port bow), a turn is a **tack** when
its unwrapped TWA sweep crosses head-to-wind and a **jibe** when it crosses dead downwind.
A sweep that crosses neither is a bear-away (falling off) or a round-up (luffing): these
are real course changes but not maneuvers, and are the false positives a naive
heading-delta counter reports as jibes. They are returned, flagged `counted = False`, and
left out of the summary counts.

Every turn also carries an **outcome**, the rider-facing three-way verdict (Jan's spec):

``flew_through``  never left the foil -- the whole turn window plus a short tail stays
                  inside a flight *and* above `foilExitSpeed`;
``touchdown``     lost the foil briefly, pumped back up, never came to a stop longer
                  than `turnTouchdownMaxStop`;
``fell_in``       came to a full stop (below `turnStopSpeedFloor`) for longer than
                  `turnFallStop` -- a swim and a water start.

The score%/success pair is kept as the secondary, continuous metric: outcome says *what
happened*, score says *how much speed the turn cost*.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from .filters import CleanTrack, hybrid_speed, unwrapped_cog_deg
from .flight import FlightResult
from .wind import WindEstimate

MPS_TO_KN = 1.9438445
KMH_TO_MPS = 1.0 / 3.6

TACK = "tack"
JIBE = "jibe"
BEAR_AWAY = "bear_away"
ROUND_UP = "round_up"
UNCLASSIFIED = "turn"          # wind axis missing or too weak (golden schema: "turn")
COUNTED_TYPES = (TACK, JIBE, UNCLASSIFIED)

FLEW_THROUGH = "flew_through"
TOUCHDOWN = "touchdown"
FELL_IN = "fell_in"
OUTCOMES = (FLEW_THROUGH, TOUCHDOWN, FELL_IN)


@dataclass
class TurnConfig:
    """docs/algorithms.md "Turn detection & classification" defaults."""

    min_angle_deg: float = 60.0           # turnMinAngle: net unwrapped COG change
    max_duration_s: float = 8.0           # turnMaxDuration: window for the net change
    peak_rate_deg_s: float = 25.0         # turnPeakRate: at >= 1 sample
    continue_rate_deg_s: float = 5.0      # lab-added: edge trim, below this is not turning
    min_cog_speed_mps: float = 2.0        # lab-added: COG != heading below this (COAPS)
    context_after_s: float = 3.0          # turnContext: ON_FOIL or <= this after a flight
    entry_speed_window_s: float = 3.0     # entrySpeedWindow: max speed before turn start
    min_speed_lag_s: float = 2.0          # lab-added: the minimum can land past the exit
    success_pct: float = 70.0             # turnSuccessPct
    foil_exit_speed_kmh: float = 8.0      # flight config's exit speed (success floor)
    stop_speed_floor_mps: float = 1.0     # turnStopSpeedFloor: below this = "stopped"
    touchdown_max_stop_s: float = 3.0     # turnTouchdownMaxStop: still a touchdown
    fall_stop_s: float = 5.0              # turnFallStop: above this = fell in
    outcome_lookahead_s: float = 5.0      # turnOutcomeLookahead: tail searched for the loss
    outcome_window_s: float = 60.0        # turnOutcomeWindow: cap on following the recovery


@dataclass
class Turn:
    """One detected course change, scored and (given wind) classified."""

    start_t: float
    end_t: float
    min_t: float                     # time of the speed minimum
    kind: str                        # tack | jibe | bear_away | round_up | turn
    counted: bool                    # tack/jibe (or plain turn) -> counts in summaries
    net_deg: float                   # signed net COG change (+ = clockwise/starboard)
    peak_rate_deg_s: float           # signed peak rate
    direction: str                   # "starboard" (clockwise) | "port" (counter-clockwise)
    side: str                        # tack sailed *before* the turn: port|starboard|unknown
    entry_kn: float                  # maneuver channel, max over entry window
    min_kn: float                    # maneuver channel, min over the turn
    entry_kn_doppler: float
    min_kn_doppler: float
    score: float                     # min_kn / entry_kn in [0,1]
    success: bool                    # score >= turnSuccessPct AND never dropped off foil
    twa_in_deg: float                # TWA entering the turn (nan without wind)
    twa_out_deg: float
    outcome: str = FLEW_THROUGH      # flew_through | touchdown | fell_in
    borderline: bool = False         # stop landed in the ambiguous 3-5 s band
    off_foil_s: float = 0.0          # time not flying, from the loss to the recovery
    stopped_s: float = 0.0           # longest contiguous spell below turnStopSpeedFloor


@dataclass
class OutcomeCounts:
    """Three-way outcome tally for one family of turns."""

    flew_through: int = 0
    touchdown: int = 0
    fell_in: int = 0
    borderline: int = 0              # touchdowns whose stop fell in the ambiguous band

    def add(self, turn: "Turn") -> None:
        setattr(self, turn.outcome, getattr(self, turn.outcome) + 1)
        self.borderline += int(turn.borderline)

    @property
    def total(self) -> int:
        return self.flew_through + self.touchdown + self.fell_in


@dataclass
class TurnSummary:
    """Counts suitable for session fields / goldens (bear-aways excluded by design)."""

    tacks: int = 0
    tacks_successful: int = 0
    jibes: int = 0
    jibes_successful: int = 0
    tack_outcomes: OutcomeCounts = field(default_factory=OutcomeCounts)
    jibe_outcomes: OutcomeCounts = field(default_factory=OutcomeCounts)
    outcomes: OutcomeCounts = field(default_factory=OutcomeCounts)   # all counted turns
    unclassified: int = 0            # detected turns with no usable wind axis
    turns_counted: int = 0           # tacks + jibes + unclassified (the "attempted" count)
    turns_successful: int = 0
    success_pct: float = 0.0         # of turns_counted
    rejected: int = 0                # bear-aways / round-ups, not maneuvers
    port: int = 0                    # counted turns entered on port tack
    starboard: int = 0
    unknown_side: int = 0


def detect_turns(clean: CleanTrack, flights: FlightResult,
                 wind: WindEstimate | None = None,
                 config: TurnConfig | None = None) -> list[Turn]:
    """Detect, score and classify every turn in a cleaned track, in time order."""
    cfg = config or TurnConfig()
    turns: list[Turn] = []
    for seg in clean.segments():
        if len(seg) < 3 or seg["x"].isna().all():
            continue
        t = seg["t"].to_numpy(float)
        x, y = seg["x"].to_numpy(float), seg["y"].to_numpy(float)
        v = seg["doppler_mps"].to_numpy(float)
        for a, b in _sailing_runs(v >= cfg.min_cog_speed_mps):
            u = unwrapped_cog_deg(x[a:b + 1], y[a:b + 1])
            tu = t[a:a + len(u)]
            rate = _rates(tu, u)
            for i, j in _suppress(_candidates(tu, u, rate, cfg)):
                i, j = _trim(i, j, rate, u, cfg)
                if not _on_foil(tu[i], tu[j], flights, cfg):
                    continue
                turns.append(_build_turn(seg, t, tu, u, rate, i, j, wind, cfg))
    turns.sort(key=lambda x: x.start_t)
    turns = _drop_overlaps(turns)
    _assign_outcomes(turns, clean, flights, cfg)
    return turns


def summarize_turns(turns: list[Turn]) -> TurnSummary:
    """Aggregate detected turns; bear-aways/round-ups only feed `rejected`."""
    s = TurnSummary()
    for t in turns:
        if not t.counted:
            s.rejected += 1
            continue
        if t.kind == TACK:
            s.tacks += 1
            s.tacks_successful += int(t.success)
            s.tack_outcomes.add(t)
        elif t.kind == JIBE:
            s.jibes += 1
            s.jibes_successful += int(t.success)
            s.jibe_outcomes.add(t)
        else:
            s.unclassified += 1
        s.outcomes.add(t)
        s.turns_counted += 1
        s.turns_successful += int(t.success)
        s.port += int(t.side == "port")
        s.starboard += int(t.side == "starboard")
        s.unknown_side += int(t.side == "unknown")
    s.success_pct = 100.0 * s.turns_successful / s.turns_counted if s.turns_counted else 0.0
    return s


def _assign_outcomes(turns: list[Turn], clean: CleanTrack, flights: FlightResult,
                     cfg: TurnConfig) -> None:
    """Fill `outcome`/`borderline`/`off_foil_s`/`stopped_s` on every turn, in place.

    Runs over the whole cleaned track rather than per segment: a fall that starts before a
    recording gap is still followed into the samples after it.
    """
    df = clean.records
    if df.empty:
        return
    t = df["t"].to_numpy(float)
    dop = df["doppler_mps"].to_numpy(float)
    gap = df["gap_before"].to_numpy(bool)
    stop_v = np.minimum(dop, hybrid_speed(df))
    flying = _flying_mask(t, dop, flights, cfg)
    for turn in turns:
        _outcome(turn, t, gap, stop_v, flying, cfg)


def _flying_mask(t: np.ndarray, dop: np.ndarray, flights: FlightResult,
                 cfg: TurnConfig) -> np.ndarray:
    """Per sample: inside a flight *and* still above the foil exit speed.

    Flight segmentation alone is too coarse for this job: its exit needs `exitHold` (3 s)
    of sub-exit speed, so a 1-2 s touchdown -- exactly Jan's middle case -- never breaks
    the flight. Adding the instantaneous exit-speed test makes those visible while the
    flight mask still catches the long losses that the speed trace alone would blur.
    """
    m = np.zeros(len(t), dtype=bool)
    for f in flights.flights:
        m |= (t >= f.start_t) & (t <= f.end_t)
    return m & (dop > cfg.foil_exit_speed_kmh * KMH_TO_MPS)


def _outcome(turn: Turn, t: np.ndarray, gap: np.ndarray, stop_v: np.ndarray,
             flying: np.ndarray, cfg: TurnConfig) -> None:
    """Three-way outcome for one turn (see the module docstring).

    The loss of foil is looked for from the turn start to `outcomeLookahead` past the COG
    sweep -- a botched exit collapses just after the turn geometry ends, the same lag the
    speed minimum needs. Once lost, the off-foil run is followed until foiling resumes,
    capped at `outcomeWindow` so a turn taken just before a break does not absorb it.
    """
    lost = np.flatnonzero((t >= turn.start_t) & (t <= turn.end_t + cfg.outcome_lookahead_s)
                          & ~flying)
    if lost.size == 0:
        turn.outcome, turn.borderline = FLEW_THROUGH, False
        turn.off_foil_s = turn.stopped_s = 0.0
        return

    a = int(lost[0])
    cap = turn.end_t + cfg.outcome_window_s
    b = a
    while b + 1 < len(t) and not flying[b + 1] and t[b + 1] <= cap:
        b += 1
    end = min(b + 1, len(t) - 1)                       # first flying sample, if there is one

    turn.off_foil_s = _elapsed(t, gap, a, end)
    turn.stopped_s = _longest_stop(t, gap, stop_v, a, b, cfg.stop_speed_floor_mps)
    if turn.stopped_s > cfg.fall_stop_s:
        turn.outcome, turn.borderline = FELL_IN, False
    else:
        turn.outcome = TOUCHDOWN
        turn.borderline = turn.stopped_s > cfg.touchdown_max_stop_s


def _elapsed(t: np.ndarray, gap: np.ndarray, a: int, b: int) -> float:
    """Recorded time from sample `a` to `b`, skipping intervals that span a gap."""
    if b <= a:
        return 0.0
    dt = np.diff(t[a:b + 1])
    return float(dt[~gap[a + 1:b + 1]].sum())


def _longest_stop(t: np.ndarray, gap: np.ndarray, v: np.ndarray, a: int, b: int,
                  floor: float) -> float:
    """Longest contiguous spell below `floor` in [a, b], in recorded seconds.

    An interval counts only when *both* of its end samples are below the floor and no gap
    separates them -- the same "hold" convention flight segmentation uses, so a stop and a
    flight exit are measured on the same clock.
    """
    below = v[a:b + 1] < floor
    if below.size < 2:
        return 0.0
    ok = below[1:] & below[:-1] & ~gap[a + 1:b + 1]
    best = run = 0.0
    for keep, step in zip(ok, np.diff(t[a:b + 1])):
        run = run + step if keep else 0.0
        best = max(best, run)
    return float(best)


def _sailing_runs(ok: np.ndarray) -> list[tuple[int, int]]:
    """Maximal index runs (a, b) of consecutive True, at least 3 samples long.

    Below `min_cog_speed_mps` the COG is position noise rather than a heading, so a
    capsize or a wobbling water start would otherwise read as a multi-turn spin. Runs
    bound the *geometry* only -- entry/minimum speeds are still read from the whole
    segment, so a turn that ends in a collapse still scores against its collapse.
    """
    runs, start = [], None
    for i, good in enumerate(ok):
        if good and start is None:
            start = i
        elif not good and start is not None:
            if i - start >= 3:
                runs.append((start, i - 1))
            start = None
    if start is not None and len(ok) - start >= 3:
        runs.append((start, len(ok) - 1))
    return runs


def _drop_overlaps(turns: list[Turn]) -> list[Turn]:
    """Keep the wider-sweeping turn when two detections overlap in time across runs."""
    out: list[Turn] = []
    for t in turns:
        if out and t.start_t <= out[-1].end_t:
            if abs(t.net_deg) > abs(out[-1].net_deg):
                out[-1] = t
            continue
        out.append(t)
    return out


def _rates(tu: np.ndarray, u: np.ndarray) -> np.ndarray:
    """Signed COG rate per interval between consecutive bearings (len(u) - 1)."""
    dt = np.diff(tu)
    return np.where(dt > 0, np.diff(u) / np.where(dt > 0, dt, 1.0), 0.0)


def _candidates(tu: np.ndarray, u: np.ndarray, rate: np.ndarray,
                cfg: TurnConfig) -> list[tuple[int, int, float]]:
    """Per start index, the largest net COG change reachable within the duration cap.

    Kept when it clears `min_angle_deg` and contains a `peak_rate_deg_s` sample.
    """
    out: list[tuple[int, int, float]] = []
    n = len(u)
    for i in range(n - 1):
        j_end = int(np.searchsorted(tu, tu[i] + cfg.max_duration_s, side="right"))
        if j_end <= i + 1:
            continue
        net = u[i + 1:j_end] - u[i]
        k = int(np.argmax(np.abs(net)))
        if abs(net[k]) < cfg.min_angle_deg:
            continue
        j = i + 1 + k
        if np.max(np.abs(rate[i:j])) < cfg.peak_rate_deg_s:
            continue
        out.append((i, j, float(abs(net[k]))))
    return out


def _suppress(cands: list[tuple[int, int, float]]) -> list[tuple[int, int]]:
    """Non-maximum suppression: strongest net change first, drop anything overlapping it."""
    taken: list[tuple[int, int]] = []
    for i, j, _ in sorted(cands, key=lambda c: -c[2]):
        if any(i <= b and a <= j for a, b in taken):
            continue
        taken.append((i, j))
    return sorted(taken)


def _trim(i: int, j: int, rate: np.ndarray, u: np.ndarray,
          cfg: TurnConfig) -> tuple[int, int]:
    """Shrink the span to the actually-turning part; revert if that loses the turn."""
    a, b = i, j
    while a < b and abs(rate[a]) < cfg.continue_rate_deg_s:
        a += 1
    while b > a and abs(rate[b - 1]) < cfg.continue_rate_deg_s:
        b -= 1
    if b <= a or abs(u[b] - u[a]) < cfg.min_angle_deg:
        return i, j
    return a, b


def _on_foil(start_t: float, end_t: float, flights: FlightResult, cfg: TurnConfig) -> bool:
    """True when the turn overlaps a flight, or starts within `context_after_s` of one."""
    return any(start_t <= f.end_t + cfg.context_after_s and end_t >= f.start_t
               for f in flights.flights)


def _build_turn(seg, t: np.ndarray, tu: np.ndarray, u: np.ndarray, rate: np.ndarray,
                i: int, j: int, wind: WindEstimate | None, cfg: TurnConfig) -> Turn:
    start_t, end_t = float(tu[i]), float(tu[j])
    net = float(u[j] - u[i])
    peak = float(rate[i:j][np.argmax(np.abs(rate[i:j]))]) if j > i else 0.0

    man = hybrid_speed(seg)
    dop = seg["doppler_mps"].to_numpy(float)
    entry_win = (t >= start_t - cfg.entry_speed_window_s) & (t <= start_t)
    turn_win = (t >= start_t) & (t <= end_t + cfg.min_speed_lag_s)
    if not entry_win.any():
        entry_win = t == t[max(i, 0)]
    entry_man = float(np.max(man[entry_win]))
    entry_dop = float(np.max(dop[entry_win]))
    min_idx = int(np.flatnonzero(turn_win)[int(np.argmin(man[turn_win]))])
    min_man = float(man[min_idx])
    min_dop = float(np.min(dop[turn_win]))

    score = min_man / entry_man if entry_man > 0 else 0.0
    stayed_up = min_dop > cfg.foil_exit_speed_kmh * KMH_TO_MPS
    success = bool(score >= cfg.success_pct / 100.0 and stayed_up)

    kind, side, twa_in, twa_out = _classify(u[i], u[j], wind)
    return Turn(
        start_t=start_t, end_t=end_t, min_t=float(t[min_idx]), kind=kind,
        counted=kind in COUNTED_TYPES, net_deg=net, peak_rate_deg_s=peak,
        direction="starboard" if net >= 0 else "port", side=side,
        entry_kn=entry_man * MPS_TO_KN, min_kn=min_man * MPS_TO_KN,
        entry_kn_doppler=entry_dop * MPS_TO_KN, min_kn_doppler=min_dop * MPS_TO_KN,
        score=float(score), success=success, twa_in_deg=twa_in, twa_out_deg=twa_out,
    )


def _classify(cog_in: float, cog_out: float,
              wind: WindEstimate | None) -> tuple[str, str, float, float]:
    """(kind, side, twa_in, twa_out) from the unwrapped COG sweep and the wind axis.

    The sweep is carried onto TWA unwrapped, so "crosses head-to-wind" is "passes a
    multiple of 360" and "crosses dead downwind" is "passes 180 + a multiple of 360".
    A sweep wide enough to do both is named after whichever crossing sits nearer its
    middle. Without a usable wind axis every turn stays `UNCLASSIFIED`.
    """
    if wind is None or not wind.usable:
        return UNCLASSIFIED, "unknown", float("nan"), float("nan")
    twa_in = _wrap180(cog_in - wind.dir_deg)
    twa_out = twa_in + (cog_out - cog_in)
    lo, hi = min(twa_in, twa_out), max(twa_in, twa_out)
    mid = 0.5 * (lo + hi)
    head = _nearest_crossing(lo, hi, 0.0, mid)
    down = _nearest_crossing(lo, hi, 180.0, mid)
    side = "port" if twa_in > 0 else "starboard"
    if head is None and down is None:
        kind = BEAR_AWAY if abs(twa_out) > abs(twa_in) else ROUND_UP
    elif down is None or (head is not None and abs(head - mid) <= abs(down - mid)):
        kind = TACK
    else:
        kind = JIBE
    return kind, side, float(twa_in), float(_wrap180(twa_out))


def _nearest_crossing(lo: float, hi: float, offset: float, mid: float) -> float | None:
    """The value ``offset + 360k`` inside [lo, hi] closest to `mid`, if any."""
    k0 = np.floor((lo - offset) / 360.0)
    best = None
    for k in (k0, k0 + 1, k0 + 2):
        v = offset + 360.0 * k
        if lo <= v <= hi and (best is None or abs(v - mid) < abs(best - mid)):
            best = v
    return best


def _wrap180(deg: float) -> float:
    return (float(deg) + 180.0) % 360.0 - 180.0
