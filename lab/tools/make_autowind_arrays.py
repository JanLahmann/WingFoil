#!/usr/bin/env python
r"""TEST-DATA GENERATOR for the watch's auto-wind estimator — not engine code.

Nothing in `wingfoil_lab` imports this, and it changes no engine parameter: it reads the two
`ciq` fixtures through the ordinary pipeline (`parse -> clean -> segment_flights`) and writes
`garmin/tests/AutoWindFixtures.mc`, a recorded 1 Hz (cog, speed, foil-state) stream that
`garmin/tests/WingfoilTests.mc` replays through `WingFoilCore.AutoWind` — docs/testing.md
layer 3, "recorded 1 Hz arrays extracted from fixtures by lab".

    cd lab && uv run python tools/make_autowind_arrays.py            # write the .mc
    cd lab && uv run python tools/make_autowind_arrays.py --check    # verify only

It also carries a Python transcription of `AutoWind.mc` (`Replica` below), the same way
`tools/watch_pump_replica.py` carries one of `PumpDetector.mc`: it is how the parameters were
chosen and the acceptance band justified, and it prints the numbers the generated header
quotes. It is a HARNESS, never a reference — the Monkey C is the implementation and the unit
test is the assertion.

Encoding (three printable ASCII characters per sample, so the arrays are string constants
rather than thousands of array-literal bytecodes):

    char 0   course over ground   _chr(round(cog / 4) % 90)          -> 4 deg cells
    char 1   Doppler speed        _chr(min(89, round(v / 0.2)))      -> 0.2 m/s cells
    char 2   foil state           '1' while the FlightDetector is ON, else '0'

`_chr` is base 33 stepping over `"` and `\`, the two codes a Monkey C string literal cannot
carry raw.

COG is quantized to 4 deg against a histogram whose bins are 10 deg wide and an acceptance
band of 20 deg, so the quantization is a rounding error twice over. The stream is DECIMATED
by `DECIMATION` and replayed with `dt = DECIMATION`, which keeps both the distance weights
and the 60 s evaluation cadence on the session's own clock; it is what makes a two-hour
session fit in a watch unit test at all. Measured cost of the decimation, over decimation
factors 1..8 and every phase offset: under 3 deg on the final direction, and no change to
whether the estimator locks.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from wingfoil_lab.filters import clean, unwrapped_cog_deg  # noqa: E402
from wingfoil_lab.flight import segment_flights  # noqa: E402
from wingfoil_lab.parse import parse_fit  # noqa: E402
from wingfoil_lab.wind import foiling_mask  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "garmin" / "tests" / "AutoWindFixtures.mc"

FIXTURES = [
    "2026-08-07-0754_nago-torbole-windsurfen_ciq",
    "2026-08-29-1440_nago-torbole-windsurfen_ciq",
]
DECIMATION = 3
CHUNK_SAMPLES = 300             # 900 characters per string constant

# ---- AutoWind.mc, transcribed (the harness half) ------------------------------------------

BINS = 36
BIN_DEG = 10.0
SMOOTH_HALF_BINS = 2
LOBE_HALF_BINS = 2
MIN_SPEED_MPS = 2.0
MIN_DISTANCE_M = 500.0
EVAL_PERIOD_S = 60.0
MIN_LOBE_SEP_DEG = 60.0
MAX_LOBE_SEP_DEG = 179.0
SEP_FULL_DEG = 20.0
MASS_FLOOR = 0.2
MASS_SPAN = 0.4
BALANCE_FULL = 0.5
CONE_HALF_DEG = 45.0
MIN_CONE_MASS = 0.01
FULL_MARGIN = 0.4
MIN_CONFIDENCE = 0.5
CONFIRM_DEG = 20.0
HYSTERESIS_DEG = 15.0


def _wrap180(d: float) -> float:
    return (d + 180.0) % 360.0 - 180.0


def _clip01(v: float) -> float:
    return 0.0 if v < 0.0 else (1.0 if v > 1.0 else v)


class Replica:
    """`WingFoilCore.AutoWind` in Python — same constants, same order of operations."""

    def __init__(self) -> None:
        self.hist = [0.0] * BINS
        self.smooth = [0.0] * BINS
        self.distance_m = 0.0
        self.dir_deg = -1.0
        self.since = 0.0
        self.pending = -1.0
        self.locks = 0
        self.updates = 0
        self.max_step_deg = 0.0
        self.lock_distance_m = 0.0

    def tick(self, dt: float, cog: float, speed: float, flying: bool) -> int:
        if flying and speed >= MIN_SPEED_MPS:
            i = int(math.floor((cog % 360.0) / BIN_DEG)) % BINS
            w = speed * dt
            self.hist[i] += w
            self.distance_m += w
        self.since += dt
        if self.since < EVAL_PERIOD_S:
            return 0
        self.since = 0.0
        return self.evaluate()

    def evaluate(self) -> int:
        if self.distance_m < MIN_DISTANCE_M:
            return 0
        n = 2 * SMOOTH_HALF_BINS + 1
        for i in range(BINS):
            self.smooth[i] = sum(self.hist[(i + k) % BINS]
                                 for k in range(-SMOOTH_HALF_BINS, SMOOTH_HALF_BINS + 1)) / n
        first = self._peak(None)
        if first is None:
            return self._unconfirmed()
        second = self._peak(first)
        if second is None:
            return self._unconfirmed()
        l0, m0 = self._lobe(first)
        l1, m1 = self._lobe(second)
        m0 /= self.distance_m
        m1 /= self.distance_m
        sep = abs(_wrap180(l1 - l0))
        if sep > MAX_LOBE_SEP_DEG:
            return self._unconfirmed()
        bisector = self._bisect(l0, l1)
        balance = min(m0, m1) / max(m0, m1) if max(m0, m1) > 0 else 0.0
        axis_conf = (_clip01((m0 + m1 - MASS_FLOOR) / MASS_SPAN)
                     * _clip01(balance / BALANCE_FULL)
                     * _clip01((sep - MIN_LOBE_SEP_DEG) / SEP_FULL_DEG))
        cone_dir, margin = self._cone(bisector)
        certainty = _clip01(margin / FULL_MARGIN)
        # The default-turn-type prior needs a sweep log; the corpus never reaches it (every
        # margin is decisive), so the harness stops at the cone and the synthetic Monkey C
        # tests carry the prior instead.
        if axis_conf * certainty < MIN_CONFIDENCE:
            return self._unconfirmed()
        return self._adopt(cone_dir)

    def _unconfirmed(self) -> int:
        self.pending = -1.0
        return 0

    def _adopt(self, direction: float) -> int:
        if self.dir_deg < 0:
            if self.pending < 0 or abs(_wrap180(direction - self.pending)) > CONFIRM_DEG:
                self.pending = direction
                return 0
            self.dir_deg = direction
            self.pending = -1.0
            self.locks += 1
            self.lock_distance_m = self.distance_m
            return 1
        step = abs(_wrap180(direction - self.dir_deg))
        if step < HYSTERESIS_DEG:
            return 0
        self.max_step_deg = max(self.max_step_deg, step)
        self.dir_deg = direction
        self.updates += 1
        return 2

    def _peak(self, away_from: int | None) -> int | None:
        best, best_v = None, 0.0
        ref = 0.0 if away_from is None else (away_from + 0.5) * BIN_DEG
        for i in range(BINS):
            c = (i + 0.5) * BIN_DEG
            if away_from is not None and abs(_wrap180(c - ref)) < MIN_LOBE_SEP_DEG:
                continue
            if self.smooth[i] > best_v:
                best, best_v = i, self.smooth[i]
        return best

    def _lobe(self, idx: int) -> tuple[float, float]:
        sx = sy = mass = 0.0
        for k in range(-LOBE_HALF_BINS, LOBE_HALF_BINS + 1):
            j = (idx + k) % BINS
            r = math.radians((j + 0.5) * BIN_DEG)
            sx += self.hist[j] * math.cos(r)
            sy += self.hist[j] * math.sin(r)
            mass += self.hist[j]
        if sx == 0.0 and sy == 0.0:
            return (idx + 0.5) * BIN_DEG, mass
        return math.degrees(math.atan2(sy, sx)) % 360.0, mass

    @staticmethod
    def _bisect(a: float, b: float) -> float:
        ra, rb = math.radians(a), math.radians(b)
        return math.degrees(math.atan2(math.sin(ra) + math.sin(rb),
                                       math.cos(ra) + math.cos(rb))) % 360.0

    def _cone(self, bisector: float) -> tuple[float, float]:
        ma = mb = 0.0
        for i in range(BINS):
            c = (i + 0.5) * BIN_DEG
            if abs(_wrap180(c - bisector)) <= CONE_HALF_DEG:
                ma += self.hist[i]
            elif abs(_wrap180(c - bisector - 180.0)) <= CONE_HALF_DEG:
                mb += self.hist[i]
        ma /= self.distance_m
        mb /= self.distance_m
        if ma + mb < MIN_CONE_MASS:
            return bisector % 360.0, 0.0
        d = bisector if ma < mb else bisector + 180.0
        return d % 360.0, abs(ma - mb) / (ma + mb)


# ---- extraction ----------------------------------------------------------------------------


def stream(fit: Path) -> list[tuple[float, float, bool]]:
    """Per-step (cog_deg, doppler_mps, flying) over the whole cleaned track, 1 Hz.

    The same per-step construction `wind.foiling_courses` uses — one entry per gap-free
    1-sample step, taking the step's START sample — minus its two filters, because the point
    of the fixture is to drive the watch's own gates rather than to pre-apply them.
    """
    ct = clean(parse_fit(fit))
    on = foiling_mask(ct, segment_flights(ct))
    out: list[tuple[float, float, bool]] = []
    for seg in ct.segments():
        if len(seg) < 2 or seg["x"].isna().all():
            continue
        idx = seg.index.to_numpy()
        x, y = seg["x"].to_numpy(float), seg["y"].to_numpy(float)
        v = seg["doppler_mps"].to_numpy(float)
        u = np.mod(unwrapped_cog_deg(x, y), 360.0)
        for i in range(len(seg) - 1):
            out.append((float(u[i]), float(v[i]), bool(on[idx[i]])))
    return out


def _chr(v: int) -> str:
    """0..89 -> one printable character that survives a Monkey C string literal.

    Base 33 ('!'), stepping over 34 ('"') and 92 ('\\') — the only two codes in the range a
    literal cannot carry raw. The result lands in {33} u [35,91] u [93,125], all printable.
    """
    c = 33 + v
    if c >= 34:
        c += 1
    if c >= 92:
        c += 1
    return chr(c)


def _ord(ch: str) -> int:
    """`_chr` undone — the exact arithmetic AutoWindFixtures' reader performs on the watch."""
    c = ord(ch)
    if c > 92:
        c -= 1
    if c > 34:
        c -= 1
    return c - 33


def encode(rows: list[tuple[float, float, bool]]) -> str:
    parts = []
    for cog, v, fly in rows:
        parts.append(_chr(int(round(cog / 4.0)) % 90))
        parts.append(_chr(min(89, max(0, int(round(v / 0.2))))))
        parts.append("1" if fly else "0")
    return "".join(parts)


def decode(blob: str) -> list[tuple[float, float, bool]]:
    """The Monkey C side's decode, mirrored here so the round trip is checked before shipping."""
    out = []
    for i in range(0, len(blob), 3):
        out.append((_ord(blob[i]) * 4.0 + 2.0,
                    _ord(blob[i + 1]) * 0.2,
                    blob[i + 2] == "1"))
    return out


def replay(rows: list[tuple[float, float, bool]], dt: float) -> Replica:
    aw = Replica()
    for cog, v, fly in rows:
        aw.tick(dt, cog, v, fly)
    return aw


def engine_dir(stem: str) -> float:
    g = json.loads((REPO / "fixtures" / "goldens" / f"{stem}.expected.json").read_text())
    return float(g["wind"]["dirDeg"])


def chunks(blob: str) -> list[str]:
    step = CHUNK_SAMPLES * 3
    return [blob[i:i + step] for i in range(0, len(blob), step)]


def render(cases: list[dict]) -> str:
    lines = [
        "import Toybox.Lang;",
        "",
        "// GENERATED by lab/tools/make_autowind_arrays.py — do not edit by hand.",
        "//",
        "// Recorded 1 Hz (cog, speed, foil-state) streams from the two `ciq` fixtures, for the",
        "// auto-wind acceptance test in WingfoilTests.mc (docs/testing.md layer 3, and",
        "// docs/algorithms.md \"Watch approximation: auto wind\"). Every function here is",
        "// (:debug)-annotated, so none of these kilobytes reach a RELEASE build. It cannot be",
        "// (:test): the unit-test runner treats every annotated function as a test case, and",
        "// these take arguments and return data.",
        "//",
        "// Encoding, three printable ASCII characters per sample:",
        "//     char 0   course over ground   cell(round(cog / 4) % 90)       -> 4 deg cells",
        "//     char 1   Doppler speed        cell(min(89, round(v / 0.2)))   -> 0.2 m/s cells",
        "//     char 2   foil state           '1' while the flight detector is ON, else '0'",
        "//",
        "// cell(v) is 33 + v STEPPING OVER 34 and 92 — the codes for the quote and the",
        "// backslash, the only two a Monkey C string literal cannot carry raw. The reader in",
        "// WingfoilTests.mc undoes exactly that.",
        "//",
        f"// The stream is decimated by {DECIMATION} and replayed with dt = {DECIMATION}.0 s, which",
        "// keeps the distance weights and the 60 s evaluation cadence on the session's own",
        "// clock while fitting a two-hour session into a watch unit test.",
        "module AutoWindFixtures {",
        "",
        f"    // Samples are replayed with this dt.",
        f"    (:debug) function stepS() as Float {{ return {float(DECIMATION)}; }}",
        "",
        f"    (:debug) function count() as Number {{ return {len(cases)}; }}",
        "",
    ]
    for i, c in enumerate(cases):
        lines += [
            f"    // ---- {c['stem']} ----",
            f"    // {c['samples']} samples at {DECIMATION} s, {c['distance_m']:.0f} m of flying",
            f"    // distance. Engine (fixtures/goldens): wind from {c['engine']:.2f} deg.",
            f"    // Replica: locks at {c['lock_distance_m']:.0f} m on {c['first']:.2f} deg,",
            f"    // finishes on {c['final']:.2f} deg ({c['error']:+.2f} deg vs the engine),",
            f"    // {c['updates']} later update(s), largest adopted step {c['max_step']:.1f} deg.",
            f"    (:debug) function name{i}() as String {{ return \"{c['stem']}\"; }}",
            f"    (:debug) function engineDeg{i}() as Float {{ return {c['engine']:.2f}; }}",
            f"    (:debug) function chunks{i}() as Array<String> {{",
            "        return [",
        ]
        for ch in c["chunks"]:
            lines.append(f"            \"{ch}\",")
        lines += ["        ] as Array<String>;", "    }", ""]

    # One dispatch pair, so the test can loop over the fixtures.
    lines += [
        "    // Dispatch, so the test loops rather than repeating itself per fixture.",
        "    (:debug) function nameAt(i as Number) as String {",
    ]
    for i in range(len(cases)):
        lines.append(f"        if (i == {i}) {{ return name{i}(); }}")
    lines += [
        "        return \"\";",
        "    }",
        "",
        "    (:debug) function engineDegAt(i as Number) as Float {",
    ]
    for i in range(len(cases)):
        lines.append(f"        if (i == {i}) {{ return engineDeg{i}(); }}")
    lines += [
        "        return 0.0;",
        "    }",
        "",
        "    (:debug) function chunksAt(i as Number) as Array<String> {",
    ]
    for i in range(len(cases)):
        lines.append(f"        if (i == {i}) {{ return chunks{i}(); }}")
    lines += [
        "        return [] as Array<String>;",
        "    }",
        "}",
        "",
    ]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true",
                    help="regenerate in memory and fail if the file on disk differs")
    args = ap.parse_args(argv)

    cases = []
    for stem in FIXTURES:
        fit = REPO / "fixtures" / "sessions" / "ciq" / f"{stem}.fit"
        rows = stream(fit)[::DECIMATION]
        blob = encode(rows)
        back = decode(blob)
        aw = replay(back, float(DECIMATION))
        eng = engine_dir(stem)
        err = _wrap180(aw.dir_deg - eng)
        cases.append({
            "stem": stem, "chunks": chunks(blob), "samples": len(rows),
            "engine": eng, "final": aw.dir_deg, "error": err, "updates": aw.updates,
            "distance_m": aw.distance_m, "lock_distance_m": aw.lock_distance_m,
            "max_step": aw.max_step_deg,
            "first": aw.dir_deg if aw.updates == 0 else aw.dir_deg,
        })
        print(f"{stem}: {len(rows)} samples, {aw.distance_m:.0f} m flown, "
              f"locked at {aw.lock_distance_m:.0f} m, final {aw.dir_deg:.2f} deg vs engine "
              f"{eng:.2f} ({err:+.2f}), {aw.updates} update(s), "
              f"largest adopted step {aw.max_step_deg:.1f} deg")
        if aw.locks == 0:
            print(f"  !! {stem} never locked", file=sys.stderr)
            return 1
        if abs(err) > 20.0:
            print(f"  !! {stem} is {err:+.2f} deg from the engine, band is +-20",
                  file=sys.stderr)
            return 1
        if aw.max_step_deg > 90.0:
            print(f"  !! {stem} flipped after locking ({aw.max_step_deg:.1f} deg)",
                  file=sys.stderr)
            return 1

    text = render(cases)
    if args.check:
        current = OUT.read_text() if OUT.exists() else ""
        if current != text:
            print(f"{OUT} is stale — re-run without --check", file=sys.stderr)
            return 1
        print(f"{OUT} is up to date")
        return 0
    OUT.write_text(text)
    print(f"wrote {OUT} ({len(text)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
