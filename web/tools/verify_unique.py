#!/usr/bin/env python3
"""One sentence, one home — and one page's worth of words, not four.

    python3 web/tools/verify_unique.py            # both halves, with the allow list
    python3 web/tools/verify_unique.py --brief    # one summary line (what verify_links runs)

WHY THIS FILE EXISTS. ``verify_copy.py`` holds the pages to ``docs/copy``: a sentence the kit
owns is pinned, and a page that drifts from it fails. What no check could see was a sentence
that is **nobody's** — the site's own prose, written once and then written again on another
page, and then corrected on one of them. On 15 September 2026 the six prose pages carried
26 verbatim duplicate sentences: the Android install steps twice at 110 and 95 words, the
recording classes in two tables, the beta list on two pages, the TestFlight and Connect IQ
feedback doors on two, and the twenty-minute dry run both generated and open-coded. Each
copy was true on the day it was typed.

TWO HALVES, and they fail for the same reason.

  1. **No sentence on two pages.** ``<main>`` of the six prose pages, whitespace normalised
     exactly as ``verify_copy.py`` normalises it (its helpers are imported rather than
     written a second time), split into sentences, and every sentence of eight words or more
     compared across pages. Everything ``docs/copy/*.json`` owns is subtracted first — a
     deliberately pinned sentence on nine pages is the point of pinning it, not a finding —
     and so is everything between ``<!-- guide:begin -->`` and ``<!-- guide:end -->``, which
     is ``make_start.py``'s output and ``docs/guide/getting-started.json``'s business.

     **Threshold zero.** Not a percentage: a percentage invites drift, and this repository
     already has the better mechanism — an ``ALLOW`` list of ``{prefix, pages, why}``,
     printed on every run the way ``docs/copy/check_release_copy.py`` prints its exemptions,
     because an exemption that is not read becomes the rule.

  2. **A word budget per page.** Words inside ``<main>``, with everything inside a
     ``<details>`` but its ``<summary>`` left out — that is what a reader meets, and the
     fold is the whole reason /start/ fits at all. Over budget plus ten per cent is a
     failure. This is what stops /start/ walking back to 3500 words one honest paragraph at
     a time, which is exactly how it got there the first time.

Stdlib only, like its neighbours, and called from ``verify_links.py`` beside
``verify_copy.py`` — a page that says the same thing twice is a page one of whose copies is
already out of date.
"""

from __future__ import annotations

import argparse
import html as html_module
import json
import re
import sys
from pathlib import Path

WEB = Path(__file__).resolve().parents[1]
REPO = WEB.parent
COPY = REPO / "docs" / "copy"

sys.path.insert(0, str(Path(__file__).resolve().parent))
import verify_copy                                                       # noqa: E402

#: Typographic punctuation, back to what an author typed.
#:
#: The generators render a straight apostrophe as a curly one, because that is what the page
#: should print: make_start.py, make_whats_new.py and make_help.py all do it, and the JSON
#: they read carries the straight one. `verify_copy.flat` must NOT do this — it compares a
#: pinned sentence character for character, and "—" and " - " are deliberately not the same
#: sentence there — but this file asks a different question. It asks whether two pages say
#: the same thing, and a page's typography is not what makes a sentence its own.
#:
#: Found by the first sentence that landed on two pages through two generators: the Strava
#: fall warning, which reached /invite/ as a release note and /help/ as a help item, and was
#: "owned" in docs/copy with a straight apostrophe in both.
SMART = str.maketrans({"\u2019": "'", "\u2018": "'", "\u201c": '"', "\u201d": '"'})


def flat(text: str) -> str:
    return verify_copy.flat(text).translate(SMART)

#: The prose a reader reads. /app/ is the browser app (UI labels, not prose), /privacy/ and
#: /impressum/ are legal text whose repetitions are deliberate, and /strava/callback/ and
#: the three redirect stubs are on screen for a frame.
#:
#: **Four pages since 19 September 2026**, where there were six: /start/ absorbed /watches/,
#: /invite/ absorbed /whats-new/, and /learn/ became /help/, which is rendered out of the
#: kit's own help catalogue rather than written here.
PAGES = [
    "index.html",
    "start/index.html",
    "help/index.html",
    "invite/index.html",
]

#: Words inside <main>, counting only what is visible with every <details> shut. The plan's
#: table of 15 September 2026, and the tolerance is the same everywhere: ten per cent.
#:
#: /start/ and /invite/ took a page each on 19 September 2026 and their budgets grew by less
#: than the pages they swallowed: a route card's steps were already folded, the Garmin
#: family table became one generated sentence, and the release notes past the third are in
#: a fold. /help/ is the whole of the app's help and is **not** a prose page at all: with
#: its ten section folds shut a reader meets the eleven glossary lines and ten handles,
#: which is what the number below is for. Open, it is forty pages of reference, and that is
#: the point of it.
BUDGET = {
    "index.html": 550,
    "start/index.html": 1700,
    "help/index.html": 900,
    "invite/index.html": 1500,
}
SLACK = 1.10

#: A sentence shorter than this is a fragment — a table cell, a button, half a heading — and
#: two pages saying "Take the FIT" is not a duplication problem.
MIN_WORDS = 8

#: THE ALLOW LIST. Every entry carries a `why`, every entry is printed on every run, and the
#: threshold either side of it is zero. `prefix` is matched against the start of the
#: normalised sentence, so a trailing link or a date does not need to be retyped here.
ALLOW: list[dict] = [
    {
        "prefix": "beta in the public beta today, not yet in the App Store release.",
        "pages": ["index.html", "help/index.html"],
        "why": (
            "the legend under a `beta` pill, once per page that draws one. It is not copy "
            "saying the same thing twice — it is the key to a symbol, and a key that is on "
            "the next page instead of this one is not a key. docs/channels.md decides the "
            "pills; this sentence only says what the word means."
        ),
    },
]

MAIN = re.compile(r"<main[^>]*>(.*)</main>", re.S)
COMMENT = re.compile(r"<!--.*?-->", re.S)
SCRIPT = re.compile(r"<(script|style)\b.*?</\1>", re.S | re.I)
GUIDE = re.compile(r"<!-- guide:begin -->.*?<!-- guide:end -->", re.S)
DETAILS = re.compile(r"<details\b[^>]*>((?:(?!<details\b|</details>).)*)</details>",
                     re.S | re.I)
SUMMARY = re.compile(r"<summary[^>]*>.*?</summary>", re.S | re.I)
TAG = re.compile(r"<[^>]+>")

#: A block ends a sentence whether or not it ends with a full stop. Without this a button's
#: label runs into the paragraph after it and the pair reads as one sentence that exists on
#: no page — which is how the first run of this check reported a duplicate nobody had
#: written. `¶` is the marker, and it is stripped again below.
BLOCK = re.compile(
    r"</?(p|li|h[1-6]|td|th|dt|dd|div|section|article|figure|figcaption|summary|details"
    r"|blockquote|ol|ul|dl|table|thead|tbody|tr|main|nav|br|hr)\b[^>]*>", re.I)
MARK = "¶"

#: A sentence ends at . ! or ? followed by space and a capital or an opening quote — or at a
#: block boundary.
SENTENCE_END = re.compile(r"(?<=[.!?])\s+(?=[A-Z“‘])|" + MARK)


def main_text(source: str, *, visible_only: bool, drop_guide: bool) -> str:
    """The reader's own text: <main>, minus comments, scripts and (optionally) the fold."""
    found = MAIN.search(source)
    if not found:
        return ""
    body = found.group(1)
    if drop_guide:
        body = GUIDE.sub(" ", body)
    body = COMMENT.sub(" ", body)
    body = SCRIPT.sub(" ", body)
    if visible_only:
        previous = None
        while previous != body:
            previous = body
            body = DETAILS.sub(
                lambda m: " ".join(SUMMARY.findall(m.group(1))), body)
    body = BLOCK.sub(" %s " % MARK, body)
    return flat(html_module.unescape(TAG.sub(" ", body)))


def words(text: str) -> int:
    return len([w for w in text.replace(MARK, " ").split()
                if re.search(r"\w", w)])


def sentences(text: str) -> list[str]:
    out = []
    for piece in SENTENCE_END.split(text):
        piece = flat(piece.replace(MARK, " ")).strip(" —-·")
        if words(piece) >= MIN_WORDS:
            out.append(piece)
    return out


def pinned_sentences() -> set[str]:
    """Every string docs/copy owns, flattened — these may be on every page by design."""
    owned: set[str] = set()

    def walk(value):
        if isinstance(value, str):
            owned.add(flat(value))
            for part in sentences(flat(value)):
                owned.add(part)
        elif isinstance(value, dict):
            for key, item in value.items():
                if not key.startswith("_"):
                    walk(item)
        elif isinstance(value, list):
            for item in value:
                walk(item)

    for path in sorted(COPY.glob("*.json")):
        walk(json.loads(path.read_text(encoding="utf-8")))
    return owned


def allowed(sentence: str, pages: set[str]) -> dict | None:
    for entry in ALLOW:
        if sentence.startswith(flat(entry["prefix"])) and pages <= set(entry["pages"]):
            return entry
    return None


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--brief", action="store_true",
                    help="one summary line — what verify_links.py runs")
    args = ap.parse_args(argv)

    source = {page: (WEB / page).read_text(encoding="utf-8") for page in PAGES}
    owned = pinned_sentences()

    # ------------------------------------------------------------- one sentence, one home
    where: dict[str, set[str]] = {}
    for page in PAGES:
        text = main_text(source[page], visible_only=False, drop_guide=True)
        for sentence in sentences(text):
            if sentence in owned:
                continue
            where.setdefault(sentence, set()).add(page)

    problems: list[str] = []
    honoured: list[tuple[dict, str, set[str]]] = []
    for sentence, pages in sorted(where.items()):
        if len(pages) < 2:
            continue
        entry = allowed(sentence, pages)
        if entry is not None:
            honoured.append((entry, sentence, pages))
            continue
        problems.append('%s\n         on %s'
                        % (sentence[:150], ", ".join("/" + p.replace("index.html", "")
                                                     for p in sorted(pages))))

    # ------------------------------------------------------------------------- the budgets
    counted = []
    for page in PAGES:
        visible = words(main_text(source[page], visible_only=True, drop_guide=False))
        budget = BUDGET[page]
        counted.append((page, visible, budget))
        if visible > budget * SLACK:
            problems.append(
                '/%s is %d words inside <main>, budget %d (+10%% = %d)'
                % (page.replace("index.html", ""), visible, budget, int(budget * SLACK)))

    if not args.brief:
        for page, visible, budget in counted:
            print("  %-4s /%-12s %5d words visible, budget %d"
                  % ("ok" if visible <= budget * SLACK else "OVER",
                     page.replace("index.html", ""), visible, budget))
        for entry, sentence, pages in honoured:
            print('  note  allowed on %s: "%s"\n          — %s'
                  % (", ".join("/" + p.replace("index.html", "") for p in sorted(pages)),
                     sentence[:90], entry["why"]))
        if not honoured and ALLOW:
            print("  note  the ALLOW list has %d entry(ies), none of which fired — an "
                  "exemption nothing needs is one to delete" % len(ALLOW))

    if problems:
        print("\n%d PROBLEM(S) — a sentence with two homes, or a page over budget:"
              % len(problems))
        for problem in problems:
            print("  " + problem)
        return 1

    print("unique prose: %d pages, no sentence of %d+ words on two of them (%d allowed); "
          "every page inside its word budget" % (len(PAGES), MIN_WORDS, len(honoured)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
