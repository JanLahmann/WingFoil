#!/usr/bin/env python
"""Regenerate golden files for the whole fixture corpus.

Runs parse -> clean -> flights -> records over every FIT **and GPX** under
fixtures/sessions/** and fixtures/synthetic/, writes fixtures/goldens/<stem>.expected.json,
and prints a summary table. Since engine 0.9.0 the corpus holds both formats; `analyze`
dispatches on the file itself (`parse.parse_track`), so nothing here needs to know which
is which beyond the glob — and the `cls` column in the table is where the difference shows.

Usage: cd lab && uv run python tools/make_goldens.py [--fixtures DIR] [--out DIR] [--dry-run]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from wingfoil_lab.goldens import analyze, build_golden, golden_path, write_golden

REPO = Path(__file__).resolve().parents[2]

#: What counts as a session recording. Extensions only — `analyze` confirms by
#: content, so a mislabelled file is still read for what it is.
TRACK_SUFFIXES = {".fit", ".gpx"}

HEADER = (f"{'file':<52} {'cls':>3} {'hz':>4} {'foil%':>6} {'fl':>4} {'long_s':>7} "
          f"{'2s':>6} {'10s':>6} {'5x10s':>6} {'500m':>6} {'alpha':>6} {'km':>7} "
          f"{'hr_cost':>8} {'hr_n':>7}")


def _hr_cells(hr: dict) -> tuple[str, str]:
    """avg takeoff cost and its `valid/total`, or dashes when the source carries no HR."""
    if not hr["hasHR"]:
        return "-", "-"
    s = hr["summary"]
    cost = "-" if s["avgTakeoffCostBpm"] is None else f"{s['avgTakeoffCostBpm']:.1f}"
    return cost, f"{s['takeoffCostValid']}/{s['takeoffCostTotal']}"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--fixtures", type=Path, default=REPO / "fixtures",
                    help="fixtures root (default: <repo>/fixtures)")
    ap.add_argument("--out", type=Path, default=None,
                    help="goldens output dir (default: <fixtures>/goldens)")
    ap.add_argument("--dry-run", action="store_true", help="analyze and print, write nothing")
    args = ap.parse_args(argv)
    out_dir = args.out or args.fixtures / "goldens"

    fits = sorted(p for p in (args.fixtures / "sessions").rglob("*")
                  if p.suffix.lower() in TRACK_SUFFIXES)
    fits += sorted(p for p in (args.fixtures / "synthetic").glob("*")
                   if p.suffix.lower() in TRACK_SUFFIXES)
    if not fits:
        print(f"no fixtures under {args.fixtures}", file=sys.stderr)
        return 1

    print(HEADER)
    print("-" * len(HEADER))
    written = 0
    for fit in fits:
        a = analyze(fit)
        g = build_golden(a)
        if not args.dry_run:
            write_golden(g, golden_path(fit, out_dir))
            written += 1
        s, r = g["summary"], g["records"]
        hr_cost, hr_n = _hr_cells(g["hr"])
        print(f"{fit.stem:<52} {a.track.capabilities.source_class:>3} "
              f"{g['capabilities']['sampleRateHz']:>4.1f} {s['foilPct']:>6.1f} "
              f"{s['flightCount']:>4d} {s['longestFlightS']:>7.1f} "
              f"{r['best2sKn']:>6.2f} {r['best10sKn']:>6.2f} {r['best5x10sKn']:>6.2f} "
              f"{r['best500mKn']:>6.2f} {r['alpha500Kn']:>6.2f} {s['distanceKm']:>7.2f} "
              f"{hr_cost:>8} {hr_n:>7}")
    print("-" * len(HEADER))
    print(f"{written} goldens written to {out_dir}" if not args.dry_run
          else f"dry run: {len(fits)} fixtures analyzed, nothing written")
    return 0


if __name__ == "__main__":
    sys.exit(main())
