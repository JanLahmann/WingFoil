"""GP3S speed-record set on the Doppler channel (docs/algorithms.md "Speed records").

Everything is time/distance-window based and dt-aware: windows are found by
interpolating cumulative distance vs time (trapezoid-integrated Doppler), never by
sample counts. Windows never span gaps (per-segment). No minimum-speed floor anywhere.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np

from .filters import CleanTrack, unwrapped_cog_deg

MPS_TO_KN = 1.9438445

ALPHA_PROXIMITY_M = 50.0        # endpoint-to-startpoint (Pythagoras on local meters)
ALPHA_MAX_DISTANCE_M = 500.0    # total path length cap
ALPHA_MIN_PATH_M = 250.0        # candidate prune: path >= this ...
ALPHA_MIN_COG_SPREAD_DEG = 90.0  # ... AND COG spread >= this
NM_M = 1852.0


@dataclass
class RecordWindow:
    start_t: float
    duration_s: float


@dataclass
class GP3SRecords:
    best2s_kn: float = 0.0
    best10s_kn: float = 0.0
    best5x10s_kn: float = 0.0
    best100m_kn: float = 0.0
    best250m_kn: float = 0.0
    best500m_kn: float = 0.0
    best_nm_kn: float = 0.0
    best_hour_kn: float = 0.0
    alpha500_kn: float = 0.0
    distance_m: float = 0.0
    # window provenance keyed like the golden schema ("best2s", ..., "alpha500");
    # "best5x10s" maps to the list of chosen disjoint windows.
    windows: dict[str, RecordWindow | list[RecordWindow]] = field(default_factory=dict)


def records(clean: CleanTrack) -> GP3SRecords:
    segs = _segment_arrays(clean)
    out = GP3SRecords()
    out.distance_m = float(sum(s["c"][-1] for s in segs))

    for name, dur in (("best2s", 2.0), ("best10s", 10.0), ("bestHour", 3600.0)):
        hit = _best_duration_window(segs, dur)
        if hit is not None:
            mps, start = hit
            _set_kn(out, name, mps)
            out.windows[name] = RecordWindow(start, dur)

    mean_mps, wins = _best_5x10(segs)
    if wins:
        out.best5x10s_kn = mean_mps * MPS_TO_KN
        out.windows["best5x10s"] = wins

    for name, dist in (("best100m", 100.0), ("best250m", 250.0),
                       ("best500m", 500.0), ("bestNm", NM_M)):
        hit = _best_distance_window(segs, dist)
        if hit is not None:
            mps, start, elapsed = hit
            _set_kn(out, name, mps)
            out.windows[name] = RecordWindow(start, elapsed)

    hit = _best_alpha(segs)
    if hit is not None:
        mps, start, elapsed = hit
        out.alpha500_kn = mps * MPS_TO_KN
        out.windows["alpha500"] = RecordWindow(start, elapsed)
    return out


_ATTR = {"best2s": "best2s_kn", "best10s": "best10s_kn", "bestHour": "best_hour_kn",
         "best100m": "best100m_kn", "best250m": "best250m_kn", "best500m": "best500m_kn",
         "bestNm": "best_nm_kn"}


def _set_kn(out: GP3SRecords, name: str, mps: float) -> None:
    setattr(out, _ATTR[name], mps * MPS_TO_KN)


def _segment_arrays(clean: CleanTrack) -> list[dict]:
    """Per gap-free segment: t, trapezoid cumulative distance c, x, y, unwrapped COG u."""
    segs = []
    for seg in clean.segments():
        t = seg["t"].to_numpy(float)
        if len(t) < 2:
            continue
        v = seg["doppler_mps"].to_numpy(float)
        c = np.concatenate([[0.0], np.cumsum((v[1:] + v[:-1]) / 2.0 * np.diff(t))])
        x = seg["x"].to_numpy(float)
        y = seg["y"].to_numpy(float)
        segs.append({"t": t, "c": c, "x": x, "y": y, "u": unwrapped_cog_deg(x, y)})
    return segs


def _best_duration_window(segs: list[dict], dur: float,
                          exclude: list[tuple[float, float]] = ()) -> tuple[float, float] | None:
    """Max average Doppler speed over any window of `dur` seconds -> (mps, start_t).

    Candidate starts: every sample time (forward search) and every sample time minus
    `dur` (backward search -- the classic 1 h bug guard), plus exclusion-zone edges.
    Cumulative distance is interpolated at the window edges.
    """
    best_v, best_s = -math.inf, None
    for s in segs:
        t, c = s["t"], s["c"]
        if t[-1] - t[0] + 1e-9 < dur:
            continue
        cand = [t, t - dur]
        for a, b in exclude:
            cand.append(np.array([b, a - dur]))
        cc = np.unique(np.concatenate(cand))
        cc = cc[(cc >= t[0] - 1e-9) & (cc <= t[-1] - dur + 1e-9)]
        for a, b in exclude:
            cc = cc[(cc + dur <= a + 1e-9) | (cc >= b - 1e-9)]
        if cc.size == 0:
            continue
        avg = (np.interp(cc + dur, t, c) - np.interp(cc, t, c)) / dur
        k = int(np.argmax(avg))
        if avg[k] > best_v:
            best_v, best_s = float(avg[k]), float(cc[k])
    return (best_v, best_s) if best_s is not None else None


def _best_5x10(segs: list[dict], dur: float = 10.0,
               count: int = 5) -> tuple[float, list[RecordWindow]]:
    """Greedy best `count` non-overlapping `dur`-second windows -> (mean mps, windows)."""
    chosen: list[tuple[float, float]] = []
    vals: list[float] = []
    wins: list[RecordWindow] = []
    for _ in range(count):
        hit = _best_duration_window(segs, dur, exclude=chosen)
        if hit is None:
            break
        mps, start = hit
        vals.append(mps)
        chosen.append((start, start + dur))
        wins.append(RecordWindow(start, dur))
    return (float(np.mean(vals)), wins) if vals else (0.0, [])


def _best_distance_window(segs: list[dict], dist: float) -> tuple[float, float, float] | None:
    """Min time over any contiguous window covering `dist` meters -> (mps, start_t, elapsed).

    Two passes per segment over cumulative distance with edge interpolation:
    forward from every sample and backward from every sample.
    """
    best_el, best_start = math.inf, None
    for s in segs:
        t, c = s["t"], s["c"]
        n = len(c)
        if c[-1] < dist:
            continue
        # forward: window starts at sample i, end edge interpolated
        tgt = c + dist
        j = np.searchsorted(c, tgt, side="left")
        ok = j < n
        if ok.any():
            jj = j[ok]
            denom = np.maximum(c[jj] - c[jj - 1], 1e-12)
            t2 = t[jj - 1] + (tgt[ok] - c[jj - 1]) / denom * (t[jj] - t[jj - 1])
            el = t2 - t[ok]
            k = int(np.argmin(el))
            if el[k] < best_el:
                best_el, best_start = float(el[k]), float(t[ok][k])
        # backward: window ends at sample j, start edge interpolated (latest possible t1)
        tgt2 = c - dist
        ok2 = tgt2 >= c[0] - 1e-12
        if ok2.any():
            ii = np.searchsorted(c, tgt2[ok2], side="right") - 1
            ii = np.clip(ii, 0, n - 1)
            nxt = np.minimum(ii + 1, n - 1)
            exact = c[ii] >= tgt2[ok2] - 1e-12
            denom = np.maximum(c[nxt] - c[ii], 1e-12)
            t1 = np.where(exact, t[ii],
                          t[ii] + (tgt2[ok2] - c[ii]) / denom * (t[nxt] - t[ii]))
            el = t[ok2] - t1
            k = int(np.argmin(el))
            if el[k] < best_el:
                best_el, best_start = float(el[k]), float(t1[k])
    if best_start is None or best_el <= 0:
        return None
    return dist / best_el, best_start, best_el


def _best_alpha(segs: list[dict],
                prox_m: float = ALPHA_PROXIMITY_M,
                max_path_m: float = ALPHA_MAX_DISTANCE_M,
                min_path_m: float = ALPHA_MIN_PATH_M,
                min_spread_deg: float = ALPHA_MIN_COG_SPREAD_DEG,
                ) -> tuple[float, float, float] | None:
    """Alpha 500: best path/time over a contiguous window with path <= 500 m and
    endpoints <= 50 m apart, pruned to path >= 250 m and COG spread >= 90 deg.

    Window ends at sample edges plus one interpolated end capping the path at exactly
    500 m; starts at sample edges. Returns (mps, start_t, elapsed) or None.
    """
    best_v, best_start, best_el = -math.inf, None, 0.0
    for s in segs:
        t, c, x, y, u = s["t"], s["c"], s["x"], s["y"], s["u"]
        n = len(t)
        if n < 3 or np.isnan(x).all():
            continue
        for i in range(n - 1):
            lim = c[i] + max_path_m
            jend = int(np.searchsorted(c, lim, side="right")) - 1  # last sample with path <= cap
            if jend <= i:
                continue
            path = c[i + 1:jend + 1] - c[i]
            dtv = t[i + 1:jend + 1] - t[i]
            prox = np.hypot(x[i + 1:jend + 1] - x[i], y[i + 1:jend + 1] - y[i])
            uu = u[i:jend]  # bearings of intervals i .. jend-1
            spread = np.maximum.accumulate(uu) - np.minimum.accumulate(uu)
            valid = (path >= min_path_m) & (spread >= min_spread_deg) & (prox <= prox_m) & (dtv > 0)
            if valid.any():
                sp = np.where(valid, path / np.maximum(dtv, 1e-12), -math.inf)
                k = int(np.argmax(sp))
                if sp[k] > best_v:
                    best_v, best_start, best_el = float(sp[k]), float(t[i]), float(dtv[k])
            # interpolated end capping path at exactly max_path_m
            if jend < n - 1 and c[jend + 1] - c[i] > max_path_m and c[jend + 1] > c[jend]:
                frac = (lim - c[jend]) / (c[jend + 1] - c[jend])
                ts = t[jend] + frac * (t[jend + 1] - t[jend])
                xs = x[jend] + frac * (x[jend + 1] - x[jend])
                ys = y[jend] + frac * (y[jend + 1] - y[jend])
                uu2 = u[i:jend + 1]  # includes the partial interval's bearing
                spread2 = float(np.max(uu2) - np.min(uu2))
                el = ts - t[i]
                if (el > 0 and spread2 >= min_spread_deg
                        and math.hypot(xs - x[i], ys - y[i]) <= prox_m):
                    sp2 = max_path_m / el
                    if sp2 > best_v:
                        best_v, best_start, best_el = float(sp2), float(t[i]), float(el)
    if best_start is None:
        return None
    return best_v, best_start, best_el
