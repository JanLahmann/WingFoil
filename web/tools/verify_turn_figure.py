#!/usr/bin/env python3
"""**The turn drawing's geometry, held to the phone's** — the web's half of the contract.

The turn page and the flight-end page draw one maneuver at its own scale, and everything
about that picture that can be *wrong* is arithmetic: the projection into local metres, the
bearing written onto each vertex, the wind-up rotation, the padded frame, the scale bar, the
three speed marks, and where the ramp puts a knot reading. The kit holds those rules in
`TurnSliceTests`; this holds the browser's port of them
(`web/js/maneuverfigure.js`), so a rule that drifts on one surface fails on both.

    python3 web/tools/verify_turn_figure.py

How it works, and why this shape. `web/tools/turn_figure.mjs` runs the module the tab
actually imports over a synthetic session — a quarter circle at 20 m radius, 1 Hz, inside a
straight lead-in and run-out — and prints what it computed. Everything below re-derives the
same numbers from the Swift, written out differently on purpose: two spellings of one rule
agreeing is evidence, one spelling agreeing with itself is not. The sources:

    ios/WingFoilKit/Sources/WingFoilKit/Presentation/TurnSlice.swift
    ios/WingFoilKit/Sources/WingFoilKit/Presentation/FlightEndSlice.swift
    ios/WingFoilKit/Sources/WingFoilKit/Presentation/TurnSpeedRamp.swift
    ios/WingFoilKit/Sources/WingFoilKit/Presentation/SliceAngles.swift

The session is synthetic because it has to be: an analysis golden carries the turn records
but not the positional view the browser draws from (`web_entry._view` builds that at analysis
time and it is never written to `fixtures/`), so there is no reachable JSON of one real
turn's drawn extents to compare against. What a real turn would add is sample spacing; what
it cannot add is a known right answer for a projection.

Needs `node`, and skips with a note rather than failing when there is none — the same rule
`verify_presentation.py` applies to its own node harnesses.

Exit 0 = everything matched; exit 1 = the mismatches are listed.
"""

from __future__ import annotations

import json
import math
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
HARNESS = REPO / "web" / "tools" / "turn_figure.mjs"
TOKENS = REPO / "design" / "tokens.json"

# The synthetic ride, spelled out again here. Keep it in step with `turn_figure.mjs`: the
# two halves describe one session and a divergence in the *input* would make the whole run
# meaningless rather than red.
RADIUS_M = 20.0
ORIGIN = (1000.0, -500.0)
SWEEP_FROM = 16
SWEEP_TO = 24
WIND_FROM_DEG = 300.0

ENTRY_SPEED_WINDOW_S = 3.0
MIN_SPEED_LAG_S = 2.0
OUTCOME_LOOKAHEAD_S = 12.0
RECOVER_PCT = 80.0
FOIL_ENTRY_SPEED_KMH = 12.0
KMH_TO_KN = 1 / 1.852

# The kit's constants (`TurnSlice`).
MIN_STEP_M = 0.5
PAD_FRACTION = 0.14
MIN_SPAN_M = 20.0
DEFAULT_PAD_S = 8.0


def ride() -> list[dict]:
    """One sample per second, in the engine's own east/north metres."""
    out = []
    for i in range(41):
        if i < SWEEP_FROM:
            x = ORIGIN[0]
            y = ORIGIN[1] + (i - SWEEP_FROM) * 5
        elif i <= SWEEP_TO:
            a = (i - SWEEP_FROM) / (SWEEP_TO - SWEEP_FROM) * (math.pi / 2)
            x = ORIGIN[0] + RADIUS_M * (1 - math.cos(a))
            y = ORIGIN[1] + RADIUS_M * math.sin(a)
        else:
            x = ORIGIN[0] + RADIUS_M + (i - SWEEP_TO) * 5
            y = ORIGIN[1] + RADIUS_M
        sag = (5 * math.sin((i - SWEEP_FROM) / (SWEEP_TO - SWEEP_FROM) * math.pi)
               if SWEEP_FROM <= i <= SWEEP_TO else 0.0)
        # The view rounds every channel before it reaches the browser, so the Python has to
        # round too, or the two would disagree in the fourth decimal of a speed mark.
        out.append({"t": float(i), "x": round(x, 1), "y": round(y, 1),
                    "kn": round(12 - sag, 2)})
    return out


TURN = {"ts": float(SWEEP_FROM), "endTs": float(SWEEP_TO), "minTs": 20.0,
        "entryKn": 12.0, "minKn": 7.0, "exitKn": 12.0, "axisTs": 20.0}
END = {"ts": 20.0, "minKn": 1.5}


# ------------------------------------------------------------------ the rules again


def normalize(deg: float) -> float:
    wrapped = math.fmod(deg, 360.0)
    return wrapped + 360.0 if wrapped < 0 else wrapped


def delta(from_deg: float, to_deg: float) -> float:
    d = math.fmod(to_deg - from_deg, 360.0)
    if d > 180:
        d -= 360
    if d < -180:
        d += 360
    return d


def project(samples: list[dict], anchor: dict, zero_t: float, in_event) -> list[dict]:
    points = [{"x": s["x"] - anchor["x"], "y": s["y"] - anchor["y"],
               "rt": s["t"] - zero_t, "kn": s["kn"], "heading": None,
               "inTurn": in_event(s["t"])} for s in samples]
    apply_headings(points)
    return points


def apply_headings(points: list[dict]) -> None:
    if len(points) < 2:
        return
    for i in range(len(points) - 1):
        dx = points[i + 1]["x"] - points[i]["x"]
        dy = points[i + 1]["y"] - points[i]["y"]
        if math.hypot(dx, dy) < MIN_STEP_M:
            continue
        points[i]["heading"] = normalize(math.degrees(math.atan2(dx, dy)))
    points[-1]["heading"] = points[-2]["heading"]


def rotated(points: list[dict], wind_from: float) -> list[dict]:
    rad = math.radians(wind_from)
    s, c = math.sin(rad), math.cos(rad)
    out = []
    for p in points:
        out.append({**p,
                    "x": p["x"] * c - p["y"] * s,
                    "y": p["x"] * s + p["y"] * c,
                    "heading": None if p["heading"] is None
                    else normalize(p["heading"] - wind_from)})
    return out


def padded_bounds(points: list[dict]) -> dict | None:
    if not points:
        return None
    xs = [p["x"] for p in points]
    ys = [p["y"] for p in points]
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    pad = max(w, h, MIN_SPAN_M) * PAD_FRACTION
    return {"minX": min(xs) - pad, "minY": min(ys) - pad,
            "maxX": max(xs) + pad, "maxY": max(ys) + pad}


def scale_bar_m(span: float) -> float:
    for candidate in (50.0, 25.0, 10.0):
        if candidate <= span * 0.45:
            return candidate
    return 10.0


def ramp_position(kn: float, entry_kn: float) -> float:
    if entry_kn < 0.5 or kn <= 0:
        return 0.0
    if kn <= entry_kn:
        cold = entry_kn * 0.5
        return 0.5 * min(max((kn - cold) / (entry_kn - cold), 0.0), 1.0)
    over = (kn - entry_kn) / (entry_kn * 0.3)
    return 0.5 + 0.5 * min(over, 1.0)


def ramp_stop(position: float, stops: int = 5) -> tuple[int, int, float]:
    scaled = min(max(position, 0.0), 1.0) * (stops - 1)
    lower = min(int(math.floor(scaled)), stops - 2)
    return lower, lower + 1, scaled - lower


def ramp_rgb() -> list[tuple[float, float, float]]:
    """The five stops, read from design/tokens.json — the same file the generator writes
    `DesignTokens.Speed.rampRGB` and `js/tokens.js` out of."""
    speed = json.loads(TOKENS.read_text())["colors"]["speed"]
    out = []
    for name in ("stopped", "slow", "entry", "fast", "fastest"):
        hexval = speed[name]["hex"].lstrip("#")
        out.append(tuple(int(hexval[i:i + 2], 16) / 255 for i in (0, 2, 4)))
    return out


def ramp_color(position: float) -> str:
    lower, upper, blend = ramp_stop(position)
    ramp = ramp_rgb()
    parts = [round((ramp[lower][i] + (ramp[upper][i] - ramp[lower][i]) * blend) * 255)
             for i in range(3)]
    return f"rgb({parts[0]}, {parts[1]}, {parts[2]})"


def turn_marks(window: list[dict]) -> dict:
    duration = max(TURN["endTs"] - TURN["ts"], 0.0)
    min_rt = min(max(TURN["minTs"] - TURN["ts"], 0.0), duration + MIN_SPEED_LAG_S)
    entry_window = [s for s in window
                    if TURN["ts"] - ENTRY_SPEED_WINDOW_S <= s["t"] <= TURN["ts"]]
    entry_at = None
    best = math.inf
    for s in entry_window:                       # first minimal wins, as Swift's min(by:)
        score = abs(s["kn"] - TURN["entryKn"])
        if score < best:
            best, entry_at = score, s
    threshold = RECOVER_PCT / 100 * TURN["entryKn"]
    recover_at = next((s for s in window
                       if s["t"] > TURN["endTs"] and s["kn"] >= threshold), None)
    return {"entryKn": TURN["entryKn"],
            "entryRt": (entry_at["t"] - TURN["ts"]) if entry_at else 0.0,
            "minKn": TURN["minKn"], "minRt": min_rt,
            "exitKn": TURN["exitKn"], "exitRt": duration,
            "recoverRt": (recover_at["t"] - TURN["ts"]) if recover_at else None}


def end_marks(window: list[dict]) -> dict:
    entry_window = [s for s in window
                    if END["ts"] - ENTRY_SPEED_WINDOW_S <= s["t"] <= END["ts"]]
    entry_at = None
    best = -math.inf
    for s in entry_window:                       # last maximal wins, as Swift's max(by:)
        if s["kn"] >= best:
            best, entry_at = s["kn"], s
    entry_kn = entry_at["kn"] if entry_at else 0.0
    after = [s for s in window if s["t"] >= END["ts"]]
    low_at = None
    best = math.inf
    for s in after:
        score = abs(s["kn"] - END["minKn"])
        if score < best:
            best, low_at = score, s
    threshold = max(RECOVER_PCT / 100 * entry_kn, FOIL_ENTRY_SPEED_KMH * KMH_TO_KN)
    recover_at = next((s for s in window
                       if s["t"] > END["ts"] and s["kn"] >= threshold), None)
    return {"entryKn": entry_kn,
            "entryRt": (entry_at["t"] - END["ts"]) if entry_at else 0.0,
            "lowKn": END["minKn"], "lowRt": (low_at["t"] - END["ts"]) if low_at else None,
            "outKn": recover_at["kn"] if recover_at else None,
            "recoverRt": (recover_at["t"] - END["ts"]) if recover_at else None}


def mid_rotation(points: list[dict]) -> float | None:
    arc = [p for p in points if p["inTurn"] and p["heading"] is not None]
    if len(arc) < 3:
        return None
    total = 0.0
    steps = []
    for i in range(1, len(arc)):
        total += abs(delta(arc[i - 1]["heading"], arc[i]["heading"]))
        steps.append((arc[i]["rt"], total))
    if total <= 0:
        return None
    for rt, swept in steps:
        if swept >= total / 2:
            return rt
    return steps[-1][0]


def slice_angles(points: list[dict], wind_from: float | None) -> dict:
    raw = [(p["rt"], delta(wind_from, p["heading"]) if wind_from is not None
            else p["heading"])
           for p in points if p["heading"] is not None]
    if len(raw) < 2:
        return {"points": [(rt, deg, None) for rt, deg in raw], "peak": 0.0}
    unwrapped = [raw[0][1]]
    for i in range(1, len(raw)):
        unwrapped.append(unwrapped[i - 1] + delta(raw[i - 1][1], raw[i][1]))
    peak = 0.0
    out = []
    for i, (rt, _) in enumerate(raw):
        rate = None
        if i + 1 < len(raw):
            dt = raw[i + 1][0] - raw[i][0]
            if dt > 0.001:
                rate = (unwrapped[i + 1] - unwrapped[i]) / dt
                if abs(rate) > abs(peak):
                    peak = rate
        out.append((rt, unwrapped[i], rate))
    return {"points": out, "peak": peak}


def path_labels(points: list[dict], every: float = 5.0) -> list[float]:
    first, last = points[0]["rt"], points[-1]["rt"]
    if last <= first:
        return []
    out = []
    rt = math.ceil(first / every) * every
    while rt <= last:
        if abs(rt) > 0.001:
            at = min(points, key=lambda p: abs(p["rt"] - rt))
            if abs(at["rt"] - rt) <= every / 2:
                out.append(float(rt))
        rt += every
    return out


# ------------------------------------------------------------------ the comparison


def r(value, places: int = 6):
    if value is None or (isinstance(value, float) and not math.isfinite(value)):
        return None
    return round(float(value), places)


def expected() -> dict:
    samples = ride()
    window = [s for s in samples
              if TURN["ts"] - DEFAULT_PAD_S <= s["t"] <= TURN["endTs"] + DEFAULT_PAD_S]
    anchor = min(window, key=lambda s: abs(s["t"] - TURN["ts"]))
    points = project(window, anchor, TURN["ts"],
                     lambda t: TURN["ts"] <= t <= TURN["endTs"])
    up = rotated(points, WIND_FROM_DEG)
    marks = turn_marks(window)
    duration = max(TURN["endTs"] - TURN["ts"], 0.0)
    domain = [-DEFAULT_PAD_S, max(duration + DEFAULT_PAD_S, -DEFAULT_PAD_S + 1)]
    entry_at = next(p for p in points if p["rt"] == 0)

    end_window = [s for s in samples
                  if END["ts"] - DEFAULT_PAD_S <= s["t"] <= END["ts"] + DEFAULT_PAD_S]
    end_anchor = min(end_window, key=lambda s: abs(s["t"] - END["ts"]))
    end_points = project(end_window, end_anchor, END["ts"], lambda t: t <= END["ts"])
    end_speed = end_marks(end_window)

    angles = slice_angles(points, WIND_FROM_DEG)
    degs = [p[1] for p in angles["points"]]
    lo, hi = min(degs), max(degs)
    pad = max((hi - lo) * 0.12, (30.0 - (hi - lo)) / 2, 2.0)

    return {
        "turn": {
            "count": len(points),
            "firstRt": r(points[0]["rt"]),
            "lastRt": r(points[-1]["rt"]),
            "entryXY": [r(entry_at["x"]), r(entry_at["y"])],
            "inTurnCount": sum(1 for p in points if p["inTurn"]),
            "headings": [r(p["heading"], 4) for p in points],
            "windUpHeadings": [r(p["heading"], 4) for p in up],
            "windUpXY": [[r(p["x"], 4), r(p["y"], 4)] for p in up],
            "bounds": {k: r(v) for k, v in padded_bounds(points).items()},
            "windUpBounds": {k: r(v) for k, v in padded_bounds(up).items()},
            "axisRt": r(TURN["axisTs"] - TURN["ts"]),
            "timeDomain": [r(v) for v in domain],
            "durationS": r(duration),
            "title": "Jibe",
            "speed": {k: r(v) for k, v in marks.items()},
            "midRotationRt": r(mid_rotation(points)),
            "lowRt": r(marks["minRt"]),
            "endRt": r(marks["exitRt"]),
            "pathLabels": [r(v) for v in path_labels(points)],
            "nearest": 0.0,
            "nearestMiss": True,
        },
        "end": {
            "count": len(end_points),
            "endRt": 0.0,
            "axisRt": None,
            "durationS": 0.0,
            "title": "Flight end",
            "inTurnCount": sum(1 for p in end_points if p["inTurn"]),
            "speed": {k: r(v) for k, v in end_speed.items()},
        },
        "ramp": {
            "positions": [r(ramp_position(kn, 12.0))
                          for kn in (0, 3, 6, 9, 12, 13, 15.6, 20)],
            "lowEntry": r(ramp_position(9, 0.2)),
            "stops": [[s[0], s[1], r(s[2])]
                      for s in (ramp_stop(p) for p in (0, 0.125, 0.25, 0.5, 0.75, 1))],
            "colors": [ramp_color(p) for p in (0, 0.25, 0.5, 0.75, 1)],
            "legendBottomKn": 6.0,
            # The top of the legend's bar: the entry speed, or the turn's own maximum where
            # it went faster than that, never past the ramp's cap.
            "legendTopKn": [r(max(12.0, min(kn, 12.0 * 1.3))) for kn in (11.0, 14.0, 40.0)],
        },
        "scaleBar": [scale_bar_m(s) for s in (10, 20, 30, 56, 60, 111, 200)],
        "angles": {
            "isTwa": True,
            "first": r(degs[0], 4),
            "last": r(degs[-1], 4),
            "peakRateDegS": r(angles["peak"], 4),
            "domain": [r(lo - pad, 4), r(hi + pad, 4)],
            "headingOnly": r(slice_angles(points, None)["points"][0][1], 4),
        },
        "foil": [[-8.0, 4.0, True], [4.0, 10.0, False], [10.0, 16.0, True]],
        "helpers": {
            "normalize": [r(normalize(d), 4) for d in (-10, 0, 359.5, 360, 720.5)],
            "delta": [r(delta(a, b), 4)
                      for a, b in ((350, 10), (10, 350), (0, 180), (0, 181), (90, 270))],
        },
    }


def compare(path: str, want, got, failures: list[str]) -> None:
    if isinstance(want, dict):
        if not isinstance(got, dict):
            failures.append(f"{path}: expected an object, got {got!r}")
            return
        for key in want:
            if key not in got:
                failures.append(f"{path}.{key}: missing")
                continue
            compare(f"{path}.{key}", want[key], got[key], failures)
        return
    if isinstance(want, list):
        if not isinstance(got, list) or len(want) != len(got):
            failures.append(f"{path}: expected {len(want)} entries, got {got!r}")
            return
        for i, item in enumerate(want):
            compare(f"{path}[{i}]", item, got[i], failures)
        return
    if isinstance(want, bool) or isinstance(got, bool):
        if bool(want) != bool(got):
            failures.append(f"{path}: expected {want!r}, got {got!r}")
        return
    if want is None or got is None:
        if want is not got:
            failures.append(f"{path}: expected {want!r}, got {got!r}")
        return
    if isinstance(want, (int, float)) and isinstance(got, (int, float)):
        if abs(float(want) - float(got)) > 1e-6:
            failures.append(f"{path}: expected {want!r}, got {got!r}")
        return
    if want != got:
        failures.append(f"{path}: expected {want!r}, got {got!r}")


def main() -> int:
    node = shutil.which("node")
    if not node:
        print("SKIP  turn figure — no node on this machine")
        return 0
    proc = subprocess.run([node, str(HARNESS)], capture_output=True, text=True,
                          cwd=REPO, check=False)
    if proc.returncode != 0:
        print("FAIL  turn figure — the harness did not run")
        print(proc.stderr.strip()[:2000])
        return 1
    got = json.loads(proc.stdout)
    failures: list[str] = []
    compare("figure", expected(), got, failures)
    if failures:
        print(f"FAIL  turn figure — {len(failures)} mismatches")
        for line in failures[:40]:
            print("  " + line)
        if len(failures) > 40:
            print(f"  … and {len(failures) - 40} more")
        return 1
    print("PASS  turn figure — projection, headings, wind-up rotation, frame, marks, "
          "ramp, scale bar, angles and foil spans")
    return 0


if __name__ == "__main__":
    sys.exit(main())
