"""Track hygiene: gate/NaN/spike dropping, dt-aware gap segmentation, local-meter
projection, positional speed.

Contract: docs/algorithms.md "speed sample hygiene". The gap rule is dt-aware for
Garmin Smart Recording: gap iff dt > max(gap_min_s, gap_factor x median dt); gaps are
hard segment breaks, never interpolated (dt-weighted windows subsume the 1 Hz
`gapInterpolateMax` linear-interpolation rule).
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Iterator

import numpy as np
import pandas as pd

from .parse import RawTrack, SourceCapabilities

M_PER_DEG_LON_EQ = 111320.0  # x = (lon-lon0) * cos(lat0) * this
M_PER_DEG_LAT = 110540.0     # y = (lat-lat0) * this
MIN_COG_DISPLACEMENT_M = 0.5  # below this a step carries no usable bearing

_COLUMNS = ["t", "x", "y", "lat", "lon", "alt_m", "doppler_mps", "pos_mps", "dt",
            "gap_before", "segment"]


@dataclass
class FilterConfig:
    """docs/algorithms.md 'speed sample hygiene' defaults (dt-aware gap rule)."""

    max_hdop: float = 5.0            # gate applied only when an hdop channel exists
    min_satellites: int = 5          # gate applied only when a satellites channel exists
    max_accel_1hz: float = 4.0       # m/s^2: reject Doppler samples with |dv/dt| above this
    gap_min_s: float = 3.0           # gap iff dt > max(gap_min_s, gap_factor * median dt)
    gap_factor: float = 2.0


@dataclass
class CleanTrack:
    path: str
    records: pd.DataFrame            # columns: _COLUMNS
    capabilities: SourceCapabilities
    config: FilterConfig
    median_dt_s: float = 0.0
    gap_threshold_s: float = 0.0
    timer_time_s: float = 0.0        # total non-gap time (denominator for foil_pct)
    dropped_gate: int = 0
    dropped_nan: int = 0
    dropped_spike: int = 0

    def segments(self) -> Iterator[pd.DataFrame]:
        """Yield contiguous (gap-free) runs in time order."""
        for _, seg in self.records.groupby("segment", sort=True):
            yield seg


def clean(track: RawTrack, config: FilterConfig | None = None) -> CleanTrack:
    """RawTrack -> CleanTrack: drop unusable rows into gap regions, project, derive speeds."""
    cfg = config or FilterConfig()
    df = track.records.copy()

    if df.empty or "t" not in df.columns or "speed_mps" not in df.columns:
        return CleanTrack(track.path, _empty_frame(), track.capabilities, cfg)

    # Quality gates -- only when the channel exists (native Garmin FITs have neither).
    dropped_gate = 0
    for col, bad in (("hdop", lambda s: s > cfg.max_hdop),
                     ("satellites", lambda s: s < cfg.min_satellites),
                     ("n_satellites", lambda s: s < cfg.min_satellites)):
        if col in df.columns:
            mask = bad(df[col].astype(float)).fillna(False)
            dropped_gate += int(mask.sum())
            df = df[~mask]

    # NaN drop: rows without time/speed/position go into gap regions.
    has_pos = "lat" in df.columns and "lon" in df.columns
    need = ["t", "speed_mps"] + (["lat", "lon"] if has_pos else [])
    n_before = len(df)
    df = df.dropna(subset=need).sort_values("t")
    df = df[~df["t"].duplicated(keep="first")]
    dropped_nan = n_before - len(df)

    if df.empty:
        return CleanTrack(track.path, _empty_frame(), track.capabilities, cfg,
                          dropped_gate=dropped_gate, dropped_nan=dropped_nan)

    t = df["t"].to_numpy(float)
    v = df["speed_mps"].to_numpy(float)
    dts = np.diff(t)
    med = float(np.median(dts)) if dts.size else 0.0
    thr = max(cfg.gap_min_s, cfg.gap_factor * med) if med > 0 else cfg.gap_min_s

    # Doppler acceleration spike rejection, dt-scaled: |dv/dt| > max_accel_1hz -> drop row.
    keep = _spike_keep(t, v, cfg.max_accel_1hz, thr)
    dropped_spike = int((~keep).sum())
    df = df[keep]

    out = pd.DataFrame({"t": df["t"].to_numpy(float),
                        "doppler_mps": df["speed_mps"].to_numpy(float)})
    # Barometric altitude is carried through unfiltered: on the water its *absolute* value
    # is meaningless, but a dunked wrist reads hundreds of metres low (`turnBaroDrop`, step 2
    # of docs/algorithms.md "Turn outcome"), and that transient must survive to the turns.
    alt = next((df[c] for c in ("enhanced_altitude", "altitude") if c in df.columns), None)
    out["alt_m"] = np.nan if alt is None else alt.to_numpy(float)
    if has_pos:
        lat = df["lat"].to_numpy(float)
        lon = df["lon"].to_numpy(float)
        lat0, lon0 = float(np.mean(lat)), float(np.mean(lon))
        out["lat"], out["lon"] = lat, lon
        out["x"] = (lon - lon0) * math.cos(math.radians(lat0)) * M_PER_DEG_LON_EQ
        out["y"] = (lat - lat0) * M_PER_DEG_LAT
    else:
        out["lat"] = out["lon"] = out["x"] = out["y"] = np.nan

    out, timer = _assemble(out, thr)
    return CleanTrack(track.path, out[_COLUMNS], track.capabilities, cfg,
                      median_dt_s=med, gap_threshold_s=thr, timer_time_s=timer,
                      dropped_gate=dropped_gate, dropped_nan=dropped_nan,
                      dropped_spike=dropped_spike)


def clean_from_arrays(t, doppler_mps, x=None, y=None, alt_m=None,
                      config: FilterConfig | None = None,
                      path: str = "<arrays>") -> CleanTrack:
    """Build a CleanTrack straight from arrays (unit tests, Monkey C array extraction).

    The arrays are taken as ground truth: no gate/NaN/spike dropping is applied, only
    gap segmentation and derived channels. If x/y are omitted the track is laid out
    along +x by integrating the Doppler speed (pos_mps then matches doppler_mps).
    """
    cfg = config or FilterConfig()
    t = np.asarray(t, float)
    v = np.asarray(doppler_mps, float)
    if x is None:
        x = np.concatenate([[0.0], np.cumsum((v[1:] + v[:-1]) / 2.0 * np.diff(t))])
    else:
        x = np.asarray(x, float)
    y = np.zeros_like(t) if y is None else np.asarray(y, float)

    dts = np.diff(t)
    med = float(np.median(dts)) if dts.size else 0.0
    thr = max(cfg.gap_min_s, cfg.gap_factor * med) if med > 0 else cfg.gap_min_s

    out = pd.DataFrame({"t": t, "doppler_mps": v, "x": x, "y": y,
                        "lat": np.nan, "lon": np.nan,
                        "alt_m": np.nan if alt_m is None else np.asarray(alt_m, float)})
    out, timer = _assemble(out, thr)
    caps = SourceCapabilities(has_speed=True, has_position=True,
                              sample_rate_hz=round(1.0 / med, 3) if med > 0 else 0.0)
    return CleanTrack(path, out[_COLUMNS], caps, cfg,
                      median_dt_s=med, gap_threshold_s=thr, timer_time_s=timer)


def unwrapped_cog_deg(x: np.ndarray, y: np.ndarray,
                      min_disp_m: float = MIN_COG_DISPLACEMENT_M) -> np.ndarray:
    """Per-interval course over ground (deg, unwrapped), length ``len(x) - 1``.

    Element ``i`` is the bearing of the step leaving sample ``i`` (0 deg = +y = north,
    clockwise). Steps shorter than ``min_disp_m`` carry only position noise and inherit
    the last usable bearing. Unwrapped so that turn rates are plain differences; only
    call it per gap-free segment (a gap would unwrap across missing motion).
    """
    dx, dy = np.diff(x), np.diff(y)
    disp = np.hypot(dx, dy)
    bear = np.degrees(np.arctan2(dx, dy))
    bear = np.where(disp >= min_disp_m, bear, np.nan)
    bear = pd.Series(bear).ffill().bfill().fillna(0.0).to_numpy()
    return np.degrees(np.unwrap(np.radians(bear)))


def hybrid_speed(records: pd.DataFrame) -> np.ndarray:
    """Maneuver speed channel (docs/algorithms.md ``speedChannelManeuvers``).

    Positional speed where available, Doppler where not: device Doppler is smoothed over
    ~3-4 s and understates turn minima, so turn entry/minimum speeds are read here while
    speed records stay on the Doppler channel.
    """
    pos = records["pos_mps"].to_numpy(float)
    dop = records["doppler_mps"].to_numpy(float)
    return np.where(np.isfinite(pos), pos, dop)


def _empty_frame() -> pd.DataFrame:
    return pd.DataFrame({c: pd.Series(dtype=float) for c in _COLUMNS}).astype({"segment": int})


def _spike_keep(t: np.ndarray, v: np.ndarray, max_accel: float, gap_thr: float) -> np.ndarray:
    """Forward pass vs last good sample; resets across gaps (self-recovering on spike runs)."""
    n = len(t)
    keep = np.ones(n, dtype=bool)
    if n == 0:
        return keep
    tg, vg = t[0], v[0]
    for i in range(1, n):
        d = t[i] - tg
        if d > gap_thr:                       # new segment: accept unconditionally
            tg, vg = t[i], v[i]
            continue
        if d <= 0 or abs(v[i] - vg) / d > max_accel:
            keep[i] = False
        else:
            tg, vg = t[i], v[i]
    return keep


def _assemble(df: pd.DataFrame, gap_thr: float) -> tuple[pd.DataFrame, float]:
    """Add dt / gap_before / segment / pos_mps; return (df, timer_time_s)."""
    t = df["t"].to_numpy(float)
    n = len(t)
    dt = np.concatenate([[np.nan], np.diff(t)]) if n else np.array([])
    gap = np.zeros(n, dtype=bool)
    if n > 1:
        gap[1:] = dt[1:] > gap_thr
    df["dt"] = dt
    df["gap_before"] = gap
    df["segment"] = np.cumsum(gap).astype(int)

    pos = np.full(n, np.nan)
    x = df["x"].to_numpy(float)
    y = df["y"].to_numpy(float)
    starts = np.flatnonzero(gap).tolist()
    bounds = list(zip([0] + starts, starts + [n]))
    for s0, s1 in bounds:
        pos[s0:s1] = _positional_speed(t[s0:s1], x[s0:s1], y[s0:s1])
    df["pos_mps"] = pos

    timer = float(np.nansum(dt[1:][~gap[1:]])) if n > 1 else 0.0
    return df, timer


def _positional_speed(t: np.ndarray, x: np.ndarray, y: np.ndarray) -> np.ndarray:
    """Central difference (dt-aware) within a segment; one-sided at the edges."""
    n = len(t)
    out = np.full(n, np.nan)
    if n < 2 or np.isnan(x).all():
        return out
    out[0] = math.hypot(x[1] - x[0], y[1] - y[0]) / (t[1] - t[0])
    out[-1] = math.hypot(x[-1] - x[-2], y[-1] - y[-2]) / (t[-1] - t[-2])
    if n >= 3:
        span = t[2:] - t[:-2]
        out[1:-1] = np.hypot(x[2:] - x[:-2], y[2:] - y[:-2]) / span
    return out
