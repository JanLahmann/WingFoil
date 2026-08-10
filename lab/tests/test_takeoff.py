"""Takeoff analysis on constructed tracks: the flight *start* and the attempts that failed.

Tracks are integrated from a (course, speed) profile exactly as in test_flightend.py, and the
wrist stream is a sine burst at pumping cadence exactly as in test_pump.py, so both channels
of every case are exact and the expected stroke counts are arithmetic, not guesses.
"""

from pathlib import Path

import numpy as np
import pandas as pd
import pytest

from wingfoil_lab.filters import clean, clean_from_arrays
from wingfoil_lab.flight import segment_flights
from wingfoil_lab.parse import RawTrack, parse_fit
from wingfoil_lab.pump import PumpConfig, pump_track, pump_track_from_arrays
from wingfoil_lab.takeoff import (EPISODE_OUTCOMES, FAILED, IN_FLIGHT, RECOVERY, SUCCESS,
                                  UNKNOWN, TakeoffConfig, analyze_takeoffs,
                                  summarize_takeoffs)
from wingfoil_lab.turns import detect_turns
from wingfoil_lab.wind import WindEstimate, estimate_wind

FIXTURES = Path(__file__).resolve().parents[2] / "fixtures"
TODAY = FIXTURES / "sessions/ciq/2026-08-07-0754_nago-torbole-windsurfen_ciq.fit"

WIND_N = WindEstimate(dir_deg=0.0, confidence=1.0, source="estimate", axis_deg=0.0)


def _track(course_deg, speed_mps, hz=1.0, t=None):
    """Integrate (course, speed) samples into a CleanTrack (course in compass degrees)."""
    course = np.asarray(course_deg, float)
    v = np.asarray(speed_mps, float)
    t = np.arange(len(course), dtype=float) / hz if t is None else np.asarray(t, float)
    dt = np.concatenate([np.diff(t), [1.0 / hz]])
    dx = np.sin(np.radians(course)) * v * dt
    dy = np.cos(np.radians(course)) * v * dt
    x = np.concatenate([[0.0], np.cumsum(dx)[:-1]])
    y = np.concatenate([[0.0], np.cumsum(dy)[:-1]])
    return clean_from_arrays(t, v, x=x, y=y)


def _reach(*parts):
    """A straight 090 reach whose speed follows the concatenated `parts`."""
    speed = [v for part in parts for v in part]
    return [90.0] * len(speed), speed


def _rest(n, speed=0.5):
    return [speed] * n


def _ramp(n=5, lo=1.0, hi=6.0):
    """The water start: speed climbing through `foilEntrySpeed` (3.33 m/s)."""
    return list(np.linspace(lo, hi, n))


def _fly(n, speed=6.0):
    return [speed] * n


def _wrist(duration, *bursts, hz=25.0, cadence_hz=1.2, amp_g=0.6):
    """A pump track over [0, duration] carrying a sine burst for each (t0, t1) given."""
    t = np.arange(0.0, duration, 1.0 / hz)
    mag = np.ones_like(t)
    for t0, t1 in bursts:
        on = (t >= t0) & (t <= t1)
        mag[on] += amp_g * np.sin(2 * np.pi * cadence_hz * t[on])
    return pump_track_from_arrays(t, mag)


def _analyze(course, speed, t=None, turns=None, pump=None, config=None):
    ct = _track(course, speed, t=t)
    flights = segment_flights(ct)
    return flights, analyze_takeoffs(ct, flights, turns, config, pump)


# The canonical successful takeoff: 20 s sitting on the board, a pump burst, the speed rise
# through the entry threshold, and a flight. The flight starts at t = 22 (first sample at or
# above 12 km/h that is held for `entryHold`), the rise starts at t = 20 (the last sample at
# rest), and the burst runs 10 -> 19 s, which is inside `takeoffAttemptWindow` of the start.
TAKEOFF = _reach(_rest(20), _ramp(), _fly(60))
BURST = (10.0, 19.0)


# --- the takeoff run ----------------------------------------------------------------------

def test_a_pumped_takeoff_reports_its_strokes_duration_and_entry():
    flights, a = _analyze(*TAKEOFF, pump=_wrist(85.0, BURST))
    assert flights.flight_count == 1
    assert len(a.takeoffs) == 1

    k = a.takeoffs[0]
    assert k.t == flights.flights[0].start_t == 22.0
    assert not k.truncated and k.judged
    assert k.pumps_to_takeoff == pytest.approx(11, abs=3)      # 9 s at 1.2 Hz
    assert k.run_start_t == pytest.approx(BURST[0], abs=1.0)   # the run opens on the burst...
    assert k.speed_rise_s == pytest.approx(2.0)                # ...well before the speed rise
    assert k.duration_s == pytest.approx(22.0 - BURST[0], abs=1.0)
    assert k.cadence_spm == pytest.approx(60 * 1.2, rel=0.35)
    assert k.entry_kn == pytest.approx(3.5 * 1.9438445, abs=0.01)
    assert not k.free


def test_the_run_starts_where_the_rider_stopped_resting_not_when_he_sat_down():
    """A flat trace is "non-increasing" too: without the rest floor the walk-back would
    swallow all 20 s of sitting still and call it a 22 s takeoff."""
    _, a = _analyze(*TAKEOFF)
    assert a.takeoffs[0].run_start_t == 20.0
    assert a.takeoffs[0].duration_s == pytest.approx(2.0)


def test_a_flight_the_wind_did_the_work_for_is_free():
    """Speed rises to flying with a silent wrist: 0 strokes, flagged `free`."""
    _, a = _analyze(*TAKEOFF, pump=_wrist(85.0))
    k = a.takeoffs[0]
    assert k.pumps_to_takeoff == 0 and k.free
    assert k.duration_s == pytest.approx(k.speed_rise_s)
    assert summarize_takeoffs(a).free_takeoffs == 1


def test_a_burst_too_long_before_the_flight_is_not_its_takeoff_run():
    """The run only claims a burst within `takeoffAttemptWindow` of the flight start."""
    _, a = _analyze(*TAKEOFF, pump=_wrist(85.0, (0.0, 5.0)))   # 17 s before the start
    k = a.takeoffs[0]
    assert k.pumps_to_takeoff == 0 and k.run_start_t == 20.0
    assert summarize_takeoffs(a).failed_attempts == 1          # it was its own attempt


def test_the_run_cannot_reach_back_through_the_previous_flight():
    course, speed = _reach(_rest(20), _ramp(), _fly(40), _rest(8), _ramp(), _fly(40))
    flights, a = _analyze(course, speed)
    assert flights.flight_count == 2
    assert a.takeoffs[1].run_start_t >= flights.flights[0].end_t


# --- failed attempts, and everything that must not be counted as one -----------------------

def test_a_burst_that_leads_nowhere_is_a_failed_attempt():
    course, speed = _reach(_rest(20), _ramp(), _fly(40), _rest(60))
    flights, a = _analyze(course, speed, pump=_wrist(125.0, BURST, (75.0, 85.0)))
    assert flights.flight_count == 1

    outcomes = [e.outcome for e in a.episodes]
    assert outcomes == [SUCCESS, FAILED]
    s = summarize_takeoffs(a)
    assert (s.takeoff_successes, s.failed_attempts, s.takeoff_attempts) == (1, 1, 2)
    assert s.success_pct == pytest.approx(50.0)


def test_bursts_a_few_seconds_apart_are_one_attempt_not_four():
    """`takeoffAttemptWindow` of silence ends an attempt -- a minute of thrashing is one."""
    course, speed = _reach(_rest(20), _ramp(), _fly(40), _rest(80))
    pump = _wrist(145.0, BURST, (75.0, 80.0), (85.0, 90.0), (95.0, 100.0))
    _, a = _analyze(course, speed, pump=pump)
    failed = [e for e in a.episodes if e.outcome == FAILED]
    assert len(failed) == 1
    assert failed[0].bursts == 3
    assert failed[0].strokes > 12
    assert summarize_takeoffs(a).failed_attempts == 1


def test_pumping_inside_a_flight_is_a_separate_metric_not_an_attempt():
    course, speed = _reach(_rest(20), _ramp(), _fly(80))
    _, a = _analyze(course, speed, pump=_wrist(105.0, BURST, (50.0, 60.0)))
    assert [e.outcome for e in a.episodes] == [SUCCESS, IN_FLIGHT]
    assert a.takeoffs[0].in_flight_strokes == pytest.approx(12, abs=3)

    s = summarize_takeoffs(a)
    assert s.failed_attempts == 0 and s.takeoff_attempts == 1
    assert s.in_flight_episodes == 1
    assert s.in_flight_pump_strokes == a.takeoffs[0].in_flight_strokes
    assert s.total_pump_strokes > s.in_flight_pump_strokes    # the takeoff's strokes too


def _jibe_then(dip, tail=40):
    """A clean jibe carried at speed, then `dip`, then a leg -- test_flightend's shape."""
    ramp = list(np.linspace(90.0, 270.0, 7))
    course = [90.0] * 40 + ramp + [270.0] * (2 + len(dip) + tail)
    speed = ([6.0] * 40 + list(np.linspace(6.0, 5.0, 7)) + [5.0] * 2
             + list(dip) + [6.0] * tail)
    return course, speed


def test_pumping_back_up_after_a_jibe_belongs_to_the_turn_not_to_the_takeoffs():
    """Recovery pumping inside a turn's outcome window is already scored as that turn."""
    course, speed = _jibe_then([0.3] * 30)
    ct = _track(course, speed)
    flights = segment_flights(ct)
    turns = detect_turns(ct, flights, WIND_N)
    assert len(turns) == 1

    pump = _wrist(len(course) + 5.0, (52.0, 58.0))     # early in the dip, 20 s before flying
    owned = analyze_takeoffs(ct, flights, turns, pump=pump)
    assert [e.outcome for e in owned.episodes] == [RECOVERY]
    assert owned.episodes[0].turn_index == 0
    assert summarize_takeoffs(owned).failed_attempts == 0
    assert summarize_takeoffs(owned).recovery_episodes == 1

    # Without the turn list the very same burst reads as a failed takeoff attempt: the
    # ownership rule is what keeps the two channels from counting one event twice.
    assert [e.outcome for e in analyze_takeoffs(ct, flights, pump=pump).episodes] == [FAILED]


# --- degradation: no accelerometer, and a recording that does not cover the run ------------

def test_a_source_without_accel_degrades_to_a_speed_only_run():
    flights, a = _analyze(*TAKEOFF)
    k = a.takeoffs[0]
    assert not a.has_accel
    assert k.pumps_to_takeoff is None and k.in_flight_strokes is None
    assert k.duration_s == k.speed_rise_s == pytest.approx(2.0)
    assert a.episodes == []

    s = summarize_takeoffs(a)
    assert s.takeoff_successes == 1
    assert s.takeoff_attempts == 1              # failures are invisible without the wrist...
    assert s.success_pct is None                # ...so no flattering 100 % is reported
    assert s.avg_pumps_to_takeoff is None and s.total_pump_strokes is None
    assert s.avg_takeoff_s == pytest.approx(2.0)


def test_a_flight_start_cut_off_by_a_recording_gap_is_truncated_not_a_one_second_takeoff():
    """Smart Recording resumes mid-water-start: the run is simply not in the data."""
    course, speed = _reach(_rest(20), _ramp(), _fly(60))
    t = np.arange(len(course), dtype=float)
    t[21:] += 60.0                              # the gap lands one sample into the ramp
    flights, a = _analyze(course, speed, t=t)
    assert flights.flight_count == 1

    k = a.takeoffs[0]
    assert k.truncated and not k.judged
    assert k.pumps_to_takeoff is None
    assert k.duration_s == 0.0 and k.pre_window_s < TakeoffConfig().min_pre_window_s

    s = summarize_takeoffs(a)
    assert s.takeoff_successes == 1             # the flight happened; only its cost is unknown
    assert (s.runs_judged, s.runs_truncated) == (0, 1)
    assert s.avg_takeoff_s is None and s.avg_pumps_to_takeoff is None


def test_an_attempt_the_recording_stops_on_is_unknown_not_a_failure():
    """No gap-free lookahead past the last stroke ⇒ nothing is known about what followed."""
    course, speed = _reach(_rest(20), _ramp(), _fly(40), _rest(10))
    _, a = _analyze(course, speed, pump=_wrist(75.0, BURST, (66.0, 71.0)))
    assert [e.outcome for e in a.episodes] == [SUCCESS, UNKNOWN]

    s = summarize_takeoffs(a)
    assert s.unknown_attempts == 1
    assert s.failed_attempts == 0 and s.takeoff_attempts == 1   # kept out of the tally
    assert s.success_pct == pytest.approx(100.0)


# --- summary, config -----------------------------------------------------------------------

def test_every_episode_outcome_is_one_of_the_declared_five():
    course, speed = _reach(_rest(20), _ramp(), _fly(40), _rest(60))
    _, a = _analyze(course, speed, pump=_wrist(125.0, BURST, (75.0, 85.0)))
    assert all(e.outcome in EPISODE_OUTCOMES for e in a.episodes)
    assert all(e.strokes >= PumpConfig().min_strokes for e in a.episodes)


def test_attempts_are_successes_plus_failures_and_nothing_else():
    course, speed = _reach(_rest(20), _ramp(), _fly(40), _rest(60))
    _, a = _analyze(course, speed, pump=_wrist(125.0, BURST, (75.0, 85.0)))
    s = summarize_takeoffs(a)
    assert s.takeoff_attempts == s.takeoff_successes + s.failed_attempts
    assert s.takeoff_successes == s.runs_judged + s.runs_truncated
    assert s.success_pct == pytest.approx(100.0 * s.takeoff_successes / s.takeoff_attempts)


def test_thresholds_are_tunable():
    pump = _wrist(85.0, BURST)                    # last stroke ~3 s before the flight start
    assert _analyze(*TAKEOFF, pump=pump)[1].takeoffs[0].pumps_to_takeoff > 4
    strict = TakeoffConfig(attempt_window_s=1.0)  # too far back to be this flight's run
    _, a = _analyze(*TAKEOFF, pump=pump, config=strict)
    assert a.takeoffs[0].pumps_to_takeoff == 0
    assert [e.outcome for e in a.episodes] == [FAILED]


def test_an_empty_track_analyzes_to_nothing():
    ct = clean(RawTrack(path="<empty>", records=pd.DataFrame()))
    a = analyze_takeoffs(ct, segment_flights(ct))
    assert a.takeoffs == [] and a.episodes == []
    assert summarize_takeoffs(a).takeoff_attempts == 0


# --- real fixture ---------------------------------------------------------------------------

@pytest.mark.skipif(not TODAY.exists(), reason="ciq fixture missing")
def test_real_session_takeoffs():
    """2026-08-07 Torbole: a learning day -- every takeoff was pumped, none came free."""
    cfg = TakeoffConfig()
    track = parse_fit(TODAY)
    ct = clean(track)
    flights = segment_flights(ct)
    pump = pump_track(track)
    turns = detect_turns(ct, flights, estimate_wind(ct, flights), pump=pump)
    a = analyze_takeoffs(ct, flights, turns, pump=pump)

    assert a.has_accel
    assert len(a.takeoffs) == flights.flight_count
    for k, flight in zip(a.takeoffs, flights.flights):
        assert k.t == flight.start_t
        assert k.entry_kn >= 12.0 / 3.6 * 1.9438445 - 0.5      # at or above foilEntrySpeed
        assert k.judged                                        # 1 Hz CIQ: nothing truncated
        assert 0.0 < k.duration_s <= cfg.max_run_s
        assert k.duration_s >= k.speed_rise_s
        assert k.pumps_to_takeoff is not None and k.in_flight_strokes is not None

    # Every flight is produced by exactly one pumping effort, and no effort produces two.
    produced = [e.flight_index for e in a.episodes if e.outcome == SUCCESS]
    assert sorted(produced) == list(range(flights.flight_count))

    s = summarize_takeoffs(a)
    assert s.takeoff_successes == flights.flight_count
    assert s.failed_attempts > 0                  # a learning day has failed water starts
    assert 50.0 < s.success_pct < 90.0
    assert s.free_takeoffs == 0                   # light morning wind: he pumped every one
    assert 4.0 < s.avg_pumps_to_takeoff < 20.0
    assert s.total_pump_strokes > s.in_flight_pump_strokes > 0
    assert 3.0 < s.median_takeoff_s < 20.0
