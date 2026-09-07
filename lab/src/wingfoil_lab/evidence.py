"""Shared off-foil evidence: the channels every outcome verdict is read from.

Turn outcomes (`turns.py`) and flight-end outcomes (`flightend.py`) ask the *same three
questions* of the same track -- did the foil stop carrying (speed), did the wrist go under
(barometer), did the rider have to pump it back up (accelerometer) -- so the masks, the
stop measure and the recovery search live here and both callers read one ladder. Only the
maneuver-specific parts stay with the caller: which window is judged, which entry speed the
recovery is measured against, and what the verdict is called.

The contract is docs/algorithms.md "Turn outcome"; `flightend.py` reuses steps 0-4 of it
verbatim and only renames the leaf verdicts.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .filters import CleanTrack, hybrid_speed
from .flight import FlightResult

MPS_TO_KN = 1.9438445
KMH_TO_MPS = 1.0 / 3.6


@dataclass
class OffFoilEvidence:
    """Per-sample evidence arrays for one cleaned track, aligned to `t`."""

    t: np.ndarray                # sample times (whole track, gaps included)
    gap: np.ndarray              # bool: a recording gap precedes this sample
    doppler: np.ndarray          # device Doppler (flight state, recovery test)
    speed: np.ndarray            # min(Doppler, positional): the sharp "is it carrying" test
    submerged: np.ndarray        # bool: barometer says the wrist is under water
    flying: np.ndarray           # bool: in a flight, above exit speed, not submerged

    def __len__(self) -> int:
        return len(self.t)


def off_foil_evidence(clean: CleanTrack, flights: FlightResult,
                      exit_speed_kmh: float, baro_drop_m: float) -> OffFoilEvidence | None:
    """Build the evidence arrays for a whole cleaned track, or None when it is empty.

    Built over the whole track rather than per segment: a fall that starts before a
    recording gap is still followed into the samples after it (the *window* search stops at
    the gap, but the arrays must span it).
    """
    df = clean.records
    if df.empty:
        return None
    t = df["t"].to_numpy(float)
    dop = df["doppler_mps"].to_numpy(float)
    speed = np.minimum(dop, hybrid_speed(df))
    submerged = submerged_mask(df["alt_m"].to_numpy(float), baro_drop_m)
    return OffFoilEvidence(
        t=t, gap=df["gap_before"].to_numpy(bool), doppler=dop, speed=speed,
        submerged=submerged,
        flying=flying_mask(t, speed, submerged, flights, exit_speed_kmh * KMH_TO_MPS),
    )


def flying_mask(t: np.ndarray, speed: np.ndarray, submerged: np.ndarray,
                flights: FlightResult, exit_mps: float) -> np.ndarray:
    """Per sample: inside a flight, above the foil exit speed, and not underwater.

    Flight segmentation alone is too coarse for this job: its exit needs `exitHold` (3 s)
    of sub-exit speed, so a 1-2 s touchdown -- exactly Jan's middle case -- never breaks
    the flight. The instantaneous speed test makes those visible while the flight mask
    still catches the long losses that the speed trace alone would blur.

    `speed` is min(Doppler, positional): both channels over-read a stopped rider (wrist
    Doppler picks up swim strokes, positional picks up GPS jitter) and only the Doppler
    under-reacts, being smoothed over 3-4 s -- so the lower of the two is the sharper
    "is the foil still carrying" test, the same argument the stop measure already makes.
    """
    m = np.zeros(len(t), dtype=bool)
    for f in flights.flights:
        m |= (t >= f.start_t) & (t <= f.end_t)
    return m & (speed > exit_mps) & ~submerged


def submerged_reference(alt: np.ndarray) -> float | None:
    """The altitude the submersion test is measured *against*: the session median of the
    finite samples, or None when there is no altitude channel at all.

    Spelled once because two things read it -- the mask below, and `dropM` on a submersion
    episode, which is how far under this same line the deepest sample of the run got. A
    second median computed anywhere else is a second definition waiting to drift.
    """
    ok = np.isfinite(alt)
    if not ok.any():
        return None
    return float(np.median(alt[ok]))


def submerged_mask(alt: np.ndarray, drop_m: float) -> np.ndarray:
    """Per sample: the barometer reads `drop_m` below the session median = wrist wet.

    All-NaN (no altitude channel) yields all-False, so sources without a barometer simply
    lose this evidence instead of failing.
    """
    ref = submerged_reference(alt)
    if ref is None:
        return np.zeros(len(alt), dtype=bool)
    return np.isfinite(alt) & (alt < ref - drop_m)


# --------------------------------------------------------------- submersion episodes


#: Two runs closer together than this are one submersion (docs/algorithms.md "Submersion
#: episodes"). A dunk and the wave that follows it are one event to the rider, and the
#: altimeter's slew limiter crosses the threshold twice on the way back up.
SUBMERSION_MERGE_S = 2.0


@dataclass
class Submersion:
    """One spell the barometer says the wrist spent under water.

    **Presentation evidence, never a verdict.** The `submerged` flags on turns and flight
    ends are the outcome ladder's input and are computed exactly as they always were; this
    is the same mask read a second way -- as events with a time, a length and a depth, so a
    map can put one mark on each of them instead of one mark on the maneuver that owned one.
    """

    start_t: float                   # first submerged sample of the run
    end_t: float                     # last submerged sample of the run
    duration_s: float                # gap-aware elapsed time between the two
    drop_m: float                    # deepest sample below `submerged_reference`
    #: The counted turn whose outcome window this run overlaps, else None.
    turn_index: int | None = None
    #: Failing that, the drawn flight end whose window it overlaps, else None -- and a run
    #: with neither happened while the rider was already off the foil.
    flight_end_index: int | None = None


def submersion_runs(t: np.ndarray, gap: np.ndarray, submerged: np.ndarray,
                    alt: np.ndarray,
                    merge_s: float = SUBMERSION_MERGE_S) -> list[Submersion]:
    """The mask's contiguous true-runs, per gap-free segment, with near ones merged.

    A recording gap always breaks a run: the samples either side of it are not evidence
    about one another, which is the rule every other window in this module obeys.
    """
    ref = submerged_reference(alt)
    if ref is None:
        return []
    n = len(t)
    spans: list[tuple[int, int]] = []
    i = 0
    while i < n:
        if not submerged[i]:
            i += 1
            continue
        b = i
        while b + 1 < n and submerged[b + 1] and not gap[b + 1]:
            b += 1
        if spans:
            pa, pb = spans[-1]
            near = t[i] - t[pb] < merge_s
            broken = bool(gap[pb + 1:i + 1].any())
            if near and not broken:
                spans[-1] = (pa, b)
                i = b + 1
                continue
        spans.append((i, b))
        i = b + 1

    out = []
    for a, b in spans:
        window = alt[a:b + 1]
        deepest = float(np.min(window[np.isfinite(window)]))
        out.append(Submersion(start_t=float(t[a]), end_t=float(t[b]),
                              duration_s=elapsed(t, gap, a, b),
                              drop_m=float(ref - deepest)))
    return out


def attribute_submersions(subs: list[Submersion],
                          turn_windows: list[tuple[int, float, float]],
                          end_windows: list[tuple[int, float, float]]) -> None:
    """Name what each episode happened *during*, in place.

    Order matters and is the map's: a counted turn's outcome window first, because that is
    the maneuver a rider remembers going under in; then a drawn flight end's window, which
    is the straight-line swim; and otherwise nothing at all -- the rider was already off the
    foil, which is a real answer and not a missing one. First match wins, so an episode is
    named once.
    """
    for sub in subs:
        for index, w0, w1 in turn_windows:
            if sub.start_t <= w1 and sub.end_t >= w0:
                sub.turn_index = index
                break
        if sub.turn_index is not None:
            continue
        for index, w0, w1 in end_windows:
            if sub.start_t <= w1 and sub.end_t >= w0:
                sub.flight_end_index = index
                break


def recovery_end(t: np.ndarray, gap: np.ndarray, dop: np.ndarray, lo: int,
                 cap_t: float, after_t: float, thr_mps: float, hold_s: float) -> int:
    """Last sample index an outcome is judged over: recovery, a gap, or the `cap_t` cap.

    *Recovery* is the rider back to cruising -- Doppler at or above `thr_mps`, held for
    `hold_s` with the same both-ends-qualify convention flight entry uses. Searched only
    past `after_t`, so the speed the window opened at cannot close it immediately.

    A **recording gap ends the window** even before recovery: flights hard-break at gaps, so
    every sample after one reads as "not flying" until a new flight has been established,
    and following the search across would manufacture a loss out of missing data.
    """
    hi, last = lo, -1
    held = 0.0
    for i in range(lo, len(t)):
        if t[i] > cap_t or (i > lo and gap[i]):
            break
        hi = i
        if t[i] <= after_t:
            continue
        if dop[i] < thr_mps:
            held, last = 0.0, -1
            continue
        held = held + (t[i] - t[last]) if last == i - 1 else 0.0
        last = i
        if held >= hold_s:
            break
    return hi


def off_foil_run(t: np.ndarray, flying: np.ndarray, a: int,
                 cap_t: float) -> tuple[int, int]:
    """From the first non-flying sample `a`, (last non-flying index, first flying index).

    The run is followed past the judging window until foiling resumes, capped at `cap_t` so
    an event just before a break does not absorb it. The second value is clamped to the end
    of the track when the rider never gets going again.
    """
    b = a
    while b + 1 < len(t) and not flying[b + 1] and t[b + 1] <= cap_t:
        b += 1
    return b, min(b + 1, len(t) - 1)


def elapsed(t: np.ndarray, gap: np.ndarray, a: int, b: int) -> float:
    """Recorded time from sample `a` to `b`, skipping intervals that span a gap."""
    if b <= a:
        return 0.0
    dt = np.diff(t[a:b + 1])
    return float(dt[~gap[a + 1:b + 1]].sum())


def longest_stop(t: np.ndarray, gap: np.ndarray, v: np.ndarray, a: int, b: int,
                 floor: float) -> float:
    """Longest contiguous spell below `floor` in [a, b], in recorded seconds.

    An interval counts only when *both* of its end samples are below the floor and no gap
    separates them -- the same "hold" convention flight segmentation uses, so a stop and a
    flight exit are measured on the same clock.
    """
    below = v[a:b + 1] < floor
    if below.size < 2:
        return 0.0
    ok = below[1:] & below[:-1] & ~gap[a + 1:b + 1]
    best = run = 0.0
    for keep, step in zip(ok, np.diff(t[a:b + 1])):
        run = run + step if keep else 0.0
        best = max(best, run)
    return float(best)
