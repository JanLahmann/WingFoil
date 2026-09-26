#!/usr/bin/env python3
"""The help page is the app's help catalogue; this renders it.

    python3 web/tools/make_help.py            # write the block into web/help/index.html
    python3 web/tools/make_help.py --check    # exit 1 if the page is stale

Source: ``docs/copy/help.json``, written out of ``HelpCatalog`` by the kit's
``HelpExportTests`` (``COPY_WRITE=1 swift test --filter HelpExportTests``), plus
``docs/copy/glossary.json`` for the nineteen metric one-liners that open the page.

Jan, 19 September 2026: *"one product, three shells"* — iOS is the reference and the web is
the port. ``/learn/`` was the counter-example: eleven glossary lines and four questions,
written in the website's own pass, about an app whose own Help had been answering the same
questions for a month in different words. So the page stopped being written. It is
rendered, from the same catalogue the phone renders, and ``/learn/`` is a redirect to
``/help/#numbers``.

WHAT IT RENDERS, into the block between ``<!-- help:begin -->`` and ``<!-- help:end -->``:

1. **What the numbers mean** — the nineteen ``glossary.json`` entries as a definition list
   marked ``data-copy="glossary"``, which is the pin ``web/tools/verify_copy.py`` holds. It
   was ``/learn/``'s job and it is the one thing on this page that is not a help topic: a
   rider who followed a metric's name here wants the one-liner, not a page.
2. **The seven sections, as folds.** One ``<details>`` per ``HelpSection``, in the
   catalogue's order, each holding its topics as articles: the summary, the body, the items
   as a definition list, and the "read next" links. Closed, because forty pages of
   reference is a book and the seven handles are its contents — and because
   ``web/tools/verify_unique.py`` counts a page the way a reader meets it, which is what
   lets a reference work live on a site with word budgets. "Read the numbers" is
   sub-headed (a topic's ``group``), the way the phone's index is.

**THE MERGE OF 26 SEPTEMBER 2026 KEEPS ITS OLD LINKS.** A topic's ``aliases`` are the ids
it absorbed; each is an empty anchor at the top of the article, so ``#help-foilPct`` still
opens the fold and lands on Flights and foil time. An item's ``link`` is the topic it is
the signpost for, drawn as a link on its term when that topic is printed.

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


#: Topics this page does **not** print as a fold, and why.
#:
#: `numbers` is the glossary, and the glossary is section 1 of this page already — the
#: phone needs a topic because its Help has no section 1, the site does not. Printing both
#: would put the same nineteen sentences on one page twice (`verify_unique.py`).
SKIP_TOPICS = {"numbers"}


def public(row: dict) -> bool:
    """A topic or an item this site may print at all."""
    if row.get("id") in SKIP_TOPICS:
        return False
    return any(channel in WEB_CHANNELS for channel in row["channels"])


def pill(row: dict) -> str:
    """The `beta` pill, on anything the App Store release does not have."""
    return "" if "release" in row["channels"] else '<span class="tag beta">beta</span>'


# --------------------------------------------------------------------------- the glossary

#: The rider's word for a `places` value, and the group it reads as. A definition list
#: that spells eight screens in one sentence is a list, not a sentence, and docs/voice.md
#: budgets a sentence at twenty words — so the screens he holds are one clause and the two
#: machine-readable places (the FIT field, the Garmin Connect row) are a second.
PLACE_WORDS = {
    "watchPage": "the watch",
    "phoneRow": "the phone",
    "phonePage": "the phone",
    "card": "the share card",
    "web": "the website",
}


def where_it_shows(entry: dict) -> str:
    """``where it shows``, from ``places`` and ``fit`` — the 20 September 2026 fields.

    Jan, that day: *"the definitions of the numbers are important to clarify, make
    transparent, and consistent across all surfaces."* A tester had compared three screens
    about one afternoon and read three numbers. Naming the screens a word shows on is what
    lets the next reader do that comparison and come out right.

    ``help`` is dropped: it is this page, and nineteen rows saying so say nothing.
    """
    seen, words = set(), []
    for place in entry.get("places", []):
        word = PLACE_WORDS.get(place)
        if word and word not in seen:
            seen.add(word)
            words.append(word)
    out = []
    if words:
        joined = words[0] if len(words) == 1 \
            else ", ".join(words[:-1]) + " and " + words[-1]
        out.append("Shows on " + joined + ".")
    if "fitField" in entry.get("places", []) and entry.get("fit"):
        out.append("In the FIT as " + entry["fit"] + ".")
    if "connectField" in entry.get("places", []):
        out.append("Garmin Connect prints it.")
    return " ".join(out)


def render_glossary(entries: list[dict]) -> list[str]:
    """The nineteen one-liners, in the JSON's order — the pin verify_copy.py holds.

    ``/learn/`` carried a twelfth of its own, *Pump & takeoff effort*, marked
    ``glossary-extra``. It is gone from here on purpose rather than forgotten: the pump
    strokes have a help topic of their own three folds down, which is a page rather than a
    line, and rule 10 of docs/voice.md asks only that the fact keep a home.

    **Where it shows rides in an aside** (20 September 2026). ``verify_copy.py`` compares a
    pinned element's text with any ``data-copy="aside"`` descendant removed, which is how a
    row can carry a pill and still *be* the JSON's sentence. The places line is the same
    kind of thing: the ``line`` is the definition and the aside is the index of screens
    that print it, so the pin stays exactly the kit's sentence.
    """
    lines = [
        '  <section class="home-section" id="numbers">',
        "    <h2>What the numbers mean</h2>",
        '    <p class="section-lede">',
        "      Nineteen words, one line each, and the screens each one shows on. The app",
        "      prints the same line beside the same number.",
        "    </p>",
        '    <dl class="terms" data-copy="glossary">',
    ]
    for entry in entries:
        places = where_it_shows(entry)
        aside = (f' <span class="muted small" data-copy="aside">{places}</span>'
                 if places else "")
        lines += [
            '      <div class="term">',
            f"        <dt>{html_text(entry['term'])}</dt>",
            f"        <dd>{html_text(entry['line'])}{aside}</dd>",
            "      </div>",
        ]
    lines += ["    </dl>", "  </section>", ""]
    return lines


# ----------------------------------------------------------------------------- the topics

def render_topic(topic: dict, printed: set[str], titles: dict[str, str],
                 indent: int) -> list[str]:
    pad = " " * indent
    lines = [f'{pad}<article class="panel piece" id="help-{topic["id"]}">']
    # The ids this topic absorbed, as anchors an old link still lands on.
    for alias in topic.get("aliases", []):
        lines.append(f'{pad}  <span class="help-alias" id="help-{alias}"></span>')
    lines += [
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
            term = html_text(item["term"])
            if item.get("link") in printed:
                term = f'<a href="#help-{item["link"]}">{term}</a>'
            lines += [
                f'{pad}    <div class="term">',
                f"{pad}      <dt>{term}{pill(item)}</dt>",
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

    listed = [s for s in sections if [t for t in s["topics"] if public(t)]]

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
        # THE CONTENTS, AND A WAY TO SEARCH IT (docs/web-design-review.md, finding 11; the
        # browser app got the same two on 20 September 2026 and this is the same renderer's
        # half of it). Seven shut folds are a table of contents only if the reader can see all
        # seven at once, and a reference work is only a reference work if he can look
        # something up in it. The chips scroll sideways under 720 px, in the shape the
        # section nav already takes there (finding 13).
        '    <nav class="help-index" aria-label="Help sections">',
    ]
    for section in listed:
        topics = [t for t in section["topics"] if public(t)]
        count = "1 page" if len(topics) == 1 else f"{len(topics)} pages"
        lines.append(f'      <a class="help-chip" href="#section-{section["id"]}">'
                     f'{html_text(section["title"])}'
                     f'<span class="help-count">{count}</span></a>')
    lines += [
        "    </nav>",
        '    <p class="help-search">',
        '      <label class="sr-only" for="help-filter">Filter the help</label>',
        '      <input id="help-filter" type="search" autocomplete="off" spellcheck="false"',
        '             placeholder="Filter by title or summary">',
        '      <span class="muted small" id="help-filter-count" role="status"></span>',
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
        group = None
        for topic in topics:
            # A sub-heading wherever the group changes ("Read the numbers" only).
            here = (topic.get("group") or {}).get("id")
            if here and here != group:
                lines += [f'      <h3 class="help-group">'
                          f'{html_text(topic["group"]["title"])}</h3>', ""]
            group = here
            lines += render_topic(topic, printed, titles, indent=6)
        lines += ["    </details>", ""]
    lines += ["  </section>", "", *FILTER_SCRIPT, ""]
    return lines


#: The filter, and the deep link. Eighteen lines of vanilla JavaScript, inlined for the
#: reason every other script on this site is inlined: there is no build step, and a
#: reference work must still read with JavaScript off — which it does, because the folds
#: are `<details>` and the chips are ordinary anchors. All this adds is *search*, and the
#: one thing an anchor cannot do on its own: open the fold it lands in.
FILTER_SCRIPT = [
    "  <script>",
    "    (function () {",
    '      var field = document.getElementById("help-filter");',
    '      var status = document.getElementById("help-filter-count");',
    '      var folds = [].slice.call(document.querySelectorAll("#topics details"));',
    "      function open(hash) {",
    '        var target = hash && document.querySelector(hash.replace(/[^\\w#-]/g, ""));',
    "        if (!target) return;",
    '        var fold = target.closest("details");',
    "        if (fold) fold.open = true;",
    '        target.scrollIntoView({ block: "start" });',
    "      }",
    '      field.addEventListener("input", function () {',
    "        var needle = field.value.trim().toLowerCase(), hits = 0;",
    "        folds.forEach(function (fold) {",
    '          var shown = 0, pages = fold.querySelectorAll("article.piece");',
    "          [].forEach.call(pages, function (page) {",
    "            var match = !needle || page.textContent.toLowerCase().indexOf(needle) >= 0;",
    "            page.hidden = !match;",
    "            if (match) shown += 1;",
    "          });",
    "          fold.hidden = needle ? shown === 0 : false;",
    "          fold.open = needle ? shown > 0 : false;",
    "          hits += shown;",
    "        });",
    '        status.textContent = needle',
    '          ? (hits === 1 ? "1 page matches." : hits + " pages match.")',
    '          : "";',
    "      });",
    "      open(location.hash);",
    '      addEventListener("hashchange", function () { open(location.hash); });',
    "    })();",
    "  </script>",
]


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
        "       THE FOLDS ARE SHUT. Forty pages of reference is a book, and the seven handles",
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
