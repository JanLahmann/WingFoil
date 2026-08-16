"""Session-library glue: digests, dedupe keys, all-time records, trend series.

The second (and last) piece of hand-written Python the web app adds, next to
`web_entry.py`. It exists so that **the browser never computes a number in JavaScript**.
Everything the library and the trends view show — the dedupe key, the per-session summary
row, the all-time record winners, every trend point, the port/starboard split — is derived
here, in CPython, from the analysis document `web_entry.analyze_bytes()` produced. The JS
side stores bytes, orchestrates and draws; it does not aggregate.

Four entry points, all also usable outside the browser (that is how they are tested):

    digest(doc, file_name)        analysis document -> the compact record the library stores
    dedupe_match(new, existing)   is this session already in the library?
    aggregate(digests)            records + trends over the whole library
    export_begin/add/finish       "download everything" as a zip, via CPython's `zipfile`

`digest` is a *projection* of the analysis JSON, not a second engine: every field it
carries is copied or counted straight out of `golden`/`meta`. The library keeps the full
analysis JSON on disk as well — opening a stored session re-renders that document
verbatim, with no Pyodide run at all — but records and trends read the digests, because
loading fifty 200 KB documents to find one maximum would be silly.

    PYTHONPATH=web/lab_bundle python -c "import library; ..."
"""

from __future__ import annotations

import hashlib
import json
import math
import os
import re
import zipfile
from datetime import datetime, timezone

SCHEMA = 1

# The project-wide "same session" rule, in one place: a session start within +/-60 s AND a
# duration within +/-60 s of an existing entry is the same session recorded twice (watch
# export vs intervals.icu re-encode, a re-download, a trimmed copy). Both bounds are
# inclusive: exactly 60 s still matches, 61 s does not.
DEDUPE_START_S = 60.0
DEDUPE_DURATION_S = 60.0

# The GP3S record kinds, in the order the records table shows them. The second element is
# the key under `golden.records.windows` that says *where* in the session the record was
# set, so the UI can open the session with that window highlighted. `bestHour` has no
# window in the golden (it is a whole-session rollup), hence None.
RECORD_KINDS = [
    ("best2sKn", "best2s", "Best 2 s", "kn"),
    ("best10sKn", "best10s", "Best 10 s", "kn"),
    ("best5x10sKn", "best5x10s", "Best 5×10 s", "kn"),
    ("best100mKn", "best100m", "Best 100 m", "kn"),
    ("best250mKn", "best250m", "Best 250 m", "kn"),
    ("best500mKn", "best500m", "Best 500 m", "kn"),
    ("bestNmKn", "bestNm", "Best 1 NM", "kn"),
    ("bestHourKn", None, "Best hour", "kn"),
    ("alpha500Kn", "alpha500", "Alpha 500", "kn"),
]

SIDES = ("port", "starboard")


# --------------------------------------------------------------------------- helpers


def _num(v, places: int | None = None):
    """Anything -> a finite float (optionally rounded), or None. Never raises."""
    if v is None or isinstance(v, bool):
        return None
    try:
        f = float(v)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(f):
        return None
    return f if places is None else round(f, places)


def _epoch(iso: str | None):
    """ISO-8601 UTC timestamp -> POSIX seconds, or None if it is missing/unparseable."""
    if not iso:
        return None
    text = str(iso).strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.timestamp()


def _as_doc(doc):
    return json.loads(doc) if isinstance(doc, (str, bytes, bytearray)) else doc


_DATE_STAMP = re.compile(r"^\d{4}-\d{2}-\d{2}(-\d{3,4})?$")
_SOURCE_TOKEN = re.compile(
    r"^(ciq|native|wingfoiling|foilmotion|speedreader|garmin|export|orig|original|raw|fit)$",
    re.IGNORECASE,
)


def spot_name(file_name: str) -> str:
    """A spot-ish label out of the corpus filename convention.

    `2026-08-07-0754_nago-torbole-windsurfen_ciq.fit` -> `Nago Torbole Windsurfen`.
    Filenames that do not follow the convention are simply tidied, never rejected.
    """
    stem = re.sub(r"\.(fit|zip|gz|json)$", "", str(file_name or ""), flags=re.IGNORECASE)
    stem = re.sub(r"\.analysis$", "", stem, flags=re.IGNORECASE)
    parts = [p for p in stem.split("_") if p]
    if parts and _DATE_STAMP.match(parts[0]):
        parts = parts[1:]
    if len(parts) > 1 and _SOURCE_TOKEN.match(parts[-1]):
        parts = parts[:-1]
    text = " ".join(parts).replace("-", " ")
    text = re.sub(r"\s+", " ", text).strip()
    if not text:
        return "Session"
    return " ".join(w[:1].upper() + w[1:] for w in text.split(" "))


def _session_id(start_epoch, duration_s, file_name: str) -> str:
    """A stable, filesystem-safe id. Two *copies* of one session get different ids —
    ids identify a stored file, `dedupe_match` identifies the session."""
    if start_epoch is not None and duration_s is not None:
        return f"s{int(start_epoch)}-{int(round(duration_s))}"
    tag = hashlib.sha1(str(file_name).encode("utf-8")).hexdigest()[:10]
    return f"x{tag}-{int(round(duration_s or 0))}"


# --------------------------------------------------------------------------- digest


def _duration(doc) -> float | None:
    """Elapsed session duration in seconds, with the fallbacks a degraded source needs."""
    meta = doc.get("meta") or {}
    for key in ("durationS", "timerTimeS"):
        v = _num(meta.get(key))
        if v:
            return v
    bounds = ((doc.get("view") or {}).get("bounds")) or {}
    t0, t1 = _num(bounds.get("t0")), _num(bounds.get("t1"))
    if t0 is not None and t1 is not None and t1 > t0:
        return t1 - t0
    return None


def _turn_split(turns) -> dict:
    """Counted turns grouped by the tack they were *entered* on.

    `golden.summary.turns` already publishes the port/starboard entry counts, but not the
    success split, which is the whole point of the trend. Counting it here keeps the split
    on the same `counted`/`success` definitions the rest of the engine uses.
    """
    out = {s: {"entries": 0, "successes": 0, "successPct": None} for s in SIDES}
    out["unknown"] = {"entries": 0, "successes": 0, "successPct": None}
    for t in turns or []:
        if not t.get("counted"):
            continue
        side = t.get("side")
        bucket = out[side] if side in out else out["unknown"]
        bucket["entries"] += 1
        if t.get("success"):
            bucket["successes"] += 1
    for bucket in out.values():
        if bucket["entries"]:
            bucket["successPct"] = round(100.0 * bucket["successes"] / bucket["entries"], 2)
    return out


def _windows(rec: dict, window_key: str | None) -> list:
    """Record provenance as a uniform list of {startTs, durS} — 5x10 s has five."""
    if not window_key:
        return []
    w = (rec.get("windows") or {}).get(window_key)
    if w is None:
        return []
    items = w if isinstance(w, list) else [w]
    out = []
    for item in items:
        if not isinstance(item, dict):
            continue
        start, dur = _num(item.get("startTs")), _num(item.get("durS"))
        if start is None or dur is None:
            continue
        out.append({"startTs": start, "durS": dur})
    return out


def digest(doc, file_name: str | None = None) -> dict:
    """Analysis document (dict or JSON text) -> the compact entry the library stores."""
    doc = _as_doc(doc)
    g = doc.get("golden") or {}
    meta = doc.get("meta") or {}
    summ = g.get("summary") or {}
    turns = summ.get("turns") or {}
    takeoff = summ.get("takeoff") or {}
    rec = g.get("records") or {}
    caps = g.get("capabilities") or {}
    wind = g.get("wind") or None

    name = file_name or (doc.get("file") or {}).get("name") or "session.fit"
    start_utc = meta.get("startUtc")
    start_epoch = _epoch(start_utc)
    duration_s = _duration(doc)

    return {
        "schema": SCHEMA,
        "id": _session_id(start_epoch, duration_s, name),
        "engineVersion": doc.get("engineVersion"),
        "fileName": name,
        "spot": spot_name(name),
        # --- the dedupe key, and only these two fields ---
        "startUtc": start_utc,
        "startEpoch": None if start_epoch is None else round(start_epoch, 3),
        "durationS": _num(duration_s, 1),
        # --- the library row ---
        "dateUtc": (str(start_utc)[:10] if start_utc else None),
        "distanceKm": _num(summ.get("distanceKm")),
        "foilPct": _num(summ.get("foilPct")),
        "foilTimeS": _num(summ.get("foilTimeS")),
        "flightCount": int(summ.get("flightCount") or 0),
        "longestFlightS": _num(summ.get("longestFlightS")),
        "longestFlightM": _num(summ.get("longestFlightM")),
        "sourceClass": meta.get("sourceClass"),
        "discipline": meta.get("discipline"),
        "sport": meta.get("sport"),
        "hasAccel": bool(caps.get("hasAccel")),
        "hasHR": bool(caps.get("hasHR")),
        "windDirDeg": _num((wind or {}).get("dirDeg")) if wind else None,
        # --- what records + trends read ---
        "records": {key: _num(rec.get(key)) for key, _w, _l, _u in RECORD_KINDS},
        "recordWindows": {key: _windows(rec, wkey) for key, wkey, _l, _u in RECORD_KINDS},
        "turns": {
            "counted": int(turns.get("turnsCounted") or 0),
            "successful": int(turns.get("turnsSuccessful") or 0),
            "successPct": _num(turns.get("successPct")),
            "jibes": int(turns.get("jibes") or 0),
            "tacks": int(turns.get("tacks") or 0),
            "bySide": _turn_split(g.get("turns")),
        },
        "takeoff": {
            "attempts": int(takeoff.get("takeoffAttempts") or 0),
            "successes": int(takeoff.get("takeoffSuccesses") or 0),
            "successPct": _num(takeoff.get("successPct")),
            "avgPumpsToTakeoff": _num(takeoff.get("avgPumpsToTakeoff")),
            "avgTakeoffS": _num(takeoff.get("avgTakeoffS")),
        },
    }


def digest_json(doc_json: str, file_name: str | None = None) -> str:
    """`digest`, JSON in / JSON out — the shape the worker posts to the UI."""
    return json.dumps(digest(doc_json, file_name), allow_nan=False)


# --------------------------------------------------------------------------- dedupe


def is_same_session(a: dict, b: dict) -> bool:
    """The project's session-identity rule: start within +/-60 s AND duration within
    +/-60 s. Both bounds inclusive. An entry with no usable start never matches anything
    — silently merging two sessions is worse than storing one twice."""
    a_start, b_start = _num(a.get("startEpoch")), _num(b.get("startEpoch"))
    a_dur, b_dur = _num(a.get("durationS")), _num(b.get("durationS"))
    if a_start is None or b_start is None or a_dur is None or b_dur is None:
        return False
    return (abs(a_start - b_start) <= DEDUPE_START_S
            and abs(a_dur - b_dur) <= DEDUPE_DURATION_S)


def dedupe_match(new: dict, existing) -> dict:
    """Is `new` already in the library? -> {match: bool, index, id, deltaStartS, deltaDurS}.

    The closest match wins if several entries qualify, so a replace always lands on the
    nearest recording rather than the first one stored.
    """
    new = _as_doc(new)
    entries = _as_doc(existing) or []
    best = None
    for i, other in enumerate(entries):
        if not isinstance(other, dict) or not is_same_session(new, other):
            continue
        d_start = abs(_num(new.get("startEpoch")) - _num(other.get("startEpoch")))
        d_dur = abs(_num(new.get("durationS")) - _num(other.get("durationS")))
        cand = (d_start + d_dur, i, other, d_start, d_dur)
        if best is None or cand[0] < best[0]:
            best = cand
    if best is None:
        return {"match": False, "index": None, "id": None,
                "deltaStartS": None, "deltaDurS": None}
    _score, i, other, d_start, d_dur = best
    return {"match": True, "index": i, "id": other.get("id"),
            "fileName": other.get("fileName"),
            "deltaStartS": round(d_start, 1), "deltaDurS": round(d_dur, 1)}


def dedupe_match_json(new_json: str, existing_json: str) -> str:
    return json.dumps(dedupe_match(new_json, existing_json), allow_nan=False)


# ------------------------------------------------------------------ records + trends


def _sorted(digests) -> list:
    ds = [d for d in (_as_doc(digests) or []) if isinstance(d, dict)]
    ds.sort(key=lambda d: (d.get("startEpoch") is None,
                           _num(d.get("startEpoch")) or 0.0,
                           str(d.get("id") or "")))
    return ds


def _stamp(d: dict) -> dict:
    """The bit of a digest every records row / trend point needs to name its session."""
    return {"id": d.get("id"), "fileName": d.get("fileName"), "spot": d.get("spot"),
            "startUtc": d.get("startUtc"), "dateUtc": d.get("dateUtc")}


def _records(ds: list) -> list:
    """All-time best per GP3S kind, with the session and the window it came from.

    Ties go to the *earliest* session — the record was set then, not re-set later.
    A kind nobody has a positive value for is dropped rather than shown as a dash.
    """
    out = []
    for key, _wkey, label, unit in RECORD_KINDS:
        best = None
        for d in ds:                                  # ds is already oldest-first
            v = _num((d.get("records") or {}).get(key))
            if v is None or v <= 0:
                continue
            if best is None or v > best[0]:
                best = (v, d)
        if best is None:
            continue
        value, d = best
        row = {"key": key, "label": label, "unit": unit, "value": round(value, 3),
               "windows": (d.get("recordWindows") or {}).get(key) or []}
        row.update(_stamp(d))
        out.append(row)
    return out


def _points(ds: list, pick) -> list:
    pts = []
    for i, d in enumerate(ds):
        v = pick(d)
        pts.append({"i": i, "id": d.get("id"), "v": None if v is None else round(v, 3)})
    return pts


def _y_axis(charts_lines, percent: bool) -> dict:
    """The chart's y domain and gridline step.

    Axis scaling is arithmetic over the data, so it belongs here rather than in the
    renderer — the SVG code should place ticks, not decide where they go. Percentages get
    a fixed 0-100 domain so the eye can compare two sessions across two charts; anything
    else gets a 1/2/2.5/5 x 10^k step chosen for four to six gridlines.
    """
    values = [p["v"] for line in charts_lines for p in line["points"] if p["v"] is not None]
    top = max(values) if values else 0.0
    if percent:
        return {"yMax": 100.0, "yStep": 25.0}
    if top <= 0:
        return {"yMax": 1.0, "yStep": 0.5}
    raw = top / 5.0
    power = 10.0 ** math.floor(math.log10(raw))
    for mult in (1.0, 2.0, 2.5, 5.0, 10.0):
        step = mult * power
        if step >= raw:
            break
    return {"yMax": round(math.ceil(top / step) * step, 6), "yStep": round(step, 6)}


def _side_pct(d: dict, side: str):
    by = ((d.get("turns") or {}).get("bySide") or {}).get(side) or {}
    return _num(by.get("successPct"))


def _trends(ds: list) -> dict:
    """Per-session series, oldest first. One `charts` entry == one SVG in the UI.

    `role` is a drawing hint, not data: the renderer maps primary/secondary onto the two
    blues the speed strip already uses, and the second line is dashed as well as tinted so
    the split chart survives a CVD check without a second hue.
    """
    charts = _charts(ds)
    for c in charts:
        c.update(_y_axis(c["lines"], bool(c.get("percent"))))
    return {"sessions": [_stamp(d) for d in ds], "charts": charts}


def _charts(ds: list) -> list:
    return [
        {"key": "foilPct", "label": "On foil", "unit": "%", "percent": True,
         "lines": [{"key": "foilPct", "label": "on foil", "role": "primary",
                    "points": _points(ds, lambda d: _num(d.get("foilPct")))}]},
        {"key": "longestFlight", "label": "Longest flight", "unit": "s",
         "lines": [{"key": "longestFlightS", "label": "longest flight", "role": "primary",
                    "points": _points(ds, lambda d: _num(d.get("longestFlightS")))}]},
        {"key": "turnSuccess", "label": "Turn success rate", "unit": "%", "percent": True,
         "lines": [{"key": "successPct", "label": "success rate", "role": "primary",
                    "points": _points(ds, lambda d: _num((d.get("turns") or {}).get("successPct")))}]},
        {"key": "pumps", "label": "Avg pumps to takeoff", "unit": "",
         "lines": [{"key": "avgPumpsToTakeoff", "label": "pumps", "role": "primary",
                    "points": _points(ds, lambda d: _num((d.get("takeoff") or {}).get("avgPumpsToTakeoff")))}]},
        {"key": "turnSide", "label": "Turn success by entry tack", "unit": "%", "percent": True,
         "lines": [
             {"key": "port", "label": "port entry", "role": "primary",
              "points": _points(ds, lambda d: _side_pct(d, "port"))},
             {"key": "starboard", "label": "starboard entry", "role": "secondary",
              "points": _points(ds, lambda d: _side_pct(d, "starboard"))},
         ]},
    ]


def _on_water_s(d: dict):
    """The denominator the engine itself used for this session's `foilPct`.

    Recovering it (foil time / share) rather than reaching for `durationS` matters: the
    engine divides by its own cleaned timer time, which excludes the gaps and the parked
    stretches that total elapsed time still counts. Summing elapsed time instead would
    quietly report a library-wide on-foil share ~19 points below every session in it.
    """
    foil, pct = _num(d.get("foilTimeS")), _num(d.get("foilPct"))
    if foil is None or not pct:
        return None
    return foil * 100.0 / pct


def _totals(ds: list) -> dict:
    """Library-level rollups. Averages are weighted the way the metric means them:
    on-foil share is total foil time over total on-water time, not the mean of the
    per-session percentages, and the turn rate is successes over turns."""
    dist = sum(_num(d.get("distanceKm")) or 0.0 for d in ds)
    foil = sum(_num(d.get("foilTimeS")) or 0.0 for d in ds)
    on_water = sum(_on_water_s(d) or 0.0 for d in ds)
    elapsed = sum(_num(d.get("durationS")) or 0.0 for d in ds)
    flights = sum(int(d.get("flightCount") or 0) for d in ds)
    counted = sum(int((d.get("turns") or {}).get("counted") or 0) for d in ds)
    ok = sum(int((d.get("turns") or {}).get("successful") or 0) for d in ds)
    by_side = {}
    for side in SIDES:
        e = sum(int((((d.get("turns") or {}).get("bySide") or {}).get(side) or {}).get("entries") or 0)
                for d in ds)
        s = sum(int((((d.get("turns") or {}).get("bySide") or {}).get(side) or {}).get("successes") or 0)
                for d in ds)
        by_side[side] = {"entries": e, "successes": s,
                         "successPct": round(100.0 * s / e, 2) if e else None}
    return {
        "sessions": len(ds),
        "distanceKm": round(dist, 2),
        "foilTimeS": round(foil, 1),
        "onWaterS": round(on_water, 1),
        "elapsedS": round(elapsed, 1),
        "foilPct": round(100.0 * foil / on_water, 2) if on_water else None,
        "flightCount": flights,
        "turnsCounted": counted,
        "turnsSuccessful": ok,
        "turnSuccessPct": round(100.0 * ok / counted, 2) if counted else None,
        "turnsBySide": by_side,
        "firstUtc": ds[0].get("startUtc") if ds else None,
        "lastUtc": ds[-1].get("startUtc") if ds else None,
    }


def aggregate(digests) -> dict:
    """The whole Records & Trends view, in one Python call over the stored digests."""
    ds = _sorted(digests)
    return {"schema": SCHEMA, "count": len(ds), "totals": _totals(ds),
            "records": _records(ds), "trends": _trends(ds)}


def aggregate_json(digests_json: str) -> str:
    return json.dumps(aggregate(digests_json), allow_nan=False)


# ------------------------------------------------------------------- bulk zip export


# "Download everything" without shipping a JavaScript zip library: CPython's own
# `zipfile` is already in the browser. The archive is built member by member so the
# library never has to exist twice in memory, and it is written to the Pyodide
# filesystem — `FS.readFile` hands JavaScript a real Uint8Array, with no base64 hop.
_EXPORT = {"zip": None, "path": None}


def export_begin() -> None:
    export_abort()
    _EXPORT["path"] = "/tmp/wingfoil-export-partial.zip"
    _EXPORT["zip"] = zipfile.ZipFile(_EXPORT["path"], "w")


def _as_bytes(data) -> bytes:
    """bytes / bytearray / memoryview / str / a JS Uint8Array proxy -> bytes."""
    if isinstance(data, (bytes, bytearray, memoryview)):
        return bytes(data)
    if isinstance(data, str):
        return data.encode("utf-8")
    to_py = getattr(data, "to_py", None)             # Pyodide JsProxy
    if to_py is not None:
        return bytes(to_py())
    return bytes(data)


def export_add(name: str, data, deflate: bool = False) -> None:
    """Add one member. FIT files are stored (they do not compress); JSON is deflated."""
    zf = _EXPORT["zip"]
    if zf is None:
        raise RuntimeError("export_add() before export_begin()")
    info = zipfile.ZipInfo(str(name))
    info.compress_type = zipfile.ZIP_DEFLATED if deflate else zipfile.ZIP_STORED
    info.external_attr = 0o644 << 16
    zf.writestr(info, _as_bytes(data))


def export_finish(path: str) -> int:
    """Close the archive at `path` and return its size in bytes."""
    zf = _EXPORT["zip"]
    if zf is None:
        raise RuntimeError("export_finish() before export_begin()")
    zf.close()
    _EXPORT["zip"] = None
    partial = _EXPORT["path"]
    _EXPORT["path"] = None
    os.replace(partial, path)
    return os.path.getsize(path)


def export_abort() -> None:
    """Drop a half-built archive — safe to call at any time."""
    zf, partial = _EXPORT["zip"], _EXPORT["path"]
    _EXPORT["zip"] = _EXPORT["path"] = None
    if zf is not None:
        try:
            zf.close()
        except Exception:                            # noqa: BLE001 - best effort cleanup
            pass
    if partial and os.path.exists(partial):
        os.remove(partial)
