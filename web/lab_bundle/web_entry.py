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

from wingfoil_lab import ENGINE_VERSION, discipline
from wingfoil_lab.filters import hybrid_speed
from wingfoil_lab.flightend import UNKNOWN
from wingfoil_lab.goldens import analyze, build_golden
from wingfoil_lab.parse import MPS_TO_KN
from wingfoil_lab.presentation import (DEFAULT_SPEED_RECORD_POLICY, SPEED_RECORD_POLICIES,
                                       build_presentation)
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


#: Extensions a zipped recording may arrive under. Mirrors `parse.parse_track`'s reach.
RECORDING_SUFFIXES = (".fit", ".gpx", ".tcx")


def _unzip(raw: bytes) -> tuple[bytes, str | None]:
    """A .zip holding exactly one recording (what intervals.icu and Garmin exports give)."""
    with zipfile.ZipFile(io.BytesIO(raw)) as zf:
        fits = [n for n in zf.namelist()
                if n.lower().endswith(RECORDING_SUFFIXES) and not n.startswith("__MACOSX/")]
        if not fits:
            raise ValueError("zip contains no .fit, .gpx or .tcx file")
        if len(fits) > 1:
            raise ValueError(f"zip contains {len(fits)} recordings; expected exactly one")
        return zf.read(fits[0]), os.path.basename(fits[0])


def _sniff(raw: bytes) -> str | None:
    """-> ".fit" | ".gpx" | ".tcx" | None, by content.

    Mirrors `wingfoil_lab.parse.parse_track`'s own three tests, in the same order, and the
    kit's `TrackParser.format`. The suffix it returns is only ever used to name the
    temporary file `analyze` is handed — which then sniffs the bytes again.
    """
    if len(raw) >= 14 and raw[8:12] == b".FIT":
        return ".fit"
    head = raw[:512].lstrip(b"\xef\xbb\xbf \t\r\n")
    if not head.startswith(b"<"):
        return None
    window = raw[:2048].lower()
    if b"<trainingcenterdatabase" in window:
        return ".tcx"
    return ".gpx" if b"<gpx" in window else None


def analyze_bytes(data, name: str = "session.fit",
                  policy: str = DEFAULT_SPEED_RECORD_POLICY) -> dict:
    """Recording bytes -> the full result document (plain Python dict).

    FIT, GPX (engine 0.9.0), TCX, or a zip holding exactly one of them. Which it is comes
    off the bytes, not the name: a browser hands us whatever the rider dragged in, and all
    three formats have unmistakable signatures — `.FIT` at byte 8, a `<gpx` root element, a
    `<TrainingCenterDatabase>` one.

    `policy` is Settings → Speed records, the one rider choice `build_presentation` takes
    (ADR-033). It is **not** the speed unit: the document carries raw knots and a
    `unitKind`, which is what lets one document serve a rider reading knots and a rider
    reading km/h.
    """
    raw = _as_bytes(data)
    inner = None
    if raw[:2] == b"\x1f\x8b":          # intervals.icu /file sometimes hands back gzip
        raw = gzip.decompress(raw)
    if raw[:2] == b"PK":
        raw, inner = _unzip(raw)
    suffix = _sniff(raw)
    if suffix is None:
        raise ValueError("not a FIT, GPX or TCX file (no .FIT signature, no <gpx> or "
                         "<TrainingCenterDatabase> root)")

    tmpdir = tempfile.mkdtemp(prefix="wingfoil-")
    fallback = name if name.lower().endswith(suffix) else f"session{suffix}"
    path = os.path.join(tmpdir, inner or fallback)
    try:
        with open(path, "wb") as fh:
            fh.write(raw)
        # **The preset is read off the recording, and only off the recording.** The web has
        # no per-session settings place to hang an override on (the phone does), so a
        # windsurf session is one whose `discipline` developer field says so. The wingfoil
        # pass runs first and is re-run only when the tag moves the preset — which is never
        # on the corpus, so the common path still parses once.
        a = analyze(path)
        disc = discipline.resolve(a.track.capabilities.discipline)
        if disc is not discipline.Discipline.WINGFOIL:
            a = analyze(path, discipline=disc)
        golden = build_golden(a)
        meta = _meta(a, disc)
        return {
            "schema": SCHEMA,
            "engineVersion": ENGINE_VERSION,
            "file": {"name": inner or name, "bytes": len(raw),
                     "container": "zip" if inner else suffix.lstrip(".")},
            "meta": meta,
            "golden": golden,
            # **Every rider-facing fact of this session, once** (ADR-033, round 3). The
            # browser's renderers read this and derive nothing: the block, the card, the
            # marks, the callouts, the strip and the banner are all formatting over it.
            # It travels *inside* the analysis document rather than beside it so a session
            # re-opened from the library redraws with no Pyodide and no network, which is
            # the promise `openStoredSession` makes.
            "presentation": presentation(golden, meta, policy),
            "view": _view(a),
        }
    finally:
        for f in os.listdir(tmpdir):
            os.remove(os.path.join(tmpdir, f))
        os.rmdir(tmpdir)


def analyze_json(data, name: str = "session.fit",
                 policy: str = DEFAULT_SPEED_RECORD_POLICY) -> str:
    """Same as `analyze_bytes`, serialized — the shape the worker posts to the UI."""
    return json.dumps(analyze_bytes(data, name, policy), allow_nan=False)


# -------------------------------------------------------------- the presentation document


#: `DivergenceCheck.foilTimePctThreshold` / `.recordKnThreshold` / `.countThreshold`
#: (ios/WingFoilKit/.../DivergenceCheck.swift, docs/algorithms/divergence.md). The browser
#: had its own spelling of these three numbers in `web/js/log.js`; the check belongs beside
#: the document it feeds, because the banner and the Log tab's table are two renderers of
#: one line.
DIVERGENCE_FOIL_TIME_PCT = 5.0
DIVERGENCE_RECORD_KN = 0.3
DIVERGENCE_COUNT = 1

#: The six speed records the two devices both claim, in the kit's order. Their names come
#: from `tokens.recordWindow.<id>`, so there is one spelling of `Best 2 s` in the product.
DIVERGENCE_RECORDS = ["best2s", "best10s", "best5x10s", "best500m", "bestNm", "alpha500"]

#: The five counts, in the kit's order. `takeoffs` rather than `takeoffSuccesses`: `success`
#: is engine vocabulary and reaches no rider text (CLAUDE.md).
DIVERGENCE_COUNTS = [
    ("flights", "flightCount", ("flightCount",)),
    ("tacks", "tackCount", ("turns", "tacks")),
    ("jibes", "jibeCount", ("turns", "jibes")),
    ("takeoffAttempts", "takeoffAttempts", ("takeoff", "takeoffAttempts")),
    ("takeoffs", "takeoffSuccesses", ("takeoff", "takeoffSuccesses")),
]


def _dig(tree, path):
    for key in path:
        if not isinstance(tree, dict):
            return None
        tree = tree.get(key)
    return tree


def divergence_lines(golden: dict, watch: dict | None) -> list[dict]:
    """Every watch-vs-phone disagreement worth a line, as the document spells one.

    The Python twin of `DivergenceCheck.compare` and of `Divergence.documentLine`: ids and
    **raw** values, never a sentence and never a formatted number (ADR-033, rules 1 and 2).
    Empty for every recording without the watch's own session fields — which is a different
    answer from "the two agree", and the caller tells them apart by whether `watch` was
    there at all.
    """
    if not watch:
        return []
    summary = golden.get("summary", {})
    records = golden.get("records", {})
    out = []

    watch_foil = watch.get("foilTimeS")
    phone_foil = summary.get("foilTimeS")
    if watch_foil and phone_foil is not None:
        if abs(phone_foil - watch_foil) / watch_foil * 100 > DIVERGENCE_FOIL_TIME_PCT:
            out.append({"metricId": "foilTime",
                        "labelId": "presentation.divergence.foilTime",
                        "watch": round(watch_foil, 1), "phone": round(phone_foil, 1),
                        "unitKind": "durationS"})

    for kind in DIVERGENCE_RECORDS:
        w, p = watch.get(kind + "Kn"), records.get(kind + "Kn")
        if not w or not p or w <= 0 or p <= 0:
            continue
        if abs(p - w) <= DIVERGENCE_RECORD_KN:
            continue
        out.append({"metricId": kind, "labelId": "tokens.recordWindow." + kind,
                    "watch": round(w, 3), "phone": round(p, 3), "unitKind": "speedKn"})

    for metric, watch_key, path in DIVERGENCE_COUNTS:
        w, p = watch.get(watch_key), _dig(summary, path)
        if w is None or p is None or abs(p - w) <= DIVERGENCE_COUNT:
            continue
        out.append({"metricId": metric, "labelId": "presentation.divergence." + metric,
                    "watch": int(w), "phone": int(p), "unitKind": "count"})
    return out


def presentation(golden: dict, meta: dict | None = None,
                 policy: str = DEFAULT_SPEED_RECORD_POLICY) -> dict:
    """The presentation document for one analysis, with the banner's lines in it.

    `build_presentation` is the lab's and is authoritative; the only thing added here is
    the `divergence` argument, which an analysis cannot know because the watch's own
    summary is not part of it.
    """
    if policy not in SPEED_RECORD_POLICIES:
        policy = DEFAULT_SPEED_RECORD_POLICY
    watch = (meta or {}).get("watch")
    return build_presentation(golden, policy=policy,
                              divergence=divergence_lines(golden, watch))


def presentation_json(result_json: str,
                      policy: str = DEFAULT_SPEED_RECORD_POLICY) -> str:
    """A stored analysis document -> its presentation document, serialized.

    The one door for a session saved before this round: its JSON carries no `presentation`
    key, and the renderers need one. A session analysed since carries its own and never
    comes through here.
    """
    result = json.loads(result_json)
    return json.dumps(presentation(result.get("golden", {}), result.get("meta"), policy),
                      allow_nan=False)


# --------------------------------------------------------------------------- meta


def _meta(a, disc=None) -> dict:
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
    # (docs/algorithms/wind.md "Watch approximation: auto wind"). Kept apart from the rider's own
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
        # **Which rung of the ladder answered** (engine 0.9.1): "activity" | "icu" |
        # "longitude" | "device". The offset alone cannot be read honestly — "+7200 because
        # the watch said so" and "+7200 because the first fix was at 11°E" are the same
        # number and different facts — and only the exact rungs license the header's "times
        # as recorded on the water". A GPX is usually the guess, and the guess is *solar*:
        # an hour out under DST. `render.js` switches the note's wording on this.
        "utcOffsetSource": a.track.start_utc_offset_source,
        "durationS": _num(s.get("total_elapsed_time")),
        "timerTimeS": _num(s.get("total_timer_time")) or round(a.clean.timer_time_s, 1),
        "samples": int(len(df)),
        "sourceClass": caps.source_class,
        # **The rule, decided once, in Python.** `certified = source_class != "c"` is the
        # same one line `LibraryQueries.certified` is on iOS and `library._stamp` is here,
        # and the card's disclaimer used to spell it a fourth time in JavaScript
        # (`meta.sourceClass === "c"`). A one-line rule with four spellings is a rule with
        # four chances to drift, and this is the copy the browser reads.
        "certified": caps.source_class != "c",
        "sport": caps.sport,
        "subSport": caps.sub_sport,
        "discipline": caps.discipline,
        # Which **preset** the engine was run under (docs/algorithms/disciplines.md "Disciplines") —
        # a different fact from the tag above, which is what the watch wrote down. The page
        # reads this one for its lexicon and for the experimental chip.
        "analysedAs": (disc or discipline.Discipline.WINGFOIL).value,
        "windDirUserDeg": wind_user,
        "windDirAutoDeg": wind_auto,
        "appVersion": None if app_version is None else int(app_version),
        "schemaVersion": None if app_version is None else int(app_version) & 0xFF,
        # **What the WATCH itself wrote into this session** (docs/fit-schema.md, session
        # fields 20-56), so the Log tab can hold the two devices side by side the way the
        # phone does. Absent for every source without our developer fields, which is the
        # whole of the "show it where the data exists" rule: there is nothing to compare.
        "watch": _watch(s),
        "avgHr": _num(s.get("avg_heart_rate")),
        "maxHr": _num(s.get("max_heart_rate")),
        "calories": _num(s.get("total_calories")),
        "laps": len(a.track.laps),
        "medianDtS": round(a.clean.median_dt_s, 3),
        "droppedGate": a.clean.dropped_gate,
        "droppedNan": a.clean.dropped_nan,
        "droppedSpike": a.clean.dropped_spike,
    }


def _watch(s: dict) -> dict | None:
    """The watch's own session summary, in the units the phone compares it in.

    The twin of `FitSessionParser.watchSummary` (ios/WingFoilKit/.../FitImport). Speeds
    come off the wire in cm/s and leave here in knots, because knots is what the records
    are defined in and what the table prints. Every field is absent rather than zero when
    the watch did not write it.

    `tack_count` / `jibe_count` carry the one demotion the schema demands: a `0`/`0` pair
    with no wind axis of either kind means *unclassified*, not *none*, and older builds had
    no other value to write. Reading those as literal zeros is what produced "Jibes: watch
    0 vs phone 50" for an afternoon of fifty jibes.
    """
    def knots(key):
        cms = _num(s.get(key))
        return None if cms is None else round(cms / 100.0 * MPS_TO_KN, 3)

    def count(key):
        v = _num(s.get(key))
        return None if v is None else int(v)

    def wind(key):
        v = _num(s.get(key))
        return None if v is None or v >= 65535 else v

    out = {
        "foilTimeS": _num(s.get("foil_time")),
        "foilPct": _num(s.get("foil_pct")),
        "flightCount": count("flight_count"),
        "best2sKn": knots("best_2s"),
        "best10sKn": knots("best_10s"),
        "best5x10sKn": knots("best_5x10s"),
        "best500mKn": knots("best_500m"),
        "bestNmKn": knots("best_nm"),
        "alpha500Kn": knots("alpha500_lite"),
        "tackCount": count("tack_count"),
        "jibeCount": count("jibe_count"),
        "takeoffAttempts": count("takeoff_attempts"),
        "takeoffSuccesses": count("takeoff_successes"),
        "totalPumpStrokes": count("total_pump_strokes"),
        "cleanJibes": count("clean_jibes"),
    }
    axis = wind("wind_dir_user") is not None or wind("wind_dir_auto") is not None
    if not axis and not out["tackCount"] and not out["jibeCount"]:
        out["tackCount"] = None
        out["jibeCount"] = None
    out = {k: v for k, v in out.items() if v is not None}
    return out or None


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
        "geo": _geo_anchor(df) if has_pos else None,
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


def _geo_anchor(df) -> dict | None:
    """One sample that carries **both** its metres and its degrees — the key back to the globe.

    `x`/`y` are metres in the engine's own equirectangular frame, centred on the track: they
    are all the map figure and the speed strip have ever needed, because both draw the session
    against itself. The share card's optional map background is the one surface that has to
    place the same track on the *earth*, and for that a local frame is not enough.

    So rather than shipping a second pair of arrays (lat/lon for every sample, ~90 KB of JSON
    on a long session, all of it redundant), the view carries one row of the four columns the
    cleaned track already holds. Inverting the projection from it is two divisions:

        lat = geo.lat + (y - geo.y) / 110540
        lon = geo.lon + (x - geo.x) / (cos(geo.lat) * 111320)

    The one approximation is `cos(geo.lat)` standing in for the `cos(lat0)` the forward
    projection used (`wingfoil_lab.filters`), and a session spans hundredths of a degree — the
    error over a 2 km track is well under a metre, which is smaller than the GPS fixes it
    places. Nothing but the card's map framing reads it.

    None when no row has all four (a track whose positions are entirely absent never gets
    here, but a single all-NaN row must not become an anchor of NaNs — the document is
    serialized with `allow_nan=False`).
    """
    need = ("lat", "lon", "x", "y")
    if any(c not in df.columns for c in need):
        return None
    values = {c: df[c].to_numpy(float) for c in need}
    finite = np.ones(len(df), dtype=bool)
    for c in need:
        finite &= np.isfinite(values[c])
    if not finite.any():
        return None
    k = int(np.argmax(finite))
    return {"lat": round(float(values["lat"][k]), 7),
            "lon": round(float(values["lon"][k]), 7),
            "x": round(float(values["x"][k]), 2),
            "y": round(float(values["y"][k]), 2)}


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
