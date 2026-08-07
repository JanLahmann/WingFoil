"""Takeoff analysis: how every flight *started*, and every attempt that never became one.

Contract: docs/algorithms.md "Takeoff analysis". This is the flight-START analogue of
`flightend.py` and the product's differentiator metric (docs/plan.md: pumps-to-takeoff,
takeoff success rate, pumping effort). Flight segmentation says a flight began; this module
says what it cost to get there -- how many strokes, over how long, from what speed -- and,
crucially, how many times the rider pumped and *did not* get up, which no summary built from
flights alone can ever see.

**The takeoff run.** Looking back from `ON_FOIL`, the run is the contiguous pre-flight window
of *rising speed* plus the *pump burst* that led into it, whichever started earlier:

- the speed rise is walked back from the flight start while the previous sample is no more
  than `takeoffRiseSlack` faster than the slowest sample seen so far -- i.e. while speed was
  still climbing toward the entry, tolerating the wobble of a real water start. It is read on
  the Doppler channel, the same channel that defined the flight boundary, so run and flight
  agree on where takeoff ended;
- the pump side is the last burst of at least `pumpMinStrokes` whose final stroke falls within
  `takeoffAttemptWindow` of the flight start. A burst further back than that belongs to an
  earlier, failed attempt, not to this takeoff. Over the 23 takeoffs of 2026-08-07 that burst
  ends 0.1-2.5 s before `ON_FOIL` twenty times and 6.2/8.0/8.7 s before it three times, when
  the board kept accelerating after he stopped pumping -- which is why the window is not the
  watch's live 5 s.

The walk-back stops at a recording gap, at the end of the previous flight (a run cannot reach
back through the flight before it) and at `takeoffMaxRun` seconds.

`pumps_to_takeoff` is then the strokes inside the run, and a takeoff with fewer than
`freeTakeoff` of them is `free`: the rider got up on wind alone, which is a fact about the
conditions rather than about his pumping, and the two are worth separating in any trend.

**Failed attempts.** Pump bursts of `pumpMinStrokes` or more are first chained into
**episodes** -- one continuous effort, ended only by `takeoffAttemptWindow` of no strokes, the
watch's `attemptFailSilence` rule -- because four bursts inside a minute of thrashing are one
failed attempt and counting them as four would flatter nothing and mislead everything. Each
episode is then classified once, and only once: the same ownership discipline `flightend.py`
uses, for the same reason.

``in_flight``   the episode sits entirely inside a flight: pumping to hold or extend a glide,
                a separate metric (`in_flight_strokes`), never a takeoff.
``success``     a flight starts between the first stroke and `takeoffAttemptWindow` after the
                last -- this effort *is* that flight's takeoff run, so it is already counted
                as a flight and is not a second event.
``recovery``    the episode falls inside a detected turn's outcome window: pumping the foil
                back after a jibe touchdown is the turn's business, already scored there.
``failed``      none of the above: he pumped a real burst and did not get up.
``unknown``     the recording does not run gap-free for `takeoffAttemptWindow` past the last
                stroke, so whether a flight followed is unknowable. Excluded from tallies.

**Truncation.** The same honesty rule as the flight ends, at the other end of the flight: when
fewer than `takeoffMinPreWindow` seconds of gap-free record precede the flight start, the run
is not in the data and `pumps_to_takeoff`/`duration_s` are not reported (`truncated`). The
flight itself is still a success -- it demonstrably happened -- only its *cost* is unknown.
On 2026-08-04 pm, which Smart Recording splits into 429 gap-free runs, this is the difference
between a table of real takeoff runs and a table of fictional 1-second ones.

Sources without an accelerometer (native/GPX) degrade instead of failing: the run is the speed
rise alone, stroke counts are `None`, and the failed attempts are invisible -- so the success
rate is reported as `None` rather than as a flattering 100 %.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from .evidence import MPS_TO_KN, OffFoilEvidence, off_foil_evidence
from .filters import CleanTrack
from .flight import Flight, FlightResult
from .pump import PumpTrack
from .turns import Turn

SUCCESS = "success"
FAILED = "failed"
RECOVERY = "recovery"
IN_FLIGHT = "in_flight"
UNKNOWN = "unknown"                        # lookahead cut by a gap: no evidence
EPISODE_OUTCOMES = (SUCCESS, FAILED, RECOVERY, IN_FLIGHT, UNKNOWN)


@dataclass
class TakeoffConfig:
    """docs/algorithms.md "Takeoff analysis" defaults."""

    max_run_s: float = 30.0            # takeoffMaxRun: cap on the pre-flight window
    rise_slack_mps: float = 0.3        # takeoffRiseSlack: wobble allowed in the speed rise
    rest_speed_mps: float = 1.0        # takeoffRestSpeed: at rest -- the run starts here
    attempt_window_s: float = 10.0     # takeoffAttemptWindow: an attempt stays open this
                                       #   long after its last stroke -- ON_FOIL inside it is
                                       #   that attempt's success, silence past it is failure
    min_pre_window_s: float = 3.0      # takeoffMinPreWindow: less visible record => truncated
    free_takeoff_strokes: int = 3      # freeTakeoff: fewer strokes = got up on wind alone
    foil_exit_speed_kmh: float = 8.0   # flight config's exit speed (evidence masks)
    baro_drop_m: float = 25.0          # turnBaroDrop (evidence masks)


@dataclass
class Takeoff:
    """One flight start, with the run that produced it."""

    flight_index: int                  # index into FlightResult.flights
    t: float                           # the flight's start_t (ON_FOIL)
    run_start_t: float                 # first stroke or start of the speed rise
    duration_s: float = 0.0            # run_start_t -> ON_FOIL (0.0 when truncated)
    speed_rise_s: float = 0.0          # the speed-only part of it (the no-accel metric)
    pumps_to_takeoff: int | None = None    # None: no accel stream, or truncated
    cadence_spm: float | None = None   # strokes per minute over the run
    entry_kn: float = 0.0              # Doppler at ON_FOIL: what he took off at
    in_flight_strokes: int | None = None   # pumping *during* the flight -- a separate metric
    free: bool = False                 # fewer than freeTakeoff strokes: wind did the work
    truncated: bool = False            # the record does not reach back over the run
    pre_window_s: float = 0.0          # gap-free record available before the flight start

    @property
    def judged(self) -> bool:
        return not self.truncated


@dataclass
class PumpEpisode:
    """One continuous pumping effort, classified once (module docstring).

    An episode is one or more bursts of at least `pumpMinStrokes` with less than
    `takeoffAttemptWindow` of silence between them -- the watch's rule that an attempt ends only
    when the rider *stops trying*. Four bursts inside a minute of thrashing are one failed
    attempt, not four.
    """

    start_t: float                     # first stroke
    end_t: float                       # last stroke
    strokes: int
    outcome: str                       # success | failed | recovery | in_flight | unknown
    bursts: int = 1                    # bursts merged into this effort
    flight_index: int | None = None    # the flight it produced, or the one it happened in
    turn_index: int | None = None      # the turn whose recovery it is
    lookahead_s: float = 0.0           # gap-free record available past the last stroke

    @property
    def duration_s(self) -> float:
        return self.end_t - self.start_t


@dataclass
class TakeoffAnalysis:
    """Both halves of the picture: the takeoffs that worked and every burst that tried."""

    takeoffs: list[Takeoff] = field(default_factory=list)
    episodes: list[PumpEpisode] = field(default_factory=list)
    has_accel: bool = False
    total_strokes: int | None = None   # every detected stroke, bursts and singletons alike


@dataclass
class TakeoffSummary:
    """Session-level takeoff metrics; the first four mirror FIT session fields 35-38."""

    takeoff_attempts: int = 0          # field 35: successes + failed attempts
    takeoff_successes: int = 0         # field 36: flights -- every one is a takeoff that took
    avg_pumps_to_takeoff: float | None = None    # field 37 (x0.1 on the wire)
    total_pump_strokes: int | None = None        # field 38: every stroke in the session
    success_pct: float | None = None   # None without accel: failures are invisible there
    failed_attempts: int = 0
    unknown_attempts: int = 0          # efforts whose lookahead a gap cut short
    recovery_episodes: int = 0         # pumping back up after a turn: the turn's event
    in_flight_episodes: int = 0
    in_flight_pump_strokes: int | None = None
    runs_judged: int = 0               # flight starts with the run actually in the record
    runs_truncated: int = 0
    free_takeoffs: int = 0             # of the judged runs, those under freeTakeoff strokes
    pumped_takeoffs: int = 0
    median_pumps_to_takeoff: float | None = None
    avg_pumps_when_pumped: float | None = None   # excludes the free ones
    avg_takeoff_s: float | None = None
    median_takeoff_s: float | None = None


def analyze_takeoffs(clean: CleanTrack, flights: FlightResult,
                     turns: list[Turn] | None = None,
                     config: TakeoffConfig | None = None,
                     pump: PumpTrack | None = None) -> TakeoffAnalysis:
    """Takeoff run per flight plus every classified pump burst (see the module docstring).

    `turns` supplies the recovery-pumping exclusion and may be omitted; `pump` is optional
    accelerometer evidence, as in `turns.detect_turns` -- without it the runs are speed-only
    and no attempt can be judged.
    """
    cfg = config or TakeoffConfig()
    ev = off_foil_evidence(clean, flights, cfg.foil_exit_speed_kmh, cfg.baro_drop_m)
    if ev is None:
        return TakeoffAnalysis(has_accel=pump is not None)
    takeoffs = []
    prev_end_t = -np.inf
    for i, f in enumerate(flights.flights):
        takeoffs.append(_takeoff(i, f, ev, cfg, pump, prev_end_t))
        prev_end_t = f.end_t
    total = None if pump is None else int(pump.strokes(float(ev.t[0]),
                                                       float(ev.t[-1])).size)
    return TakeoffAnalysis(takeoffs=takeoffs,
                           episodes=_episodes(ev, flights, turns or [], cfg, pump),
                           has_accel=pump is not None, total_strokes=total)


def summarize_takeoffs(analysis: TakeoffAnalysis) -> TakeoffSummary:
    """Session tallies, FIT-field compatible (see `TakeoffSummary`).

    `takeoff_successes` counts *every* flight, truncated runs included: the flight happened,
    only the cost of getting into it is unknown. The averages, in contrast, are taken over the
    judged runs alone, so a Smart-Recording session cannot dilute them with invented zeros.
    """
    s = TakeoffSummary()
    judged = [k for k in analysis.takeoffs if k.judged]
    s.takeoff_successes = len(analysis.takeoffs)
    s.runs_judged = len(judged)
    s.runs_truncated = len(analysis.takeoffs) - len(judged)

    for ep in analysis.episodes:
        s.failed_attempts += int(ep.outcome == FAILED)
        s.unknown_attempts += int(ep.outcome == UNKNOWN)
        s.recovery_episodes += int(ep.outcome == RECOVERY)
        s.in_flight_episodes += int(ep.outcome == IN_FLIGHT)
    s.takeoff_attempts = s.takeoff_successes + s.failed_attempts
    if analysis.has_accel and s.takeoff_attempts:
        s.success_pct = 100.0 * s.takeoff_successes / s.takeoff_attempts
        s.total_pump_strokes = analysis.total_strokes
        s.in_flight_pump_strokes = sum(k.in_flight_strokes or 0 for k in analysis.takeoffs)

    durations = [k.duration_s for k in judged]
    s.avg_takeoff_s = _mean(durations)
    s.median_takeoff_s = _median(durations)

    pumps = [k.pumps_to_takeoff for k in judged if k.pumps_to_takeoff is not None]
    if pumps:
        s.avg_pumps_to_takeoff = _mean(pumps)
        s.median_pumps_to_takeoff = _median(pumps)
        s.free_takeoffs = sum(1 for k in judged if k.pumps_to_takeoff is not None and k.free)
        s.pumped_takeoffs = len(pumps) - s.free_takeoffs
        s.avg_pumps_when_pumped = _mean([k.pumps_to_takeoff for k in judged
                                         if k.pumps_to_takeoff is not None and not k.free])
    return s


def _takeoff(index: int, flight: Flight, ev: OffFoilEvidence, cfg: TakeoffConfig,
             pump: PumpTrack | None, prev_end_t: float) -> Takeoff:
    """The run behind one flight start (module docstring, "The takeoff run")."""
    t = ev.t
    lo = min(int(np.searchsorted(t, flight.start_t, "left")), len(t) - 1)
    seg_start = _segment_start(ev, lo)
    pre_window_s = float(t[lo] - t[seg_start])
    out = Takeoff(flight_index=index, t=float(flight.start_t), run_start_t=float(t[lo]),
                  entry_kn=float(ev.doppler[lo] * MPS_TO_KN), pre_window_s=pre_window_s)
    if pump is not None:
        out.in_flight_strokes = _burst_strokes(pump, flight.start_t, flight.end_t)
    if pre_window_s < cfg.min_pre_window_s:
        # The flight start sits at (or within a breath of) a segment boundary: the run that
        # produced it is simply not in the recording. Reporting a 1 s takeoff here would be
        # inventing data, so the run is flagged and kept out of every average.
        out.truncated = True
        return out

    win_start_t = max(flight.start_t - cfg.max_run_s, float(t[seg_start]), prev_end_t)
    rise_start_t = _rise_start(ev, lo, seg_start, win_start_t, cfg)
    out.speed_rise_s = float(flight.start_t - rise_start_t)
    out.run_start_t = rise_start_t
    if pump is not None:
        lead = _lead_burst(pump, win_start_t, flight.start_t, cfg)
        if lead is not None:
            out.run_start_t = min(rise_start_t, float(lead[0]))
        out.pumps_to_takeoff = int(pump.strokes(out.run_start_t, flight.start_t).size)
        out.free = out.pumps_to_takeoff < cfg.free_takeoff_strokes
    out.duration_s = float(flight.start_t - out.run_start_t)
    if out.pumps_to_takeoff and out.duration_s > 0:
        out.cadence_spm = 60.0 * out.pumps_to_takeoff / out.duration_s
    return out


def _episodes(ev: OffFoilEvidence, flights: FlightResult, turns: list[Turn],
              cfg: TakeoffConfig, pump: PumpTrack | None) -> list[PumpEpisode]:
    """Group the qualifying bursts into efforts and classify each exactly once."""
    if pump is None or len(ev) == 0:
        return []
    bursts = [b for b in pump.bursts(float(ev.t[0]), float(ev.t[-1]))
              if len(b) >= pump.config.min_strokes]
    return [_classify(ep, ev, flights, turns, cfg) for ep in _group(bursts, flights, cfg)]


def _group(bursts: list[np.ndarray], flights: FlightResult,
           cfg: TakeoffConfig) -> list[PumpEpisode]:
    """Chain bursts into episodes: silence below `takeoffAttemptWindow` keeps one going.

    Two things break a chain whatever the silence: a burst that lies wholly inside a flight
    (that is in-flight pumping, a different act), and a flight *starting* between two bursts
    (the earlier effort demonstrably worked, so the later one is a new attempt).
    """
    out: list[PumpEpisode] = []
    for b in bursts:
        first, last, n = float(b[0]), float(b[-1]), int(len(b))
        in_flight = _flight_containing(flights, first, last) is not None
        joins = (out and not in_flight and not _prev_in_flight(out[-1], flights)
                 and first - out[-1].end_t < cfg.attempt_window_s
                 and not _flight_starts_between(flights, out[-1].end_t, first))
        if not joins:
            out.append(PumpEpisode(start_t=first, end_t=last, strokes=n, outcome=FAILED))
            continue
        out[-1].end_t = last
        out[-1].strokes += n
        out[-1].bursts += 1
    return out


def _classify(ep: PumpEpisode, ev: OffFoilEvidence, flights: FlightResult,
              turns: list[Turn], cfg: TakeoffConfig) -> PumpEpisode:
    """The ladder of the module docstring, applied to one pumping effort."""
    ep.lookahead_s = _lookahead_s(ev, ep.end_t, cfg.attempt_window_s)
    inside = _flight_containing(flights, ep.start_t, ep.end_t)
    produced = _flight_produced(flights, ep.start_t, ep.end_t, cfg.attempt_window_s)
    if inside is not None:
        ep.outcome, ep.flight_index = IN_FLIGHT, inside
    elif produced is not None:
        ep.outcome, ep.flight_index = SUCCESS, produced
    elif (owner := _turn_owner(turns, ep.start_t, ep.end_t)) is not None:
        ep.outcome, ep.turn_index = RECOVERY, owner
    elif ep.lookahead_s < cfg.attempt_window_s:
        ep.outcome = UNKNOWN
    return ep


def _prev_in_flight(ep: PumpEpisode, flights: FlightResult) -> bool:
    return _flight_containing(flights, ep.start_t, ep.end_t) is not None


def _flight_starts_between(flights: FlightResult, a: float, b: float) -> bool:
    return any(a < f.start_t <= b for f in flights.flights)


def _segment_start(ev: OffFoilEvidence, i: int) -> int:
    """First index of the gap-free segment holding sample `i`."""
    j = i
    while j > 0 and not ev.gap[j]:
        j -= 1
    return j


def _rise_start(ev: OffFoilEvidence, lo: int, seg_start: int, win_start_t: float,
                cfg: TakeoffConfig) -> float:
    """Walk back from the flight start while the speed was still climbing toward it.

    A sample counts as part of the rise when it is no more than `takeoffRiseSlack` above the
    slowest sample seen so far going back -- monotone enough to be a takeoff, loose enough to
    survive the wobble of a water start. Read on the Doppler channel, which is what defined
    the flight boundary in the first place.

    The walk also stops on the first sample at or below `takeoffRestSpeed`, which is *kept*
    as the run start: that is the rider sitting on the board before he started, and without
    this test a slack-tolerant walk-back would swallow the whole rest -- a flat trace is
    "non-increasing" too. `takeoffMaxRun` is the backstop for a long slog that never rests.
    """
    i = lo
    ref = float(ev.doppler[lo])
    while i - 1 >= seg_start and ev.t[i - 1] >= win_start_t:
        v = float(ev.doppler[i - 1])
        if v > ref + cfg.rise_slack_mps:
            break
        ref = min(ref, v)
        i -= 1
        if v <= cfg.rest_speed_mps:
            break
    return float(ev.t[i])


def _lead_burst(pump: PumpTrack, win_start_t: float, start_t: float,
                cfg: TakeoffConfig) -> np.ndarray | None:
    """The burst that led into this flight: the last qualifying one close enough to it."""
    for b in reversed(pump.bursts(win_start_t, start_t)):
        if len(b) < pump.config.min_strokes:
            continue
        return b if b[-1] >= start_t - cfg.attempt_window_s else None
    return None


def _burst_strokes(pump: PumpTrack, start_t: float, end_t: float) -> int:
    """Strokes in [start_t, end_t] that belong to a burst of at least `pumpMinStrokes`."""
    return int(sum(len(b) for b in pump.bursts(start_t, end_t)
                   if len(b) >= pump.config.min_strokes))


def _flight_containing(flights: FlightResult, first: float, last: float) -> int | None:
    """Index of the flight that holds the whole burst -- pumping while already flying."""
    return next((i for i, f in enumerate(flights.flights)
                 if f.start_t <= first and last <= f.end_t), None)


def _flight_produced(flights: FlightResult, first: float, last: float,
                     window_s: float) -> int | None:
    """Index of the flight this burst pumped into, if one starts soon enough after it.

    The flight may start *during* the effort (he keeps pumping through the takeoff) or up to
    `takeoffAttemptWindow` after its last stroke -- the accelerating board carries on after the
    pumping stops, and the flight start is only confirmed `entryHold` later.
    """
    return next((i for i, f in enumerate(flights.flights)
                 if first <= f.start_t <= last + window_s), None)


def _turn_owner(turns: list[Turn], first: float, last: float) -> int | None:
    """Index of the turn whose outcome window holds the burst: recovery pumping.

    The same window `flightend.py` assigns ownership over (`start` -> `end + outcomeWindow`),
    so the two modules agree by construction on which events a turn already explains.
    """
    return next((k for k, turn in enumerate(turns)
                 if turn.start_t <= first and last <= turn.end_t + turn.outcome_window_s),
                None)


def _lookahead_s(ev: OffFoilEvidence, from_t: float, cap_s: float) -> float:
    """Gap-free recorded time available after `from_t`, capped at `cap_s`.

    Zero when the stroke itself falls inside a recording gap (the accelerometer keeps logging
    when the GPS drops out), which is exactly the case where nothing can be concluded. The
    walk stops on the *first sample at or past* the cap, not on the last one below it, so a
    1 Hz record whose samples never land exactly on `from_t + cap_s` still reports the full
    window instead of 14.6 s of it.
    """
    t, gap = ev.t, ev.gap
    i = int(np.searchsorted(t, from_t, "left"))
    if i >= len(t) or (i > 0 and gap[i]):
        return 0.0
    j = i
    while t[j] < from_t + cap_s and j + 1 < len(t) and not gap[j + 1]:
        j += 1
    return float(min(t[j] - from_t, cap_s))


def _mean(values) -> float | None:
    return float(np.mean(values)) if len(values) else None


def _median(values) -> float | None:
    return float(np.median(values)) if len(values) else None


__all__ = ["EPISODE_OUTCOMES", "FAILED", "IN_FLIGHT", "RECOVERY", "SUCCESS", "UNKNOWN",
           "PumpEpisode", "Takeoff", "TakeoffAnalysis", "TakeoffConfig", "TakeoffSummary",
           "analyze_takeoffs", "summarize_takeoffs"]
