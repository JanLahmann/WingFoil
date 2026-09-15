#!/usr/bin/env python3
"""The getting-started guide has one source; this writes both copies of it.

    python3 web/tools/make_start.py            # write both outputs
    python3 web/tools/make_start.py --check    # exit 1 if either is stale

Source: ``docs/guide/getting-started.json`` — the framing, the routes in order with their
channels and their steps, the two extras, the line that names the web page, the two
Settings sentences, and the web-only troubleshooting and report lists.

Outputs:

1. ``ios/WingFoilKit/Sources/WingFoilKit/Help/GettingStartedGuide.swift`` — static data in
   the kit, the way ``IcuSetupGuide`` is. ``HelpCatalog``'s Getting started topic takes its
   body and its ``items:`` from it, and Settings reads the two sentences from it, so a
   wording is written in one file and rendered in three places.
2. The block of ``web/start/index.html`` between ``<!-- guide:begin -->`` and
   ``<!-- guide:end -->`` — the route cards, the troubleshooting list and the report
   checklist, in the page's own markup (``article.panel.piece`` with an ``ol.steps-flow``
   inside, ``dl.terms`` for the two lists). The head, the hero, the hand-written sections
   around the block and the footer are not touched.

It also enforces the word budgets ``HelpBudgetTests`` enforces on the Swift side — 30 words
for a summary, a step, a troubleshooting answer or a report line, 45 for the framing — so
an over-long sentence fails here rather than in a Swift test nobody ran yet.

Stdlib only, on purpose: it runs with plain ``python3`` beside ``verify_links.py``, which
calls it so that touching the page without the source (or the source without the
generator) is caught by the check the site is already verified with.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

WEB = Path(__file__).resolve().parents[1]
REPO = WEB.parent

SOURCE = REPO / "docs" / "guide" / "getting-started.json"
SWIFT_OUT = (REPO / "ios" / "WingFoilKit" / "Sources" / "WingFoilKit" / "Help"
             / "GettingStartedGuide.swift")
PAGE = WEB / "start" / "index.html"

BEGIN = "<!-- guide:begin -->"
END = "<!-- guide:end -->"

SITE = "cleanjibe.org"

SUMMARY_BUDGET = 30
STEP_BUDGET = 30
FRAMING_BUDGET = 45

# A · B · C … in reading order, the way the page has always lettered its routes.
LETTERS = "ABCDEFGH"


# --------------------------------------------------------------------------- budgets

def words(text: str) -> int:
    """The same count ``HelpBudgetTests.words`` makes: whitespace tokens, ``**`` dropped."""
    return len(text.replace("**", "").split())


def budget(problems: list[str], where: str, text: str, limit: int) -> None:
    n = words(text)
    if n > limit:
        problems.append(f"{where}: {n} words, budget {limit} — {text[:60]}…")


def check_budgets(doc: dict) -> list[str]:
    problems: list[str] = []
    budget(problems, "framing", doc["framing"], FRAMING_BUDGET)
    for entry in doc["routes"] + doc["extras"]:
        where = entry["id"]
        budget(problems, f"{where}.summary", entry["summary"], SUMMARY_BUDGET)
        for i, step in enumerate(entry["steps"], 1):
            budget(problems, f"{where}.step {i}", step["detail"], STEP_BUDGET)
    for key in ("intervalsIcu", "strava"):
        budget(problems, f"settings.{key}", doc["settings"][key], SUMMARY_BUDGET)
    for group in ("troubleshooting", "report"):
        for entry in doc[group]["entries"]:
            budget(problems, f"{group}: {entry['term']}", entry["detail"], SUMMARY_BUDGET)

    ids = [e["id"] for e in doc["routes"] + doc["extras"]] + [doc["webLine"]["id"]]
    if len(ids) != len(set(ids)):
        problems.append(f"duplicate ids: {ids}")
    return problems


# ----------------------------------------------------------------------------- Swift

def swift_channel(channels: list[str]) -> str:
    """The **lowest** channel that has the door — the one `HelpTopic.channel` wants."""
    order = ["release", "beta", "dev"]
    return min(channels, key=order.index)


def swift_literal(text: str, first_col: int, cont_indent: int, width: int = 96) -> str:
    """One Swift expression: a plain literal, or ``"a " + "b"`` wrapped the house way.

    ``first_col`` is the column the opening quote sits at; ``cont_indent`` is where the
    ``+`` lines under it start — the label's own indent plus four, as every hand-written
    string in the kit is laid out.

    ``{site}`` becomes a ``\\(Branding.site)`` interpolation, which has to survive wrapping
    as one token, so the substitution happens on whole words before the split.
    """
    pad = " " * cont_indent
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    escaped = escaped.replace("{site}", "\\(Branding.site)")

    if first_col + len(escaped) + 2 <= width:
        return f'"{escaped}"'

    lines: list[str] = []
    current = ""
    room = width - cont_indent - 6          # `+ "` … `"` on a continuation line
    # Keep the trailing space on every chunk but the last, so the pieces concatenate back
    # into exactly the source string.
    for token in re.findall(r"\S+\s*", escaped):
        limit = width - first_col - 3 if not lines else room
        if current and len(current) + len(token.rstrip()) > limit:
            lines.append(current)
            current = token
        else:
            current += token
    if current:
        lines.append(current)

    parts = []
    for i, line in enumerate(lines):
        body = line if i == len(lines) - 1 else line.rstrip() + " "
        parts.append(f'"{body}"' if i == 0 else f'{pad}+ "{body}"')
    return "\n".join(parts)


def swift_steps(steps: list[dict], indent: int) -> str:
    pad = " " * indent
    out = []
    for i, step in enumerate(steps, 1):
        out.append(f"{pad}.init(number: {i},")
        out.append(f"{pad}      title: "
                   f"{swift_literal(step['title'], indent + 13, indent + 10)},")
        out.append(f"{pad}      detail: "
                   f"{swift_literal(step['detail'], indent + 14, indent + 10)}),")
    return "\n".join(out)


def swift_entry(entry: dict, indent: int) -> str:
    pad = " " * indent
    lines = [
        f"{pad}GettingStartedRoute(",
        f'{pad}    id: "{entry["id"]}",',
        f"{pad}    title: {swift_literal(entry['title'], indent + 11, indent + 8)},",
        f"{pad}    channel: .{swift_channel(entry['channels'])},",
        f"{pad}    summary: {swift_literal(entry['summary'], indent + 13, indent + 8)},",
        f"{pad}    steps: [",
        swift_steps(entry["steps"], indent + 8),
        f"{pad}    ]),",
    ]
    return "\n".join(lines)


SWIFT_HEADER = '''// GENERATED by web/tools/make_start.py from docs/guide/getting-started.json.
// Do not edit by hand: regenerate, and `make_start.py --check` fails while this file and
// the source disagree.

import Foundation

/// One numbered step of one route, shown on cleanjibe.org/start.
///
/// The app does not render these — it shows a route's title and summary and sends the
/// reader to the web for the rest — but they live here anyway, because the point of the
/// generator is that one file is the guide and both surfaces are cut from it.
public struct GettingStartedStep: Sendable, Equatable, Identifiable {
    public let number: Int
    public let title: String
    public let detail: String

    public var id: Int { number }

    public init(number: Int, title: String, detail: String) {
        self.number = number
        self.title = title
        self.detail = detail
    }
}

/// One way in — a watch, a file, a cloud account — or one of the two notes that close the
/// guide (the dry run, and where to send what you found).
public struct GettingStartedRoute: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    /// **The lowest channel that has this door** (docs/channels.md), exactly as
    /// `HelpTopic.channel` means it: the two Apple routes are `.beta`, so an App Store
    /// build never names them and reaches them through the topic's `related` instead.
    public let channel: HelpChannel
    /// The one or two sentences the app shows under the route's title.
    public let summary: String
    /// The numbered steps the web page shows under that summary.
    public let steps: [GettingStartedStep]

    public init(id: String, title: String, channel: HelpChannel,
                summary: String, steps: [GettingStartedStep]) {
        self.id = id
        self.title = title
        self.channel = channel
        self.summary = summary
        self.steps = steps
    }
}

/// **The getting-started guide, from the one source both platforms read.**
///
/// The app used to say "the same guide, on the web" about a page that had been written
/// separately and said different things (Jan, 15 September 2026). It is the same guide
/// now: `docs/guide/getting-started.json` holds the framing, the routes, the steps and the
/// two Settings sentences, and `web/tools/make_start.py` writes this file and the block of
/// `web/start/index.html` from it. `--check` fails while either is stale, and
/// `GettingStartedGuideTests` fails if the help topic stops matching this data.
public enum GettingStartedGuide {
'''

SWIFT_FOOTER = '''
    /// The routes and notes a build on `channel` may name, as the help topic's items —
    /// title as the term, summary as the detail — with the web page named last.
    ///
    /// **The channel comes from the app** (`HelpCatalog.topic(_:channel:)`, dev 65). The
    /// catalogue declares the topic with `.release`, because a static array cannot ask
    /// which build is reading it, and the lookup rebuilds the items for the channel the
    /// app hands in. So the two Apple routes are named by no release build, and are items
    /// on the two channels that have them; either way they are also topics on `related`,
    /// which `relatedTopics(of:channel:)` filters the same way.
    public static func items(for channel: HelpChannel) -> [HelpTopic.Item] {
        let ways = (routes + notes)
            .filter { channel.has($0.channel) }
            .map { HelpTopic.Item(term: $0.title, detail: $0.summary) }
        return ways + [onTheWeb]
    }
}
'''


def render_swift(doc: dict) -> str:
    out = [SWIFT_HEADER]

    out.append("    /// The one sentence that opens both the topic and the page: what the")
    out.append("    /// test actually is. First on purpose, on both surfaces.")
    out.append(f"    public static let framing =\n        {swift_literal(doc['framing'], 8, 12)}\n")

    out.append("    /// The topic's own index line.")
    out.append("    public static let topicSummary =\n"
               f"        {swift_literal(doc['app']['topicSummary'], 8, 12)}\n")

    out.append("    /// The ways in, in the order the app and the page list them.")
    out.append("    public static let routes: [GettingStartedRoute] = [")
    out.append("\n".join(swift_entry(r, 8) for r in doc["routes"]))
    out.append("    ]\n")

    out.append("    /// The two notes that close the guide: the dry run, and the report.")
    out.append("    public static let notes: [GettingStartedRoute] = [")
    out.append("\n".join(swift_entry(e, 8) for e in doc["extras"]))
    out.append("    ]\n")

    web = doc["webLine"]
    out.append("    /// The last item of the topic, and the only one the web page does not")
    out.append("    /// render — a page does not send you to itself.")
    out.append("    public static let onTheWeb = HelpTopic.Item(")
    out.append(f"        term: {swift_literal(web['title'], 14, 12)},")
    out.append(f"        detail: {swift_literal(web['summary'], 16, 12)})\n")

    out.append("    /// **Settings → intervals.icu**, the caption above the key field: why the")
    out.append("    /// detour exists at all, in one breath. The longer version, for the setup")
    out.append("    /// card and the help topic, is `IcuSetupGuide.rationale`.")
    out.append("    public static let settingsIcu =\n"
               f"        {swift_literal(doc['settings']['intervalsIcu'], 8, 12)}\n")

    out.append("    /// **Settings → Strava**, the caption above the connect button: what this")
    out.append("    /// account is for, and what it costs. The footer under the button says the")
    out.append("    /// rest — what is read, what is never written, and the connection cap.")
    out.append("    public static let settingsStrava =\n"
               f"        {swift_literal(doc['settings']['strava'], 8, 12)}")

    out.append(SWIFT_FOOTER)
    return "\n".join(out)


# ------------------------------------------------------------------------------- HTML

def html_text(text: str) -> str:
    """Source prose as the page's own typography: entities, curly quotes, em dashes kept."""
    out = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    out = out.replace("{site}", SITE)
    # `**bold**` and `*italic*`, the same markdown the help sheet renders.
    out = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"(?<![\w*])\*(.+?)\*(?![\w*])", r"<em>\1</em>", out)
    # Straight pairs to typographic ones, then the apostrophes that are left.
    out = re.sub(r'"([^"]*)"', r"&ldquo;\1&rdquo;", out)
    out = out.replace("'", "&rsquo;")
    return out


def html_card(entry: dict, letter: str | None) -> list[str]:
    """One card: the title, the status, and the summary as the handle on a disclosure.

    THE STEPS ARE BEHIND A FOLD, since 15 September 2026. A rider takes exactly one route;
    the other four are somebody else's instructions, and flat on the page they made /start/
    a 3500-word document whose own ask — read the verdicts against your memory — sat at the
    bottom of it. The summary is what a reader scans to find their own route, so the summary
    is what stays visible: `<summary>` carries it, and the `.what` class it always wore.
    Nothing in docs/guide/getting-started.json changes for this, and the app's Help topic,
    which shows title and summary and no steps at all, is untouched.
    """
    beta = "release" not in entry["channels"]
    head = html_text(entry["title"])
    if letter:
        head = f"Route {letter} &middot; {head}"
    if beta:
        head += '<span class="tag beta">beta</span>'
    lines = [
        f'    <article class="panel piece" id="guide-{entry["id"]}">',
        '      <div class="piece-head">',
        f"        <h3>{head}</h3>",
        f'        <span class="status">{html_text(entry["status"])}</span>',
        "      </div>",
        "      <details>",
        f'        <summary class="what">{html_text(entry["summary"])}</summary>',
        '        <ol class="steps-flow">',
    ]
    for step in entry["steps"]:
        lines += [
            "          <li>",
            f"            <h3>{html_text(step['title'])}</h3>",
            f"            <p>{html_text(step['detail'])}</p>",
            "          </li>",
        ]
    lines += ["        </ol>", "      </details>", "    </article>", ""]
    return lines


def html_terms(entries: list[dict]) -> list[str]:
    lines = ['    <dl class="terms">']
    for entry in entries:
        lines += [
            '      <div class="term">',
            f"        <dt>{html_text(entry['term'])}</dt>",
            f"        <dd>{html_text(entry['detail'])}</dd>",
            "      </div>",
        ]
    lines += ["    </dl>"]
    return lines


def render_html(doc: dict) -> str:
    sections = doc["sections"]
    lines = [
        BEGIN,
        "  <!-- GENERATED by web/tools/make_start.py from docs/guide/getting-started.json —",
        "       the same file the app's Getting started topic is built from, which is what",
        '       "the same guide, with every step, on the web" means. Do not edit between the',
        "       markers: regenerate, and `make_start.py --check` fails while it is stale.",
        "       The head, the hero, the hand-written sections around this block and the",
        "       footer are the page's own. -->",
        "",
        '  <section class="home-section" id="routes">',
        f'    <h2>{html_text(sections["routes"]["title"])}</h2>',
        f'    <p class="section-lede">{html_text(doc["framing"])}</p>',
        f'    <p class="section-lede">{html_text(sections["routes"]["lede"])}</p>',
        '    <p class="beta-legend">',
        '      <span class="tag beta">beta</span> '
        f'{html_text(sections["routes"]["betaLegend"])}',
        "    </p>",
        "",
    ]
    for letter, route in zip(LETTERS, doc["routes"]):
        lines += html_card(route, letter)
    for extra in doc["extras"]:
        lines += html_card(extra, None)
    lines += ["  </section>", ""]

    # Seven answers to seven things that go wrong, behind one fold. A reader who is stuck
    # opens it; a reader who is not was reading past 200 words of somebody else's problem to
    # reach the page's own ask. The section's own lede is the handle, so the words are still
    # the JSON's and still say what the list is for.
    lines += [
        '  <section class="home-section" id="stuck">',
        f'    <h2>{html_text(sections["troubleshooting"]["title"])}</h2>',
        "    <details>",
        f'      <summary class="section-lede">'
        f'{html_text(sections["troubleshooting"]["lede"])}</summary>',
    ]
    lines += ["  " + line for line in html_terms(doc["troubleshooting"]["entries"])]
    lines += ["    </details>", "  </section>", ""]

    lines += [
        '  <section class="home-section" id="report">',
        f'    <h2>{html_text(sections["report"]["title"])}</h2>',
        f'    <p class="section-lede">{html_text(sections["report"]["lede"])}</p>',
    ]
    lines += html_terms(doc["report"]["entries"])
    lines += ["  </section>", "", END]
    return "\n".join(lines)


def splice(page: str, block: str) -> str:
    start = page.find(BEGIN)
    end = page.find(END)
    if start < 0 or end < 0:
        raise SystemExit(f"{PAGE}: the {BEGIN} / {END} markers are not both there")
    return page[:start] + block + page[end + len(END):]


# ------------------------------------------------------------------------------- main

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true",
                    help="write nothing; exit 1 if either output is stale")
    args = ap.parse_args(argv)

    doc = json.loads(SOURCE.read_text(encoding="utf-8"))

    problems = check_budgets(doc)
    if problems:
        print(f"{SOURCE.relative_to(REPO)}: over budget", file=sys.stderr)
        for line in problems:
            print(f"  {line}", file=sys.stderr)
        return 1

    swift = render_swift(doc)
    page = splice(PAGE.read_text(encoding="utf-8"), render_html(doc))

    stale = []
    if not SWIFT_OUT.exists() or SWIFT_OUT.read_text(encoding="utf-8") != swift:
        stale.append(SWIFT_OUT)
    if PAGE.read_text(encoding="utf-8") != page:
        stale.append(PAGE)

    if args.check:
        if stale:
            print("stale, run `python3 web/tools/make_start.py`:", file=sys.stderr)
            for path in stale:
                print(f"  {path.relative_to(REPO)}", file=sys.stderr)
            return 1
        print("getting-started guide: both outputs match docs/guide/getting-started.json")
        return 0

    SWIFT_OUT.write_text(swift, encoding="utf-8")
    PAGE.write_text(page, encoding="utf-8")
    routes = len(doc["routes"])
    notes = len(doc["extras"])
    print(f"wrote {SWIFT_OUT.relative_to(REPO)} and {PAGE.relative_to(REPO)} "
          f"({routes} routes, {notes} notes, "
          f"{len(doc['troubleshooting']['entries'])} troubleshooting, "
          f"{len(doc['report']['entries'])} report lines)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
