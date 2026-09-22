#!/usr/bin/env python3
"""The watch's words, written out of ``docs/copy`` (ADR-034).

    python3 garmin/tools/make_strings.py            # write the three generated files
    python3 garmin/tools/make_strings.py --check    # exit 1 while one of them is stale

WHAT IT WRITES

  garmin/resources/strings/strings.xml          every ``stream: base`` string
  garmin/resources-dev/base/strings/strings.xml every ``stream: dev`` string
  garmin/source/ui/Words.mc                     the module a page draws them through

WHY. The watch was the last rider surface outside the copy contract. Its settings rows and
its FIT field names were typed in ``resources/strings/strings.xml``, its page words were
``"…"`` literals inside the Monkey C that draws them, and neither file is one anybody reads
when a wording is decided on the phone. So the watch printed ``Foil %`` for four days after
the label table had decided ``On foil``, and ``Turn success`` in Garmin Connect for longer
than that — the same drift docs/copy exists to stop, on the one surface docs/copy could not
reach.

``docs/copy/watch.json`` is the inventory: every string the watch prints, where a rider
reads it, and — for a word that names a number — which glossary term it spells.
``web/tools/verify_glossary.py`` fails on a page word or a Connect field name that is not
one of its term's own spellings, and every deliberate divergence carries its `why` there
rather than an allow-list entry here.

HOW A PAGE REACHES A WORD. ``Words.mc`` declares one member per ``var`` inside
``module Words`` and ``Words.load()`` fills them from ``Rez.Strings`` — one
``WatchUi.loadResource`` per string, once, at page construction, never inside ``onUpdate``.

A MODULE rather than the file-scope globals these words used to be: Monkey C caps the
``globals`` module at 253 members, and on the CIQ 3.x devices (the fenix 5 Plus family) the
compiler enforces it. 105 words took the app to 286 and every fenix 5 Plus build failed.
The names are the ones the drawing code and the layout suite already used, with the module
in front of them, the way ``PageModel`` and ``AppSettings`` are already named.

Stdlib only, like every other generator in this repository.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
COPY = REPO / "docs" / "copy" / "watch.json"

BASE_XML = REPO / "garmin" / "resources" / "strings" / "strings.xml"
DEV_XML = REPO / "garmin" / "resources-dev" / "base" / "strings" / "strings.xml"
WORDS_MC = REPO / "garmin" / "source" / "ui" / "Words.mc"

#: The spaces a drawn word carries with it. They are part of the small string rather than of
#: the layout because the number beside it is drawn in a different font on a different
#: baseline run, so the gap cannot come from a text width. XML is no place to keep a
#: significant space, so the generator adds them and the JSON stays readable.
PADS = {"leading": (" ", ""), "trailing": ("", " "), "both": (" ", " ")}

XML_HEADER = """<!-- GENERATED from docs/copy/watch.json by garmin/tools/make_strings.py.
     EDIT THE JSON, then run the generator; `make web-verify` fails while this is stale.

     Every word the watch prints is in that file with the place a rider reads it and, for a
     word that names a number, the glossary term it spells. docs/copy/README.md, "The watch
     is inside the contract too". -->
"""

MC_HEADER = '''// GENERATED from docs/copy/watch.json by garmin/tools/make_strings.py — do not edit.
//
// One member per word the pages draw, and one `WatchUi.loadResource` each, filled by
// `Words.load()`. The names are the ones the drawing code and the layout suite already used
// when these were `const` literals, with `Words.` in front of them.
//
// WHY A MODULE and not the file-scope globals they were: Monkey C caps the `globals` module
// at 253 members and CIQ 3.x enforces it, so 105 words failed every fenix 5 Plus build at
// 286. A module costs the globals table one name.
//
// WHEN IT RUNS: `WingfoilApp.initialize()` and the first line of every View's
// `initialize()` — page construction, never `onUpdate`. The guard makes every call after
// the first free, which is what lets a view be built twice (the lock screen hands over to
// the start page) and what lets a unit test load the words without an app around it.
//
// WHAT IT COSTS: one String per entry below, held for the life of the app. They were
// already in the program as code constants; this moves them into the resource table and
// hands the app a reference to each.

import Toybox.Lang;
import Toybox.WatchUi;

'''


def load_copy() -> dict:
    return json.loads(COPY.read_text(encoding="utf-8"))


def padded(entry: dict) -> str:
    """The text as the glass draws it, `pad` included — what the lint and the docs read.

    The XML holds the bare word: a leading or trailing space inside an element is exactly
    the thing an XML tool is entitled to normalise away, and a word whose gap depends on
    that is a word that loses its gap on the day somebody reformats the file. `Words.load()`
    adds the spaces in Monkey C, where they are code.
    """
    before, after = PADS.get(entry.get("pad", ""), ("", ""))
    return before + entry["text"] + after


def surface(entry: dict) -> str:
    """Where this string is read — derived from the entry, never declared beside it.

    See docs/copy/watch.json's own `_readme`: a declared surface is one more thing that can
    disagree with the entry it sits on.
    """
    if entry.get("var"):
        return "page"
    if entry["id"].startswith("FitUnit"):
        return "unit"
    if entry["id"].startswith("Fit"):
        return "connectField"
    if entry["id"].startswith("AppName"):
        return "launcher"
    return "connectSettings"


def variables(entry: dict) -> list:
    """The globals one string is drawn through — one word may be drawn in several places."""
    names = entry.get("var") or []
    return [names] if isinstance(names, str) else list(names)


def escape(text: str) -> str:
    """XML text. `'` and `"` are left alone: they are legal in element content and the
    watch's own strings carry them (`Discard session?`, `Show cell labels. Off: …`)."""
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def comment(note) -> list:
    """An entry's `note`, wrapped in an XML comment at the file's indent."""
    lines = [note] if isinstance(note, str) else list(note)
    body = " ".join(lines).split()
    out, row = [], "    <!--"
    for word in body:
        if len(row) + 1 + len(word) > 96:
            out.append(row)
            row = "        " + word
        else:
            row += " " + word
    out.append(row + " -->")
    return out


def render_xml(entries: list) -> str:
    out = [XML_HEADER + "<strings>"]
    for entry in entries:
        if entry.get("note"):
            out.append("")
            out.extend(comment(entry["note"]))
        out.append('    <string id="%s">%s</string>'
                   % (entry["id"], escape(entry["text"])))
    out.append("</strings>")
    return "\n".join(out) + "\n"


def render_mc(entries: list) -> str:
    drawn = [e for e in entries if variables(e)]
    out = [MC_HEADER]
    out.append("module Words {")
    for entry in drawn:
        for name in variables(entry):
            out.append('    var %s as String = "";' % name)
    out.append("")
    out.append("    var _loaded as Boolean = false;")
    out.append("")
    out.append("    //! Fill every word above from the resource table, once.")
    out.append("    function load() as Void {")
    out.append("        if (_loaded) { return; }")
    out.append("        _loaded = true;")
    for entry in drawn:
        names = variables(entry)
        before, after = PADS.get(entry.get("pad", ""), ("", ""))
        read = "WatchUi.loadResource(Rez.Strings.%s) as String" % entry["id"]
        if before or after:
            read = '"%s" + (%s) + "%s"' % (before, read, after) if before and after \
                else ('"%s" + (%s)' % (before, read) if before
                      else '(%s) + "%s"' % (read, after))
        out.append("        %s = %s;" % (names[0], read))
        for name in names[1:]:
            out.append("        %s = %s;" % (name, names[0]))
    out.append("    }")
    out.append("}")
    return "\n".join(out) + "\n"


def problems(entries: list) -> list:
    """What the inventory itself has to be, before anything reads it."""
    found, seen = [], {}
    for entry in entries:
        where = entry.get("id", "?")
        for field in ("id", "text", "where"):
            if not entry.get(field):
                found.append("%s: no `%s`" % (where, field))
        if entry.get("id") in seen:
            found.append("%s: two entries share this id" % where)
        seen[entry.get("id")] = True
        if entry.get("pad") and entry["pad"] not in PADS:
            found.append("%s: `pad` is %r, not leading/trailing/both"
                         % (where, entry["pad"]))
        if entry.get("stream", "base") not in ("base", "dev"):
            found.append("%s: `stream` is %r, not base/dev" % (where, entry["stream"]))
        if entry.get("stream") == "dev" and variables(entry):
            found.append("%s: a dev-stream string cannot be a page word — a release build "
                         "would not have it to load" % where)
        for name in variables(entry):
            if name in seen and seen[name] is not True:
                found.append("%s: the global %s is already %s's" % (where, name, seen[name]))
            seen[name] = where
    return found


def files(copy: dict) -> list:
    entries = copy["strings"]
    base = [e for e in entries if e.get("stream", "base") == "base"]
    dev = [e for e in entries if e.get("stream") == "dev"]
    return [(BASE_XML, render_xml(base)),
            (DEV_XML, render_xml(dev)),
            (WORDS_MC, render_mc(base))]


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true",
                        help="exit 1 if a generated file is stale")
    args = parser.parse_args(argv)

    copy = load_copy()
    found = problems(copy["strings"])
    if found:
        print("docs/copy/watch.json does not hold together:", file=sys.stderr)
        for problem in found:
            print("  " + problem, file=sys.stderr)
        return 1

    written = files(copy)
    if args.check:
        stale = [path for path, text in written
                 if not path.exists() or path.read_text(encoding="utf-8") != text]
        if stale:
            for path in stale:
                print("stale, run `python3 garmin/tools/make_strings.py`: %s"
                      % path.relative_to(REPO), file=sys.stderr)
            return 1
        counts = {}
        for entry in copy["strings"]:
            counts[surface(entry)] = counts.get(surface(entry), 0) + 1
        print("watch strings: %d, generated from docs/copy/watch.json (%s)"
              % (len(copy["strings"]),
                 ", ".join("%d %s" % (n, k) for k, n in sorted(counts.items()))))
        return 0

    for path, text in written:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        print("wrote %s" % path.relative_to(REPO))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
