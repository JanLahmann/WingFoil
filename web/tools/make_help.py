#!/usr/bin/env python3
"""The help page is the app's help catalogue; this renders it.

    python3 web/tools/make_help.py            # write the block into web/help/index.html
    python3 web/tools/make_help.py --check    # exit 1 if the page is stale

Source: ``docs/copy/help.json``, written out of ``HelpCatalog`` by the kit's
``HelpExportTests`` (``COPY_WRITE=1 swift test --filter HelpExportTests``), plus
``docs/copy/glossary.json`` for the eleven metric one-liners that open the page.

Jan, 19 September 2026: *"one product, three shells"* — iOS is the reference and the web is
the port. ``/learn/`` was the counter-example: eleven glossary lines and four questions,
written in the website's own pass, about an app whose own Help had been answering the same
questions for a month in different words. So the page stopped being written. It is
rendered, from the same catalogue the phone renders, and ``/learn/`` is a redirect to
``/help/#numbers``.

WHAT IT RENDERS, into the block between ``<!-- help:begin -->`` and ``<!-- help:end -->``:

1. **What the numbers mean** — the eleven ``glossary.json`` entries as a definition list
   marked ``data-copy="glossary"``, which is the pin ``web/tools/verify_copy.py`` holds. It
   was ``/learn/``'s job and it is the one thing on this page that is not a help topic: a
   rider who followed a metric's name here wants the one-liner, not a page.
2. **The ten sections, as folds.** One ``<details>`` per ``HelpSection``, in the
   catalogue's order, each holding its topics as articles: the summary, the body, the items
   as a definition list, and the "read next" links. Closed, because forty pages of
   reference is a book and the ten handles are its contents — and because
   ``web/tools/verify_unique.py`` counts a page the way a reader meets it, which is what
   lets a reference work live on a site with word budgets.

**CHANNEL-AWARE, the same way the release notes are.** Every topic and every item carries
the channels that may read it. A row the release has is printed plainly; a row only the
beta has is printed with the ``beta`` pill and the one legend sentence this site uses for
it; a row only the dev build has is **not printed at all**, because a public page that
names a dev door promises a stranger a door nobody can have (docs/channels.md). A "read
next" link to a topic that was not printed is dropped rather than left dangling.

Stdlib only, on purpose: it runs with plain ``python3`` beside ``make_start.py`` and
``make_whats_new.py``, and ``verify_links.py`` calls all three the same way.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

WEB = Path(__file__).resolve().parents[1]
REPO = WEB.parent

HELP = REPO / "docs" / "copy" / "help.json"
GLOSSARY = REPO / "docs" / "copy" / "glossary.json"
PAGE = WEB / "help" / "index.html"

BEGIN = "<!-- help:begin -->"
END = "<!-- help:end -->"

#: What a public page may print. `dev` topics go to a handful of hand-picked testers.
WEB_CHANNELS = ("release", "beta")

#: The legend under a `beta` pill, once per page that draws one. The same sentence the front
#: door and the routes carry; `web/tools/verify_unique.py` has it in its ALLOW list with the
#: reason, because a key that is on the next page instead of this one is not a key.
BETA_LEGEND = ("in the public beta today, not yet in the App Store\n      release.")


def html_text(text: str) -> str:
    """Source prose as the page's own typography, exactly as ``make_start.py`` does it."""
    out = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    out = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"(?<![\w*])\*(.+?)\*(?![\w*])", r"<em>\1</em>", out)
    out = re.sub(r'"([^"]*)"', r"&ldquo;\1&rdquo;", out)
    out = out.replace("'", "&rsquo;")
    return out.replace("→", "&rarr;")


def public(row: dict) -> bool:
    """A topic or an item this site may print at all."""
    return any(channel in WEB_CHANNELS for channel in row["channels"])


def pill(row: dict) -> str:
    """The `beta` pill, on anything the App Store release does not have."""
    return "" if "release" in row["channels"] else '<span class="tag beta">beta</span>'


# --------------------------------------------------------------------------- the glossary

def render_glossary(entries: list[dict]) -> list[str]:
    """The eleven one-liners, in the JSON's order — the pin verify_copy.py holds.

    ``/learn/`` carried a twelfth of its own, *Pump & takeoff effort*, marked
    ``glossary-extra``. It is gone from here on purpose rather than forgotten: the pump
    strokes have a help topic of their own three folds down, which is a page rather than a
    line, and rule 10 of docs/voice.md asks only that the fact keep a home.
    """
    lines = [
        '  <section class="home-section" id="numbers">',
        "    <h2>What the numbers mean</h2>",
        '    <p class="section-lede">',
        "      Eleven words, one line each. The app prints the same line beside the same",
        "      number. Tap a word&rsquo;s page below for the whole of it.",
        "    </p>",
        '    <dl class="terms" data-copy="glossary">',
    ]
    for entry in entries:
        lines += [
            '      <div class="term">',
            f"        <dt>{html_text(entry['term'])}</dt>",
            f"        <dd>{html_text(entry['line'])}</dd>",
            "      </div>",
        ]
    lines += ["    </dl>", "  </section>", ""]
    return lines


# ----------------------------------------------------------------------------- the topics

def render_topic(topic: dict, printed: set[str], titles: dict[str, str],
                 indent: int) -> list[str]:
    pad = " " * indent
    lines = [
        f'{pad}<article class="panel piece" id="help-{topic["id"]}">',
        f'{pad}  <div class="piece-head">',
        f'{pad}    <h3>{html_text(topic["title"])}{pill(topic)}</h3>',
        f"{pad}  </div>",
        f'{pad}  <p class="what">{html_text(topic["summary"])}</p>',
    ]
    for paragraph in topic["body"]:
        lines.append(f"{pad}  <p>{html_text(paragraph)}</p>")

    items = [item for item in topic["items"] if public(item)]
    if items:
        lines.append(f'{pad}  <dl class="terms">')
        for item in items:
            lines += [
                f'{pad}    <div class="term">',
                f"{pad}      <dt>{html_text(item['term'])}{pill(item)}</dt>",
                f"{pad}      <dd>{html_text(item['detail'])}</dd>",
                f"{pad}    </div>",
            ]
        lines.append(f"{pad}  </dl>")

    # A "read next" onto a topic this page did not draw would be a link into nothing, so
    # the dev-only ones fall out here rather than being exported differently.
    related = [r for r in topic["related"] if r in printed]
    if related:
        offer = " · ".join(f'<a href="#help-{r}">{html_text(titles[r])}</a>'
                           for r in related)
        # `data-copy="related"` marks it as NAVIGATION rather than prose. It is a row of
        # topic titles joined by middle dots, so read as a sentence it is 50 words long and
        # says nothing; docs/copy/check_voice.py strips the token the way it strips a
        # generated span, and web/tools/verify_copy.py's `aside` rule is the same idea one
        # file over.
        lines.append(f'{pad}  <p class="piece-foot" data-copy="related">'
                     f"Read next: {offer}</p>")

    lines += [f"{pad}</article>", ""]
    return lines


def render_sections(sections: list[dict]) -> list[str]:
    printed = {topic["id"] for section in sections for topic in section["topics"]
               if public(topic)}
    titles = {topic["id"]: topic["title"]
              for section in sections for topic in section["topics"]}

    lines = [
        '  <section class="home-section" id="topics">',
        "    <h2>Every page, by subject</h2>",
        '    <p class="section-lede">',
        "      The app&rsquo;s own help, whole. Open the part you need. Every page says what",
        "      the number is, then how it is worked out.",
        "    </p>",
        '    <p class="beta-legend">',
        f'      <span class="tag beta">beta</span> {BETA_LEGEND}',
        "    </p>",
        "",
    ]
    for section in sections:
        topics = [topic for topic in section["topics"] if public(topic)]
        if not topics:
            continue
        count = "1 page" if len(topics) == 1 else f"{len(topics)} pages"
        lines += [
            f'    <details id="section-{section["id"]}">',
            f'      <summary class="what">',
            f'        <span class="what-line">{html_text(section["title"])}</span>',
            f'        <span class="what-more">{count}</span>',
            "      </summary>",
            "",
        ]
        for topic in topics:
            lines += render_topic(topic, printed, titles, indent=6)
        lines += ["    </details>", ""]
    lines += ["  </section>", ""]
    return lines


def render_html(sections: list[dict], glossary: list[dict]) -> str:
    lines = [
        BEGIN,
        "  <!-- GENERATED by web/tools/make_help.py from docs/copy/help.json and",
        "       docs/copy/glossary.json. The JSON is written out of the kit's HelpCatalog by",
        "       HelpExportTests, so the phone and this page are one reference work rendered",
        "       twice. Do not edit between the markers: regenerate, and",
        "       `make_help.py --check` fails while it is stale. The head, the hero and the",
        "       footer are the page's own.",
        "",
        "       THE FOLDS ARE SHUT. Forty pages of reference is a book, and the ten handles",
        "       are its contents. It is also what keeps a reference work on a site with word",
        "       budgets: verify_unique.py counts a page the way a reader meets it.",
        "",
        "       No dev topic is printed, ever, for the reason docs/channels.md gives: a",
        "       public page that names a dev door promises a stranger a door nobody can",
        "       have. A beta topic is printed with the pill. -->",
        "",
    ]
    lines += render_glossary(glossary)
    lines += render_sections(sections)
    lines.append("  " + END)
    return "\n".join(lines)


def splice(page: str, block: str) -> str:
    start = page.find(BEGIN)
    end = page.find(END)
    if start < 0 or end < 0:
        raise SystemExit(f"{PAGE}: the {BEGIN} / {END} markers are not both there")
    return page[:start] + block.lstrip() + page[end + len(END):]


# ------------------------------------------------------------------------------- main

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true",
                    help="write nothing; exit 1 if the page is stale")
    args = ap.parse_args(argv)

    if not HELP.exists():
        print(f"{HELP.relative_to(REPO)} is missing — write it from the kit:\n"
              "  cd ios/WingFoilKit && COPY_WRITE=1 swift test --filter HelpExportTests",
              file=sys.stderr)
        return 1

    sections = json.loads(HELP.read_text(encoding="utf-8"))["sections"]
    glossary = json.loads(GLOSSARY.read_text(encoding="utf-8"))["entries"]

    page = splice(PAGE.read_text(encoding="utf-8"), render_html(sections, glossary))
    stale = PAGE.read_text(encoding="utf-8") != page

    topics = sum(1 for s in sections for t in s["topics"] if public(t))
    hidden = sum(1 for s in sections for t in s["topics"] if not public(t))

    if args.check:
        if stale:
            print("stale, run `python3 web/tools/make_help.py`:", file=sys.stderr)
            print(f"  {PAGE.relative_to(REPO)}", file=sys.stderr)
            return 1
        print(f"help: {len(sections)} sections, {topics} topics and "
              f"{len(glossary)} glossary lines on /help/")
        return 0

    PAGE.write_text(page, encoding="utf-8")
    print(f"wrote {PAGE.relative_to(REPO)} ({len(sections)} sections, {topics} topics, "
          f"{hidden} dev-only topic(s) left out, {len(glossary)} glossary lines)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
