#!/usr/bin/env python3
"""Headless checks for the presentation goldens — the web app's half of the contract.

`fixtures/presentation/*.expected.json` says what a session-detail screen may draw from
an analysis: how many markers per layer, how the takeoff layer splits, which record
windows can be highlighted, and what every turn filter keeps. The iOS app asserts those
numbers in `PresentationTests`; this script asserts them from the analysis documents on
this side of the repo, so a rule that drifts on one platform fails on both.

    lab/.venv/bin/python web/tools/verify_presentation.py
    lab/.venv/bin/python web/tools/verify_presentation.py --fast   # skip the engine run

Four groups:

1. **Contract shape.** Every layer and record id in a presentation golden is one the
   contract knows (design/tokens.json, the same catalogue the iOS enums are checked
   against), and the filter grid is complete — 3 types × 3 entry sides.
2. **The rules, re-derived.** The counts are recomputed here from the analysis golden,
   written out differently from the generator on purpose: two spellings of the same rule
   agreeing is evidence, one spelling agreeing with itself is not.
3. **Internal consistency.** Marker totals, takeoff totals and the filter grid have to
   add up against the analysis document's own summary block.
4. **The engine path** (skipped by `--fast`): re-analyze one FIT through `web_entry`, the
   exact call the browser makes, and check the presentation facts of the document it
   produces. This is what ties the numbers to the code the site actually runs.

Exit 0 = everything matched; exit 1 = the failures are listed.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
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
        check(f"  {stem}: the filter grid is complete",
              [(row["type"], row["side"]) for row in facts["filters"]],
              [(t, s) for t in gen.TYPE_FILTERS for s in gen.SIDE_FILTERS])
        check(f"  {stem}: bestHour is not offered",
              "bestHour" in facts["recordWindows"], False)


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
        # this asserts. (Whether a filled "this cost something" arrow is the right glyph
        # for a run nobody counted strokes on is a contract question, not a drift.)
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

    doc = json.loads(web_entry.analyze_json(fit.read_bytes(), fit.name))["golden"]
    _, facts = load(CIQ)
    fresh = gen.facts(CIQ, doc)
    for key in ("markers", "takeoff", "splash", "pumpingSpans", "recordWindows",
                "defaultRecordWindow", "filters"):
        check(f"  {CIQ}: {key} from a fresh analysis", fresh[key], facts[key])
    # The one number the whole layer exists for, stated out loud.
    check(f"  {CIQ}: failed takeoff attempts", fresh["takeoff"]["failed"], 14)


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
    check_consistency()
    if args.fast:
        _close_section()
        print("\n(--fast: the engine run was skipped)")
        _MARK[:] = [PASSED, len(FAILED)]
    else:
        check_engine()

    _close_section()
    print(f"\n{PASSED} passed, {len(FAILED)} failed")
    for f in FAILED:
        print(f"  FAIL {f}")
    return 1 if FAILED else 0


if __name__ == "__main__":
    raise SystemExit(main())
