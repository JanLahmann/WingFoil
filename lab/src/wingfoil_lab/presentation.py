"""The presentation document: every rider-facing FACT of one session, emitted once.

`docs/presentation/document.md` is the schema and the reason. The short version: five
surfaces — the iPhone, the web, the share card, the widgets and the watch's summary card —
each computed the same block, the same tally, the same record set and the same callout
sentence for themselves, in four languages, and the only thing keeping them honest was a
verifier that re-derived each one a third time. This module builds the facts **once**; a
renderer formats them and decides layout, and nothing else.

Three rules the document keeps, and they are what make it small:

* **No rider sentence is in it.** Every word a rider reads is an *id* into `docs/copy`
  (or into `design/tokens.json`, which is copy for the record and layer names), with the
  arguments the sentence interpolates. `presentation.caption.ofJibes` + `{"jibes": 50,
  "clean": 12}` — never "of 50 jibes · 12 clean".
* **No formatted number is in it.** A value is raw and carries a `unitKind`; the renderer
  formats it through its own `Units`/`Speed`, which is what lets one document serve a
  rider reading knots and a rider reading km/h.
* **No colour value is in it.** A cell carries a `colourRole` — a path into
  `design/tokens.json` (`outcome.fellIn`, `phase.flying`) or the literal `neutral`.

`build_presentation(golden)` is the whole door. It is a pure function of the analysis
golden plus the two policy inputs a rider owns (the speed-record policy, and the watch
summary when one was paired), and it is deterministic: sorted keys, fixed rounding, no
clocks and no locale. `ios/WingFoilKit/Sources/WingFoilKit/Presentation/
PresentationDocument.swift` is the twin and emits the same bytes.
"""

from __future__ import annotations

__all__ = [
    "PRESENTATION_VERSION",
    "RECORD_KINDS",
    "DEFAULT_RECORD_WINDOW",
    "DEFAULT_ROW_METRICS",
    "LEAN_CARD_KEYS",
    "FORBIDDEN_CARD_KEYS",
    "MAP_LAYERS",
    "TURN_TYPE_FILTERS",
    "TURN_SIDE_FILTERS",
    "SPEED_RECORD_POLICIES",
    "DEFAULT_SPEED_RECORD_POLICY",
    "build_presentation",
    "document_json",
    "sorted_tree",
    "round_to",
]

#: Bumped when the shape changes in a way a renderer has to know about. Independent of
#: `engineVersion`: the document is additive and no analysis number moved to add it.
PRESENTATION_VERSION = 1

#: `docs/presentation/records.md`, "Record windows" — nine kinds, canonical order.
RECORD_KINDS = ["best2s", "best10s", "best5x10s", "best100m", "best250m", "best500m",
                "bestNm", "bestHour", "alpha500"]
DEFAULT_RECORD_WINDOW = "best2s"

#: `RowMetric.defaultTriple` — what a library row draws until the rider says otherwise.
DEFAULT_ROW_METRICS = ["foilShare", "jibes", "best2s"]

#: `ShareCardStats.Preset.leanKeys`, in the order the contract spells them.
LEAN_CARD_KEYS = ["cleanJibes", "distance", "duration", "falls", "max2s", "tally"]

#: Keys that may never reach a card — real numbers the app shows in the tiles below the
#: block, which on a card would be a second, quieter answer to "was that a good session".
FORBIDDEN_CARD_KEYS = ["best500m", "flightCount", "flights", "foilPct", "longestFlight",
                       "wind"]

#: `design/tokens.json` `layers`, in its order. A line layer has no count.
MAP_LAYERS = [
    ("flying", None, "phase.flying"),
    ("offFoil", None, "phase.offFoil"),
    ("effort", None, "effort.window"),
    ("pumping", "pumping", "effort.pumping"),
    ("cleanJibe", "cleanJibe", "clean.jibe"),
    ("flewThrough", "flewThrough", "outcome.flew"),
    ("touchdown", "touchdown", "outcome.touchdown"),
    ("fellIn", "fellIn", "outcome.fellIn"),
    ("courseChange", "courseChange", "outcome.courseChange"),
    ("takeoff", "takeoff", "effort.takeoff"),
    ("splash", "splash", "effort.splash"),
    ("direction", None, "direction.ink"),
]

TURN_TYPE_FILTERS = ["both", "jibes", "tacks"]
TURN_SIDE_FILTERS = ["both", "port", "starboard"]

#: `SpeedRecordPolicy` — the rider's Settings → Speed records choice.
SPEED_RECORD_POLICIES = ["onlyVerified", "preferVerified", "includeUnverified"]
DEFAULT_SPEED_RECORD_POLICY = "preferVerified"

#: How many decimals a value of each unit kind carries. The engine's goldens are already
#: rounded to these, so re-rounding is idempotent; the Swift twin rounds a *live* analysis
#: the same way, which is what makes the two documents equal.
DECIMALS = {
    "speedKn": 3,
    "distanceKm": 3,
    "distanceM": 1,
    "durationS": 1,
    "seconds": 2,
    "percent": 2,
    "rate": 1,
    "score": 4,
    "count": None,
    "none": None,
}

#: The rider's word for each turn kind, as an id. The uncounted kinds cannot own a
#: submersion episode, but the map is spelled in full so a wrong one fails rather than
#: quietly reading "turn".
TURN_TYPE_IDS = {"jibe": "jibe", "tack": "tack", "turn": "turn",
                 "bear_away": "bearAway", "round_up": "roundUp"}

OUTCOME_IDS = {"flew_through": "flewThrough", "touchdown": "touchdown", "fell_in": "fellIn",
               "glide_out": "flewThrough"}

OUTCOME_COLOURS = {"flewThrough": "outcome.flew", "touchdown": "outcome.touchdown",
                   "fellIn": "outcome.fellIn", "courseChange": "outcome.courseChange"}


# ------------------------------------------------------------------ small helpers


def round_to(value, decimals):
    """Round for the document, the way both implementations round.

    Scale, round half to even on the scaled double, divide. Swift's
    `.rounded(.toNearestOrEven)` is the same operation on the same bits, which is the
    point: a 3-decimal knot value has one spelling on both platforms.

    `None` decimals means "leave it alone" (a count, a string, a flag). `-0.0` is
    normalised to `0.0` — "−0 must never appear" (docs/presentation/labels.md).
    """
    if value is None:
        return None
    if decimals is None:
        return value
    scale = 10 ** decimals
    out = round(float(value) * scale) / scale
    return 0.0 if out == 0 else out


def sorted_tree(value):
    """The same tree with every mapping's keys in sorted order.

    `json.dumps(..., indent=2)` then emits the document with sorted keys without sorting
    the file it is embedded in, and the Swift writer — which sorts — produces the same
    bytes.
    """
    if isinstance(value, dict):
        return {k: sorted_tree(value[k]) for k in sorted(value)}
    if isinstance(value, list):
        return [sorted_tree(v) for v in value]
    return value


def _cell(key, label_id, *, value=None, unit_kind="none", captions=None,
          colour_role="neutral", tally=None, counts=None):
    """One cell of a block row, a card tile or a library-row slot.

    `value` is raw and `unitKind` says what it is; `captions` are copy ids with their
    arguments; `colourRole` is a token path or `neutral`. `tally` is the three-rung
    outcome ladder, which is one fact on a fixed scale and therefore its own field;
    `counts` is the generic ordered pair the streaks cell needs, where the two halves are
    two different metrics rather than three rungs of one.
    """
    out = {
        "key": key,
        "labelId": label_id,
        "value": round_to(value, DECIMALS.get(unit_kind)),
        "unitKind": unit_kind,
        "captions": captions or [],
        "colourRole": colour_role,
    }
    if tally is not None:
        out["tally"] = tally
    if counts is not None:
        out["counts"] = counts
    return out


def _caption(copy_id, **args):
    return {"id": copy_id, "args": args}


def _ladder(counts):
    return {"flewThrough": counts.get("flewThrough", 0),
            "touchdown": counts.get("touchdown", 0),
            "fellIn": counts.get("fellIn", 0)}


def _outcome_layer(turn):
    """The chip a turn answers to. An uncounted sweep is a course change, whatever its
    outcome field says — a bear-away has no verdict."""
    if not turn.get("counted"):
        return "courseChange"
    return OUTCOME_IDS.get(turn.get("outcome"), "flewThrough")


def _drawn_flight_ends(doc):
    """The straight-line ends that get a hollow mark: no turn owns them, and the
    recording did not simply stop mid-flight."""
    return [e for e in doc.get("flightEnds", [])
            if e.get("ownedByTurn") is None and not e.get("truncated")]


# ------------------------------------------------------------------ the sections


def _block(doc, summary, turns, records):
    """The key-metrics block — `docs/presentation/key-metrics.md`, four rows.

    Every gate here is that file's, and nothing is re-derived: the tally falls back to
    every counted turn where the wind axis named no jibes, the tack ladder needs a tack
    *and* a jibe, the rate row gates on the jibe **count**, and a row with no cells is
    absent rather than empty.
    """
    rows = []

    # `avgSpeedKmh` itself is stored to 2 decimal places (docs/presentation/key-metrics.md
    # "Average speed is converted to knots") — a precision that suits a km/h column but
    # throws away a digit before the km/h-to-knot conversion even starts. `distanceKm` and
    # `timerTimeS` are the same division's two halves, each already at the document's own
    # convention precision, so re-deriving from them is the raw value at full precision
    # rather than a knot rounded twice.
    avg_kn = None
    if summary.get("avgSpeedKmh") is not None and summary.get("timerTimeS"):
        avg_kn = (summary["distanceKm"] / (summary["timerTimeS"] / 3600.0)) / 1.852
    rows.append({"id": "basics", "cells": [
        _cell("duration", "presentation.label.duration",
              value=summary.get("durationS"), unit_kind="durationS"),
        _cell("distance", "presentation.label.distance",
              value=summary.get("distanceKm"), unit_kind="distanceKm"),
        _cell("avgSpeed", "presentation.label.avgSpeed",
              value=avg_kn, unit_kind="speedKn"),
    ]})

    # Row 2 names the WINDOW, not the peak. The two composites beside it are block-only:
    # the card is the block minus them, because a card carries one speed.
    rows.append({"id": "speed", "cells": [
        _cell("max2s", "presentation.label.max2s",
              value=records.get("best2sKn"), unit_kind="speedKn"),
        _cell("best5x10s", "presentation.label.best5x10s",
              value=records.get("best5x10sKn"), unit_kind="speedKn"),
        _cell("alpha500", "presentation.label.alpha500",
              value=records.get("alpha500Kn"), unit_kind="speedKn"),
    ]})

    turn_cells = []
    # **The clean jibes lead the row, in their own cell** (Jan, 25 Sep 2026, F8e). They
    # were a clause in the tally's caption — "of 5 jibes · 4 clean" — which made the one
    # number the product is named for the smallest type in the block. A jibe that is clean
    # also flew through, so the ladder beside it still counts it: the star is the stricter
    # reading of the same turns, not a fourth rung.
    if turns.get("jibes", 0) > 0:
        turn_cells.append(_cell("cleanJibes", "presentation.label.cleanJibes",
                                value=turns.get("jibesSuccessful", 0), unit_kind="count",
                                colour_role="clean.jibe"))
    tally = _tally_cell(turns)
    if tally is not None:
        turn_cells.append(tally)
    tacks = _tack_cell(turns)
    if tacks is not None:
        turn_cells.append(tacks)
    falls = _falls_cell(summary)
    if falls is not None:
        turn_cells.append(falls)
    if turns.get("turnsCounted", 0) > 0:
        # Flying leads the pair: the harder run first, and the smaller number always. Each
        # half wears the ink of what it counts (F8f): a flew streak is the ladder's green,
        # and a dry streak — flew *or* touched down, never fell — is the body ink, because
        # no single rung of the ladder is what it counts.
        turn_cells.append(_cell(
            "streaks", "presentation.label.streaks", unit_kind="count",
            counts=[{"labelId": "glossary.flewThrough",
                     "value": turns.get("longestFlewStreak", 0),
                     "colourRole": "outcome.flew"},
                    {"labelId": "glossary.dry",
                     "value": turns.get("longestDryStreak", 0),
                     "colourRole": "neutral"}]))
    if turn_cells:
        rows.append({"id": "turns", "cells": turn_cells})

    rates = _rate_cells(summary, turns)
    if rates:
        rows.append({"id": "rates", "cells": rates})

    return {"rows": rows}


def _tally_cell(turns):
    """The jibe ladder, or the whole counted-turn ladder where the wind axis named no
    jibes. The caption says which. The clean count is the `cleanJibes` cell beside it since
    25 Sep 2026, so the caption no longer carries it: one fact, one cell."""
    if turns.get("jibes", 0) > 0:
        return _cell("tally", "presentation.label.outcomeLadder", unit_kind="count",
                     colour_role="outcome.ladder",
                     tally=_ladder(turns.get("jibeOutcomes", {})),
                     captions=[_caption("presentation.caption.ofJibes",
                                        jibes=turns["jibes"])])
    if turns.get("turnsCounted", 0) <= 0:
        return None
    # No clean clause on the fallback: `turnsSuccessful` is the score verdict over every
    # counted turn, and a session whose wind axis named no jibes has no clean jibes.
    return _cell("tally", "presentation.label.outcomeLadder", unit_kind="count",
                 colour_role="outcome.ladder",
                 tally=_ladder(turns.get("outcomes", {})),
                 captions=[_caption("presentation.caption.ofTurns",
                                    turns=turns["turnsCounted"])])


def _tack_cell(turns):
    """The tack ladder beside the jibe one. Two gates: a tack to report, and a jibe tally
    that is the *jibe* ladder — otherwise the fallback above already counted these turns."""
    if turns.get("tacks", 0) <= 0 or turns.get("jibes", 0) <= 0:
        return None
    return _cell("tacks", "presentation.label.outcomeLadder", unit_kind="count",
                 colour_role="outcome.ladder",
                 tally=_ladder(turns.get("tackOutcomes", {})),
                 captions=[_caption("presentation.caption.ofTacks", tacks=turns["tacks"])])


def _falls_cell(summary):
    """Every fall of the session, off the flight-end channel, with the split in its
    caption. Absent where no flight ended at all — an unknown number, not zero."""
    ends = summary.get("flightEnds", {})
    all_ends = ends.get("all", {})
    # `unknown` is deliberately outside the sum: an end the recording truncated carries no
    # evidence, and a session whose only ends are those has an *unknown* number of falls
    # rather than zero of them (`FlightEndCounts.total`).
    total = (all_ends.get("glideOut", 0) + all_ends.get("touchdown", 0)
             + all_ends.get("fellIn", 0))
    if total <= 0:
        return None
    return _cell("falls", "glossary.fellIn", value=all_ends.get("fellIn", 0),
                 unit_kind="count",
                 captions=[_caption("presentation.caption.fallsSplit",
                                    inTurn=ends.get("inTurn", {}).get("fellIn", 0),
                                    straight=ends.get("straight", {}).get("fellIn", 0))])


def _rate_cells(summary, turns):
    """Row 4. Empty where there is no hour to divide by.

    **CPH first, then ONE dry-turn rate, then WPH** (Jan, 25 Sep 2026 — it supersedes
    "JPH and TPH side by side"). The dry-turn rate is JPH while the session's counted
    turns are all jibes, and TPH once a tack is among them: a tacking rider's jibe rate
    leaves a share of his afternoon out, and two dry rates side by side are two answers to
    one question. A session whose wind axis named no jibes has no clean jibes to rate, so
    CPH is absent there and TPH stands alone. Gated on the **counts**, never on a rate.
    """
    if summary.get("wetPerHour") is None:
        return []
    jibes = turns.get("jibes", 0)
    tph = summary.get("turnsPerHour") or 0.0
    out = []
    if jibes > 0 or not tph > 0:
        out.append(_cell("cph", "glossary.cph",
                         value=summary.get("cleanJibesPerHour") or 0.0, unit_kind="rate"))
    if turns.get("tacks", 0) > 0 or (jibes <= 0 and tph > 0):
        out.append(_cell("tph", "glossary.tph", value=tph, unit_kind="rate"))
    else:
        out.append(_cell("jph", "glossary.jph", value=summary.get("jibesPerHour") or 0.0,
                         unit_kind="rate"))
    out.append(_cell("wph", "glossary.wph", value=summary["wetPerHour"], unit_kind="rate"))
    return out


def _card(block):
    """The share card is the block, re-laid-out — minus the two block-only speed cells.

    Nothing is computed here that the block does not already carry: a preset can only drop
    a tile, never reword, reorder or invent one.
    """
    tiles = []
    for row in block["rows"]:
        for cell in row["cells"]:
            if cell["key"] in ("best5x10s", "alpha500"):
                continue
            tile = dict(cell)
            tile["presets"] = (["complete", "lean"] if cell["key"] in LEAN_CARD_KEYS
                               else ["complete"])
            tiles.append(tile)
    return {"tiles": tiles, "leanKeys": list(LEAN_CARD_KEYS),
            "forbiddenKeys": list(FORBIDDEN_CARD_KEYS)}


def _row(summary, turns, records, is_session):
    """The library row: three slots the rider chose, and the tally it wears.

    The row's tally is over **every counted turn**, not over the jibes — a row scanned
    against its neighbours has to be one set of turns down the whole list.
    """
    values = {
        "foilShare": (summary.get("foilPct"), "percent"),
        "flights": (summary.get("flightCount"), "count"),
        "jibes": (turns.get("jibes"), "count"),
        "cleanJibes": (turns.get("jibesSuccessful"), "count"),
        "turns": (turns.get("turnsCounted"), "count"),
        "best2s": (records.get("best2sKn"), "speedKn"),
        "best10s": (records.get("best10sKn"), "speedKn"),
        "distance": (summary.get("distanceKm"), "distanceKm"),
        "duration": (summary.get("durationS"), "durationS"),
        "dryStreak": (turns.get("longestDryStreak"), "count"),
        "falls": (summary.get("flightEnds", {}).get("all", {}).get("fellIn"), "count"),
    }
    slots = []
    for metric in DEFAULT_ROW_METRICS:
        value, unit = values[metric]
        slots.append(_cell(metric, "presentation.rowMetric." + metric,
                           value=value, unit_kind=unit))
    out = {"slots": slots, "offered": sorted(values), "tally": None, "tagIds": []}
    if turns.get("turnsCounted", 0) > 0:
        out["tally"] = _ladder(turns.get("outcomes", {}))
    if not is_session:
        out["tagIds"] = ["verdicts.notASession.tag"]
    return out


def _records(doc, records, policy):
    """The nine kinds: value, window provenance, whether it was verified, and whether the
    rider's policy lets it stand.

    `verified` is the recording's own Doppler channel (`capabilities.hasDoppler`) — the
    same question `SpeedRecordRule` asks, in the one place the analysis can answer it. A
    session is one candidate per kind, so `preferVerified` has nothing to prefer and
    answers like `includeUnverified` (`SpeedRecordRule.stands`).
    """
    verified = bool(doc.get("capabilities", {}).get("hasDoppler"))
    stands = verified or policy != "onlyVerified"
    windows = records.get("windows") or {}
    kinds = []
    for key in RECORD_KINDS:
        value = records.get(key + "Kn")
        window = windows.get(key)
        if window is None:
            spans = []
        elif isinstance(window, list):
            spans = list(window)
        else:
            spans = [window]
        spans = [{"startTs": round_to(w.get("startTs"), DECIMALS["seconds"]),
                  "durS": round_to(w.get("durS"), DECIMALS["seconds"])} for w in spans]
        achieved = value is not None and value > 0 and bool(spans)
        kinds.append({
            "key": key,
            "labelId": "tokens.recordWindow." + key,
            "value": round_to(value, DECIMALS["speedKn"]),
            "unitKind": "speedKn",
            "windows": spans,
            "achieved": achieved,
            "verified": verified,
            "offered": achieved and stands,
            "colourRole": "effort.window",
        })
    achieved_keys = [k["key"] for k in kinds if k["achieved"]]
    return {
        "kinds": kinds,
        "achieved": achieved_keys,
        "policy": policy,
        "verified": verified,
        "default": DEFAULT_RECORD_WINDOW if DEFAULT_RECORD_WINDOW in achieved_keys else None,
    }


def _turns(doc, markers):
    """The Turns tab: the legend chips with their live counts, and one strip entry per
    detected sweep.

    `ordinal` is the turn's position among the counted turns of its own kind — the number
    the turn page's "3 of 14" and the wrist-under callout both name, computed once here so
    two surfaces cannot count differently.
    """
    counts = {
        "flewThrough": markers["flewThrough"],
        "touchdown": markers["touchdown"],
        "fellIn": markers["fellIn"],
        "courseChange": markers["courseChange"],
        "cleanJibe": markers["cleanJibe"],
        "takeoff": markers["takeoff"]["total"],
        "splash": markers["splash"],
        "pumping": markers["pumping"],
    }
    legend = [{"layerId": layer_id,
               "labelId": "tokens.layer." + layer_id,
               "count": counts.get(count_key) if count_key else None,
               "colourRole": colour,
               "defaultVisible": True}
              for layer_id, count_key, colour in MAP_LAYERS]

    ordinals = {}
    strip = []
    for index, turn in enumerate(doc.get("turns", [])):
        layer = _outcome_layer(turn)
        ordinal = None
        if turn.get("counted"):
            kind = turn.get("type")
            ordinals[kind] = ordinals.get(kind, 0) + 1
            ordinal = ordinals[kind]
        strip.append({
            "index": index,
            "counted": bool(turn.get("counted")),
            "ordinal": ordinal,
            "typeId": TURN_TYPE_IDS.get(turn.get("type"), "turn"),
            "sideId": turn.get("side"),
            "outcomeId": OUTCOME_IDS.get(turn.get("outcome"), "flewThrough"),
            "outcomeReasonId": turn.get("outcomeReason"),
            "clean": bool(turn.get("clean")),
            "cleanBlockedById": turn.get("cleanBlockedBy"),
            "aborted": bool(turn.get("aborted")),
            "borderline": bool(turn.get("borderline")),
            "ts": round_to(turn.get("ts"), DECIMALS["seconds"]),
            "minTs": round_to(turn.get("minTs"), DECIMALS["seconds"]),
            "endTs": round_to(turn.get("endTs"), DECIMALS["seconds"]),
            "entryKn": round_to(turn.get("entryKn"), DECIMALS["speedKn"]),
            "minKn": round_to(turn.get("minKn"), DECIMALS["speedKn"]),
            "exitKn": round_to(turn.get("exitKn"), DECIMALS["speedKn"]),
            "score": round_to(turn.get("score"), DECIMALS["score"]),
            "layerId": "cleanJibe" if turn.get("clean") else layer,
            "colourRole": OUTCOME_COLOURS[layer],
        })
    return {"legend": legend, "strip": strip}


def _markers(doc):
    """Turn outcomes, the drawn straight-line ends, the star layer and the two effort
    layers — the counts `fixtures/presentation/*.expected.json` has always pinned."""
    counts = {"flewThrough": 0, "touchdown": 0, "fellIn": 0, "courseChange": 0}
    for turn in doc.get("turns", []):
        counts[_outcome_layer(turn)] += 1
    for end in _drawn_flight_ends(doc):
        counts[OUTCOME_IDS.get(end.get("outcome"), "flewThrough")] += 1
    takeoffs = doc.get("takeoffs", [])
    free = sum(1 for t in takeoffs if t.get("free"))
    episodes = doc.get("pumpEpisodes", [])
    counts["cleanJibe"] = sum(1 for t in doc.get("turns", []) if t.get("clean"))
    counts["takeoff"] = {
        "pumped": len(takeoffs) - free,
        "free": free,
        "failed": sum(1 for e in episodes if e.get("outcome") == "failed"),
    }
    counts["takeoff"]["total"] = (counts["takeoff"]["pumped"] + counts["takeoff"]["free"]
                                 + counts["takeoff"]["failed"])
    counts["pumping"] = sum(1 for e in episodes
                            if e.get("outcome") in ("success", "failed"))
    counts["splash"] = len(doc.get("submersions", []))
    return counts


def _flight_ends(doc, summary):
    """Every flight end in the three buckets the marker rules distinguish, and one entry
    per *drawn* end — the hollow marks no turn explains."""
    ends = doc.get("flightEnds", [])
    drawn = _drawn_flight_ends(doc)
    marks = []
    for index, end in enumerate(ends):
        if end.get("ownedByTurn") is not None or end.get("truncated"):
            continue
        layer = OUTCOME_IDS.get(end.get("outcome"), "flewThrough")
        marks.append({
            "index": index,
            "flightIndex": end.get("flightIndex"),
            "ts": round_to(end.get("ts"), DECIMALS["seconds"]),
            "outcomeId": layer,
            "colourRole": OUTCOME_COLOURS[layer],
            "stoppedS": round_to(end.get("stoppedS"), DECIMALS["seconds"]),
            "hollow": True,
        })
    return {
        "flightCount": summary.get("flightCount"),
        "drawn": len(drawn),
        "ownedByTurn": sum(1 for e in ends
                           if e.get("ownedByTurn") is not None and not e.get("truncated")),
        "truncated": sum(1 for e in ends if e.get("truncated")),
        "total": len(ends),
        "marks": marks,
    }


def _splash(doc):
    """"Wrist under" — one mark per submersion episode, and the callout it prints, as
    copy ids with their arguments (`docs/presentation/layers-map-colour-type.md`)."""
    marks = []
    turns = doc.get("turns", [])
    ends = doc.get("flightEnds", [])
    for sub in doc.get("submersions", []):
        duration = sub.get("durationS") or 0.0
        if round(duration) < 1:
            title = _caption("presentation.wristUnder.title")
        else:
            title = _caption("presentation.wristUnder.titleFor",
                             durationS=round_to(duration, 0))
        index = sub.get("turnIndex")
        if index is not None and 0 <= index < len(turns):
            turn = turns[index]
            type_id = TURN_TYPE_IDS.get(turn.get("type"), "turn")
            same = [i for i, t in enumerate(turns)
                    if t.get("counted") and t.get("type") == turn.get("type")]
            if index in same:
                during = _caption("presentation.wristUnder.duringTurn",
                                  turnId=type_id, ordinal=same.index(index) + 1)
            else:
                during = _caption("presentation.wristUnder.duringAnyTurn", turnId=type_id)
        elif sub.get("flightEndIndex") is not None:
            end = ends[sub["flightEndIndex"]]
            stopped = end.get("stoppedS") or 0.0
            if stopped >= 1:
                during = _caption("presentation.wristUnder.afterFlightStopped",
                                  flight=end.get("flightIndex", 0) + 1,
                                  stoppedS=round_to(stopped, 0))
            else:
                during = _caption("presentation.wristUnder.afterFlight",
                                  flight=end.get("flightIndex", 0) + 1)
        else:
            during = _caption("presentation.wristUnder.offFoil")
        marks.append({
            "ts": round_to(sub.get("ts"), DECIMALS["seconds"]),
            "durationS": round_to(duration, DECIMALS["seconds"]),
            "turnIndex": sub.get("turnIndex"),
            "flightEndIndex": sub.get("flightEndIndex"),
            "title": title,
            "during": during,
            "colourRole": "effort.splash",
        })
    return {"episodes": len(marks), "marks": marks}


def _filters(doc):
    """Every type × ENTRY-side combination over the counted turns, with the flew-through
    share's numerator. Side is the tack the turn was entered on, never the rotation."""
    counted = [t for t in doc.get("turns", []) if t.get("counted")]
    out = []
    for kind in TURN_TYPE_FILTERS:
        for side in TURN_SIDE_FILTERS:
            kept = [t for t in counted
                    if (kind == "both" or t.get("type") == ("jibe" if kind == "jibes"
                                                            else "tack"))
                    and (side == "both" or t.get("side") == side)]
            out.append({
                "typeId": kind,
                "sideId": side,
                "count": len(kept),
                "flewThrough": sum(1 for t in kept if _outcome_layer(t) == "flewThrough"),
            })
    return out


def _not_a_session(summary):
    """What the rider is told about a recording that was never an afternoon — the row's
    quiet tag and the page's one line, as ids with the two numbers that decided."""
    if summary.get("isSession", True):
        return {"isSession": True, "reasonId": None, "tagId": None, "lineId": None,
                "args": {}}
    reason = summary.get("notASessionReason")
    line = ("verdicts.notASession.lines.0" if reason == "no_recording"
            else "verdicts.notASession.lines.1")
    args = {}
    if line.endswith(".1"):
        args = {"durationS": round_to(summary.get("durationS"), DECIMALS["durationS"]),
                "distanceKm": round_to(summary.get("distanceKm"), DECIMALS["distanceKm"])}
    return {"isSession": False, "reasonId": reason, "tagId": "verdicts.notASession.tag",
            "lineId": line, "args": args}


def _divergence(lines):
    """The watch-vs-phone banner. The watch summary is not part of the analysis, so a
    document built from a golden alone carries the empty, honest answer."""
    return {"available": bool(lines), "lines": list(lines or [])}


# --------------------------------------------------------------------- the door


def build_presentation(golden, *, policy=DEFAULT_SPEED_RECORD_POLICY, divergence=None):
    """Every presentation fact of one session, once.

    - `golden`: an analysis document in the golden schema (docs/testing.md).
    - `policy`: Settings → Speed records. **Not** the speed unit: a knot is what the
      engine measured and the unit is the renderer's, which is exactly why the document
      carries raw values and a `unitKind`.
    - `divergence`: the banner's lines, when a watch summary was paired; the analysis
      cannot know them.

    Deterministic: sorted keys, fixed rounding, no clock and no locale.
    """
    if policy not in SPEED_RECORD_POLICIES:
        raise ValueError("unknown speed-record policy: " + repr(policy))
    summary = golden.get("summary", {})
    turns = summary.get("turns", {})
    records = golden.get("records", {})
    markers = _markers(golden)
    block = _block(golden, summary, turns, records)
    record_block = _records(golden, records, policy)

    return sorted_tree({
        "presentationVersion": PRESENTATION_VERSION,
        "engineVersion": golden.get("engineVersion"),
        "block": block,
        "card": _card(block),
        "row": _row(summary, turns, records, summary.get("isSession", True)),
        "records": record_block,
        "turns": _turns(golden, markers),
        "markers": markers,
        "flightEnds": _flight_ends(golden, summary),
        "splash": _splash(golden),
        "filters": _filters(golden),
        "defaults": {
            "recordWindow": record_block["default"],
            "section": "ride",
            "cardPreset": "complete",
            "rowMetrics": list(DEFAULT_ROW_METRICS),
            "speedRecordPolicy": policy,
        },
        "divergence": _divergence(divergence),
        "notASession": _not_a_session(summary),
    })


def document_json(document, indent=2):
    """The document as the goldens spell it: sorted keys, ASCII-safe, one trailing
    newline. The Swift twin's canonical writer produces these bytes."""
    import json

    return json.dumps(sorted_tree(document), indent=indent, ensure_ascii=False) + "\n"
