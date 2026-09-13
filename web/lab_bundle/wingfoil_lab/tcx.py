"""Parse TCX (Garmin Training Center Database v2) files into the same `RawTrack`.

TCX is the second XML door, and unlike GPX it is **not one input class**. A TCX carries
positions and a clock like a GPX does, and it *may* also carry the receiver's own speed in
Garmin's per-point `TPX` extension (`Extensions/TPX/Speed`, m/s). Polar, Suunto and Coros
all export TCX through intervals.icu, and whether their file states a speed decides what
the analysis is allowed to claim:

* **`TPX/Speed` present ⇒ input class (b)**, exactly like a native FIT. The number was
  measured by the receiver, `SourceCapabilities.has_speed` is **True**, and the speed
  records are *certified*.
* **`TPX/Speed` absent ⇒ input class (c)**, exactly like a GPX. Speed is differentiated
  from positions with the same arithmetic `gpx.py` uses, `has_speed` stays **False**, and
  every surface marks those speed records *uncertified*.

That single rule is the whole of the difference between the two halves of this module, and
it is written down in docs/algorithms.md beside the GPX section. Everything else — the
clock, the zone ladder, the segment rule, the missing accelerometer, the missing developer
fields — a TCX shares with a GPX, and the code for it is imported from `gpx.py` rather than
spelled a second time: a positional speed that differed between the two formats would be a
bug the goldens could not see.

**Segments.** TCX nests `Activity > Lap > Track > Trackpoint`, and the two container levels
mean different things. A `<Lap>` is a *marker* — the rider pressed lap, or the watch closed
one on a distance — and the track runs straight through it, so a lap boundary is **not** a
gap. A second `<Track>` inside a lap is the recorder saying it stopped and started again,
which is precisely what a GPX `<trkseg>` boundary says, so **that** is the join marked
`gap_before`. Laps are carried through to `RawTrack.laps` with the three fields TCX states,
under the FIT names, so `has_watch_laps` follows the same rule it does for a FIT.

**Several activities.** A `<TrainingCenterDatabase>` may hold several `<Activity>`s. They
are separate sessions, not segments of one, so the first is analysed and the count is
reported in `session["tcxActivities"]` — the same rule `gpx.py` applies to several `<trk>`s.

**Sport.** `Activity/@Sport` is *not* read into `capabilities.sport`. The TCX schema admits
exactly three values — `Running`, `Biking`, `Other` — so a wingfoil session is `Other` by
construction, and filing that as the session's sport would turn "this file cannot say" into
a positive claim that a watersport gate would then act on. Silence is the honest answer.

**Distance.** `Trackpoint/DistanceMeters` is read by nothing here, for the same reason the
GPX parser reads no distance: the engine integrates its own from the cleaned track, and a
cumulative odometer written by the exporter is a different number measured a different way.

Fail-soft like both parsers above it: a `Trackpoint` without a time cannot be placed on the
timeline and is skipped, a point without both coordinates is skipped, and a malformed number
is dropped rather than raised on.
"""

from __future__ import annotations

import math
import xml.etree.ElementTree as ET
from pathlib import Path

import numpy as np
import pandas as pd

from .filters import M_PER_DEG_LAT, M_PER_DEG_LON_EQ
from .gpx import (_child_num, _declared_offset, _find_all, _num, _point_time,
                  _segment_speed)
from .parse import RawTrack, SourceCapabilities, resolve_utc_offset

#: The per-point extension a TCX may carry a measured speed in. Matched on the local tag
#: name so `ns3:TPX`, `x:TPX` and an unqualified `TPX` are all read by the same code.
SPEED_TAGS = {"speed"}


def parse_tcx(path: str | Path) -> RawTrack:
    """TCX file -> `RawTrack`, shaped exactly as `parse.parse_fit` shapes a FIT."""
    path = Path(path)
    return _track_from_root(ET.parse(path).getroot(), str(path))


def parse_tcx_bytes(data: bytes, path: str = "<tcx>") -> RawTrack:
    """Same, from bytes — the browser and the share sheet never have a file path."""
    return _track_from_root(ET.fromstring(data), path)


def is_tcx(data: bytes) -> bool:
    """Cheap content sniff: does this blob look like TCX rather than GPX or FIT?

    Byte-level rather than extension-level, for the reason `gpx.is_gpx` is: the callers
    that matter (a dropped file, an intervals.icu original, a ZIP member) all have bytes
    and only sometimes have a trustworthy name. Only the first 2 KB are examined — enough
    for the XML declaration, a byte-order mark and the root element with its namespaces.
    """
    head = data[:512].lstrip(b"\xef\xbb\xbf \t\r\n")
    if not head.startswith(b"<"):
        return False
    return b"<trainingcenterdatabase" in data[:2048].lower()


# ------------------------------------------------------------------------- internals


def _track_from_root(root: ET.Element, path: str) -> RawTrack:
    activities = [a for holder in _find_all(root, "Activities")
                  for a in _find_all(holder, "Activity")]
    first = activities[0] if activities else None

    segments: list[list[dict]] = []
    offsets: list[int] = []
    laps: list[dict] = []
    for lap in (_find_all(first, "Lap") if first is not None else []):
        laps.append(_lap_fields(lap))
        for track in _find_all(lap, "Track"):
            rows, track_offsets = _track_points(track)
            if rows:
                segments.append(rows)
                offsets.extend(track_offsets)

    session: dict = {"tcxActivities": len(activities), "tcxTracks": len(segments)}
    if first is not None:
        ident = next((c.text for c in _find_all(first, "Id") if c.text), None)
        if ident:
            session["tcxId"] = ident.strip()

    df = _frame(segments)
    caps = SourceCapabilities(
        # THE rule of this module. A stated `TPX/Speed` is the receiver's own measurement
        # and makes the file class (b); without one the `speed_mps` below is differentiated
        # from positions exactly as a GPX's is, the flag stays False, and the session is
        # class (c) with its speed records marked uncertified.
        has_speed=_stated_speed(segments),
        has_position=bool(len(df)),
        has_hr=bool(len(df)) and "heart_rate" in df and bool(df["heart_rate"].notna().any()),
        has_watch_laps=len(laps) > 1,
    )
    if len(df) > 1:
        dt = df["t"].diff().dropna()
        med = float(dt.median()) if not dt.empty else 0.0
        caps.sample_rate_hz = round(1.0 / med, 3) if med > 0 else 0.0
    if len(df):
        session["total_elapsed_time"] = round(float(df["t"].iloc[-1] - df["t"].iloc[0]), 3)

    offset, source = resolve_utc_offset(_declared_offset(offsets), df, caps)
    return RawTrack(path=path, records=df, laps=laps, session=session, capabilities=caps,
                    accel=None, start_utc_offset_s=offset, start_utc_offset_source=source)


def _stated_speed(segments: list[list[dict]]) -> bool:
    """Did the *file* state a speed, anywhere? The capability's only question."""
    return any(row.get("speed_mps") is not None for seg in segments for row in seg)


def _lap_fields(lap: ET.Element) -> dict:
    """One `<Lap>` -> the three fields TCX states, under the FIT parser's own names.

    Only what the file says: nothing is derived here, because `RawTrack.laps` is read for
    its *length* (`has_watch_laps`) and by notebooks, and a computed lap would be a number
    the recording never contained.
    """
    out: dict = {}
    start = lap.get("StartTime")
    if start:
        when, _ = _point_time_from_text(start)
        if when is not None:
            out["start_time"] = when
    total = _child_num(lap, "TotalTimeSeconds")
    if total is not None:
        out["total_timer_time"] = total
    dist = _child_num(lap, "DistanceMeters")
    if dist is not None:
        out["total_distance"] = dist
    return out


def _point_time_from_text(text: str):
    """`_point_time`'s scanner, on a bare string (a `<Lap StartTime=…>` attribute)."""
    holder = ET.Element("holder")
    child = ET.SubElement(holder, "time")
    child.text = text
    return _point_time(holder)


def _track_points(track: ET.Element) -> tuple[list[dict], list[int]]:
    """One `<Track>` -> its usable points, plus every explicitly stated UTC offset."""
    rows: list[dict] = []
    offsets: list[int] = []
    for pt in _find_all(track, "Trackpoint"):
        when, offset = _point_time(_renamed(pt, "Time"))
        if when is None:
            # No clock, no timeline — the rule `gpx.py` states at length. A TCX written by
            # a treadmill is exactly this, whole: trackpoints with a time and no position,
            # which the position test below then drops.
            continue
        lat, lon = _position(pt)
        if lat is None or lon is None:
            continue
        if offset is not None:
            offsets.append(offset)
        row: dict = {"timestamp": when, "lat": lat, "lon": lon}
        ele = _child_num(pt, "AltitudeMeters")
        if ele is not None:
            row["altitude"] = ele
        hr = _heart_rate(pt)
        if hr is not None:
            row["heart_rate"] = hr
        speed = _tpx_speed(pt)
        if speed is not None:
            row["speed_mps"] = speed
        rows.append(row)
    rows.sort(key=lambda r: r["timestamp"])
    deduped, seen = [], set()
    for row in rows:
        if row["timestamp"] in seen:
            continue
        seen.add(row["timestamp"])
        deduped.append(row)
    return deduped, offsets


def _renamed(pt: ET.Element, name: str) -> ET.Element:
    """A one-child stand-in so `gpx._point_time` can read TCX's `<Time>`.

    `_point_time` looks for a child called `time` and TCX calls it `Time`; wrapping is what
    keeps the ISO-8601 scanner — including the `Z`-is-an-instant rule the whole zone ladder
    turns on — spelled exactly once for both formats.
    """
    holder = ET.Element("holder")
    for child in _find_all(pt, name):
        clone = ET.SubElement(holder, "time")
        clone.text = child.text
    return holder


def _position(pt: ET.Element) -> tuple[float | None, float | None]:
    for pos in _find_all(pt, "Position"):
        lat = _child_num(pos, "LatitudeDegrees")
        lon = _child_num(pos, "LongitudeDegrees")
        if lat is not None and lon is not None:
            return lat, lon
    return None, None


def _heart_rate(pt: ET.Element) -> float | None:
    """`<HeartRateBpm><Value>142</Value></HeartRateBpm>`, the one shape TCX defines."""
    for hr in _find_all(pt, "HeartRateBpm"):
        v = _child_num(hr, "Value")
        if v is not None:
            return v
    return None


def _tpx_speed(pt: ET.Element) -> float | None:
    """Speed in m/s from `<Extensions>`, at any depth, under any prefix.

    Searched by local tag name rather than by namespace: the activity extension lives under
    two different Garmin URIs (v1 and v2) and every exporter picks its own prefix, and
    `Speed` is unambiguous by local name inside a trackpoint.
    """
    for ext in _find_all(pt, "Extensions"):
        for el in ext.iter():
            if el.tag.rsplit("}", 1)[-1].lower() in SPEED_TAGS:
                v = _num(el.text)
                if v is not None and v >= 0.0:
                    return v
    return None


def _frame(segments: list[list[dict]]) -> pd.DataFrame:
    """Segments -> the record frame, with the same columns a GPX produces.

    The one branch is the speed column: where the file stated `TPX/Speed` it is carried
    through untouched (class (b), a measured channel), and where it did not the positions
    are differentiated per segment (class (c), `gpx._segment_speed` byte for byte).
    """
    columns = ["timestamp", "lat", "lon", "altitude", "heart_rate", "t", "speed_mps",
               "gap_before"]
    rows = [r for seg in segments for r in seg]
    if not rows:
        return pd.DataFrame({c: pd.Series(dtype="float64") for c in columns})

    df = pd.DataFrame(rows)
    df["timestamp"] = pd.to_datetime(df["timestamp"], utc=True)
    t0 = df["timestamp"].iloc[0]
    df["t"] = (df["timestamp"] - t0).dt.total_seconds()

    gap = np.zeros(len(df), dtype=bool)
    start = 0
    for seg in segments:
        if start:
            gap[start] = True          # a second `<Track>`: two recordings, not one motion
        start += len(seg)
    df["gap_before"] = gap

    if "speed_mps" not in df.columns or not df["speed_mps"].notna().any():
        # No stated speed anywhere: derive it, exactly as `gpx._frame` does — same
        # projection, same central difference, same per-segment isolation.
        lat = df["lat"].to_numpy(float)
        lon = df["lon"].to_numpy(float)
        lat0, lon0 = float(np.mean(lat)), float(np.mean(lon))
        x = (lon - lon0) * math.cos(math.radians(lat0)) * M_PER_DEG_LON_EQ
        y = (lat - lat0) * M_PER_DEG_LAT
        speed = np.full(len(df), np.nan)
        start = 0
        for seg in segments:
            stop = start + len(seg)
            speed[start:stop] = _segment_speed(df["t"].to_numpy(float)[start:stop],
                                               x[start:stop], y[start:stop])
            start = stop
        df["speed_mps"] = speed

    for c in ("altitude", "heart_rate", "speed_mps"):
        if c not in df.columns:
            df[c] = np.nan
    return df[columns]
