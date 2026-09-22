#!/usr/bin/env python3
"""Headless checks for the presentation goldens — the web app's half of the contract.

`fixtures/presentation/*.expected.json` says what a session-detail screen may draw from
an analysis: how many markers per layer, how the takeoff layer splits, which record
windows can be highlighted, and what every turn filter keeps. The iOS app asserts those
numbers in `PresentationTests`; this script asserts them from the analysis documents on
this side of the repo, so a rule that drifts on one platform fails on both.

    lab/.venv/bin/python web/tools/verify_presentation.py
    lab/.venv/bin/python web/tools/verify_presentation.py --fast   # skip the engine run

**What this file is for, after ADR-033 round 3.** It used to re-derive every presentation
fact a *third* time — Swift, JavaScript, and here — so that the first two could be compared
against a rule rather than against each other. That was a good mechanism and it is why the
surfaces agree today. It was also the sign of the problem: a fact that needs a third
implementation to stay true is a fact with no owner. The facts have an owner now
(`build_presentation`), the goldens pin them for both platforms, and the re-derivations
below are **retired**. What is left is the two kinds of check a document cannot make:
whether the *browser* reads it, and the things the document deliberately does not carry.

1–2, 5. **The browser reads the document** — one check per retired group. The values
   themselves are pinned once, in `fixtures/presentation/*.expected.json`, by
   `lab/tests/test_presentation.py` and `GoldenTests.presentationDocumentMatchesTheGoldenByte`.
3. **Internal consistency.** Marker totals, takeoff totals and the filter grid have to
   add up against the analysis document's own summary block. **Kept deliberately**: it ties
   the document to the *analysis*, which is the engine's half of the contract rather than
   presentation's, and it is the check that would catch `build_presentation` mis-reading a
   golden.
4. **The engine path** (skipped by `--fast`): re-analyze one FIT through `web_entry`, the
   exact call the browser makes, and check the presentation facts of the document it
   produces. **Kept**: it is about the browser's call path — Pyodide, the worker, `meta` —
   and about the session clock and its note, which are `meta` facts the analysis document
   does not carry.
5b. **The rider's own title and caption.** The normalizers, the per-session key, the
   `localStorage` round trip and the one piece of the card's geometry that depends on what
   was typed. **Kept for ever**: a title and a caption are the sender's own words, not facts
   about the session, and the document must never carry them.
5c. **The optional map background.** **Kept**: projection, framing and inset are drawing.
5d/5e. **The period card and its outline stack.** **Kept**: a period is *many* sessions and
   this document is one, so `fixtures/periods/periods.expected.json` is its own contract.
6. **Why a turn is a touchdown or a fall** (engine 0.18.0). The one line under a turn's
   outcome is the same sentence the phone prints under its chips, so it is re-derived here in
   Python and compared with what `web/js/viz.js` actually produces, over every turn of every
   fixture — plus the shapes the corpus cannot supply, the retired pump rung above all. The
   engine's half is asserted too: a reason on exactly the touchdowns and falls, never on a
   fly-through, and never a code the contract does not know.

Exit 0 = everything matched; exit 1 = the failures are listed.
"""

from __future__ import annotations

import argparse
import json
import math
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

import library                                              # noqa: E402
import make_presentation_goldens as gen                     # noqa: E402

GOLDENS = REPO / "fixtures" / "goldens"
PRESENTATION = REPO / "fixtures" / "presentation"
TOKENS = REPO / "design" / "tokens.json"
SESSIONS = REPO / "fixtures" / "sessions"

CIQ = "2026-08-07-0754_nago-torbole-windsurfen_ciq"
# A fixture whose flights end in a straight line: `glide_out` ends no turn owns, which is
# what makes it one that can prove the folding rule below. Engine 0.14.0's lower peak floor
# claims ends the old one left unexplained, so glide-outs are scarcer across the whole
# corpus (2 at the most, where 0.13.0 had 3) and five fixtures now tie at the maximum.
# Engine 0.23.0 stops cutting a Smart Recording cadence into segments, so the natives' ends
# are judged rather than truncated and the count rises again — this fixture has 3, and
# 2026-08-04 pm now has the corpus maximum at 5. The rule is the same on any of them.
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


# ------------------------------- 1, 2, 2b, 2c, 5, 5a. the browser reads the document

#: The web modules the retired sections used to hold to a re-derived rule, and the document
#: field each one has to read instead. One entry per retired group: the *value* is pinned
#: once, in the presentation goldens, so the only question left on this side is whether the
#: browser asks for it rather than working it out again.
DOCUMENT_READS = [
    ("1. contract shape — the legend chips", "session.js",
     ["doc?.turns?.legend", "chip.layerId", "counts[chip.layerId] = chip.count"]),
    ("2. eligibility — which chip a mark answers to", "session.js",
     ["doc?.turns?.strip", "entry.layerId", "doc?.flightEnds?.marks", "doc?.splash?.marks"]),
    ("2b. a glide-out folds into flew through", "session.js", ["mark.outcomeId"]),
    ("5. the card is the block", "cardstats.js", ["doc?.card?.tiles", "tile.presets"]),
    ("5a. the rate row is the document's row 4", "cardstats.js", ["doc?.block?.rows"]),
    ("the records the tiles print", "render.js", ["doc?.records?.kinds"]),
    ("the turn page's 3 of 14", "turnpage.js",
     ["presentation?.turns?.strip", "presentation?.flightEnds?.marks"]),
    ("the divergence banner", "log.js", ["line.labelId", "line.unitKind"]),
]


def check_document_reads() -> None:
    """One check per retired group: the browser reads the field, and derives nothing.

    Source text rather than behaviour, deliberately. What the field *says* is already
    asserted — byte for byte, on both platforms, against the same golden — and asserting it
    again here would be the third implementation this round exists to delete. What a golden
    cannot see is a renderer quietly going back to `golden.summary`, and that is what this
    catches.
    """
    section("1, 2, 2b, 2c, 5, 5a. the browser reads the document (the retired re-derivations)")
    js = REPO / "web" / "js"
    for title, module, needles in DOCUMENT_READS:
        text = (js / module).read_text(encoding="utf-8")
        missing = [n for n in needles if n not in text]
        check(f"  {title}: js/{module}", missing, [])

    # **The legend rule, pinned on this side** (ADR-033 round 3): the chip's number is the
    # document's analysis count, and the browser adds nothing to it. The kit's twin is
    # `PresentationTests.theLegendChipCountsAreTheDocumentsAnalysisCounts`. The marker loop
    # that used to build these counts survives only for the three KIND chips, which are the
    # browser's own (the phone has no kind filter on its map), so what is checked is that it
    # no longer touches `mk.layers`.
    text = (js / "session.js").read_text(encoding="utf-8")
    check("  the browser does not re-derive a layer count from its marks",
          "mk.layers || [mk.layer]) counts[" in text, False)

    # 2c. The flight-count arithmetic is asserted on the document itself, by
    # `lab/tests/test_presentation.py::test_the_flight_count_invariants_hold_in_the_document`.
    # What is left here is that every golden carries the buckets it needs to be asserted on.
    buckets = {"flightCount", "drawn", "ownedByTurn", "truncated", "total", "marks"}
    incomplete = [stem for stem in fixtures()
                  if not buckets <= set(load(stem)[1]["document"]["flightEnds"])]
    check("  2c. every golden carries the flight-end buckets", incomplete, [])


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
        # docs/presentation/layers-map-colour-type.md, "Takeoff glyphs" — "On sources without an accelerometer
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
    # The one number the whole layer exists for, stated out loud. It read 14 until engine
    # 0.24.0 widened a not-recovered turn's ownership window to 30 s: four of those bursts
    # land inside a turn now, which makes them `recovery` pumping and not a failed takeoff
    # (docs/algorithms.md, "What 0.24.0 did to the corpus"; ADR-032).
    check(f"  {CIQ}: failed takeoff attempts", fresh["takeoff"]["failed"], 11)
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


#: The exact sentences the header may print, per source (docs/presentation/session-time-video.md "Session
#: time"). Written here rather than imported so the JavaScript is checked against a second
#: copy of the contract instead of against itself — the same rule §5 follows for the card.
EXACT_NOTE = " \u00b7 times as recorded on the water"
ESTIMATED_NOTE = " \u00b7 times estimated from the track's position"
NO_ZONE_NOTE = " \u00b7 no timezone in this file, times shown on your own clock"

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


# ------------------------------------- 5. the card is the block, and the callout's words

CARD_PARITY = TOOLS / "card_parity.mjs"

#: What `card_parity.mjs` dumped, so every section below reads it without a second node run.
#: Empty when node is not on PATH, which is the skip each of them takes.
_CARD_DUMP: list[dict] = []


def check_card() -> None:
    """**Two checks**, where there were one hundred and eighty-one.

    The card used to be held against a third Python spelling of every string in the block.
    It no longer can be, and that is the point: `card.tiles` **are** the `block` cells by
    construction (`build_presentation`), the values are pinned byte for byte in
    `fixtures/presentation/*.expected.json` for both platforms, and a re-derivation here
    would be the third implementation this round exists to delete. What a golden cannot see
    is whether the browser's two readers of that one list still agree once they have
    formatted it — so that is what is asked, once, over every fixture at once.

    The second check is the wrist-under callout, for the same reason: its two sentences are
    copy **ids with arguments** in the document now, and what is left to verify is that the
    browser can resolve every one of them into words.
    """
    section("5. the card is the block, drawn")

    goldens = sorted(PRESENTATION.glob(f"*{gen.SUFFIX}"))
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
    dumped = json.loads(raw)
    cards = dumped["cards"]

    # The block the page renders and the card's `complete` preset, over every fixture, as
    # one comparison. A preset may only DROP a tile, so `complete` — which drops none — is
    # the block minus its two block-only speeds, which is exactly what `card.tiles` is.
    check("  complete == the rendered block, every fixture",
          [[{"label": e["label"], "value": e["value"]} for e in card["complete"]]
           for card in cards],
          [card["block"] for card in cards])

    # Every `splash.marks[].title` / `.during` id resolved into a sentence. A `null` here is
    # an id with no home, which a rider would read as an empty callout.
    unresolved = [f"{Path(card['file']).name}@{mark['ts']}"
                  for card in cards for mark in card["wristUnder"]
                  if not mark["title"] or not mark["during"]]
    check("  every wrist-under callout resolves to words", unresolved, [])

    # Stashed rather than checked here, so the period card's section prints after this one —
    # one `card_parity.mjs` run answers every question below.
    _CARD_DUMP.append(dumped)


#: What the **period** card's `lean` keeps — `PeriodBlock.leanKeys` on iOS and
#: `library.PERIOD_LEAN_KEYS` in the analyzer, spelled here so the JavaScript is checked
#: against a third copy of the rule rather than against itself.
PERIOD_LEAN_KEYS = ["sessions", "hours", "cleanJibes", "cph", "best2s"]

def check_period_card() -> None:
    """The period card is the period's block, and its presets can only drop from it.

    Exactly the contract the session card is held to one section above, asked of the second
    card kind. The block itself is re-derived here from `library.periods` — so the
    JavaScript agreeing with the shared fixture is checked against what `library` produces
    *now*, and not against a file that may have been left behind by an edit to it.
    """
    if not _CARD_DUMP:
        return
    dumped = _CARD_DUMP[-1]
    section("5d. the period card carries the period's block, unchanged")
    sys.path.insert(0, str(WEB / "lab_bundle"))
    sys.path.insert(0, str(WEB / "tools"))
    import library                                                       # noqa: PLC0415
    import make_presentation_goldens as periods_gen                      # noqa: PLC0415

    periods = dumped.get("periods") or []
    check("  the fixture's periods were all measured", len(periods) > 0, True)
    check("  periodLeanKeys is the contract's set",
          dumped.get("periodLeanKeys"), PERIOD_LEAN_KEYS)
    check("  ...and it is a subset of the block, so a preset can only drop",
          set(PERIOD_LEAN_KEYS) <= {k for k, _l, _f in library.PERIOD_BLOCK}, True)

    digests = [periods_gen.period_digest(s) for s in periods_gen.PERIOD_SESSIONS]
    fresh = library.periods(digests)
    by_key = {p["key"]: p for group in ("trips", "months", "seasons")
              for p in fresh[group]}
    for r in periods_gen.PERIOD_RANGES:
        custom = library.custom_period(digests, r["start"], r["end"])
        by_key[custom["key"]] = custom

    for card in periods:
        key = card["key"]
        want = by_key.get(key)
        if want is None:
            FAILED.append(f"  period {key} is on a card and not in the library")
            continue
        block = [{"key": e["key"], "label": e["label"], "value": e["value"]}
                 for e in want["block"]]

        # 1. Complete IS the block: same entries, same order, same words, same strings.
        check(f"  {key}: complete == the period's block", card["complete"], block)

        # 2. Lean is a strict SUBSET, in the block's own order.
        check(f"  {key}: lean is the block filtered by its lean keys",
              card["lean"], [e for e in block if e["key"] in PERIOD_LEAN_KEYS])

        # 3. Nothing outside the catalogue may reach a card, and the order is the
        #    catalogue's.
        keys = [e["key"] for e in card["complete"]]
        catalogue = [k for k, _l, _f in library.PERIOD_BLOCK]
        check(f"  {key}: every cell is in the catalogue", set(keys) <= set(catalogue), True)
        check(f"  {key}: in the catalogue's order",
              keys, [k for k in catalogue if k in set(keys)])

        # 4. The heading and the span are the period's own, not re-derived at draw time.
        check(f"  {key}: the card's headline is the period's title",
              card["title"], want["title"])
        check(f"  {key}: the date line is the period's span", card["dateLine"],
              want["dateLine"])

        # 5. The map ground, re-derived here by a second copy of the rule: one spot cluster,
        #    and every afternoon in it placed by a fix rather than by the name of its file.
        #    The browser may only *read* the flag — a second clustering implementation in
        #    js/ would be a second answer to "was this one place".
        rows = [d for d in digests if d["id"] in set(want["sessionIds"])]
        anchored = all(isinstance(d.get("geo"), dict) for d in rows)
        one_place = bool(rows) and len(library._spot_clusters(rows)) == 1
        check(f"  {key}: the ground is offered iff the period is one place",
              want["mapGround"], anchored and one_place)
        check(f"  {key}: and the composer offers exactly that",
              card["mapOffered"], want["mapGround"])
        check(f"  {key}: read from the library, never re-derived",
              card["mapGround"], want["mapGround"])


def check_outline_stack() -> None:
    """The period card's artwork: many outlines, **one** metres scale, both platforms.

    The card's stats are pinned by the two sections above; its picture is pinned here. What
    makes a stack of a dozen tracks a picture rather than a scribble is that they share a
    scale — a half-hour paddle draws small inside a three-hour reach instead of being
    stretched to match it — and what makes it the *same* picture on a phone and in a browser
    is that both fit the union of the extents by the same arithmetic.

    `fixtures/periods/outlines.expected.json` is the contract: polylines in metres, a box in
    layout points, and every placed vertex. `TrackStackTests` holds the kit to it; this holds
    `stackPlacer` in web/js/sharecard.js to it, and re-derives the file from
    `make_presentation_goldens.py` first, so a stale fixture cannot pin either platform to an
    answer the rule no longer gives.
    """
    if not _CARD_DUMP:
        return
    section("5e. the period card's outlines share one scale, on both platforms")
    sys.path.insert(0, str(WEB / "tools"))
    import make_presentation_goldens as stack_gen                        # noqa: PLC0415

    stored = json.loads(
        (REPO / "fixtures" / "periods" / "outlines.expected.json").read_text(encoding="utf-8"))
    fresh = stack_gen.stack_facts()
    check("  the fixture is what the rule produces now", stored, fresh)

    got = {case["name"]: case for case in (_CARD_DUMP[-1].get("stacks") or [])}
    check("  every case was measured in the browser", sorted(got),
          sorted(c["name"] for c in fresh["cases"]))
    for want in fresh["cases"]:
        name = want["name"]
        have = got.get(name)
        if have is None:
            FAILED.append(f"  {name}: not dumped")
            continue
        check(f"  {name}: one scale, and it is the fixture's", have["scale"], want["scale"])
        check(f"  {name}: the union's centre", [have["centreX"], have["centreY"]],
              [want["centreX"], want["centreY"]])
        check(f"  {name}: every vertex lands where the fixture says", have["placed"],
              want["placed"])

    # The point of the whole thing, said out loud so a regression names itself: three tracks
    # of three different sizes come off ONE scale, and the biggest is the one that binds the
    # fit. Normalize each against its own extent — which is what the phone did before the
    # thumbnail carried its bounds — and all three would be drawn the same size.
    week = next(c for c in fresh["cases"] if c["name"] == "a week of different lengths")
    spans = []
    for track in week["placed"]:
        xs = [p[0] for p in track]
        spans.append(round(max(xs) - min(xs), 3))
    check("  the three tracks are drawn at three different widths",
          len(set(spans)) == len(spans), True)
    check("  …and the longest is the one that fills the box",
          round(max(spans), 1), round(week["box"]["w"] - 2 * fresh["rule"]["inset"], 1))


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

    # 1c. The prefill. A placeholder is not a prefill — it vanishes on the first keystroke —
    #     so the field opens *containing* what the card is headlined, and a rider renaming a
    #     session edits that instead of retyping it. Same rule as `SessionNaming.titleDraft`
    #     on iOS, and it resolves the way the headline resolves: remembered title first, the
    #     derived name otherwise.
    for remembered, name, want_js in got["drafts"]:
        want = (remembered or "").strip()[:TITLE_LIMIT].strip() or _derived_title(name)
        check(f"  cardTitleDraft({(remembered or '')[:20]!r}, {name[:28]!r})", want_js, want)
    drafts = {(r or "", n): got_draft for r, n, got_draft in got["drafts"]}
    check("  an untitled session opens on its derived name — corrected",
          drafts[("", "2026-08-30-1407_nago-torbole-windsurfen_ciq.fit")],
          "Nago Torbole Wingfoil")
    check("  a session he has titled opens on his own words",
          drafts[("  First 20 kn  ", "2026-08-30-1407_nago-torbole-windsurfen_ciq.fit")],
          "First 20 kn")
    check("  and the prefill is never blank", all(d for *_, d in got["drafts"]), True)

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
    # The prefill is a convenience for the typing, not a title the rider is recorded as having
    # given: opening the dialog on a session nobody has named must leave the store untouched.
    check("  opening an untitled session prefills the derived name",
          s["prefillOnAnUntitledSession"], "Nago Torbole Wingfoil")
    check("  and writes nothing — only a keystroke does", s["prefillWroteNothing"], True)
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

    check_card_map(got)


# ------------------------------------------------ 5c. the optional map background

#: Where the map switch is remembered, and the one value that means "on". Spelled here rather
#: than read out of the JavaScript, so the default is checked against a second copy of the
#: rule: the map is the only part of making a card that reaches a third-party server, and a
#: build that shipped it on by default would break the promise the analyzer makes loudest.
MAP_KEY = "wingfoil.shareCard.map.v1"
MAP_ON = "1"

#: ODbL's required credit for the web card's tiles, exactly as the OSM Foundation asks for it.
#: A card is a PNG in somebody else's chat thread: if this string is wrong, every copy of it
#: already sent is wrong for ever.
OSM_CREDIT = "© OpenStreetMap contributors"


def _world_point(lat: float, lon: float) -> tuple[float, float]:
    """Web Mercator's unit square, re-derived — the second implementation of
    `worldPoint` in web/js/cardmap.js. x east from the anti-meridian, y **south** from the
    top, both 0…1, which is the frame every raster tile scheme is cut out of."""
    clamped = max(-85.05112878, min(85.05112878, lat))
    s = math.sin(math.radians(clamped))
    return ((lon + 180) / 360, 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi))


def check_card_map(got: dict) -> None:
    """The optional map background: off unless asked, and the ride where it always was.

    Two promises, and both of them are about a picture nobody can take back.

    **Off.** The plain card is the card this project has exported since the beginning, and a
    rider who never opens the switch must keep getting it — including the part where making
    one asks nothing of anybody's server. So every way of reading the preference that is not
    an explicit `"1"` written by the switch itself resolves to off.

    **In place.** The whole design of the map background is that the layout does not know it
    arrived: the framing is chosen so the ride fills exactly the box the card would have
    fitted it into anyway, and only the margins around it become map. That is asserted here
    on the arithmetic — the track's own bounding box, projected and placed, has to land on
    the inset track box to a hundredth of a point.

    The tiles themselves are not fetched and the canvas is not drawn: `mapBackdrop` needs a
    DOM and a network, and neither is what could be wrong here.
    """
    section("5c. the card's optional map background")

    s = got["choice"]
    check("  nothing stored: portrait, complete, no map", s["defaultsBeforeAnythingIsWritten"],
          {"shape": "portrait", "preset": "complete", "map": False})
    check("  the switch remembers on", s["afterTurningOn"],
          {"shape": "landscape", "preset": "lean", "map": True})
    check("  and stores it as the contract's value", s["storedOn"], MAP_ON)
    check("  and remembers off", s["afterTurningOff"]["map"], False)
    check("  which is stored, not deleted", s["storedOff"], "0")
    # The three ways a truthy-looking value could turn the map on behind the rider's back.
    check("  a foreign truthy value is still off", s["foreignTruthyValue"], False)
    check("  and so is garbage under the key", s["garbageValue"], False)
    check("  a browser with no storage gets the defaults", s["withoutStorage"],
          {"shape": "portrait", "preset": "complete", "map": False})
    check("  and writing to one is a silent no-op", s["writeThrewWithoutStorage"], False)

    check("  the OSM credit is the contract's string", got["credit"], OSM_CREDIT)

    p = got["projection"]
    want = [_world_point(0, 0), _world_point(0, -180), _world_point(0, 180)]
    check("  the world square's three fixed points",
          [[round(v["x"], 9), round(v["y"], 9)] for v in p["world"]],
          [[round(x, 9), round(y, 9)] for x, y in want])
    spot_x, spot_y = _world_point(45.8647, 10.8751)
    check("  and Torbole, re-projected",
          [round(p["spot"]["x"], 9), round(p["spot"]["y"], 9)],
          [round(spot_x, 9), round(spot_y, 9)])

    # THE RIDE LANDS WHERE IT ALWAYS DID — the whole promise of the feature, as arithmetic.
    # One axis binds and puts the ride on the inset box's own edges; the other is centred in
    # what is left. Which one binds is a fact about the session, not about the rule, so the
    # assertion is written not to care: centred on both axes, inside the box on both, and
    # touching on one.
    box, inset = p["box"], p["inset"]
    nw, se = p["northWest"], p["southEast"]
    check("  the ride is centred on the track box horizontally",
          round((nw[0] + se[0]) / 2, 2), round(box["x"] + box["w"] / 2, 2))
    check("  and vertically", round((nw[1] + se[1]) / 2, 2),
          round(box["y"] + box["h"] / 2, 2))
    slack_x = round(nw[0] - (box["x"] + inset), 2)
    slack_y = round(nw[1] - (box["y"] + inset), 2)
    check("  it is inside the inset box on both axes", slack_x >= 0 and slack_y >= 0, True)
    check("  and touches it on the binding one", min(slack_x, slack_y), 0.0)
    check("  the far corner mirrors the near one",
          [round(box["x"] + box["w"] - inset - se[0], 2),
           round(box["y"] + box["h"] - inset - se[1], 2)], [slack_x, slack_y])

    # The map is a *drawing* option. It has no way into the content, and this is the proof:
    # the function that resolves everything the card says does not take it.
    c = got["content"]
    check("  a document with no view carries no anchor", c["geoWithoutAView"], None)
    check("  and one with a view carries it verbatim", c["geoFromTheView"],
          {"lat": 45.86, "lon": 10.87, "x": 1, "y": 2})


# --------------------------------------------------------------------- main


# ------------------------------------------- 6. why a turn is a touchdown or a fall

OUTCOME_TEXT = TOOLS / "outcome_text.mjs"

#: km/h to knots, for the one wording that names a config speed in the rider's unit.
KMH_TO_KN = 1 / 1.852


def _secs(value: float) -> str:
    """Whole seconds, **half away from zero** — `Math.round` in the JavaScript,
    `Double.rounded()` in the Swift. Spelled out rather than left to `format`, because
    `"%.0f" % 4.5` is `"4"` (banker's) while `(4.5).toFixed(0)` is `"5"`, and a stop of
    exactly 4.5 s is an ordinary reading at 1 Hz."""
    return str(math.floor(value + 0.5))


def expected_outcome_text(turn: dict, marginal_speed: float | None) -> str | None:
    """The line the page must print under one turn's outcome, re-derived here in Python.

    A third spelling of docs/presentation/turn-detail.md "Why it ended that way", against the JavaScript
    that draws it (`outcomeText` in web/js/viz.js) and the Swift that draws the same sentence
    on the phone (`TurnAnalytics.outcomeText`). Jan asked for "a short comment for the user why
    a jibe is a touchdown or a fall"; a comment that says one thing on the phone and another on
    the web is worse than no comment at all.

    None on a fly-through — nothing happened — and None on a document written before engine
    0.18.0, which carries no reason: a sentence rebuilt from `stoppedS` alone would be a guess
    about a ladder that may not have been climbed that way.
    """
    reason = turn.get("outcomeReason")
    if reason == "stop":
        stopped = f"stopped {_secs(turn['stoppedS'])} s"
        if turn["outcome"] == "fell_in":
            return f"fell in · {stopped}"
        return f"touchdown · {stopped}" + (", borderline" if turn["borderline"] else "")
    if reason == "off_foil":
        # "no stop", never "stopped 0 s": the rider did not stop, and a rounded zero reads as
        # a measurement of one.
        stop = (f"stopped {_secs(turn['stoppedS'])} s"
                if math.floor(turn["stoppedS"] + 0.5) >= 1 else "no stop")
        return f"touchdown · off the foil {_secs(turn['offFoilS'])} s, {stop}"
    if reason == "submerged":
        return "fell in · wrist under"
    if reason == "pumped_marginal":
        if marginal_speed is None:
            return "touchdown · pumped out below min foil speed, no sample off the foil"
        return (f"touchdown · pumped out below {marginal_speed * KMH_TO_KN:.1f} kn, "
                "no sample off the foil")
    return None


#: The sentences the hand-made cases in `outcome_text.mjs` must produce. Written out rather
#: than derived, because the whole point of them is the shapes the seventeen fixtures cannot
#: supply — the pump rung above all, which no published-default run can reach any more.
OUTCOME_TEXT_CASES = {
    "pumpedMarginal": "touchdown · pumped out below 4.3 kn, no sample off the foil",
    # The 0.17.0 reading, restored by raising `turnPumpedMarginalSpeed` to 12 km/h. This is the
    # sentence the rung printed for its whole working life, and the number is the *document's*.
    "pumpedMarginalRevived": "touchdown · pumped out below 6.5 kn, no sample off the foil",
    "pumpedMarginalNoConfig":
        "touchdown · pumped out below min foil speed, no sample off the foil",
    "offFoilNoStop": "touchdown · off the foil 2 s, no stop",
    "offFoilWithStop": "touchdown · off the foil 2 s, stopped 1 s",
    "borderline": "touchdown · stopped 4 s, borderline",
    "fellInStopped": "fell in · stopped 7 s",
    "fellInSubmerged": "fell in · wrist under",
    "flewThrough": None,
    "preReason": None,
    "halfSecond": "fell in · stopped 7 s",
}


def check_outcome_text() -> None:
    """The "why" line, over every turn of every fixture and the shapes none of them contain.

    Two things are asserted. That the JavaScript's sentence is the Python's, per turn, on all
    seventeen documents — which is the parity check. And that a reason is written down for
    exactly the touchdowns and falls, never for a fly-through, which is the check that the
    *engine* is holding up its half: a fly-through with a reason on it would print a sentence
    explaining something that did not happen.
    """
    section("6. why a turn is a touchdown or a fall")
    goldens = sorted(GOLDENS.glob(f"*{gen.SUFFIX}"))
    node = shutil.which("node")
    if not node:
        print("  (skipped: node not on PATH — the why line unchecked)")
        return
    if not goldens:
        print("  (skipped: no analysis goldens)")
        return
    try:
        raw = subprocess.run([node, str(OUTCOME_TEXT), *[str(p) for p in goldens]],
                             capture_output=True, text=True, check=True, cwd=REPO).stdout
    except (subprocess.CalledProcessError, OSError) as exc:              # pragma: no cover
        FAILED.append(f"  outcome_text.mjs failed\n{getattr(exc, 'stderr', exc)}")
        return
    got = json.loads(raw)

    check("  the hand-made cases", got["cases"], OUTCOME_TEXT_CASES)

    for entry in got["fixtures"]:
        stem = Path(entry["file"]).name[: -len(gen.SUFFIX)]
        doc = json.loads((REPO / entry["file"]).read_text(encoding="utf-8"))
        marginal = (doc.get("config") or {}).get("turnPumpedMarginalSpeed")
        turns = doc.get("turns", [])
        want = [expected_outcome_text(t, marginal) for t in turns]
        check(f"  {stem}: the why line, re-derived", entry["texts"], want)
        # The engine's half of the contract: a reason exactly where there is something to
        # explain. `glide_out` never appears on a turn — that is a flight-end word — so the
        # three outcomes partition the list.
        check(f"  {stem}: a reason on every touchdown and fall, and on nothing else",
              sorted({t["outcome"] for t in turns
                      if (t.get("outcomeReason") is None) == (t["outcome"] != "flew_through")}),
              [])
        # And the reason is one the contract knows.
        check(f"  {stem}: no unknown reason code",
              sorted({t["outcomeReason"] for t in turns
                      if t.get("outcomeReason") is not None}
                     - {"stop", "off_foil", "submerged", "pumped_marginal"}),
              [])


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

    check_document_reads()
    check_consistency()
    if args.fast:
        _close_section()
        print("\n(--fast: the engine run was skipped)")
        _MARK[:] = [PASSED, len(FAILED)]
    else:
        check_engine()
    check_card()
    check_card_text()
    check_period_card()
    check_outline_stack()
    check_outcome_text()

    _close_section()
    print(f"\n{PASSED} passed, {len(FAILED)} failed")
    for f in FAILED:
        print(f"  FAIL {f}")
    return 1 if FAILED else 0


if __name__ == "__main__":
    raise SystemExit(main())
