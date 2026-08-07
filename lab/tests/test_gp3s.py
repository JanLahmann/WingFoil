"""GP3S record unit tests on constructed tracks with hand-computable answers."""

import numpy as np
import pytest

from wingfoil_lab.filters import clean_from_arrays
from wingfoil_lab.gp3s import MPS_TO_KN, records

KN = MPS_TO_KN


def _burst(t_end, hz, base, burst, t0, t1):
    """base m/s with `burst` m/s on samples t in [t0, t1] (inclusive)."""
    t = np.arange(0.0, t_end + 1e-9, 1.0 / hz)
    v = np.where((t >= t0) & (t <= t1), burst, base)
    return clean_from_arrays(t, v)


@pytest.mark.parametrize("hz", [1.0, 0.5])
def test_best2s_and_10s_peaks(hz):
    # 8 m/s held on samples [30, 40] -> a pure 10 s window (and pure 2 s windows inside)
    r = records(_burst(120, hz, 2.0, 8.0, 30, 40))
    assert r.best2s_kn == pytest.approx(8 * KN, abs=1e-6)
    assert r.best10s_kn == pytest.approx(8 * KN, abs=1e-6)
    w2, w10 = r.windows["best2s"], r.windows["best10s"]
    assert 30.0 - 1e-9 <= w2.start_t and w2.start_t + 2 <= 40.0 + 1e-9
    assert w10.start_t == pytest.approx(30.0)
    assert w10.duration_s == 10.0


def test_2s_peak_shorter_burst_uses_interpolated_edges():
    # burst 8 m/s on samples [30, 31] at 1 Hz: best 2 s window straddles the edges;
    # trapezoid cumdist -> best 2 s = window [29.5, 31.5]... maximum is [30, 32]:
    # C(32)-C(30) = 8 + (8+2)/2 = 13 -> 6.5 m/s? window [29,31] symmetric = same.
    # True max over any 2 s window of piecewise-linear C: start 30 -> 6.5 m/s.
    r = records(_burst(60, 1.0, 2.0, 8.0, 30, 31))
    assert r.best2s_kn == pytest.approx(6.5 * KN, abs=1e-6)


def test_500m_and_100m_constant_speed():
    t = np.arange(0.0, 101.0)
    v = np.full_like(t, 10.0)               # 1000 m total
    r = records(clean_from_arrays(t, v))
    assert r.best100m_kn == pytest.approx(10 * KN, abs=1e-6)
    assert r.best250m_kn == pytest.approx(10 * KN, abs=1e-6)
    assert r.best500m_kn == pytest.approx(10 * KN, abs=1e-6)
    assert r.windows["best500m"].duration_s == pytest.approx(50.0)
    assert r.best_nm_kn == 0.0              # 1000 m < 1852 m
    assert "bestNm" not in r.windows
    assert r.best_hour_kn == 0.0            # session << 1 h
    assert r.distance_m == pytest.approx(1000.0)


def test_500m_min_time_window_found_off_samples():
    # 5 m/s for 80 s then 10 m/s for 60 s (samples aligned): the best 500 m lies
    # entirely in the fast part: 400+... fast part covers 600 m -> elapsed 50 s.
    t = np.arange(0.0, 141.0)
    v = np.where(t < 80, 5.0, 10.0)
    r = records(clean_from_arrays(t, v))
    assert r.best500m_kn == pytest.approx(10 * KN, rel=1e-3)


def test_5x10s_disjoint_windows_and_mean():
    # five pure 10 s windows at 10 m/s, one better at 12 m/s; baseline 2 m/s
    t = np.arange(0.0, 121.0)
    v = np.full_like(t, 2.0)
    for a in (10, 30, 50, 70, 90):
        v[(t >= a) & (t <= a + 10)] = 10.0
    v[(t >= 110) & (t <= 120)] = 12.0
    r = records(clean_from_arrays(t, v))
    assert r.best10s_kn == pytest.approx(12 * KN, abs=1e-6)
    assert r.best5x10s_kn == pytest.approx((12 + 4 * 10) / 5 * KN, abs=1e-6)
    wins = r.windows["best5x10s"]
    assert len(wins) == 5
    ivs = sorted((w.start_t, w.start_t + w.duration_s) for w in wins)
    for (a0, b0), (a1, b1) in zip(ivs, ivs[1:]):
        assert b0 <= a1 + 1e-9              # pairwise disjoint (touching allowed)


def test_alpha500_out_and_back():
    # straight out 30 s at 8 m/s, straight back 30 s: path 480 <= 500, endpoints meet,
    # COG spread 180 deg, path >= 250 -> alpha = 8 m/s
    t = np.arange(0.0, 61.0)
    v = np.full_like(t, 8.0)
    x = np.where(t <= 30, 8.0 * t, 240.0 - 8.0 * (t - 30))
    y = np.zeros_like(t)
    r = records(clean_from_arrays(t, v, x=x, y=y))
    assert r.alpha500_kn == pytest.approx(8 * KN, abs=0.1)
    assert "alpha500" in r.windows


def test_alpha500_straight_line_is_pruned():
    t = np.arange(0.0, 61.0)
    v = np.full_like(t, 8.0)
    x = 8.0 * t
    y = np.zeros_like(t)
    r = records(clean_from_arrays(t, v, x=x, y=y))
    assert r.alpha500_kn == 0.0
    assert "alpha500" not in r.windows


def test_windows_never_span_gaps():
    # two 10 s fast runs separated by a 60 s hole: no 250 m record, per-segment 10 s peaks
    t = np.concatenate([np.arange(0.0, 11.0), np.arange(70.0, 81.0)])
    v = np.full_like(t, 10.0)
    ct = clean_from_arrays(t, v)
    assert ct.records["segment"].nunique() == 2
    r = records(ct)
    assert r.best10s_kn == pytest.approx(10 * KN, abs=1e-6)
    assert r.distance_m == pytest.approx(200.0)
    assert r.best250m_kn == 0.0             # neither segment covers 250 m
    assert r.best_hour_kn == 0.0


def test_invariants_on_random_track():
    rng = np.random.default_rng(7)
    t = np.arange(0.0, 600.0)
    v = np.clip(np.abs(rng.normal(4.0, 2.5, t.size)), 0.0, 12.0)
    r = records(clean_from_arrays(t, v))
    assert r.best2s_kn >= r.best10s_kn - 1e-9
    assert r.best10s_kn >= r.best5x10s_kn - 1e-9
    assert r.best100m_kn >= r.best250m_kn - 1e-9 >= 0.0
    assert r.best250m_kn >= r.best500m_kn - 1e-9
    for val in (r.best2s_kn, r.best10s_kn, r.best5x10s_kn, r.best100m_kn,
                r.best250m_kn, r.best500m_kn, r.best_nm_kn, r.best_hour_kn,
                r.alpha500_kn):
        assert 0.0 <= val < 45.0
