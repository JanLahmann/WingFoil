"""Browser entry point: recording bytes (FIT or GPX) -> analysis JSON. Runs inside Pyodide.

This is the *only* code the web app adds on the Python side. Every number it reports comes
from `wingfoil_lab` unchanged — `goldens.analyze()` + `goldens.build_golden()` are the same
calls `tools/make_goldens.py` uses, so the browser output is byte-identical to
`fixtures/goldens/<stem>.expected.json` for the same file. There is no second engine here.

On top of the golden document it adds a `view` block: the geometry the SVG renderer needs
(projected track, per-sample speeds, marker positions). Nothing in `view` is a new metric —
it is the same arrays the lab's `plot_turns.py` draws from.

It is deliberately importable and testable outside the browser:

    PYTHONPATH=web/lab_bundle python -c "import web_entry; ..."
"""

from __future__ import annotations

import gzip
import io
import json
import math
import os
import tempfile
import zipfile

import numpy as np

from wingfoil_lab import ENGINE_VERSION
from wingfoil_lab.filters import hybrid_speed
from wingfoil_lab.flightend import UNKNOWN
from wingfoil_lab.goldens import analyze, build_golden
from wingfoil_lab.parse import MPS_TO_KN
from wingfoil_lab.turns import JIBE, TACK

SCHEMA = 1
MAX_VIEW_SAMPLES = 20000        # a 6 h session at 1 Hz is ~21 600; decimate beyond this


# --------------------------------------------------------------------------- input


def _as_bytes(data) -> bytes:
    """Accept bytes / bytearray / memoryview / a JS Uint8Array proxy / a list of ints."""
    if isinstance(data, (bytes, bytearray, memoryview)):
        return bytes(data)
    to_py = getattr(data, "to_py", None)         # Pyodide JsProxy
    if to_py is not None:
        return bytes(to_py())
    return bytes(data)


def _unzip(raw: bytes) -> tuple[bytes, str | None]:
    """A .zip holding exactly one recording (what intervals.icu and Garmin exports give)."""
    with zipfile.ZipFile(io.BytesIO(raw)) as zf:
        fits = [n for n in zf.namelist()
                if n.lower().endswith((".fit", ".gpx")) and not n.startswith("__MACOSX/")]
        if not fits:
            raise ValueError("zip contains no .fit or .gpx file")
        if len(fits) > 1:
            raise ValueError(f"zip contains {len(fits)} recordings; expected exactly one")
        return zf.read(fits[0]), os.path.basename(fits[0])


def _is_gpx(raw: bytes) -> bool:
    """Content sniff, mirroring `wingfoil_lab.gpx.is_gpx`."""
    head = raw[:512].lstrip(b"\xef\xbb\xbf \t\r\n")
    return head.startswith(b"<") and b"<gpx" in raw[:2048].lower()


def analyze_bytes(data, name: str = "session.fit") -> dict:
    """Recording bytes -> the full result document (plain Python dict).

    FIT, GPX (engine 0.9.0), or a zip holding exactly one of either. Which it is comes off
    the bytes, not the name: a browser hands us whatever the rider dragged in, and the two
    formats have unmistakable signatures — `.FIT` at byte 8, a `<gpx` root element.
    """
    raw = _as_bytes(data)
    inner = None
    if raw[:2] == b"\x1f\x8b":          # intervals.icu /file sometimes hands back gzip
        raw = gzip.decompress(raw)
    if raw[:2] == b"PK":
        raw, inner = _unzip(raw)
    gpx = _is_gpx(raw)
    if not gpx and (len(raw) < 14 or raw[8:12] != b".FIT"):
        raise ValueError("not a FIT or GPX file (no .FIT signature, no <gpx> root)")

    suffix = ".gpx" if gpx else ".fit"
    tmpdir = tempfile.mkdtemp(prefix="wingfoil-")
    fallback = name if name.lower().endswith(suffix) else f"session{suffix}"
    path = os.path.join(tmpdir, inner or fallback)
    try:
        with open(path, "wb") as fh:
            fh.write(raw)
        a = analyze(path)
        return {
            "schema": SCHEMA,
            "engineVersion": ENGINE_VERSION,
            "file": {"name": inner or name, "bytes": len(raw),
                     "container": "zip" if inner else suffix.lstrip(".")},
            "meta": _meta(a),
            "golden": build_golden(a),
            "view": _view(a),
        }
    finally:
        for f in os.listdir(tmpdir):
            os.remove(os.path.join(tmpdir, f))
        os.rmdir(tmpdir)


def analyze_json(data, name: str = "session.fit") -> str:
    """Same as `analyze_bytes`, serialized — the shape the worker posts to the UI."""
    return json.dumps(analyze_bytes(data, name), allow_nan=False)


# --------------------------------------------------------------------------- meta


def _meta(a) -> dict:
    """Session identity + the watch's own session-level dev fields (docs/fit-schema.md)."""
    caps = a.track.capabilities
    s = a.track.session
    df = a.track.records
    start = None
    if not df.empty and "timestamp" in df.columns:
        ts = df["timestamp"].iloc[0]
        start = ts.isoformat()
    wind_user = _num(s.get("wind_dir_user"))
    if wind_user is not None and wind_user >= 65535:     # FIT uint16 "unset" sentinel
        wind_user = None
    # Session field 44, device app >= 0.9.0: the axis the WATCH estimated for itself
    # (docs/algorithms.md "Watch approximation: auto wind"). Kept apart from the rider's own
    # bearing above because one is a statement and the other an inference — the tile marks the
    # estimate with a "~", exactly as the watch does.
    wind_auto = _num(s.get("wind_dir_auto"))
    if wind_auto is not None and wind_auto >= 65535:
        wind_auto = None
    app_version = _num(s.get("app_version"))
    return {
        "startUtc": start,          # UTC — the instant; `utcOffsetS` says how to read it
        # The session's own UTC offset in seconds (engine 0.8.2). Every clock the page
        # prints is `startUtc` shifted by this, so a session reads the way the rider's
        # watch read it — not the way the reader's laptop happens to be set today. Null
        # when the file carries neither an `activity` message nor a GPS fix; the page then
        # falls back to the reader's own zone and says so.
        "utcOffsetS": a.track.start_utc_offset_s,
        "durationS": _num(s.get("total_elapsed_time")),
        "timerTimeS": _num(s.get("total_timer_time")) or round(a.clean.timer_time_s, 1),
        "samples": int(len(df)),
        "sourceClass": caps.source_class,
        "sport": caps.sport,
        "subSport": caps.sub_sport,
        "discipline": caps.discipline,
        "windDirUserDeg": wind_user,
        "windDirAutoDeg": wind_auto,
        "appVersion": None if app_version is None else int(app_version),
        "schemaVersion": None if app_version is None else int(app_version) & 0xFF,
        "avgHr": _num(s.get("avg_heart_rate")),
        "maxHr": _num(s.get("max_heart_rate")),
        "calories": _num(s.get("total_calories")),
        "laps": len(a.track.laps),
        "medianDtS": round(a.clean.median_dt_s, 3),
        "droppedGate": a.clean.dropped_gate,
        "droppedNan": a.clean.dropped_nan,
        "droppedSpike": a.clean.dropped_spike,
    }


def _num(v):
    if v is None:
        return None
    try:
        f = float(v)
    except (TypeError, ValueError):
        return None
    return None if not math.isfinite(f) else round(f, 3)


# --------------------------------------------------------------------------- view


def _view(a) -> dict:
    """Geometry for the SVG map + speed strip. Same arrays lab/tools/plot_turns.py plots.

    A track with no GPS fixes at all (Doppler-only sources, or a FIT whose records carry
    speed but no lat/lon) has an all-NaN projection. There is no map to draw for it, and a
    NaN would take the whole document down with `json.dumps(allow_nan=False)`, so the
    positional half of the view is simply dropped: `hasPositions` is false, the `x`/`y`
    arrays are empty, the map corners of `bounds` are null and the markers carry no
    coordinates. Everything the speed strip and the tables need is time-series data and
    stays exactly as it is.
    """
    df = a.clean.records
    if df.empty:
        return {"count": 0, "hasPositions": False, "t": [], "x": [], "y": [],
                "speedKn": [], "dopplerKn": [], "segment": [], "bounds": None,
                "flights": [], "turnMarkers": [], "endMarkers": [], "stride": 1}

    t = df["t"].to_numpy(float)
    x = df["x"].to_numpy(float)
    y = df["y"].to_numpy(float)
    seg = df["segment"].to_numpy(int)
    hyb = hybrid_speed(df) * MPS_TO_KN
    dop = df["doppler_mps"].to_numpy(float) * MPS_TO_KN
    has_pos = bool(np.isfinite(x).any() and np.isfinite(y).any())

    stride = max(1, int(math.ceil(len(t) / MAX_VIEW_SAMPLES)))
    sl = slice(None, None, stride)

    return {
        "count": int(len(t[sl])),
        "stride": stride,
        "hasPositions": has_pos,
        "t": _round_list(t[sl], 1),
        "x": _round_list(x[sl], 1) if has_pos else [],
        "y": _round_list(y[sl], 1) if has_pos else [],
        "speedKn": _round_list(hyb[sl], 2),
        "dopplerKn": _round_list(dop[sl], 2),
        "segment": [int(v) for v in seg[sl]],
        "bounds": {"x0": _extent(np.nanmin, x), "x1": _extent(np.nanmax, x),
                   "y0": _extent(np.nanmin, y), "y1": _extent(np.nanmax, y),
                   "t0": round(float(t[0]), 1), "t1": round(float(t[-1]), 1),
                   "knMax": _extent(np.nanmax, np.maximum(hyb, dop), 2) or 0.0},
        "flights": [{"startTs": round(f.start_t, 1), "endTs": round(f.end_t, 1)}
                    for f in a.flights.flights],
        "turnMarkers": [_turn_marker(i, turn, t, x, y) for i, turn in enumerate(a.turns)],
        "endMarkers": [_end_marker(i, e, t, x, y) for i, e in enumerate(a.flight_ends)],
    }


def _extent(fn, arr, places: int = 1):
    """`fn` (a nan-aware reducer) over `arr`, or None when the channel is entirely missing."""
    arr = np.asarray(arr, dtype=float)
    if not np.isfinite(arr).any():
        return None
    return round(float(fn(arr)), places)


def _at(arr, k: int, places: int = 1):
    """Sample `k` of a positional array, or None where there is no fix."""
    v = float(arr[k])
    return round(v, places) if math.isfinite(v) else None


def _turn_marker(i: int, turn, t, x, y) -> dict:
    """Where the numbered turn marker sits: the sample nearest the speed minimum."""
    k = int(np.argmin(np.abs(t - turn.min_t)))
    return {
        "i": i,
        "n": i + 1,
        "t": round(float(turn.min_t), 1),
        "x": _at(x, k),
        "y": _at(y, k),
        "kn": round(float(turn.min_kn), 2),
        "kind": turn.kind,
        "outcome": turn.outcome,
        "counted": bool(turn.counted),
        "maneuver": turn.kind in (TACK, JIBE),
    }


def _end_marker(i: int, end, t, x, y) -> dict:
    """Flight ends; the map only draws the straight-line ones (`inTurn` false, evidence-bearing)."""
    k = int(np.argmin(np.abs(t - end.t)))
    return {
        "i": i,
        "flightIndex": end.flight_index,
        "t": round(float(end.t), 1),
        "x": _at(x, k),
        "y": _at(y, k),
        "kn": round(float(end.min_speed_mps) * MPS_TO_KN, 2)
              if math.isfinite(end.min_speed_mps) else None,
        "outcome": end.outcome,
        "inTurn": bool(end.in_turn),
        "ownedByTurn": end.owned_by_turn,
        "drawOnMap": (not end.in_turn) and end.outcome != UNKNOWN,
    }


def _round_list(arr, places: int) -> list:
    out = []
    for v in np.asarray(arr, dtype=float):
        out.append(None if not math.isfinite(v) else round(float(v), places))
    return out
