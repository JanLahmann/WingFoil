#!/usr/bin/env python
"""Line the rider's footage up against a session, and say what each clip shows.

The reel (CleanJibe Pro §2.5) is footage cut to detected events, and everything in it
depends on one number per camera: the offset between the camera's clock and GPS time.
This tool is the feasibility study for that number. It reads the creation time of every
video and photo in a folder, places each on the session's clock, and lists the events
the engine found inside each clip's window — turns with their verdict, takeoffs, flight
ends — so a human can check the claim against the picture in ten seconds.

Clocks, from best to worst:
  * iPhone originals (AirDrop, "All Photos Data") carry `com.apple.quicktime.creationdate`
    WITH a UTC offset, and EXIF DateTimeOriginal + OffsetTime for stills. Offset ≈ 0.
  * GoPro: `creation_time` is the camera's own clock (often minutes out, no zone); the GPMF
    track has GPS time. Phase H3 cross-correlates that; until then pass --offset-s.
  * WhatsApp/Telegram re-encodes strip everything; the file's mtime is the send time.
    Such a clip lands on the session only with a hand-entered --offset-s.

Usage:
    cd lab && uv run python tools/align_footage.py SESSION.fit FOOTAGE_DIR
                 [--offset-s 0] [--pad-s 3] [--json out.json]

`--offset-s` is added to every clip's clock (camera slow → positive). ffprobe is used for
video metadata; on macOS `mdls` reads stills so no image library is needed.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path

from wingfoil_lab.goldens import analyze

VIDEO = {".mov", ".mp4", ".m4v"}
IMAGE = {".jpg", ".jpeg", ".heic", ".png", ".dng"}


@dataclass
class Clip:
    path: str
    kind: str                # "video" | "photo"
    start_utc: float         # epoch seconds, camera clock
    duration_s: float        # 0 for a photo
    clock_source: str        # which metadata answered
    start_t: float = 0.0     # session-relative, after --offset-s
    end_t: float = 0.0
    inside: bool = False
    events: list[dict] | None = None


def _run(cmd: list[str]) -> str:
    return subprocess.run(cmd, capture_output=True, text=True, check=False).stdout


def _parse_iso(s: str) -> float | None:
    s = s.strip()
    for fmt in ("%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%dT%H:%M:%S.%fZ",
                "%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%d %H:%M:%S %z"):
        try:
            d = datetime.strptime(s, fmt)
            if d.tzinfo is None:
                d = d.replace(tzinfo=timezone.utc)
            return d.timestamp()
        except ValueError:
            continue
    return None


def video_clock(path: Path) -> tuple[float | None, float, str]:
    out = _run(["ffprobe", "-v", "quiet", "-print_format", "json", "-show_format", str(path)])
    if not out:
        return None, 0.0, "no ffprobe"
    fmt = json.loads(out).get("format", {})
    tags = fmt.get("tags", {})
    dur = float(fmt.get("duration", 0.0) or 0.0)
    # The Apple key carries the zone; `creation_time` is UTC by convention but a GoPro
    # writes its own clock there. Prefer the one that says what it is.
    for key in ("com.apple.quicktime.creationdate", "creation_time"):
        if key in tags:
            t = _parse_iso(tags[key])
            if t is not None:
                return t, dur, key
    return None, dur, "no creation tag"


def image_clock(path: Path) -> tuple[float | None, str]:
    if sys.platform == "darwin":
        out = _run(["mdls", "-raw", "-name", "kMDItemContentCreationDate", str(path)])
        t = _parse_iso(out.replace(" +0000", " +0000")) if out and out != "(null)" else None
        if t is not None:
            return t, "mdls kMDItemContentCreationDate"
    return None, "no reader"


def read_clips(folder: Path) -> list[Clip]:
    clips: list[Clip] = []
    for p in sorted(folder.iterdir()):
        ext = p.suffix.lower()
        if ext in VIDEO:
            t, dur, src = video_clock(p)
            if t is not None:
                clips.append(Clip(str(p), "video", t, dur, src))
        elif ext in IMAGE:
            t, src = image_clock(p)
            if t is not None:
                clips.append(Clip(str(p), "photo", t, 0.0, src))
    return clips


def session_epoch0(a) -> float:
    rec = a.track.records
    if "timestamp" in rec:
        t0 = rec["timestamp"].iloc[0]
        return t0.timestamp() if hasattr(t0, "timestamp") else float(t0)
    raise SystemExit("session has no record timestamps")


def events_of(a) -> list[dict]:
    ev: list[dict] = []
    for i, t in enumerate(a.turns, 1):
        ev.append({"kind": f"turn/{t.kind}", "n": i, "t": t.start_t, "end": t.end_t,
                   "outcome": t.outcome, "clean": bool(getattr(t, "clean", False)),
                   "score": round(t.score, 2)})
    for i, f in enumerate(a.flights.flights, 1):
        ev.append({"kind": "takeoff", "n": i, "t": f.start_t, "end": f.start_t,
                   "flight_s": round(f.duration_s, 1)})
    for e in a.flight_ends:
        ev.append({"kind": f"flight_end/{e.outcome}", "n": e.flight_index + 1,
                   "t": e.t, "end": e.t})
    return sorted(ev, key=lambda e: e["t"])


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("fit")
    ap.add_argument("footage", type=Path)
    ap.add_argument("--offset-s", type=float, default=0.0,
                    help="camera clock correction, added to every clip (camera slow -> +)")
    ap.add_argument("--pad-s", type=float, default=3.0,
                    help="seconds either side of an event that still count as 'in the clip'")
    ap.add_argument("--json", type=Path)
    args = ap.parse_args()

    a = analyze(args.fit)
    epoch0 = session_epoch0(a)
    span = float(a.track.records.index[-1])
    events = events_of(a)
    clips = read_clips(args.footage)
    if not clips:
        print("no readable footage in", args.footage)
        return 1

    print(f"session {Path(args.fit).name}: {span/60:.0f} min, {len(events)} events, "
          f"start {datetime.fromtimestamp(epoch0, timezone.utc):%Y-%m-%d %H:%M:%S}Z")
    print(f"{len(clips)} clips, offset {args.offset_s:+.1f} s\n")
    for c in clips:
        c.start_t = c.start_utc + args.offset_s - epoch0
        c.end_t = c.start_t + c.duration_s
        c.inside = c.end_t >= -args.pad_s and c.start_t <= span + args.pad_s
        c.events = [e for e in events
                    if e["end"] >= c.start_t - args.pad_s and e["t"] <= c.end_t + args.pad_s] \
            if c.inside else []
        where = "outside the session" if not c.inside else \
            f"{c.start_t/60:6.1f}–{c.end_t/60:5.1f} min"
        print(f"{Path(c.path).name:36s} {c.kind:5s} {c.duration_s:5.0f} s  {where}  "
              f"[{c.clock_source}]")
        for e in c.events:
            at = e["t"] - c.start_t
            tag = ""
            if e["kind"].startswith("turn"):
                tag = f"{e['outcome']}{' · clean' if e['clean'] else ''} · score {e['score']}"
            elif e["kind"] == "takeoff":
                tag = f"flight {e['flight_s']} s"
            print(f"    {at:+7.1f} s  {e['kind']} #{e['n']}  {tag}")
    covered = sum(1 for c in clips if c.events)
    print(f"\n{covered} of {len(clips)} clips contain at least one detected event")

    if args.json:
        args.json.write_text(json.dumps({"fit": args.fit, "epoch0": epoch0,
                                         "offset_s": args.offset_s,
                                         "clips": [asdict(c) for c in clips]}, indent=1))
        print("wrote", args.json)
    return 0


if __name__ == "__main__":
    sys.exit(main())
