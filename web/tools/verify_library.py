#!/usr/bin/env python3
"""Headless checks for `web/lab_bundle/library.py` — the session-library Python glue.

The library and the trends view are the only parts of the web app that look at more than
one session, and every number they show is produced here rather than in JavaScript. That
makes them testable with plain CPython, which is what this script does — no browser, no
Pyodide, no OPFS.

    lab/.venv/bin/python web/tools/verify_library.py
    lab/.venv/bin/python web/tools/verify_library.py --fast   # skip the FIT-corpus checks

Four groups:

1. **Dedupe edge cases.** The +/-60 s rule is the project's session-identity rule; 59 s
   must match and 61 s must not, on either axis, and an entry with no start must never
   match anything.
1c. **Attribution.** The bundled example and a session a friend rode are stored like any
   other and counted in nothing; `counts_towards_records` is the rule and `aggregate` is
   the only place it is applied, so a friend's faster afternoon must not reach the records
   table — and an entry saved before the fields existed must still count as the reader's.
2. **Digest fidelity.** The digest is a projection of the analysis document, so every
   field it carries must equal the golden it came from — including the port/starboard
   turn split, which is hand-counted here from the golden's own `turns` array.
3. **Records aggregation** over the real FIT corpus, with the winners named explicitly.
4. **Trend series shape**: one point per session per line, oldest first, aligned indices.

Groups 2-4 need `fixtures/sessions/**.fit` and take ~20 s (they run the real engine).
`--fast` runs group 1 and the pure-string checks only.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys
from datetime import datetime
from pathlib import Path

WEB = Path(__file__).resolve().parents[1]
REPO = WEB.parent
sys.path.insert(0, str(WEB / "lab_bundle"))

import library                                              # noqa: E402
import web_entry                                            # noqa: E402

CIQ = "2026-08-07-0754_nago-torbole-windsurfen_ciq"

PASSED = 0
FAILED: list[str] = []
_MARK = [0, 0]                                  # (passed, failed) when the section opened


def check(name: str, got, want) -> None:
    global PASSED
    if got == want:
        PASSED += 1
    else:
        FAILED.append(f"{name}\n      got  {got!r}\n      want {want!r}")


def section(title: str) -> None:
    _close_section()
    print(f"\n{title}")
    print("-" * len(title))
    _MARK[:] = [PASSED, len(FAILED)]


def _close_section() -> None:
    ok, bad = PASSED - _MARK[0], len(FAILED) - _MARK[1]
    if ok or bad:
        print(f"  -> {ok} passed" + (f", {bad} FAILED" if bad else ""))


# ------------------------------------------------------------------ 1. dedupe rule


def entry(start: float, dur: float, ident: str = "e") -> dict:
    return {"id": ident, "startEpoch": start, "durationS": dur, "fileName": f"{ident}.fit"}


def check_dedupe() -> None:
    section("1. dedupe key (+/-60 s start AND +/-60 s duration, both inclusive)")
    base = entry(1_786_082_075.0, 5493.9, "base")
    lib = [base]

    cases = [
        # (label, start delta, duration delta, expect a match?)
        ("identical",                    0,    0,    True),
        ("start +59 s",                 59,    0,    True),
        ("start -59 s",                -59,    0,    True),
        ("start +60 s (boundary)",      60,    0,    True),
        ("start +61 s",                 61,    0,    False),
        ("start -61 s",                -61,    0,    False),
        ("duration +59 s",               0,   59,    True),
        ("duration -59 s",               0,  -59,    True),
        ("duration +60 s (boundary)",    0,   60,    True),
        ("duration +61 s",               0,   61,    False),
        ("duration -61 s",               0,  -61,    False),
        ("both +59 s",                  59,   59,    True),
        ("start ok, duration +61 s",    59,   61,    False),
        ("start +61 s, duration ok",    61,   59,    False),
        ("next session, 2 h later",   7200,  120,    False),
    ]
    for label, ds, dd, want in cases:
        cand = entry(base["startEpoch"] + ds, base["durationS"] + dd, "cand")
        got = library.dedupe_match(cand, lib)
        check(f"  {label}", got["match"], want)
        if want:
            check(f"  {label} -> points at the stored entry", got["id"], "base")

    # A start we could not read must never silently merge two sessions.
    check("  no start on the candidate",
          library.dedupe_match(entry(None, 5493.9, "x"), lib)["match"], False)
    check("  no start on the stored entry",
          library.dedupe_match(base, [entry(None, 5493.9, "x")])["match"], False)
    check("  no duration on the candidate",
          library.dedupe_match(entry(base["startEpoch"], None, "x"), lib)["match"], False)
    check("  empty library", library.dedupe_match(base, [])["match"], False)

    # Several qualifying entries: the *closest* one is the one a replace should land on.
    crowd = [entry(base["startEpoch"] + 55, base["durationS"] + 40, "far"),
             entry(base["startEpoch"] + 3, base["durationS"] - 2, "near")]
    check("  closest match wins", library.dedupe_match(base, crowd)["id"], "near")

    # JSON in / JSON out is what the worker actually calls.
    round_trip = json.loads(library.dedupe_match_json(json.dumps(base), json.dumps(lib)))
    check("  dedupe_match_json round trip", round_trip["match"], True)
    check("  delta fields reported", (round_trip["deltaStartS"], round_trip["deltaDurS"]),
          (0.0, 0.0))


def check_spot_names() -> None:
    section("1b. spot names from the corpus filename convention")
    cases = [
        ("2026-08-07-0754_nago-torbole-windsurfen_ciq.fit", "Nago Torbole Windsurfen"),
        ("2026-08-05-1356_nago-torbole-foilmotion_foilmotion.fit", "Nago Torbole Foilmotion"),
        ("2026-06-13-1558_rheinstetten-windsurfen_native.fit", "Rheinstetten Windsurfen"),
        ("2026-08-06-0757_nago-torbole-wingfoiling_wingfoiling.fit",
         "Nago Torbole Wingfoiling"),
        ("Activity.fit", "Activity"),
        ("12345678.fit", "12345678"),
        ("", "Session"),
        ("lake-garda.fit", "Lake Garda"),
    ]
    for name, want in cases:
        check(f"  {name or '(empty)'}", library.spot_name(name), want)


# ------------------------------------------------------------------ 1c. attribution


def counted_entry(ident: str, best2s: float, **extra) -> dict:
    """A stored index entry, thin but real: everything `aggregate` reads is present, so
    the only thing under test is whether the entry is counted at all."""
    e = {
        "schema": library.SCHEMA, "id": ident, "fileName": f"{ident}.fit", "spot": ident,
        "startUtc": "2026-08-01T08:00:00Z", "startEpoch": 1_785_916_800.0,
        "dateUtc": "2026-08-01", "durationS": 3600.0, "distanceKm": 10.0,
        "foilPct": 50.0, "foilTimeS": 1800.0, "flightCount": 5, "longestFlightS": 60.0,
        # Three clean jibes in one hour — the engine's own rate (schema 6), stated rather
        # than left for `_cph` to divide, exactly as a stored digest carries it.
        "cleanJibesPerHour": 3.0,
        "records": {"best2sKn": best2s}, "recordWindows": {"best2sKn": []},
        "turns": {"counted": 10, "successful": 4, "successPct": 40.0,
                  "jibes": 8, "jibesSuccessful": 3,
                  "longestDryStreak": 4, "longestFlewStreak": 2,
                  "bySide": {"port": {"entries": 5, "successes": 2},
                             "starboard": {"entries": 5, "successes": 2}}},
        "takeoff": {"attempts": 5, "successes": 5},
    }
    e.update(extra)
    return e


def check_attribution() -> None:
    """The bundled example and a friend's session are shown in full and counted in
    nothing. The rule lives in `counts_towards_records` and is applied in `aggregate`
    only, so these checks are what stop a third copy of it appearing somewhere else."""
    section("1c. attribution (the example and a friend's session do not count)")
    cases = [
        ("no fields at all (an entry saved before schema 2)", {}, True),
        ("rider: null", {"rider": None}, True),
        ("rider: \"\"", {"rider": ""}, True),
        ("rider: whitespace", {"rider": "   "}, True),
        ("rider: a name", {"rider": "Max"}, False),
        ("example: false", {"example": False}, True),
        ("example: true", {"example": True}, False),
        ("example: true and a rider", {"example": True, "rider": "Max"}, False),
    ]
    for label, fields, want in cases:
        check(f"  {label}", library.counts_towards_records(dict(fields)), want)
    check("  not a dict", library.counts_towards_records("nope"), False)

    # The friend is the fastest session in this library and the example is the longest —
    # neither may reach the records table, the totals or a trend point.
    mine = counted_entry("mine", 12.0)
    friend = counted_entry("friend", 20.0, rider="Max", distanceKm=99.0)
    demo = counted_entry("demo", 18.0, example=True, distanceKm=42.0)
    agg = library.aggregate([mine, friend, demo])
    check("  aggregate counts only the reader's own", agg["count"], 1)
    check("  totals.sessions", agg["totals"]["sessions"], 1)
    check("  totals.distanceKm ignores the excluded two", agg["totals"]["distanceKm"], 10.0)
    check("  totals.turnsCounted ignores them too", agg["totals"]["turnsCounted"], 10)
    rows = {r["key"]: r for r in agg["records"]}
    check("  the record is the reader's, not the friend's",
          (rows["best2sKn"]["value"], rows["best2sKn"]["id"]), (12.0, "mine"))
    # The same rule over the *session* records, which have their own aggregation loop and
    # would otherwise be a second place for the exclusion to be forgotten. The friend rode
    # the longest and the furthest of the three; neither may reach the table.
    session_rows = {r["key"]: r for r in agg["sessionRecords"]}
    check("  the session records are the reader's too",
          sorted({r["id"] for r in agg["sessionRecords"]}), ["mine"])
    check("  most distance is the reader's 10 km, not the friend's 99",
          session_rows["mostDistance"]["value"], 10.0)
    check("  one point per counted session",
          [len(l["points"]) for c in agg["trends"]["charts"] for l in c["lines"]],
          [1] * sum(len(c["lines"]) for c in agg["trends"]["charts"]))
    check("  the trend stamps name only the counted session",
          [s["id"] for s in agg["trends"]["sessions"]], ["mine"])

    # A library made only of those: `count` is 0, which is what lets js/trends.js say
    # "nothing here counts yet" without knowing the rule itself.
    empty = library.aggregate([friend, demo])
    check("  nothing counted -> count 0", empty["count"], 0)
    check("  nothing counted -> no records", empty["records"], [])
    check("  nothing counted -> no trend stamps", empty["trends"]["sessions"], [])

    # Back-compat, stated as a check rather than a comment: a library written before the
    # fields existed must aggregate exactly as it did then.
    old = [counted_entry("a", 12.0), counted_entry("b", 14.0)]
    for e in old:
        e.pop("schema")
    check("  a schema-1 library is unchanged", library.aggregate(old)["count"], 2)
    check("  digest stamps the current schema",
          library.digest({"golden": {}, "meta": {}}, "x.fit")["schema"], 6)

    # Schema 3 (engine 0.8.2): the session's own UTC offset, and the local calendar date it
    # implies. `dateUtc` stays what it always was — the UTC day — so an entry written before
    # this existed still reads correctly; `dateLocal` is the day the *rider* had, and it is
    # what the trend rows and the x-axis ticks name.
    doc = {"golden": {}, "meta": {"startUtc": "2026-08-30T22:40:00+00:00", "utcOffsetS": 7200}}
    tz = library.digest(doc, "late.fit")
    check("  digest carries the session's own offset", tz["utcOffsetS"], 7200)
    check("  dateUtc stays the UTC day", tz["dateUtc"], "2026-08-30")
    check("  dateLocal is the day the rider had", tz["dateLocal"], "2026-08-31")
    none = library.digest({"golden": {}, "meta": {"startUtc": "2026-08-30T22:40:00+00:00"}},
                          "unknown.fit")
    check("  no offset -> no local date rather than a guessed one", none["dateLocal"], None)
    check("  no offset -> null, never a zero that reads as UTC", none["utcOffsetS"], None)

    # Schema 4 (engine 0.9.1): *which rung* of the ladder produced that offset. A stored row
    # outlives the recording it was made from, so the qualification has to be stored with
    # it — an offset whose provenance was dropped reads as exact for ever, and the guess it
    # may actually have been is an hour out under DST.
    def rung(source):
        meta = {"startUtc": "2026-08-30T22:40:00+00:00", "utcOffsetS": 7200}
        if source is not None:
            meta["utcOffsetSource"] = source
        return library.digest({"golden": {}, "meta": meta}, "s.fit")["utcOffsetSource"]

    for source in ("activity", "icu", "longitude", "device"):
        check(f"  digest keeps the `{source}` rung", rung(source), source)
    check("  a digest written before schema 4 says nothing rather than 'exact'",
          rung(None), None)


# --------------------------------------------------------------- 2-4. the FIT corpus


def build_digests() -> list[dict]:
    fits = sorted(glob.glob(str(REPO / "fixtures" / "sessions" / "*" / "*.fit")))
    out = []
    for path in fits:
        name = os.path.basename(path)
        doc = web_entry.analyze_bytes(Path(path).read_bytes(), name)
        out.append(library.digest(doc, name))
    return out


def check_digest_fidelity() -> None:
    """Every digest field must equal the golden it was projected from."""
    section("2. digest fidelity against fixtures/goldens/")
    fit = REPO / "fixtures" / "sessions" / "ciq" / f"{CIQ}.fit"
    golden = json.loads((REPO / "fixtures" / "goldens" / f"{CIQ}.expected.json").read_text())
    doc = web_entry.analyze_bytes(fit.read_bytes(), fit.name)
    d = library.digest(doc, fit.name)

    s, rec = golden["summary"], golden["records"]
    check("  distanceKm == golden", d["distanceKm"], s["distanceKm"])
    check("  foilPct == golden", d["foilPct"], s["foilPct"])
    # Schema 6: CPH is the engine's rate, copied like every other number on this row. The
    # library used to divide the count by the hour itself, which was the same arithmetic
    # in a second place — and a second place is where two answers come from.
    check("  cleanJibesPerHour == golden", d["cleanJibesPerHour"], s["cleanJibesPerHour"])
    check("  flightCount == golden", d["flightCount"], s["flightCount"])
    check("  longestFlightS == golden", d["longestFlightS"], s["longestFlightS"])
    check("  turns.counted == golden", d["turns"]["counted"], s["turns"]["turnsCounted"])
    check("  turns.successPct == golden", d["turns"]["successPct"], s["turns"]["successPct"])
    # The outcome tally the library row draws on the ladder's inks (app-ui-review.md 5.6).
    # It is copied from the engine's verdict, never recounted here -- a second count would
    # be a second definition of the ladder.
    check("  turns.outcomes == golden", d["turns"]["outcomes"],
          {k: s["turns"]["outcomes"][k] for k in ("flewThrough", "touchdown", "fellIn")})
    check("  turns.outcomes sums to the counted turns",
          sum(d["turns"]["outcomes"].values()), d["turns"]["counted"])
    # A document with no outcome block gets None, never three zeroes: the row then renders
    # a dash. Three zeroes would say the rider took fifty turns and none of them went
    # anywhere, which is the "absent is never 0" rule (docs/presentation.md) at row scale.
    check("  turns.outcomes is absent, not zeroed, when the engine reported none",
          library.digest({"golden": {"summary": {"turns": {}}}}, "x.fit")["turns"]["outcomes"],
          None)
    check("  records.best2sKn == golden", d["records"]["best2sKn"], rec["best2sKn"])
    check("  records.alpha500Kn == golden", d["records"]["alpha500Kn"], rec["alpha500Kn"])
    check("  recordWindows.best2s == golden", d["recordWindows"]["best2sKn"],
          [rec["windows"]["best2s"]])
    check("  recordWindows.best5x10s carries all five", len(d["recordWindows"]["best5x10sKn"]), 5)
    check("  takeoff.avgPumpsToTakeoff == golden", d["takeoff"]["avgPumpsToTakeoff"],
          s["takeoff"]["avgPumpsToTakeoff"])

    # Known reference numbers for this session (web/README.md quotes the same ones).
    check("  known: 30 counted turns", d["turns"]["counted"], 30)
    check("  known: 23 flights", d["flightCount"], 23)
    check("  known: 12.764 km", d["distanceKm"], 12.764)
    check("  known: spot name", d["spot"], "Nago Torbole Windsurfen")
    check("  known: id", d["id"], "s1786082075-5494")

    # The port/starboard split is the one number the digest *counts* rather than copies,
    # so hand-count it here straight off the golden's own turn rows.
    hand = {"port": [0, 0], "starboard": [0, 0]}
    for t in golden["turns"]:
        if t["counted"] and t["side"] in hand:
            hand[t["side"]][0] += 1
            hand[t["side"]][1] += 1 if t["success"] else 0
    by = d["turns"]["bySide"]
    check("  hand-counted port entries", by["port"]["entries"], hand["port"][0])
    check("  hand-counted port successes", by["port"]["successes"], hand["port"][1])
    check("  hand-counted starboard entries", by["starboard"]["entries"], hand["starboard"][0])
    check("  hand-counted starboard successes", by["starboard"]["successes"],
          hand["starboard"][1])
    # Explicit, so a change to the counting rule cannot quietly re-baseline the test.
    check("  known: port 14 entries / 2 clean", (by["port"]["entries"], by["port"]["successes"]),
          (14, 2))
    check("  known: starboard 16 entries / 2 clean",
          (by["starboard"]["entries"], by["starboard"]["successes"]), (16, 2))
    check("  known: port clean 14.29 %", by["port"]["successPct"], 14.29)
    check("  known: starboard clean 12.5 %", by["starboard"]["successPct"], 12.5)
    # The two sides must add up to the engine's own counted total.
    check("  sides sum to turnsCounted",
          by["port"]["entries"] + by["starboard"]["entries"] + by["unknown"]["entries"],
          s["turns"]["turnsCounted"])
    check("  side successes sum to turnsSuccessful",
          by["port"]["successes"] + by["starboard"]["successes"] + by["unknown"]["successes"],
          s["turns"]["turnsSuccessful"])
    check("  golden agrees on the entry counts",
          (by["port"]["entries"], by["starboard"]["entries"]),
          (s["turns"]["port"], s["turns"]["starboard"]))

    json.dumps(d, allow_nan=False)          # the shape the worker posts to the UI
    check("  digest_json round trip", json.loads(library.digest_json(json.dumps(doc),
                                                                     fit.name)), d)


def check_records(digests: list[dict]) -> None:
    section("3. all-time records over the FIT corpus")
    agg = library.aggregate(digests)
    rows = {r["key"]: r for r in agg["records"]}
    # Stated, not derived from `digests`: the aggregate must actually see every session
    # fixture, and comparing it to `len(digests)` would pass on an empty corpus too.
    check("  corpus size", agg["count"], 15)

    # Independently: the winner of each kind is the max over the digests, and it must be
    # the session the aggregate names.
    for key, _w, label, _u in library.RECORD_KINDS:
        values = [(d["records"].get(key) or 0.0, d["id"]) for d in digests]
        best_value = max(v for v, _ in values)
        if best_value <= 0:
            check(f"  {label}: dropped (nobody set one)", key in rows, False)
            continue
        row = rows.get(key)
        check(f"  {label}: value", row and row["value"], round(best_value, 3))
        winners = {i for v, i in values if v == best_value}
        check(f"  {label}: session", row and row["id"] in winners, True)

    # Named winners, so the expectation is readable rather than self-fulfilling.
    check("  best 2 s = 14.99 kn on 2026-08-01",
          (rows["best2sKn"]["value"], rows["best2sKn"]["dateUtc"]), (14.99, "2026-08-01"))
    check("  best 1 NM = 11.451 kn on 2026-08-05 (foilmotion)",
          (rows["bestNmKn"]["value"], rows["bestNmKn"]["dateUtc"]), (11.451, "2026-08-05"))
    check("  alpha 500 = 11.994 kn on 2026-08-05 (foilmotion)",
          (rows["alpha500Kn"]["value"], rows["alpha500Kn"]["dateUtc"]), (11.994, "2026-08-05"))
    check("  best hour is dropped (all zero in this corpus)", "bestHourKn" in rows, False)
    check("  8 record kinds shown", len(agg["records"]), 8)

    # Every record must carry a window the UI can highlight, and it must be a real slice
    # of the session it points at.
    for row in agg["records"]:
        src = next(d for d in digests if d["id"] == row["id"])
        check(f"  {row['label']}: window present", bool(row["windows"]), True)
        for w in row["windows"]:
            in_range = 0 <= w["startTs"] <= (src["durationS"] or 0) and w["durS"] > 0
            check(f"  {row['label']}: window inside the session", in_range, True)
    check("  best 5x10 s carries five windows", len(rows["best5x10sKn"]["windows"]), 5)

    # Totals are weighted, not averaged over sessions.
    tot = agg["totals"]
    check("  totals.sessions", tot["sessions"], len(digests))
    check("  totals.turnsCounted", tot["turnsCounted"],
          sum(d["turns"]["counted"] for d in digests))
    check("  totals.turnSuccessPct is successes/turns", tot["turnSuccessPct"],
          round(100 * sum(d["turns"]["successful"] for d in digests)
                / sum(d["turns"]["counted"] for d in digests), 2))
    check("  totals.foilPct sits inside the per-session range",
          min(d["foilPct"] for d in digests) <= tot["foilPct"]
          <= max(d["foilPct"] for d in digests), True)
    check("  totals.turnsBySide sums", tot["turnsBySide"]["port"]["entries"]
          + tot["turnsBySide"]["starboard"]["entries"], tot["turnsCounted"])

    check_session_records(digests)


def check_session_records(digests: list[dict]) -> None:
    """The second records table: all-time bests that are not speeds.

    Same rules as the GP3S table (max over the counted digests, ties to the earliest
    session, a kind nobody set is dropped), so the checks are the same shape — plus the
    two rules that only exist here: the >= 5 jibes floor under the clean-jibe rate, and
    the absence of any certification badge on a row that makes no speed claim.
    """
    section("3b. session records (the non-speed table)")
    agg = library.aggregate(digests)
    rows = {r["key"]: r for r in agg["sessionRecords"]}

    for key, label, _unit, places, pick, _caption in library.SESSION_RECORD_KINDS:
        values = [(pick(d) or 0.0, d["id"]) for d in digests]
        best = max(v for v, _ in values)
        if best <= 0:
            check(f"  {label}: dropped (nobody set one)", key in rows, False)
            continue
        row = rows.get(key)
        check(f"  {label}: value", row and row["value"], round(best, places))
        check(f"  {label}: session", row and row["id"] in {i for v, i in values if v == best},
              True)
        check(f"  {label}: carries no certification badge", "certified" in (row or {}), False)

    check("  the table's order matches the catalogue",
          [r["key"] for r in agg["sessionRecords"]],
          [k for k, *_ in library.SESSION_RECORD_KINDS if k in rows])
    check("  the longest flight names its distance",
          rows["longestFlight"]["caption"].endswith("m of it"), True)
    check("  the clean-jibe rate states its floor",
          rows["bestCleanJibeRate"]["caption"], "Sessions with at least 5 jibes.")

    # The >= 5 jibes floor. Every corpus session clears it, so the boundary is drawn with
    # synthetic entries: four-for-four is a perfect afternoon and not a rate.
    def rate_of(jibes: int, clean: int):
        e = counted_entry("thin", 10.0)
        e["turns"] = dict(e["turns"], jibes=jibes, jibesSuccessful=clean)
        winners = {r["key"]: r for r in library.aggregate([e])["sessionRecords"]}
        return winners.get("bestCleanJibeRate", {}).get("value")

    check(f"  {library.MIN_JIBES_FOR_RATE - 1} jibes set no rate record",
          rate_of(library.MIN_JIBES_FOR_RATE - 1, library.MIN_JIBES_FOR_RATE - 1), None)
    check(f"  {library.MIN_JIBES_FOR_RATE} jibes do", rate_of(library.MIN_JIBES_FOR_RATE, 4),
          round(100.0 * 4 / library.MIN_JIBES_FOR_RATE, 1))

    # CPH is the engine's own rate (0.10.0), and the winner is the session that maximises
    # it — not the one with the most clean jibes.
    cph = max((d["cleanJibesPerHour"], d["id"]) for d in digests)
    check("  CPH is the engine's summary.cleanJibesPerHour", rows["bestCph"]["value"],
          round(cph[0], 2))
    check("  CPH names the session that maximises it", rows["bestCph"]["id"], cph[1])
    # …and it is **not** the division the library used to do for itself, which is why the
    # switch was worth making rather than a rename. The engine divides by its own *cleaned*
    # session span — the denominator every per-hour rate in this project shares
    # (docs/algorithms.md "Session rates") — and the digest's `durationS` is the FIT's
    # `total_elapsed_time`. On the Rheinstetten afternoon those are 7742 s and 10338 s, and
    # the library's own arithmetic reported a CPH a third too low on the page next door.
    naive = [round(d["turns"]["jibesSuccessful"] * 3600.0 / d["durationS"], 1)
             for d in digests]
    engine = [round(d["cleanJibesPerHour"], 1) for d in digests]
    check("  the corpus contains sessions the two denominators disagree about",
          sum(1 for a, b in zip(naive, engine) if a != b) > 0, True)
    check("  and the record follows the engine, not the old division",
          rows["bestCph"]["value"] in {round(v, 2) for v in
                                       (d["cleanJibesPerHour"] for d in digests)}, True)
    # A row saved before schema 6 has no rate to read, and the fallback division answers
    # for it — otherwise every afternoon in a library saved last month would drop out of
    # the CPH record and the CPH trend line.
    old = counted_entry("pre-v6", 10.0)
    old.pop("cleanJibesPerHour", None)
    check("  a pre-schema-6 row still has a CPH", library._cph(old), 3.0)

    # Ties go to the earliest session. Two synthetic entries with the same duration: the
    # older one holds the record, and adding a later equal never takes it away.
    early = counted_entry("early", 10.0, startEpoch=1000.0, durationS=3600.0)
    late = counted_entry("late", 10.0, startEpoch=2000.0, durationS=3600.0)
    tied = library.aggregate([late, early])["sessionRecords"]
    check("  a tie goes to the earliest session",
          next(r for r in tied if r["key"] == "longestSession")["id"], "early")

    # A digest saved before schema 5 carries none of the three turn counts. It must drop
    # out of those records rather than enter them as a zero.
    old = counted_entry("old", 10.0)
    old["turns"] = {"counted": 10, "successful": 4, "successPct": 40.0, "jibes": 8,
                    "bySide": {"port": {"entries": 5, "successes": 2},
                               "starboard": {"entries": 5, "successes": 2}}}
    # Schema 6's rate is the same clean count over the hour, so a row that predates the
    # count predates the rate too — there is nothing for the fallback to divide either.
    old.pop("cleanJibesPerHour")
    keys = {r["key"] for r in library.aggregate([old])["sessionRecords"]}
    check("  a pre-schema-5 digest sets no jibe record",
          keys & {"mostCleanJibes", "bestCph", "bestCleanJibeRate",
                  "longestDryStreak", "longestFlewStreak"}, set())
    check("  …but still sets the ones it can", "mostDistance" in keys, True)


def check_trends(digests: list[dict]) -> None:
    section("4. trend series shape")
    agg = library.aggregate(digests)
    tr = agg["trends"]
    n = len(digests)
    check("  one stamp per session", len(tr["sessions"]), n)
    check("  sessions are oldest first",
          [s["startUtc"] for s in tr["sessions"]],
          sorted(s["startUtc"] for s in tr["sessions"]))
    check("  seven charts", [c["key"] for c in tr["charts"]],
          ["foilPct", "longestFlight", "turnSuccess", "cleanJibes", "cph", "pumps", "turnSide"])
    for c in tr["charts"]:
        for line in c["lines"]:
            check(f"  {c['key']}/{line['key']}: one point per session", len(line["points"]), n)
            check(f"  {c['key']}/{line['key']}: indices align",
                  [p["i"] for p in line["points"]], list(range(n)))
            check(f"  {c['key']}/{line['key']}: ids align",
                  [p["id"] for p in line["points"]], [s["id"] for s in tr["sessions"]])
    split = next(c for c in tr["charts"] if c["key"] == "turnSide")
    check("  the split chart has two lines", [l["key"] for l in split["lines"]],
          ["port", "starboard"])

    # Values, not just shape: the series must be the digests' own numbers, in order.
    order = {d["id"]: d for d in digests}
    ordered = [order[s["id"]] for s in tr["sessions"]]
    foil = next(c for c in tr["charts"] if c["key"] == "foilPct")["lines"][0]
    check("  foilPct series == digests in order", [p["v"] for p in foil["points"]],
          [d["foilPct"] for d in ordered])
    port = split["lines"][0]
    check("  port series == the hand-countable split",
          [p["v"] for p in port["points"]],
          [d["turns"]["bySide"]["port"]["successPct"] for d in ordered])

    # A session with no wrist accelerometer has no pump number: the point must be a
    # documented hole (null), never a zero the chart would draw as a collapse.
    pumps = next(c for c in tr["charts"] if c["key"] == "pumps")["lines"][0]
    no_accel = [i for i, d in enumerate(ordered) if not d["hasAccel"]]
    check("  the corpus has accelerometer-less sessions to test with", bool(no_accel), True)
    check("  pumps is null where there is no accelerometer",
          all(pumps["points"][i]["v"] is None for i in no_accel), True)

    json.dumps(agg, allow_nan=False)        # the shape the worker posts to the UI
    check("  aggregate_json round trip",
          json.loads(library.aggregate_json(json.dumps(digests))), agg)

    check("  empty library aggregates cleanly",
          library.aggregate([])["totals"]["sessions"], 0)
    check("  empty library has no records", library.aggregate([])["records"], [])
    check("  single-session library still charts",
          len(library.aggregate([digests[0]])["trends"]["charts"]), 7)

    # The CPH series reads the same engine field the CPH record does, session by session.
    cph = next(c for c in tr["charts"] if c["key"] == "cph")["lines"][0]
    check("  cph == the engine's summary.cleanJibesPerHour",
          [p["v"] for p in cph["points"]],
          [None if d["cleanJibesPerHour"] is None else round(d["cleanJibesPerHour"], 3)
           for d in ordered])

    # Weeks: ISO Monday buckets in the session's own local time, zero-filled.
    weeks = tr["weeks"]
    check("  every bucket opens on a Monday",
          all(library._week_start(w["weekStart"]) == w["weekStart"] for w in weeks), True)
    starts = [datetime.strptime(w["weekStart"], "%Y-%m-%d").date() for w in weeks]
    check("  buckets are seven days apart with no gaps",
          {(b - a).days for a, b in zip(starts, starts[1:])} or {7}, {7})
    check("  the sessions all land in some bucket",
          sum(w["count"] for w in weeks), len(digests))
    check("  hours sum to the library's elapsed time",
          round(sum(w["hours"] for w in weeks), 3),
          round(sum(d["durationS"] for d in digests) / 3600.0, 3))


def check_export() -> None:
    """The bulk export must produce an archive a normal unzip can read."""
    section("5. bulk zip export (CPython zipfile, no JS zip library)")
    import io
    import tempfile
    import zipfile

    payload = b"\x00\x01\x02" * 4000
    text = json.dumps({"hello": "world"})
    out = os.path.join(tempfile.mkdtemp(prefix="wingfoil-zip-"), "library.zip")
    library.export_begin()
    library.export_add("sessions/a.fit", payload, False)
    library.export_add("sessions/a.analysis.json", text, True)
    size = library.export_finish(out)
    check("  archive written", size > 0, True)
    with zipfile.ZipFile(out) as zf:
        check("  members", sorted(zf.namelist()),
              ["sessions/a.analysis.json", "sessions/a.fit"])
        check("  FIT bytes survive", zf.read("sessions/a.fit"), payload)
        check("  JSON survives", zf.read("sessions/a.analysis.json").decode(), text)
        check("  FIT is stored, not deflated",
              zf.getinfo("sessions/a.fit").compress_type, zipfile.ZIP_STORED)
        check("  JSON is deflated",
              zf.getinfo("sessions/a.analysis.json").compress_type, zipfile.ZIP_DEFLATED)
    os.remove(out)

    # A half-built archive must be droppable, and the next export must start clean.
    library.export_begin()
    library.export_add("x.bin", b"partial")
    library.export_abort()
    try:
        library.export_add("y.bin", b"after abort")
        check("  export_add after abort raises", False, True)
    except RuntimeError:
        check("  export_add after abort raises", True, True)
    # Uint8Array-shaped input (what the worker really passes) via the to_py() duck type.
    class FakeJsProxy:                                          # noqa: D401
        def to_py(self):
            return io.BytesIO(b"proxied").getvalue()
    library.export_begin()
    library.export_add("p.bin", FakeJsProxy())
    out2 = os.path.join(tempfile.mkdtemp(prefix="wingfoil-zip-"), "p.zip")
    library.export_finish(out2)
    with zipfile.ZipFile(out2) as zf:
        check("  JS-proxy bytes survive", zf.read("p.bin"), b"proxied")
    os.remove(out2)


# --------------------------------------------------------------------------- main


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fast", action="store_true",
                    help="skip the checks that re-run the engine over fixtures/sessions/")
    args = ap.parse_args(argv)

    check_dedupe()
    check_spot_names()
    check_attribution()
    check_export()
    if not args.fast:
        digests = build_digests()
        check_digest_fidelity()
        check_records(digests)
        check_trends(digests)
    else:
        _close_section()
        print("\n(--fast: corpus checks skipped)")
        _MARK[:] = [PASSED, len(FAILED)]

    _close_section()
    print(f"\n{PASSED} passed, {len(FAILED)} failed")
    for f in FAILED:
        print(f"  FAIL {f}")
    return 1 if FAILED else 0


if __name__ == "__main__":
    raise SystemExit(main())
