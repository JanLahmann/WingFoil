"""Shared off-foil evidence: the channels every outcome verdict is read from.

Turn outcomes (`turns.py`) and flight-end outcomes (`flightend.py`) ask the *same three
questions* of the same track -- did the foil stop carrying (speed), did the wrist go under
(barometer), did the rider have to pump it back up (accelerometer) -- so the masks, the
stop measure and the recovery search live here and both callers read one ladder. Only the
maneuver-specific parts stay with the caller: which window is judged, which entry speed the
recovery is measured against, and what the verdict is called.

The contract is docs/algorithms/pumping.md "Turn outcome"; `flightend.py` reuses steps 0-4 of it
verbatim and only renames the leaf verdicts.
"""

from __future__ import annotations

import math
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
    baseline: np.ndarray         # the local altitude baseline `submerged` was read against
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
    gap = df["gap_before"].to_numpy(bool)
    submerged, baseline = submerged_trace(df["alt_m"].to_numpy(float), t, gap, baro_drop_m)
    return OffFoilEvidence(
        t=t, gap=gap, doppler=dop, speed=speed,
        submerged=submerged, baseline=baseline,
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


# ------------------------------------------------------------------- the submersion mask

#: The baseline's time constant, seconds. The watch's live test walks its pressure baseline
#: by `BARO_EMA` = 0.02 of the residual per 1 Hz sample; spelled as a time constant instead,
#: the same walk is exact at any sample rate, which a bare coefficient is not (a 4 Hz source
#: would adapt four times as fast for no physical reason). **A constant, not a parameter:**
#: it is the altimeter's own slew behaviour, not a judgement about riding, and a rider who
#: moved it would be tuning his watch's firmware rather than his session.
BARO_TAU_S = 50.0

#: How long a level has to hold before the baseline accepts it, seconds. A dunk is a spike --
#: 30 cm of water for a few seconds -- and a re-anchored altimeter is a *level*: a tester's
#: fenix 5X Plus (20 Sep 2026) stepped its whole reference by up to 190 m between stretches
#: and then sat there for minutes. Twenty seconds is long enough that no fall can buy it
#: (the longest corpus episode lasts 9 s) and short enough that the stretch after a re-anchor
#: is read as riding rather than as a swim. **A constant, not a parameter**, for the same
#: reason as above: it describes the sensor, not the sport.
BARO_SETTLE_S = 20.0

#: How still that level has to be, metres. Within +/-5 m of each other for `BARO_SETTLE_S` is
#: flat next to a `turnBaroDrop` of 25 m and next to the 250 m a wrist under water reads, so
#: the release cannot be triggered by a dunk that is merely slow to come back. **A constant,
#: not a parameter**, for the same reason as above.
BARO_SETTLE_M = 5.0


def _settled(alt: np.ndarray, t: np.ndarray, gap: np.ndarray, i: int, x: float) -> bool:
    """Has the level held within `BARO_SETTLE_M` for `BARO_SETTLE_S` of unbroken samples?

    Walks back from `i` while the window is not yet `BARO_SETTLE_S` long, and refuses on the
    first gap, the first non-finite sample and the first sample more than `BARO_SETTLE_M`
    from `x`. False when the track simply does not reach back that far -- a settle has to be
    *observed*, and the opening seconds of a recording have observed nothing.
    """
    j = i
    while j > 0 and t[i] - t[j] < BARO_SETTLE_S:
        if gap[j] or not np.isfinite(alt[j - 1]) or abs(alt[j - 1] - x) > BARO_SETTLE_M:
            return False
        j -= 1
    return t[i] - t[j] >= BARO_SETTLE_S - 1e-9


def submerged_trace(alt: np.ndarray, t: np.ndarray, gap: np.ndarray,
                    drop_m: float) -> tuple[np.ndarray, np.ndarray]:
    """(mask, baseline): the wrist-under test and the line each sample was judged against.

    Causal and local (engine 0.22.0, docs/algorithms/pumping.md "Turn outcome" step 2). A sample is
    wet when it sits `drop_m` below the baseline **in force at that moment**, not below the
    session's median: a watch that re-anchors its altitude after a swim otherwise turns every
    later stretch into a swim of its own.

    The baseline starts at the first finite sample, restarts at every sample a recording gap
    precedes, and otherwise walks towards a dry sample with time constant `BARO_TAU_S`. While
    a sample reads wet the baseline **holds** -- a swim must not be able to re-baseline itself
    dry -- except for the **settle release**: a level that has held for `BARO_SETTLE_S` within
    `BARO_SETTLE_M` is accepted as the new baseline and the sample is dry. A dunk is a spike;
    a level is not a dunk.

    All-NaN (no altitude channel) yields all-False, so sources without a barometer simply
    lose this evidence instead of failing.
    """
    n = len(alt)
    mask = np.zeros(n, dtype=bool)
    baseline = np.full(n, np.nan)
    base: float | None = None
    last_t = 0.0
    for i in range(n):
        x = float(alt[i])
        if not np.isfinite(x):
            baseline[i] = np.nan if base is None else base
            continue
        if base is None or gap[i]:
            base, last_t = x, float(t[i])
            baseline[i] = base
            continue
        dt = float(t[i]) - last_t
        last_t = float(t[i])
        if x >= base - drop_m:
            base += (1.0 - math.exp(-dt / BARO_TAU_S)) * (x - base)
        elif _settled(alt, t, gap, i, x):
            base = x                            # the settle release: a level is not a dunk
        else:
            mask[i] = True                      # wet: the baseline holds under a spike
        baseline[i] = base
    return mask, baseline


def submerged_mask(alt: np.ndarray, t: np.ndarray, gap: np.ndarray,
                   drop_m: float) -> np.ndarray:
    """Per sample: the barometer reads `drop_m` below the local baseline = wrist wet.

    The mask half of `submerged_trace`, for the callers that do not need the baseline.
    """
    return submerged_trace(alt, t, gap, drop_m)[0]


# --------------------------------------------------------------- submersion episodes


#: Two runs closer together than this are one submersion (docs/algorithms/pumping.md "Submersion
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
    drop_m: float                    # deepest sample below the baseline the run started on
    #: The counted turn whose outcome window this run overlaps, else None.
    turn_index: int | None = None
    #: Failing that, the drawn flight end whose window it overlaps, else None -- and a run
    #: with neither happened while the rider was already off the foil.
    flight_end_index: int | None = None


def submersion_runs(t: np.ndarray, gap: np.ndarray, submerged: np.ndarray,
                    alt: np.ndarray, baseline: np.ndarray,
                    merge_s: float = SUBMERSION_MERGE_S) -> list[Submersion]:
    """The mask's contiguous true-runs, per gap-free segment, with near ones merged.

    A recording gap always breaks a run: the samples either side of it are not evidence
    about one another, which is the rule every other window in this module obeys.

    `baseline` is `submerged_trace`'s second return, and a run's depth is read against the
    line **in force at its first wet sample** -- the same line the mask crossed to open the
    run, so the two cannot drift and `drop_m` is always at least `turnBaroDrop`.
    """
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
                              drop_m=float(baseline[a] - deepest)))
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


def outcome_tail(t: np.ndarray, gap: np.ndarray, dop: np.ndarray, lo: int,
                 from_t: float, after_t: float, thr_mps: float, hold_s: float,
                 lookahead_s: float, not_recovered_s: float) -> tuple[int, bool]:
    """(last sample index of an outcome tail, *did the rider never recover*).

    **A fall the turn caused is the turn's fall** (engine 0.24.0, ADR-032). `recovery_end`
    above answers "how long is this event on the hook" and closes the tail at the first
    recovery, the first gap, or a cap. Until 0.24.0 that cap was `lookahead_s` (12 s) for
    everyone, and a rider who *never recovers* — the learner who mushes slowly out of a jibe
    and coasts to a stop — had his stop begin just past it, so the maneuver read `touchdown`
    and the stop was booked a second time by the other channel. The tail now follows a
    rider who is **still not flying again** for up to `not_recovered_s` (30 s).

    Recovery is unchanged and still closes the tail wherever it happens, so this only ever
    lengthens a tail that had nothing to close it. A recording gap still ends the
    measurement exactly as before: a gap inside the first `lookahead_s` closes the tail
    there *and* reports `False` — the samples the far side of a hole are not evidence that
    the rider failed to recover, they are no evidence at all.

    The second return is the **not-recovered condition**, defined once here and read by both
    `turns.py` and `flightend.py`: the tail ran past `lookahead_s` without recovery and
    without a gap. Equivalently: *no recovery at any point between the event and the stop.*
    """
    hi = recovery_end(t, gap, dop, lo, from_t + max(lookahead_s, not_recovered_s),
                      after_t, thr_mps, hold_s)
    return hi, bool(float(t[hi]) > from_t + lookahead_s)


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
