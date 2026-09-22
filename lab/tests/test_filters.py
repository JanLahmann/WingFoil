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
    """The three terms of the rule (docs/algorithms/hygiene.md "speed sample hygiene")."""
    # Smart Recording: median dt 2 -> the 10 s floor applies, so a 5 s and an 8 s step are
    # cadence, not holes, and only the 17 s one cuts.
    t = [0, 2, 4, 6, 8, 13, 21, 38]
    ct = clean(_raw(t, [1] * 8))
    assert ct.gap_threshold_s == pytest.approx(10.0)
    assert list(ct.records["gap_before"]) == [False] * 7 + [True]
    # 1 Hz: median 1 is below smartMedianDtS, so the threshold is max(3, 2) = 3, untouched.
    ct2 = clean(_raw([0, 1, 2, 3, 7], [1] * 5))
    assert ct2.gap_threshold_s == pytest.approx(3.0)
    assert list(ct2.records["gap_before"]) == [False, False, False, False, True]


def test_the_smart_recording_floor_only_lifts_the_threshold():
    """`smartGapS` is a floor under `max(gapMinS, gapFactor x median)`, never a cap."""
    # A 20 s cadence: 2 x 20 = 40 already exceeds the floor, so the dt rule keeps winning.
    slow = clean(_raw([0, 20, 40, 60, 80, 141], [1] * 6))
    assert slow.gap_threshold_s == pytest.approx(40.0)
    assert list(slow.records["gap_before"]) == [False] * 5 + [True]
    # Switched off (smartGapS = 0), a median-2 track is cut at 4 s exactly as before 0.23.0.
    old = clean(_raw([0, 2, 4, 6, 8, 13], [1] * 6), FilterConfig(smart_gap_s=0.0))
    assert old.gap_threshold_s == pytest.approx(4.0)
    assert list(old.records["gap_before"]) == [False] * 5 + [True]


def test_the_spike_budget_stops_growing_at_three_seconds():
    """A reacquisition burst across a long Smart Recording step is still a spike.

    `maxAccel1Hz` is a 1 Hz value, so `|dv| <= 4 x dt` would let a 7 s step carry 28 m/s —
    which is exactly what a receiver emits when it finds the sky again. Capping the budget
    at `spikeMaxDtS` keeps the rule meaning what it says. At 1 Hz no step inside a segment
    reaches three seconds, so nothing there moves.
    """
    t = [0.0, 2.0, 4.0, 6.0, 8.0, 15.0, 17.0, 19.0, 21.0, 23.0, 25.0]
    v = [1.0, 1.0, 1.0, 1.0, 1.0, 17.0, 1.0, 1.0, 1.0, 1.0, 1.0]
    ct = clean(_raw(t, v))
    assert ct.gap_threshold_s == pytest.approx(10.0)         # the 7 s step is not a gap
    assert ct.records["doppler_mps"].max() == pytest.approx(1.0)
    # Uncapped, the same 16 m/s over 7 s reads as 2.3 m/s^2 and sails through.
    loose = clean(_raw(t, v), FilterConfig(spike_max_dt_s=1e9))
    assert loose.records["doppler_mps"].max() == pytest.approx(17.0)


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
