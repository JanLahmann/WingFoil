"""HR cost of pumping, on constructed HR traces and on the fixtures that carry one.

The traces are built sample-by-sample (1 Hz unless a case is about a ragged cadence), so
every expected baseline, peak, cost and half-decay below is arithmetic rather than a guess.
Takeoffs are hand-built `Takeoff` records for the same reason: this module's job is what HR
did around a given anchor, and a detector-derived anchor would only blur the assertion. One
integration test per fixture then runs the whole pipeline.
"""

from pathlib import Path

import numpy as np
import pandas as pd
import pytest

from wingfoil_lab.flight import Flight, FlightResult
from wingfoil_lab.flightend import FELL_IN, GLIDE_OUT, FlightEnd
from wingfoil_lab.goldens import analyze
from wingfoil_lab.hrcost import (SWIM, TAKEOFF, Coverage, HrConfig, analyze_hr, fatigue_curve,
                                 hr_track, hr_track_from_arrays, pump_vs_cruise, summarize_hr,
                                 swim_events, takeoff_events)
from wingfoil_lab.parse import RawTrack
from wingfoil_lab.pump import pump_track_from_arrays
from wingfoil_lab.takeoff import FAILED, SUCCESS, PumpEpisode, Takeoff, TakeoffAnalysis

FIXTURES = Path(__file__).resolve().parents[2] / "fixtures"
CIQ = FIXTURES / "sessions/ciq/2026-08-07-0754_nago-torbole-windsurfen_ciq.fit"
NATIVE = FIXTURES / "sessions/windsurf-native/2026-08-05-0827_nago-torbole-windsurfen_native.fit"

CFG = HrConfig()
# Some cases need a trace that sits at one value for minutes on end (a whole session of
# cruising, a bin's worth of resting HR). That is exactly what `hrFlatlineMax` exists to
# reject, so those cases disable it rather than dress the trace up with fake jitter.
NO_FLATLINE = HrConfig(flatline_max_s=1e6)


# --- trace builders ---------------------------------------------------------------------

def _hr(values, t=None, config=None):
    """An HrTrack from 1 Hz `values` (or explicit sample times)."""
    t = np.arange(len(values), dtype=float) if t is None else np.asarray(t, float)
    return hr_track_from_arrays(t, np.asarray(values, float), config)


def _ramp(lo, hi, n):
    return list(np.linspace(lo, hi, n))


def _flat(value, n):
    return [float(value)] * n


def _takeoff(t, run_start_t, strokes=8, truncated=False):
    """One flight start whose run opened at `run_start_t` -- the HR anchor."""
    return Takeoff(flight_index=0, t=t, run_start_t=run_start_t,
                   duration_s=t - run_start_t, speed_rise_s=2.0,
                   pumps_to_takeoff=strokes, truncated=truncated)


def _analysis(*takeoffs, episodes=()):
    return TakeoffAnalysis(takeoffs=list(takeoffs), episodes=list(episodes), has_accel=True)


def _event(hr, *takeoffs, config=CFG):
    return takeoff_events(hr, _analysis(*takeoffs), config)[0]


# The canonical attempt, 1 Hz: 40 s resting at 90 bpm, the effort starts at t = 40, HR climbs
# to 110 by t = 60, holds until t = 70, then decays back to 90 at 0.5 bpm/s (reaching 100 --
# halfway -- at t = 90), and rests there. The flight itself starts at t = 50.
CLIMB = (_flat(90, 41) + _ramp(90, 110, 21)[1:] + _flat(110, 10)
         + _ramp(110, 90, 41)[1:] + _flat(90, 40))
ANCHOR, FLIGHT = 40.0, 50.0


# --- the per-takeoff cost ---------------------------------------------------------------

def test_a_takeoff_reports_the_hr_rise_from_the_effort_to_its_peak():
    ev = _event(_hr(CLIMB), _takeoff(t=FLIGHT, run_start_t=ANCHOR))
    assert ev.kind == TAKEOFF and ev.valid and not ev.approximate
    assert ev.baseline_bpm == 90.0                    # median of [30, 40]
    assert ev.peak_bpm == 110.0
    assert ev.cost_bpm == 20.0
    assert ev.peak_lag_s == pytest.approx(20.0)       # first sample at the top
    assert ev.baseline_coverage == 1.0 and ev.peak_coverage == 1.0


def test_the_anchor_is_the_start_of_the_effort_not_the_flight():
    """Anchoring on ON_FOIL would start measuring after the pumping had already been going
    for ten seconds, and charge the attempt with only what was left of the rise."""
    hr = _hr(CLIMB)
    assert _event(hr, _takeoff(t=FLIGHT, run_start_t=ANCHOR)).cost_bpm == 20.0
    late = _event(hr, _takeoff(t=FLIGHT, run_start_t=FLIGHT))
    assert late.baseline_bpm == 95.0 and late.cost_bpm == 15.0


def test_the_peak_is_only_searched_over_the_configured_window():
    short = HrConfig(peak_window_s=5.0)
    ev = _event(_hr(CLIMB), _takeoff(t=FLIGHT, run_start_t=ANCHOR), config=short)
    assert ev.peak_bpm == 95.0 and ev.cost_bpm == 5.0


def test_hr_falling_through_an_attempt_reports_a_negative_cost_not_a_zero():
    """Clamping would turn "he was still recovering when he started" into "this cost
    nothing", and the two are different facts. The sign is reported."""
    falling = _flat(140, 30) + _ramp(140, 100, 41)[1:] + _flat(100, 50)
    ev = _event(_hr(falling), _takeoff(t=FLIGHT, run_start_t=ANCHOR))
    assert ev.valid and ev.cost_bpm == pytest.approx(-5.0)


def test_a_takeoff_without_strokes_is_flagged_approximate():
    """No accelerometer (or a genuinely free takeoff): the anchor is the speed rise alone."""
    ev = _event(_hr(CLIMB), _takeoff(t=FLIGHT, run_start_t=ANCHOR, strokes=None))
    assert ev.valid and ev.approximate and ev.strokes is None


def test_a_truncated_run_anchors_on_the_flight_start_and_says_it_is_approximate():
    k = _takeoff(t=FLIGHT, run_start_t=ANCHOR, strokes=None, truncated=True)
    ev = _event(_hr(CLIMB), k)
    assert ev.t == FLIGHT and ev.approximate


# --- validity: gaps, flatlines, nonsense ------------------------------------------------

def test_a_gap_over_the_baseline_window_yields_no_cost_and_a_reported_coverage():
    """Smart Recording resumes mid-attempt: there is no "HR before the effort" to subtract."""
    t = np.arange(len(CLIMB), dtype=float)
    t[35:] += 60.0                                    # a 61 s hole 5 s before the anchor
    ev = _event(_hr(CLIMB, t=t), _takeoff(t=FLIGHT + 60.0, run_start_t=ANCHOR + 60.0))
    assert ev.cost_bpm is None and not ev.valid
    assert ev.baseline_bpm is None and ev.peak_bpm is None
    assert ev.baseline_coverage == pytest.approx(0.5)
    assert ev.peak_coverage == 1.0                    # the peak side was fine; the cost is not


def test_a_gap_over_the_peak_window_yields_no_cost_either():
    t = np.arange(len(CLIMB), dtype=float)
    t[45:] += 120.0
    ev = _event(_hr(CLIMB, t=t), _takeoff(t=FLIGHT, run_start_t=ANCHOR))
    assert ev.cost_bpm is None and ev.peak_coverage < CFG.min_coverage


def test_smart_recordings_ragged_cadence_is_not_a_gap():
    """1-9 s between samples is how Garmin writes a native session, and HR is a slow channel:
    the cleaner's ~4 s speed-gap rule would throw the whole channel away for nothing."""
    t = np.concatenate([np.arange(0.0, 40.0, 6.0), np.arange(40.0, 110.0, 3.0)])
    values = np.interp(t, np.arange(len(CLIMB), dtype=float), CLIMB)
    ev = _event(_hr(values, t=t), _takeoff(t=FLIGHT, run_start_t=ANCHOR))
    assert ev.valid and ev.cost_bpm == pytest.approx(20.0, abs=1.0)
    assert ev.baseline_coverage == 1.0


def test_a_stuck_sensor_is_not_a_steady_heart_rate():
    """An optical sensor that has lost the wrist repeats its last value. A run of identical
    bpm longer than `hrFlatlineMax` is dropped whole -- there is no telling which end of it
    was still the rider."""
    hr = _hr(_flat(90, 200))
    assert not hr.usable.any()
    assert hr.coverage(0.0, 100.0) == 0.0
    assert _event(hr, _takeoff(t=FLIGHT, run_start_t=ANCHOR)).cost_bpm is None


def test_a_short_steady_stretch_survives():
    """40 s at one value is a plausible heart, not a stuck sensor -- the guard is duration."""
    hr = _hr(_flat(90, 41) + _ramp(90, 110, 21)[1:] + _flat(110, 40))
    assert hr.usable.all()
    assert _event(hr, _takeoff(t=FLIGHT, run_start_t=ANCHOR)).cost_bpm == 20.0


def test_a_flatline_run_is_cut_at_a_recording_gap():
    """A session paused for ten minutes at 90 bpm and resumed at 90 bpm is not a stuck
    sensor: neither side of the hole is long enough to be one."""
    values = _flat(90, 40) + _flat(90, 40)
    t = np.arange(80.0)
    t[40:] += 600.0
    assert _hr(values, t=t).usable.all()


def test_implausible_values_are_dropped_rather_than_averaged_in():
    trace = list(CLIMB)
    trace[45] = 250.0                                 # a sensor spike, not a heart rate
    trace[46] = 0.0
    hr = _hr(trace)
    assert hr.usable.sum() == len(trace) - 2
    ev = _event(hr, _takeoff(t=FLIGHT, run_start_t=ANCHOR))
    assert ev.peak_bpm == 110.0                       # the spike never becomes the peak


def test_a_source_without_a_heart_rate_channel_degrades_to_nothing():
    track = RawTrack(path="<no hr>", records=pd.DataFrame({"t": [0.0, 1.0]}))
    assert hr_track(track) is None
    a = analyze_hr(track, FlightResult([], 0.0, 0.0, 0, None), _analysis())
    assert not a.has_hr and a.takeoff_events == [] and a.bins == []
    assert not a.summary.has_hr and a.summary.avg_takeoff_cost_bpm is None


# --- recovery ---------------------------------------------------------------------------

def test_recovery_is_the_time_to_fall_halfway_back_to_the_pre_effort_baseline():
    """Peak 110 against a 90 baseline: halfway is 100 bpm, reached at t = 90."""
    ev = _event(_hr(CLIMB), _takeoff(t=FLIGHT, run_start_t=ANCHOR))
    assert ev.recovery_half_s == pytest.approx(30.0)  # 10 s of plateau + 20 s of decay
    assert not ev.recovery_censored


def test_a_decay_slower_than_the_window_is_censored_not_blamed_on_the_rider():
    slow = HrConfig(recovery_window_s=5.0)
    ev = _event(_hr(CLIMB), _takeoff(t=FLIGHT, run_start_t=ANCHOR), config=slow)
    assert ev.recovery_half_s is None and ev.recovery_censored


def test_a_gap_after_the_peak_ends_the_recovery_search():
    """HR was 110 before a ten-minute hole and 90 after it. It did not decay in 5 s."""
    t = np.arange(len(CLIMB), dtype=float)
    t[65:] += 600.0
    ev = _event(_hr(CLIMB, t=t), _takeoff(t=FLIGHT, run_start_t=ANCHOR))
    assert ev.cost_bpm == 20.0
    assert ev.recovery_half_s is None and ev.recovery_censored


def test_an_attempt_that_never_raised_the_heart_rate_has_no_recovery_to_measure():
    ev = _event(_hr(_flat(90, 40) + _ramp(90, 92, 111)),
                _takeoff(t=FLIGHT, run_start_t=ANCHOR))
    assert ev.cost_bpm is not None and ev.cost_bpm < CFG.min_rise_bpm
    assert ev.recovery_half_s is None and not ev.recovery_censored


# --- swims ------------------------------------------------------------------------------

def _end(index, t, outcome):
    return FlightEnd(flight_index=index, t=t, outcome=outcome)


def test_only_the_flight_ends_that_fell_in_become_swim_events():
    evs = swim_events(_hr(CLIMB), [_end(0, ANCHOR, FELL_IN), _end(1, 90.0, GLIDE_OUT)], [])
    assert len(evs) == 1
    assert evs[0].kind == SWIM and evs[0].index == 0 and evs[0].cost_bpm == 20.0


def test_swims_are_sorted_and_measured_like_takeoffs():
    evs = swim_events(_hr(CLIMB), [_end(1, 80.0, FELL_IN), _end(0, ANCHOR, FELL_IN)], [])
    assert [e.t for e in evs] == [ANCHOR, 80.0]
    assert all(e.kind == SWIM for e in evs)


# --- pumping vs cruising ----------------------------------------------------------------

def _wrist(duration, *bursts, hz=25.0, cadence_hz=1.2, amp_g=0.6):
    t = np.arange(0.0, duration, 1.0 / hz)
    mag = np.ones_like(t)
    for t0, t1 in bursts:
        on = (t >= t0) & (t <= t1)
        mag[on] += amp_g * np.sin(2 * np.pi * cadence_hz * t[on])
    return pump_track_from_arrays(t, mag)


def _one_flight(duration=200.0):
    return FlightResult([Flight(0.0, duration, 0.0, 0.0, duration)], duration, 100.0, 1, None)


def test_pumping_reads_hotter_than_cruising_once_the_lag_is_allowed_for():
    """HR rises 15 bpm ten seconds after each burst -- exactly the delay `hrLag` exists for."""
    trace = _flat(100, 40) + _flat(115, 30) + _flat(100, 130)
    pc = pump_vs_cruise(_hr(trace, config=NO_FLATLINE), _wrist(200.0, (30.0, 40.0)),
                        _one_flight())
    assert pc.pumping_spans == 1 and pc.cruising_spans >= 1
    assert pc.pumping_bpm == pytest.approx(115.0, abs=1.0)
    assert pc.cruising_bpm == pytest.approx(100.0, abs=1.0)
    assert pc.delta_bpm == pytest.approx(15.0, abs=1.5)
    assert pc.pumping_coverage == pytest.approx(1.0)


def test_without_an_accelerometer_there_is_no_pumping_side_and_no_delta():
    pc = pump_vs_cruise(_hr(_flat(100, 60) + _ramp(100, 120, 141)), None, _one_flight())
    assert pc.pumping_bpm is None and pc.delta_bpm is None
    assert pc.cruising_bpm is not None and pc.cruising_spans == 1


def test_cruising_never_includes_the_seconds_around_a_burst():
    """The guard band is what stops the lagged pumping HR from being averaged into cruising
    and quietly closing the gap the metric is trying to measure."""
    trace = _flat(100, 40) + _flat(115, 30) + _flat(100, 130)
    pc = pump_vs_cruise(_hr(trace, config=NO_FLATLINE), _wrist(200.0, (30.0, 40.0)),
                        _one_flight())
    assert pc.cruising_bpm < float(np.mean(trace))
    assert pc.cruising_span_s < 200.0


# --- the fatigue curve ------------------------------------------------------------------

def _late_session():
    """Three flights over 13 minutes, with two failed bursts clustered in the middle bin."""
    hr = _hr(_flat(90, 300) + _flat(100, 300) + _flat(105, 200), config=NO_FLATLINE)
    takeoffs = [_takeoff(t=FLIGHT, run_start_t=ANCHOR), _takeoff(t=170.0, run_start_t=160.0),
                _takeoff(t=470.0, run_start_t=460.0)]
    for i, k in enumerate(takeoffs):
        k.flight_index = i
    episodes = [PumpEpisode(start_t=ANCHOR, end_t=49.0, strokes=8, outcome=SUCCESS),
                PumpEpisode(start_t=500.0, end_t=510.0, strokes=8, outcome=FAILED),
                PumpEpisode(start_t=560.0, end_t=570.0, strokes=8, outcome=FAILED)]
    return hr, _analysis(*takeoffs, episodes=episodes)


def test_the_fatigue_curve_bins_attempts_and_cost_over_session_time():
    hr, analysis = _late_session()
    bins = fatigue_curve(hr, analysis, takeoff_events(hr, analysis), bin_minutes=5.0)
    assert len(bins) == 3
    assert [b.successes for b in bins] == [2, 1, 0]
    assert [b.failed for b in bins] == [0, 2, 0]      # failures land on their first stroke
    assert bins[0].success_pct == 100.0
    assert bins[1].success_pct == pytest.approx(100.0 / 3.0)
    assert bins[2].attempts == 0 and bins[2].success_pct is None
    assert bins[0].mean_bpm == pytest.approx(90.0, abs=1.0)


def test_equal_bins_are_available_for_short_sessions():
    hr, analysis = _late_session()
    bins = fatigue_curve(hr, analysis, takeoff_events(hr, analysis), n_bins=3)
    assert len(bins) == 3
    assert bins[0].start_t == 0.0 and bins[-1].end_t == pytest.approx(hr.t[-1])


def test_every_bin_carries_the_coverage_behind_its_average():
    hr, analysis = _late_session()
    bins = fatigue_curve(hr, analysis, takeoff_events(hr, analysis), bin_minutes=5.0)
    for b in bins:
        assert b.cost_coverage.total == b.successes
        assert b.cost_coverage.valid <= b.cost_coverage.total
        if b.cost_coverage.valid == 0:
            assert b.avg_cost_bpm is None


def test_a_bin_records_the_hr_he_started_its_attempts_at():
    """A late rise shrinks because the baseline has drifted up, not because the effort got
    cheaper -- so the baseline is reported beside the cost."""
    hr, analysis = _late_session()
    bins = fatigue_curve(hr, analysis, takeoff_events(hr, analysis), bin_minutes=5.0)
    assert bins[0].avg_baseline_bpm == pytest.approx(90.0)
    assert bins[1].avg_baseline_bpm == pytest.approx(100.0)


# --- the summary ------------------------------------------------------------------------

def test_the_summary_reports_coverage_beside_every_average():
    hr = _hr(CLIMB)
    good = _takeoff(t=FLIGHT, run_start_t=ANCHOR)
    blind = _takeoff(t=400.0, run_start_t=390.0)      # past the end of the trace
    s = summarize_hr(hr, takeoff_events(hr, _analysis(good, blind)), [])
    assert s.has_hr
    assert s.takeoff_cost_coverage.valid == 1 and s.takeoff_cost_coverage.total == 2
    assert s.takeoff_cost_coverage.pct == 50.0
    assert s.avg_takeoff_cost_bpm == 20.0             # the invalid one is not a zero
    assert "1/2" in str(s.takeoff_cost_coverage)


def test_bpm_per_stroke_is_pooled_and_the_spread_is_shown_beside_it():
    hr = _hr(CLIMB)
    evs = takeoff_events(hr, _analysis(_takeoff(t=FLIGHT, run_start_t=ANCHOR, strokes=10)))
    s = summarize_hr(hr, evs, [])
    assert s.bpm_per_stroke == pytest.approx(2.0)     # 20 bpm over 10 strokes
    assert s.median_bpm_per_stroke == pytest.approx(2.0)
    assert s.bpm_per_stroke_coverage.valid == 1


def test_bpm_per_stroke_is_none_without_stroke_counts():
    hr = _hr(CLIMB)
    evs = takeoff_events(hr, _analysis(_takeoff(t=FLIGHT, run_start_t=ANCHOR, strokes=None)))
    s = summarize_hr(hr, evs, [])
    assert s.bpm_per_stroke is None and s.bpm_per_stroke_coverage.valid == 0
    assert s.avg_takeoff_cost_bpm == 20.0             # the cost itself is still measured


def test_recovery_coverage_counts_the_attempts_that_actually_rose():
    hr = _hr(CLIMB)
    flat = _hr(_flat(90, 40) + _ramp(90, 92, 111))
    rose = takeoff_events(hr, _analysis(_takeoff(t=FLIGHT, run_start_t=ANCHOR)))
    still = takeoff_events(flat, _analysis(_takeoff(t=FLIGHT, run_start_t=ANCHOR)))
    assert summarize_hr(hr, rose, []).takeoff_recovery_coverage == Coverage(1, 1)
    assert summarize_hr(flat, still, []).takeoff_recovery_coverage == Coverage(0, 0)


def test_coverage_of_nothing_is_not_a_percentage():
    assert Coverage().pct is None
    assert str(Coverage()) == "0/0"


# --- real fixtures ------------------------------------------------------------------------

@pytest.mark.skipif(not CIQ.exists(), reason="ciq fixture missing")
def test_real_ciq_session_hr_cost():
    """2026-08-07 Torbole: 1 Hz optical HR, every takeoff anchored on its own pump burst."""
    a = analyze(CIQ)
    h = analyze_hr(a.track, a.flights, a.takeoffs, a.flight_ends, a.pump, a.turns)
    s = h.summary

    assert h.has_hr and s.has_hr
    assert len(h.takeoff_events) == a.flights.flight_count
    assert s.takeoff_cost_coverage.valid == s.takeoff_cost_coverage.total  # nothing dropped
    assert s.approximate_takeoffs == 0                # class (a): every anchor is a burst
    assert 0.0 < s.avg_takeoff_cost_bpm < 30.0
    assert 5.0 < s.median_peak_lag_s < 30.0           # optical HR trails the effort
    assert s.pump_cruise.delta_bpm > 0.0              # HR *is* higher when pumping
    assert s.bpm_per_stroke is not None
    assert s.median_takeoff_recovery_s is not None
    assert len(h.swim_events) > 0                     # a learning day has swims
    assert h.bins and sum(b.successes for b in h.bins) == a.flights.flight_count

    for e in h.takeoff_events:
        assert e.kind == TAKEOFF
        assert e.baseline_coverage >= CFG.min_coverage
        if e.recovery_half_s is not None:
            assert 0.0 < e.recovery_half_s <= CFG.recovery_window_s


@pytest.mark.skipif(not NATIVE.exists(), reason="native fixture missing")
def test_a_native_session_still_gets_an_approximate_cost():
    """No accelerometer and Smart Recording: every anchor is the speed rise, flagged."""
    a = analyze(NATIVE)
    h = analyze_hr(a.track, a.flights, a.takeoffs, a.flight_ends, a.pump, a.turns)
    s = h.summary

    assert h.has_hr and a.pump is None
    assert all(e.approximate for e in h.takeoff_events)
    assert s.approximate_takeoffs == s.takeoff_cost_coverage.valid
    assert s.takeoff_cost_coverage.pct > 50.0         # the HR gap rule keeps the channel
    assert s.bpm_per_stroke is None                   # no strokes to divide by
    assert s.pump_cruise.pumping_bpm is None
    assert s.pump_cruise.cruising_bpm is not None
