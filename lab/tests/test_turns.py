"""Turn detection/scoring/classification on constructed tracks.

Tracks are built by integrating a course profile at constant-ish speed, so the COG the
detector recovers is the course that was written in and the expected turn is exact.
"""

from pathlib import Path

import numpy as np
import pytest

from wingfoil_lab.filters import clean, clean_from_arrays
from wingfoil_lab.flight import segment_flights
from wingfoil_lab.parse import parse_fit
from wingfoil_lab.turns import (BEAR_AWAY, COUNTED_TYPES, FELL_IN, FLEW_THROUGH, JIBE,
                                OUTCOMES, TACK, TOUCHDOWN, UNCLASSIFIED, TurnConfig,
                                detect_turns, summarize_turns)
from wingfoil_lab.wind import WindEstimate, estimate_wind

FIXTURES = Path(__file__).resolve().parents[2] / "fixtures"
TODAY = FIXTURES / "sessions/ciq/2026-08-07-0754_nago-torbole-windsurfen_ciq.fit"

WIND_N = WindEstimate(dir_deg=0.0, confidence=1.0, source="estimate", axis_deg=0.0)


def _track(course_deg, speed_mps, hz=1.0):
    """Integrate (course, speed) samples into a CleanTrack (course in compass degrees)."""
    course = np.asarray(course_deg, float)
    v = np.asarray(speed_mps, float)
    t = np.arange(len(course), dtype=float) / hz
    dt = 1.0 / hz
    dx = np.sin(np.radians(course)) * v * dt
    dy = np.cos(np.radians(course)) * v * dt
    x = np.concatenate([[0.0], np.cumsum(dx)[:-1]])
    y = np.concatenate([[0.0], np.cumsum(dy)[:-1]])
    return clean_from_arrays(t, v, x=x, y=y)


def _leg(course, n, speed=6.0):
    return [course] * n, [speed] * n


def _ramp(c0, c1, n, speeds):
    """`n` samples turning linearly from c0 to c1 with the given speed profile."""
    return list(np.linspace(c0, c1, n)), list(speeds)


def _join(*parts):
    course, speed = [], []
    for c, s in parts:
        course += list(c)
        speed += list(s)
    return course, speed


def _detect(course, speed, wind=WIND_N, config=None):
    ct = _track(course, speed)
    return detect_turns(ct, segment_flights(ct), wind, config)


# --- a clean jibe: beam reach to beam reach through dead downwind, speed carried -------

def _clean_jibe(min_speed=5.0, c0=90.0, c1=270.0):
    """Beam reach `c0` -> beam reach `c1` through dead downwind at 30 deg/s."""
    return _join(_leg(c0, 40),
                 _ramp(c0, c1, 7, np.linspace(6.0, min_speed, 7)),
                 _leg(c1, 40))


def test_clean_jibe_detected_and_successful():
    turns = _detect(*_clean_jibe(min_speed=5.0))
    assert len(turns) == 1
    turn = turns[0]
    assert turn.kind == JIBE and turn.counted
    assert turn.net_deg == pytest.approx(180.0, abs=1.0)
    assert turn.direction == "starboard"          # 90 -> 270 the downwind way is clockwise
    assert turn.side == "port"                    # entered on TWA +90: wind over port bow
    assert turn.entry_kn == pytest.approx(6.0 * 1.9438445, rel=0.05)
    assert turn.score > 0.7 and turn.success


def test_jibe_losing_speed_is_a_failed_turn():
    turns = _detect(*_clean_jibe(min_speed=2.0))
    assert len(turns) == 1
    assert turns[0].kind == JIBE
    assert turns[0].score == pytest.approx(2.0 / 6.0, abs=0.06)
    assert not turns[0].success                   # 33 % < turnSuccessPct and below exit speed


def test_tack_crosses_head_to_wind():
    # close reach to close reach through 0 deg TWA
    course, speed = _join(_leg(45.0, 40),
                          _ramp(45.0, -45.0, 4, np.linspace(6.0, 5.0, 4)),
                          _leg(-45.0, 40))
    turns = _detect(course, speed)
    assert len(turns) == 1
    assert turns[0].kind == TACK and turns[0].counted
    assert turns[0].direction == "port"           # counter-clockwise
    assert turns[0].side == "port"                # TWA +45 before the turn
    assert turns[0].twa_in_deg == pytest.approx(45.0, abs=10.0)
    assert turns[0].twa_out_deg == pytest.approx(-45.0, abs=10.0)


# --- the false positive wind-axis awareness exists to kill -----------------------------

def test_bear_away_is_not_counted_as_a_turn():
    # 60 deg course change that stays on one side of the wind: close reach -> broad reach
    course, speed = _join(_leg(50.0, 40),
                          _ramp(50.0, 140.0, 4, [6.0] * 4),
                          _leg(140.0, 40))
    turns = _detect(course, speed)
    assert len(turns) == 1
    assert turns[0].kind == BEAR_AWAY
    assert not turns[0].counted                   # a naive heading-delta counter says "jibe"
    summary = summarize_turns(turns)
    assert (summary.tacks, summary.jibes, summary.turns_counted) == (0, 0, 0)
    assert summary.rejected == 1


def test_chop_wiggle_below_thresholds_is_not_a_turn():
    # steering through chop: +-25 deg at 8 s period -> peak ~20 deg/s, net swing 50 deg
    t = np.arange(200.0)
    course = 90.0 + 25.0 * np.sin(2 * np.pi * t / 8.0)
    assert _detect(course, np.full(200, 6.0)) == []


def test_slow_pivot_below_peak_rate_is_not_a_turn():
    # 90 deg over 30 s = 3 deg/s: net angle qualifies over 8 s? no -- and no 25 deg/s peak
    course, speed = _join(_leg(90.0, 30), _ramp(90.0, 180.0, 30, [6.0] * 30),
                          _leg(180.0, 30))
    assert _detect(course, speed) == []


# --- context, channels, classification fallbacks ---------------------------------------

def test_turn_while_not_foiling_is_ignored():
    # same jibe shape at 1.5 m/s: never a flight, and below the COG speed floor
    course, speed = _join(_leg(90.0, 40), _ramp(90.0, 270.0, 7, [1.5] * 7), _leg(270.0, 40))
    course = list(course)
    speed = [1.5] * len(course)
    ct = _track(course, speed)
    assert segment_flights(ct).flight_count == 0
    assert detect_turns(ct, segment_flights(ct), WIND_N) == []


def test_without_wind_turns_stay_unclassified_but_still_count():
    turns = _detect(*_clean_jibe(), wind=None)
    assert len(turns) == 1
    assert turns[0].kind == UNCLASSIFIED and turns[0].counted
    assert turns[0].side == "unknown"
    assert np.isnan(turns[0].twa_in_deg)
    summary = summarize_turns(turns)
    assert summary.unclassified == 1 and summary.turns_counted == 1
    assert summary.tacks == summary.jibes == 0


def test_low_confidence_wind_is_not_used():
    weak = WindEstimate(dir_deg=0.0, confidence=0.2, source="estimate", axis_deg=0.0)
    assert _detect(*_clean_jibe(), wind=weak)[0].kind == UNCLASSIFIED


def test_success_needs_both_score_and_staying_on_foil():
    # score 83 % -- but with the exit floor raised to 19 km/h the 5 m/s minimum is "off foil".
    # (Under the shipped defaults the floor barely bites: flying entry >= 12 km/h times the
    # 70 % score already lands above the 8 km/h exit speed.)
    turns = _detect(*_clean_jibe(min_speed=5.0), config=TurnConfig(foil_exit_speed_kmh=19.0))
    assert len(turns) == 1
    assert turns[0].score > 0.7
    assert not turns[0].success


def test_summary_counts_by_side_and_success():
    # jibe out (90 -> 270) then jibe back the same way round (270 -> 90), the second botched
    course, speed = _join(_leg(90.0, 40),
                          _ramp(90.0, 270.0, 7, np.linspace(6.0, 5.0, 7)),
                          _leg(270.0, 40),
                          _ramp(270.0, 90.0, 7, np.linspace(6.0, 2.0, 7)),
                          _leg(90.0, 40))
    turns = _detect(course, speed)
    assert len(turns) == 2
    assert [t.kind for t in turns] == [JIBE, JIBE]
    assert [t.side for t in turns] == ["port", "starboard"]
    summary = summarize_turns(turns)
    assert summary.jibes == 2 and summary.jibes_successful == 1
    assert summary.turns_counted == 2 and summary.turns_successful == 1
    assert summary.success_pct == pytest.approx(50.0)
    assert summary.port + summary.starboard == 2


# --- outcome: flew through / touched down / fell in -------------------------------------

def _jibe_then(dip, tail=40):
    """A clean jibe, two samples of carried speed, then `dip` (a speed profile), then a leg.

    The dip lands inside `turnOutcomeLookahead` of the turn, so whatever it does to the
    speed is attributed to this turn.
    """
    return _join(_leg(90.0, 40),
                 _ramp(90.0, 270.0, 7, np.linspace(6.0, 5.0, 7)),
                 _leg(270.0, 2),
                 ([270.0] * len(dip), list(dip)),
                 _leg(270.0, tail))


def test_clean_jibe_flew_through():
    turn = _detect(*_clean_jibe(min_speed=5.0))[0]
    assert turn.outcome == FLEW_THROUGH and not turn.borderline
    assert turn.off_foil_s == 0.0 and turn.stopped_s == 0.0


def test_touchdown_is_a_brief_loss_the_flight_machine_never_sees():
    """2 s below the stop floor, pumped straight back up: touchdown, no fall.

    The dip is shorter than the flight `exitHold` (3 s), so flight segmentation still
    reports one unbroken flight -- the outcome has to come from the speed trace.
    """
    course, speed = _jibe_then([0.6] * 3)
    ct = _track(course, speed)
    flights = segment_flights(ct)
    assert flights.flight_count == 1                  # the touchdown never ends the flight

    turns = detect_turns(ct, flights, WIND_N)
    assert len(turns) == 1
    assert turns[0].kind == JIBE
    assert turns[0].outcome == TOUCHDOWN and not turns[0].borderline
    assert turns[0].stopped_s == pytest.approx(2.0)
    # ...and the score does not see it either: the dip lands past `minSpeedLag`, so the
    # secondary metric still reads 83 %/made. Outcome is the channel that catches this.
    assert turns[0].score > 0.8 and turns[0].success


def test_fall_is_a_long_stop():
    turns = _detect(*_jibe_then([0.3] * 11))
    assert len(turns) == 1
    assert turns[0].outcome == FELL_IN and not turns[0].borderline
    assert turns[0].stopped_s == pytest.approx(10.0)
    assert turns[0].off_foil_s >= 10.0


def test_stop_between_the_two_thresholds_is_a_borderline_touchdown():
    """The 3-5 s band: called a touchdown, but flagged so tuning can find these."""
    turns = _detect(*_jibe_then([0.6] * 5))
    assert len(turns) == 1
    assert turns[0].outcome == TOUCHDOWN and turns[0].borderline
    assert turns[0].stopped_s == pytest.approx(4.0)


def test_outcome_thresholds_are_tunable():
    course, speed = _jibe_then([0.6] * 5)
    strict = TurnConfig(touchdown_max_stop_s=1.0, fall_stop_s=2.0)
    assert _detect(course, speed, config=strict)[0].outcome == FELL_IN
    # raising the stop floor above the dip speed makes the same dip a plain touchdown
    high = TurnConfig(stop_speed_floor_mps=0.4)
    turn = _detect(course, speed, config=high)[0]
    assert turn.outcome == TOUCHDOWN and turn.stopped_s == 0.0


def test_summary_counts_outcomes_per_family():
    # jibe out flying, jibe back with a 10 s stop in the water
    course, speed = _join(_leg(90.0, 40),
                          _ramp(90.0, 270.0, 7, np.linspace(6.0, 5.0, 7)),
                          _leg(270.0, 40),
                          _ramp(270.0, 90.0, 7, np.linspace(6.0, 5.0, 7)),
                          _leg(90.0, 2),
                          ([90.0] * 11, [0.3] * 11),
                          _leg(90.0, 40))
    turns = _detect(course, speed)
    assert [t.outcome for t in turns] == [FLEW_THROUGH, FELL_IN]
    summary = summarize_turns(turns)
    assert (summary.jibe_outcomes.flew_through, summary.jibe_outcomes.touchdown,
            summary.jibe_outcomes.fell_in) == (1, 0, 1)
    assert summary.jibe_outcomes.total == summary.jibes == 2
    assert summary.tack_outcomes.total == 0
    assert summary.outcomes.total == summary.turns_counted


# --- real fixture -----------------------------------------------------------------------

@pytest.mark.skipif(not TODAY.exists(), reason="ciq fixture missing")
def test_real_session_turns_smoke():
    """2026-08-07 Torbole: a wingfoil session is jibe-dominated and every turn is on foil."""
    cfg = TurnConfig()
    ct = clean(parse_fit(TODAY))
    flights = segment_flights(ct)
    turns = detect_turns(ct, flights, estimate_wind(ct, flights))
    assert len(turns) > 10

    for turn in turns:
        assert cfg.min_angle_deg <= abs(turn.net_deg) <= 360.0
        assert 0.0 < turn.end_t - turn.start_t <= cfg.max_duration_s
        assert abs(turn.peak_rate_deg_s) >= cfg.peak_rate_deg_s
        assert turn.direction in ("port", "starboard")
        assert turn.entry_kn > 0.0 and 0.0 <= turn.score <= 1.0
        assert turn.min_kn <= turn.entry_kn
        assert turn.counted == (turn.kind in COUNTED_TYPES)
        assert any(turn.start_t <= f.end_t + cfg.context_after_s and turn.end_t >= f.start_t
                   for f in flights.flights)
        assert turn.outcome in OUTCOMES
        assert turn.stopped_s <= turn.off_foil_s
        if turn.outcome == FLEW_THROUGH:
            assert turn.off_foil_s == 0.0 and not turn.borderline
        if turn.outcome == FELL_IN:
            assert turn.stopped_s > cfg.fall_stop_s and not turn.borderline
        if turn.borderline:
            assert turn.outcome == TOUCHDOWN
            assert cfg.touchdown_max_stop_s < turn.stopped_s <= cfg.fall_stop_s
    for a, b in zip(turns, turns[1:]):
        assert b.start_t > a.end_t            # no overlapping detections survive

    summary = summarize_turns(turns)
    assert summary.jibes > summary.tacks      # tacking a wing foil is the rare maneuver
    assert summary.turns_counted == summary.tacks + summary.jibes + summary.unclassified
    assert summary.unclassified == 0          # the wind axis is usable for this session
    assert summary.rejected == len(turns) - summary.turns_counted
    assert summary.port + summary.starboard == summary.turns_counted

    # Torbole 2026-08-07: a learning session -- most jibes flown, a real minority swum.
    outcomes = summary.jibe_outcomes
    assert outcomes.total == summary.jibes
    assert outcomes.flew_through > outcomes.touchdown + outcomes.fell_in
    assert outcomes.fell_in > 0 and outcomes.touchdown > 0
    assert outcomes.borderline <= 1                   # the 3-5 s band is all but empty
    assert summary.outcomes.total == summary.turns_counted
