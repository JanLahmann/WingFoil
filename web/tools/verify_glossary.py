"""Every metric label the browser prints is a glossary term.

    python3 web/tools/verify_glossary.py            # the list, with the allow-list
    python3 web/tools/verify_glossary.py --brief    # one line — what verify_links.py runs

THE CASE, 20 September 2026. A tester compared three screens about one afternoon and read
*Turn success 29 %* in Garmin Connect, *93 % flew through* on this site and 44 % on the
phone. All three were right. Nothing said they were three different measurements, and
nothing could have: the words that collided were typed in files that never met.

So `docs/copy/glossary.json` is the meeting place. It is written out of the kit's
`MetricGlossary` (`COPY_WRITE=1 swift test --filter CopyContractTests`), every entry carries
`labels` — **every spelling a surface may print for that term** — and the kit's
`GlossaryLintTests` holds the phone's own labels to it. This is the same lint for the
browser: a label a rider reads here is a glossary spelling, or it is a unit, a clock, a
plain measure or a maneuver noun on the allow-list below, with a reason.

WHAT IT SCANS, and why each region rather than the whole file: a JavaScript file is full of
strings, and most of them are not labels. So every scan is anchored to the one shape that
produces a label, the way the kit's lint scans `StatCard(title: "…")` in one file:

  js/render.js      the session page's tiles (`k:`) and the takeoff block's rows
  js/trends.js      `renderTotals`, the Trends totals list

  docs/copy/watch.json
                    every word the WATCH prints that names a number — a page word and a
                    Garmin Connect field name — held to the term its entry declares. The
                    watch was outside this lint until 22 September 2026, and it is the
                    surface the incident above actually happened on: `Turn success 29 %` was
                    a Garmin Connect row. An entry that names a term whose spelling it does
                    not use carries a `why`, which is printed like the allow-list below.

  docs/copy/presentation.json
                    `label`, `rowMetric` and `divergence` — the key-metrics block (which IS
                    the share card), the library row's cells and the watch-vs-phone rows.
                    Since ADR-033 round 3 the browser types none of those words: the
                    document names an **id** and `js/presentation.js` resolves it here, so
                    the file is what a rider actually reads and the file is what is linted.
                    Three source scans retired with the literals they used to find — and a
                    literal creeping back is caught by the scans that remain, because a
                    label that is not resolved from copy has to be written somewhere.

WHAT IT DOES NOT SCAN, deliberately:

  * **the aggregate labels the digest authors** (`lab_bundle/library.py`: the records table,
    the chart titles, the period block). They are the engine's output, mirrored from `lab/`
    by `bundle_lab.py`, and the browser prints them without a word of its own. Each is a
    superlative or a rate over a term that IS in the glossary — "Longest dry streak",
    "Best CPH" — and the place to hold them is the lab, in the round that gives the lab a
    glossary of its own.
  * **table column heads** (`entry kn`, `stop s`, `#`). A column head is read with its table
    and its neighbours; a metric label is read alone, under a number, and that is the one
    this file is about.
"""
import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))          # web/
REPO = os.path.dirname(ROOT)
GLOSSARY = os.path.join(REPO, "docs", "copy", "glossary.json")
WATCH = os.path.join(REPO, "docs", "copy", "watch.json")

#: What a metric label may be without being a glossary term — the kit's
#: `GlossaryLintTests.allowed`, plus the four the browser prints and the phone does not.
#: Each entry says why, and the whole list is printed on every full run, because an
#: allow-list nobody reads becomes the rule.
ALLOWED = {
    "duration": "a clock. Every product spells it the same and CleanJibe adds nothing",
    "time": "the same clock, at a row's width",
    "distance": "a plain measure, in km",
    "avg speed": "a plain measure. The window it averages is the session itself",
    "longest flight": "a clock over the flights term, not a second metric",
    "jibes": "a maneuver noun from the rider lexicon, not a metric",
    "tacks": "a maneuver noun from the rider lexicon, not a metric",
    "turns": "a maneuver noun from the rider lexicon, not a metric",
    "unclassified turns": "the maneuver noun with the state that named it",
    "port / starboard": "the entry side, a dimension of a turn rather than a metric",
    "glide-outs": "a flight-end verdict that is not a loss and has no other surface",
    "touchdowns": "the plural of the touchdown term",
    "touchdowns · glide-outs": "the touchdown term and the glide-out verdict on one card: "
                               "both a flight that ended without a swim (Jan, 25 Sep 2026)",
    "best streaks": "the dry-streak term at the block's width",
    "pumps to takeoff": "a stroke count, under the takeoffs term",
    "takeoff run": "a clock, under the takeoffs term",
    "pump strokes": "a stroke count",
    "failed attempts": "the attempts term's complement, spelled on the same card",
    "run to planing": "the windsurf lexicon's spelling of the takeoff run",
    "heart rate": "a sensor reading, not a CleanJibe verdict",
    # The browser's own four.
    "sessions": "a count of afternoons — the library's size, not a measurement of one",
    "turns counted": "the maneuver noun with the state that named it, like "
                     "\"unclassified turns\" above",
    "wind axis": "a reading of the water, not of the rider. It has no verdict and no "
                 "second surface to disagree with",
    "avg pumps to takeoff": "the pumps-to-takeoff count with the window it averages",
    "median pumps to takeoff": "the same count at the other average",
    "total pump strokes": "the pump-stroke count over the session",
    "in-flight pump strokes": "the pump-stroke count over the flights",
    "free takeoffs (no pumping)": "the takeoffs term with the condition that made it free",
    "avg time to foil": "a clock, under the takeoffs term — the takeoff run averaged",
    "median time to foil": "the same clock at the other average",
}

#: Where a label can be written, and the shape that makes it one. `region` is a function or
#: a const to look inside — a JavaScript file is mostly strings, and only a few of them are
#: names a rider reads under a number.
SCANS = [
    ("js/render.js", "renderSummary", r"\bk:\s*\"([^\"]*)\"",
     "a session-page tile"),
    ("js/render.js", "renderTakeoffs", r"\[\s*\"([^\"]*)\",",
     "a takeoff-block row"),
    ("js/trends.js", "renderTotals", r"\[\s*\"([^\"]*)\",",
     "a Trends totals row"),
]

#: The copy groups the browser resolves a `labelId` into, and what each one names. Every
#: value in them is a word a rider reads under a number (ADR-033, `docs/presentation/
#: document.md`), so every value is linted exactly as a literal used to be.
COPY_GROUPS = [
    ("label", "the key-metrics block, and therefore the share card"),
    ("rowMetric", "a library row's cell"),
    ("divergence", "a watch-vs-phone row"),
]

#: What `cardstats.js` hangs a cell's qualifier off. A caption is not a name: "of 55 jibes"
#: and "4 in a turn · 21 in a straight line" qualify the number, they do not call it
#: anything. Kept in step with `CAPTION_SEP` in js/cardstats.js and `KeyMetricsView`.
CAPTION_SEP = " — "

#: The six speed records the watch-vs-phone table can name come from
#: `tokens.recordWindow.<id>` (design/tokens.json), not from the copy file — there is one
#: spelling of `Best 2 s` in the product and the legend chip owns it.
EXTRA: list = []


def labels_of(entry: dict) -> list:
    """Every spelling this term may be printed as.

    `labels` and the term itself, plus `short` — the same word at the WATCH's width, which
    docs/copy/glossary.json keeps as a field precisely so that a MIP cell is held to the
    contract rather than excused from it. The browser never prints a `short`; the watch
    prints little else.
    """
    return (list(entry.get("labels") or [])
            + [entry["term"]]
            + ([entry["short"]] if entry.get("short") else []))


def watch_rows() -> list:
    """(entry, where) for every watch string that NAMES A NUMBER.

    Two surfaces, derived by docs/copy/watch.json rather than declared on each entry (see
    its `_readme`): a PAGE word is an entry with a `var`, the word the glass draws under a
    number; a GARMIN CONNECT FIELD is an id beginning `Fit` that is not one of the units. A
    settings row is a question rather than a label and is judged by check_voice.py instead.
    """
    doc = json.load(open(WATCH, encoding="utf-8"))
    rows = []
    for entry in doc["strings"]:
        if entry.get("var"):
            rows.append((entry, "a watch page word"))
        elif entry["id"].startswith("Fit") and not entry["id"].startswith("FitUnit"):
            rows.append((entry, "a Garmin Connect field"))
    return rows


def known(label: str, glossary: set) -> bool:
    want = label.strip().lower()
    return want in glossary or want in ALLOWED


CLOSER = {"{": "}", "[": "]"}


def region(text: str, name: str) -> str:
    """The body of one function or one const, by matching its brackets.

    Deliberately crude, like the kit's own `quoted`: it is a lint over a handful of files
    with one shape each, and a JavaScript parser here would be a second engine. The
    declaration is found by its own shape (`function name(`, `const name =`) rather than by
    the first mention of the word, which is usually a comment; the region is then from its
    first `{` or `[` to the bracket that closes it. A region that cannot be found is an
    error rather than an empty scan — a renamed function must fail loudly, not quietly stop
    checking.
    """
    at = -1
    for shape in ("function %s(" % name, "const %s =" % name, "%s(" % name):
        at = text.find(shape)
        if at != -1:
            break
    if at == -1:
        return ""
    opens = [(text.find(o, at), o) for o in CLOSER if text.find(o, at) != -1]
    if not opens:
        return ""
    start, opener = min(opens)
    depth, i = 0, start
    while i < len(text):
        if text[i] == opener:
            depth += 1
        elif text[i] == CLOSER[opener]:
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
        i += 1
    return ""


def scan(path: str, name: str, pattern: str) -> list:
    """Every label the pattern finds inside the named region of one file."""
    text = open(os.path.join(ROOT, path), encoding="utf-8").read()
    body = region(text, name)
    if not body:
        raise LookupError("%s has no %s to scan — was it renamed?" % (path, name))
    out = []
    for found in re.finditer(pattern, body):
        raw = found.group(1)
        if raw.startswith(("\"", "`")):
            raw = raw[1:-1]
        # A template literal's interpolations are values, never words: a label that is all
        # `${…}` has nothing to check, and one that carries a caption is cut at the
        # separator that hangs the caption off it.
        raw = raw.split("${" + "CAPTION_SEP}")[0]
        if "${" in raw:
            raw = re.sub(r"\$\{[^}]*\}", "", raw)
        raw = raw.strip()
        if raw:
            out.append(raw)
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--brief", action="store_true",
                    help="one summary line — what verify_links.py runs")
    args = ap.parse_args(argv)

    doc = json.load(open(GLOSSARY, encoding="utf-8"))
    entries = doc["entries"]
    glossary = {label.strip().lower() for e in entries for label in labels_of(e)}

    problems, seen, checked = [], [], 0
    for path, name, pattern, where in SCANS:
        try:
            found = scan(path, name, pattern)
        except LookupError as exc:
            problems.append(str(exc))
            continue
        if not found:
            problems.append("%s: the %s scan found no label at all — check the pattern"
                            % (path, name))
        for label in found:
            checked += 1
            seen.append((path, label, where, known(label, glossary)))
    for path, label, where in EXTRA:
        checked += 1
        seen.append((path, label, where, known(label, glossary)))

    # The words the presentation document points at. The browser prints these and types
    # none of them, so this is where the lint has to look since ADR-033 round 3.
    copy = json.load(open(os.path.join(REPO, "docs", "copy", "presentation.json"),
                          encoding="utf-8"))
    for group, where in COPY_GROUPS:
        values = copy.get(group) or {}
        if not values:
            problems.append("docs/copy/presentation.json has no %s group — was it renamed?"
                            % group)
        for label in values.values():
            checked += 1
            seen.append(("docs/copy/presentation.json", label, where,
                         known(label, glossary)))

    # ---- the watch (22 September 2026) ----
    #
    # Held to the term its own entry names, not to the glossary at large: a page that called
    # the foil share "flights" would pass a check that only asked whether the word is in the
    # book. A `why` is a deliberate divergence at the glass's width and is printed below,
    # like the allow-list. A word that IS a glossary spelling and names no term fails — a
    # label this lint cannot see is a label that drifts, which is the whole case above.
    spellings = {e["id"]: {s.strip().lower() for s in labels_of(e)} for e in entries}
    divergences = []
    for entry, where in watch_rows():
        checked += 1
        label, term = entry["text"], entry.get("term")
        if term is None:
            ok = not known(label, glossary) or label.strip().lower() in ALLOWED
            if not ok:
                problems.append(
                    'docs/copy/watch.json prints "%s" (%s) as `%s` and names no `term`.\n'
                    "      It is a spelling of a glossary word, so say which one: add "
                    '"term": "<glossary id>" to that entry.' % (label, where, entry["id"]))
            seen.append(("docs/copy/watch.json", label, where, True))
            continue
        if term not in spellings:
            problems.append('docs/copy/watch.json: "%s" names the term `%s`, which is not '
                            "in docs/copy/glossary.json" % (entry["id"], term))
            continue
        ok = label.strip().lower() in spellings[term]
        if not ok and entry.get("why"):
            divergences.append((label, term, entry["where"], entry["why"]))
            ok = True
        elif not ok:
            problems.append(
                'docs/copy/watch.json prints "%s" (%s) for the glossary term `%s`, which '
                "is not one of its spellings.\n"
                "      Either spell it the way the term is spelled, or — where the glass "
                "cannot take that word — add a `why` to the entry saying what it could not "
                "take." % (label, where, term))
        seen.append(("docs/copy/watch.json", label, where, ok))

    for path, label, where, ok in seen:
        if not ok:
            problems.append(
                '%s prints "%s" (%s) and it is not a glossary term.\n'
                "      Add it to MetricGlossary — as a term, or as a `labels` spelling of "
                "the term it already is — and regenerate docs/copy/glossary.json; or, if it "
                "is a unit, a clock or a maneuver noun, add it to verify_glossary.ALLOWED "
                "with the reason." % (path, label, where))

    if not args.brief:
        for path, label, where, ok in seen:
            print("  %-4s %-28s %s · %s" % ("ok" if ok else "FAIL", label, path, where))
        print("\n  the allow-list — a label may be one of these without being a term:")
        for label in sorted(ALLOWED):
            print("    · %-28s %s" % (label, ALLOWED[label]))
        print("\n  the watch's divergences — a word the glass could not take, with the "
              "reason (docs/copy/watch.json):")
        for label, term, where, why in divergences:
            print("    · %-18s %-16s %s\n      %s" % (label, term, where, why))

    if problems:
        print("\n%d PROBLEM(S) — a number the browser calls something the glossary does "
              "not:" % len(problems))
        for problem in problems:
            print("  " + problem)
        return 1

    print("glossary: %d rider-facing metric labels over %d surfaces, every one a term in "
          "docs/copy/glossary.json (%d entries) or on the allow-list (%d); the watch adds "
          "%d divergences, each with its reason"
          % (checked, len({p for p, _, _, _ in seen}), len(entries), len(ALLOWED),
             len(divergences)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
