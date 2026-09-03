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
from datetime import datetime, timedelta, timezone

# The stored-entry schema. v2 added the two attribution fields the JS side writes beside
# the digest (`rider`, `example`, see `counts_towards_records`); a v1 entry predates them
# and reads as the rider's own, which is what it always was. v3 (engine 0.8.2) added the
# session's own UTC offset and the *local* calendar date it implies — `dateUtc` was, and
# still is, the UTC day, which is a different day from the rider's for every session
# either side of midnight and the wrong one to bucket a trend by. v4 (engine 0.9.1) adds
# `utcOffsetSource`: which rung of the ladder produced that offset, so a stored row can
# still tell an exact answer from a solar guess after the recording itself is long gone.
# Null on every row written before it, which reads as "unrecorded", not as "exact".
# v5 adds the three turn counts the *session* records need — `jibesSuccessful` and the two
# streaks — which the digest carried in no form at all: the records table was speed-only,
# so nothing had ever asked for them. Absent (null) on every row written before it, which
# is why every session record skips a null rather than reading it as a zero: a library
# saved last month must not report "0 clean jibes" as its all-time best.
# v6 (engine 0.10.0) carries `cleanJibesPerHour` itself, instead of leaving `_cph` to divide
# the count by the hour. The arithmetic is identical; what changes is *who owns it* — CPH is
# an engine rate now (docs/algorithms.md "Session rates"), published beside JPH and WPH, and
# a metric with an engine field must not be re-derived by a reader. Null on every row written
# before it, where `_cph` still does the division — see there.
# v7 carries the three facts a *period* needs and a session never did: `rateDurationS` (the
# engine's own cleaned session span, which is the denominator every per-hour rate divides by
# and is not `durationS`), `wetExits` (the fell-in flight ends WPH counts), and `geo` (one
# lat/lon, so an afternoon can be placed at a spot without trusting a filename). All three
# null on a row written before them; `periods` degrades one metric at a time rather than
# refusing to describe a library.
SCHEMA = 7

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

# A clean-jibe *rate* over three jibes is a fact about three jibes. The floor is stated
# here, applied in `_clean_jibe_rate`, and printed in the table's caption on both
# platforms, so the rule the number obeys is the rule the reader is told.
MIN_JIBES_FOR_RATE = 5

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


def _count(v):
    """A whole-number tally, or None when the field is *absent*.

    Deliberately not `int(x or 0)`, which is what the older digest fields do: for a count
    that feeds a "most / longest ever" record, absent and zero have to stay different.
    A digest saved before schema 5 carries no `jibesSuccessful` at all, and reading that
    as 0 would put a fabricated zero in the running for an all-time best.
    """
    if v is None or isinstance(v, bool):
        return None
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def _offset(value):
    """A UTC offset in whole seconds, or None. Anything absurd is treated as absent."""
    if value is None:
        return None
    try:
        seconds = int(round(float(value)))
    except (TypeError, ValueError):
        return None
    return seconds if -18 * 3600 <= seconds <= 18 * 3600 else None


def _local_date(start_epoch, offset_s) -> str | None:
    """The `YYYY-MM-DD` the rider would have written on it, or None without an offset."""
    offset = _offset(offset_s)
    if start_epoch is None or offset is None:
        return None
    return datetime.fromtimestamp(start_epoch + offset, tz=timezone.utc).strftime("%Y-%m-%d")


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


def _outcomes(raw) -> dict | None:
    """The three-rung outcome tally, or None when the engine reported none.

    Read straight out of `summary.turns.outcomes` rather than recounted: the ladder is the
    engine's verdict and a second count here would be a second definition of it. None
    rather than three zeroes when the block is absent — the row then says nothing instead
    of saying that nothing happened.
    """
    if not isinstance(raw, dict):
        return None
    return {key: int(raw.get(key) or 0) for key in ("flewThrough", "touchdown", "fellIn")}


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


def _geo(doc) -> dict | None:
    """The session's one anchor fix as `{lat, lon}`, or None.

    `view.geo` (web_entry) already carries one row that knows both its metres and its
    degrees — it exists for the share card's map background. The digest keeps only the two
    degrees: a spot is a place, and the metres are about a projection this row will never
    do. None on a recording with no fixes and on a document analysed before the anchor
    existed, which simply cannot be placed.
    """
    geo = (doc.get("view") or {}).get("geo")
    if not isinstance(geo, dict):
        return None
    lat, lon = _num(geo.get("lat")), _num(geo.get("lon"))
    if lat is None or lon is None:
        return None
    return {"lat": round(lat, 6), "lon": round(lon, 6)}


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
        # The session's own UTC offset in seconds (engine 0.8.2), so a stored row can be
        # dated and clocked the way the rider saw it without re-reading the FIT. Null on a
        # digest written before the field existed, and on a source that could not say.
        "utcOffsetS": _offset(meta.get("utcOffsetS")),
        # Where that offset came from (engine 0.9.1, schema 4): "activity" | "icu" |
        # "longitude" | "device", or null on a digest written before the field existed.
        # A stored row outlives the file it was made from, so the qualification has to be
        # stored with it — an offset whose provenance was dropped reads as exact for ever.
        "utcOffsetSource": meta.get("utcOffsetSource"),
        "dateUtc": (str(start_utc)[:10] if start_utc else None),
        # The rider's own calendar day. A session that starts at 23:30 in Torbole is a
        # 21:30 UTC session on the *previous* day two months of the year, and a trend
        # bucketed on `dateUtc` would file that evening under the day before it happened.
        "dateLocal": _local_date(start_epoch, meta.get("utcOffsetS")),
        "distanceKm": _num(summ.get("distanceKm")),
        "foilPct": _num(summ.get("foilPct")),
        "foilTimeS": _num(summ.get("foilTimeS")),
        "flightCount": int(summ.get("flightCount") or 0),
        "longestFlightS": _num(summ.get("longestFlightS")),
        "longestFlightM": _num(summ.get("longestFlightM")),
        # The engine's own strict jibe rate (0.10.0, schema 6). Copied, never recomputed:
        # `_cph` divides for a stored row that predates it and reads this everywhere else.
        "cleanJibesPerHour": _num(summ.get("cleanJibesPerHour")),
        # The engine's *cleaned* session span (schema 7) — the denominator all four session
        # rates share (docs/algorithms.md "Session rates"). Deliberately beside `durationS`
        # rather than instead of it: `durationS` is the FIT's `total_elapsed_time` and it is
        # what the stored id is built from, so it may not move. A period's hours and its CPH
        # divide by *this*, or a month holding one session would report a rate that
        # disagreed with that session's own page.
        "rateDurationS": _num(summ.get("durationS")),
        # Every fell-in flight end — turn swims and straight-line swims alike, which is what
        # WPH counts (`summary.wetPerHour`). Absent, never 0, on a row written before it.
        "wetExits": _count(((summ.get("flightEnds") or {}).get("all") or {}).get("fellIn")),
        # Where the session was, to one fix (schema 7). The digest's `spot` is derived from
        # the *filename*, which spells one beach three ways in this project's own corpus —
        # `nago-torbole-windsurfen`, `-foilmotion`, `-wingfoiling` — so a trip detected on
        # the name alone would split a week at Garda into three holidays. Coordinates are
        # what the phone clusters on (`SpotClusterer`), and this is the web's half of it.
        "geo": _geo(doc),
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
            # Schema 5, for the session records and the two new trend series. `successful`
            # above is over *every* counted turn; this is the jibes alone, which is what
            # "clean jibes" means everywhere else in both apps.
            "jibesSuccessful": _count(turns.get("jibesSuccessful")),
            # How the session *felt*, not how the turn channel scored (docs/algorithms.md
            # "Turn streaks"): a swim in a straight line ends a run exactly as a botched
            # jibe does, so these are engine numbers and are never recomputed here.
            "longestDryStreak": _count(turns.get("longestDryStreak")),
            "longestFlewStreak": _count(turns.get("longestFlewStreak")),
            # The outcome tally, so a library row can carry the headline metric the iOS
            # rows have always carried and these did not (app-ui-review.md §5.6). Over
            # every counted turn, which is what the iOS row shows, not over jibes alone.
            # Absent on a digest written before this field existed: the row renders "—"
            # there rather than three zeroes, which would read as a session in which
            # nothing happened.
            "outcomes": _outcomes(turns.get("outcomes")),
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


def counts_towards_records(entry) -> bool:
    """Is this stored entry one of the reader's *own* sessions?

    Two things in the library are shown in full and counted in nothing:

      * the bundled example (`example: true`) — a demonstration nobody in front of this
        browser rode, loaded by the "try the example session" button;
      * a session someone else rode (`rider: "<name>"`) — a FIT a friend sent, scrubbed
        and identity-free by design, so attribution is the receiver's to state.

    Both are stated at save time by `js/store.js` and stored beside the digest, because
    nothing in a FIT could say either. Neither field exists on an entry written before
    schema 2: **missing reads as the reader's own, not example**, so nobody's saved
    library changes meaning under them.

    This is the one condition, and it is applied in exactly one place — `aggregate`,
    below — so the records table, the totals block and every trend chart honour it
    without three call sites remembering to. Same rule as the iOS `LibraryStore.clause`.
    """
    if not isinstance(entry, dict):
        return False
    if entry.get("example"):
        return False
    rider = entry.get("rider")
    return rider is None or not str(rider).strip()


def _sorted(digests) -> list:
    ds = [d for d in (_as_doc(digests) or []) if isinstance(d, dict)]
    ds.sort(key=lambda d: (d.get("startEpoch") is None,
                           _num(d.get("startEpoch")) or 0.0,
                           str(d.get("id") or "")))
    return ds


def _stamp(d: dict) -> dict:
    """The bit of a digest every records row / trend point needs to name its session."""
    return {"id": d.get("id"), "fileName": d.get("fileName"), "spot": d.get("spot"),
            "startUtc": d.get("startUtc"), "dateUtc": d.get("dateUtc"),
            "dateLocal": d.get("dateLocal"), "utcOffsetS": d.get("utcOffsetS"),
            # Which recording set it, in the one word the records table needs (engine
            # 0.9.0). A class-(c) session — a GPX, or any file with no speed channel —
            # had its speed differentiated from positions, and a differentiated speed can
            # read high. The record still stands in the table, because it is still the
            # rider's session; it stands there *marked*, because an all-time best is
            # exactly where an unverifiable number does the most damage.
            "sourceClass": d.get("sourceClass"),
            "certified": d.get("sourceClass") != "c"}


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


# ------------------------------------------------------- the non-speed session records


def _clean_jibes(d: dict):
    """Clean jibes in this session (`summary.turns.jibesSuccessful`), or None if the digest
    predates schema 5 and never carried the number."""
    return _count((d.get("turns") or {}).get("jibesSuccessful"))


def _cph(d: dict):
    """Clean jibes per hour — the engine's `summary.cleanJibesPerHour` (0.10.0, schema 6).

    The division below is the **fallback for a stored row written before that field
    existed**, and nothing else. It is the same arithmetic the engine does — clean jibes
    over elapsed session time — kept here because a library saved last month is still the
    rider's library and its afternoons still hold records; dropping those rows out of the
    CPH record and the CPH trend line would be a worse answer than re-deriving a number
    whose inputs the digest already carries.

    A stored 0.0 is a *measured* zero and is returned as one: `is None` rather than a
    falsy test, or an afternoon of jibes he never carved would fall through to the
    division and print the identical 0.0 by a different route.
    """
    stored = _num(d.get("cleanJibesPerHour"))
    if stored is not None:
        return stored
    clean, duration = _clean_jibes(d), _num(d.get("durationS"))
    if clean is None or duration is None or duration <= 0:
        return None
    return clean * 3600.0 / duration


def _clean_jibe_rate(d: dict):
    """Share of jibes that were clean, over sessions with enough jibes to mean anything."""
    turns = d.get("turns") or {}
    clean, jibes = _clean_jibes(d), _count(turns.get("jibes"))
    if clean is None or jibes is None or jibes < MIN_JIBES_FOR_RATE:
        return None
    return 100.0 * clean / jibes


def _streak(d: dict, key: str):
    return _count((d.get("turns") or {}).get(key))


def _flight_caption(d: dict):
    """The longest flight's *distance*, which is the fact the duration alone leaves out —
    six minutes downwind and six minutes of pumping in a lull are not the same flight."""
    metres = _num(d.get("longestFlightM"))
    return None if metres is None else f"{int(round(metres))} m of it"


# The session records, in the order the second table shows them, and identical to iOS's
# `SessionRecordKind`. Every entry is `(key, label, unit, places, pick, caption)`; `pick`
# reads one digest and answers None when that session cannot supply the number at all,
# which is what keeps a missing field out of a "best ever" claim. `caption` is either a
# fixed string or a function of the *winning* digest.
#
# These are all-time bests over whole sessions, so — unlike the GP3S rows — they carry no
# certification: a class-(c) recording can misreport a speed, but the number of jibes it
# holds and the minutes it lasted are not claims its speed channel makes.
SESSION_RECORD_KINDS = [
    ("longestFlight", "Longest flight", "s", 1,
     lambda d: _num(d.get("longestFlightS")), _flight_caption),
    ("mostFlights", "Most flights", "", 0,
     lambda d: _count(d.get("flightCount")), None),
    ("bestFoilPct", "Highest on-foil share", "%", 1,
     lambda d: _num(d.get("foilPct")), None),
    ("mostCleanJibes", "Most clean jibes", "", 0, _clean_jibes, None),
    ("bestCph", "Best CPH", "/h", 2, _cph, "Clean jibes per hour of session time."),
    ("bestCleanJibeRate", "Best clean-jibe rate", "%", 1, _clean_jibe_rate,
     f"Sessions with at least {MIN_JIBES_FOR_RATE} jibes."),
    ("longestDryStreak", "Longest dry streak", "", 0,
     lambda d: _streak(d, "longestDryStreak"), "Maneuvers in a row without a swim."),
    ("longestFlewStreak", "Longest flew streak", "", 0,
     lambda d: _streak(d, "longestFlewStreak"), "Maneuvers in a row that never touched down."),
    ("longestSession", "Longest session", "s", 0,
     lambda d: _num(d.get("durationS")), None),
    ("mostDistance", "Most distance", "km", 2,
     lambda d: _num(d.get("distanceKm")), None),
]


def _session_records(ds: list) -> list:
    """All-time best per session-record kind. Same rules as `_records`: ties go to the
    earliest session, and a kind nobody has a positive value for is dropped."""
    out = []
    for key, label, unit, places, pick, caption in SESSION_RECORD_KINDS:
        best = None
        for d in ds:                                  # ds is already oldest-first
            v = _num(pick(d))
            if v is None or v <= 0:
                continue
            if best is None or v > best[0]:
                best = (v, d)
        if best is None:
            continue
        value, d = best
        row = {"key": key, "label": label, "unit": unit, "value": round(value, places)}
        text = caption(d) if callable(caption) else caption
        if text:
            row["caption"] = text
        row.update(_stamp(d))
        # A session record is not a speed claim, so it carries no certification to badge.
        row.pop("certified", None)
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

    `sidePort` / `sideStarboard` are the same idea for the one chart whose lines mean a
    *side*: they map onto the `side.*` design tokens instead of the app's own blues, which
    is what stops a chart about entry tacks being drawn in a vocabulary that means
    something else (docs/presentation.md "Entry tack", app-ui-review.md §5.2).
    """
    charts = _charts(ds)
    for c in charts:
        c.update(_y_axis(c["lines"], bool(c.get("percent"))))
    return {"sessions": [_stamp(d) for d in ds], "charts": charts, "weeks": _weeks(ds)}


# The week rule, in one sentence and in one place: **ISO-8601 weeks, Monday start, in the
# session's own local time**. iOS says the same thing in `LibraryStore.weeks` with
# `Calendar(identifier: .iso8601)`; this is the web's half of that agreement, and it lives
# in Python rather than in the chart code for the same reason every other number here does.
#
# Local time, not UTC: a Sunday-evening session that starts at 23:30 in Torbole is a 21:30
# UTC session on the Sunday two months of the year and on the *Saturday* the rest of the
# time — bucketing on the UTC instant would file it under the week before it happened.
# `dateLocal` (schema 3) is the day the rider had; `dateUtc` is the fallback for a digest
# saved before that field existed.
def _week_start(date_text: str) -> str:
    """`YYYY-MM-DD` -> the `YYYY-MM-DD` of the Monday that opens its ISO week."""
    d = datetime.strptime(date_text, "%Y-%m-%d").date()
    return (d - timedelta(days=d.weekday())).isoformat()


def _weeks(ds: list) -> list:
    """Sessions per ISO week, zero-filled from the first week to the last.

    A week with no session is a bar of height 0, because that *is* the information — a
    chart that simply omits the quiet weeks draws a season with no gaps in it.
    """
    buckets: dict[str, dict] = {}
    for d in ds:
        day = d.get("dateLocal") or d.get("dateUtc")
        if not day:
            continue
        try:
            key = _week_start(str(day)[:10])
        except ValueError:
            continue
        b = buckets.setdefault(key, {"weekStart": key, "count": 0, "hours": 0.0})
        b["count"] += 1
        b["hours"] += (_num(d.get("durationS")) or 0.0) / 3600.0
    if not buckets:
        return []
    cursor = datetime.strptime(min(buckets), "%Y-%m-%d").date()
    end = datetime.strptime(max(buckets), "%Y-%m-%d").date()
    out = []
    # Same 520-week ceiling as iOS: a single mis-dated digest from 1989 must not turn the
    # chart into thirty years of empty bars.
    while cursor <= end and len(out) < 520:
        key = cursor.isoformat()
        b = buckets.get(key) or {"weekStart": key, "count": 0, "hours": 0.0}
        out.append({**b, "hours": round(b["hours"], 3)})
        cursor += timedelta(days=7)
    return out


def _charts(ds: list) -> list:
    return [
        {"key": "foilPct", "label": "On foil", "unit": "%", "percent": True,
         "lines": [{"key": "foilPct", "label": "on foil", "role": "primary",
                    "points": _points(ds, lambda d: _num(d.get("foilPct")))}]},
        {"key": "longestFlight", "label": "Longest flight", "unit": "s",
         "lines": [{"key": "longestFlightS", "label": "longest flight", "role": "primary",
                    "points": _points(ds, lambda d: _num(d.get("longestFlightS")))}]},
        {"key": "turnSuccess", "label": "Clean jibe rate", "unit": "%", "percent": True,
         "lines": [{"key": "successPct", "label": "clean", "role": "primary",
                    "points": _points(ds, lambda d: _num((d.get("turns") or {}).get("successPct")))}]},
        {"key": "cleanJibes", "label": "Clean jibes per session", "unit": "",
         "lines": [{"key": "cleanJibes", "label": "clean jibes", "role": "primary",
                    "points": _points(ds, _clean_jibes)}]},
        {"key": "cph", "label": "Clean jibes per hour", "unit": "/h",
         "lines": [{"key": "cph", "label": "CPH", "role": "primary",
                    "points": _points(ds, _cph)}]},
        {"key": "pumps", "label": "Avg pumps to takeoff", "unit": "",
         "lines": [{"key": "avgPumpsToTakeoff", "label": "pumps", "role": "primary",
                    "points": _points(ds, lambda d: _num((d.get("takeoff") or {}).get("avgPumpsToTakeoff")))}]},
        {"key": "turnSide", "label": "Clean jibes by entry tack", "unit": "%", "percent": True,
         "lines": [
             {"key": "port", "label": "port entry", "role": "sidePort",
              "points": _points(ds, lambda d: _side_pct(d, "port"))},
             {"key": "starboard", "label": "starboard entry", "role": "sideStarboard",
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


# ==================================================================== periods
#
# A month, a season, a trip or a range the rider typed — four ways of naming a *set of
# afternoons*, all answered by one aggregate block (docs/presentation.md "Periods").
#
# Everything below is arithmetic and calendar work, which is why it is here rather than in
# js/trends.js: the analyzer's rule is that the browser never computes a number, and a trip
# is a number's worth of judgement (which afternoons belong to it) before it is a heading.
# iOS says the same things in `LibraryStore.periods` and `PeriodBlock`, and the two are
# pinned against one shared fixture — `fixtures/periods/periods.expected.json`.


#: How far apart two afternoons can be and still be one holiday. Three days: a trip has
#: rest days, blown-out days and travel days in it, and a Tuesday off does not end a week
#: at Garda. Four days apart is two visits.
TRIP_GAP_DAYS = 3
#: One afternoon somewhere is a session, not a trip. The heading has to be worth a heading.
TRIP_MIN_SESSIONS = 2
#: Spot radius for the trip clusterer. Deliberately looser than the phone's 500 m
#: (`SpotClusterer.defaultRadiusM`), because this is not the same question: the phone is
#: naming *launches* and wants the beach, and a trip is asking whether two afternoons were
#: the same holiday — Torbole and Malcesine are one week at Garda and 15 km apart. 3 km
#: keeps a lake's north shore together and still separates two spots in one city.
TRIP_RADIUS_M = 3000

_EARTH_RADIUS_M = 6_371_000

#: The season cut: **1 April → 31 March**, one Northern-hemisphere water year, so a
#: February session still counts towards the winter it belongs to. The same cut the iOS
#: Trends range picker has always used (`TrendsView.TrendRange.season`); stated once here
#: rather than invented a second time.
SEASON_START_MONTH = 4

_MONTHS_LONG = ["January", "February", "March", "April", "May", "June", "July",
                "August", "September", "October", "November", "December"]
_MONTHS_SHORT = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


def _day(d: dict):
    """The calendar day the *rider* had, as a `date`, or None.

    `dateLocal` (schema 3) is the day in the session's own zone; `dateUtc` is the fallback
    for a row saved before it, and is the UTC day — right for most afternoons and a day out
    for one either side of midnight. Every bucket on this page is cut on this, because a
    month is a fact about the rider's calendar and not about Greenwich's.
    """
    text = d.get("dateLocal") or d.get("dateUtc")
    if not text:
        return None
    try:
        return datetime.strptime(str(text)[:10], "%Y-%m-%d").date()
    except ValueError:
        return None


def _distance_m(a: dict, b: dict) -> float:
    """Great-circle metres — the same haversine `SpotClusterer.distance` uses."""
    lat1, lon1, lat2, lon2 = a["lat"], a["lon"], b["lat"], b["lon"]
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = math.radians(lat2 - lat1), math.radians(lon2 - lon1)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * _EARTH_RADIUS_M * math.atan2(math.sqrt(h), math.sqrt(max(0.0, 1 - h)))


def _spot_clusters(ds: list) -> list[list[int]]:
    """Group the digests into places, as lists of indices into `ds`.

    Single-link greedy assignment against a moving centroid, which is exactly what the
    phone does (`SpotClusterer.cluster`) and for the same reason: a rig-up beach is tens of
    metres across and the next spot is kilometres away, so there is no cluster count to get
    wrong.

    A digest with **no** anchor (schema < 7, or a recording with no fixes) cannot be placed,
    so it falls back to its filename-derived `spot` string: it joins a cluster that already
    answers to that name, and otherwise seeds one of its own. That is weaker than
    coordinates and is why the field was added — but a library saved last month must still
    produce trips, and a name is the only thing those rows have.
    """
    clusters: list[dict] = []          # {lat, lon, n, names: set, members: [i]}
    unplaced: list[int] = []
    for i, d in enumerate(ds):
        geo = d.get("geo")
        if not isinstance(geo, dict) or _num(geo.get("lat")) is None:
            unplaced.append(i)
            continue
        point = {"lat": float(geo["lat"]), "lon": float(geo["lon"])}
        best, best_d = None, float("inf")
        for c in clusters:
            gap = _distance_m(point, c)
            if gap <= TRIP_RADIUS_M and gap < best_d:
                best, best_d = c, gap
        if best is None:
            clusters.append({"lat": point["lat"], "lon": point["lon"], "n": 1,
                             "names": {str(d.get("spot") or "")}, "members": [i]})
            continue
        n = best["n"]
        best["lat"] = (best["lat"] * n + point["lat"]) / (n + 1)
        best["lon"] = (best["lon"] * n + point["lon"]) / (n + 1)
        best["n"] = n + 1
        best["names"].add(str(d.get("spot") or ""))
        best["members"].append(i)

    for i in unplaced:
        name = str(ds[i].get("spot") or "")
        home = next((c for c in clusters if name in c["names"]), None)
        if home is None:
            home = {"lat": None, "lon": None, "n": 0, "names": {name}, "members": []}
            clusters.append(home)
        home["members"].append(i)

    return [sorted(c["members"]) for c in clusters]


def _cluster_name(ds: list, members: list[int]) -> str:
    """What to call a cluster: the spot name most of its afternoons carry.

    Ties go to the earliest session's, because `ds` is oldest-first and the first name a
    place was given is the one the rider has been reading ever since. The name is still the
    filename's guess — the *view* applies the one correction (`sportCorrected`), here as on
    every other surface that prints it.
    """
    counts: dict[str, int] = {}
    for i in members:
        name = str(ds[i].get("spot") or "").strip()
        if name:
            counts[name] = counts.get(name, 0) + 1
    if not counts:
        return "Session"
    best = max(counts.values())
    for i in members:                                   # oldest first
        name = str(ds[i].get("spot") or "").strip()
        if counts.get(name) == best:
            return name
    return "Session"


def _runs(ds: list, members: list[int]) -> list[list[int]]:
    """Split one place's afternoons into visits, on the `TRIP_GAP_DAYS` rule.

    Members with no usable date cannot be placed in time and are simply left out — a trip
    is a span, and a session that cannot say which day it was on cannot be inside one.
    """
    dated = [(i, _day(ds[i])) for i in members]
    dated = sorted(((i, day) for i, day in dated if day is not None), key=lambda p: p[1])
    out: list[list[int]] = []
    run: list[int] = []
    previous = None
    for i, day in dated:
        if previous is not None and (day - previous).days > TRIP_GAP_DAYS:
            out.append(run)
            run = []
        run.append(i)
        previous = day
    if run:
        out.append(run)
    return out


# ------------------------------------------------------------------ the block


def _f_int(v):
    return f"{int(round(v))}"


def _f_hours(v):
    return f"{v:.1f} h"


def _f_km(v):
    return f"{v:.1f} km"


def _f_pct(v):
    return f"{v:.1f} %"


def _f_rate(v):
    return f"{v:.1f}"


def _f_kn(v):
    return f"{v:.2f} kn"


def _f_clock(v):
    """`m:ss min` / `h:mm h` — the key-metrics block's own duration rule (`hm` in
    js/cardstats.js, `KeyMetrics.duration` on iOS), so a flight on a period card reads the
    way a duration reads everywhere else in this project."""
    total = max(0, int(round(v)))
    if total >= 3600:
        m = int(round(total / 60))
        return f"{m // 60}:{m % 60:02d} h"
    return f"{total // 60}:{total % 60:02d} min"


#: **The aggregate block**, in the one order both platforms show it in
#: (docs/presentation.md "Periods"). `(key, label, formatter)`; the value itself is
#: computed in `_period_facts`, once, from summed numerators over summed denominators.
#:
#: An entry whose fact the period cannot supply is **omitted**, not printed as a dash or a
#: zero — the same rule `KeyMetrics.rates` follows, and the same rule that lets a card
#: preset be a strict subset without ever inventing a cell.
PERIOD_BLOCK = [
    ("sessions", "sessions", _f_int),
    ("hours", "hours on the water", _f_hours),
    ("distance", "distance", _f_km),
    ("flights", "flights", _f_int),
    ("foilPct", "on foil", _f_pct),
    ("cleanJibes", "clean jibes", _f_int),
    ("cph", "CPH · clean jibes per hour", _f_rate),
    ("turns", "turns", _f_int),
    ("cleanJibeRate", "clean-jibe rate", _f_pct),
    ("wph", "WPH · swims per hour", _f_rate),
    ("best2s", "best 2 s", _f_kn),
    ("best10s", "best 10 s", _f_kn),
    ("longestFlight", "longest flight", _f_clock),
    ("longestDryStreak", "longest dry streak", _f_int),
    ("spots", "spots visited", _f_int),
]

#: What the period card's `lean` preset keeps — the five a rider quotes about a holiday.
#: Keys, not a rebuilt list, so the preset can only ever *drop* an entry: the same rule the
#: session card's `LEAN_KEYS` follows and for the same reason.
PERIOD_LEAN_KEYS = ["sessions", "hours", "cleanJibes", "cph", "best2s"]


def _rate_duration_s(d: dict):
    """The seconds a period's rates divide by, for one session.

    `rateDurationS` (schema 7) is the engine's own cleaned span — the denominator every
    per-session rate already uses — so a month holding one afternoon reports that
    afternoon's CPH and not a second opinion about it. `durationS` is the fallback for a
    row saved before the field, where it is the closest thing stored.
    """
    engine = _num(d.get("rateDurationS"))
    return engine if engine is not None else _num(d.get("durationS"))


def _sum(ds: list, pick):
    """Σ over the digests that can answer, or None when *none* of them can.

    The distinction is the block's whole honesty: a period whose rows all predate a field
    has no answer and drops the entry, where a period in which the rider genuinely did
    none of something has a measured zero and prints it.
    """
    values = [pick(d) for d in ds]
    values = [v for v in values if v is not None]
    return sum(values) if values else None


def _max(ds: list, pick):
    values = [pick(d) for d in ds if pick(d) is not None]
    return max(values) if values else None


def _period_facts(ds: list, spots: int) -> dict:
    """Every number the block prints, as numbers.

    **Rates use the summed denominators, never the mean of the per-session rates.** Ten
    minutes with one clean jibe and three hours with three are not "3.0 and 1.0, so 2.0 an
    hour"; they are four clean jibes in three hours and ten minutes. The same rule already
    governs the library totals' on-foil share, which is total foil time over total on-water
    time and not the average of the percentages.
    """
    seconds = _sum(ds, _rate_duration_s) or 0.0
    hours = seconds / 3600.0 if seconds > 0 else None
    clean = _sum(ds, _clean_jibes)
    jibes = _sum(ds, lambda d: _count((d.get("turns") or {}).get("jibes")))
    wet = _sum(ds, lambda d: _count(d.get("wetExits")))
    foil = _sum(ds, lambda d: _num(d.get("foilTimeS")))
    on_water = _sum(ds, _on_water_s)
    return {
        "sessions": float(len(ds)),
        "hours": hours,
        "distance": _sum(ds, lambda d: _num(d.get("distanceKm"))),
        "flights": _sum(ds, lambda d: _count(d.get("flightCount"))),
        "foilPct": (100.0 * foil / on_water) if foil is not None and on_water else None,
        "cleanJibes": None if clean is None else float(clean),
        "cph": None if clean is None or hours is None else clean / hours,
        "turns": _sum(ds, lambda d: _count((d.get("turns") or {}).get("counted"))),
        # Same floor as the session record, over the period's own total: four clean out of
        # four is a good week, and it is still not a rate.
        "cleanJibeRate": (100.0 * clean / jibes)
                         if clean is not None and jibes and jibes >= MIN_JIBES_FOR_RATE
                         else None,
        "wph": None if wet is None or hours is None else wet / hours,
        "best2s": _max(ds, lambda d: _num((d.get("records") or {}).get("best2sKn"))),
        "best10s": _max(ds, lambda d: _num((d.get("records") or {}).get("best10sKn"))),
        "longestFlight": _max(ds, lambda d: _num(d.get("longestFlightS"))),
        "longestDryStreak": _max(ds, lambda d: _streak(d, "longestDryStreak")),
        "spots": float(spots),
    }


def period_block(ds: list, spots: int = 1) -> list:
    """The aggregate block for one set of digests, as `{key, label, value}` entries.

    Display strings, as on the session card and for the same reason: a period card is a PNG
    in somebody else's chat thread, so every rounding and every absence has to be decided in
    a function a test can call rather than by a binding at draw time.
    """
    facts = _period_facts(ds, spots)
    out = []
    for key, label, fmt in PERIOD_BLOCK:
        value = facts.get(key)
        if value is None:
            continue
        out.append({"key": key, "label": label, "value": fmt(value)})
    return out


# ------------------------------------------------------------------ the headings


def _span_line(first, last) -> str:
    """The period's dates in words, en-GB, the way the card's date line reads them.

    One day is one date; a span inside one month names the month once; a span inside one
    year names the year once. The year is always there, because a card outlives the season
    it was made in.
    """
    if first == last:
        return f"{first.day} {_MONTHS_LONG[first.month - 1]} {first.year}"
    if (first.year, first.month) == (last.year, last.month):
        return f"{first.day} – {last.day} {_MONTHS_LONG[last.month - 1]} {last.year}"
    if first.year == last.year:
        return (f"{first.day} {_MONTHS_LONG[first.month - 1]} – "
                f"{last.day} {_MONTHS_LONG[last.month - 1]} {last.year}")
    return (f"{first.day} {_MONTHS_LONG[first.month - 1]} {first.year} – "
            f"{last.day} {_MONTHS_LONG[last.month - 1]} {last.year}")


def _span_short(first, last) -> str:
    """`31 Jul – 6 Aug`, for a trip heading that already carries the spot's name. The year
    joins it only when the trip crosses one, where leaving it out would be a riddle."""
    if first.year != last.year:
        return (f"{first.day} {_MONTHS_SHORT[first.month - 1]} {first.year} – "
                f"{last.day} {_MONTHS_SHORT[last.month - 1]} {last.year}")
    if first == last:
        return f"{first.day} {_MONTHS_SHORT[first.month - 1]}"
    return (f"{first.day} {_MONTHS_SHORT[first.month - 1]} – "
            f"{last.day} {_MONTHS_SHORT[last.month - 1]}")


def season_year(day) -> int:
    """Which season a day belongs to, named by the calendar year it opened in.

    1 April → 31 March. A February afternoon belongs to the season that started the
    previous April, which is the winter the rider actually rode it in.
    """
    return day.year if day.month >= SEASON_START_MONTH else day.year - 1


def season_label(start_year: int, crosses: bool) -> str:
    """`2026/27` for a season that has reached January, `2026` for one that has not.

    A season is named for the year it opened in either way; the second half of the name
    appears once there is a second half of the season to name.
    """
    return f"{start_year}/{(start_year + 1) % 100:02d}" if crosses else str(start_year)


def _anchored(d: dict) -> bool:
    """Whether this session was placed by a **fix** rather than by the name of its file.

    `_spot_clusters` falls back to the filename-derived spot for a digest with no anchor, which
    is right for deciding whether two afternoons were one holiday and not good enough for
    deciding where on the earth to point a camera.
    """
    geo = d.get("geo")
    return isinstance(geo, dict) and _num(geo.get("lat")) is not None


def _map_ground(rows: list, spots: int) -> bool:
    """Whether this period has **one ground** a card can draw itself on.

    A period is a set of afternoons and they need not have happened anywhere near one another.
    The session card can always answer "which rectangle of the earth?" — one recording, one
    bounding box — and a period cannot: a month split between Garda and the Rhine has a union
    box that is mostly the motorway between them, at a zoom where neither beach is visible.

    So the ground is offered exactly when the period is **one place**: every session inside a
    single 3 km spot cluster — the same radius and the same clusterer that decides whether two
    afternoons were one trip — and every one of them placed by a fix. A trip is one place by
    construction; a month, a season or a typed range is one when the rider only rode one beach
    in it. Otherwise the switch is not offered at all, which is the honest shape of a control
    that has no answer (docs/presentation.md, "The period card").
    """
    return bool(rows) and spots == 1 and all(_anchored(r) for r in rows)


def _period(kind: str, key: str, title: str, ds: list, members: list[int],
            spot: str | None = None) -> dict:
    """One period, headed and blocked. `members` is oldest-first into `ds`."""
    rows = [ds[i] for i in members]
    days = [d for d in (_day(r) for r in rows) if d is not None]
    first, last = (min(days), max(days)) if days else (None, None)
    spots = len(_spot_clusters(rows))
    return {
        "kind": kind,
        "key": key,
        "title": title,
        "spot": spot,
        "dateLine": _span_line(first, last) if first else "",
        "spanShort": _span_short(first, last) if first else "",
        "startDate": first.isoformat() if first else None,
        "endDate": last.isoformat() if last else None,
        "sessionIds": [r.get("id") for r in rows],
        "sessions": len(rows),
        # Whether the card may offer a map background — see `_map_ground`. Decided here
        # because it is a fact about which afternoons these are, and the browser never
        # computes one of those.
        "mapGround": _map_ground(rows, spots),
        "block": period_block(rows, spots),
    }


def periods(digests) -> dict:
    """Every period the library implies: **trips, then months, then seasons**, newest first.

    The reader's own sessions only — `counts_towards_records`, applied here as it is in
    `aggregate`, because a trip built out of a friend's afternoon would be a holiday
    somebody else had.
    """
    ds = [d for d in _sorted(digests) if counts_towards_records(d)]
    return {"trips": _trips(ds), "months": _months(ds), "seasons": _seasons(ds)}


def _trips(ds: list) -> list:
    """A trip is: the same place, afternoons no more than `TRIP_GAP_DAYS` apart, at least
    `TRIP_MIN_SESSIONS` of them. Newest first, because the last holiday is the one being
    looked for."""
    out = []
    for members in _spot_clusters(ds):
        name = _cluster_name(ds, members)
        for run in _runs(ds, members):
            if len(run) < TRIP_MIN_SESSIONS:
                continue
            first, last = _day(ds[run[0]]), _day(ds[run[-1]])
            title = f"{name} · {_span_short(first, last)}"
            out.append(_period("trip", f"trip:{ds[run[0]].get('id')}", title, ds, run,
                               spot=name))
    out.sort(key=lambda p: (p["startDate"] or "", p["title"]), reverse=True)
    return out


def _months(ds: list) -> list:
    buckets: dict[str, list[int]] = {}
    for i, d in enumerate(ds):
        day = _day(d)
        if day is None:
            continue
        buckets.setdefault(f"{day.year:04d}-{day.month:02d}", []).append(i)
    out = []
    for key in sorted(buckets, reverse=True):
        year, month = int(key[:4]), int(key[5:])
        out.append(_period("month", key, f"{_MONTHS_LONG[month - 1]} {year}",
                           ds, buckets[key]))
    return out


def _seasons(ds: list) -> list:
    buckets: dict[int, list[int]] = {}
    crosses: dict[int, bool] = {}
    for i, d in enumerate(ds):
        day = _day(d)
        if day is None:
            continue
        year = season_year(day)
        buckets.setdefault(year, []).append(i)
        crosses[year] = crosses.get(year, False) or day.year > year
    out = []
    for year in sorted(buckets, reverse=True):
        label = season_label(year, crosses[year])
        out.append(_period("season", str(year), f"Season {label}", ds, buckets[year]))
    return out


def custom_period(digests, start: str | None = None, end: str | None = None) -> dict:
    """The rider's own range, inclusive on both ends, in **local** calendar days.

    Inclusive because the two date inputs are read as "from this day to that day", which is
    what a person means by them; an exclusive end would silently drop the last afternoon of
    a holiday, which is usually the best one. An open end is open: no start means "since the
    first session", no end means "up to the last".
    """
    ds = [d for d in _sorted(digests) if counts_towards_records(d)]
    members = []
    for i, d in enumerate(ds):
        day = _day(d)
        if day is None:
            continue
        if start and str(day) < str(start)[:10]:
            continue
        if end and str(day) > str(end)[:10]:
            continue
        members.append(i)
    rows = [ds[i] for i in members]
    days = [d for d in (_day(r) for r in rows) if d is not None]
    if days:
        title = _span_short(min(days), max(days))
        if min(days).year == max(days).year:
            title = f"{title} {max(days).year}"
    else:
        title = "No sessions in this range"
    key = f"custom:{start or ''}:{end or ''}"
    return _period("custom", key, title, ds, members)


def periods_json(digests_json: str) -> str:
    return json.dumps(periods(digests_json), allow_nan=False)


def custom_period_json(digests_json: str, start: str | None = None,
                       end: str | None = None) -> str:
    return json.dumps(custom_period(digests_json, start or None, end or None),
                      allow_nan=False)


# ------------------------------------------------------------------ the whole view


def aggregate(digests) -> dict:
    """The whole Records & Trends view, in one Python call over the stored digests.

    The example session and a friend's session are filtered out here and nowhere else —
    see `counts_towards_records`. `count` is therefore what the view actually aggregates,
    which is what lets the UI say "nothing here counts yet" without knowing the rule.
    """
    ds = [d for d in _sorted(digests) if counts_towards_records(d)]
    return {"schema": SCHEMA, "count": len(ds), "totals": _totals(ds),
            "records": _records(ds), "sessionRecords": _session_records(ds),
            "trends": _trends(ds),
            # The whole periods section rides on the aggregate the view already asks for:
            # it reads the same digests, and a second round trip to Pyodide for the same
            # list would be a second answer waiting to disagree with this one. Only the
            # rider's own custom range needs a call of its own (`custom_period`).
            "periods": {"trips": _trips(ds), "months": _months(ds),
                        "seasons": _seasons(ds)}}


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
