"""Turn detection/scoring/classification on constructed tracks.

Tracks are built by integrating a course profile at constant-ish speed, so the COG the
detector recovers is the course that was written in and the expected turn is exact.
"""

from pathlib import Path

import numpy as np
import pytest

from wingfoil_lab.filters import clean, clean_from_arrays
from wingfoil_lab.flight import segment_flights
from wingfoil_lab.flightend import GLIDE_OUT, UNKNOWN, FlightEnd, classify_flight_ends
from wingfoil_lab.parse import parse_fit
from wingfoil_lab.pump import pump_track_from_arrays
from wingfoil_lab.evidence import off_foil_evidence
from wingfoil_lab.turns import (BEAR_AWAY, COUNTED_TYPES, FELL_IN, FLEW_THROUGH, JIBE,
                                OUTCOMES, REASON_OFF_FOIL, REASON_PUMPED_MARGINAL,
                                REASON_STOP, REASON_SUBMERGED, ROUND_UP, TACK, THREE_SIXTY,
                                TOUCHDOWN, UNCLASSIFIED, Turn, TurnConfig, detect_turns,
                                streaks, summarize_turns)
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

def test_a_narrow_sweep_through_downwind_is_a_course_change_not_a_jibe():
    """`turnClassifyMinAngle` (90 deg, engine 0.13.0): a sweep this narrow is not a maneuver.

    The sweep crosses dead downwind, so every rule before 0.13.0 called it a jibe -- but 80
    deg of it is a rider bearing off and coming back onto the other gybe by geometry alone.
    It is still *detected* (`turnMinAngle` is still 60 deg, and the page marks the course
    change); it simply counts towards nothing.
    """
    course, speed = _join(_leg(140.0, 40),
                          _ramp(140.0, 220.0, 4, [6.0] * 4),
                          _leg(220.0, 40))
    turns = _detect(course, speed)
    assert len(turns) == 1
    assert abs(turns[0].net_deg) == pytest.approx(80.0, abs=5.0)
    assert turns[0].kind in (BEAR_AWAY, ROUND_UP) and not turns[0].counted
    assert summarize_turns(turns).rejected == 1
    # Drop the floor and the same sweep is the jibe every earlier engine called it.
    named = _detect(course, speed, config=TurnConfig(classify_min_angle_deg=0.0))[0]
    assert named.kind == JIBE and named.counted


def test_a_narrow_sweep_without_a_wind_axis_is_a_course_change_too():
    """No axis is not a licence to count it: below the floor nothing is a maneuver."""
    course, speed = _join(_leg(140.0, 40),
                          _ramp(140.0, 220.0, 4, [6.0] * 4),
                          _leg(220.0, 40))
    turns = _detect(course, speed, wind=None)
    assert len(turns) == 1
    assert not turns[0].counted and turns[0].side == "unknown"
    # Wide enough, and no axis: an unnamed maneuver is still a maneuver.
    wide = _detect(*_clean_jibe(), wind=None)
    assert len(wide) == 1 and wide[0].kind == UNCLASSIFIED and wide[0].counted


def test_bear_away_is_not_counted_as_a_turn():
    # 90 deg course change that stays on one side of the wind: close reach -> broad reach
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
    # steering through chop: +-25 deg at 8 s period -> peak ~20 deg/s, net swing 50 deg.
    # Since engine 0.14.0 that peak clears `turnPeakRate` (18 deg/s); the 50 deg net swing
    # is what rejects it, and `turnMinAngle` is the gate doing the work here.
    t = np.arange(200.0)
    course = 90.0 + 25.0 * np.sin(2 * np.pi * t / 8.0)
    assert _detect(course, np.full(200, 6.0)) == []


def test_slow_pivot_below_peak_rate_is_not_a_turn():
    # 90 deg over 30 s = 3 deg/s: net angle qualifies over 8 s? no -- and no 18 deg/s peak
    course, speed = _join(_leg(90.0, 30), _ramp(90.0, 180.0, 30, [6.0] * 30),
                          _leg(180.0, 30))
    assert _detect(course, speed) == []


# --- engine 0.15.0: the wind-axis crossing, and the two requirements around it ---------


def test_the_crossing_is_recorded_on_every_counted_jibe():
    """Jan's definition of a jibe -- "a turn through the wind axis" -- made an instant.

    Wind from north, 90 deg -> 270 deg the downwind way: the axis is dead downwind, so the
    crossing is where the course passes 180, the sweep starts 90 deg off it and carries
    90 deg past it before the run-out leg holds.
    """
    turns = _detect(*_clean_jibe())
    turn = turns[0]
    assert turn.kind == JIBE
    assert turn.start_t <= turn.axis_t <= turn.end_t
    assert turn.axis_before_deg == pytest.approx(90.0, abs=5.0)
    assert turn.axis_after_deg == pytest.approx(90.0, abs=5.0)


def test_a_tack_crosses_head_to_wind_and_says_when():
    course, speed = _join(_leg(45.0, 40),
                          _ramp(45.0, -45.0, 4, np.linspace(6.0, 5.0, 4)),
                          _leg(-45.0, 40))
    turn = _detect(course, speed)[0]
    assert turn.kind == TACK
    assert turn.start_t <= turn.axis_t <= turn.end_t
    assert turn.axis_before_deg == pytest.approx(45.0, abs=5.0)
    assert turn.axis_after_deg == pytest.approx(45.0, abs=5.0)


def test_a_course_change_and_an_axis_less_turn_carry_no_crossing():
    """nan, never 0: "he started on the axis" and "there was no axis" are different facts."""
    course, speed = _join(_leg(50.0, 40),
                          _ramp(50.0, 140.0, 4, [6.0] * 4),
                          _leg(140.0, 40))
    bear_away = _detect(course, speed)[0]
    assert bear_away.kind == BEAR_AWAY
    for value in (bear_away.axis_t, bear_away.axis_before_deg, bear_away.axis_after_deg):
        assert np.isnan(value)
    no_wind = _detect(*_clean_jibe(), wind=None)[0]
    assert no_wind.kind == UNCLASSIFIED and no_wind.counted
    for value in (no_wind.axis_t, no_wind.axis_before_deg, no_wind.axis_after_deg):
        assert np.isnan(value)


def test_axis_before_deg_files_a_late_started_sweep_as_a_course_change():
    """170 -> 290: it crosses dead downwind, but it began 10 deg off it.

    That is a rider already three quarters of the way round straightening out, not a turn
    *through* the wind -- and at `axis_before_deg` 30 it is filed exactly where the
    classification floor files its own refusals, with its axis numbers going with the label.
    """
    course, speed = _join(_leg(170.0, 40),
                          _ramp(170.0, 290.0, 7, [6.0] * 7),
                          _leg(290.0, 40))
    named = _detect(course, speed)[0]
    assert named.kind == JIBE and named.counted
    assert named.axis_before_deg == pytest.approx(10.0, abs=5.0)

    refused = _detect(course, speed, config=TurnConfig(axis_before_deg=30.0))[0]
    assert refused.kind in (BEAR_AWAY, ROUND_UP) and not refused.counted
    assert np.isnan(refused.axis_t) and np.isnan(refused.axis_before_deg)
    assert summarize_turns([refused]).rejected == 1


def test_axis_after_deg_costs_the_clean_verdict_and_nothing_else():
    """90 -> 190 through dead downwind: only 10 deg out the other side.

    Jan: "it might be an additional requirement for a successful jibe to turn 30 deg after
    the axis. But not require that for a touch-down or failed jibe." So the turn stays a
    counted jibe with its outcome untouched; what it loses is `success`, and with it `clean`.
    """
    course, speed = _join(_leg(90.0, 40),
                          _ramp(90.0, 190.0, 6, np.linspace(6.0, 5.0, 6)),
                          _leg(190.0, 40))
    carried = _detect(course, speed)[0]
    assert carried.kind == JIBE and carried.success and carried.clean
    assert carried.axis_after_deg == pytest.approx(10.0, abs=5.0)

    strict = _detect(course, speed, config=TurnConfig(axis_after_deg=30.0))[0]
    assert strict.kind == JIBE and strict.counted        # still a jibe he made
    assert strict.outcome == carried.outcome             # the ladder is untouched
    assert not strict.success and not strict.clean
    assert summarize_turns([strict]).jibes_successful == 0


def test_the_defaults_ask_nothing():
    """Both parameters are 0, and 0 refuses nothing -- the reason no golden number moved."""
    assert TurnConfig().axis_before_deg == 0.0
    assert TurnConfig().axis_after_deg == 0.0
    turn = _detect(*_clean_jibe())[0]
    assert turn.axis_before_deg >= 0.0 and turn.axis_after_deg >= 0.0


# --- engine 0.14.0: the carved jibe the 25 deg/s peak floor threw away -----------------

#: A 150 deg carve at a 15 deg/s *mean*, ten one-second steps easing in and out of a 19
#: deg/s plateau. This is the shape of the jibes the corpus was losing: a rider carving a
#: wide radius at 11 kn turns steadily and never spikes.
_CARVE_RATES = [9.0, 14.0, 18.0, 19.0, 19.0, 19.0, 19.0, 18.0, 9.0, 6.0]


def _carved_jibe(c0=90.0):
    """Beam reach -> beam reach through dead downwind, carved over 10 s at 15 deg/s mean."""
    ramp = [c0] + list(c0 + np.cumsum(_CARVE_RATES))
    return _join(_leg(c0, 40), (ramp, [6.0] * len(ramp)), _leg(ramp[-1], 40))


def test_a_carved_150_deg_sweep_at_15_deg_s_is_a_jibe():
    """Engine 0.14.0's reason to exist: a carve is slow, and 25 deg/s called it nothing.

    150 deg through dead downwind over 10 s -- a real jibe, ridden and counted by the rider
    -- peaks at 19 deg/s and never comes near the old floor. Under the 0.13.0 pair the
    engine did not emit so much as a grey course-change marker for it.

    The sweep window stays at 8 s, so what the detector reports is the 135 deg of the carve
    that fits in it rather than the whole 150. That is deliberate and it is enough: the
    verdict a rider reads is *jibe, counted*, and 135 deg is over `classify_min_angle_deg`
    with room to spare. Widening the window to 12 s would recover the last 15 deg and cost
    26 clean jibes across the corpus (docs/algorithms.md), which is a bad trade -- a jibe
    counted a little short is worth more than a jibe scored a little more generously.
    """
    course, speed = _carved_jibe()

    turns = _detect(course, speed)
    assert len(turns) == 1
    turn = turns[0]
    assert turn.kind == JIBE and turn.counted
    assert abs(turn.peak_rate_deg_s) == pytest.approx(19.0, abs=0.5)   # never near 25
    # The 8 s window's share of a 10 s carve, not the carve's full 150 deg.
    assert turn.net_deg == pytest.approx(135.0, abs=1.0)
    assert turn.end_t - turn.start_t == pytest.approx(8.0, abs=0.5)

    # The 0.13.0 thresholds saw nothing at all here -- not even a course change.
    assert _detect(course, speed,
                   config=TurnConfig(peak_rate_deg_s=25.0, max_duration_s=8.0)) == []
    # The window that was measured and rejected: it does see the whole carve.
    whole = _detect(course, speed, config=TurnConfig(max_duration_s=12.0))
    assert len(whole) == 1 and whole[0].kind == JIBE
    assert whole[0].net_deg == pytest.approx(150.0, abs=1.0)


def test_a_100_deg_correction_at_20_deg_s_is_still_not_counted():
    """The lower floor buys markers, not maneuvers.

    A 100 deg bear-away at 20 deg/s clears `turnPeakRate` only because 0.14.0 lowered it,
    and it is *detected* -- the page marks the course change. It stays on one side of the
    wind, so it is no more a jibe than it was before: the wind-axis rule, not the peak
    floor, is what decides whether a sweep counts, and lowering the floor did not touch it.
    """
    course, speed = _join(_leg(40.0, 40),
                          _ramp(40.0, 140.0, 6, [6.0] * 6),
                          _leg(140.0, 40))
    turns = _detect(course, speed)
    assert len(turns) == 1
    assert turns[0].net_deg == pytest.approx(100.0, abs=1.0)
    assert abs(turns[0].peak_rate_deg_s) == pytest.approx(20.0, abs=0.5)
    assert turns[0].kind == BEAR_AWAY and not turns[0].counted

    summary = summarize_turns(turns)
    assert (summary.tacks, summary.jibes, summary.turns_counted) == (0, 0, 0)
    assert summary.rejected == 1

    # Below the 0.13.0 floor of 25 deg/s, so the old engine did not even mark it.
    assert _detect(course, speed,
                   config=TurnConfig(peak_rate_deg_s=25.0, max_duration_s=8.0)) == []


def test_wallow_rotation_is_rejected_by_the_spatial_gate():
    """A heading flip while drifting: the right angle, but no water covered.

    2.2 m/s clears `turnCogSpeedFloor`, so the speed floor alone lets this through -- it is
    the geometry that says no: 11 m of arc and a 3.5 m radius, a rider spinning the board
    round on the spot rather than carving 180 deg of a circle.
    """
    course, speed = _join(_leg(90.0, 40, speed=6.0),
                          ([90.0] * 2, [2.2] * 2),
                          _ramp(90.0, 270.0, 5, [2.2] * 5),
                          _leg(270.0, 20, speed=2.2))
    ct = _track(course, speed)
    flights = segment_flights(ct)

    ungated = detect_turns(ct, flights, WIND_N,
                           TurnConfig(min_arc_m=0.0, min_radius_m=0.0))
    assert len(ungated) == 1                      # angle-only detection finds a "jibe"
    assert ungated[0].kind == JIBE
    assert ungated[0].arc_m < 12.0 and ungated[0].radius_m < 6.0

    assert detect_turns(ct, flights, WIND_N) == []   # ...and the gate drops it outright


def test_a_real_jibe_arc_survives_the_gate_with_margin():
    """The shape the gate must never touch: a carved 180 deg at foiling speed."""
    turn = _detect(*_clean_jibe(min_speed=5.0))[0]
    cfg = TurnConfig()
    assert turn.arc_m > 2.0 * cfg.min_arc_m       # ~38 m of water covered
    assert turn.radius_m > 2.0 * cfg.min_radius_m  # ~12 m radius: a real carve
    assert turn.chord_m < turn.arc_m              # it curved, it did not go straight


def test_the_spatial_gate_is_geometric_not_another_speed_floor():
    """Identical speed, duration and arc length -- only the tightness differs.

    Both sweeps run 4.0 m/s for 3 s and cover exactly 16 m of water, so no speed test of
    any kind can separate them. The 180 deg one pivots inside a 5 m radius and is dropped;
    the 90 deg one carves 10 m and is kept. That is what "moved around the curve" means.
    """
    def sweep(to_deg):
        return _join(_leg(90.0, 40, speed=4.0), _ramp(90.0, to_deg, 4, [4.0] * 4),
                     _leg(to_deg, 20, speed=4.0))

    loose = TurnConfig(min_arc_m=0.0, min_radius_m=0.0)
    tight_open = _detect(*sweep(270.0), config=loose)
    wide_open = _detect(*sweep(180.0), config=loose)
    assert len(tight_open) == len(wide_open) == 1
    assert tight_open[0].arc_m == pytest.approx(wide_open[0].arc_m, abs=0.1)
    assert tight_open[0].radius_m < 6.0 < wide_open[0].radius_m

    assert _detect(*sweep(270.0)) == []               # pivoted on the spot: dropped
    assert len(_detect(*sweep(180.0))) == 1           # carved a real arc: kept


def test_gate_thresholds_are_tunable():
    course, speed = _clean_jibe(min_speed=5.0)
    assert _detect(course, speed, config=TurnConfig(min_arc_m=1000.0)) == []
    assert _detect(course, speed, config=TurnConfig(min_radius_m=100.0)) == []


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
    # 9 s of it, not the full 10: `turnOutcomeWindow` is 12 s since engine 0.13.0, so the
    # stop is measured over the same tail the outcome is judged over and no further.
    assert turns[0].stopped_s == pytest.approx(9.0)
    assert turns[0].off_foil_s >= 9.0


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


def _mush_out(exit_speed=4.0, decay=0.25, n=16):
    """A jibe exited above `foilExitSpeed` that then bleeds off to a standstill.

    Nothing here trips the flight machine for many seconds: the exit is still flying and
    the decay is gradual, which is exactly the failure a fixed short lookahead misses.
    """
    tail = np.clip(exit_speed - decay * np.arange(1, n + 1), 0.2, None)
    return _join(_leg(90.0, 40),
                 _ramp(90.0, 270.0, 7, np.linspace(6.0, exit_speed, 7)),
                 ([270.0] * n, list(tail)),
                 _leg(270.0, 40, speed=0.2))


def test_mush_out_after_the_turn_is_the_turns_fault():
    """The 12 s tail catches the mush-out; what happens after it is not the turn's.

    The turn is charged with the collapse it can be seen to have caused -- the exit is off
    the foil inside the window, so this is a **touchdown** and not a fly-through. The
    standstill this fixture eventually reaches lands past `turnOutcomeWindow` (12 s since
    engine 0.13.0, equal to `turnOutcomeLookahead`), and a fall a quarter of a minute after
    the sweep is a straight-line fall: the flight-end channel counts it, and WPH with it.
    """
    turn = _detect(*_mush_out())[0]
    assert turn.outcome == TOUCHDOWN
    assert turn.outcome_window_s > 5.0            # the old fixed 5 s tail saw none of this

    # With the 60 s window 0.13.0 replaced, the same fixture read as the turn's own fall --
    # the turn was blamed for a collapse three quarters of a minute past its exit.
    wide = _detect(*_mush_out(), config=TurnConfig(outcome_window_s=60.0))[0]
    assert wide.outcome == FELL_IN


def test_a_short_lookahead_would_have_called_the_mush_out_a_fly_through():
    """Regression guard on `turnOutcomeLookahead`: at the old 5 s the collapse is invisible."""
    course, speed = _mush_out()
    assert _detect(course, speed, config=TurnConfig(outcome_lookahead_s=5.0))[0].outcome \
        == FLEW_THROUGH


def test_recovery_closes_the_window_so_a_later_touchdown_is_not_absorbed():
    """Powered straight out of the jibe, then a fall a minute later: not this turn's."""
    course, speed = _join(_leg(90.0, 40),
                          _ramp(90.0, 270.0, 7, np.linspace(6.0, 5.0, 7)),
                          _leg(270.0, 60),
                          ([270.0] * 20, [0.3] * 20),
                          _leg(270.0, 20))
    turn = _detect(course, speed)[0]
    assert turn.outcome == FLEW_THROUGH
    assert turn.outcome_window_s < 5.0            # closed as soon as cruising speed returned


def test_the_window_stops_at_a_recording_gap():
    """Flights hard-break at gaps, so following the search across would invent a loss."""
    course, speed = _mush_out(exit_speed=4.6, decay=0.1, n=4)
    t = np.arange(len(course), dtype=float)
    t[51:] += 30.0                                # 30 s of missing samples right after the exit
    ct = _track(course, speed, t=t)
    turn = detect_turns(ct, segment_flights(ct), WIND_N)[0]
    assert turn.outcome == FLEW_THROUGH
    assert turn.outcome_window_s <= 4.0


def test_positional_channel_catches_a_touchdown_the_doppler_smooths_away():
    """Doppler held up (firmware smoothing), the track says he stopped: still a touchdown.

    `_jibe_then` puts its dip at index 49; here the *reported* Doppler never dips at all
    while the ground truth does, which is what 3-4 s of firmware smoothing does to a 3 s
    touchdown. Only the positional channel can see it.
    """
    course, doppler = _jibe_then([3.0] * 3)       # Doppler stays above foilExitSpeed
    truth = list(doppler)
    truth[49:52] = [0.5, 0.5, 0.5]                # what the board actually did
    geometry = _track(course, truth).records

    ct = clean_from_arrays(geometry["t"].to_numpy(float), np.asarray(doppler, float),
                           x=geometry["x"].to_numpy(float),
                           y=geometry["y"].to_numpy(float))
    assert ct.records["doppler_mps"].min() > TurnConfig().foil_exit_speed_kmh / 3.6
    turn = detect_turns(ct, segment_flights(ct), WIND_N)[0]
    assert turn.outcome == TOUCHDOWN              # min(Doppler, positional) sees the stop


# --- the clean jibe's quiet tail (engine 0.17.0) -----------------------------------------
#
# Jan, 7 Sep 2026: "an additional requirement for a clean jibe: no touch down or fall within
# 10 s afterwards. This only applies to clean jibe, not to carried through." The outcome
# window closes at recovery, so the losses below are all *outside* it and the ladder is
# right to keep calling the turn a fly-through. Only `clean` moves.


def _jibe_then_later(dip, quiet=6, tail=40):
    """A jibe powered straight out of, `quiet` seconds of cruising, then `dip`.

    The cruising leg closes the outcome window (recovery), so the dip is past the verdict
    and inside the quiet tail -- which is exactly the shape the rule was written for.
    """
    return _join(_leg(90.0, 40),
                 _ramp(90.0, 270.0, 7, np.linspace(6.0, 5.0, 7)),
                 _leg(270.0, quiet),
                 ([270.0] * len(dip), list(dip)),
                 _leg(270.0, tail))


def test_a_touchdown_inside_the_quiet_tail_costs_the_jibe_its_star():
    course, speed = _jibe_then_later([0.5] * 3)
    turn = _detect(course, speed)[0]
    # The ladder is untouched: the loss is outside the window the outcome was read from.
    assert turn.outcome == FLEW_THROUGH and turn.success
    assert not turn.clean and turn.clean_blocked_by == "quiet_off_foil"


def test_the_quiet_tail_is_off_at_zero():
    course, speed = _jibe_then_later([0.5] * 3)
    turn = _detect(course, speed, config=TurnConfig(clean_quiet_s=0.0))[0]
    assert turn.clean and turn.clean_blocked_by is None


def test_a_loss_past_the_quiet_tail_leaves_the_jibe_clean():
    """The same touchdown, twenty seconds later: not this jibe's business."""
    turn = _detect(*_jibe_then_later([0.5] * 3, quiet=20))[0]
    assert turn.clean and turn.clean_blocked_by is None


def test_a_recording_gap_ends_the_quiet_tail():
    """Samples the far side of a hole are not evidence about what happened in it."""
    course, speed = _jibe_then_later([0.5] * 3)
    t = np.arange(len(course), dtype=float)
    t[50:] += 30.0                                # the recording stops right after the sweep
    ct = _track(course, speed, t=t)
    turn = detect_turns(ct, segment_flights(ct), WIND_N)[0]
    assert turn.outcome == FLEW_THROUGH and turn.clean


def test_a_touchdown_flight_end_in_the_tail_blocks_it_and_a_glide_out_does_not():
    """The three flight-end verdicts the rule distinguishes, on one clean jibe."""
    course, speed = _clean_jibe(min_speed=5.0)
    ct = _track(course, speed)
    flights = segment_flights(ct)

    def clean_with(*ends):
        turn = detect_turns(ct, flights, WIND_N, ends=ends)[0]
        return turn.clean, turn.clean_blocked_by

    after = 52.0                                  # a few seconds past the sweep
    assert clean_with() == (True, None)
    assert clean_with(_end(after, GLIDE_OUT)) == (True, None)
    assert clean_with(_end(after, UNKNOWN, truncated=True)) == (True, None)
    assert clean_with(_end(after, TOUCHDOWN)) == (False, "quiet_flight_end")
    assert clean_with(_end(after, FELL_IN)) == (False, "quiet_flight_end")
    assert clean_with(_end(after + 30.0, TOUCHDOWN)) == (True, None)   # past the tail


def test_a_wrist_under_in_the_tail_blocks_it():
    """One submerged sample, too short to be an off-foil spell, and still a swim."""
    course, speed = _clean_jibe(min_speed=5.0)
    alt = np.full(len(course), 70.0)
    alt[52] = -200.0                              # 30 cm of water, past the outcome window
    ct = _track(course, speed, alt_m=alt)
    turn = detect_turns(ct, segment_flights(ct), WIND_N)[0]
    assert turn.outcome == FLEW_THROUGH and not turn.submerged
    assert not turn.clean and turn.clean_blocked_by == "quiet_submerged"


def test_the_quiet_tail_moves_clean_and_nothing_else():
    """Every other number a rider reads is the same with the gate on and off."""
    course, speed = _jibe_then_later([0.5] * 3)
    ct = _track(course, speed)
    flights = segment_flights(ct)
    on = detect_turns(ct, flights, WIND_N)[0]
    off = detect_turns(ct, flights, WIND_N, TurnConfig(clean_quiet_s=0.0))[0]
    assert (on.outcome, on.success, on.score, on.counted, on.kind, on.off_foil_s,
            on.stopped_s, on.outcome_window_s) == \
           (off.outcome, off.success, off.score, off.counted, off.kind, off.off_foil_s,
            off.stopped_s, off.outcome_window_s)
    assert on.clean != off.clean
    # And the summary moves in exactly one place.
    a, b = summarize_turns([on]), summarize_turns([off])
    assert a.jibes == b.jibes == 1
    assert a.turns_successful == b.turns_successful == 1
    assert (a.jibes_successful, b.jibes_successful) == (0, 1)


def test_a_jibe_the_outcome_already_failed_needs_no_explanation():
    """`cleanBlockedBy` is for the refusals nothing else on the page shows."""
    turn = _detect(*_jibe_then([0.3] * 11))[0]
    assert turn.outcome == FELL_IN and not turn.clean
    assert turn.clean_blocked_by is None


def test_a_tack_carries_no_clean_verdict_and_no_reason():
    """"Clean" is a jibe word, so a tack is never blocked and never explained."""
    course, speed = _join(_leg(45.0, 40),
                          _ramp(45.0, -45.0, 5, np.linspace(6.0, 4.0, 5)),
                          _leg(-45.0, 6),
                          ([-45.0] * 3, [0.5] * 3),
                          _leg(-45.0, 40))
    turn = _detect(course, speed)[0]
    assert turn.kind == TACK
    assert not turn.clean and turn.clean_blocked_by is None


def test_the_axis_after_gate_says_so_when_it_takes_a_jibe():
    """The other invisible refusal: carried, flew through, and not far enough past the axis."""
    course, speed = _clean_jibe(min_speed=5.0)
    turn = _detect(course, speed, config=TurnConfig(axis_after_deg=120.0))[0]
    assert turn.outcome == FLEW_THROUGH and not turn.success
    assert not turn.clean and turn.clean_blocked_by == "axis_after"


# --- barometric submersion: a wet wrist is proof of a swim ------------------------------

def test_wrist_submersion_makes_a_short_stop_a_fall():
    """3 s stop = a touchdown on speed alone; the barometer says he was under water."""
    course, speed = _jibe_then([0.6] * 3)
    dry = _detect(course, speed)[0]
    assert dry.outcome == TOUCHDOWN and not dry.submerged

    alt = np.full(len(course), 70.0)
    alt[49:53] = [-180.0, -230.0, -210.0, -190.0]  # 30 cm of water ~ 30 hPa ~ 250 m "drop"
    ct = _track(course, speed, alt_m=alt)
    turn = detect_turns(ct, segment_flights(ct), WIND_N)[0]
    assert turn.submerged and turn.outcome == FELL_IN


def test_submersion_threshold_is_tunable_and_ignores_real_altitude_noise():
    course, speed = _jibe_then([0.6] * 3)
    alt = 70.0 + np.random.default_rng(0).normal(0.0, 3.0, len(course))   # baro wander
    turn = _detect(course, speed, config=TurnConfig())
    assert not turn[0].submerged
    ct = _track(course, speed, alt_m=alt)
    assert not detect_turns(ct, segment_flights(ct), WIND_N)[0].submerged


def test_missing_altitude_channel_degrades_to_speed_only():
    """Native/GPX sources have no usable barometer: same verdict as before, no crash."""
    course, speed = _jibe_then([0.3] * 11)
    turn = _detect(course, speed)[0]              # _track leaves alt_m all-NaN
    assert turn.outcome == FELL_IN and not turn.submerged


# --- accelerometer: pumping corroborates, it does not decide -----------------------------

def _pump_stream(t0, t1, hz=25.0, cadence_hz=1.2, amp_g=0.6, quiet=0.0):
    """(t, |a|) for a wrist that is pumping at `cadence_hz` between t0 and t1."""
    t = np.arange(0.0, 200.0, 1.0 / hz)
    mag = np.full_like(t, 1.0) + quiet * np.sin(2 * np.pi * 3.0 * t)
    on = (t >= t0) & (t <= t1)
    mag[on] += amp_g * np.sin(2 * np.pi * cadence_hz * t[on])
    return t, mag


def test_a_dip_below_entry_speed_but_above_min_foil_speed_flew_through():
    """**Engine 0.18.0: the pump rung moved to the minimum foiling speed, and stopped firing.**

    Until 0.17.0 the corroborating speed was `foilEntrySpeed` (12 km/h), the speed a *flight
    starts* at, and a jibe that sagged to 2.8 m/s = 10.1 km/h with the wrist working was called
    a touchdown -- no off-foil sample, no stop, no wrist under. Jan's Jibe 50 of 4 Sep 2026 is
    that turn, and he flew it. The speed below which the foil stops carrying is `foilExitSpeed`
    (8 km/h), and this dip is well above it.

    `pumped` is untouched: the rider did work for it, and the page still says so.
    """
    course, speed = _jibe_then([2.8] * 4)         # above foilExitSpeed, below foilEntrySpeed
    assert _detect(course, speed)[0].outcome == FLEW_THROUGH       # speed alone: not enough

    ct = _track(course, speed)
    pump = pump_track_from_arrays(*_pump_stream(48.0, 56.0))
    turn = detect_turns(ct, segment_flights(ct), WIND_N, pump=pump)[0]
    assert turn.pumped
    assert turn.outcome == FLEW_THROUGH and turn.outcome_reason is None


def test_the_pump_rung_cannot_fire_at_the_published_defaults():
    """And it cannot fire whichever way the switch is set, which is why it is a *retired* rule.

    `flying` is defined as in a flight, not submerged, and above `foilExitSpeed`, so on the
    branch this rung lives on -- no non-flying sample anywhere in the window -- every sample is
    already above the speed the rung tests against. Turning `pumpedOutIsTouchdown` off can
    therefore move nothing at the published defaults, and this is the test that says so out
    loud rather than leaving it to be rediscovered.
    """
    course, speed = _jibe_then([2.8] * 4)
    ct, flights = _track(course, speed), None
    flights = segment_flights(ct)
    pump = pump_track_from_arrays(*_pump_stream(48.0, 56.0))
    on = detect_turns(ct, flights, WIND_N, pump=pump, config=TurnConfig())
    off = detect_turns(ct, flights, WIND_N, pump=pump,
                       config=TurnConfig(pumped_out_is_touchdown=False))
    assert TurnConfig().pumped_out_is_touchdown is True            # on, and inert
    assert [t.outcome for t in on] == [t.outcome for t in off] == [FLEW_THROUGH]
    assert [t.outcome_reason for t in on] == [t.outcome_reason for t in off] == [None]


def test_the_pump_rung_still_computes_where_the_two_speeds_disagree():
    """The rung is unreachable, not deleted -- and a stored document from an older engine still
    carries its verdict, so the code and its reason code have to keep working.

    The only way to reach it is to judge a turn against a *higher* exit speed than the evidence
    was built with, which is what 0.17.0 effectively did by testing the entry speed. Handing
    `detect_turns` evidence built at 6 km/h while the turn config judges at 12 km/h reproduces
    exactly that, and the rung fires with its own reason.
    """
    course, speed = _jibe_then([2.8] * 4)                          # 10.1 km/h
    ct = _track(course, speed)
    flights = segment_flights(ct)
    pump = pump_track_from_arrays(*_pump_stream(48.0, 56.0))
    lenient = off_foil_evidence(ct, flights, 6.0, TurnConfig().baro_drop_m)
    cfg = TurnConfig(foil_exit_speed_kmh=12.0)
    turn = detect_turns(ct, flights, WIND_N, config=cfg, pump=pump, evidence=lenient)[0]
    assert turn.pumped and turn.off_foil_s == 0.0
    assert turn.outcome == TOUCHDOWN and turn.outcome_reason == REASON_PUMPED_MARGINAL

    # And the switch is what gates it: off, the same turn flew through.
    cfg_off = TurnConfig(foil_exit_speed_kmh=12.0, pumped_out_is_touchdown=False)
    off = detect_turns(ct, flights, WIND_N, config=cfg_off, pump=pump, evidence=lenient)[0]
    assert off.pumped and off.outcome == FLEW_THROUGH and off.outcome_reason is None


def test_every_touchdown_and_fall_says_why_and_no_fly_through_does():
    """**Engine 0.18.0**: `outcome_reason` is the rung that decided, and None on a fly-through.

    Jan, 7 Sep 2026: *"Can we add a short comment for the user why a jibe is a touchdown or a
    fall?"* The engine writes the code; the words are presentation's. Four shapes, one each.
    """
    # A short touch: off the foil, no stop worth naming.
    touch = _detect(*_jibe_then([1.0] * 2 + [6.0] * 20))[0]
    assert touch.outcome == TOUCHDOWN and touch.outcome_reason == REASON_OFF_FOIL

    # A long stop: a fall, named after the stop.
    fell = _detect(*_jibe_then([0.3] * 11))[0]
    assert fell.outcome == FELL_IN and not fell.submerged
    assert fell.outcome_reason == REASON_STOP

    # The wrist under water: a fall, named after the wrist even though the stop is there too.
    course, speed = _jibe_then([0.3] * 11)
    alt = np.full(len(course), 70.0)
    alt[52:56] = -180.0
    ct = _track(course, speed, alt_m=alt)
    wet = detect_turns(ct, segment_flights(ct), WIND_N)[0]
    assert wet.submerged and wet.outcome == FELL_IN
    assert wet.outcome_reason == REASON_SUBMERGED

    # A fly-through explains nothing, because nothing happened.
    flew = _detect(*_clean_jibe(min_speed=5.0))[0]
    assert flew.outcome == FLEW_THROUGH and flew.outcome_reason is None


def test_pumping_alone_never_overturns_a_clean_fly_through():
    """The rider pumps a wing for many reasons; without a speed dip it stays a fly-through."""
    ct = _track(*_clean_jibe(min_speed=5.0))
    pump = pump_track_from_arrays(*_pump_stream(40.0, 60.0))
    turn = detect_turns(ct, segment_flights(ct), WIND_N, pump=pump)[0]
    assert turn.pumped and turn.outcome == FLEW_THROUGH


def test_a_quiet_wrist_leaves_the_marginal_dip_a_fly_through():
    course, speed = _jibe_then([2.8] * 4)
    ct = _track(course, speed)
    pump = pump_track_from_arrays(*_pump_stream(0.0, 0.0, quiet=0.02))
    turn = detect_turns(ct, segment_flights(ct), WIND_N, pump=pump)[0]
    assert not turn.pumped and turn.outcome == FLEW_THROUGH


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
            assert (turn.stopped_s > cfg.fall_stop_s or turn.submerged)
            assert not turn.borderline
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

    # Torbole 2026-08-07 against Jan's own reading of the session: this was a *learning*
    # day, and roughly two jibes in three cost him the foil -- either pumped back out of it
    # or swum. All three outcomes are well represented; none of them dominates.
    outcomes = summary.jibe_outcomes
    assert outcomes.total == summary.jibes
    assert min(outcomes.flew_through, outcomes.touchdown, outcomes.fell_in) >= 5
    assert outcomes.flew_through < outcomes.touchdown + outcomes.fell_in
    assert outcomes.borderline <= 2                   # the 3-5 s band is all but empty
    assert summary.outcomes.total == summary.turns_counted


@pytest.mark.skipif(not TODAY.exists(), reason="ciq fixture missing")
def test_real_session_pumping_moves_no_verdict():
    """Accel evidence was corroborating and could only ever *promote* a fly-through to a
    touchdown. Since engine 0.18.0 the rung it promoted through is unreachable, so on a real
    class-(a) session the wrist now moves **nothing**: the same turns, the same outcomes, with
    and without the accelerometer.

    The stream is still read and `pumped` is still set -- what the page says about effort is
    untouched. This is the assertion that the *verdict* no longer depends on it.
    """
    from wingfoil_lab.pump import pump_track

    track = parse_fit(TODAY)
    ct = clean(track)
    flights = segment_flights(ct)
    wind = estimate_wind(ct, flights)
    pump = pump_track(track)
    assert pump is not None                           # class (a): SensorLogging is on

    dry_turns = detect_turns(ct, flights, wind)
    wet_turns = detect_turns(ct, flights, wind, pump=pump)
    dry = summarize_turns(dry_turns).jibe_outcomes
    wet = summarize_turns(wet_turns).jibe_outcomes
    assert (wet.flew_through, wet.touchdown, wet.fell_in) \
        == (dry.flew_through, dry.touchdown, dry.fell_in)
    assert [t.outcome_reason for t in wet_turns] == [t.outcome_reason for t in dry_turns]
    # …and the wrist was genuinely heard, so this is not a vacuous comparison.
    assert any(t.pumped for t in wet_turns) and not any(t.pumped for t in dry_turns)


# --- streaks: merged turn + flight-end event list ----------------------------------------

def _seq(*outcomes, counted=True):
    """Counted turns carrying only what a streak reads: end time and outcome.

    `counted` may be a tuple to interleave rejected sweeps. End times are 10, 20, 30 ...
    so a flight end can be dropped between any two of them.
    """
    flags = counted if isinstance(counted, tuple) else (counted,) * len(outcomes)
    return [Turn(start_t=10.0 * (i + 1) - 1, end_t=10.0 * (i + 1), min_t=10.0 * (i + 1),
                 kind=JIBE, counted=c, net_deg=180.0, peak_rate_deg_s=30.0,
                 direction="port", side="port", entry_kn=12.0, min_kn=9.0, exit_kn=10.0,
                 entry_kn_doppler=12.0, min_kn_doppler=9.0, score=0.75, success=True,
                 twa_in_deg=90.0, twa_out_deg=-90.0, outcome=o)
            for i, (o, c) in enumerate(zip(outcomes, flags))]


def _end(t, outcome, owner=None, truncated=False):
    """A flight end at `t`; `owner` is an index into the turn list, as `flightend` sets it."""
    return FlightEnd(flight_index=0, t=float(t), outcome=outcome, truncated=truncated,
                     owned_by_turn=owner)


def test_streaks_are_zero_without_counted_turns():
    assert streaks([]) == (0, 0)
    assert streaks(_seq(FLEW_THROUGH, FLEW_THROUGH, counted=False)) == (0, 0)
    # A flight end on its own cannot make a streak either -- only turns lengthen a run.
    assert streaks([], [_end(5, GLIDE_OUT)]) == (0, 0)


def test_touchdown_extends_the_dry_streak_but_breaks_the_flown_one():
    """Staying out of the water and carrying it clean are different claims."""
    assert streaks(_seq(FLEW_THROUGH, TOUCHDOWN, FLEW_THROUGH)) == (3, 1)


def test_a_fall_resets_both_streaks_and_the_longest_run_wins():
    assert streaks(_seq(FLEW_THROUGH, FLEW_THROUGH, FELL_IN, FLEW_THROUGH)) == (2, 2)
    assert streaks(_seq(FLEW_THROUGH, FLEW_THROUGH, FLEW_THROUGH,
                        FELL_IN, FLEW_THROUGH)) == (3, 3)


def test_a_borderline_touchdown_counts_as_a_touchdown():
    """`borderline` is a flag on a touchdown, not a fourth outcome: dry survives it."""
    turns = _seq(FLEW_THROUGH, TOUCHDOWN, FLEW_THROUGH)
    turns[1].borderline = True
    assert streaks(turns) == (3, 1)


def test_rejected_sweeps_neither_extend_nor_break_a_streak_as_turns():
    """A bear-away is not a maneuver, so *as a turn* it is invisible either way."""
    assert streaks(_seq(FLEW_THROUGH, FELL_IN, FLEW_THROUGH,
                        counted=(True, False, True))) == (2, 2)
    assert streaks(_seq(FLEW_THROUGH, FLEW_THROUGH, FLEW_THROUGH,
                        counted=(True, False, True))) == (2, 2)


# --- ...but their consequences are visible, and so are straight-line ones ----------------

def test_a_straight_line_fall_inside_a_flown_run_breaks_it():
    """The bug the first cut of this metric had: a swim between two clean jibes.

    Nothing in the turn channel records it -- the rider simply fell in on a reach -- and a
    turn-only streak reads four clean jibes in a row where the rider remembers two.
    """
    turns = _seq(FLEW_THROUGH, FLEW_THROUGH, FLEW_THROUGH, FLEW_THROUGH)
    assert streaks(turns) == (4, 4)                       # blind to it
    broken = streaks(turns, [_end(25, FELL_IN)])          # ...between turns 2 and 3
    assert broken == (2, 2)


def test_a_fall_owned_by_a_rejected_sweep_breaks_the_streak():
    """The sweep is not a maneuver; the swim it ended is still a swim."""
    turns = _seq(FLEW_THROUGH, FELL_IN, FLEW_THROUGH, FLEW_THROUGH,
                 counted=(True, False, True, True))
    # The bear-away is turn index 1, and the flight end it owns lands just after it.
    assert streaks(turns, [_end(21, FELL_IN, owner=1)]) == (2, 2)
    # Without the end, the rejected turn alone leaves the run untouched.
    assert streaks(turns) == (3, 3)


def test_an_end_owned_by_a_counted_turn_is_not_charged_twice():
    """The turn's own outcome already speaks for it (flightend ownership)."""
    turns = _seq(FLEW_THROUGH, FELL_IN, FLEW_THROUGH, FLEW_THROUGH)
    owned = streaks(turns, [_end(21, FELL_IN, owner=1)])
    assert owned == streaks(turns) == (2, 2)


def test_a_straight_line_touchdown_breaks_flew_but_not_dry():
    """He got wet without swimming: the dry run survives, the clean run does not."""
    turns = _seq(FLEW_THROUGH, FLEW_THROUGH, FLEW_THROUGH)
    assert streaks(turns, [_end(15, TOUCHDOWN)]) == (3, 2)


def test_glide_outs_unknowns_and_truncated_ends_change_nothing():
    turns = _seq(FLEW_THROUGH, FLEW_THROUGH, FLEW_THROUGH)
    for end in (_end(15, GLIDE_OUT), _end(15, UNKNOWN),
                _end(15, UNKNOWN, truncated=True),
                _end(15, FELL_IN, truncated=True)):   # a stopped recording says nothing
        assert streaks(turns, [end]) == (3, 3), end.outcome


def test_non_turn_events_never_lengthen_a_run():
    """Only a maneuver the rider carried can add to a streak."""
    turns = _seq(FLEW_THROUGH, FLEW_THROUGH)
    assert streaks(turns, [_end(t, GLIDE_OUT) for t in (5, 15, 25, 35)]) == (2, 2)


def test_events_are_merged_in_time_order_not_list_order():
    turns = _seq(FELL_IN, FLEW_THROUGH, FLEW_THROUGH)
    turns.reverse()                                   # list order now flew, flew, fell
    assert streaks(turns) == (2, 2)                   # end order still fell, flew, flew
    # ...and an end sorts into the middle of the turn list by its own timestamp.
    assert streaks(turns, [_end(25, FELL_IN)]) == (1, 1)


def test_summary_carries_the_streaks():
    turns = _seq(FLEW_THROUGH, TOUCHDOWN, FLEW_THROUGH, FELL_IN, FLEW_THROUGH)
    s = summarize_turns(turns, [_end(15, GLIDE_OUT)])
    assert (s.longest_dry_streak, s.longest_flew_streak) == (3, 1)
    assert s.turns_counted == 5


def test_flown_streak_never_exceeds_the_dry_one():
    ends = [_end(15, FELL_IN), _end(35, TOUCHDOWN)]
    for outcomes in ((FLEW_THROUGH, TOUCHDOWN, FELL_IN, FLEW_THROUGH, FLEW_THROUGH),
                     (TOUCHDOWN, TOUCHDOWN, TOUCHDOWN),
                     (FELL_IN, FELL_IN)):
        for e in ([], ends):
            dry, flew = streaks(_seq(*outcomes), e)
            assert flew <= dry


@pytest.mark.skipif(not TODAY.exists(), reason="ciq fixture missing")
def test_real_session_streaks_match_the_merged_event_sequence():
    """Recompute the runs from the two channels, independently of the summarizer."""
    ct = clean(parse_fit(TODAY))
    flights = segment_flights(ct)
    turns = detect_turns(ct, flights, estimate_wind(ct, flights))
    ends = classify_flight_ends(ct, flights, turns)
    s = summarize_turns(turns, ends)

    counted = {i for i, t in enumerate(turns) if t.counted}
    events = [(t.end_t, 1, t.outcome, t.borderline) for i, t in enumerate(turns)
              if i in counted]
    events += [(e.t, 0, e.outcome, False) for e in ends
               if not e.truncated and e.owned_by_turn not in counted]
    assert any(ev[1] == 0 for ev in events), "the fixture must exercise the merge"

    dry = flew = best_dry = best_flew = 0
    for _t, is_turn, outcome, borderline in sorted(events, key=lambda e: (e[0], e[1])):
        if is_turn:
            dry = 0 if outcome == FELL_IN else dry + 1
            flew = flew + 1 if (outcome == FLEW_THROUGH and not borderline) else 0
            best_dry, best_flew = max(best_dry, dry), max(best_flew, flew)
        else:
            if outcome == FELL_IN:
                dry = 0
            if outcome in (FELL_IN, TOUCHDOWN):
                flew = 0
    assert (s.longest_dry_streak, s.longest_flew_streak) == (best_dry, best_flew)
    assert s.longest_flew_streak <= s.longest_dry_streak <= s.turns_counted
    # The merged rule can only ever be stricter than the turn-only one it replaced.
    turn_only = streaks(turns)
    assert s.longest_dry_streak <= turn_only[0]
    assert s.longest_flew_streak <= turn_only[1]


# --- 360 spins (EXPERIMENTAL, dark unless detectThreeSixty is set) ---------------------

SPIN_ON = TurnConfig(detect_three_sixty=True)
SPIN_KMH = 15.0                                   # the speed the synthetic spins are ridden at


def _spin(deg=360.0, secs=6, kmh=SPIN_KMH, before=30, after=30):
    """A constant-rate `deg` sweep ridden at `kmh`, entered and left on a straight leg."""
    v = kmh / 3.6
    return _join(_leg(90.0, before, speed=v),
                 _ramp(90.0, 90.0 + deg, secs + 1, [v] * (secs + 1)),
                 _leg(90.0 + deg, after, speed=v))


def _spins(course, speed, config=SPIN_ON):
    ct = _track(course, speed)
    return [t for t in detect_turns(ct, segment_flights(ct), WIND_N, config)
            if t.kind == THREE_SIXTY]


def test_full_rotation_on_foil_is_a_three_sixty():
    turns = _spins(*_spin())
    assert len(turns) == 1
    spin = turns[0]
    assert spin.kind == THREE_SIXTY
    assert not spin.counted                       # never a tack, never a jibe
    assert spin.net_deg == pytest.approx(360.0, abs=25.0)
    assert spin.end_t - spin.start_t <= SPIN_ON.three_sixty_max_s
    assert spin.direction == "starboard"


def test_the_same_rotation_at_walking_pace_is_not_a_three_sixty():
    """The gate the whole detector rests on: a stopped rider's COG spins freely.

    Same geometry, same 360 deg, ridden at 3 km/h -- under `foilEntrySpeed` at the sweep
    start and under `threeSixtyMinKmh` inside it, so nothing about the shape can save it.
    """
    assert _spins(*_spin(kmh=3.0)) == []


def test_a_jibe_is_not_a_three_sixty():
    assert _spins(*_clean_jibe()) == []


def test_a_tack_and_a_jibe_around_a_straight_are_not_merged_into_one():
    """Two same-direction sweeps with three seconds of sailing between them.

    Refused twice over: they sum to 220 deg, under `threeSixtyMinDeg`, and the eleven
    seconds from the first sweep's start to the second's end are over `threeSixtyMaxS`.
    The straight between them is the point -- it is monotone, so monotonicity alone would
    have let the pair through.
    """
    v = SPIN_KMH / 3.6
    course, speed = _join(_leg(90.0, 30, speed=v),
                          _ramp(90.0, 200.0, 5, [v] * 5),        # ~a tack, 110 deg
                          _leg(200.0, 3, speed=v),               # 3 s straight
                          _ramp(200.0, 310.0, 5, [v] * 5),       # ~a jibe, same direction
                          _leg(310.0, 30, speed=v))
    assert _spins(course, speed) == []


def test_a_rotation_that_backs_off_mid_sweep_is_not_monotone():
    """`threeSixtyReversalDeg`: a spin does not change its mind halfway round."""
    v = SPIN_KMH / 3.6
    course, speed = _join(_leg(90.0, 30, speed=v),
                          _ramp(90.0, 290.0, 5, [v] * 5),        # 200 deg clockwise
                          _ramp(290.0, 250.0, 2, [v] * 2),       # 40 deg back the other way
                          _ramp(250.0, 450.0, 5, [v] * 5),       # 200 deg on round again
                          _leg(450.0, 30, speed=v))
    assert _spins(course, speed) == []


def test_the_detector_is_dark_by_default():
    """The same track, the shipped config: no spin exists at all."""
    course, speed = _spin()
    assert [t.kind for t in _detect(course, speed)].count(THREE_SIXTY) == 0
    assert _spins(course, speed, config=TurnConfig()) == []


def test_a_three_sixty_feeds_its_own_count_and_nothing_else():
    ct = _track(*_spin())
    flights = segment_flights(ct)
    turns = detect_turns(ct, flights, WIND_N, SPIN_ON)
    dark = detect_turns(ct, flights, WIND_N)

    spun, plain = summarize_turns(turns, config=SPIN_ON), summarize_turns(dark)
    assert spun.three_sixties == 1
    assert plain.three_sixties is None            # not 0: nobody looked
    # Every maneuver tally reads exactly as it did with the detector down.
    assert (spun.turns_counted, spun.rejected) == (plain.turns_counted, plain.rejected)
    assert (spun.tacks, spun.jibes) == (plain.tacks, plain.jibes)
    assert spun.outcomes.total == plain.outcomes.total
    assert (spun.longest_dry_streak, spun.longest_flew_streak) == \
           (plain.longest_dry_streak, plain.longest_flew_streak)


def test_the_count_is_zero_not_absent_when_the_detector_ran_and_found_nothing():
    turns = _detect(*_clean_jibe(), config=SPIN_ON)
    assert summarize_turns(turns, config=SPIN_ON).three_sixties == 0


def test_the_spin_pass_leaves_the_maneuvers_it_overlaps_alone():
    """Additive by construction: whatever the main scan said about the same water stands."""
    ct = _track(*_spin())
    flights = segment_flights(ct)
    plain = [(t.kind, t.start_t, t.end_t) for t in detect_turns(ct, flights, WIND_N)]
    both = [(t.kind, t.start_t, t.end_t)
            for t in detect_turns(ct, flights, WIND_N, SPIN_ON) if t.kind != THREE_SIXTY]
    assert both == plain
