#!/usr/bin/env python
"""Convert a fixture FIT's track to TCX v2 — the corpus's two synthetic TCX recordings.

The sibling of `fit_to_gpx.py`, and for the same reason: the point of a TCX fixture is to
pin down what the engine does when the *same session* arrives in the other XML format, so
every difference between the goldens is the source class and nothing else. A TCX exported
from some other afternoon would test the parser and prove nothing about the degradation.

A TCX is the one format that can be either input class, and which one is decided by a
single element (docs/algorithms/imports.md, "TCX import"):

    --speed     writes `Extensions/TPX/Speed` from the FIT's own Doppler channel.
                The file states a measured speed, so it is class (b) and its speed
                records certify, exactly as the FIT's do.
    (default)   omits it. Speed is then differentiated from positions by `tcx.py`, the
                file is class (c), and the records are marked uncertified — the same
                degradation the GPX fixture measures.

Both are written from the same FIT, so the pair is the experiment: one element in, one
element out, and two goldens that differ by exactly what that element licenses.

What else crosses over: `Position` lat/lon, `AltitudeMeters` from the FIT's altitude,
`Time` (UTC, `Z`, one second's resolution as the record stream has it) and
`HeartRateBpm/Value`. What deliberately does not: the accelerometer stream, our developer
fields and the session summary. One `<Activity>`, one `<Lap>`, one `<Track>` — what a real
exporter hands out for an unlapped session.

    cd lab && uv run python tools/fit_to_tcx.py \\
        ../fixtures/sessions/ciq/2026-08-30-1407_nago-torbole-windsurfen_ciq.fit \\
        --out ../fixtures/sessions/tcx/2026-08-30-1407_nago-torbole-nospeed.tcx
    cd lab && uv run python tools/fit_to_tcx.py --speed \\
        ../fixtures/sessions/ciq/2026-08-30-1407_nago-torbole-windsurfen_ciq.fit \\
        --out ../fixtures/sessions/tcx/2026-08-30-1407_nago-torbole-speed.tcx
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from xml.sax.saxutils import escape

from wingfoil_lab.parse import parse_fit

REPO = Path(__file__).resolve().parents[2]

TCX_NS = "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"
TPX_NS = "http://www.garmin.com/xmlschemas/ActivityExtension/v2"


def to_tcx(path: Path, *, with_speed: bool, sport: str = "Other") -> str:
    """The FIT's record stream as a TCX v2 document (one Activity, one Lap, one Track)."""
    track = parse_fit(path)
    df = track.records
    if df.empty or "timestamp" not in df.columns:
        raise SystemExit(f"{path.name}: no timestamped records to convert")

    start = _iso(df["timestamp"].iloc[0])
    elapsed = float(df["t"].iloc[-1] - df["t"].iloc[0]) if "t" in df.columns else 0.0
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<TrainingCenterDatabase xmlns="{TCX_NS}" xmlns:ns3="{TPX_NS}">',
        "  <Activities>",
        f'    <Activity Sport="{escape(sport)}">',
        f"      <Id>{start}</Id>",
        f'      <Lap StartTime="{start}">',
        f"        <TotalTimeSeconds>{elapsed:.1f}</TotalTimeSeconds>",
        "        <Track>",
    ]
    written = 0
    for row in df.itertuples(index=False):
        lat, lon = getattr(row, "lat", None), getattr(row, "lon", None)
        ts = getattr(row, "timestamp", None)
        if lat is None or lon is None or ts is None or lat != lat or lon != lon:
            continue
        lines.append("          <Trackpoint>")
        lines.append(f"            <Time>{_iso(ts)}</Time>")
        lines.append("            <Position>"
                     f"<LatitudeDegrees>{lat:.7f}</LatitudeDegrees>"
                     f"<LongitudeDegrees>{lon:.7f}</LongitudeDegrees></Position>")
        ele = _first_finite(row, ("enhanced_altitude", "altitude"))
        if ele is not None:
            lines.append(f"            <AltitudeMeters>{ele:.2f}</AltitudeMeters>")
        hr = _first_finite(row, ("heart_rate",))
        if hr is not None:
            lines.append("            <HeartRateBpm>"
                         f"<Value>{int(round(hr))}</Value></HeartRateBpm>")
        speed = _first_finite(row, ("speed_mps", "enhanced_speed", "speed"))
        if with_speed and speed is not None:
            lines.append("            <Extensions><ns3:TPX>"
                         f"<ns3:Speed>{speed:.3f}</ns3:Speed></ns3:TPX></Extensions>")
        lines.append("          </Trackpoint>")
        written += 1
    lines += ["        </Track>", "      </Lap>", "    </Activity>", "  </Activities>",
              "</TrainingCenterDatabase>", ""]
    if not written:
        raise SystemExit(f"{path.name}: no GPS fixes to convert")
    kind = "class (b), TPX speed written" if with_speed else "class (c), no speed channel"
    print(f"{path.name}: {written} of {len(df)} records carried a fix — {kind}",
          file=sys.stderr)
    return "\n".join(lines)


def _first_finite(row, names):
    for n in names:
        v = getattr(row, n, None)
        if v is not None and v == v:
            return float(v)
    return None


def _iso(ts) -> str:
    """UTC, `Z`, whole seconds — the shape every exporter in the wild writes."""
    return ts.tz_convert("UTC").strftime("%Y-%m-%dT%H:%M:%SZ")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("fit", type=Path, help="source FIT fixture")
    ap.add_argument("--speed", action="store_true",
                    help="write Extensions/TPX/Speed from the FIT's Doppler channel "
                         "(makes the result class (b) rather than class (c))")
    ap.add_argument("--out", type=Path, default=None,
                    help="output .tcx (default: fixtures/sessions/tcx/<stem>.tcx)")
    args = ap.parse_args(argv)

    out = args.out or REPO / "fixtures" / "sessions" / "tcx" / f"{args.fit.stem}.tcx"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(to_tcx(args.fit, with_speed=args.speed), encoding="utf-8")
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
