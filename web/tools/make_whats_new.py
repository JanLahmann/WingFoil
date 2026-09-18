#!/usr/bin/env python3
"""The release notes have one source; this writes the copies of it.

    python3 web/tools/make_whats_new.py            # write both outputs
    python3 web/tools/make_whats_new.py --check    # exit 1 if either is stale

Source: ``docs/copy/whats-new.json`` — one entry per shipped build, newest first:

    {"version": "0.15.0", "build": 53, "channel": "beta", "date": "2026-09-14",
     "title": "The beta channel, with its own icon", "lines": ["…", "…"]}

``build`` is the TestFlight build number of the iPhone app, or **null** for the Garmin
watch app, which ships as Connect IQ versions and has no build number. That one field is
what decides which of the two products an entry is about, on every surface.

``channel`` is the channel the build went to (docs/channels.md). It is what the app filters
on — a release build shows release entries, a beta build shows beta and release, the dev
build shows everything — and it is why the website prints no ``dev`` entry at all: those
builds go to a handful of hand-picked testers and naming them publicly would promise a door
nobody may have.

Outputs:

1. ``ios/WingFoilKit/Sources/WingFoilKit/Help/WhatsNew.swift`` — static data in the kit, the
   way ``GettingStartedGuide`` is. The app's *What's new* screen (Help, and Settings →
   About) renders it, filtered by the channel the app hands in.
2. The block of ``web/whats-new/index.html`` between ``<!-- whats-new:begin -->`` and
   ``<!-- whats-new:end -->`` — the release cards in the page's own markup
   (``article.panel.piece``), the three newest open and everything older inside the one
   ``<details>`` fold the page already had. The head, the hero, the section lede, the
   closing note and the footer are the page's own.

Third renderer, outside this file: ``ios/tools/testflight_publish.py`` reads the same JSON
for the *What to Test* text of the build it is attaching.

**Dates are allowed in these sentences**, and nowhere else in the app: a release note that
does not say when it shipped is not a release note. They are written *by this generator*
from the source's ISO dates rather than typed, which is the condition
``docs/copy/check_voice.py`` puts on a dated surface (its ``dated`` Target flag, carried by
/whats-new/ and by the generated Swift file).

The word rules of docs/voice.md register 1 are enforced here, on the source, so a long or
dashed sentence fails at the generator rather than in a lint run on generated output: a
title is at most 8 words, a line at most 20, and no line carries an em-dash, a semicolon or
a parenthesis.

Stdlib only, on purpose: it runs with plain ``python3`` beside ``make_start.py``, which
``verify_links.py`` calls the same way.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

WEB = Path(__file__).resolve().parents[1]
REPO = WEB.parent

SOURCE = REPO / "docs" / "copy" / "whats-new.json"
SWIFT_OUT = (REPO / "ios" / "WingFoilKit" / "Sources" / "WingFoilKit" / "Help"
             / "WhatsNew.swift")
PAGE = WEB / "whats-new" / "index.html"

BEGIN = "<!-- whats-new:begin -->"
END = "<!-- whats-new:end -->"

#: The three newest cards stay open and everything older goes in the fold. Nine cards of
#: equal weight made the newest look like an archive entry (the page's own note, 15 Sep).
OPEN_CARDS = 3

TITLE_BUDGET = 8
LINE_BUDGET = 20

CHANNELS = ("release", "beta", "dev")
#: What the website may print. `dev` builds go to a handful of hand-picked testers, so a
#: public card about one would name a door nobody else can have (docs/channels.md).
WEB_CHANNELS = ("release", "beta")

MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August",
          "September", "October", "November", "December"]

ISO = re.compile(r"^(\d{4})-(\d{2})-(\d{2})$")


# --------------------------------------------------------------------------- the source

def words(text: str) -> int:
    """The same count ``HelpBudgetTests.words`` makes: whitespace tokens, ``**`` dropped."""
    return len(text.replace("**", "").split())


def day(iso: str) -> str:
    """``2026-09-14`` → ``14 September 2026``, the spelling the page already uses."""
    m = ISO.match(iso)
    if not m:
        raise SystemExit(f"{SOURCE}: {iso!r} is not an ISO date (yyyy-mm-dd)")
    year, month, date = m.groups()
    return f"{int(date)} {MONTHS[int(month) - 1]} {year}"


def check(entries: list[dict]) -> list[str]:
    """Everything a wrong entry could be, said before either output is written."""
    problems: list[str] = []
    seen: set[tuple] = set()
    order: list[tuple] = []
    for entry in entries:
        where = label(entry)
        for key in ("version", "channel", "date", "title", "lines"):
            if key not in entry:
                problems.append(f"{where}: no {key}")
        if "build" not in entry:
            problems.append(f"{where}: no build (an integer, or null for the watch app)")
        if entry.get("channel") not in CHANNELS:
            problems.append(f"{where}: channel {entry.get('channel')!r} is not one of "
                            + ", ".join(CHANNELS))
        if not ISO.match(str(entry.get("date", ""))):
            problems.append(f"{where}: date {entry.get('date')!r} is not yyyy-mm-dd")
        build = entry.get("build")
        if build is not None and not isinstance(build, int):
            problems.append(f"{where}: build {build!r} is not an integer or null")

        title = entry.get("title", "")
        if words(title) > TITLE_BUDGET:
            problems.append(f"{where}: title is {words(title)} words, budget {TITLE_BUDGET}")
        for line in entry.get("lines", []):
            problems += line_problems(where, line)
        if not entry.get("lines"):
            problems.append(f"{where}: no lines")

        key = (entry.get("channel"), entry.get("version"), entry.get("build"))
        if key in seen:
            problems.append(f"{where}: declared twice")
        seen.add(key)
        order.append((entry.get("date", ""), entry.get("build")))

    # Newest first, the way the page, the app and TestFlight all read it. Two products
    # share the list and number differently, so the *dates* carry the order and the build
    # numbers are only checked against each other.
    dates = [d for d, _ in order]
    if dates != sorted(dates, reverse=True):
        problems.append("the entries are not newest first")
    builds = [b for _, b in order if b is not None]
    if builds != sorted(builds, reverse=True):
        problems.append("the build numbers do not run downwards")
    return problems


def line_problems(where: str, line: str) -> list[str]:
    """docs/voice.md register 1, the rules a machine can hold, on one release-note line."""
    out = []
    n = words(line)
    if n > LINE_BUDGET:
        out.append(f"{where}: {n} words, budget {LINE_BUDGET} — {line[:60]}…")
    if "—" in line or "–" in line:
        out.append(f"{where}: a dash is a second sentence hiding — {line[:60]}…")
    if ";" in line:
        out.append(f"{where}: a semicolon — {line[:60]}…")
    if "(" in line and ")" in line:
        out.append(f"{where}: a parenthesis — {line[:60]}…")
    return out


def label(entry: dict) -> str:
    build = entry.get("build")
    return f"build {build}" if build is not None else f"watch {entry.get('version')}"


def heading(entry: dict) -> str:
    """What the card and the app's row are titled: the product, then its number."""
    build = entry.get("build")
    if build is None:
        return f"Garmin watch app · {entry['version']}"
    return f"iPhone · build {build}"


# ----------------------------------------------------------------------------- Swift

def swift_string(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


SWIFT_HEADER = '''// GENERATED by web/tools/make_whats_new.py from docs/copy/whats-new.json.
// Do not edit by hand: regenerate, and `make_whats_new.py --check` fails while this file
// and the source disagree.

import Foundation

/// One shipped build, and what it changed.
public struct WhatsNewEntry: Sendable, Equatable, Identifiable {
    /// The app's marketing version, or the watch app's Connect IQ version.
    public let version: String
    /// The TestFlight build number, or **nil** for the Garmin watch app, which ships as
    /// Connect IQ versions and has no build number. The one field that says which of the
    /// two products an entry is about.
    public let build: Int?
    /// **The channel this build went to** (docs/channels.md). A release build shows the
    /// release entries, a beta build shows beta and release, the dev build shows the lot —
    /// `WhatsNew.entries(for:)` is that filter, and the app hands its own channel in.
    public let channel: HelpChannel
    /// ISO 8601, `yyyy-MM-dd`. Sorted and tested on; never shown.
    public let date: String
    /// The same day in the words a rider reads, written by the generator so that no date
    /// on any rider-facing surface was ever typed by hand.
    public let dateText: String
    /// What the build was about, in at most eight words.
    public let title: String
    /// One thought per line, register 1 of docs/voice.md.
    public let lines: [String]

    public var id: String { "\\(channel.rawValue)-\\(version)-\\(build.map(String.init) ?? "")" }

    /// The row's title: the product and its number.
    public var heading: String {
        guard let build else { return "Garmin watch app · " + version }
        return "iPhone · build " + String(build)
    }

    public init(version: String, build: Int?, channel: HelpChannel, date: String,
                dateText: String, title: String, lines: [String]) {
        self.version = version
        self.build = build
        self.channel = channel
        self.date = date
        self.dateText = dateText
        self.title = title
        self.lines = lines
    }
}

/// **The release notes, from the one source all three surfaces read.**
///
/// They had three homes and no source until 18 September 2026: two hand-typed strings in
/// `ios/tools/testflight_publish.py`, a stack of hand-written cards on
/// `web/whats-new/index.html`, and nothing at all in the app. `docs/copy/whats-new.json` is
/// the source now; `web/tools/make_whats_new.py` writes this file and the cards, and
/// `testflight_publish.py` reads the newest entry of the channel it is publishing to.
/// `--check` fails while either output is stale.
///
/// **This is the app's one dated surface.** A release note that does not say when it
/// shipped is not a release note, and every date here is written by the generator rather
/// than typed, which is the condition `docs/copy/check_voice.py` puts on a dated target.
public enum WhatsNew {

    /// Every entry, newest first.
    public static let entries: [WhatsNewEntry] = ['''

SWIFT_FOOTER = '''    ]

    /// What a build on `channel` may read: its own entries and every channel below it.
    ///
    /// The release build never sees a beta or a dev note, for the reason docs/channels.md
    /// gives for every other channel-bound sentence: a note about a door this build does
    /// not have describes a screen the rider cannot reach.
    public static func entries(for channel: HelpChannel) -> [WhatsNewEntry] {
        Self.entries.filter { channel.has($0.channel) }
    }

    /// The newest entry of one channel exactly, which is what a TestFlight build's *What
    /// to Test* is: the notes for the build being attached, not for the one below it.
    public static func newest(ofExactly channel: HelpChannel) -> WhatsNewEntry? {
        Self.entries.first { $0.channel == channel }
    }
}
'''


def render_swift(entries: list[dict]) -> str:
    out = [SWIFT_HEADER]
    for entry in entries:
        build = entry["build"]
        out.append("        WhatsNewEntry(")
        out.append(f'            version: {swift_string(entry["version"])},')
        out.append(f"            build: {build if build is not None else 'nil'},")
        out.append(f'            channel: .{entry["channel"]},')
        out.append(f'            date: {swift_string(entry["date"])},')
        out.append(f'            dateText: {swift_string(day(entry["date"]))},')
        out.append(f'            title: {swift_string(entry["title"])},')
        out.append("            lines: [")
        for line in entry["lines"]:
            out.append(f"                {swift_string(line)},")
        out.append("            ]),")
    out.append(SWIFT_FOOTER)
    return "\n".join(out)


# ------------------------------------------------------------------------------- HTML

def html_text(text: str) -> str:
    """Source prose as the page's own typography, exactly as ``make_start.py`` does it."""
    out = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    out = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"(?<![\w*])\*(.+?)\*(?![\w*])", r"<em>\1</em>", out)
    out = re.sub(r'"([^"]*)"', r"&ldquo;\1&rdquo;", out)
    out = out.replace("'", "&rsquo;")
    return out.replace("→", "&rarr;")


def html_card(entry: dict, *, live: bool, indent: int) -> list[str]:
    pad = " " * indent
    head = html_text(heading(entry))
    if entry["channel"] == "beta":
        head += ' <span class="tag beta">beta</span>'
    status = day(entry["date"])
    if entry["build"] is not None:
        status += f" · {entry['version']}"
    title = entry["title"]
    if title[-1] not in ".!?":
        title += "."
    lines = [
        f'{pad}<article class="panel piece">',
        f'{pad}  <div class="piece-head">',
        f"{pad}    <h3>{head}</h3>",
        f'{pad}    <span class="status{" live" if live else ""}">{status}</span>',
        f"{pad}  </div>",
        f'{pad}  <p class="what">{html_text(title)}</p>',
        f"{pad}  <ul>",
    ]
    for line in entry["lines"]:
        lines.append(f"{pad}    <li>{html_text(line)}</li>")
    lines += [f"{pad}  </ul>", f"{pad}</article>", ""]
    return lines


def fold_summary(folded: list[dict]) -> str:
    """*Earlier builds: iPhone 49 back to 41, watch app 0.9.9* — the handle, from the data."""
    builds = [e["build"] for e in folded if e["build"] is not None]
    versions = [e["version"] for e in folded if e["build"] is None]
    parts = []
    if len(builds) == 1:
        parts.append(f"iPhone {builds[0]}")
    elif builds:
        parts.append(f"iPhone {max(builds)} back to {min(builds)}")
    if len(versions) == 1:
        parts.append(f"watch app {versions[0]}")
    elif versions:
        parts.append("watch app " + ", ".join(versions))
    return "Earlier builds: " + ", ".join(parts)


def render_html(entries: list[dict]) -> str:
    public = [e for e in entries if e["channel"] in WEB_CHANNELS]
    open_cards, folded = public[:OPEN_CARDS], public[OPEN_CARDS:]
    lines = [
        BEGIN,
        "    <!-- GENERATED by web/tools/make_whats_new.py from docs/copy/whats-new.json —",
        "         the same file the app's What's new screen and the TestFlight What to Test",
        "         text are written from. Do not edit between the markers: regenerate, and",
        "         `make_whats_new.py --check` fails while it is stale. The head, the hero,",
        "         the section lede above, the closing note below and the footer are the",
        "         page's own.",
        "",
        "         THE THREE NEWEST ARE OPEN AND THE REST ARE IN THE FOLD. Nine cards of equal",
        "         weight made the newest look like an archive entry, and freshness cannot be",
        "         shown by a stack. A dated note is never rewritten either: it says what was",
        "         true on its day, and a correction goes in brackets inside the card.",
        "",
        "         No `dev` card, ever: those builds go to a handful of hand-picked testers,",
        "         so a public card about one would name a door nobody else can have",
        "         (docs/channels.md). -->",
        "",
    ]
    for index, entry in enumerate(open_cards):
        lines += html_card(entry, live=index == 0, indent=4)
    if folded:
        lines += [
            "    <details>",
            f"      <summary>{html_text(fold_summary(folded))}</summary>",
        ]
        for entry in folded:
            lines += html_card(entry, live=False, indent=6)
        lines += ["    </details>", ""]
    lines.append("    " + END)
    return "\n".join(lines)


def splice(page: str, block: str) -> str:
    start = page.find(BEGIN)
    end = page.find(END)
    if start < 0 or end < 0:
        raise SystemExit(f"{PAGE}: the {BEGIN} / {END} markers are not both there")
    return page[:start] + block.lstrip() + page[end + len(END):]


# ------------------------------------------------------------------------------- main

def load() -> list[dict]:
    return json.loads(SOURCE.read_text(encoding="utf-8"))["entries"]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true",
                    help="write nothing; exit 1 if either output is stale")
    args = ap.parse_args(argv)

    entries = load()

    problems = check(entries)
    if problems:
        print(f"{SOURCE.relative_to(REPO)}: off the voice or malformed", file=sys.stderr)
        for line in problems:
            print(f"  {line}", file=sys.stderr)
        return 1

    swift = render_swift(entries)
    page = splice(PAGE.read_text(encoding="utf-8"), render_html(entries))

    stale = []
    if not SWIFT_OUT.exists() or SWIFT_OUT.read_text(encoding="utf-8") != swift:
        stale.append(SWIFT_OUT)
    if PAGE.read_text(encoding="utf-8") != page:
        stale.append(PAGE)

    if args.check:
        if stale:
            print("stale, run `python3 web/tools/make_whats_new.py`:", file=sys.stderr)
            for path in stale:
                print(f"  {path.relative_to(REPO)}", file=sys.stderr)
            return 1
        print("release notes: both outputs match docs/copy/whats-new.json")
        return 0

    SWIFT_OUT.write_text(swift, encoding="utf-8")
    PAGE.write_text(page, encoding="utf-8")
    public = sum(1 for e in entries if e["channel"] in WEB_CHANNELS)
    print(f"wrote {SWIFT_OUT.relative_to(REPO)} and {PAGE.relative_to(REPO)} "
          f"({len(entries)} entries, {public} of them public, "
          f"{OPEN_CARDS} open cards)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
