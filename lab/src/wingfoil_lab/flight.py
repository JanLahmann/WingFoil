"""Flight (foil) segmentation: hysteresis state machine per docs/algorithms.md.

Time-window based: entry/exit holds accumulate real dt between qualifying samples,
so 1 Hz and 0.5 Hz tracks of the same speed profile segment identically. An interval
counts toward a hold only when both of its end samples qualify. Gaps hard-break
flights (a flight never spans a gap; state resets per segment).
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .filters import CleanTrack

MPS_TO_KN = 1.9438445
KMH_TO_MPS = 1.0 / 3.6


@dataclass
class FlightConfig:
    """docs/algorithms.md flight-detection defaults."""

    foil_entry_speed_kmh: float = 12.0
    entry_hold_s: float = 2.0
    foil_exit_speed_kmh: float = 8.0
    exit_hold_s: float = 3.0
    min_flight_duration_s: float = 5.0
    touchdown_merge_gap_s: float = 0.0   # 0 = off (phone-only, v2)


@dataclass
class Flight:
    start_t: float       # first qualifying (>= entry) sample -- backdated
    end_t: float         # first sub-exit sample -- backdated (segment end if cut by a gap)
    dist_m: float        # trapezoid integral of Doppler speed over the flight
    max_kn: float
    duration_s: float


@dataclass
class FlightResult:
    flights: list[Flight]
    foil_time_s: float
    foil_pct: float      # of timer time = total non-gap time
    flight_count: int
    longest: Flight | None


def segment_flights(clean: CleanTrack, config: FlightConfig | None = None) -> FlightResult:
    cfg = config or FlightConfig()
    entry = cfg.foil_entry_speed_kmh * KMH_TO_MPS
    exit_ = cfg.foil_exit_speed_kmh * KMH_TO_MPS
    flights: list[Flight] = []
    for seg in clean.segments():
        t = seg["t"].to_numpy(float)
        v = seg["doppler_mps"].to_numpy(float)
        for s, e in _flight_spans(t, v, entry, exit_, cfg.entry_hold_s, cfg.exit_hold_s):
            dur = float(t[e] - t[s])
            if dur < cfg.min_flight_duration_s:
                continue
            tt, vv = t[s:e + 1], v[s:e + 1]
            dist = float(np.sum((vv[1:] + vv[:-1]) / 2.0 * np.diff(tt)))
            flights.append(Flight(start_t=float(t[s]), end_t=float(t[e]), dist_m=dist,
                                  max_kn=float(np.max(vv) * MPS_TO_KN), duration_s=dur))
    foil_time = float(sum(f.duration_s for f in flights))
    timer = clean.timer_time_s
    pct = 100.0 * foil_time / timer if timer > 0 else 0.0
    longest = max(flights, key=lambda f: f.duration_s, default=None)
    return FlightResult(flights=flights, foil_time_s=foil_time, foil_pct=float(pct),
                        flight_count=len(flights), longest=longest)


def _flight_spans(t: np.ndarray, v: np.ndarray, entry: float, exit_: float,
                  entry_hold: float, exit_hold: float) -> list[tuple[int, int]]:
    """Hysteresis over one gap-free segment; returns (start_idx, end_idx) pairs."""
    spans: list[tuple[int, int]] = []
    on = False
    start_idx = -1
    run = -1          # entry-run first index, -1 = inactive
    acc = 0.0
    xrun = -1         # exit-run first index
    xacc = 0.0
    for i in range(len(t)):
        if not on:
            if v[i] >= entry:
                if run < 0:
                    run, acc = i, 0.0
                else:
                    acc += t[i] - t[i - 1]
                if acc >= entry_hold:
                    on = True
                    start_idx = run
                    xrun, xacc = -1, 0.0
            else:
                run = -1
        else:
            if v[i] <= exit_:
                if xrun < 0:
                    xrun, xacc = i, 0.0
                else:
                    xacc += t[i] - t[i - 1]
                if xacc >= exit_hold:
                    on = False
                    spans.append((start_idx, xrun))
                    run = -1
            else:
                xrun = -1
    if on:
        spans.append((start_idx, len(t) - 1))
    return spans
