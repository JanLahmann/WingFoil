"""The presentation document: deterministic, complete, and made of ids.

`docs/presentation/document.md` is the schema. These are the three properties the schema
is worthless without — the document is the same bytes twice, it builds for every fixture
in the corpus, and every word in it is an id that resolves in `docs/copy` (or in
`design/tokens.json`, which is copy for the record and layer names).

The fourth property — that the Swift twin emits the same bytes — is pinned by the goldens
and asserted by `PresentationTests.presentationDocumentMatchesTheGoldenByte`.
"""

import json
import re
from pathlib import Path

import pytest

from wingfoil_lab.presentation import (DEFAULT_RECORD_WINDOW, DEFAULT_ROW_METRICS,
                                       FORBIDDEN_CARD_KEYS, LEAN_CARD_KEYS,
                                       PRESENTATION_VERSION, RECORD_KINDS,
                                       SPEED_RECORD_POLICIES, build_presentation,
                                       document_json, round_to, sorted_tree)

REPO = Path(__file__).resolve().parents[2]
GOLDENS = REPO / "fixtures" / "goldens"
COPY = REPO / "docs" / "copy"
TOKENS = json.loads((REPO / "design" / "tokens.json").read_text(encoding="utf-8"))

#: Every top-level key, and nothing else. A renderer reads this list; a key that appears
#: without the schema saying so is a fact with no documented owner.
TOP_KEYS = {"block", "card", "defaults", "divergence", "engineVersion", "filters",
            "flightEnds", "markers", "notASession", "presentationVersion", "records",
            "row", "splash", "turns"}

#: The brace-matching extraction the Swift test uses to lift `document` out of the golden
#: is only safe while no string in the document can contain a brace. It cannot: every
#: string is an id, an enum value or a version.
SAFE_STRING = re.compile(r"^[A-Za-z0-9._\-]*$")

#: The engine's own snake_case enum values, which the document passes through untouched —
#: an outcome reason, a clean block, a not-a-session code. They are ids like any other and
#: the renderer owns their words; they are allowed an underscore and nothing else is.
SAFE_ENUM = re.compile(r"^[a-z][a-z_]*$")


def goldens() -> list[Path]:
    return sorted(GOLDENS.glob("*.expected.json"))


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def documents() -> dict[str, dict]:
    return {p.name[: -len(".expected.json")]: build_presentation(load(p))
            for p in goldens()}


# --------------------------------------------------------------- it is deterministic


def test_two_builds_are_the_same_bytes(documents):
    """No clock, no locale, no set iteration order, no dict insertion order."""
    for path in goldens():
        golden = load(path)
        assert document_json(build_presentation(golden)) \
            == document_json(build_presentation(golden))


def test_keys_are_sorted_everywhere(documents):
    """`sorted_tree` is what lets `json.dumps(indent=2)` and the Swift canonical writer —
    which sorts — produce one file."""
    def walk(value):
        if isinstance(value, dict):
            assert list(value) == sorted(value), list(value)
            for v in value.values():
                walk(v)
        elif isinstance(value, list):
            for v in value:
                walk(v)

    for doc in documents.values():
        walk(doc)
        assert sorted_tree(doc) == doc


def test_round_to_is_idempotent_and_kills_negative_zero():
    assert round_to(12.6014, 3) == 12.601
    assert round_to(round_to(12.6014, 3), 3) == 12.601
    assert round_to(-0.0004, 3) == 0.0
    assert str(round_to(-0.0004, 3)) == "0.0"
    assert round_to(None, 3) is None
    assert round_to(7, None) == 7


# ------------------------------------------------------------------ it is complete


def test_every_fixture_builds(documents):
    assert documents, "fixtures/goldens is empty"
    for stem, doc in documents.items():
        assert set(doc) == TOP_KEYS, stem
        assert doc["presentationVersion"] == PRESENTATION_VERSION
        assert doc["engineVersion"]


def test_the_document_carries_the_facts_the_goldens_already_pinned(documents):
    """`fixtures/presentation/*.expected.json`'s own counts, out of the document instead
    of out of a second reading of the rules. The two must never disagree — that is the
    whole point of the round."""
    for path in sorted((REPO / "fixtures" / "presentation").glob("*.expected.json")):
        want = load(path)
        doc = documents[want["fixture"]]
        markers, ends = doc["markers"], doc["flightEnds"]
        assert {k: markers[k] for k in want["markers"]} == want["markers"], want["fixture"]
        assert markers["cleanJibe"] == want["cleanJibes"]
        assert markers["takeoff"] == want["takeoff"]
        assert markers["pumping"] == want["pumpingSpans"]
        assert markers["splash"] == want["splash"] == doc["splash"]["episodes"]
        assert {k: ends[k] for k in want["flightEnds"]} == want["flightEnds"]
        assert ends["flightCount"] == want["flightCount"]
        assert doc["records"]["achieved"] == want["recordWindows"]
        assert doc["defaults"]["recordWindow"] == want["defaultRecordWindow"]
        assert [{"type": f["typeId"], "side": f["sideId"], "count": f["count"],
                 "flewThrough": f["flewThrough"]} for f in doc["filters"]] == want["filters"]


def test_the_flight_count_invariants_hold_in_the_document(documents):
    """docs/presentation/enforcement.md 3, read off the document: one takeoff starts every
    flight, one end stops it, and a failed attempt starts none."""
    for stem, doc in documents.items():
        takeoff, ends = doc["markers"]["takeoff"], doc["flightEnds"]
        assert takeoff["pumped"] + takeoff["free"] == ends["flightCount"], stem
        assert ends["total"] == ends["flightCount"], stem
        assert ends["drawn"] + ends["ownedByTurn"] + ends["truncated"] == ends["total"], stem
        assert ends["drawn"] == len(ends["marks"]), stem


def test_the_card_is_the_block_minus_the_two_block_only_speeds(documents):
    """A preset may drop a tile. It may not reword, reorder or invent one."""
    for stem, doc in documents.items():
        block = [c for row in doc["block"]["rows"] for c in row["cells"]]
        tiles = doc["card"]["tiles"]
        assert [t["key"] for t in tiles] == \
            [c["key"] for c in block if c["key"] not in ("best5x10s", "alpha500")], stem
        for tile in tiles:
            cell = next(c for c in block if c["key"] == tile["key"])
            assert {k: v for k, v in tile.items() if k != "presets"} == cell, stem
            assert ("lean" in tile["presets"]) == (tile["key"] in LEAN_CARD_KEYS), stem
            assert tile["key"] not in FORBIDDEN_CARD_KEYS, stem
        assert doc["card"]["leanKeys"] == LEAN_CARD_KEYS


def test_the_records_block_is_the_nine_kinds_in_order(documents):
    for stem, doc in documents.items():
        records = doc["records"]
        assert [k["key"] for k in records["kinds"]] == RECORD_KINDS, stem
        assert records["policy"] in SPEED_RECORD_POLICIES
        for kind in records["kinds"]:
            # A record with a value and no window is inert, and a window with no value
            # cannot exist: `achieved` is the conjunction, and it is what the picker reads.
            assert kind["achieved"] == (kind["value"] is not None and kind["value"] > 0
                                        and bool(kind["windows"])), (stem, kind["key"])
            assert kind["offered"] <= kind["achieved"]
        assert records["default"] in (None, DEFAULT_RECORD_WINDOW)


def test_only_verified_withdraws_every_record_from_an_uncertified_recording():
    """The policy is an argument, not a stored fact — one analysis, three answers."""
    golden = load(next(p for p in goldens() if "nospeed" in p.name))
    assert not golden["capabilities"]["hasDoppler"]
    strict = build_presentation(golden, policy="onlyVerified")
    loose = build_presentation(golden, policy="includeUnverified")
    assert not any(k["offered"] for k in strict["records"]["kinds"])
    assert [k["achieved"] for k in strict["records"]["kinds"]] \
        == [k["offered"] for k in loose["records"]["kinds"]]
    # Nothing but the record block moves: the policy is a record question.
    assert strict["block"] == loose["block"]


def test_the_turn_strip_numbers_every_counted_turn_within_its_own_kind(documents):
    for stem, doc in documents.items():
        seen: dict[str, int] = {}
        for entry in doc["turns"]["strip"]:
            if not entry["counted"]:
                assert entry["ordinal"] is None and entry["colourRole"] \
                    == "outcome.courseChange", stem
                continue
            seen[entry["typeId"]] = seen.get(entry["typeId"], 0) + 1
            assert entry["ordinal"] == seen[entry["typeId"]], stem
            assert entry["clean"] is False or entry["layerId"] == "cleanJibe", stem
        assert sum(1 for e in doc["turns"]["strip"] if e["clean"]) \
            == doc["markers"]["cleanJibe"], stem


def test_the_legend_counts_are_the_marker_counts(documents):
    for stem, doc in documents.items():
        chips = {c["layerId"]: c["count"] for c in doc["turns"]["legend"]}
        markers = doc["markers"]
        for layer in ("flewThrough", "touchdown", "fellIn", "courseChange", "cleanJibe",
                      "splash"):
            assert chips[layer] == markers[layer], (stem, layer)
        assert chips["takeoff"] == markers["takeoff"]["total"], stem
        assert chips["pumping"] == markers["pumping"], stem
        # The line layers have no count to be live about.
        assert chips["flying"] is None and chips["offFoil"] is None


def test_the_row_carries_the_riders_three_and_the_whole_turn_ladder(documents):
    for stem, doc in documents.items():
        row = doc["row"]
        assert [s["key"] for s in row["slots"]] == DEFAULT_ROW_METRICS, stem
        counted = sum(1 for e in doc["turns"]["strip"] if e["counted"])
        if counted:
            assert sum(row["tally"].values()) == counted, stem
        else:
            assert row["tally"] is None, stem


# ---------------------------------------------------------------- it is made of ids


def copy_ids() -> set[str]:
    """Every id the document may name, out of the copy artefacts themselves."""
    out: set[str] = set()
    glossary = json.loads((COPY / "glossary.json").read_text(encoding="utf-8"))
    out |= {"glossary." + e["id"] for e in glossary["entries"]}
    out |= {"tokens.recordWindow." + w["id"] for w in TOKENS["recordWindows"]["order"]}
    out |= {"tokens.layer." + layer["id"] for layer in TOKENS["layers"]}
    verdicts = json.loads((COPY / "verdicts.json").read_text(encoding="utf-8"))
    out.add("verdicts.notASession.tag")
    out |= {f"verdicts.notASession.lines.{i}"
            for i, _ in enumerate(verdicts["notASession"]["lines"])}

    presentation = json.loads((COPY / "presentation.json").read_text(encoding="utf-8"))
    for group, entries in presentation.items():
        if group.startswith("_") or not isinstance(entries, dict):
            continue
        out |= {f"presentation.{group}.{key}" for key in entries}
    return out


def walk_ids(value, into: list[str]) -> None:
    if isinstance(value, dict):
        for key in ("labelId", "tagId", "lineId"):
            if isinstance(value.get(key), str):
                into.append(value[key])
        if isinstance(value.get("id"), str) and "args" in value:
            into.append(value["id"])
        for v in value.values():
            walk_ids(v, into)
    elif isinstance(value, list):
        for v in value:
            walk_ids(v, into)


def test_every_label_and_caption_is_an_id_that_exists_in_copy(documents):
    """The document never contains a rider sentence — and never names a word that has no
    home. Both halves fail here."""
    known = copy_ids()
    for stem, doc in documents.items():
        ids: list[str] = []
        walk_ids(doc, ids)
        assert ids, stem
        missing = sorted({i for i in ids if i not in known})
        assert not missing, f"{stem}: no copy entry for {missing}"


def branch_documents() -> list[dict]:
    """The three branches no corpus fixture is, built here the way `card_parity.mjs`
    builds its `allWetJibes` case: the wind axis that named no jibes, a wrist-under during
    a turn the tally does not count, and one after a flight end that stopped for under a
    second. Each is a real shape of the product and each owns a line of copy."""
    base = load(goldens()[0])

    no_jibes = json.loads(json.dumps(base))
    no_jibes["summary"]["turns"]["jibes"] = 0
    no_jibes["summary"]["turns"]["jibeOutcomes"] = {"flewThrough": 0, "touchdown": 0,
                                                    "fellIn": 0, "borderline": 0}

    callouts = json.loads(json.dumps(base))
    callouts["turns"] = [dict(callouts["turns"][0], counted=False, type="bear_away")]
    callouts["flightEnds"] = [dict(callouts["flightEnds"][0], stoppedS=0.0,
                                   flightIndex=0)]
    callouts["submersions"] = [
        {"ts": 10.0, "durationS": 3.0, "turnIndex": 0, "flightEndIndex": None},
        {"ts": 20.0, "durationS": 0.4, "turnIndex": None, "flightEndIndex": 0},
        {"ts": 30.0, "durationS": 4.0, "turnIndex": None, "flightEndIndex": None},
    ]
    return [build_presentation(no_jibes), build_presentation(callouts)]


def test_the_branches_no_corpus_fixture_is():
    """The fallback tally caption, and the two wrist-under callouts the corpus never
    produces. Asserted here so they are contract rather than dead code."""
    no_jibes, callouts = branch_documents()
    tally = next(c for row in no_jibes["block"]["rows"] for c in row["cells"]
                 if c["key"] == "tally")
    # The fallback carries no clean clause: a session whose wind axis named no jibes has
    # no clean jibes to report (docs/presentation/key-metrics.md, "Row 3").
    assert [c["id"] for c in tally["captions"]] == ["presentation.caption.ofTurns"]
    assert "clean" not in tally["captions"][0]["args"]

    during = [m["during"]["id"] for m in callouts["splash"]["marks"]]
    assert during == ["presentation.wristUnder.duringAnyTurn",
                      "presentation.wristUnder.afterFlight",
                      "presentation.wristUnder.offFoil"]
    assert callouts["splash"]["marks"][1]["title"]["id"] \
        == "presentation.wristUnder.title"
    assert callouts["splash"]["marks"][0]["during"]["args"] == {"turnId": "bearAway"}


def test_the_copy_file_carries_no_id_the_document_cannot_reach(documents):
    """The other direction: a label that is written down and never pointed at is copy
    nobody maintains.

    Three groups are exempt, and each for a reason a document cannot show:

    * `turnKind` is interpolated *into* a caption by the renderer rather than named by a
      `labelId`;
    * `divergence` names the watch-vs-phone metrics, and a divergence line exists only when
      a **watch summary** was paired — an analysis golden never has one, so the document
      built here is the empty, honest answer (`docs/presentation/document.md`,
      "`divergence`"). The kit's `CopyContractTests.everyIdTheDocumentCanEmitHasAHome` is
      what covers them, against the resolver the phone actually calls;
    * `banner` is the one sentence a renderer *builds* rather than names, like `turnKind`.
    """
    used: list[str] = []
    for doc in list(documents.values()) + branch_documents():
        walk_ids(doc, used)
    presentation = json.loads((COPY / "presentation.json").read_text(encoding="utf-8"))
    reachable = set(used)
    # The row offers eleven metrics and draws three; all eleven are reachable by a rider
    # who changes the triple, so the row names them rather than the test guessing.
    for doc in documents.values():
        reachable |= {"presentation.rowMetric." + m for m in doc["row"]["offered"]}
    orphans = sorted(f"presentation.{group}.{key}"
                     for group, entries in presentation.items()
                     if isinstance(entries, dict) and not group.startswith("_")
                     and group not in ("turnKind", "divergence", "banner")
                     for key in entries
                     if f"presentation.{group}.{key}" not in reachable)
    assert not orphans, f"unreachable copy: {orphans}"


def test_no_string_in_the_document_is_a_sentence(documents):
    """A brace, a space or a digit-and-a-unit in a document string would mean a renderer
    somewhere is printing what the engine wrote. Every string is an id or an enum value —
    which is also what makes the Swift test's brace-matching extraction safe."""
    def walk(value, path):
        if isinstance(value, dict):
            for k, v in value.items():
                walk(v, f"{path}.{k}")
        elif isinstance(value, list):
            for i, v in enumerate(value):
                walk(v, f"{path}[{i}]")
        elif isinstance(value, str):
            assert SAFE_STRING.match(value) or SAFE_ENUM.match(value), \
                f"{path}: {value!r}"

    for stem, doc in documents.items():
        walk(doc, stem)


def test_the_not_a_session_line_is_an_id_with_the_two_numbers_that_decided():
    """No engine vocabulary, and no sentence: the reason is a code and the line is an id
    (docs/presentation/not-a-session-spots.md)."""
    golden = load(goldens()[0])
    golden = json.loads(json.dumps(golden))
    golden["summary"]["isSession"] = False
    golden["summary"]["notASessionReason"] = "too_short"
    note = build_presentation(golden)["notASession"]
    assert note == {"args": {"distanceKm": golden["summary"]["distanceKm"],
                             "durationS": golden["summary"]["durationS"]},
                    "isSession": False,
                    "lineId": "verdicts.notASession.lines.1",
                    "reasonId": "too_short",
                    "tagId": "verdicts.notASession.tag"}

    golden["summary"]["notASessionReason"] = "no_recording"
    note = build_presentation(golden)["notASession"]
    assert note["lineId"] == "verdicts.notASession.lines.0" and note["args"] == {}


def test_an_unknown_policy_is_refused():
    with pytest.raises(ValueError):
        build_presentation(load(goldens()[0]), policy="whateverTheRiderTyped")


def test_the_rate_row_is_cph_then_one_dry_turn_rate(documents):
    """Jan, 25 Sep 2026: CPH first, then JPH on a jibes-only session or TPH once a tack
    is among the counted turns, then WPH — never JPH and TPH side by side. And the clean
    jibes are a cell of their own at the head of the turns row, in the clean ink."""
    seen = set()
    for stem, doc in documents.items():
        golden = load(GOLDENS / (stem + ".expected.json"))
        turns = golden["summary"]["turns"]
        rows = {row["id"]: row for row in doc["block"]["rows"]}
        if "rates" in rows:
            keys = [c["key"] for c in rows["rates"]["cells"]]
            if turns.get("tacks", 0) > 0:
                want = ["cph", "tph", "wph"]
            elif turns.get("jibes", 0) > 0:
                want = ["cph", "jph", "wph"]
            else:
                want = keys  # the no-jibe fallback is the branch test's
            assert keys == want, stem
            assert not {"jph", "tph"} <= set(keys), stem
            seen.add(tuple(keys))
        turn_keys = [c["key"] for c in rows.get("turns", {"cells": []})["cells"]]
        if turns.get("jibes", 0) > 0:
            clean = rows["turns"]["cells"][0]
            assert clean["key"] == "cleanJibes", stem
            assert clean["value"] == turns["jibesSuccessful"], stem
            assert clean["colourRole"] == "clean.jibe", stem
            tally = next(c for c in rows["turns"]["cells"] if c["key"] == "tally")
            assert "clean" not in tally["captions"][0]["args"], stem
        else:
            assert "cleanJibes" not in turn_keys, stem
    assert ("cph", "tph", "wph") in seen and ("cph", "jph", "wph") in seen
