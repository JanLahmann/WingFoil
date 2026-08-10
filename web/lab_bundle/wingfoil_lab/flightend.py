"""Flight-end classification: what happened every time the rider came off the foil.

Contract: docs/algorithms.md "Flight-end outcome". Turn outcomes only explain the losses
that happen *in a maneuver*, but most sessions also lose the foil in a straight line -- a
gust dies, the foil ventilates, he catches a wingtip on a reach -- and until now those were
invisible: flight segmentation reported "a flight ended" and nothing said whether he swam,
touched down and pumped back up, or simply settled onto the board and kept moving.

Every flight end is classified with the *same three-channel evidence ladder* the turns use
(`evidence.py`, docs/algorithms.md "Turn outcome" steps 0-4). Only the leaf verdicts differ,
because a flight end is by definition already off the foil -- there is no `flew_through`:

``glide_out``   came off the foil and **kept making way** -- the speed never once reached
                `turnStopSpeedFloor`. Settling onto the board and taxiing/slogging on, the
                benign ending; also what a deliberate stop-riding looks like.
``touchdown``   came off and came to rest, briefly (up to `turnTouchdownMaxStop`), typically
                water-starting or pumping straight back into the next flight.

Note the glide/touchdown line is drawn on *whether the rider ever stopped*, not on a stop
**duration** above zero. Native Smart Recording samples at ~2 s, and the stop measure needs
two consecutive sub-floor samples (the both-ends-qualify convention), so a genuine 3 s
standstill can measure `stopped_s == 0` there -- 2026-08-04 pm has flight ends touching
0.5 m/s that a duration test would have called glide-outs. `stopped_s` is still reported and
still decides `fell_in`/`borderline`, where the durations involved (5 s, 3 s) are long
enough for the cadence to resolve them.
``fell_in``     stopped longer than `turnFallStop`, or the barometer says the wrist went
                under -- a swim.
``unknown``     the flight did not *end*, the **recording** did: its last sample is the last
                sample of a gap-free segment, so there is not one sample of evidence about
                what happened next. Flagged `truncated` and kept out of every tally.

That fourth state is not bookkeeping pedantry, it is the difference between a usable summary
and a fictional one. Garmin Smart Recording writes native sessions at a ragged cadence, and
2026-08-04 pm segments into 429 gap-free runs: 111 of its 130 "flights" end at a segment
boundary with the rider still doing 4-5 m/s. Classified on the visible evidence they would
all read `glide_out` and the session would claim 111 straight-line glide-outs that never
happened. Class-(a) CIQ sessions record at a steady 1 Hz and lose only 2 of 23.

**Ownership.** A flight end that lands inside a detected turn's outcome window is *that
turn's* event and is already counted there, so it is flagged `owned_by_turn` (the turn's
index) and left out of the straight-line tallies. Without this rule every jibe that ended in
a swim would be counted twice -- once as a `fell_in` jibe and once as a fall -- which is
exactly the double count that makes a session summary untrustworthy. Ownership is tested
against *every* detected turn, bear-aways and round-ups included: a fall inside a bear-away's
window is still explained by that course change, not by a straight-line loss.

The session split that falls out of this -- falls in turns vs straight-line falls, the same
for touchdowns -- is what `summarize_flight_ends` and `split_outcomes` report.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from .evidence import (KMH_TO_MPS, OffFoilEvidence, elapsed, longest_stop,
                       off_foil_evidence, off_foil_run, recovery_end)
from .filters import CleanTrack
from .flight import FlightResult
from .pump import PumpTrack
from .turns import FELL_IN, TOUCHDOWN, Turn, TurnSummary

GLIDE_OUT = "glide_out"
UNKNOWN = "unknown"                        # truncated by a recording gap: no evidence
FLIGHT_END_OUTCOMES = (GLIDE_OUT, TOUCHDOWN, FELL_IN, UNKNOWN)


@dataclass
class FlightEndConfig:
    """docs/algorithms.md "Flight-end outcome" defaults.

    Deliberately the *same numbers* as the turn ladder: one physical question ("did the
    rider stop, and for how long") deserves one set of thresholds however the loss started,
    and a session summary that mixed two stop definitions would be unreadable. They are
    separate fields only so a future tuning pass can move one end without the other.
    """

    stop_speed_floor_mps: float = 1.0     # turnStopSpeedFloor
    touchdown_max_stop_s: float = 3.0     # turnTouchdownMaxStop
    fall_stop_s: float = 5.0              # turnFallStop
    baro_drop_m: float = 25.0             # turnBaroDrop
    foil_exit_speed_kmh: float = 8.0      # flight config's exit speed
    foil_entry_speed_kmh: float = 12.0    # flight config's entry speed (recovery floor)
    entry_speed_window_s: float = 3.0     # entrySpeedWindow: speed the flight was ending at
    recover_pct: float = 70.0             # turnRecoverPct
    recover_hold_s: float = 2.0           # turnRecoverHold
    outcome_lookahead_s: float = 12.0     # turnOutcomeLookahead
    outcome_window_s: float = 60.0        # turnOutcomeWindow


@dataclass
class FlightEnd:
    """One flight ending, with its verdict and the evidence behind it."""

    flight_index: int                # index into FlightResult.flights
    t: float                         # the flight's end_t (first sub-exit sample)
    outcome: str                     # glide_out | touchdown | fell_in | unknown
    borderline: bool = False         # stop landed in the ambiguous 3-5 s band
    off_foil_s: float = 0.0          # time not flying, from the end to the recovery
    stopped_s: float = 0.0           # longest contiguous spell below turnStopSpeedFloor
    min_speed_mps: float = float("inf")   # slowest sample in the off-foil run
    pumped: bool = False             # accel: a pump burst inside the outcome window
    submerged: bool = False          # baro: the wrist went under inside the window
    window_s: float = 0.0            # evidence actually available past the flight end
    truncated: bool = False          # the recording ended, not the flight: no evidence
    owned_by_turn: int | None = None  # index into the turn list, when a turn explains it

    @property
    def in_turn(self) -> bool:
        return self.owned_by_turn is not None


@dataclass
class FlightEndCounts:
    """Three-way tally for one family of flight ends."""

    glide_out: int = 0
    touchdown: int = 0
    fell_in: int = 0
    unknown: int = 0                 # truncated by a recording gap -- evidence-free
    borderline: int = 0

    def add(self, end: FlightEnd) -> None:
        setattr(self, end.outcome, getattr(self, end.outcome) + 1)
        self.borderline += int(end.borderline)

    @property
    def total(self) -> int:
        """Flight ends with usable evidence -- `unknown` is deliberately not counted."""
        return self.glide_out + self.touchdown + self.fell_in


@dataclass
class FlightEndSummary:
    """Every flight end, split by whether a turn already owns it."""

    all_ends: FlightEndCounts = field(default_factory=FlightEndCounts)
    straight: FlightEndCounts = field(default_factory=FlightEndCounts)   # not in a turn
    in_turn: FlightEndCounts = field(default_factory=FlightEndCounts)


@dataclass
class OutcomeSplit:
    """The rider-facing session split: where did the falls and touchdowns happen?

    Turn-side counts come from the turn ladder (a 2 s turn touchdown never ends a flight, so
    the two channels genuinely see different events); straight-line counts are the flight
    ends no turn owns. `glide_outs` has no turn counterpart -- a maneuver the rider glides
    out of is a `touchdown` or a `flew_through` there, never a separate class.
    """

    turn_falls: int = 0
    straight_falls: int = 0
    turn_touchdowns: int = 0
    straight_touchdowns: int = 0
    glide_outs: int = 0
    unknown_ends: int = 0            # flight ends truncated by a gap: nothing can be said

    @property
    def falls(self) -> int:
        return self.turn_falls + self.straight_falls

    @property
    def touchdowns(self) -> int:
        return self.turn_touchdowns + self.straight_touchdowns


def classify_flight_ends(clean: CleanTrack, flights: FlightResult,
                         turns: list[Turn] | None = None,
                         config: FlightEndConfig | None = None,
                         pump: PumpTrack | None = None,
                         evidence: OffFoilEvidence | None = None) -> list[FlightEnd]:
    """Classify every flight ending in time order (see the module docstring).

    `turns` supplies the ownership rule and may be omitted (then nothing is owned); `pump`
    is optional accelerometer evidence, as in `turns.detect_turns`. `evidence` is the same
    read-only off-foil evidence the turn pass uses and may be handed in by a pipeline that
    already built it; omitted, it is built here.
    """
    cfg = config or FlightEndConfig()
    ev = evidence
    if ev is None:
        ev = off_foil_evidence(clean, flights, cfg.foil_exit_speed_kmh, cfg.baro_drop_m)
    if ev is None:
        return []
    ends = [_classify(i, f.end_t, ev, cfg, pump) for i, f in enumerate(flights.flights)]
    _assign_ownership(ends, turns or [])
    return ends


def summarize_flight_ends(ends: list[FlightEnd]) -> FlightEndSummary:
    """Tally all flight ends and split them into turn-owned and straight-line."""
    s = FlightEndSummary()
    for end in ends:
        s.all_ends.add(end)
        (s.in_turn if end.in_turn else s.straight).add(end)
    return s


def split_outcomes(turn_summary: TurnSummary, ends: FlightEndSummary) -> OutcomeSplit:
    """Combine the two channels into the falls/touchdowns split for a session summary."""
    return OutcomeSplit(
        turn_falls=turn_summary.outcomes.fell_in,
        straight_falls=ends.straight.fell_in,
        turn_touchdowns=turn_summary.outcomes.touchdown,
        straight_touchdowns=ends.straight.touchdown,
        glide_outs=ends.straight.glide_out,
        unknown_ends=ends.all_ends.unknown,
    )


def _classify(index: int, end_t: float, ev: OffFoilEvidence, cfg: FlightEndConfig,
              pump: PumpTrack | None) -> FlightEnd:
    """The evidence ladder for one flight end, from `end_t` to its recovery."""
    t = ev.t
    lo = min(int(np.searchsorted(t, end_t, "left")), len(t) - 1)
    if lo + 1 >= len(t) or ev.gap[lo + 1]:
        # The segment ends here, so the flight machine never saw an exit: the *recording*
        # stopped mid-flight. Nothing after it is evidence about anything.
        return FlightEnd(flight_index=index, t=float(end_t), outcome=UNKNOWN, truncated=True)
    hi = recovery_end(t, ev.gap, ev.doppler, lo,
                      end_t + cfg.outcome_lookahead_s, end_t,
                      _recover_threshold(ev, end_t, cfg), cfg.recover_hold_s)
    end = FlightEnd(flight_index=index, t=float(end_t), outcome=GLIDE_OUT,
                    window_s=float(max(t[hi] - end_t, 0.0)))
    win = (t >= end_t) & (t <= t[hi])
    end.pumped = bool(pump is not None and pump.is_pumping(end_t, t[hi]))
    end.submerged = bool(ev.submerged[win].any())

    lost = np.flatnonzero(win & ~ev.flying)
    if lost.size:
        a = int(lost[0])
        b, last = off_foil_run(t, ev.flying, a, end_t + cfg.outcome_window_s)
        end.off_foil_s = elapsed(t, ev.gap, a, last)
        end.stopped_s = longest_stop(t, ev.gap, ev.speed, a, b, cfg.stop_speed_floor_mps)
        end.min_speed_mps = float(np.min(ev.speed[a:b + 1]))

    if end.submerged or end.stopped_s > cfg.fall_stop_s:
        end.outcome = FELL_IN
    elif end.min_speed_mps < cfg.stop_speed_floor_mps:
        end.outcome = TOUCHDOWN
        end.borderline = end.stopped_s > cfg.touchdown_max_stop_s
    elif end.pumped and _marginal(ev, win, cfg):
        # Same corroboration rule as the turns: accel promotes only when the speed channels
        # also went marginal. At a flight end that test is nearly vacuous -- the flight ended
        # because the speed fell below `foilExitSpeed` -- and that is intended: a rider who
        # has to pump a burst out of it did not glide out by choice, he touched down.
        end.outcome = TOUCHDOWN
    return end


def _recover_threshold(ev: OffFoilEvidence, end_t: float, cfg: FlightEndConfig) -> float:
    """Doppler that means "flying again": `recoverPct` of the speed the flight was carrying.

    Read over `entrySpeedWindow` *before* the end, the same window the turns score their
    entry over -- not the flight's peak, which would demand 17 kn back after a 25 kn run.
    Floored at `foilEntrySpeed`: nothing below that is flying.
    """
    win = (ev.t >= end_t - cfg.entry_speed_window_s) & (ev.t <= end_t)
    entry = float(np.max(ev.doppler[win])) if win.any() else 0.0
    return max(cfg.recover_pct / 100.0 * entry, cfg.foil_entry_speed_kmh * KMH_TO_MPS)


def _marginal(ev: OffFoilEvidence, win: np.ndarray, cfg: FlightEndConfig) -> bool:
    return bool((ev.speed[win] < cfg.foil_entry_speed_kmh * KMH_TO_MPS).any())


def _assign_ownership(ends: list[FlightEnd], turns: list[Turn]) -> None:
    """Flag each flight end that falls inside a turn's outcome window, in place.

    A turn's window runs from `start_t` to `end_t + outcome_window_s` (the tail its outcome
    was actually judged over, not the lookahead cap), so the two channels agree by
    construction on which events they are looking at.
    """
    for end in ends:
        for k, turn in enumerate(turns):
            if turn.start_t <= end.t <= turn.end_t + turn.outcome_window_s:
                end.owned_by_turn = k
                break


__all__ = ["FELL_IN", "FLIGHT_END_OUTCOMES", "GLIDE_OUT", "TOUCHDOWN", "UNKNOWN",
           "FlightEnd", "FlightEndConfig", "FlightEndCounts", "FlightEndSummary",
           "OutcomeSplit", "classify_flight_ends", "split_outcomes",
           "summarize_flight_ends"]
