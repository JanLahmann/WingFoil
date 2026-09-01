"""Parse GPX 1.1 track files into the same `RawTrack` the FIT parser produces.

GPX is docs/plan.md's **input class (c)**: positions and a clock, and nothing else the
analysis would like to have. The three absences are the whole design of this module, and
each one is recorded as a *fact about the source* rather than papered over:

* **No Doppler.** A GPX carries no speed channel — GPS receivers compute speed from the
  carrier phase and no exporter writes it down. Speed here is therefore *differentiated
  from positions*, which is systematically noisier and can read high on a bad fix, so
  `SourceCapabilities.has_speed` stays **False** even though `records["speed_mps"]` is
  populated. That is not a contradiction: the column says "the analysis has a number to
  work with", the capability says "the file could not prove it was measured". `has_speed`
  is what drives `source_class` -> `"c"`, and class (c) is what every surface reads to
  label these speed records **uncertified** (docs/presentation.md).
* **No accelerometer.** So no pump strokes, no failed takeoff attempts, no
  accelerometer-confirmed touchdowns — `pump.py` and `takeoff.py` already degrade to their
  speed-only paths on a source without `RawTrack.accel`, and nothing new is needed here.
* **No developer fields.** Nothing of ours ever reached a GPX, so there is no watch
  summary to diverge from and no discipline tag to read.

**Speed derivation.** Positions are projected with `filters.py`'s own local-meter
projection (equirectangular about the track's mean latitude) and central-differenced
inside each contiguous run — the same arithmetic `filters._positional_speed` applies to
`pos_mps`, deliberately, so a GPX session's Doppler and positional channels agree instead
of disagreeing by the difference between two ways of measuring the same metres. Haversine
would be marginally more correct over a session's *extent* and no more correct at all over
the one-second steps this reads, which is the only distance it ever measures.

**Segments.** A `<trkseg>` boundary is the recorder saying "I stopped": the two sides are
not one continuous motion, and a speed differentiated across the join would be a fiction.
Each segment is differentiated on its own and the join is marked `gap_before`, which
`filters.clean` ORs into its dt-aware gap rule — so the break survives even when the clock
happens to be continuous across it, which is the one case the dt rule alone cannot see.

**Multiple tracks.** A `<gpx>` may hold several `<trk>`s. They are separate activities,
not segments of one, so the first is analysed and the count is reported in
`session["gpxTracks"]` for a caller that wants to say "this file held 3 tracks; showing
the first".

**Time zone.** GPX timestamps are ISO 8601 and usually `Z`. `Z` is a statement about the
*instant* and none at all about the rider's clock, so it yields no offset and the
longitude fallback takes over — the same resolution ladder engine 0.8.2 built for FITs,
shared as `parse.resolve_utc_offset`. A timestamp written with a numeric offset (`+02:00`)
*is* the exporter telling us the local clock, and wins over the guess. Which rung answered
is recorded (`RawTrack.start_utc_offset_source`, engine 0.9.1), and this format is why it
had to be: for a GPX the guess is the *normal* case, and it is a solar guess an hour out
under DST — a page that prints it as "times as recorded on the water" is over-claiming.

Fail-soft like the FIT parser: a `trkpt` without a time cannot be placed on the timeline
and is skipped; a malformed number is dropped rather than raised on.
"""

from __future__ import annotations

import math
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd

from .filters import M_PER_DEG_LAT, M_PER_DEG_LON_EQ
from .parse import RawTrack, SourceCapabilities, resolve_utc_offset

#: Garmin's per-point extension, the one place a GPX may carry heart rate. Matched on the
#: local tag name (`hr`) so both TrackPointExtension v1 and v2 — and the handful of
#: exporters that write the element unqualified — are read by the same code.
HR_TAGS = {"hr", "heartrate"}


def parse_gpx(path: str | Path) -> RawTrack:
    """GPX 1.1 file -> `RawTrack`, shaped exactly as `parse.parse_fit` shapes a FIT."""
    path = Path(path)
    root = ET.parse(path).getroot()
    return _track_from_root(root, str(path))


def parse_gpx_bytes(data: bytes, path: str = "<gpx>") -> RawTrack:
    """Same, from bytes — the browser and the share sheet never have a file path."""
    return _track_from_root(ET.fromstring(data), path)


def is_gpx(data: bytes) -> bool:
    """Cheap content sniff: does this blob look like GPX rather than FIT?

    Byte-level rather than extension-level because the callers that matter (a dropped
    file, an archived original, a ZIP member) all have bytes and only sometimes have a
    trustworthy name. Only the first 512 bytes are examined — enough for the XML
    declaration, any byte-order mark, a comment or two and the root element.
    """
    head = data[:512].lstrip(b"\xef\xbb\xbf \t\r\n")
    if not head.startswith(b"<"):
        return False
    return b"<gpx" in data[:2048].lower()


# ------------------------------------------------------------------------- internals


def _local(tag: str) -> str:
    """`{http://www.topografix.com/GPX/1/1}trkpt` -> `trkpt`.

    Namespace-blind on purpose: GPX 1.0 and 1.1 differ in their namespace URI, Garmin's
    extensions live in two more, and every exporter picks its own prefixes. Nothing this
    parser reads is ambiguous by local name.
    """
    return tag.rsplit("}", 1)[-1] if "}" in tag else tag


def _find_all(el: ET.Element, name: str) -> list[ET.Element]:
    return [c for c in el if _local(c.tag) == name]


def _track_from_root(root: ET.Element, path: str) -> RawTrack:
    trks = _find_all(root, "trk")
    segments: list[list[dict]] = []
    offsets: list[int] = []
    for seg in (_find_all(trks[0], "trkseg") if trks else []):
        rows, segment_offsets = _segment_points(seg)
        if rows:
            segments.append(rows)
            offsets.extend(segment_offsets)

    session: dict = {"gpxTracks": len(trks), "gpxSegments": len(segments)}
    name = next((n.text for n in _find_all(trks[0], "name") if n.text), None) if trks else None
    if name:
        session["gpxName"] = name.strip()

    df = _frame(segments)
    caps = SourceCapabilities(
        # has_speed stays False: `speed_mps` below is *derived*, and the flag is the
        # file's claim, not the analysis's. This is what makes the session class (c).
        has_speed=False,
        has_position=bool(len(df)),
        has_hr=bool(len(df)) and "heart_rate" in df and bool(df["heart_rate"].notna().any()),
    )
    if len(df) > 1:
        dt = df["t"].diff().dropna()
        med = float(dt.median()) if not dt.empty else 0.0
        caps.sample_rate_hz = round(1.0 / med, 3) if med > 0 else 0.0
    if len(df):
        session["total_elapsed_time"] = round(float(df["t"].iloc[-1] - df["t"].iloc[0]), 3)

    # The same ladder the FIT parser climbs (`parse.resolve_utc_offset`), entered one rung
    # lower: a GPX's own `<time>` is the file stating the offset, exactly as a FIT's
    # `activity` message does, and most GPX files state none — which is why the honest
    # source label matters more here than anywhere (engine 0.9.1).
    offset, source = resolve_utc_offset(_declared_offset(offsets), df, caps)
    return RawTrack(path=path, records=df, laps=[], session=session, capabilities=caps,
                    accel=None, start_utc_offset_s=offset, start_utc_offset_source=source)


def _declared_offset(offsets: list[int]) -> int | None:
    """The local UTC offset the file *stated*, or None when it only stated instants.

    A `Z` timestamp contributes nothing (it is UTC, which is not a claim about the rider's
    clock) and is filtered out before this is called. Among what remains the first point's
    offset wins: a session that crosses a DST boundary or a zone would otherwise have no
    single answer, and the clock a session is read on is the one it *started* on — the
    same rule `activity.local_timestamp` encodes for a FIT.
    """
    return offsets[0] if offsets else None


def _segment_points(seg: ET.Element) -> tuple[list[dict], list[int]]:
    """One `<trkseg>` -> its usable points, plus every explicitly stated UTC offset."""
    rows: list[dict] = []
    offsets: list[int] = []
    for pt in _find_all(seg, "trkpt"):
        lat, lon = _num(pt.get("lat")), _num(pt.get("lon"))
        if lat is None or lon is None:
            continue
        when, offset = _point_time(pt)
        if when is None:
            # No clock, no timeline: every phase of the analysis is a function of time, so
            # a point that cannot say when it happened is not a degraded sample, it is not
            # a sample. (Route/waypoint-style GPX files are exactly this, whole.)
            continue
        if offset is not None:
            offsets.append(offset)
        row = {"timestamp": when, "lat": lat, "lon": lon}
        ele = _child_num(pt, "ele")
        if ele is not None:
            row["altitude"] = ele
        hr = _hr(pt)
        if hr is not None:
            row["heart_rate"] = hr
        rows.append(row)
    rows.sort(key=lambda r: r["timestamp"])
    # Two points on the same second are one point recorded twice: keeping both would put a
    # zero in the denominator of the very difference this module exists to compute.
    deduped, seen = [], set()
    for row in rows:
        if row["timestamp"] in seen:
            continue
        seen.add(row["timestamp"])
        deduped.append(row)
    return deduped, offsets


def _point_time(pt: ET.Element) -> tuple[datetime | None, int | None]:
    """`<time>` -> (aware UTC datetime, stated local offset in seconds or None)."""
    raw = next((c.text for c in _find_all(pt, "time") if c.text), None)
    if not raw:
        return None, None
    text = raw.strip()
    try:
        when = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None, None
    if when.tzinfo is None:                       # naive: the exporter meant UTC (GPX says so)
        return when.replace(tzinfo=timezone.utc), None
    # `Z` is an instant, not a clock. `+00:00` spelled out is a clock that happens to be
    # UTC — the difference is what the exporter was willing to say, and the ladder honours it.
    stated = None if text.endswith(("Z", "z")) else int(when.utcoffset().total_seconds())
    return when.astimezone(timezone.utc), stated


def _hr(pt: ET.Element) -> float | None:
    """Heart rate from `<extensions>`, at any depth, under any prefix."""
    for ext in _find_all(pt, "extensions"):
        for el in ext.iter():
            if _local(el.tag).lower() in HR_TAGS:
                v = _num(el.text)
                if v is not None:
                    return v
    return None


def _child_num(el: ET.Element, name: str) -> float | None:
    return next((v for v in (_num(c.text) for c in _find_all(el, name)) if v is not None), None)


def _num(text) -> float | None:
    if text is None:
        return None
    try:
        v = float(str(text).strip())
    except (TypeError, ValueError):
        return None
    return v if math.isfinite(v) else None


def _frame(segments: list[list[dict]]) -> pd.DataFrame:
    """Segments -> the record frame, with `t`, derived `speed_mps` and the segment joins.

    Every column the rest of the lab reads off a FIT's record frame is present with the
    same name and the same units; the ones a GPX cannot fill (`distance`, the developer
    fields) are simply absent, which is what every consumer already tests for.
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

    lat = df["lat"].to_numpy(float)
    lon = df["lon"].to_numpy(float)
    lat0, lon0 = float(np.mean(lat)), float(np.mean(lon))
    x = (lon - lon0) * math.cos(math.radians(lat0)) * M_PER_DEG_LON_EQ
    y = (lat - lat0) * M_PER_DEG_LAT

    speed = np.full(len(df), np.nan)
    gap = np.zeros(len(df), dtype=bool)
    start = 0
    for seg in segments:
        stop = start + len(seg)
        speed[start:stop] = _segment_speed(df["t"].to_numpy(float)[start:stop],
                                           x[start:stop], y[start:stop])
        if start:
            gap[start] = True          # the join: two recordings, not one motion
        start = stop
    df["speed_mps"] = speed
    df["gap_before"] = gap
    for c in ("altitude", "heart_rate"):
        if c not in df.columns:
            df[c] = np.nan
    return df[columns]


def _segment_speed(t: np.ndarray, x: np.ndarray, y: np.ndarray) -> np.ndarray:
    """Central difference inside one contiguous run, one-sided at its two ends.

    Byte-for-byte the arithmetic of `filters._positional_speed`, on purpose: this is the
    channel that will *become* `doppler_mps`, and a GPX whose two speed channels disagreed
    would have the maneuver detector and the record windows reading different sessions.
    A one-sample segment yields NaN and is dropped by `filters.clean`.
    """
    n = len(t)
    out = np.full(n, np.nan)
    if n < 2:
        return out
    out[0] = math.hypot(x[1] - x[0], y[1] - y[0]) / (t[1] - t[0])
    out[-1] = math.hypot(x[-1] - x[-2], y[-1] - y[-2]) / (t[-1] - t[-2])
    if n >= 3:
        span = t[2:] - t[:-2]
        out[1:-1] = np.hypot(x[2:] - x[:-2], y[2:] - y[:-2]) / span
    out[~np.isfinite(out)] = np.nan     # a repeated instant divides by zero; NaN drops the row
    return out
