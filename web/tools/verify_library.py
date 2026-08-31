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
    check("  known: port 14 entries / 2 held", (by["port"]["entries"], by["port"]["successes"]),
          (14, 2))
    check("  known: starboard 16 entries / 2 held",
          (by["starboard"]["entries"], by["starboard"]["successes"]), (16, 2))
    check("  known: port success 14.29 %", by["port"]["successPct"], 14.29)
    check("  known: starboard success 12.5 %", by["starboard"]["successPct"], 12.5)
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
    check("  corpus size", agg["count"], 14)

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


def check_trends(digests: list[dict]) -> None:
    section("4. trend series shape")
    agg = library.aggregate(digests)
    tr = agg["trends"]
    n = len(digests)
    check("  one stamp per session", len(tr["sessions"]), n)
    check("  sessions are oldest first",
          [s["startUtc"] for s in tr["sessions"]],
          sorted(s["startUtc"] for s in tr["sessions"]))
    check("  five charts", [c["key"] for c in tr["charts"]],
          ["foilPct", "longestFlight", "turnSuccess", "pumps", "turnSide"])
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
          len(library.aggregate([digests[0]])["trends"]["charts"]), 5)


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
