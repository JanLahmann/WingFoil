"""Flight-end classification on constructed tracks.

Tracks are integrated from a (course, speed) profile exactly as in test_turns.py, so the
flight the segmenter finds and the loss that follows it are both exact. Most cases sail a
straight line -- the point of this module is the losses that happen *outside* a maneuver.
"""

from pathlib import Path

import numpy as np
import pytest

from wingfoil_lab.evidence import off_foil_evidence
from wingfoil_lab.filters import clean, clean_from_arrays
from wingfoil_lab.flight import segment_flights
from wingfoil_lab.flightend import (FELL_IN, FLIGHT_END_OUTCOMES, GLIDE_OUT, TOUCHDOWN,
                                    UNKNOWN, FlightEndConfig, classify_flight_ends,
                                    split_outcomes, summarize_flight_ends)
from wingfoil_lab.parse import parse_fit
from wingfoil_lab.pump import pump_track, pump_track_from_arrays
from wingfoil_lab.takeoff import analyze_takeoffs
from wingfoil_lab.turns import detect_turns, summarize_turns
from wingfoil_lab.wind import WindEstimate, estimate_wind

FIXTURES = Path(__file__).resolve().parents[2] / "fixtures"
TODAY = FIXTURES / "sessions/ciq/2026-08-07-0754_nago-torbole-windsurfen_ciq.fit"

WIND_N = WindEstimate(dir_deg=0.0, confidence=1.0, source="estimate", axis_deg=0.0)


def _track(course_deg, speed_mps, hz=1.0, alt_m=None, t=None):
    """Integrate (course, speed) samples into a CleanTrack (course in compass degrees)."""
    course = np.asarray(course_deg, float)
    v = np.asarray(speed_mps, float)
    t = np.arange(len(course), dtype=float) / hz if t is None else np.asarray(t, float)
    dt = np.concatenate([np.diff(t), [1.0 / hz]])
    dx = np.sin(np.radians(course)) * v * dt
    dy = np.cos(np.radians(course)) * v * dt
    x = np.concatenate([[0.0], np.cumsum(dx)[:-1]])
    y = np.concatenate([[0.0], np.cumsum(dy)[:-1]])
    return clean_from_arrays(t, v, x=x, y=y, alt_m=alt_m)


def _reach(*parts):
    """A straight 090 reach whose speed follows the concatenated `parts`."""
    speed = [v for part in parts for v in part]
    return [90.0] * len(speed), speed


def _fly(n, speed=6.0):
    return [speed] * n


# A dip only becomes a *flight end* once it breaks the flight, which needs `exitHold` (3 s)
# below `foilExitSpeed` (2.22 m/s). Shorter dips stay inside the flight and are the turn
# channel's business, not this module's -- so a settle at 1.5 m/s precedes every stop here.
SETTLE = [1.5] * 4


def _ends(course, speed, alt_m=None, t=None, turns=None, pump=None, config=None):
    ct = _track(course, speed, alt_m=alt_m, t=t)
    flights = segment_flights(ct)
    return ct, flights, classify_flight_ends(ct, flights, turns, config, pump)


# --- the three verdicts ------------------------------------------------------------------

def test_glide_out_is_coming_off_the_foil_without_ever_stopping():
    """Settled onto the board and slogged on at 1.8 m/s: off the foil, still making way."""
    ct, flights, ends = _ends(*_reach(_fly(40), _fly(25, 1.8)))
    assert flights.flight_count == 1
    assert len(ends) == 1
    assert ends[0].outcome == GLIDE_OUT
    assert ends[0].stopped_s == 0.0
    assert ends[0].min_speed_mps > FlightEndConfig().stop_speed_floor_mps
    assert not ends[0].truncated and not ends[0].in_turn


def test_touchdown_is_a_brief_stop_the_rider_starts_out_of():
    """2 s at a standstill, then straight back onto the foil: a touchdown, not a swim.

    The second flight runs to the end of the recording, so its own end is `unknown` -- the
    watch was stopped while he was still going, and nothing is known about what followed.
    """
    _, flights, ends = _ends(*_reach(_fly(40), SETTLE, _fly(3, 0.5), _fly(40)))
    assert flights.flight_count == 2                  # he got going again
    assert [e.outcome for e in ends] == [TOUCHDOWN, UNKNOWN]
    assert not ends[0].borderline
    assert ends[0].stopped_s == pytest.approx(2.0)


def test_fell_in_is_a_long_stop():
    _, _, ends = _ends(*_reach(_fly(40), _fly(15, 0.3), _fly(40)))
    assert ends[0].outcome == FELL_IN and not ends[0].borderline
    assert ends[0].stopped_s == pytest.approx(14.0)
    assert ends[0].off_foil_s >= ends[0].stopped_s


def test_stop_between_the_two_thresholds_is_a_borderline_touchdown():
    _, _, ends = _ends(*_reach(_fly(40), _fly(5, 0.6), _fly(40)))
    assert ends[0].outcome == TOUCHDOWN and ends[0].borderline
    assert ends[0].stopped_s == pytest.approx(4.0)


def test_the_glide_touchdown_line_is_reaching_the_floor_not_dwelling_below_it():
    """One sub-floor sample is still a touchdown: at 2 s cadence a real stop measures 0 s.

    Native Smart Recording tracks are the reason -- `longest_stop` needs two consecutive
    sub-floor samples, so a duration test would call a genuine standstill a glide-out.
    """
    t = np.arange(0.0, 120.0, 2.0)                    # 2 s cadence, as Garmin writes it
    speed = np.concatenate([np.full(30, 6.0), [1.5, 1.5, 0.5], np.full(27, 6.0)])
    _, _, ends = _ends([90.0] * len(t), speed, t=t)
    assert ends[0].stopped_s == 0.0                   # the cadence cannot resolve it...
    assert ends[0].min_speed_mps == pytest.approx(0.5)
    assert ends[0].outcome == TOUCHDOWN               # ...but he plainly stopped


def test_thresholds_are_tunable():
    course, speed = _reach(_fly(40), _fly(5, 0.6), _fly(40))
    strict = FlightEndConfig(touchdown_max_stop_s=1.0, fall_stop_s=2.0)
    assert _ends(course, speed, config=strict)[2][0].outcome == FELL_IN
    lenient = FlightEndConfig(stop_speed_floor_mps=0.4)   # the dip is no longer a stop
    assert _ends(course, speed, config=lenient)[2][0].outcome == GLIDE_OUT


# --- barometer and accelerometer, exactly as in the turns ---------------------------------

def test_wrist_submersion_makes_a_short_stop_a_fall():
    course, speed = _reach(_fly(40), SETTLE, _fly(3, 0.5), _fly(40))
    assert _ends(course, speed)[2][0].outcome == TOUCHDOWN

    alt = np.full(len(course), 70.0)
    alt[44:48] = [-180.0, -230.0, -210.0, -190.0]     # 30 cm of water ~ a 250 m "drop"
    ends = _ends(course, speed, alt_m=alt)[2]
    assert ends[0].submerged and ends[0].outcome == FELL_IN


def test_missing_altitude_channel_degrades_to_speed_only():
    ends = _ends(*_reach(_fly(40), _fly(15, 0.3), _fly(40)))[2]
    assert ends[0].outcome == FELL_IN and not ends[0].submerged


def _pump_stream(t0, t1, hz=25.0, cadence_hz=1.2, amp_g=0.6):
    t = np.arange(0.0, 200.0, 1.0 / hz)
    mag = np.full_like(t, 1.0)
    on = (t >= t0) & (t <= t1)
    mag[on] += amp_g * np.sin(2 * np.pi * cadence_hz * t[on])
    return t, mag


def test_pumping_promotes_a_glide_out_to_a_touchdown():
    """He never stopped -- but the wrist says he was pumping to get back up, so he fell off
    the foil rather than choosing to settle."""
    course, speed = _reach(_fly(40), _fly(25, 1.8))
    assert _ends(course, speed)[2][0].outcome == GLIDE_OUT

    pump = pump_track_from_arrays(*_pump_stream(40.0, 52.0))
    ends = _ends(course, speed, pump=pump)[2]
    assert ends[0].pumped and ends[0].outcome == TOUCHDOWN


def test_pumping_never_demotes_a_fall():
    course, speed = _reach(_fly(40), _fly(15, 0.3), _fly(40))
    pump = pump_track_from_arrays(*_pump_stream(40.0, 55.0))
    assert _ends(course, speed, pump=pump)[2][0].outcome == FELL_IN


# --- the recording, not the flight, ended -------------------------------------------------

def test_a_flight_cut_by_a_recording_gap_is_unknown_not_a_glide_out():
    """Smart Recording drops out mid-flight at 6 m/s: nothing is known about what followed.

    Classifying on the visible evidence would call this a glide-out and invent an event
    that never happened -- 111 of them on 2026-08-04 pm alone.
    """
    course, speed = _reach(_fly(40), _fly(20), _fly(20, 1.8))
    t = np.arange(len(course), dtype=float)
    t[40:] += 60.0                                    # a minute of missing samples
    ct, flights, ends = _ends(course, speed, t=t)
    assert flights.flight_count == 2
    assert ends[0].outcome == UNKNOWN and ends[0].truncated
    assert ends[0].window_s == 0.0
    assert ends[1].outcome == GLIDE_OUT                # the second flight ends for real

    counts = summarize_flight_ends(ends).all_ends
    assert counts.unknown == 1
    assert counts.total == 1                          # the truncated end is not tallied


def test_every_outcome_is_one_of_the_declared_four():
    _, _, ends = _ends(*_reach(_fly(40), _fly(15, 0.3), _fly(40)))
    assert all(e.outcome in FLIGHT_END_OUTCOMES for e in ends)


# --- ownership: a turn's fall is not also a straight-line fall -----------------------------

def _jibe_then(dip, tail=40):
    """A clean jibe carried at speed, then `dip`, then a leg -- test_turns' shape."""
    ramp = list(np.linspace(90.0, 270.0, 7))
    course = [90.0] * 40 + ramp + [270.0] * (2 + len(dip) + tail)
    speed = ([6.0] * 40 + list(np.linspace(6.0, 5.0, 7)) + [5.0] * 2
             + list(dip) + [6.0] * tail)
    return course, speed


def test_a_fall_inside_a_turn_belongs_to_the_turn_and_is_not_counted_twice():
    course, speed = _jibe_then([0.3] * 15)
    ct = _track(course, speed)
    flights = segment_flights(ct)
    turns = detect_turns(ct, flights, WIND_N)
    assert len(turns) == 1 and turns[0].outcome == FELL_IN

    ends = classify_flight_ends(ct, flights, turns)
    assert ends[0].outcome == FELL_IN
    assert ends[0].in_turn and ends[0].owned_by_turn == 0

    summary = summarize_flight_ends(ends)
    assert summary.in_turn.fell_in == 1
    assert summary.straight.fell_in == 0              # the double count that must not happen
    assert summary.all_ends.fell_in == 1


def test_a_straight_line_fall_is_owned_by_nobody():
    ct = _track(*_reach(_fly(40), _fly(15, 0.3), _fly(40)))
    flights = segment_flights(ct)
    turns = detect_turns(ct, flights, WIND_N)
    assert turns == []                                # a straight reach: no maneuver at all

    summary = summarize_flight_ends(classify_flight_ends(ct, flights, turns))
    assert summary.straight.fell_in == 1
    assert summary.in_turn.total == 0


def test_ownership_needs_the_turn_list_and_defaults_to_unowned():
    course, speed = _jibe_then([0.3] * 15)
    ct = _track(course, speed)
    flights = segment_flights(ct)
    assert not classify_flight_ends(ct, flights)[0].in_turn      # no turns passed


def test_the_split_separates_turn_falls_from_straight_line_falls():
    """One jibe swum, then a straight-line swim later: two falls, one of each kind."""
    course, speed = _jibe_then([0.3] * 15, tail=60)
    course = list(course) + [270.0] * 55
    speed = list(speed) + [0.3] * 15 + [6.0] * 40
    ct = _track(course, speed)
    flights = segment_flights(ct)
    turns = detect_turns(ct, flights, WIND_N)
    ends = classify_flight_ends(ct, flights, turns)
    assert [e.outcome for e in ends] == [FELL_IN, FELL_IN, UNKNOWN]
    assert [e.in_turn for e in ends] == [True, False, False]

    split = split_outcomes(summarize_turns(turns), summarize_flight_ends(ends))
    assert split.turn_falls == 1 and split.straight_falls == 1
    assert split.falls == 2


def test_counts_add_up():
    course, speed = _reach(_fly(40), _fly(15, 0.3), _fly(40), _fly(20, 1.8))
    ct = _track(course, speed)
    flights = segment_flights(ct)
    summary = summarize_flight_ends(classify_flight_ends(ct, flights))
    for counts in (summary.all_ends, summary.straight, summary.in_turn):
        assert counts.total == counts.glide_out + counts.touchdown + counts.fell_in
    assert summary.all_ends.total == summary.straight.total + summary.in_turn.total


# --- real fixture --------------------------------------------------------------------------

@pytest.mark.skipif(not TODAY.exists(), reason="ciq fixture missing")
def test_real_session_flight_ends():
    """2026-08-07 Torbole: a learning day -- every flight ended in a stop, none glided out."""
    cfg = FlightEndConfig()
    track = parse_fit(TODAY)
    ct = clean(track)
    flights = segment_flights(ct)
    wind = estimate_wind(ct, flights)
    pump = pump_track(track)
    turns = detect_turns(ct, flights, wind, pump=pump)
    ends = classify_flight_ends(ct, flights, turns, pump=pump)

    assert len(ends) == flights.flight_count
    for end, flight in zip(ends, flights.flights):
        assert end.t == flight.end_t
        assert end.outcome in FLIGHT_END_OUTCOMES
        assert end.truncated == (end.outcome == UNKNOWN)
        if end.outcome == FELL_IN:
            assert end.stopped_s > cfg.fall_stop_s or end.submerged
            assert not end.borderline
        if end.outcome == GLIDE_OUT:
            assert end.min_speed_mps >= cfg.stop_speed_floor_mps
        if end.borderline:
            assert end.outcome == TOUCHDOWN
            assert cfg.touchdown_max_stop_s < end.stopped_s <= cfg.fall_stop_s
        if end.in_turn:
            turn = turns[end.owned_by_turn]
            assert turn.start_t <= end.t <= turn.end_t + turn.outcome_window_s

    summary = summarize_flight_ends(ends)
    assert summary.all_ends.total + summary.all_ends.unknown == flights.flight_count
    # 1 Hz CIQ recording: only the two flights the session itself cut are evidence-free.
    assert summary.all_ends.unknown <= 2
    assert summary.all_ends.fell_in > summary.all_ends.glide_out

    split = split_outcomes(summarize_turns(turns), summary)
    assert split.falls == split.turn_falls + split.straight_falls
    assert split.straight_falls >= 1        # falls outside a maneuver are real and counted
    assert split.turn_falls >= split.straight_falls


def test_shared_off_foil_evidence_matches_building_it_per_consumer():
    """The pipeline builds the evidence once and hands it to all three outcome passes.

    `evidence.OffFoilEvidence` is read-only, so sharing it must be bit-identical to letting
    every consumer build its own -- this pins that contract (goldens depend on it).
    """
    course, speed = _reach(_fly(40), SETTLE, _fly(6, 0.4), _fly(40), SETTLE, _fly(20, 0.3))
    ct = _track(course, speed)
    flights = segment_flights(ct)
    cfg = FlightEndConfig()
    ev = off_foil_evidence(ct, flights, cfg.foil_exit_speed_kmh, cfg.baro_drop_m)
    assert ev is not None

    own_turns = detect_turns(ct, flights, WIND_N)
    shared_turns = detect_turns(ct, flights, WIND_N, evidence=ev)
    assert shared_turns == own_turns

    assert (classify_flight_ends(ct, flights, own_turns, evidence=ev)
            == classify_flight_ends(ct, flights, own_turns))
    assert (analyze_takeoffs(ct, flights, own_turns, evidence=ev)
            == analyze_takeoffs(ct, flights, own_turns))
