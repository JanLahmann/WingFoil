"""Pump-stroke detection from the wrist accelerometer (docs/algorithms.md "Pumping").

A wing pump is a whole-body, roughly 1 Hz oscillation the wrist sees as a large swing in
|a|. Everything else the wrist does while foiling -- chop, arm drift, wing trim -- is either
slower or much smaller, so a narrow band-pass around the pumping cadence plus an amplitude
gate separates the two cleanly. This is the phone-side twin of the watch `PumpDetector`
(docs/plan.md 3.2) and deliberately uses the same shape so the two can be cross-checked:

1. magnitude ``|a|`` of the raw stream (orientation-free -- the wrist rotates constantly),
2. box-averaged onto a uniform ``pumpResampleHz`` grid (anti-alias + gap bookkeeping; the
   band of interest ends at 2.5 Hz so 25 Hz is ample and matches the watch),
3. FIR band-pass ``pumpBandLo``..``pumpBandHi`` (Hamming-windowed sinc difference),
4. peak-pick with an amplitude gate ``pumpStrokeAmp`` and a ``pumpRefractory`` dead time,
5. strokes closer together than ``pumpStrokeMaxInterval`` form a *burst*; a burst of
   ``pumpMinStrokes`` or more is pumping.

Consumers ask questions about time windows (`is_pumping`), never about the raw signal.
Sources without an accel stream get `None` from `pump_track` and every consumer degrades to
its speed-only path -- native and GPX sessions must keep working unchanged.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .parse import RawTrack


@dataclass
class PumpConfig:
    """docs/algorithms.md "Pumping (accelerometer)" defaults."""

    band_lo_hz: float = 0.5              # pumpBandLo
    band_hi_hz: float = 2.5              # pumpBandHi
    resample_hz: float = 25.0            # pumpResampleHz
    filter_span_s: float = 2.0           # pumpFilterSpan: FIR length (two full slow cycles)
    stroke_amp_g: float = 0.25           # pumpStrokeAmp
    refractory_s: float = 0.4            # pumpRefractory
    stroke_max_interval_s: float = 1.5   # pumpStrokeMaxInterval: still the same burst
    min_strokes: int = 4                 # pumpMinStrokes: burst length that means "pumping"


@dataclass
class PumpTrack:
    """Band-passed accel magnitude on a uniform grid, plus the stroke queries built on it."""

    t: np.ndarray                        # uniform grid, seconds on the records' time base
    band: np.ndarray                     # band-passed |a| in g (0 where there is no data)
    valid: np.ndarray                    # bool: the bin held at least one raw sample
    config: PumpConfig

    def strokes(self, start_t: float, end_t: float) -> np.ndarray:
        """Times of the pump strokes detected in [start_t, end_t]."""
        lo = int(np.searchsorted(self.t, start_t, "left"))
        hi = int(np.searchsorted(self.t, end_t, "right"))
        return _pick_peaks(self.t[lo:hi], self.band[lo:hi], self.valid[lo:hi],
                           self.config.stroke_amp_g, self.config.refractory_s)

    def longest_burst(self, start_t: float, end_t: float) -> int:
        """Most strokes in a row with no gap longer than `pumpStrokeMaxInterval`."""
        return _longest_burst(self.strokes(start_t, end_t),
                              self.config.stroke_max_interval_s)

    def is_pumping(self, start_t: float, end_t: float) -> bool:
        """True when [start_t, end_t] holds a burst of at least `pumpMinStrokes`."""
        return self.longest_burst(start_t, end_t) >= self.config.min_strokes


def pump_track(track: RawTrack, config: PumpConfig | None = None) -> PumpTrack | None:
    """Build a PumpTrack from a parsed source, or None when it carries no accel stream."""
    accel = track.accel
    if accel is None or accel.empty:
        return None
    return pump_track_from_arrays(accel["t"].to_numpy(float),
                                  np.hypot(np.hypot(accel["ax"].to_numpy(float),
                                                    accel["ay"].to_numpy(float)),
                                           accel["az"].to_numpy(float)),
                                  config)


def pump_track_from_arrays(t: np.ndarray, mag: np.ndarray,
                           config: PumpConfig | None = None) -> PumpTrack | None:
    """PumpTrack from raw (time, |a| in g) samples -- unit tests and Monkey C array replay."""
    cfg = config or PumpConfig()
    t = np.asarray(t, float)
    mag = np.asarray(mag, float)
    if t.size < 2:
        return None

    step = 1.0 / cfg.resample_hz
    n_bins = int(np.floor((t[-1] - t[0]) / step)) + 1
    idx = np.clip(((t - t[0]) / step).astype(int), 0, n_bins - 1)
    count = np.bincount(idx, minlength=n_bins)
    total = np.bincount(idx, weights=mag, minlength=n_bins)
    valid = count > 0
    if valid.sum() < 3:
        return None

    grid = t[0] + np.arange(n_bins) * step
    level = float(total[valid].sum() / count[valid].sum())
    # Empty bins (sensor gaps) are held at the mean so the FIR does not ring on them; the
    # filtered value there is discarded via `valid` anyway.
    binned = np.where(valid, total / np.maximum(count, 1), level)
    band = np.convolve(binned - level, _bandpass_taps(cfg), mode="same")
    band[~valid] = 0.0
    return PumpTrack(t=grid, band=band, valid=valid, config=cfg)


def _bandpass_taps(cfg: PumpConfig) -> np.ndarray:
    """Hamming-windowed sinc band-pass (difference of two low-passes), odd tap count."""
    n_taps = int(round(cfg.filter_span_s * cfg.resample_hz)) | 1
    k = np.arange(n_taps) - (n_taps - 1) / 2.0

    def low_pass(fc: float) -> np.ndarray:
        return 2.0 * fc / cfg.resample_hz * np.sinc(2.0 * fc / cfg.resample_hz * k)

    return (low_pass(cfg.band_hi_hz) - low_pass(cfg.band_lo_hz)) * np.hamming(n_taps)


def _pick_peaks(t: np.ndarray, band: np.ndarray, valid: np.ndarray,
                amp: float, refractory_s: float) -> np.ndarray:
    """Local maxima above `amp`, at least `refractory_s` apart (first-wins)."""
    if t.size < 3:
        return np.empty(0)
    hit = (band[1:-1] > amp) & (band[1:-1] > band[:-2]) & (band[1:-1] >= band[2:])
    hit &= valid[1:-1]
    out: list[float] = []
    last = -np.inf
    for i in np.flatnonzero(hit) + 1:
        if t[i] - last >= refractory_s:
            out.append(float(t[i]))
            last = t[i]
    return np.asarray(out, float)


def _longest_burst(strokes: np.ndarray, max_interval_s: float) -> int:
    if strokes.size == 0:
        return 0
    best = run = 1
    for gap in np.diff(strokes):
        run = run + 1 if gap <= max_interval_s else 1
        best = max(best, run)
    return int(best)
