#!/usr/bin/env python
"""HR-cost report for one or more session FITs (docs/algorithms.md "HR cost").

Prints the per-session summary (takeoff HR cost, pumping vs cruising, bpm per stroke,
recovery) and the fatigue curve, with coverage beside every aggregate.

Usage:
    cd lab && uv run python tools/hr_report.py [FIT ...] [--bins N | --bin-minutes M]
                                               [--events]
With no FIT given it reports the three reference sessions.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from wingfoil_lab.goldens import analyze
from wingfoil_lab.hrcost import HrConfig, analyze_hr, fatigue_curve

REPO = Path(__file__).resolve().parents[2]
REFERENCE = [
    "sessions/ciq/2026-08-07-0754_nago-torbole-windsurfen_ciq.fit",
    "sessions/windsurf-native/2026-08-05-0827_nago-torbole-windsurfen_native.fit",
    "sessions/windsurf-native/2026-08-04-1411_nago-torbole-windsurfen_native.fit",
]


def _f(v, places=1, unit="") -> str:
    return "-" if v is None else f"{v:.{places}f}{unit}"


def report(path: Path, cfg: HrConfig, bins: int | None, bin_minutes: float | None,
           events: bool) -> None:
    a = analyze(path)
    h = analyze_hr(a.track, a.flights, a.takeoffs, a.flight_ends, a.pump, a.turns,
                   config=cfg)
    print(f"\n=== {path.name}  (class {a.track.capabilities.source_class}, "
          f"{a.flights.flight_count} flights)")
    if not h.has_hr:
        print("  no HR channel")
        return
    s, pc = h.summary, h.summary.pump_cruise
    print(f"  usable HR                {_f(s.usable_pct, 1, ' % of session span')}")
    print(f"  takeoff HR cost          avg {_f(s.avg_takeoff_cost_bpm)} bpm, "
          f"median {_f(s.median_takeoff_cost_bpm)} bpm   [{s.takeoff_cost_coverage}]"
          f"{f', {s.approximate_takeoffs} approximate' if s.approximate_takeoffs else ''}")
    print(f"  peak lag (median)        {_f(s.median_peak_lag_s)} s")
    print(f"  pumping vs cruising      {_f(pc.pumping_bpm)} vs {_f(pc.cruising_bpm)} bpm "
          f"= {_f(pc.delta_bpm, 1, ' bpm')}   [{pc.pumping_spans} burst spans "
          f"{_f(pc.pumping_covered_s, 0, ' s')} cov {_f(pc.pumping_coverage, 2)} | "
          f"{pc.cruising_spans} cruise spans {_f(pc.cruising_covered_s, 0, ' s')} "
          f"cov {_f(pc.cruising_coverage, 2)}]")
    print(f"  bpm per stroke           pooled {_f(s.bpm_per_stroke, 2)}, "
          f"median {_f(s.median_bpm_per_stroke, 2)}   [{s.bpm_per_stroke_coverage}]")
    print(f"  recovery (half decay)    takeoff {_f(s.median_takeoff_recovery_s, 0, ' s')} "
          f"[{s.takeoff_recovery_coverage}] | swim "
          f"{_f(s.median_swim_recovery_s, 0, ' s')} [{s.swim_recovery_coverage}]")
    print(f"  swim HR cost             avg {_f(s.avg_swim_cost_bpm)} bpm "
          f"[{s.swim_cost_coverage}]")

    rows = fatigue_curve(h.hr, a.takeoffs, h.takeoff_events, cfg,
                         bin_minutes=bin_minutes, n_bins=bins) if (bins or bin_minutes) \
        else h.bins
    print(f"  {'bin (min)':>13} {'att':>4} {'ok':>3} {'fail':>5} {'succ%':>6} "
          f"{'cost':>6} {'base':>6} {'meanHR':>7} {'pumps':>6}  cov")
    for b in rows:
        print(f"  {b.start_t / 60:6.1f}-{b.end_t / 60:6.1f} {b.attempts:4d} "
              f"{b.successes:3d} {b.failed:5d} {_f(b.success_pct, 0):>6} "
              f"{_f(b.avg_cost_bpm):>6} {_f(b.avg_baseline_bpm, 0):>6} "
              f"{_f(b.mean_bpm, 0):>7} {_f(b.avg_pumps):>6}  {b.cost_coverage}")

    if events:
        print("   idx     t(min)  base  peak   cost  lag  strokes  recov  approx")
        for e in h.takeoff_events:
            cost = "-" if e.cost_bpm is None else f"{e.cost_bpm:+.0f}"
            print(f"  {e.index:4d} {e.t / 60:9.2f} {_f(e.baseline_bpm, 0):>5} "
                  f"{_f(e.peak_bpm, 0):>5} {cost:>6} "
                  f"{_f(e.peak_lag_s, 0):>4} {str(e.strokes):>8} "
                  f"{_f(e.recovery_half_s, 0):>6}  {e.approximate}")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("fits", nargs="*", type=Path)
    ap.add_argument("--bins", type=int, default=None, help="equal bins (e.g. 3 for thirds)")
    ap.add_argument("--bin-minutes", type=float, default=None)
    ap.add_argument("--events", action="store_true", help="also print every takeoff event")
    args = ap.parse_args(argv)

    fits = args.fits or [REPO / "fixtures" / p for p in REFERENCE]
    cfg = HrConfig()
    for fit in fits:
        report(Path(fit), cfg, args.bins, args.bin_minutes, args.events)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
