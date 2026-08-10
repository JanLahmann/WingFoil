#!/usr/bin/env python3
"""Headless checks for `web/lab_bundle/web_entry.py` — the only Python the web app adds.

Two things can break without a browser noticing:

1. **Golden drift.** `web_entry.analyze_bytes` must reproduce
   `fixtures/goldens/<stem>.expected.json` byte-for-byte for the same FIT. This is the
   spot-check that used to live as a heredoc in `web/README.md`.
2. **A track with no GPS fixes.** `analyze_json` serializes with `allow_nan=False`, so a
   single NaN anywhere in the document fails the *whole* analysis. A Doppler-only track
   has an all-NaN projection, and the map bounds/markers are where that used to leak out.
   The view must degrade to `hasPositions: false` and stay serializable.

Run it from the repo root (or anywhere — paths are resolved from this file):

    lab/.venv/bin/python web/tools/verify_web_entry.py
    uv run --project lab python web/tools/verify_web_entry.py

Exit 0 = both checks pass; exit 1 = the message says which one did not.
"""

from __future__ import annotations

import json
import sys
import types
from pathlib import Path

WEB = Path(__file__).resolve().parents[1]
REPO = WEB.parent
sys.path.insert(0, str(WEB / "lab_bundle"))

import numpy as np                                          # noqa: E402

import web_entry                                            # noqa: E402
from wingfoil_lab.filters import clean_from_arrays          # noqa: E402
from wingfoil_lab.flight import segment_flights             # noqa: E402
from wingfoil_lab.flightend import classify_flight_ends     # noqa: E402
from wingfoil_lab.turns import detect_turns                 # noqa: E402

CIQ = "2026-08-07-0754_nago-torbole-windsurfen_ciq"


def check_golden() -> str:
    """`analyze_bytes` on the reference CIQ session == its golden, exactly."""
    fit = REPO / "fixtures" / "sessions" / "ciq" / f"{CIQ}.fit"
    golden = REPO / "fixtures" / "goldens" / f"{CIQ}.expected.json"
    if not fit.exists() or not golden.exists():
        return "SKIP golden spot-check (fixture missing)"
    result = web_entry.analyze_bytes(fit.read_bytes(), fit.name)
    expected = json.loads(golden.read_text())
    if result["golden"] != expected:
        raise SystemExit("FAIL: web_entry drifted from the golden")
    json.dumps(result, allow_nan=False)          # the shape the worker actually posts
    s = result["golden"]["summary"]
    return (f"OK  golden spot-check: {s['turns']['turnsCounted']} turns, "
            f"{s['flightCount']} flights, {s['distanceKm']} km")


def check_position_less_track() -> str:
    """A speed-only track still analyses: no map, but a JSON-serializable view."""
    n = 140
    t = np.arange(n, dtype=float)
    speed = np.concatenate([np.full(20, 1.0), np.full(60, 7.0),
                            np.full(20, 0.4), np.full(40, 7.0)])
    nan = np.full(n, np.nan)                     # no lat/lon -> all-NaN projection
    clean = clean_from_arrays(t, speed, x=nan, y=nan)
    flights = segment_flights(clean)
    turns = detect_turns(clean, flights)
    ends = classify_flight_ends(clean, flights, turns)
    a = types.SimpleNamespace(clean=clean, flights=flights, turns=turns, flight_ends=ends)

    view = web_entry._view(a)
    if view["hasPositions"] is not False:
        raise SystemExit("FAIL: a position-less track must report hasPositions false")
    if view["x"] or view["y"]:
        raise SystemExit("FAIL: a position-less track must not carry x/y arrays")
    b = view["bounds"]
    if not (b["x0"] is None and b["x1"] is None and b["y0"] is None and b["y1"] is None):
        raise SystemExit("FAIL: map bounds must be null without positions")
    if b["knMax"] <= 0 or view["count"] != n:
        raise SystemExit("FAIL: the speed strip lost its data")
    for m in view["turnMarkers"] + view["endMarkers"]:
        if m["x"] is not None or m["y"] is not None:
            raise SystemExit("FAIL: markers must carry no coordinates without positions")
    json.dumps(view, allow_nan=False)            # the failure this check exists for
    return (f"OK  position-less track: {flights.flight_count} flights, "
            f"{len(ends)} flight ends, view serializes")


def main() -> int:
    for check in (check_golden, check_position_less_track):
        print(check())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
