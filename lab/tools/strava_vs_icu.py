#!/usr/bin/env python
"""Why the same session read through Strava shows fewer touchdowns than through intervals.icu.

Jan, 17 Sep 2026: *"the same session imported from intervals.icu (FIT, class b/a) and from
Strava (positions only, class c) gives fewer touchdowns on the Strava copy."* This script is
the experiment that answers it, and it changes no engine behaviour: every variant is a
`FilterConfig` / `TurnConfig` handed to `goldens.analyze`, nothing is monkey-patched.

**The two arms.**

* *icu* — the fixture FIT itself, exactly what intervals.icu hands back: device Doppler,
  barometer, accelerometer, developer fields. Class (a)/(b).
* *strava* — the same session with only what a Strava export carries: latitude, longitude,
  elevation and a clock, written out as GPX 1.1 through `tools/fit_to_gpx.to_gpx` and
  re-read through the engine's class (c) door. Positions are **rounded to 1e-6 deg**,
  because that is the precision Strava stores them at: the activity-stream API for
  19964283802 (2026-08-30 14:07, the twin of the ciq fixture) returns 646 samples at a flat
  1 Hz with six decimals, against the FIT's semicircle resolution of ~8.4e-8 deg. So the
  synthetic arm is not an approximation of the Strava copy in cadence or coverage; the one
  thing it rounds is the one thing Strava rounds.

**The variants** (`--variants`), each a single knob moved on the *strava* arm only:

    strava            the class (c) reading as shipped
    nospike           max_accel_1hz = inf: the Doppler spike filter is not applied to a
                      channel that was differentiated from positions in the first place
    noele             the GPX is written without <ele>: the barometer rung (step 2 of the
                      turn-outcome ladder) is gone, which is what a Strava copy whose
                      elevation was corrected against a DEM looks like
    stop=<mps>        turnStopSpeedFloor moved on the turn and flight-end configs
    exit=<kmh>        foilExitSpeed moved on the turn/flight-end/takeoff configs together

Usage:

    cd lab && uv run python tools/strava_vs_icu.py                      # the default corpus
    cd lab && uv run python tools/strava_vs_icu.py --variants strava nospike --turns
    cd lab && uv run python tools/strava_vs_icu.py --fit ../fixtures/sessions/ciq/*.fit
"""

from __future__ import annotations

import argparse
import math
import sys
import tempfile
from dataclasses import replace
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from fit_to_gpx import to_gpx  # noqa: E402

from wingfoil_lab.filters import FilterConfig  # noqa: E402
from wingfoil_lab.flightend import FlightEndConfig  # noqa: E402
from wingfoil_lab.goldens import Analysis, analyze, session_duration_s  # noqa: E402
from wingfoil_lab.takeoff import TakeoffConfig  # noqa: E402
from wingfoil_lab.turns import TurnConfig  # noqa: E402

REPO = Path(__file__).resolve().parents[2]

DEFAULT_FITS = [
    "fixtures/sessions/ciq/2026-08-07-0754_nago-torbole-windsurfen_ciq.fit",
    "fixtures/sessions/ciq/2026-08-29-1440_nago-torbole-windsurfen_ciq.fit",
    "fixtures/sessions/ciq/2026-08-30-1407_nago-torbole-windsurfen_ciq.fit",
    "fixtures/sessions/windsurf-native/2026-08-04-1411_nago-torbole-windsurfen_native.fit",
    "fixtures/sessions/windsurf-native/2026-08-05-0827_nago-torbole-windsurfen_native.fit",
]


# ---------------------------------------------------------------- the Strava view


def strava_gpx(fit: Path, out_dir: Path, decimals: int = 6, ele: bool = True) -> Path:
    """The FIT as a Strava export would carry it: positions, elevation, a clock — no speed.

    `decimals` is Strava's stored precision (six), applied by rewriting the `lat`/`lon`
    attributes of the GPX `to_gpx` already writes at seven.
    """
    text = to_gpx(fit, name=fit.stem, creator="strava_vs_icu (synthetic Strava export)")
    if decimals != 7:
        import re

        def round_attr(m: "re.Match[str]") -> str:
            return f'{m.group(1)}="{round(float(m.group(2)), decimals):.{decimals}f}"'

        text = re.sub(r'\b(lat|lon)="(-?\d+\.\d+)"', round_attr, text)
    if not ele:
        import re as _re
        text = _re.sub(r"\s*<ele>[^<]*</ele>", "", text)
    out = out_dir / f"{fit.stem}.strava{'' if ele else '.noele'}.gpx"
    out.write_text(text, encoding="utf-8")
    return out


def run(path: Path, variant: str) -> Analysis:
    """`analyze` with the one knob this variant moves."""
    fcfg, tcfg = FilterConfig(), TurnConfig()
    fecfg, tocfg = FlightEndConfig(), TakeoffConfig()
    if variant == "nospike":
        fcfg = replace(fcfg, max_accel_1hz=float("inf"))
    elif variant.startswith("stop="):
        tcfg = replace(tcfg, stop_speed_floor_mps=float(variant.split("=", 1)[1]))
        fecfg = replace(fecfg, stop_speed_floor_mps=float(variant.split("=", 1)[1]))
    elif variant.startswith("exit="):
        kmh = float(variant.split("=", 1)[1])
        tcfg = replace(tcfg, foil_exit_speed_kmh=kmh)
        fecfg = replace(fecfg, foil_exit_speed_kmh=kmh)
        tocfg = replace(tocfg, foil_exit_speed_kmh=kmh)
    elif variant not in ("icu", "strava", "noele"):
        raise SystemExit(f"unknown variant {variant!r}")
    return analyze(path, filter_config=fcfg, turn_config=tcfg,
                   flight_end_config=fecfg, takeoff_config=tocfg)


# ---------------------------------------------------------------- reporting


def counts(a: Analysis) -> dict:
    turns = [t for t in a.turns if t.counted]
    out = {"turns": len(turns), "flew": 0, "touch": 0, "fell": 0, "clean": 0}
    for t in turns:
        out[{"flew_through": "flew", "touchdown": "touch", "fell_in": "fell"}[t.outcome]] += 1
        out["clean"] += bool(t.clean)
    out["foilS"] = round(a.flights.foil_time_s, 1)
    out["durS"] = round(session_duration_s(a.clean), 1)
    out["samples"] = len(a.clean.records)
    out["spikeDrop"] = a.clean.dropped_spike
    out["best2sKn"] = round(a.records.best2s_kn, 2)
    # The rider-facing session split (docs/algorithms.md "Where it went wet"): turn-side and
    # straight-line losses together, which is the "touchdowns" number on the session page.
    out["sTouch"] = a.outcome_split.touchdowns
    out["sFall"] = a.outcome_split.falls
    out["glide"] = a.outcome_split.glide_outs
    return out


def match_turns(icu, other, tol_s: float = 10.0):
    """Pair turns across the two arms on the time of the speed minimum."""
    pairs, used = [], set()
    for t in icu:
        best, bd = None, tol_s
        for j, o in enumerate(other):
            if j in used:
                continue
            d = abs(o.min_t - t.min_t)
            if d < bd:
                best, bd = j, d
        if best is None:
            pairs.append((t, None))
        else:
            used.add(best)
            pairs.append((t, other[best]))
    for j, o in enumerate(other):
        if j not in used:
            pairs.append((None, o))
    return sorted(pairs, key=lambda p: (p[0] or p[1]).min_t)


ICON = {"flew_through": "flew", "touchdown": "touch", "fell_in": "fell"}


def turn_table(fit: Path, icu: Analysis, other: Analysis, t0: float) -> list[str]:
    rows = [f"  {'t':>7}  {'kind':<9} {'icu':<6} {'strava':<6}  "
            f"{'icu min kn':>10} {'str min kn':>10}  why(icu) / why(strava)"]
    for a, b in match_turns([t for t in icu.turns if t.counted],
                            [t for t in other.turns if t.counted]):
        ref = a or b
        t = ref.min_t - t0
        mark = " " if (a and b and a.outcome == b.outcome) else "*"
        rows.append(
            f" {mark}{int(t)//60:>3}:{int(t)%60:02d}  {ref.kind:<9} "
            f"{(ICON[a.outcome] if a else '--'):<6} {(ICON[b.outcome] if b else '--'):<6}  "
            f"{(a.min_kn if a else math.nan):>10.2f} {(b.min_kn if b else math.nan):>10.2f}  "
            f"{(a.outcome_reason or '-') if a else '-'} / "
            f"{(b.outcome_reason or '-') if b else '-'}")
    return rows


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fit", nargs="*", type=Path, default=None)
    ap.add_argument("--variants", nargs="*", default=["strava"],
                    help="strava | nospike | exit=<kmh>")
    ap.add_argument("--turns", action="store_true", help="per-turn diff table")
    ap.add_argument("--decimals", type=int, default=6,
                    help="position precision of the Strava view (default 6, Strava's own)")
    args = ap.parse_args(argv)

    fits = args.fit or [REPO / p for p in DEFAULT_FITS]
    tmp = Path(tempfile.mkdtemp(prefix="strava_vs_icu_"))
    hdr = f"{'session':<34} {'arm':<10} {'turns':>5} {'flew':>5} {'touch':>5} {'fell':>5} " \
          f"{'clean':>5} {'foil s':>7} {'S-tch':>6} {'S-fll':>6} {'glide':>6} {'best2s':>7}"
    print(hdr)
    print("-" * len(hdr))
    for fit in fits:
        icu = run(Path(fit), "icu")
        t0 = float(icu.clean.records["t"].iloc[0])
        gpx = strava_gpx(Path(fit), tmp, args.decimals)
        bare = strava_gpx(Path(fit), tmp, args.decimals, ele=False)
        name = Path(fit).stem[:34]
        for arm, a in [("icu", icu)] + [(v, run(bare if v == "noele" else gpx, v))
                                        for v in args.variants]:
            c = counts(a)
            print(f"{name:<34} {arm:<10} {c['turns']:>5} {c['flew']:>5} {c['touch']:>5} "
                  f"{c['fell']:>5} {c['clean']:>5} {c['foilS']:>7.1f} {c['sTouch']:>6} "
                  f"{c['sFall']:>6} {c['glide']:>6} {c['best2sKn']:>7.2f}")
        if args.turns:
            v0 = args.variants[0]
            first = run(bare if v0 == "noele" else gpx, v0)
            print("\n".join(turn_table(Path(fit), icu, first, t0)))
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
