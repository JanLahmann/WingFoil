#!/usr/bin/env python
"""Convert a fixture FIT's track to GPX 1.1 — the corpus's only synthetic recording.

Why a converted file rather than a real GPX export: the point of the GPX fixture is to
pin down what the engine does when the *same session* arrives without a Doppler channel,
without an accelerometer and without our developer fields. A GPX from some other afternoon
would test the parser and prove nothing about the degradation, because there would be no
FIT to compare it against. Converting one fixture makes the comparison exact — same
positions, same clock, same rider — so every difference in the two goldens is the source
class and nothing else.

What crosses over: `trkpt` lat/lon, `<ele>` from the FIT's altitude, `<time>` (UTC, `Z`,
one second's resolution as the record stream has it) and heart rate in Garmin's
`TrackPointExtension`. What deliberately does not: the speed channel (no GPX carries one —
that is the whole point), the accelerometer stream, the developer fields, the laps and the
session summary. The result is what a real exporter would hand out.

    cd lab && uv run python tools/fit_to_gpx.py \
        ../fixtures/sessions/ciq/2026-08-30-1407_nago-torbole-windsurfen_ciq.fit \
        --out ../fixtures/sessions/gpx/2026-08-30-1407_nago-torbole.gpx
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from xml.sax.saxutils import escape

from wingfoil_lab.parse import parse_fit

REPO = Path(__file__).resolve().parents[2]

GPX_NS = "http://www.topografix.com/GPX/1/1"
TPX_NS = "http://www.garmin.com/xmlschemas/TrackPointExtension/v1"


def to_gpx(path: Path, name: str | None = None, creator: str = "wingfoil-lab fit_to_gpx") -> str:
    """The FIT's record stream as a GPX 1.1 document (one `trk`, one `trkseg`)."""
    track = parse_fit(path)
    df = track.records
    if df.empty or "timestamp" not in df.columns:
        raise SystemExit(f"{path.name}: no timestamped records to convert")

    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<gpx version="1.1" creator="{escape(creator)}" xmlns="{GPX_NS}" '
        f'xmlns:gpxtpx="{TPX_NS}">',
        "  <metadata>",
        f"    <time>{_iso(df['timestamp'].iloc[0])}</time>",
        "  </metadata>",
        "  <trk>",
        f"    <name>{escape(name or path.stem)}</name>",
        "    <trkseg>",
    ]
    written = 0
    for row in df.itertuples(index=False):
        lat, lon = getattr(row, "lat", None), getattr(row, "lon", None)
        ts = getattr(row, "timestamp", None)
        if lat is None or lon is None or ts is None or lat != lat or lon != lon:
            continue
        lines.append(f'      <trkpt lat="{lat:.7f}" lon="{lon:.7f}">')
        ele = _first_finite(row, ("enhanced_altitude", "altitude"))
        if ele is not None:
            lines.append(f"        <ele>{ele:.2f}</ele>")
        lines.append(f"        <time>{_iso(ts)}</time>")
        hr = _first_finite(row, ("heart_rate",))
        if hr is not None:
            lines.append("        <extensions><gpxtpx:TrackPointExtension>"
                         f"<gpxtpx:hr>{int(round(hr))}</gpxtpx:hr>"
                         "</gpxtpx:TrackPointExtension></extensions>")
        lines.append("      </trkpt>")
        written += 1
    lines += ["    </trkseg>", "  </trk>", "</gpx>", ""]
    if not written:
        raise SystemExit(f"{path.name}: no GPS fixes to convert")
    print(f"{path.name}: {written} of {len(df)} records carried a fix", file=sys.stderr)
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
    ap.add_argument("--out", type=Path, default=None,
                    help="output .gpx (default: fixtures/sessions/gpx/<stem>.gpx)")
    ap.add_argument("--name", default=None, help="<trk><name> (default: the FIT's stem)")
    args = ap.parse_args(argv)

    out = args.out or REPO / "fixtures" / "sessions" / "gpx" / f"{args.fit.stem}.gpx"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(to_gpx(args.fit, name=args.name), encoding="utf-8")
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
