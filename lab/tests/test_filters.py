"""filters.clean unit tests: projection, NaN/gap handling, spike rejection, pos speed."""

import numpy as np
import pandas as pd
import pytest

from wingfoil_lab.filters import FilterConfig, clean, clean_from_arrays
from wingfoil_lab.parse import RawTrack, SourceCapabilities


def _raw(t, v, lat=None, lon=None):
    n = len(t)
    df = pd.DataFrame({
        "t": np.asarray(t, float),
        "speed_mps": np.asarray(v, float),
        "lat": np.full(n, 45.0) if lat is None else np.asarray(lat, float),
        "lon": np.full(n, 10.0) if lon is None else np.asarray(lon, float),
    })
    caps = SourceCapabilities(has_speed=True, has_position=True, sample_rate_hz=1.0)
    return RawTrack(path="<test>", records=df, capabilities=caps)


def test_projection_scale():
    # 1e-3 deg steps: y ~ 110.54 m, x ~ 111320 * cos(45 deg) * 1e-3 ~ 78.72 m
    t = [0.0, 1.0, 2.0]
    ct = clean(_raw(t, [1, 1, 1], lat=[45.0, 45.001, 45.001], lon=[10.0, 10.0, 10.001]))
    df = ct.records
    assert df["y"].iloc[1] - df["y"].iloc[0] == pytest.approx(110.54, abs=0.01)
    assert df["x"].iloc[2] - df["x"].iloc[1] == pytest.approx(
        111320 * np.cos(np.radians(45.0)) * 1e-3, rel=1e-3)


def test_nan_rows_dropped_into_gap():
    t = np.arange(0.0, 30.0)
    v = np.full(30, 5.0)
    v[10:16] = np.nan                       # 6 samples dropped -> dt 7 > 3 -> gap
    ct = clean(_raw(t, v))
    assert ct.dropped_nan == 6
    assert ct.records["segment"].nunique() == 2
    # segment 0 spans t 0..9 (9 s of intervals), segment 1 spans t 16..29 (13 s)
    assert ct.timer_time_s == pytest.approx(22.0)


def test_gap_threshold_dt_aware():
    # 0.5 Hz: median dt 2 -> threshold max(3, 4) = 4; dt 4 is NOT a gap, dt 5 is
    t = [0, 2, 4, 6, 8, 12, 17]
    ct = clean(_raw(t, [1] * 7))
    assert ct.gap_threshold_s == pytest.approx(4.0)
    assert list(ct.records["gap_before"]) == [False] * 6 + [True]
    # 1 Hz: threshold max(3, 2) = 3
    ct2 = clean(_raw([0, 1, 2, 3, 7], [1] * 5))
    assert ct2.gap_threshold_s == pytest.approx(3.0)
    assert list(ct2.records["gap_before"]) == [False, False, False, False, True]


def test_spike_rejected_dt_scaled():
    t = np.arange(0.0, 20.0)
    v = np.full(20, 5.0)
    v[7] = 60.0                              # |dv/dt| = 55 m/s^2 >> 4
    ct = clean(_raw(t, v))
    assert ct.dropped_spike == 1
    assert ct.records["doppler_mps"].max() == pytest.approx(5.0)
    # a 3.5 m/s step over 1 s is legal (3.5 < 4); over 2 s even 7 m/s would be
    v2 = np.full(20, 1.0)
    v2[10:] = 4.5
    ct2 = clean(_raw(t, v2))
    assert ct2.dropped_spike == 0


def test_positional_speed_matches_doppler_on_consistent_track():
    t = np.arange(0.0, 60.0, 2.0)            # 0.5 Hz
    v = np.full_like(t, 5.0)
    ct = clean_from_arrays(t, v)             # x integrated from doppler
    df = ct.records
    assert np.allclose(df["pos_mps"], 5.0, atol=1e-9)
    assert np.allclose(df["doppler_mps"], df["pos_mps"])


def test_from_arrays_does_not_spike_filter():
    # step of 6 m/s in 1 s would trip the spike filter; from_arrays keeps arrays verbatim
    t = np.arange(0.0, 10.0)
    v = np.where(t < 5, 2.0, 8.0)
    ct = clean_from_arrays(t, v)
    assert len(ct.records) == 10
    assert ct.records["doppler_mps"].max() == pytest.approx(8.0)
