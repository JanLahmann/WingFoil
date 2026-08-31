"""Offline replica of the WATCH's live pump/takeoff segmentation -- a TUNING HARNESS.

NOT engine code: nothing in `wingfoil_lab` imports it, and it must never be used as a
reference for anything. It is a faithful Python transcription of
`garmin/source/detectors/PumpDetector.mc` (plus the slice of `WingFoilCore.FlightDetector`
that drives it), so the watch's LIVE rule can be replayed offline against a fixture FIT and
its segmentation knobs swept against the phone engine's authoritative episode count
(`lab/src/wingfoil_lab/takeoff.py`, which stays untouched -- the phone is authoritative by
design, docs/plan.md 3).

Faithfulness check: replay the 2026-08-29 ciq fixture and compare against the watch's own
session dev field `takeoff_pack` (avgPumpsX10<<16 | attempts<<8 | successes).

    uv run python tools/watch_pump_replica.py ../fixtures/sessions/ciq/*.fit
    uv run python tools/watch_pump_replica.py --sweep ../fixtures/sessions/ciq/*.fit

Structure: the FIR/peak-pick front end is knob-independent, so the stroke train (with the
watch's filter resets, warmups, refractory and 1 s group delay all reproduced) is computed
once per fixture and the swept state machine is replayed over it.
"""

from __future__ import annotations

import argparse
import math
import sys
from dataclasses import dataclass
from pathlib import Path

import fitdecode
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from wingfoil_lab.goldens import analyze  # noqa: E402
from wingfoil_lab.parse import _accel_batch, _frame_fields  # noqa: E402

# ---- PumpDetector.mc constants ------------------------------------------------------

GRID_HZ = 25
STEP_MS = 40
N_TAPS = 51
GROUP_DELAY_MS = 1000
BAND_LO_HZ = 0.5
BAND_HI_HZ = 2.5
STROKE_AMP_G = 0.25
REFRACTORY_MS = 400
BURST_GAP_MS = 1500
MIN_STROKES = 4
LEVEL_ALPHA = 0.002
MILLI_G_FLOOR = 20.0

# WingFoilCore.Config / FlightDetector
ENTRY_MPS = 3.33
EXIT_MPS = 2.22
ENTRY_HOLD_S = 2
EXIT_HOLD_S = 3
MIN_FLIGHT_S = 5


@dataclass(frozen=True)
class Knobs:
    """Segmentation knobs under test. Defaults = today's shipping watch code."""

    attempt_window_ms: int = 10000        # ATTEMPT_WINDOW_MS: success window + fail silence
    merge_gap_ms: int = 10000             # silence that still keeps one effort alive
    merge_from_burst_start: bool = False  # measure that silence to the burst's FIRST stroke
                                          # (lab) or to its qualifying 4th (today's watch)
    hold_open_while_bursting: bool = False   # don't expire an effort while strokes arrive
    defer_ms: int = 0                     # hold an effort open while a burst that began
                                          # inside the merge window is still too young to
                                          # have reached pumpMinStrokes (0 = off)
    pumps_last_burst_only: bool = False   # pumps-to-takeoff = the lead burst, not the effort


def _bandpass_taps() -> np.ndarray:
    mid = (N_TAPS - 1) / 2.0
    f_lo, f_hi = 2.0 * BAND_LO_HZ / GRID_HZ, 2.0 * BAND_HI_HZ / GRID_HZ

    def low_pass(f: float, k: float) -> float:
        if k == 0.0:
            return f
        x = math.pi * f * k
        return f * math.sin(x) / x

    return np.asarray([(low_pass(f_hi, i - mid) - low_pass(f_lo, i - mid))
                       * (0.54 - 0.46 * math.cos(2.0 * math.pi * i / (N_TAPS - 1)))
                       for i in range(N_TAPS)])


TAPS = _bandpass_taps()

# What PumpDetector.mc does today, after this harness's sweep: merge on the burst's first
# stroke, hold an effort open for ATTEMPT_JOIN_GRACE_MS while a burst that began inside the
# window forms, and report the lead burst as pumps-to-takeoff.
TUNED = Knobs(merge_from_burst_start=True, defer_ms=6500, pumps_last_burst_only=True)


# ---- FIT feed ------------------------------------------------------------------------

@dataclass
class Feed:
    rec_t: np.ndarray            # record times, s on the records' base
    speed: np.ndarray            # m/s (0 where absent)
    sample_ms: np.ndarray        # every accel sample, ms
    sample_mag: np.ndarray       # |a| raw (milli-g on Garmin; the scale is sniffed)
    batch_of: np.ndarray         # index of the batch each sample came in
    batch_arrival_ms: np.ndarray # last sample time of each batch = when the watch saw it
    batch_reset: np.ndarray      # bool: this batch tripped the late/short-batch reset
    watch_pack: tuple | None     # (avgPumpsX10, attempts, successes) from takeoff_pack


def load_feed(path: Path) -> Feed:
    records, batches, session = [], [], {}
    with fitdecode.FitReader(path, check_crc=fitdecode.CrcCheck.WARN) as reader:
        for frame in reader:
            if not isinstance(frame, fitdecode.FitDataMessage):
                continue
            if frame.name == "record":
                f = _frame_fields(frame)
                if "timestamp" in f:
                    records.append((f["timestamp"].timestamp(),
                                    f.get("enhanced_speed", f.get("speed"))))
            elif frame.name == "accelerometer_data":
                b = _accel_batch(_frame_fields(frame))
                if b is not None:
                    batches.append(b)
            elif frame.name == "session":
                session = _frame_fields(frame)

    records.sort()
    epoch0 = records[0][0]
    rec_t = np.asarray([r[0] - epoch0 for r in records])
    speed = np.asarray([0.0 if r[1] is None else float(r[1]) for r in records])

    # The FIT carries the SensorLogger stream (100 Hz on fenix 8); the LIVE listener
    # `SessionController._startAccel` asks for `PumpDetector.GRID_HZ` = 25 Hz with
    # `:period => 1`, so the detector sees ~25 samples per second. Box-average |a| onto that
    # grid -- the same reduction the lab's `pump_track_from_arrays` performs, and the same one
    # `onAccelBatch` performs when a device runs the sensor faster than the grid.
    at = np.concatenate([b[0] for b in batches]) - epoch0
    amag = np.sqrt(sum(np.concatenate([b[i] for b in batches]) ** 2 for i in (1, 2, 3)))
    order = np.argsort(at, kind="stable")
    at, amag = at[order], amag[order]
    step = 1.0 / GRID_HZ
    n_bins = int(np.floor((at[-1] - at[0]) / step)) + 1
    idx = np.clip(((at - at[0]) / step).astype(int), 0, n_bins - 1)
    count = np.bincount(idx, minlength=n_bins)
    total = np.bincount(idx, weights=amag, minlength=n_bins)
    grid_ms = np.round((at[0] + np.arange(n_bins) * step) * 1000).astype(np.int64)
    full = count > 0
    grid_ms, gmag = grid_ms[full], total[full] / count[full]

    # the listener hands the detector one batch per second; a hole in the grid makes the next
    # batch short or late, which is exactly what trips `onAccelBatch`'s reset test
    ms, mag, bof, arrival, reset = [], [], [], [], []
    last_arrival = 0
    starts = np.arange(0, len(grid_ms), GRID_HZ)
    for bi, a in enumerate(starts):
        tm = grid_ms[a:a + GRID_HZ]
        n = len(tm)
        now = int(tm[-1])
        span = n * 1000 // GRID_HZ
        reset.append(last_arrival != 0 and abs(now - last_arrival - span) > span / 2 + 200)
        last_arrival = now
        ms.append(tm)
        mag.append(gmag[a:a + GRID_HZ])
        bof.append(np.full(n, bi))
        arrival.append(now)

    pack = session.get("takeoff_pack")
    unpacked = None
    if isinstance(pack, (int, float)):
        p = int(pack)
        unpacked = ((p >> 16) & 0xFF, (p >> 8) & 0xFF, p & 0xFF)
    return Feed(rec_t=rec_t, speed=speed,
                sample_ms=np.concatenate(ms), sample_mag=np.concatenate(mag),
                batch_of=np.concatenate(bof),
                batch_arrival_ms=np.asarray(arrival),
                batch_reset=np.asarray(reset), watch_pack=unpacked)


# ---- the 1 Hz context track (knob-independent) ----------------------------------------

class WatchFlight:
    """The slice of WingFoilCore.FlightDetector the pump detector reads."""

    STATE_OFF, STATE_ON = 0, 2

    def __init__(self):
        self.state = self.STATE_OFF
        self._entry_accum = 0.0
        self._entry_run = False
        self._exit_accum = 0.0
        self._exit_run = False
        self._cur_s = 0.0
        self._confirmed = False

    def tick(self, dt: float, speed: float) -> bool:
        """True on EVENT_START: a flight just reached minFlight."""
        if self.state == self.STATE_OFF:
            if speed >= ENTRY_MPS:
                if self._entry_run:
                    self._entry_accum += dt
                else:
                    self._entry_run, self._entry_accum = True, 0.0
                if self._entry_accum >= ENTRY_HOLD_S:
                    self.state = self.STATE_ON
                    self._confirmed = False
                    self._cur_s = self._entry_accum
                    self._entry_accum, self._entry_run = 0.0, False
                    self._exit_accum, self._exit_run = 0.0, False
            else:
                self._entry_accum, self._entry_run = 0.0, False
            return False

        self._cur_s += dt
        event = False
        if not self._confirmed and not self._exit_run and self._cur_s >= MIN_FLIGHT_S:
            self._confirmed = True
            event = True
        if speed <= EXIT_MPS:
            if self._exit_run:
                self._exit_accum += dt
            else:
                self._exit_run, self._exit_accum = True, 0.0
            if self._exit_accum >= EXIT_HOLD_S:
                self.state = self.STATE_OFF
                self._cur_s = 0.0
                self._entry_accum, self._entry_run = 0.0, False
                self._exit_accum, self._exit_run = 0.0, False
        else:
            self._exit_accum, self._exit_run = 0.0, False
        return event


def context_track(feed: Feed) -> list[tuple[int, bool, bool, bool]]:
    """(now_ms, gap, flying, flight_start) per MetricsEngine tick."""
    out = []
    flight = WatchFlight()
    prev_t = None
    for i, t in enumerate(feed.rec_t):
        dt = 1.0 if prev_t is None else t - prev_t
        prev_t = t
        if dt < 0.2:
            continue
        gap = dt > 3.0 or not (0.0 <= feed.speed[i] < 40.0)
        if gap:
            out.append((int(round(t * 1000)), True, False, False))
            continue
        started = flight.tick(min(dt, 3.0), float(feed.speed[i]))
        out.append((int(round(t * 1000)), False,
                    flight.state == WatchFlight.STATE_ON, started))
    return out


# ---- the front end: |a| -> stroke train (knob-independent) ----------------------------

def stroke_train(feed: Feed, ticks: list[tuple[int, bool, bool, bool]]
                 ) -> list[tuple[int, int]]:
    """(arrival_ms, stroke_ms) for every stroke the watch's chain would emit.

    Reproduces: the milli-g sniff, the 20 s EMA level (which `resetFilter` does NOT clear),
    the causal 51-tap FIR, the N_TAPS+2 warmup after every reset, the three-sample local
    maximum with the amplitude gate, the global refractory dead time, and the 1 s group-delay
    correction. Filter resets come from late/short batches and from `onGap` ticks.
    """
    ms, mag = feed.sample_ms, feed.sample_mag
    # scale sniff: the first sample with |a| > 0.2 decides g vs milli-g, once, for good
    first = int(np.argmax(mag > 0.2))
    scale = 0.001 if mag[first] > MILLI_G_FLOOR else 1.0
    x = mag[first:] * scale
    ms = ms[first:]
    batch_of = feed.batch_of[first:]

    # 20 s EMA level, subtracted per sample (continuous across resets)
    level = np.empty_like(x)
    lv = x[0]
    for i, v in enumerate(x):
        level[i] = lv
        lv += LEVEL_ALPHA * (v - lv)
    centred = x - level

    # reset points: batch-gap resets, plus every onGap tick (which calls resetFilter)
    resets = {int(np.searchsorted(ms, feed.batch_arrival_ms[bi] - 999, "left"))
              for bi in np.flatnonzero(feed.batch_reset)}
    resets |= {int(np.searchsorted(ms, t, "left")) for t, gap, _, _ in ticks if gap}
    bounds = sorted({0, len(x)} | {r for r in resets if 0 < r < len(x)})

    out: list[tuple[int, int]] = []
    last_stroke_ms = 0
    for a, b in zip(bounds, bounds[1:]):
        seg = centred[a:b]
        if len(seg) < N_TAPS + 3:
            continue
        y = np.convolve(seg, TAPS)[:len(seg)]     # causal: y[n] uses seg[n-50..n]
        # the watch starts testing on the (N_TAPS+3)-th sample after a reset, and tests y[n-1]
        lo = N_TAPS + 1
        idx = np.flatnonzero((y[lo:-1] > STROKE_AMP_G) & (y[lo:-1] > y[lo - 1:-2])
                             & (y[lo:-1] >= y[lo + 1:])) + lo
        for i in idx:
            stroke_ms = int(ms[a + i + 1]) - GROUP_DELAY_MS - STEP_MS
            if last_stroke_ms == 0 or stroke_ms - last_stroke_ms >= REFRACTORY_MS:
                last_stroke_ms = stroke_ms
                out.append((int(feed.batch_arrival_ms[batch_of[a + i + 1]]), stroke_ms))
    return out


# ---- the swept state machine (PumpDetector.mc, verbatim) ------------------------------

class WatchPump:
    def __init__(self, k: Knobs):
        self.k = k
        self.strokes = 0
        self.successes = 0
        self.failed = 0
        self.recovery_episodes = 0
        self.pumps_sum = 0
        self.efforts: list[tuple[float, float, int, str]] = []

        self._burst_n = 0
        self._burst_start_ms = 0
        self._burst_prev_ms = 0
        self._burst_owned = False
        self._at_open = False
        self._at_start_ms = 0
        self._at_last_ms = 0
        self._at_strokes = 0
        self._at_burst_strokes = 0
        self._at_recovery = False
        self._flying = False
        self._turn_open = False
        self._on_foil_ms = 0

    def on_gap(self) -> None:
        self._at_open = False
        self._at_recovery = False
        self._burst_n = 0
        self._burst_owned = False

    def on_stroke(self, t_ms: int) -> None:
        # The raw peak train -- `PumpDetector.peaks`, not its `strokes`. This harness sweeps
        # the *segmentation* knobs, and the stroke train is the input those are swept over;
        # the session total's amplitude and speed gates (engine 0.8.0) are deliberately not
        # replicated here, because they change no attempt boundary. The printed `str` column
        # is therefore the peak count, which is what it always was.
        self.strokes += 1
        if self._burst_n > 0 and t_ms - self._burst_prev_ms <= BURST_GAP_MS:
            self._burst_n += 1
        else:
            self._burst_n = 1
            self._burst_start_ms = t_ms
            self._burst_owned = False
        self._burst_prev_ms = t_ms

        if self._burst_n < MIN_STROKES:
            return
        k = self.k
        if self._burst_n == MIN_STROKES:
            ref = self._burst_start_ms if k.merge_from_burst_start else t_ms
            if self._at_open and ref - self._at_last_ms < k.merge_gap_ms:
                self._at_strokes += MIN_STROKES
                self._at_burst_strokes = MIN_STROKES
                self._burst_owned = True
            elif not self._flying:
                self._at_open = True
                self._at_start_ms = self._burst_start_ms
                self._at_strokes = MIN_STROKES
                self._at_burst_strokes = MIN_STROKES
                self._at_recovery = self._turn_open
                self._burst_owned = True
        elif self._burst_owned and self._at_open:
            self._at_strokes += 1
            self._at_burst_strokes += 1
        if self._burst_owned and self._at_open:
            self._at_last_ms = t_ms
            if self._turn_open:
                self._at_recovery = True

    def tick(self, now_ms: int, flying: bool, turn_open: bool, flight_start: bool) -> None:
        self._turn_open = turn_open
        if flying and not self._flying:
            self._on_foil_ms = now_ms - ENTRY_HOLD_S * 1000
        self._flying = flying
        if flight_start:
            self._flight_confirmed()
        self._expire(now_ms)

    def _flight_confirmed(self) -> None:
        self.successes += 1
        k = self.k
        pumped = (self._at_open and self._on_foil_ms >= self._at_start_ms
                  and self._on_foil_ms - self._at_last_ms <= k.attempt_window_ms)
        pumps = 0
        if pumped:
            pumps = self._at_burst_strokes if k.pumps_last_burst_only else self._at_strokes
        self.pumps_sum += pumps
        if pumped:
            self.efforts.append((self._at_start_ms / 1000, self._at_last_ms / 1000,
                                 self._at_strokes, "success"))
            self._at_open = False
            self._at_recovery = False
            self._burst_owned = False

    def _expire(self, now_ms: int) -> None:
        k = self.k
        if not self._at_open or now_ms - self._at_last_ms <= k.attempt_window_ms:
            return
        if self._flying and self._on_foil_ms - self._at_last_ms <= k.attempt_window_ms:
            return
        if (k.hold_open_while_bursting and self._burst_n > 0
                and now_ms - self._burst_prev_ms <= BURST_GAP_MS):
            return
        if (k.defer_ms and self._burst_n > 0 and not self._burst_owned
                and self._burst_start_ms - self._at_last_ms < k.merge_gap_ms
                and now_ms - self._burst_start_ms <= k.defer_ms):
            return      # a burst opened inside the window and may still qualify
        if self._at_recovery:
            self.recovery_episodes += 1
            outcome = "recovery"
        else:
            self.failed += 1
            outcome = "failed"
        self.efforts.append((self._at_start_ms / 1000, self._at_last_ms / 1000,
                             self._at_strokes, outcome))
        self._at_open = False
        self._at_recovery = False
        self._burst_owned = False

    @property
    def attempts(self) -> int:
        return self.successes + self.failed

    @property
    def avg_pumps_x10(self) -> int:
        if self.successes <= 0:
            return 0
        return min(self.pumps_sum * 10 // self.successes, 254)


def replay(strokes: list[tuple[int, int]], ticks: list[tuple[int, bool, bool, bool]],
           k: Knobs) -> WatchPump:
    """Interleave the stroke train and the 1 Hz ticks in *processing* order.

    A stroke is handed to the state machine when its batch arrives -- i.e. ~1 s after the
    instant it carries -- exactly as on the watch, where the FIR's group delay is corrected
    in the timestamp but not in the wall clock.
    """
    pump = WatchPump(k)
    si = 0
    for now_ms, gap, flying, started in ticks:
        while si < len(strokes) and strokes[si][0] <= now_ms:
            pump.on_stroke(strokes[si][1])
            si += 1
        if gap:
            pump.on_gap()
            continue
        pump.tick(now_ms, flying, False, started)
    return pump


# ---- reporting -----------------------------------------------------------------------

def phone_reference(path: Path) -> tuple[int, int, float]:
    s = analyze(path).takeoff_summary
    return s.takeoff_attempts, s.takeoff_successes, s.avg_pumps_to_takeoff or 0.0


def main() -> None:
    ap = argparse.ArgumentParser(description="watch pump/takeoff replica (tuning harness)")
    ap.add_argument("fits", nargs="+", type=Path)
    ap.add_argument("--sweep", action="store_true")
    args = ap.parse_args()

    data = {}
    for p in args.fits:
        feed = load_feed(p)
        ticks = context_track(feed)
        data[p] = (feed, ticks, stroke_train(feed, ticks), phone_reference(p))

    def report(label: str, k: Knobs) -> None:
        print(f"\n--- {label}")
        for p, (feed, ticks, strokes, ref) in data.items():
            w = replay(strokes, ticks, k)
            ra, rs, rp = ref
            real = ("watch %3d/%3d/%5.1f" % (feed.watch_pack[1], feed.watch_pack[2],
                                             feed.watch_pack[0] / 10)
                    if feed.watch_pack else "watch     n/a      ")
            print(f"  {p.name[:30]:32} replica {w.attempts:>3}/{w.successes:>3}/"
                  f"{w.avg_pumps_x10 / 10:5.1f} str {w.strokes:>4}   {real}   "
                  f"phone {ra:>3}/{rs:>3}/{rp:5.1f}   dAtt {w.attempts - ra:+d}")

    report("BEFORE (pre-tuning watch rule)", Knobs())
    report("AFTER  (PumpDetector.mc as shipped now)", TUNED)
    if not args.sweep:
        return

    grid = [Knobs(merge_gap_ms=g, merge_from_burst_start=s, hold_open_while_bursting=h,
                  defer_ms=d)
            for s in (False, True) for h in (False, True)
            for d in (0, 3000, 4500, 6000)
            for g in (10000, 12000, 14000, 16000, 20000)]
    rows = []
    for k in grid:
        err, detail, ok = 0, [], True
        for p, (feed, ticks, strokes, ref) in data.items():
            w = replay(strokes, ticks, k)
            ok &= w.successes == ref[1]
            err += abs(w.attempts - ref[0])
            detail.append(f"{p.name[5:10]} {w.attempts:>3}/{ref[0]:<3}")
        rows.append((err, ok, k, detail))
    rows.sort(key=lambda r: (not r[1], r[0]))
    print("\n--- sweep, sorted by total |attempt error| vs phone")
    for err, ok, k, detail in rows:
        print(f"  err {err:>3} succ_exact {str(ok):5} gap {k.merge_gap_ms:>5} "
              f"from_burst_start {str(k.merge_from_burst_start):5} "
              f"hold_open {str(k.hold_open_while_bursting):5} defer {k.defer_ms:>5}  "
              f"{'  '.join(detail)}")


if __name__ == "__main__":
    main()
