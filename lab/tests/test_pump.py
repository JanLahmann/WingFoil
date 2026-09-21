"""Pump-stroke detection on synthetic wrist traces and on the one fixture that has accel."""

from pathlib import Path

import numpy as np
import pytest

from wingfoil_lab.parse import parse_fit
from wingfoil_lab.pump import PumpConfig, pump_track, pump_track_from_arrays

FIXTURES = Path(__file__).resolve().parents[2] / "fixtures"
CIQ = FIXTURES / "sessions/ciq/2026-08-07-0754_nago-torbole-windsurfen_ciq.fit"
NATIVE = FIXTURES / "sessions/windsurf-native/2026-08-05-0827_nago-torbole-windsurfen_native.fit"

HZ = 100.0


def _wrist(duration=60.0, hz=HZ):
    t = np.arange(0.0, duration, 1.0 / hz)
    return t, np.ones_like(t)                     # a still wrist reads 1 g


def _add(t, mag, t0, t1, freq, amp):
    on = (t >= t0) & (t <= t1)
    mag = mag.copy()
    mag[on] += amp * np.sin(2 * np.pi * freq * t[on])
    return mag


def test_a_pumping_burst_is_found_at_the_right_cadence_and_time():
    t, mag = _wrist()
    mag = _add(t, mag, 20.0, 30.0, freq=1.2, amp=0.6)
    track = pump_track_from_arrays(t, mag)

    strokes = track.strokes(0.0, 60.0)
    assert len(strokes) == pytest.approx(12, abs=3)      # 10 s at 1.2 Hz
    assert 19.0 <= strokes.min() and strokes.max() <= 31.0
    assert np.median(np.diff(strokes)) == pytest.approx(1 / 1.2, abs=0.1)
    assert track.is_pumping(20.0, 30.0)
    assert not track.is_pumping(0.0, 15.0)              # nothing outside the burst


def test_a_still_wrist_is_never_pumping():
    t, mag = _wrist()
    assert not pump_track_from_arrays(t, mag).is_pumping(0.0, 60.0)


def test_chop_is_rejected_by_the_band_and_the_amplitude_gate():
    """Fast small ripple (chop, 6 Hz) and a slow big lean (0.1 Hz) both fall outside."""
    t, mag = _wrist()
    mag = _add(t, mag, 0.0, 60.0, freq=6.0, amp=0.5)
    mag = _add(t, mag, 0.0, 60.0, freq=0.1, amp=1.0)
    assert not pump_track_from_arrays(t, mag).is_pumping(0.0, 60.0)


def test_small_wing_trim_wobble_is_below_the_stroke_amplitude():
    t, mag = _wrist()
    mag = _add(t, mag, 10.0, 50.0, freq=1.2, amp=0.06)   # in band, far too small
    assert not pump_track_from_arrays(t, mag).is_pumping(0.0, 60.0)


def test_a_burst_shorter_than_min_strokes_is_not_pumping():
    t, mag = _wrist()
    mag = _add(t, mag, 20.0, 21.6, freq=1.2, amp=0.6)    # two strokes
    track = pump_track_from_arrays(t, mag)
    assert 0 < track.longest_burst(0.0, 60.0) < PumpConfig().min_strokes
    assert not track.is_pumping(0.0, 60.0)


def test_thresholds_are_tunable():
    t, mag = _wrist()
    mag = _add(t, mag, 20.0, 30.0, freq=1.2, amp=0.12)
    assert not pump_track_from_arrays(t, mag).is_pumping(0.0, 60.0)
    lenient = PumpConfig(stroke_amp_g=0.05)
    assert pump_track_from_arrays(t, mag, lenient).is_pumping(0.0, 60.0)


def test_a_sensor_gap_carries_no_strokes():
    t, mag = _wrist()
    mag = _add(t, mag, 20.0, 30.0, freq=1.2, amp=0.6)
    keep = (t < 22.0) | (t > 28.0)                       # SensorLogging dropped out
    track = pump_track_from_arrays(t[keep], mag[keep])
    assert not track.valid[(track.t > 23.0) & (track.t < 27.0)].any()
    assert track.strokes(23.0, 27.0).size == 0


def test_too_little_data_yields_no_track():
    assert pump_track_from_arrays(np.array([0.0]), np.array([1.0])) is None


@pytest.mark.skipif(not CIQ.exists(), reason="ciq fixture missing")
def test_real_ciq_session_has_a_usable_accel_stream():
    track = parse_fit(CIQ)
    assert track.capabilities.has_accel
    accel = track.accel
    assert accel is not None and len(accel) > 100_000
    # Garmin writes milli-g; parse sniffs the scale, so |a| must sit around 1 g.
    mag = np.hypot(np.hypot(accel["ax"], accel["ay"]), accel["az"])
    assert 0.8 < float(np.median(mag)) < 1.5
    assert float(np.median(np.diff(accel["t"]))) == pytest.approx(0.01, abs=0.005)

    pumps = pump_track(track)
    assert pumps is not None
    assert 0.0 < pumps.band.std() < 1.0


@pytest.mark.skipif(not NATIVE.exists(), reason="native fixture missing")
def test_a_source_without_accel_degrades_to_none():
    track = parse_fit(NATIVE)
    assert not track.capabilities.has_accel
    assert track.accel is None
    assert pump_track(track) is None


def test_a_broken_clock_is_refused_rather_than_allocated_on():
    """The grid's length comes out of a file, so nothing here trusts it (engine 0.23.0).

    Three shapes, one answer: `None`, which is what a source with no accelerometer already
    gets, so every consumer degrades the way it always has. The NaN case is the one that
    used to raise -- `int(floor(nan))` is not a number of bins, and `goldens.analyze` died
    on a tester's file for it.
    """
    t, mag = _wrist(4.0)
    assert pump_track_from_arrays(np.full_like(t, np.nan), mag) is None   # all times NaN
    fifty_days = np.array([0.0, 50 * 86400.0])
    assert pump_track_from_arrays(fifty_days, np.ones(2)) is None         # past MAX_PUMP_BINS


def test_non_finite_samples_are_dropped_and_the_rest_still_reads():
    """One poisoned sample costs one sample, not the channel."""
    t, mag = _wrist(30.0)
    mag = mag + 0.5 * np.sin(2 * np.pi * 1.0 * t)      # a 1 Hz pump, well inside the band
    t = t.copy()
    t[100] = np.nan
    mag = mag.copy()
    mag[200] = np.inf
    track = pump_track_from_arrays(t, mag)
    assert track is not None
    assert bool(np.isfinite(track.band).all())
    assert track.longest_burst(0.0, 30.0) >= 4


def test_an_unsorted_stream_is_sorted_rather_than_mis_binned():
    t, mag = _wrist(20.0)
    mag = mag + 0.5 * np.sin(2 * np.pi * 1.0 * t)
    order = np.arange(t.size)
    order[5], order[9] = order[9], order[5]
    shuffled = pump_track_from_arrays(t[order], mag[order])
    straight = pump_track_from_arrays(t, mag)
    assert shuffled is not None and straight is not None
    assert np.allclose(shuffled.band, straight.band)
