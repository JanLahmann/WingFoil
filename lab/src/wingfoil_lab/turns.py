"""Turn detection, scoring and wind-axis classification.

Contract: docs/algorithms.md "Turn detection & classification". Per gap-free segment the
unwrapped COG is scanned for a net change of at least `turnMinAngle` inside at most
`turnMaxDuration` seconds containing a `turnPeakRate` spike; candidates are then
non-maximum-suppressed, trimmed to the actually-turning part, and kept only when they
touch a flight (`turnContext`).

A COG sweep alone is not a maneuver. A rider swimming next to the board, or drifting while
he sorts the wing out, produces heading flips that are geometrically indistinguishable from
a jibe *in angle terms* while covering almost no water -- and `turnCogSpeedFloor` cannot
catch all of them, because a 2-3 m/s drift clears it. So a candidate must also have **carved
an arc**: `turnMinArc` metres of path travelled across the sweep, and an effective radius
``arc / |net heading change in radians|`` of at least `turnMinRadius`. A real jibe carries
speed through 6-8 m of turning radius; a heading flip on the spot has a radius near zero
whatever its angle. This is a *geometric* gate, deliberately not another speed floor:
`turnCogSpeedFloor` stays where it is. Candidates that fail it are dropped, like turns that
touch no flight -- they are not course changes at all, so they are not bear-aways either.

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

``flew_through``  never left the foil -- the turn's whole outcome window stays inside a
                  flight *and* above `foilExitSpeed`, with no pumping;
``touchdown``     lost the foil briefly, pumped back up, never came to a stop longer
                  than `turnTouchdownMaxStop`;
``fell_in``       came to a full stop (below `turnStopSpeedFloor`) for longer than
                  `turnFallStop` -- a swim and a water start.

The window a turn is judged over is **not a fixed tail**: it runs from the turn start until
the rider is demonstrably flying again -- back above `turnRecoverPct` of the entry speed
(never below `foilEntrySpeed`) for `turnRecoverHold` -- capped at `turnOutcomeLookahead`.
A jibe exited at marginal speed can bleed off for 8-12 s before the foil finally stalls,
and that mush-out belongs to the jibe; a jibe the rider powers straight out of closes its
window in a second or two and cannot absorb a later, unrelated touchdown.

Inside that window three channels give evidence, strongest first, each degrading to nothing
when its channel is missing:

**speed (always)** -- the primary touchdown detector. A sample counts as flying only inside
a flight and with *both* speed channels above `foilExitSpeed`. The Doppler alone is not
enough: the firmware smooths it over 3-4 s, so a 1-2 s touchdown is averaged away, while
the positional channel is a plain 2 s central difference and shows it.

**barometric altitude (when the source has it)** -- a dunked wrist reads absurdly low: 30 cm
of water is ~30 hPa, which the altimeter renders as a ~250 m drop, and its slew limiter then
crawls back over minutes. Nothing on a lake moves an altimeter by `turnBaroDrop`, so a
sample that far below the session's median altitude is proof the rider was in the water: it
is never flying, and it makes the turn a `fell_in` outright. Positive-only evidence -- most
falls keep the wrist dry, so its silence means nothing.

**wrist accelerometer (class (a) only)** -- pumping, per `pump.PumpTrack`. Corroborating,
not primary: the rider pumps a wing for many reasons, so a pump burst turns a fly-through
into a touchdown only when the speed channels *also* saw the foil go marginal (below
`foilEntrySpeed`) in the same window. Speed says the foil stopped carrying, accel says the
rider had to pump it out; neither alone is enough.

The score%/success pair is kept as the secondary, continuous metric: outcome says *what
happened*, score says *how much speed the turn cost*.

The summary finally carries two **streaks**, ``longest_dry_streak`` (no swim) and
``longest_flew_streak`` (every turn carried clean). They are the one part of the summary
that is *not* read from the turn channel alone: a streak claims something about the rider,
and a swim in a straight line ends a run of clean jibes exactly as a botched jibe does. So
the counted turns are merged with the flight ends no counted turn owns into one time-ordered
event list, and only a counted turn can lengthen a run -- see `streaks`.
"""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass, field
from typing import Protocol

import numpy as np

from .evidence import (KMH_TO_MPS, MPS_TO_KN, OffFoilEvidence, elapsed, longest_stop,
                       off_foil_evidence, off_foil_run, recovery_end)
from .filters import CleanTrack, hybrid_speed, unwrapped_cog_deg
from .flight import FlightResult
from .pump import PumpTrack
from .wind import WindEstimate

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
    min_arc_m: float = 12.0               # turnMinArc: path travelled across the sweep
    min_radius_m: float = 6.0             # turnMinRadius: arc / |net angle| (rad)
    context_after_s: float = 3.0          # turnContext: ON_FOIL or <= this after a flight
    entry_speed_window_s: float = 3.0     # entrySpeedWindow: max speed before turn start
    min_speed_lag_s: float = 2.0          # lab-added: the minimum can land past the exit
    success_pct: float = 70.0             # turnSuccessPct
    foil_exit_speed_kmh: float = 8.0      # flight config's exit speed (success floor)
    foil_entry_speed_kmh: float = 12.0    # flight config's entry speed (recovery floor)
    stop_speed_floor_mps: float = 1.0     # turnStopSpeedFloor: below this = "stopped"
    touchdown_max_stop_s: float = 3.0     # turnTouchdownMaxStop: still a touchdown
    fall_stop_s: float = 5.0              # turnFallStop: above this = fell in
    outcome_lookahead_s: float = 12.0     # turnOutcomeLookahead: cap on the tail searched
    recover_pct: float = 70.0             # turnRecoverPct: of entry speed = flying again
    recover_hold_s: float = 2.0           # turnRecoverHold: held this long = turn is over
    outcome_window_s: float = 60.0        # turnOutcomeWindow: cap on following the recovery
    baro_drop_m: float = 25.0             # turnBaroDrop: below median altitude = submerged


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
    arc_m: float = 0.0               # path length travelled across the COG sweep
    chord_m: float = 0.0             # straight-line displacement across the sweep
    radius_m: float = 0.0            # arc_m / |net_deg| in radians: how tightly it carved
    outcome: str = FLEW_THROUGH      # flew_through | touchdown | fell_in
    borderline: bool = False         # stop landed in the ambiguous 3-5 s band
    off_foil_s: float = 0.0          # time not flying, from the loss to the recovery
    stopped_s: float = 0.0           # longest contiguous spell below turnStopSpeedFloor
    pumped: bool = False             # accel: a pump burst inside the outcome window
    submerged: bool = False          # baro: the wrist went under inside the window
    outcome_window_s: float = 0.0    # tail past the sweep the outcome was judged over


class FlightEndLike(Protocol):
    """The four fields a streak reads off a `flightend.FlightEnd`.

    Declared structurally rather than imported: `flightend` imports *this* module for the
    shared outcome vocabulary, so the dependency has to keep running one way only.
    """

    t: float
    outcome: str
    truncated: bool
    owned_by_turn: int | None


@dataclass(frozen=True)
class _StreakEvent:
    """One thing that happened to the rider, from either channel (see `streaks`)."""

    t: float
    is_turn: bool
    outcome: str
    borderline: bool

    @property
    def flew_clean(self) -> bool:
        """A counted turn carried all the way through -- the only thing `flew` extends on.

        `borderline` only ever rides on a `touchdown`, so the flag is redundant against the
        outcome today; it is spelled out because a streak is exactly where a "nearly a fall"
        must not read as a clean one, whatever a later re-tune does to the flag.
        """
        return self.is_turn and self.outcome == FLEW_THROUGH and not self.borderline


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
    longest_dry_streak: int = 0      # longest run of counted turns without a fell_in
    longest_flew_streak: int = 0     # longest run of counted turns that all flew through


def detect_turns(clean: CleanTrack, flights: FlightResult,
                 wind: WindEstimate | None = None,
                 config: TurnConfig | None = None,
                 pump: PumpTrack | None = None,
                 evidence: OffFoilEvidence | None = None) -> list[Turn]:
    """Detect, score and classify every turn in a cleaned track, in time order.

    `pump` is optional accelerometer evidence (class-(a) sources); without it the outcome
    rests on the speed channels alone. `evidence` lets a pipeline that already built the
    off-foil evidence for this track hand it in (it is read-only, and the flight-end and
    takeoff passes ask for the very same arrays); omitted, it is built here.
    """
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
                turn = _build_turn(seg, t, tu, u, rate, i, j, wind, cfg,
                                   _arc(x, y, a + i, a + j + 1))
                if not _carved(turn, cfg):
                    continue
                turns.append(turn)
    turns.sort(key=lambda x: x.start_t)
    turns = _drop_overlaps(turns)
    _assign_outcomes(turns, clean, flights, cfg, pump, evidence)
    return turns


def summarize_turns(turns: list[Turn],
                    ends: Sequence[FlightEndLike] = ()) -> TurnSummary:
    """Aggregate detected turns; bear-aways/round-ups only feed `rejected`.

    Every count here reads turns alone. `ends` is needed by the **streaks** only, which are
    a claim about the rider rather than about the turn channel and so have to see the
    losses that happened outside a maneuver too (`streaks`).
    """
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
    s.longest_dry_streak, s.longest_flew_streak = streaks(turns, ends)
    return s


def streaks(turns: list[Turn], ends: Sequence[FlightEndLike] = ()) -> tuple[int, int]:
    """(longest dry streak, longest flew streak) over one merged, time-ordered event list.

    A streak is a claim about *the rider*, not about the turn channel, so it cannot be read
    from turn outcomes alone: a swim in a straight line, or one inside a bear-away, ends a
    run of clean jibes just as surely as a botched jibe does. The events are therefore

    * every **counted turn**, at its ``end_t``, carrying its turn outcome; and
    * every **flight end no counted turn owns** -- straight-line ends, and ends owned by a
      rejected sweep -- at its ``t``, carrying its flight-end outcome.

    An end a counted turn *does* own is left out: that turn's own outcome already speaks
    for it, and counting both would penalize one swim twice.

    Only a counted turn can lengthen a run. A non-turn event can only end one:

    ``dry``  reset by ``fell_in`` from either channel; a turn extends it on anything else,
             and a non-turn ``touchdown``/``glide_out``/``unknown`` changes nothing --
             pumping straight back up out of a straight-line touchdown is still dry;
    ``flew`` reset by ``touchdown`` or ``fell_in`` from either channel (and by a
             ``borderline`` turn); only ``flew_through`` extends it.

    `ends` omitted means the caller has no flight-end channel to offer -- correct for a
    synthetic turn-only track, and never the case in the real pipeline, which classifies
    ends before it summarizes turns.
    """
    longest_dry = longest_flew = dry = flew = 0
    for ev in _streak_events(turns, ends):
        if ev.is_turn:
            dry = 0 if ev.outcome == FELL_IN else dry + 1
            flew = flew + 1 if ev.flew_clean else 0
            longest_dry = max(longest_dry, dry)
            longest_flew = max(longest_flew, flew)
        else:
            # Nothing outside a maneuver is a maneuver the rider carried, so a non-turn
            # event never lengthens a run -- it can only cut one short.
            if ev.outcome == FELL_IN:
                dry = 0
            if ev.outcome in (FELL_IN, TOUCHDOWN):
                flew = 0
    return longest_dry, longest_flew


def _streak_events(turns: list[Turn],
                   ends: Sequence[FlightEndLike]) -> list["_StreakEvent"]:
    """The merged event list a streak walks, in time order (see `streaks`).

    Truncated ends are dropped outright: the recording stopped, which is not evidence that
    anything happened to the rider. At an identical timestamp the non-turn event is applied
    first, so a coincident fall breaks the run rather than being masked by the turn that
    would extend it -- the conservative reading, and a tie the ownership window makes
    unreachable in practice anyway.
    """
    counted = {i for i, t in enumerate(turns) if t.counted}
    events = [_StreakEvent(t.end_t, True, t.outcome, t.borderline)
              for i, t in enumerate(turns) if i in counted]
    for end in ends:
        if end.truncated or end.owned_by_turn in counted:
            continue
        events.append(_StreakEvent(float(end.t), False, end.outcome, False))
    events.sort(key=lambda e: (e.t, e.is_turn))
    return events


def _assign_outcomes(turns: list[Turn], clean: CleanTrack, flights: FlightResult,
                     cfg: TurnConfig, pump: PumpTrack | None = None,
                     evidence: OffFoilEvidence | None = None) -> None:
    """Fill `outcome`/`borderline`/`off_foil_s`/`stopped_s` on every turn, in place."""
    ev = evidence
    if ev is None:
        ev = off_foil_evidence(clean, flights, cfg.foil_exit_speed_kmh, cfg.baro_drop_m)
    if ev is None:
        return
    for turn in turns:
        _outcome(turn, ev, cfg, pump)


def _outcome(turn: Turn, ev: OffFoilEvidence, cfg: TurnConfig,
             pump: PumpTrack | None = None) -> None:
    """Three-way outcome for one turn (see the module docstring).

    The loss of foil is looked for from the turn start to the end of the turn's *outcome
    window* (`_window_end`). Once lost, the off-foil run is followed until foiling resumes,
    capped at `outcomeWindow` so a turn taken just before a break does not absorb it.
    """
    t = ev.t
    hi = _window_end(turn, ev, cfg)
    turn.outcome_window_s = float(max(t[hi] - turn.end_t, 0.0))
    win = (t >= turn.start_t) & (t <= t[hi])
    turn.pumped = bool(pump is not None and pump.is_pumping(turn.start_t, t[hi]))
    turn.submerged = bool(ev.submerged[win].any())

    lost = np.flatnonzero(win & ~ev.flying)
    if lost.size == 0:
        turn.borderline = False
        turn.off_foil_s = turn.stopped_s = 0.0
        marginal = bool((ev.speed[win] < cfg.foil_entry_speed_kmh * KMH_TO_MPS).any())
        turn.outcome = TOUCHDOWN if (turn.pumped and marginal) else FLEW_THROUGH
        return

    a = int(lost[0])
    b, end = off_foil_run(t, ev.flying, a, turn.end_t + cfg.outcome_window_s)
    turn.off_foil_s = elapsed(t, ev.gap, a, end)
    turn.stopped_s = longest_stop(t, ev.gap, ev.speed, a, b, cfg.stop_speed_floor_mps)
    if turn.submerged or turn.stopped_s > cfg.fall_stop_s:
        turn.outcome, turn.borderline = FELL_IN, False
    else:
        turn.outcome = TOUCHDOWN
        turn.borderline = turn.stopped_s > cfg.touchdown_max_stop_s


def _window_end(turn: Turn, ev: OffFoilEvidence, cfg: TurnConfig) -> int:
    """Last sample index the turn is judged over: recovery, a gap, or the lookahead cap.

    Recovery is `evidence.recovery_end` measured against `turnRecoverPct` of the *turn's*
    entry speed, floored at `foilEntrySpeed` (below that nothing is flying however slowly
    the turn was entered), and searched only past the speed minimum so the entry itself
    cannot close the window.
    """
    lo = min(int(np.searchsorted(ev.t, turn.start_t, "left")), len(ev.t) - 1)
    thr = max(cfg.recover_pct / 100.0 * turn.entry_kn / MPS_TO_KN,
              cfg.foil_entry_speed_kmh * KMH_TO_MPS)
    return recovery_end(ev.t, ev.gap, ev.doppler, lo,
                        turn.end_t + cfg.outcome_lookahead_s, turn.min_t,
                        thr, cfg.recover_hold_s)


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


def _arc(x: np.ndarray, y: np.ndarray, lo: int, hi: int) -> tuple[float, float]:
    """(path length, straight-line displacement) in metres over the samples [lo, hi].

    `lo`/`hi` are indices into the segment's projected track. The COG element `k` describes
    the step *leaving* sample `k`, so a sweep over COG elements i..j spans samples i..j+1.
    """
    lo, hi = max(lo, 0), min(hi, len(x) - 1)
    if hi <= lo:
        return 0.0, 0.0
    dx, dy = np.diff(x[lo:hi + 1]), np.diff(y[lo:hi + 1])
    return float(np.hypot(dx, dy).sum()), float(math.hypot(x[hi] - x[lo], y[hi] - y[lo]))


def _carved(turn: Turn, cfg: TurnConfig) -> bool:
    """The spatial gate: did the rider actually move around the curve? (module docstring)

    Two geometric tests, both scale-free with respect to sample rate: `turnMinArc` metres of
    water covered across the sweep, and an effective radius (arc over the swept angle in
    radians) of at least `turnMinRadius`. Angle alone passes a heading flip on the spot;
    these do not.
    """
    return turn.arc_m >= cfg.min_arc_m and turn.radius_m >= cfg.min_radius_m


def _on_foil(start_t: float, end_t: float, flights: FlightResult, cfg: TurnConfig) -> bool:
    """True when the turn overlaps a flight, or starts within `context_after_s` of one."""
    return any(start_t <= f.end_t + cfg.context_after_s and end_t >= f.start_t
               for f in flights.flights)


def _build_turn(seg, t: np.ndarray, tu: np.ndarray, u: np.ndarray, rate: np.ndarray,
                i: int, j: int, wind: WindEstimate | None, cfg: TurnConfig,
                arc: tuple[float, float] = (0.0, 0.0)) -> Turn:
    start_t, end_t = float(tu[i]), float(tu[j])
    net = float(u[j] - u[i])
    arc_m, chord_m = arc
    radius_m = arc_m / abs(math.radians(net)) if net else 0.0
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
        arc_m=arc_m, chord_m=chord_m, radius_m=radius_m,
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
