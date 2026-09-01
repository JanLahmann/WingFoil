#!/usr/bin/env python3
"""Headless checks for the presentation goldens — the web app's half of the contract.

`fixtures/presentation/*.expected.json` says what a session-detail screen may draw from
an analysis: how many markers per layer, how the takeoff layer splits, which record
windows can be highlighted, and what every turn filter keeps. The iOS app asserts those
numbers in `PresentationTests`; this script asserts them from the analysis documents on
this side of the repo, so a rule that drifts on one platform fails on both.

    lab/.venv/bin/python web/tools/verify_presentation.py
    lab/.venv/bin/python web/tools/verify_presentation.py --fast   # skip the engine run

Six groups:

1. **Contract shape.** Every layer and record id in a presentation golden is one the
   contract knows (design/tokens.json, the same catalogue the iOS enums are checked
   against), and the filter grid is complete — 3 types × 3 entry sides.
2. **The rules, re-derived.** The counts are recomputed here from the analysis golden,
   written out differently from the generator on purpose: two spellings of the same rule
   agreeing is evidence, one spelling agreeing with itself is not.
2b. **Flight-end folding.** A `glide_out` end is a hollow *flew through* mark, not a layer
   of its own — asserted on the fixture with the most straight-line ends to fold.
2c. **Flight-count invariants.** One takeoff starts every flight and one end stops it, so
   `takeoff.pumped + takeoff.free == flightCount == flightEnds.total`, per fixture, with the
   three end buckets partitioning the block. The pairing lines in docs/presentation.md are
   built on that arithmetic.
3. **Internal consistency.** Marker totals, takeoff totals and the filter grid have to
   add up against the analysis document's own summary block.
4. **The engine path** (skipped by `--fast`): re-analyze one FIT through `web_entry`, the
   exact call the browser makes, and check the presentation facts of the document it
   produces. This is what ties the numbers to the code the site actually runs.
5. **The share card is the block.** The exported card's stat list, for every fixture, is
   the key-metrics block the page renders — same entries, same order, same labels, same
   strings — with `lean` a strict subset of it and nothing from the tiles allowed in. A
   card is a PNG in somebody else's chat thread: no re-render, no correction, nothing
   beside it to check against. The drawing cannot be golden-tested; the content derivation
   is a pure function (`web/js/cardstats.js`) and so it is, through
   `web/tools/card_parity.mjs` (needs `node` — skipped without it).

Exit 0 = everything matched; exit 1 = the failures are listed.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path

WEB = Path(__file__).resolve().parents[1]
REPO = WEB.parent
TOOLS = WEB / "tools"
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(WEB / "lab_bundle"))

import make_presentation_goldens as gen                     # noqa: E402

GOLDENS = REPO / "fixtures" / "goldens"
PRESENTATION = REPO / "fixtures" / "presentation"
TOKENS = REPO / "design" / "tokens.json"
SESSIONS = REPO / "fixtures" / "sessions"

CIQ = "2026-08-07-0754_nago-torbole-windsurfen_ciq"
# A fixture whose flights end in a straight line: three `glide_out` ends no turn owns, which
# is what makes it the one that can prove the folding rule below.
GLIDE_OUT = "2026-08-03-0741_nago-torbole-windsurfen_native"

PASSED = 0
FAILED: list[str] = []
_MARK = [0, 0]


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


def load(stem: str) -> tuple[dict, dict]:
    """The analysis document and the presentation golden for one fixture."""
    analysis = json.loads((GOLDENS / f"{stem}{gen.SUFFIX}").read_text(encoding="utf-8"))
    facts = json.loads((PRESENTATION / f"{stem}{gen.SUFFIX}").read_text(encoding="utf-8"))
    return analysis, facts


def fixtures() -> list[str]:
    return sorted(p.name[: -len(gen.SUFFIX)] for p in PRESENTATION.glob(f"*{gen.SUFFIX}"))


# ------------------------------------------------------------ 1. contract shape


def check_shape() -> None:
    section("1. contract shape (layers, records, filter grid)")
    tokens = json.loads(TOKENS.read_text(encoding="utf-8"))
    layer_ids = {entry["id"] for entry in tokens["layers"]}
    record_ids = [entry["id"] for entry in tokens["recordWindows"]["order"]]

    check("  the record catalogue is the contract's, in order", gen.RECORD_ORDER, record_ids)
    check("  the default window is the contract's",
          gen.RECORD_DEFAULT, tokens["recordWindows"]["default"])

    names = fixtures()
    check("  every analysis golden has a presentation golden", names,
          sorted(p.name[: -len(gen.SUFFIX)] for p in GOLDENS.glob(f"*{gen.SUFFIX}")))

    for stem in names:
        _, facts = load(stem)
        check(f"  {stem}: marker layers are legend chips",
              set(facts["markers"]) - layer_ids, set())
        check(f"  {stem}: record windows are catalogue entries",
              [k for k in facts["recordWindows"] if k not in record_ids], [])
        check(f"  {stem}: record windows keep catalogue order",
              facts["recordWindows"],
              [k for k in record_ids if k in facts["recordWindows"]])
        check(f"  {stem}: the flight-end buckets are the three the rules distinguish",
              sorted(facts["flightEnds"]), ["drawn", "ownedByTurn", "total", "truncated"])
        check(f"  {stem}: the filter grid is complete",
              [(row["type"], row["side"]) for row in facts["filters"]],
              [(t, s) for t in gen.TYPE_FILTERS for s in gen.SIDE_FILTERS])
        check(f"  {stem}: bestHour is not offered",
              "bestHour" in facts["recordWindows"], False)
        check(f"  {stem}: there is no glided-out layer",
              "glideOut" in facts["markers"], False)


# --------------------------------------------------------- 2. the rules, again


def check_rules() -> None:
    section("2. eligibility rules, re-derived from the analysis documents")
    for stem in fixtures():
        doc, facts = load(stem)

        # Markers. Written as two Counters rather than as the generator's loop: an
        # uncounted turn is a course change whatever its outcome says, a drawn flight end
        # is one no turn owns from a recording that did not stop, and `glide_out` is the
        # green end of the ladder.
        turns = Counter(t["outcome"] if t["counted"] else "course"
                        for t in doc.get("turns", []))
        ends = Counter(e["outcome"] for e in doc.get("flightEnds", [])
                       if e.get("ownedByTurn") is None and not e.get("truncated", False))
        want = {
            "flewThrough": turns["flew_through"] + turns["glide_out"]
                           + ends["flew_through"] + ends["glide_out"],
            "touchdown": turns["touchdown"] + ends["touchdown"],
            "fellIn": turns["fell_in"] + ends["fell_in"],
            "courseChange": turns["course"],
        }
        check(f"  {stem}: markers per layer", facts["markers"], want)
        # An end with no verdict is a recording that stopped, not an event; if one ever
        # survives the ownership filter the ladder above would silently paint it green.
        check(f"  {stem}: no drawn flight end has an unknown outcome", ends["unknown"], 0)

        # Takeoffs: the successes come from `takeoffs` (the engine only writes one for a
        # flight that happened), the failures only from the pumping episodes.
        episodes = Counter(ep["outcome"] for ep in doc.get("pumpEpisodes", []))
        free = sum(1 for k in doc.get("takeoffs", []) if k["free"])
        check(f"  {stem}: takeoff layer",
              facts["takeoff"],
              {"pumped": len(doc.get("takeoffs", [])) - free, "free": free,
               "failed": episodes["failed"],
               "total": len(doc.get("takeoffs", [])) + episodes["failed"]})
        check(f"  {stem}: recovery and in-flight pumping are never drawn",
              facts["pumpingSpans"], episodes["success"] + episodes["failed"])
        check(f"  {stem}: recovery / in-flight / unknown episodes stay out",
              len(doc.get("pumpEpisodes", [])) - facts["pumpingSpans"],
              episodes["recovery"] + episodes["in_flight"] + episodes["unknown"])

        # Splashes: the engine's flags, both channels, never re-derived.
        splash = sum(1 for t in doc.get("turns", []) if t["submerged"] and t["counted"])
        splash += sum(1 for e in doc.get("flightEnds", [])
                      if e["submerged"] and e.get("ownedByTurn") is None
                      and not e.get("truncated", False))
        check(f"  {stem}: splash evidence", facts["splash"], splash)

        # Record windows: a value AND the provenance the map draws with it.
        records = doc.get("records", {})
        windows = records.get("windows", {}) or {}
        achieved = [k for k in gen.RECORD_ORDER
                    if (records.get(f"{k}Kn") or 0) > 0 and windows.get(k)]
        check(f"  {stem}: achieved record windows", facts["recordWindows"], achieved)
        check(f"  {stem}: default window",
              facts["defaultRecordWindow"],
              gen.RECORD_DEFAULT if gen.RECORD_DEFAULT in achieved else None)

        # Filters: type × ENTRY side, ANDed, over counted turns only.
        counted = [t for t in doc.get("turns", []) if t["counted"]]
        for row in facts["filters"]:
            kept = [t for t in counted
                    if (row["type"] == "both"
                        or t["type"] == ("jibe" if row["type"] == "jibes" else "tack"))
                    and (row["side"] == "both" or t["side"] == row["side"])]
            check(f"  {stem}: filter {row['type']}/{row['side']} count",
                  row["count"], len(kept))
            check(f"  {stem}: filter {row['type']}/{row['side']} flew through",
                  row["flewThrough"],
                  sum(1 for t in kept if t["outcome"] in ("flew_through", "glide_out")))


# --------------------------------------------- 2c. the flight-count invariants

def check_flight_invariants() -> None:
    """One takeoff starts every flight; one end stops it.

    docs/presentation.md, "Enforcement" 3. The pairing lines a popover draws
    ("starts flight 12 · 1:23 · ended: touchdown") are only meaningful if the three blocks
    are the same list of flights seen from three sides, so the arithmetic is pinned per
    fixture rather than trusted: a takeoff with no flight to name, or a flight with two
    ends, would print a wrong number in a callout long before any tally looked odd.

    `failed` attempts are deliberately outside both sums — a failed attempt is the one mark
    in the takeoff layer that starts no flight, and folding it in would hide exactly the
    thing the layer exists to show.
    """
    section("2c. flight-count invariants (one takeoff and one end per flight)")
    for stem in fixtures():
        doc, facts = load(stem)
        count = facts["flightCount"]
        ends = facts["flightEnds"]

        check(f"  {stem}: flightCount is the engine's own",
              count, doc.get("summary", {}).get("flightCount"))
        check(f"  {stem}: ... and the length of the flights block",
              count, len(doc.get("flights", [])))
        check(f"  {stem}: takeoff marks that flew == flightCount",
              facts["takeoff"]["pumped"] + facts["takeoff"]["free"], count)
        check(f"  {stem}: flight-end marks total == flightCount", ends["total"], count)
        check(f"  {stem}: the end buckets partition the block",
              ends["drawn"] + ends["ownedByTurn"] + ends["truncated"], ends["total"])
        check(f"  {stem}: the drawn ends are the ones the marker rules keep",
              ends["drawn"], len(gen.drawn_flight_ends(doc)))
        # The pairing reads `flights[i]` through the takeoff drawn at its start, so the two
        # lists have to line up index for index — not merely have the same length.
        pairs = list(zip(doc.get("takeoffs", []), doc.get("flights", [])))
        check(f"  {stem}: takeoff i starts flight i", len(pairs), count)
        check(f"  {stem}: ... at the same instant",
              [i for i, (k, f) in enumerate(pairs) if k["startTs"] != f["startTs"]], [])
        check(f"  {stem}: flight end i stops flight i",
              [e["flightIndex"] for e in doc.get("flightEnds", [])], list(range(count)))
        check(f"  {stem}: ... at the same instant",
              [i for i, (e, f) in enumerate(zip(doc.get("flightEnds", []),
                                                doc.get("flights", [])))
               if e["ts"] != f["endTs"]], [])
        # A failed attempt is not a flight: it must be in neither sum.
        check(f"  {stem}: failed attempts start no flight",
              facts["takeoff"]["total"] - facts["takeoff"]["failed"], count)


# ------------------------------------------------- 2b. flight ends fold into the ladder


def check_flight_end_folding() -> None:
    """A `glide_out` flight end is a *flew through* mark drawn hollow, not a layer of its own.

    docs/presentation.md, "Colour and glyph vocabulary": the ladder carries the verdict and
    the fill carries the channel — solid = a maneuver's outcome, hollow = a straight-line
    flight end no turn explains. A separate "glided out" chip (which the web app used to
    have) says the same thing twice and makes the two platforms count differently, so this
    asserts the folding on the fixture that has the most straight-line ends to fold.
    """
    section("2b. glide-out flight ends fold into flewThrough (hollow, same ladder)")
    doc, facts = load(GLIDE_OUT)
    ends = Counter(e["outcome"] for e in gen.drawn_flight_ends(doc))
    turns = Counter(t["outcome"] for t in doc.get("turns", []) if t["counted"])

    # Without ends to fold the rest of this section would pass vacuously.
    check(f"  {GLIDE_OUT}: has straight-line glide-outs to fold", ends["glide_out"], 3)
    check(f"  {GLIDE_OUT}: they are counted under flewThrough",
          facts["markers"]["flewThrough"], turns["flew_through"] + ends["glide_out"])
    check(f"  {GLIDE_OUT}: and they are the difference — a turns-only count is short",
          facts["markers"]["flewThrough"] - turns["flew_through"], ends["glide_out"])
    check(f"  {GLIDE_OUT}: no glide-out chip exists to hold them",
          sorted(facts["markers"]), ["courseChange", "fellIn", "flewThrough", "touchdown"])
    # The hollow half must not leak into a verdict tally: the filter grid is turns only.
    grid = {(row["type"], row["side"]): row for row in facts["filters"]}
    check(f"  {GLIDE_OUT}: the filter grid counts turns, not ends",
          grid[("both", "both")]["flewThrough"], turns["flew_through"] + turns["glide_out"])


# ------------------------------------------------------ 3. internal consistency


def check_consistency() -> None:
    section("3. the counts agree with the analysis document's own summary")
    for stem in fixtures():
        doc, facts = load(stem)
        grid = {(row["type"], row["side"]): row for row in facts["filters"]}
        summary = doc.get("summary", {})
        turns = summary.get("turns", {})
        takeoff = summary.get("takeoff", {})

        check(f"  {stem}: the unfiltered tally is turnsCounted",
              grid[("both", "both")]["count"], turns.get("turnsCounted"))
        check(f"  {stem}: course-change markers are the rejected sweeps",
              facts["markers"]["courseChange"], turns.get("rejected"))
        check(f"  {stem}: port + starboard + unknown is the whole grid",
              grid[("both", "port")]["count"] + grid[("both", "starboard")]["count"]
              + turns.get("unknownSide", 0),
              grid[("both", "both")]["count"])
        check(f"  {stem}: jibes + tacks + unclassified is the whole grid",
              grid[("jibes", "both")]["count"] + grid[("tacks", "both")]["count"]
              + turns.get("unclassified", 0),
              grid[("both", "both")]["count"])
        check(f"  {stem}: the takeoff layer is the engine's attempts",
              facts["takeoff"]["pumped"] + facts["takeoff"]["free"],
              takeoff.get("takeoffSuccesses"))
        check(f"  {stem}: failed attempts are the engine's",
              facts["takeoff"]["failed"], takeoff.get("failedAttempts"))
        # The free/pumped split is only a *claim* where the source has a wrist
        # accelerometer. Without one the engine reports neither, every takeoff carries
        # `free: false`, and both apps draw the filled arrow — identically, which is what
        # this asserts. That is now written down rather than merely observed:
        # docs/presentation.md, "Takeoff glyphs" — "On sources without an accelerometer
        # stream every takeoff renders as the filled (pumped) arrow; free takeoffs cannot
        # be distinguished without stroke counts."
        if doc.get("capabilities", {}).get("hasAccel"):
            check(f"  {stem}: free + pumped takeoffs are the engine's split",
                  [facts["takeoff"]["free"], facts["takeoff"]["pumped"]],
                  [takeoff.get("freeTakeoffs"), takeoff.get("pumpedTakeoffs")])
        else:
            check(f"  {stem}: without an accelerometer every takeoff is drawn pumped",
                  [facts["takeoff"]["free"], facts["takeoff"]["pumped"]],
                  [0, len(doc.get("takeoffs", []))])
        check(f"  {stem}: the marker total is turns + drawn ends",
              sum(facts["markers"].values()),
              len(doc.get("turns", []))
              + len(gen.drawn_flight_ends(doc)))


# ----------------------------------------------------------- 4. the engine path


def check_engine() -> None:
    section("4. the same facts out of web_entry (the call the browser makes)")
    found = sorted(SESSIONS.rglob(f"{CIQ}.fit"))
    if not found:
        print(f"  (skipped: {CIQ}.fit not found under fixtures/sessions)")
        return
    fit = found[0]
    try:
        import web_entry                                     # noqa: PLC0415
    except Exception as exc:                                 # pragma: no cover
        print(f"  (skipped: web_entry not importable: {exc})")
        return

    result = json.loads(web_entry.analyze_json(fit.read_bytes(), fit.name))
    doc = result["golden"]
    _, facts = load(CIQ)
    fresh = gen.facts(CIQ, doc)
    for key in ("markers", "flightCount", "flightEnds", "takeoff", "splash", "pumpingSpans",
                "recordWindows", "defaultRecordWindow", "filters"):
        check(f"  {CIQ}: {key} from a fresh analysis", fresh[key], facts[key])
    # The one number the whole layer exists for, stated out loud.
    check(f"  {CIQ}: failed takeoff attempts", fresh["takeoff"]["failed"], 14)
    check_session_clock(result)


def check_session_clock(result: dict) -> None:
    """The web half of `SessionTimeZoneTests`: this page reads on the session's clock.

    The fixture is `2026-08-07-0754_…`, and the filename is the assertion: the rider was on
    the water at **07:54** on 7 August. The recording says 05:54:35 UTC. Until engine 0.8.2
    the page had nothing to bridge the two with — `meta` carried the instant and the browser
    formatted it wherever the reader happened to be, so the heading was right in Italy in
    August and wrong everywhere and everywhen else. `meta.utcOffsetS` is what fixes it, and
    this asserts the arithmetic every clock on the page now goes through (`zonedFormat` in
    web/js/viz.js), in Python, so the machine's own clock cannot supply the answer.

    The expected strings are taken from the fixture's **filename**, which is what a rider
    wrote down: a change that made this fail would be a change that made the page disagree
    with the file it is showing.
    """
    stamp = CIQ.split("_")[0]                       # "2026-08-07-0754"
    day, clock = stamp[:10], f"{stamp[11:13]}:{stamp[13:15]}"
    meta = result["meta"]
    check("  meta carries the session's own UTC offset", meta["utcOffsetS"], 7200)
    start = datetime.fromisoformat(meta["startUtc"]).astimezone(timezone.utc)
    check("  the instant underneath is untouched (UTC)",
          start.strftime("%H:%M:%S"), "05:54:35")
    # `zonedFormat`, spelled out: shift by the offset, then read in UTC. The naive rendering
    # on a UTC machine says 05:54; the session's own clock says what the filename says.
    shown = start + timedelta(seconds=meta["utcOffsetS"])
    check("  the page's heading reads on the session's clock",
          shown.strftime("%H:%M"), clock)
    check("  …and dates it on the session's calendar day",
          shown.strftime("%Y-%m-%d"), day)
    # Engine 0.9.1: *which rung* answered. This fixture's watch wrote the offset down, so
    # the page is entitled to state the clock as fact — and the assertion is worth making
    # because the same +7200 could have come off the longitude guess, which for this
    # longitude would have said +3600 and been an hour wrong.
    check("  …and says which rung of the ladder answered", meta["utcOffsetSource"], "activity")
    check_clock_note()


#: The exact sentences the header may print, per source (docs/presentation.md "Session
#: time"). Written here rather than imported so the JavaScript is checked against a second
#: copy of the contract instead of against itself — the same rule §5 follows for the card.
EXACT_NOTE = " \u00b7 times as recorded on the water"
ESTIMATED_NOTE = " \u00b7 times estimated from the track's position"
NO_ZONE_NOTE = " \u00b7 no timezone in this file \u2014 times shown on your own clock"

CLOCK_NOTE = TOOLS / "clock_note.mjs"


def check_clock_note() -> None:
    """The note the page prints under the title, one case per rung of the ladder.

    This is the only sentence on the page that tells a reader whether to *trust* a clock,
    and until engine 0.9.1 it said "times as recorded on the water" over an offset that
    could be a solar guess from longitude — an hour out under DST, and the normal case for
    a GPX, which carries no zone at all. The wording now follows `meta.utcOffsetSource`,
    and the strings come out of `render.js` itself (via `clock_note.mjs`) so this cannot
    pass against a copy of the rule that the browser does not run.
    """
    node = shutil.which("node")
    if not node:
        print("  (skipped: node not on PATH — clock note unchecked)")
        return
    try:
        raw = subprocess.run([node, str(CLOCK_NOTE)], capture_output=True, text=True,
                             check=True, cwd=REPO).stdout
    except (subprocess.CalledProcessError, OSError) as exc:                 # pragma: no cover
        check("  clock_note.mjs runs", f"failed: {exc}", "ok")
        return
    notes = json.loads(raw)
    # The two exact rungs make the same claim, because they are the same kind of fact.
    check("  an `activity` offset states the clock", notes["activity"], EXACT_NOTE)
    check("  an `icu` offset states it too", notes["icu"], EXACT_NOTE)
    # The one that had been over-claiming.
    check("  a `longitude` offset softens to an estimate", notes["longitude"], ESTIMATED_NOTE)
    # Not the session's zone at all — the reader has to be told whose clock this is.
    check("  `device` names the reader's own clock", notes["device"], NO_ZONE_NOTE)
    check("  …and so does a missing offset", notes["absent"], NO_ZONE_NOTE)
    # A pre-0.9.1 document cannot say which rung it used. Inventing a caveat there would be
    # as wrong as inventing a certainty, so it keeps the wording it always had.
    check("  an unrecorded source keeps the old wording", notes["unrecorded"], EXACT_NOTE)


# --------------------------------------------- 5. the share card is the block

CARD_PARITY = TOOLS / "card_parity.mjs"

#: What `lean` is allowed to keep — `ShareCardStats.Preset.leanKeys`, spelled here so the
#: JavaScript is checked against a second copy of the rule rather than against itself.
LEAN_KEYS = ["distance", "duration", "max2s", "tally"]

#: Keys that must never reach a card. They are real numbers the app shows — in the *tiles*,
#: below the block — and a card that printed them would be a second, quieter answer to "was
#: that a good session" travelling in a picture next to the loud one. (iOS gives its clip
#: outro a ninth `longestFlight` cell; the exported card there does not get it either.)
FORBIDDEN_KEYS = {"flightCount", "flights", "foilPct", "longestFlight", "best500m", "wind"}


def _hm(sec: float) -> str:
    """`1:25 h` / `10:45 min`, written out again — the Python spelling of the block's
    duration rule (`KeyMetrics.duration`, `hm` in web/js/cardstats.js).

    Under an hour it is minutes and seconds, because `h:mm` printed `0:11` for the ten
    minute forty-five second example session and a card is the last place a number may be
    rounded into meaninglessness. The unit rides inside the string, as `km` and `kn` do in
    every other cell, so `10:45` can never be read as ten and three quarter hours.
    """
    total = max(0, round(sec))
    if total >= 3600:
        m = round(total / 60)
        return f"{m // 60}:{m % 60:02d} h"
    return f"{total // 60}:{total % 60:02d} min"


def expected_card_values(doc: dict) -> dict[str, str]:
    """The block's strings, re-derived here from the analysis golden.

    Deliberately a *third* implementation (Swift, JavaScript, and this): the JS card and the
    JS block agreeing proves they share a list, which they do by construction; it does not
    prove the list says the right thing. These do.
    """
    s, t, rec = doc["summary"], doc["summary"]["turns"], doc["records"]
    out = {
        "duration": _hm(s["durationS"]),
        "distance": f"{s['distanceKm']:.1f} km",
        "avgSpeed": "—" if s.get("avgSpeedKmh") is None
                    else f"{s['avgSpeedKmh'] / 1.852:.2f} kn",
        "max2s": f"{rec['best2sKn']:.2f} kn" if rec["best2sKn"] >= 0.05 else "—",
    }
    outcomes = t["jibeOutcomes"] if t["jibes"] > 0 else t["outcomes"]
    if t["jibes"] > 0 or t["turnsCounted"] > 0:
        out["tally"] = (f"{outcomes['flewThrough']} · {outcomes['touchdown']} · "
                        f"{outcomes['fellIn']}")
    if t["turnsCounted"] > 0:
        # Flying leads the pair: the harder run first, and `longestFlewStreak` is always
        # the smaller of the two.
        out["streaks"] = f"{t['longestFlewStreak']} flew · {t['longestDryStreak']} dry"
    if s.get("wetPerHour") is not None:
        if s["jibesPerHour"] > 0 or not s["turnsPerHour"] > 0:
            out["jph"] = f"{s['jibesPerHour']:.1f}"
        else:
            out["tph"] = f"{s['turnsPerHour']:.1f}"
        out["wph"] = f"{s['wetPerHour']:.1f}"
    return out


def check_card() -> None:
    """The exported card says exactly what the key-metrics block says.

    A card is a PNG in somebody else's chat thread: there is no re-render, no correction and
    nothing beside it to check against, so it is the last place the app may name a different
    number for the same session than the page does. `web/js/cardstats.js` makes that
    structurally true — one list, two readers — and this is what proves it stayed true, over
    every fixture, on the *rendered markup* rather than on the array behind it.

    The drawing cannot be golden-tested (a canvas is pixels). The content derivation is a
    pure function, and therefore can be, and therefore must be.
    """
    section("5. the share card carries the key-metrics block, unchanged")

    goldens = sorted(GOLDENS.glob(f"*{gen.SUFFIX}"))
    node = shutil.which("node")
    if not node:
        print("  (skipped: node not on PATH)")
        return
    try:
        raw = subprocess.run([node, str(CARD_PARITY), *[str(p) for p in goldens]],
                             capture_output=True, text=True, check=True, cwd=REPO).stdout
    except subprocess.CalledProcessError as exc:              # pragma: no cover
        FAILED.append(f"  card_parity.mjs failed\n{exc.stderr.strip()}")
        return
    cards = json.loads(raw)

    check("  every analysis golden was measured", len(cards), len(goldens))
    for card in cards:
        stem = Path(card["file"]).name[: -len(gen.SUFFIX)]
        doc = json.loads(Path(REPO / card["file"]).read_text(encoding="utf-8"))
        block = card["block"]
        complete = card["complete"]
        lean = card["lean"]

        # 1. Complete IS the block: same entries, same order, same words, same strings.
        check(f"  {stem}: complete == the rendered block",
              [{"label": e["label"], "value": e["value"]} for e in complete], block)

        # 2. Lean is a strict SUBSET — it may drop entries and may not reword, reorder or
        #    substitute one. Held as keys, so a preset cannot invent a cell.
        check(f"  {stem}: lean is the block filtered by leanKeys",
              lean, [e for e in complete if e["key"] in LEAN_KEYS])
        check(f"  {stem}: lean keeps the block's order",
              [e["key"] for e in lean],
              [e["key"] for e in complete if e["key"] in LEAN_KEYS])

        # 3. Nothing the block does not carry may appear on a card.
        keys = {e["key"] for e in complete}
        check(f"  {stem}: no tile-only cell reached the card", keys & FORBIDDEN_KEYS, set())

        # 4. The strings themselves, re-derived from the golden by a third implementation.
        want = expected_card_values(doc)
        check(f"  {stem}: the card's values, re-derived",
              {e["key"]: e["value"] for e in complete}, want)

        # 5. The tally's three counts stay counts, so the card can wear the ladder's inks —
        #    and they are the same three the value string spells out.
        tally = next((e for e in complete if e["key"] == "tally"), None)
        if tally is not None:
            counts = tally["tally"]
            check(f"  {stem}: the tally cell carries its counts",
                  f"{counts['flewThrough']} · {counts['touchdown']} · {counts['fellIn']}",
                  tally["value"])
            t = doc["summary"]["turns"]
            source = t["jibeOutcomes"] if t["jibes"] > 0 else t["outcomes"]
            check(f"  {stem}: the tally counts are the golden's own",
                  counts, {k: source[k] for k in ("flewThrough", "touchdown", "fellIn")})

    if cards:
        check("  leanKeys is the contract's set", cards[0]["leanKeys"], LEAN_KEYS)


CARD_TEXT = TOOLS / "card_text.mjs"

#: The caption's cap, and the title's — `SessionNaming.noteLimit` / `.titleLimit` on iOS,
#: spelled here so the JavaScript is checked against a second copy of the rule rather than
#: against itself. Eighty is about one line of chat, and about what the card's header sets on
#: one line at a size a chat thumbnail still resolves.
NOTE_LIMIT = 80
TITLE_LIMIT = 60

#: The header with no caption on it, in layout points, and what one costs — the only piece of
#: the card's geometry that depends on its content. `HEADER_BASE_H` is the number the card has
#: always laid out against, and the point of asserting it is that a card *without* a caption
#: must be the card it was before the field existed, down to the point.
HEADER_BASE_H = 42
NOTE_LINE_H = 14

#: The sport, and the words a Garmin watch writes instead of it — `SessionNaming.sport` and
#: `SessionNaming.sportCorrected` on iOS, spelled here so the JavaScript is checked against a
#: second copy of the rule. The watch has no wingfoil profile, so it records under the windsurf
#: one and names the activity after it, in the watch's own locale; the word then rides the
#: filename into every derived title on both platforms.
SPORT = "Wingfoil"
GARMIN_SPORT_WORDS = {"windsurfen", "windsurfing", "windsurf"}


def _derived_title(file_name: str) -> str:
    """`cardTitle`, re-derived: the middle underscore-part, hyphens to spaces, every all-digit
    word dropped, each word capitalised — and Garmin's sport word swapped for ours where it
    stands alone."""
    stem = re.sub(r"\.[^./\\]+$", "", file_name)
    parts = stem.split("_")
    if len(parts) >= 2:
        stem = parts[1]
    words = [w for w in stem.replace("-", " ").split(" ") if w and not w.isdigit()]
    if not words:
        return "Session"
    out = []
    for word in words:
        capped = word[0].upper() + word[1:]
        out.append(SPORT if capped.lower() in GARMIN_SPORT_WORDS else capped)
    return " ".join(out)


def check_card_text() -> None:
    """The rider's own title and caption: normalized, remembered, and out of the numbers.

    Three promises, and the failure mode of each is a card in somebody else's chat thread:
    a caption that ran off the edge, a session whose caption came back attached to the wrong
    afternoon, and — the one that matters most — a caption that displaced a metric. The last
    is why `statsUnchanged` is asserted here rather than trusted: §5 proves the card's cells
    are the block's cells, and this proves the caption did not quietly become a cell.

    The dialog itself is a `<dialog>` with a canvas in it and is not scriptable from here
    (`verify_library.py` covers the Python library, not the DOM). What is asserted instead is
    everything the dialog calls, which is where all the rules live.
    """
    section("5b. the rider's own title and caption")

    goldens = sorted(GOLDENS.glob(f"*{gen.SUFFIX}"))
    node = shutil.which("node")
    if not node:
        print("  (skipped: node not on PATH)")
        return
    if not goldens:
        print("  (skipped: no analysis goldens)")
        return
    try:
        raw = subprocess.run([node, str(CARD_TEXT), *[str(p) for p in goldens]],
                             capture_output=True, text=True, check=True, cwd=REPO).stdout
    except subprocess.CalledProcessError as exc:              # pragma: no cover
        FAILED.append(f"  card_text.mjs failed\n{exc.stderr.strip()}")
        return
    got = json.loads(raw)

    check("  the caps are the contract's", got["limits"],
          {"note": NOTE_LIMIT, "title": TITLE_LIMIT})

    # 1. A caption is one trimmed, capped line. Re-derived here rather than copied out of the
    #    JavaScript's answer: trim, fold every run of newlines to one space, cap, trim again.
    for raw_text, want_js in got["notes"]:
        folded = " ".join(part for part in re.split(r"[\r\n]+", raw_text))
        want = folded.strip()
        if len(want) > NOTE_LIMIT:
            want = want[:NOTE_LIMIT].strip()
        check(f"  cleanNote({raw_text[:24]!r}…)", want_js, want)
        check("  a stored caption never ends in whitespace", want_js.strip(), want_js)

    for raw_text, want_js in got["titles"]:
        want = raw_text.strip()
        if len(want) > TITLE_LIMIT:
            want = want[:TITLE_LIMIT].strip()
        check(f"  cleanTitle({raw_text[:24]!r}…)", want_js, want)

    # 1b. The derived name, and its one correction. A card exported from the browser must not
    #     caption a wingfoil session with the profile Garmin happened to record it under —
    #     the same swap `SessionDisplay.derivedTitle` makes on the phone, on the same words.
    check("  the sport is spelled one way", got["sport"], SPORT)
    for name, want_js in got["derived"]:
        check(f"  cardTitle({name[:34]!r})", want_js, _derived_title(name))
    derived = dict(got["derived"])
    check("  Garmin's German word is displayed as the sport",
          derived["2026-08-30-1407_nago-torbole-windsurfen_ciq.fit"], "Nago Torbole Wingfoil")
    check("  and so is the English one",
          derived["2026-08-30-1407_nago-torbole-windsurfing_native.fit"],
          "Nago Torbole Wingfoil")
    check("  and so does a session synced from intervals.icu",
          derived["i123_nago-torbole-windsurfen_icu.fit"], "Nago Torbole Wingfoil")
    check("  the word has to stand alone", derived["windsurfschule-torbole.fit"],
          "Windsurfschule Torbole")

    # 2. The per-session key is the digest's own id, re-derived from `meta` — so a document
    #    opened out of the library and the same document freshly analysed remember one
    #    caption between them rather than two.
    start = datetime(2026, 8, 30, 12, 7, tzinfo=timezone.utc).timestamp()
    try:
        import library as lib                                # noqa: PLC0415
        want_id = lib._session_id(start, 5000.4, "a.fit")
    except Exception:                                        # pragma: no cover
        want_id = f"s{int(start)}-{round(5000.4)}"           # the rule, second copy
    check("  the key is the digest's session id", got["keys"][0], want_id)
    check("  the timer time is the duration's fallback", got["keys"][1], "s1788091620-120")
    # A recording with no clock cannot be identified by one. The two implementations need not
    # spell that branch the same way — nothing but the browser's own storage reads it — but it
    # must be stable and it must not collide with the dated form.
    check("  a clockless recording keys on its filename", got["keys"][2], "xno-clock.fit")
    check("  and never on the dated form", got["keys"][2].startswith("s"), False)

    # 3. The round trip, including every way `localStorage` fails.
    s = got["storage"]
    empty = {"title": "", "note": ""}
    check("  nothing remembered reads as the empty pair",
          s["emptyBeforeAnythingIsWritten"], empty)
    check("  what comes back is what went in, normalized",
          s["afterWriting"], {"title": "First 20 kn", "note": "cold and glassy at last"})
    check("  it is stored normalized, not normalized on the way out",
          s["storedRaw"], s["afterWriting"])
    check("  a second session is a second entry", s["otherSession"],
          {"title": "Другое", "note": ""})
    check("  and does not disturb the first", s["firstStillThere"], s["afterWriting"])
    check("  clearing both fields reads back empty", s["afterClearing"], empty)
    check("  and removes the entry rather than storing two blanks",
          s["keysAfterClearing"], ["s9-9"])
    check("  the map is bounded", s["boundedTo"], 50)
    check("  the oldest entry is the one evicted", s["oldestStillThere"], False)
    check("  the newest is kept", s["newestStillThere"], True)
    # A share dialog that could not open because a preference could not be read would be the
    # worst possible trade — so every one of these is the empty pair, and none of them throws.
    check("  somebody else's JSON under our key reads as nothing",
          s["arrayUnderTheKey"], empty)
    check("  and so does unparseable text", s["garbageUnderTheKey"], empty)
    check("  a browser with no storage reads as nothing", s["withoutStorage"], empty)
    check("  and writing to one is a silent no-op", s["writeThrewWithoutStorage"], False)

    # 4. The geometry. Absent, the header is the header the card has always had.
    h = got["header"]
    check("  no caption: the header is unchanged", h["plain"], HEADER_BASE_H)
    check("  a cleared caption is no caption", h["cleared"], HEADER_BASE_H)
    check("  a caption costs one line", h["named"], HEADER_BASE_H + NOTE_LINE_H)

    # 5. The content. A typed title replaces the one derived from the filename; a cleared one
    #    gives it back; and neither field may touch a single number on the card.
    c = got["content"]
    check("  the derived title is the default", c["plain"]["title"], "Nago Torbole")
    check("  and carries no caption", c["plain"]["note"], None)
    check("  a typed title wins", c["named"]["title"], "First 20 kn")
    check("  a typed caption is carried, trimmed", c["named"]["note"], "cold and glassy")
    check("  a cleared title gives the derived one back", c["cleared"]["title"],
          "Nago Torbole")
    check("  a cleared caption is no caption", c["cleared"]["note"], None)
    check("  THE CAPTION IS NOT A CELL: the stats are untouched", c["statsUnchanged"], True)
    check("  and so is the disclaimer", c["disclaimerUnchanged"], True)
    check("  and so is the date line", c["dateUnchanged"], True)


# --------------------------------------------------------------------- main


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fast", action="store_true",
                    help="skip group 4 (re-running the engine over a fixture FIT)")
    args = ap.parse_args(argv)

    if not PRESENTATION.is_dir() or not fixtures():
        print("fixtures/presentation is empty — run "
              "python3 web/tools/make_presentation_goldens.py", file=sys.stderr)
        return 1

    check_shape()
    check_rules()
    check_flight_invariants()
    check_flight_end_folding()
    check_consistency()
    if args.fast:
        _close_section()
        print("\n(--fast: the engine run was skipped)")
        _MARK[:] = [PASSED, len(FAILED)]
    else:
        check_engine()
    check_card()
    check_card_text()

    _close_section()
    print(f"\n{PASSED} passed, {len(FAILED)} failed")
    for f in FAILED:
        print(f"  FAIL {f}")
    return 1 if FAILED else 0


if __name__ == "__main__":
    raise SystemExit(main())
