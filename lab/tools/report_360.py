#!/usr/bin/env python
"""Run the **experimental** 360 detector over the whole fixture corpus and print what it finds.

    cd lab && uv run python tools/report_360.py          # every session in fixtures/sessions
    cd lab && uv run python tools/report_360.py --quiet  # one line per session, no candidates

The detector is dark in the engine (`detectThreeSixty`, docs/algorithms.md "360 spins"); this
tool is the only thing that turns it on, and it exists to answer one question honestly: on
real water, is a candidate a spin the rider rode, or one of the shapes that merely look like
one? So every candidate is printed with the evidence needed to tell them apart --

* **when** it happened, in the rider's local clock and as an offset into the session, so it
  can be found on a map or in a video;
* **net deg / dur** -- the rotation itself;
* **entry / min km/h** (Doppler) -- the two speed gates. A spin entered barely over
  `foilEntrySpeed` and collapsing towards `threeSixtyMinKmh` is the stopped-and-drifting
  false positive; one held near foiling speed all the way round is a real carve;
* **arcM / radM** -- the same carve geometry the turn detector reads, and **outcome** --
  a spin that ends in `fell_in` with a long stop was not a spin the rider rode away from;
* **overlaps** -- the counted maneuver, if any, the sweep sits on top of. A 360 that overlaps
  a tack *and* a jibe is very likely those two maneuvers rather than a spin.

Nothing here writes a file or a golden. The pass is additive and off by default precisely
because none of it is calibrated: there is no ground-truthed 360 anywhere in the corpus.
"""

from __future__ import annotations

import argparse
import sys
from datetime import timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from wingfoil_lab.filters import clean                                   # noqa: E402
from wingfoil_lab.flight import segment_flights                          # noqa: E402
from wingfoil_lab.parse import parse_track                               # noqa: E402
from wingfoil_lab.turns import (THREE_SIXTY, Turn, TurnConfig,           # noqa: E402
                                detect_turns)
from wingfoil_lab.wind import estimate_wind                              # noqa: E402

FIXTURES = ROOT.parent / "fixtures" / "sessions"
TRACK_SUFFIXES = {".fit", ".gpx"}
MPS_TO_KMH = 3.6
KN_TO_KMH = 1.0 / 1.9438445 * 3.6

HEADER = (f"{'local':>8} {'t+':>8} {'netDeg':>8} {'durS':>6} {'entry':>7} {'min':>7} "
          f"{'arcM':>7} {'radM':>6} {'outcome':>12}  overlaps")


def _clock(track, t: float) -> str:
    """The rider's own wall clock at session time `t`, or `--:--:--` when nothing can say.

    `start_utc_offset_s` may be a solar guess from longitude (parse.py's ladder); this is a
    lab report, so the guess is printed rather than withheld -- it is still the right minute
    for finding the moment in a video.
    """
    ts = track.records["timestamp"]
    if ts.empty or track.start_utc_offset_s is None:
        return "--:--:--"
    local = ts.iloc[0].to_pydatetime() + timedelta(seconds=track.start_utc_offset_s + t)
    return local.strftime("%H:%M:%S")


def _offset(t: float, t0: float) -> str:
    """Session time as mm:ss from the first cleaned sample."""
    d = max(t - t0, 0.0)
    return f"{int(d) // 60:d}:{int(d) % 60:02d}"


def _sweep_min_kmh(ct, spin: Turn) -> float:
    """The lowest Doppler **inside the sweep** -- the number `threeSixtyMinKmh` gates on.

    Not `Turn.min_kn_doppler`, which is measured to `turnEnd + minSpeedLag`: that tail is the
    right window for scoring a maneuver and the wrong one for reading a gate, and the two
    differ by a knot or so exactly where it matters, at the bottom of a collapsing spin.
    """
    r = ct.records
    v = r["doppler_mps"][(r["t"] >= spin.start_t) & (r["t"] <= spin.end_t)]
    return float(v.min()) * MPS_TO_KMH if len(v) else float("nan")


def _overlaps(spin: Turn, turns: list[Turn]) -> str:
    """The counted maneuvers whose sweeps intersect this one, in time order."""
    hits = [f"{t.kind}@{t.net_deg:+.0f}" for t in turns
            if t.counted and t.start_t <= spin.end_t and t.end_t >= spin.start_t]
    return ", ".join(hits) if hits else "-"


def analyse(path: Path, cfg: TurnConfig):
    """(spins, all turns, raw track, cleaned track, session start t), detector ON."""
    track = parse_track(path)
    ct = clean(track)
    fr = segment_flights(ct)
    turns = detect_turns(ct, fr, estimate_wind(ct, fr), cfg)
    t0 = float(ct.records["t"].iloc[0]) if len(ct.records) else 0.0
    return [t for t in turns if t.kind == THREE_SIXTY], turns, track, ct, t0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fixtures", type=Path, default=FIXTURES)
    ap.add_argument("--quiet", action="store_true", help="counts only, no candidate rows")
    ap.add_argument("--min-deg", type=float, default=TurnConfig.three_sixty_min_deg)
    ap.add_argument("--max-s", type=float, default=TurnConfig.three_sixty_max_s)
    ap.add_argument("--reversal-deg", type=float,
                    default=TurnConfig.three_sixty_reversal_deg)
    ap.add_argument("--min-kmh", type=float, default=TurnConfig.three_sixty_min_kmh)
    args = ap.parse_args(argv)

    cfg = TurnConfig(detect_three_sixty=True, three_sixty_min_deg=args.min_deg,
                     three_sixty_max_s=args.max_s,
                     three_sixty_reversal_deg=args.reversal_deg,
                     three_sixty_min_kmh=args.min_kmh)
    paths = sorted(p for p in args.fixtures.rglob("*") if p.suffix.lower() in TRACK_SUFFIXES)
    if not paths:
        print(f"no fixtures under {args.fixtures}", file=sys.stderr)
        return 1

    print(f"360 detector ON: minDeg={cfg.three_sixty_min_deg:g} "
          f"maxS={cfg.three_sixty_max_s:g} "
          f"reversalDeg={cfg.three_sixty_reversal_deg:g} minKmh={cfg.three_sixty_min_kmh:g} "
          f"entry={cfg.foil_entry_speed_kmh:g} km/h\n")

    total = 0
    for path in paths:
        spins, turns, track, ct, t0 = analyse(path, cfg)
        total += len(spins)
        counted = sum(1 for t in turns if t.counted)
        print(f"{path.name}  —  {len(spins)} candidate(s), {counted} counted turn(s)")
        if not spins or args.quiet:
            continue
        print(HEADER)
        for s in spins:
            print(f"{_clock(track, s.start_t):>8} {_offset(s.start_t, t0):>8} "
                  f"{s.net_deg:>8.1f} {s.end_t - s.start_t:>6.1f} "
                  f"{s.entry_kn_doppler * KN_TO_KMH:>7.1f} "
                  f"{_sweep_min_kmh(ct, s):>7.1f} "
                  f"{s.arc_m:>7.1f} {s.radius_m:>6.1f} {s.outcome:>12}  "
                  f"{_overlaps(s, turns)}")
        print()
    print(f"\n{total} candidate(s) over {len(paths)} session(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
