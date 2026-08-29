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
from wingfoil_lab.turns import (BEAR_AWAY, COUNTED_TYPES, FELL_IN, FLEW_THROUGH, JIBE,
                                OUTCOMES, TACK, TOUCHDOWN, UNCLASSIFIED, Turn, TurnConfig,
                                detect_turns, streaks, summarize_turns)
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
    """The window runs to *recovery*, so a slow collapse 6-12 s out still belongs here."""
    turn = _detect(*_mush_out())[0]
    assert turn.outcome == FELL_IN
    assert turn.outcome_window_s > 5.0            # the old fixed 5 s tail saw none of this


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


def test_pumping_plus_a_marginal_speed_dip_is_a_touchdown():
    """Speed says the foil went marginal, accel says he pumped it out -- together: touchdown."""
    course, speed = _jibe_then([2.8] * 4)         # above foilExitSpeed, below foilEntrySpeed
    assert _detect(course, speed)[0].outcome == FLEW_THROUGH       # speed alone: not enough

    ct = _track(course, speed)
    pump = pump_track_from_arrays(*_pump_stream(48.0, 56.0))
    turn = detect_turns(ct, segment_flights(ct), WIND_N, pump=pump)[0]
    assert turn.pumped and turn.outcome == TOUCHDOWN


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
def test_real_session_pumping_only_adds_touchdowns():
    """Accel evidence is corroborating: it may promote fly-throughs, never demote a fall."""
    from wingfoil_lab.pump import pump_track

    track = parse_fit(TODAY)
    ct = clean(track)
    flights = segment_flights(ct)
    wind = estimate_wind(ct, flights)
    pump = pump_track(track)
    assert pump is not None                           # class (a): SensorLogging is on

    dry = summarize_turns(detect_turns(ct, flights, wind)).jibe_outcomes
    wet = summarize_turns(detect_turns(ct, flights, wind, pump=pump)).jibe_outcomes
    assert wet.fell_in == dry.fell_in
    assert wet.touchdown > dry.touchdown
    assert wet.flew_through == dry.flew_through - (wet.touchdown - dry.touchdown)


# --- streaks: merged turn + flight-end event list ----------------------------------------

def _seq(*outcomes, counted=True):
    """Counted turns carrying only what a streak reads: end time and outcome.

    `counted` may be a tuple to interleave rejected sweeps. End times are 10, 20, 30 ...
    so a flight end can be dropped between any two of them.
    """
    flags = counted if isinstance(counted, tuple) else (counted,) * len(outcomes)
    return [Turn(start_t=10.0 * (i + 1) - 1, end_t=10.0 * (i + 1), min_t=10.0 * (i + 1),
                 kind=JIBE, counted=c, net_deg=180.0, peak_rate_deg_s=30.0,
                 direction="port", side="port", entry_kn=12.0, min_kn=9.0,
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
