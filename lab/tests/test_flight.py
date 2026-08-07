"""Flight hysteresis unit tests on constructed speed arrays (hand-computable).

The same time profile sampled at 1 Hz and at 0.5 Hz must yield the same flights:
holds are time-accumulated, entries/exits are backdated to sample times.
"""

import numpy as np
import pytest

from wingfoil_lab.filters import clean_from_arrays
from wingfoil_lab.flight import FlightConfig, segment_flights

KMH = 1.0 / 3.6


def _sample(profile_kmh, t_end, hz):
    t = np.arange(0.0, t_end + 1e-9, 1.0 / hz)
    v = np.array([profile_kmh(x) for x in t]) * KMH
    return clean_from_arrays(t, v)


def _step_profile(t):
    """5 km/h taxi, 20 km/h flight on [20, 80), 5 km/h after."""
    return 20.0 if 20 <= t < 80 else 5.0


@pytest.mark.parametrize("hz", [1.0, 0.5])
def test_basic_flight_backdated(hz):
    fr = segment_flights(_sample(_step_profile, 120, hz))
    assert fr.flight_count == 1
    f = fr.flights[0]
    assert f.start_t == pytest.approx(20.0)   # backdated to first >= entry sample
    assert f.end_t == pytest.approx(80.0)     # backdated to first <= exit sample
    assert f.duration_s == pytest.approx(60.0)
    assert fr.foil_time_s == pytest.approx(60.0)
    assert fr.foil_pct == pytest.approx(50.0, abs=0.01)
    assert fr.longest is f


def test_same_profile_1hz_and_05hz_same_flights():
    a = segment_flights(_sample(_step_profile, 120, 1.0))
    b = segment_flights(_sample(_step_profile, 120, 0.5))
    assert a.flight_count == b.flight_count == 1
    for fa, fb in zip(a.flights, b.flights):
        assert fa.start_t == pytest.approx(fb.start_t)
        assert fa.end_t == pytest.approx(fb.end_t)
        assert fa.duration_s == pytest.approx(fb.duration_s)
    assert a.foil_time_s == pytest.approx(b.foil_time_s)


@pytest.mark.parametrize("hz", [1.0, 0.5])
def test_short_blip_discarded(hz):
    def blip(t):
        return 20.0 if 10 <= t < 14 else 5.0   # 4 s < minFlightDuration 5 s

    fr = segment_flights(_sample(blip, 40, hz))
    assert fr.flight_count == 0
    assert fr.foil_time_s == 0.0


@pytest.mark.parametrize("hz", [1.0, 0.5])
def test_hysteresis_band_keeps_flight(hz):
    def dip(t):
        if 20 <= t < 80:
            return 10.0 if 40 <= t < 50 else 20.0   # dip to 10 km/h: < entry but > exit
        return 5.0

    fr = segment_flights(_sample(dip, 120, hz))
    assert fr.flight_count == 1
    assert fr.flights[0].start_t == pytest.approx(20.0)
    assert fr.flights[0].end_t == pytest.approx(80.0)


def test_entry_hold_not_reached_no_flight():
    # alternating 13 / 10 km/h at 1 Hz: never two consecutive >= entry samples
    t = np.arange(0.0, 60.0)
    v = np.where(t.astype(int) % 2 == 0, 13.0, 10.0) * KMH
    fr = segment_flights(clean_from_arrays(t, v))
    assert fr.flight_count == 0


def test_gap_splits_flight_and_timer_time():
    # constant 20 km/h, but samples 100..109 missing -> 11 s gap -> two flights
    t = np.concatenate([np.arange(0.0, 100.0), np.arange(110.0, 200.0)])
    v = np.full_like(t, 20.0 * KMH)
    ct = clean_from_arrays(t, v)
    assert ct.records["segment"].nunique() == 2
    fr = segment_flights(ct)
    assert fr.flight_count == 2
    (f1, f2) = fr.flights
    assert (f1.start_t, f1.end_t) == (0.0, 99.0)
    assert (f2.start_t, f2.end_t) == (110.0, 199.0)
    assert ct.timer_time_s == pytest.approx(188.0)
    assert fr.foil_pct == pytest.approx(100.0)


def test_exit_hold_requires_sustained_slow():
    # 2 s sub-exit dip must NOT end the flight (exitHold = 3 s)
    def dip(t):
        if 20 <= t < 80:
            return 5.0 if 40 <= t < 42 else 20.0
        return 5.0

    fr = segment_flights(_sample(dip, 120, 1.0))
    assert fr.flight_count == 1
    assert fr.flights[0].end_t == pytest.approx(80.0)


def test_dist_and_max():
    fr = segment_flights(_sample(_step_profile, 120, 1.0))
    f = fr.flights[0]
    # 59 intervals at 5.5556 m/s + final interval avg (20+5)/2 km/h
    assert f.dist_m == pytest.approx(59 * 20 * KMH + (20 + 5) / 2 * KMH, rel=1e-6)
    assert f.max_kn == pytest.approx(20 * KMH * 1.9438445, abs=1e-6)
