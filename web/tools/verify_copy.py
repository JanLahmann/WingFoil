#!/usr/bin/env python3
"""The website says what ``docs/copy`` says — and a change on **either** side fails here.

    python3 web/tools/verify_copy.py            # one line per pinned string
    python3 web/tools/verify_copy.py --brief    # one summary line (what verify_links runs)

``docs/copy/README.md`` states the contract: the JSON files are the artefact, the kit is the
author, and both sides are pinned. ``CopyContractTests`` is the kit's half — a Swift edit
that moves a fact fails the kit suite until the JSON moves with it. **This is the web's
half.** Nothing here retypes a sentence: every string is read out of the JSON at run time
and looked for in the page, so a JSON that moves and a page that does not is a failure, and
so is a page that is edited away from the JSON.

WHAT IS PINNED, and where it bites

  phrases.json
    `promise`        the hero paragraph on / — the one sentence that also opens the
                     welcome screen and the App Store description
    `callToAction`   what web/js/cardstats.js builds as BRANDING.line. The JS COMPOSES it
                     (`cta` + " — " + `site`), so the two parts are pinned and the
                     composition is re-done here rather than the sentence being looked for
    `captionOffer`   the tail of the share-card caption template in web/js/sharecard.js,
                     composed from the same two parts
    `strava`         present on /learn/, /start/ and /privacy/ …
    `stravaForbidden`… and none of those five phrases anywhere under web/**.html
    `ciqListingTitle` every <span data-copy="ciq-title">
    `appStoreName` / `appStoreSubtitle`
                     NOT PINNED: the site never names the App Store app. Nothing on any
                     page says "Wingfoil Analyzer" — the iPhone app is "CleanJibe" here and
                     the store link is not on the site yet. The day a page prints the store
                     name, wrap it in <span data-copy="appstore-name"> and the pin below
                     wakes up on its own.
    `lexicon.banned` absent from the visible text of every page. **HTML only**, and that is
                     a decision rather than an oversight: phrases.json already carries an
                     exemption for "carried" in TurnAnalytics.swift — "not clean · carried
                     18° past the axis", where the word is the ordinary verb and the arc is
                     what carried. The analyzer does not draw that sentence today (its turn
                     table prints the score as a number), but the day it does, running this
                     list over web/js/*.js would mean writing the same exemption down a
                     second time, in a second place, for the same string. The JS is
                     verify_presentation.py's ground, and that is where the two sides of an
                     outcome sentence get held together.

  channels.json
    the beta <ul> and the dev <ul> on /invite/ — the one page that prints them — carry
    exactly the JSON's rows, in the JSON's order, verbatim; the section <h2> is
    `sectionTitle`; and no `forbiddenInRelease`
    word appears on / or /app/ outside those lists and the elements marked
    `data-copy="beta-door"`. The exemptions for that last rule are NOT written here: they
    live in `docs/copy/check_release_copy.py`'s own allow map for the same page, which is
    read below, so a door that is allowed is allowed once and printed on every run.

  recording-classes.json
    the four `name` and four `line` strings, verbatim, in the one class table
    (/watches/#classes), in the cells marked `data-copy="class-name"` / `class-line`.
    The /watches/ "What you ride with" table keeps its own shape; only its class LETTERS
    are checked against the names.

  glossary.json
    the eight `term`/`line` pairs in /learn/'s definition list, in order, in the JSON's
    order; entries the site keeps that the kit does not have are marked
    `data-copy="glossary-extra"` and must come after all eight.

  feedback.json
    the three `prompts` in every mailto: body on the site (percent-decoded), and the
    `invitation` sentence in every "Tell us" block.

  icu-setup.json
    the four step `title`s and `saveButton`, on /start/, OUTSIDE the generated guide block.
    Nothing between <!-- guide:begin --> and <!-- guide:end --> is read: that block is
    make_start.py's output and docs/guide/getting-started.json's business.

THE MARKING RULES

  A pinned element's text is its own text with any descendant marked `data-copy="aside"`
  removed. That is how a row can carry a trailing `beta` pill or a link and still BE the
  JSON's sentence: the pill goes in an aside, outside the sentence. `data-copy` is a
  space-separated token list, like `class`, so one cell can be both a `class-name` and a
  `beta-door`.

  Comparison collapses runs of whitespace **and non-breaking spaces** to one space and
  trims; entities are resolved by the parser. Everything else — em dashes, the middle dot,
  typographic apostrophes — is compared exactly, which is the point: "—" and " - " are not
  the same sentence.

Stdlib only, on purpose: it runs with plain `python3` beside verify_links.py, which calls
it the way it calls `make_start.py --check` and `make_devices.py --check` — a page that has
drifted from the copy contract is a link to a promise nobody made.
"""

from __future__ import annotations

import argparse
import html as html_module
import json
import re
import sys
import urllib.parse
from pathlib import Path

WEB = Path(__file__).resolve().parents[1]
REPO = WEB.parent
COPY = REPO / "docs" / "copy"

# The exemptions for the forbidden-door rule have ONE home, and it is not this file:
# docs/copy/check_release_copy.py's allow map, where every one carries a `why` and is
# printed on every run (docs/copy/README.md, "Exemptions").
sys.path.insert(0, str(COPY))
import check_release_copy as release                                     # noqa: E402

PAGES = [
    "index.html",
    "learn/index.html",
    "invite/index.html",
    "start/index.html",
    "privacy/index.html",
    "impressum/index.html",
    "watches/index.html",
    "whats-new/index.html",
    "app/index.html",
    "strava/callback/index.html",
]

VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param",
        "source", "track", "wbr", "path", "circle", "rect", "line", "polyline", "polygon",
        "use", "stop", "ellipse"}

GUIDE_BLOCK = re.compile(r"<!-- guide:begin -->.*?<!-- guide:end -->", re.S)


# ------------------------------------------------------------------- a very small DOM

class Node:
    """One element. `kids` are Nodes and plain strings, in document order."""

    __slots__ = ("tag", "attrs", "kids", "line")

    def __init__(self, tag: str, attrs: dict, line: int = 0):
        self.tag, self.attrs, self.kids, self.line = tag, attrs, [], line

    @property
    def copy_tokens(self) -> list[str]:
        return (self.attrs.get("data-copy") or "").split()


class Tree(release.HTMLParser):
    """The document as a tree. Script and style keep their tags and drop their text."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node("#document", {})
        self.stack = [self.root]
        self.mute = 0

    def handle_starttag(self, tag, attrs):
        node = Node(tag, {k: (v or "") for k, v in attrs}, self.getpos()[0])
        self.stack[-1].kids.append(node)
        if tag in ("script", "style"):
            self.mute += 1
        if tag not in VOID and not (self.get_starttag_text() or "").rstrip().endswith("/>"):
            self.stack.append(node)

    def handle_startendtag(self, tag, attrs):
        self.stack[-1].kids.append(Node(tag, {k: (v or "") for k, v in attrs},
                                        self.getpos()[0]))

    def handle_endtag(self, tag):
        if tag in ("script", "style") and self.mute:
            self.mute -= 1
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag:
                del self.stack[i:]
                return

    def handle_data(self, data):
        if not self.mute:
            self.stack[-1].kids.append(data)


def parse(source: str) -> Node:
    tree = Tree()
    tree.feed(source)
    tree.close()
    return tree.root


def flat(text: str) -> str:
    """Whitespace, non-breaking spaces included, collapsed to one space; ends trimmed."""
    return re.sub(r"[\s\u00a0]+", " ", text).strip()


def text_of(node: Node, drop_asides: bool = True) -> str:
    """The element's own sentence: its text, minus any `data-copy="aside"` descendant."""
    out: list[str] = []

    def walk(n: Node):
        for kid in n.kids:
            if isinstance(kid, str):
                out.append(kid)
            elif drop_asides and "aside" in kid.copy_tokens:
                out.append(" ")
            else:
                out.append(" ")
                walk(kid)
                out.append(" ")

    walk(node)
    return flat("".join(out))


def descendants(node: Node):
    for kid in node.kids:
        if isinstance(kid, Node):
            yield kid
            yield from descendants(kid)


def descendants_marked(node: Node, inherited: frozenset = frozenset()):
    """Every descendant, with the `data-copy` tokens it INHERITS from its ancestors.

    A mark on a wrapper is a mark on what it wraps: `<div class="term"
    data-copy="glossary-extra">` marks the `<dt>` and `<dd>` inside it, which is the way an
    editor would expect to write it and the way the markup already groups them.
    """
    for kid in node.kids:
        if isinstance(kid, Node):
            tokens = inherited | frozenset(kid.copy_tokens)
            yield kid, tokens
            yield from descendants_marked(kid, tokens)


def marked(root: Node, token: str) -> list[Node]:
    return [n for n in descendants(root) if token in n.copy_tokens]


# ------------------------------------------------------------------------- the report

class Report:
    """One line per pin on the way past; every miss printed at the end."""

    def __init__(self, brief: bool):
        self.brief = brief
        self.pins = 0
        self.failures: list[str] = []

    def ok(self, line: str):
        self.pins += 1
        if not self.brief:
            print("  ok   " + line)

    def fail(self, where: str, key: str, message: str, snippet: str = ""):
        near = ""
        if snippet:
            near = "\n         nearest: …%s…" % flat(snippet)[:180]
        self.failures.append("%s [%s] %s%s" % (where, key, message, near))


def nearest(haystack: str, needle: str) -> str:
    """The stretch of page that looks most like the string we wanted, for the message."""
    words = needle.split()
    for length in (6, 4, 3, 2):
        if len(words) < length:
            continue
        probe = " ".join(words[:length])
        at = haystack.find(probe)
        if at >= 0:
            return haystack[max(0, at - 30):at + len(needle) + 40]
    return haystack[:150]


# -------------------------------------------------------------------------- the pages

class Site:
    def __init__(self):
        self.source: dict[str, str] = {}
        self.tree: dict[str, Node] = {}
        self.text: dict[str, str] = {}
        for page in PAGES:
            src = (WEB / page).read_text(encoding="utf-8")
            self.source[page] = src
            self.tree[page] = parse(src)
            self.text[page] = text_of(self.tree[page], drop_asides=False)

    def outside_guide(self, page: str) -> Node:
        """The page with the generated guide block taken out (make_start.py owns that)."""
        return parse(GUIDE_BLOCK.sub("", self.source[page]))


# --------------------------------------------------------------------------- the pins

def pin_promise(site: Site, phrases: dict, report: Report):
    want = phrases["promise"]
    page = "index.html"
    nodes = marked(site.tree[page], "promise")
    if not nodes:
        report.fail("web/" + page, "phrases.promise",
                    'no element marked data-copy="promise"',
                    nearest(site.text[page], want))
        return
    for node in nodes:
        got = text_of(node)
        if got != want:
            report.fail("web/%s:%d" % (page, node.line), "phrases.promise",
                        "the hero paragraph is not the JSON's sentence", got)
            return
    report.ok('phrases.promise → web/%s (the hero paragraph, %d words)'
              % (page, len(want.split())))


def pin_branding(phrases: dict, report: Report):
    """The card's CTA and the caption offer — composed in JS, so the PARTS are pinned."""
    cardstats = (WEB / "js" / "cardstats.js").read_text(encoding="utf-8")
    sharecard = (WEB / "js" / "sharecard.js").read_text(encoding="utf-8")

    parts = {}
    for key in ("name", "site", "cta"):
        match = re.search(r"^\s*%s:\s*\"([^\"]*)\"," % key, cardstats, re.M)
        if not match:
            report.fail("web/js/cardstats.js", "phrases", "no BRANDING.%s literal" % key)
            return
        parts[key] = match.group(1)

    # BRANDING.line = `${BRANDING.cta} — ${BRANDING.site}` — the composition, read rather
    # than assumed, so a change of separator fails here and not in a rider's chat thread.
    line = re.search(r"BRANDING\.line\s*=\s*`\$\{BRANDING\.cta\}(.*?)\$\{BRANDING\.site\}`",
                     cardstats)
    if not line:
        report.fail("web/js/cardstats.js", "phrases.callToAction",
                    "BRANDING.line is no longer `${BRANDING.cta}…${BRANDING.site}`")
        return
    built = parts["cta"] + line.group(1) + parts["site"]
    if built != phrases["callToAction"]:
        report.fail("web/js/cardstats.js", "phrases.callToAction",
                    "BRANDING.line composes %r" % built, built)
    else:
        report.ok("phrases.callToAction → web/js/cardstats.js (BRANDING.cta + BRANDING.site)")

    caption = re.search(r"analysed with \$\{BRANDING\.name\}, free at \$\{BRANDING\.site\}",
                        sharecard)
    if not caption:
        report.fail("web/js/sharecard.js", "phrases.captionOffer",
                    "the caption template no longer ends "
                    "\"analysed with ${BRANDING.name}, free at ${BRANDING.site}\"")
        return
    offer = caption.group(0).replace("${BRANDING.name}", parts["name"]) \
                            .replace("${BRANDING.site}", parts["site"])
    if offer != phrases["captionOffer"]:
        report.fail("web/js/sharecard.js", "phrases.captionOffer",
                    "the caption tail composes %r" % offer, offer)
    else:
        report.ok("phrases.captionOffer → web/js/sharecard.js (the caption's tail)")


def pin_strava(site: Site, phrases: dict, report: Report):
    owed = ["learn/index.html", "start/index.html", "privacy/index.html"]
    sentence = phrases["strava"]
    for page in owed:
        if sentence not in site.text[page]:
            report.fail("web/" + page, "phrases.strava",
                        "the one Strava sentence is not on this page",
                        nearest(site.text[page], sentence))
    if not report.failures:
        report.ok("phrases.strava → %s" % ", ".join("web/" + p for p in owed))
    # what a positions-only recording loses, on the one page that sets Strava up
    fall = phrases["stravaFall"]
    if fall.replace("'", "\u2019") not in site.text["start/index.html"].replace("'", "\u2019"):
        report.fail("web/start/index.html", "phrases.stravaFall",
                    "the Strava fall sentence is not on this page",
                    nearest(site.text["start/index.html"], fall))
    else:
        report.ok("phrases.stravaFall → web/start/index.html")

    hits = 0
    for page in PAGES:
        for phrase in phrases["stravaForbidden"]:
            if phrase.lower() in site.text[page].lower():
                hits += 1
                report.fail("web/" + page, "phrases.stravaForbidden",
                            'says "%s" — docs/channels.md: the rider-facing text never says '
                            "what Strava has or has not reviewed" % phrase,
                            nearest(site.text[page], phrase))
    if not hits:
        report.ok("phrases.stravaForbidden → none of the %d phrases on any of the %d pages"
                  % (len(phrases["stravaForbidden"]), len(PAGES)))


def pin_ciq_title(site: Site, phrases: dict, report: Report):
    want = phrases["ciqListingTitle"]
    found = 0
    for page in PAGES:
        for node in marked(site.tree[page], "ciq-title"):
            found += 1
            got = text_of(node)
            if got != want:
                report.fail("web/%s:%d" % (page, node.line), "phrases.ciqListingTitle",
                            "the listing name on the page is not the store's", got)
    if not found:
        report.fail("web/**", "phrases.ciqListingTitle",
                    'no <span data-copy="ciq-title"> anywhere on the site')
    else:
        report.ok("phrases.ciqListingTitle → %d spans (%s)" % (found, want))

    pin_ciq_title_in_guide(want, report)


# The ONE string the generated guide block is held to. Everything else between
# <!-- guide:begin --> and <!-- guide:end --> is make_start.py's and
# docs/guide/getting-started.json's business (`outside_guide`, and docs/copy/README.md's
# ownership rule) — but the Connect IQ listing's NAME is not a wording, it is a fact about
# a store page, and phrases.json already owns it for the two pinned spans. Until this pin
# existed, web/start/index.html printed two different names for one listing 150 lines
# apart, one of which the store does not show (ux-audit B2, change #6).
GUIDE_INSTALL_STEP = re.compile(
    r"<h[1-6][^>]*>\s*Install the watch app\s*</h[1-6]>\s*<p>\s*<strong>(.*?)</strong>", re.S)


def pin_ciq_title_in_guide(want: str, report: Report):
    source = (WEB / "start" / "index.html").read_text(encoding="utf-8")
    block = GUIDE_BLOCK.search(source)
    if not block:
        report.fail("web/start/index.html", "phrases.ciqListingTitle",
                    "no <!-- guide:begin --> … <!-- guide:end --> block on the page")
        return
    step = GUIDE_INSTALL_STEP.search(block.group(0))
    if not step:
        report.fail("web/start/index.html", "phrases.ciqListingTitle",
                    'the generated guide has no "Install the watch app" step opening with a '
                    "bolded listing name — re-scope this pin, do not delete it")
        return
    got = flat(html_module.unescape(re.sub(r"<[^>]+>", "", step.group(1))))
    if got != want:
        line = source[:block.start() + step.start(1)].count("\n") + 1
        report.fail("web/start/index.html:%d" % line, "phrases.ciqListingTitle",
                    "the generated guide names a listing the store does not show — fix "
                    "docs/guide/getting-started.json and run web/tools/make_start.py", got)
    else:
        report.ok("phrases.ciqListingTitle → the generated guide block's install step "
                  "(the one string in it that is pinned)")


def pin_appstore_name(site: Site, phrases: dict, report: Report):
    """Nothing to pin until a page names the store app — and then it pins itself."""
    spans = [(p, n) for p in PAGES for n in marked(site.tree[p], "appstore-name")]
    subs = [(p, n) for p in PAGES for n in marked(site.tree[p], "appstore-subtitle")]
    for key, nodes, want in (("appStoreName", spans, phrases["appStoreName"]),
                             ("appStoreSubtitle", subs, phrases["appStoreSubtitle"])):
        for page, node in nodes:
            got = text_of(node)
            if got != want:
                report.fail("web/%s:%d" % (page, node.line), "phrases." + key,
                            "does not print the store's own %s" % key, got)
    # The bare name, typed rather than marked, is the failure this really guards: a page
    # that says "Wingfoil Analyzer" in prose can drift the day the store name changes.
    loose = [p for p in PAGES
             if phrases["appStoreName"] in site.text[p] and not marked(site.tree[p],
                                                                      "appstore-name")]
    for page in loose:
        report.fail("web/" + page, "phrases.appStoreName",
                    'the App Store name is typed into the prose — wrap it in '
                    '<span data-copy="appstore-name">',
                    nearest(site.text[page], phrases["appStoreName"]))
    if spans or subs:
        report.ok("phrases.appStoreName/Subtitle → %d spans" % (len(spans) + len(subs)))
    elif not loose:
        report.ok("phrases.appStoreName/Subtitle → nothing to pin: no page names the "
                  "App Store app (the site says \"CleanJibe\" and links no store)")


def pin_lexicon(site: Site, phrases: dict, report: Report):
    banned = phrases["lexicon"]["banned"]
    exempt = [e for e in phrases["lexicon"].get("exemptions", [])
              if e["path"].startswith("web/")]
    hits = 0
    for page in PAGES:
        allowed = {e["word"].lower() for e in exempt
                   if ("web/" + page).startswith(e["path"])}
        for word in banned:
            if word.lower() in allowed:
                continue
            if release.whole_word(word, site.text[page]):
                hits += 1
                report.fail("web/" + page, "phrases.lexicon.banned",
                            'says "%s" — not a word this product uses (CLAUDE.md)' % word,
                            nearest(site.text[page], word))
    if not hits:
        report.ok("phrases.lexicon.banned → none of the %d words on any of the %d pages "
                  "(HTML only; the JS side is verify_presentation.py's)"
                  % (len(banned), len(PAGES)))
    for exemption in exempt:
        print('  note  exemption honoured: "%s" under %s — %s'
              % (exemption["word"], exemption["path"], exemption["why"]))


def pin_channels(site: Site, channels: dict, report: Report):
    # ONE HOME, and the page map is the written form of it. The two lists left the front
    # door on 15 September 2026 (a dev list on a page a stranger meets is a promise to a
    # stranger; the app keeps those rows behind `#if BETA` for the same reason), so
    # /invite/#coming is the only page that prints them — and a second copy anywhere now
    # fails this check rather than quietly drifting out of step with the first.
    pages = ["invite/index.html"]
    for page in pages:
        for node in marked(site.tree[page], "channels-title"):
            got = text_of(node)
            if got != channels["sectionTitle"]:
                report.fail("web/%s:%d" % (page, node.line), "channels.sectionTitle",
                            "the section heading is not the app's own", got)
        if not marked(site.tree[page], "channels-title"):
            report.fail("web/" + page, "channels.sectionTitle",
                        'no heading marked data-copy="channels-title"')
    report.ok('channels.sectionTitle → "%s" on /invite/' % channels["sectionTitle"])

    for kind in ("beta", "dev"):
        rows = [row["text"] for row in channels[kind]]
        for page in pages:
            lists = marked(site.tree[page], "channels-" + kind)
            if len(lists) != 1:
                report.fail("web/" + page, "channels." + kind,
                            'expected one <ul data-copy="channels-%s">, found %d'
                            % (kind, len(lists)))
                continue
            items = [n for n in lists[0].kids if isinstance(n, Node) and n.tag == "li"]
            pinned = [n for n in items if "extra" not in n.copy_tokens]
            extra = [n for n in items if "extra" in n.copy_tokens]
            if extra and items.index(extra[0]) < len(pinned):
                report.fail("web/%s:%d" % (page, extra[0].line), "channels." + kind,
                            "a data-copy=\"extra\" row comes before a pinned one — the "
                            "JSON's rows come first, in order", text_of(extra[0]))
            if len(pinned) != len(rows):
                report.fail("web/%s:%d" % (page, lists[0].line), "channels." + kind,
                            "%d pinned rows, docs/copy has %d" % (len(pinned), len(rows)),
                            " / ".join(text_of(n) for n in pinned))
                continue
            for node, want in zip(pinned, rows):
                got = text_of(node)
                if got != want:
                    report.fail("web/%s:%d" % (page, node.line), "channels." + kind,
                                "row is not the JSON's sentence", got)
        report.ok("channels.%s → %d rows, in order, on /invite/" % (kind, len(rows)))

    pin_forbidden_doors(site, channels, report)


def pin_forbidden_doors(site: Site, channels: dict, report: Report):
    """No release copy promises a door above the release.

    **Scoped**, and the scope is the point. Site-wide this rule is false: /invite/ and
    /watches/ exist to describe the beta, and /start/ walks a tester through it. It runs
    over the two pages a stranger reads as the product's own claim — the front door and the
    analyzer — with the two channel lists and every `data-copy="beta-door"` element taken
    out first. What is left is the release's own voice.

    The exemptions come from docs/copy/check_release_copy.py's allow map for the same page,
    so the browser analyzer's own .gpx and .tcx support — which is not an iPhone door at
    all — is written down once, with a reason, and printed there.
    """
    targets = {t.path: t for t in release.TARGETS if t.path.startswith("web/")}
    for page in ("index.html", "app/index.html"):
        entry = targets.get("web/" + page)
        if entry is None:
            report.fail("web/" + page, "channels.forbiddenInRelease",
                        "no target for this page in docs/copy/check_release_copy.py")
            continue
        if release.FORBIDDEN_DOORS not in entry.rules:
            # /app/ is the browser analyzer: a different product, no channels, and it reads
            # .gpx and .tcx in the tab the reader already has open. check_release_copy.py
            # says so at the target, which is where that decision belongs.
            report.ok("channels.forbiddenInRelease → web/%s is out of scope by "
                      "check_release_copy.py's own target (%s)" % (page, entry.label))
            continue
        target = entry.allow
        root = parse(site.source[page])
        for node in descendants(root):
            tokens = node.copy_tokens
            if "beta-door" in tokens or any(t.startswith("channels-") for t in tokens):
                node.kids = []
        text = text_of(root, drop_asides=False)
        hits = 0
        for term in channels["forbiddenInRelease"]:
            if term.lower() not in text.lower():
                continue
            if term in target:
                continue
            hits += 1
            report.fail("web/" + page, "channels.forbiddenInRelease",
                        '"%s" is a door this build does not have, outside the channel '
                        'lists and outside any data-copy="beta-door"' % term,
                        nearest(text, term))
        if not hits:
            report.ok("channels.forbiddenInRelease → web/%s clean outside the lists and "
                      "the beta-door marks (%d allowed, see check_release_copy.py)"
                      % (page, len(target)))


def pin_classes(site: Site, classes: dict, report: Report):
    rows = classes["classes"]
    # /watches/#classes ONLY since 15 September 2026. The front door printed the same four
    # rows above a link to this page; it now prints the link and one sentence, and the four
    # pinned cells exist once on the site.
    # THE TABLE IS A SET, NOT A LIST, since 16 September 2026. docs/copy/recording-classes
    # .json is the kit's file and keeps the kit's order (`RecordingClass.allCases`: a, b,
    # bPlus, c); the page prints A, B+, B, C, because on this site Apple Watch comes right
    # after Garmin wherever watches are listed. Both are right, and neither is the other's
    # business — so what is pinned is that the four cells ARE the four rows, and that each
    # name still carries its own line. A page that drops a class, invents a fifth or pairs
    # the B+ name with the C sentence still fails.
    line_of = {row["name"]: row["line"] for row in rows}
    by_name = {row["name"]: row for row in rows}
    for page in ("watches/index.html",):
        names = marked(site.tree[page], "class-name")
        lines = marked(site.tree[page], "class-line")
        for kind, nodes in (("name", names), ("line", lines)):
            if len(nodes) != len(rows):
                report.fail("web/" + page, "recording-classes." + kind,
                            "%d cells marked data-copy=\"class-%s\", docs/copy has %d "
                            "classes" % (len(nodes), kind, len(rows)))
        if len(names) == len(rows) and len(lines) == len(rows):
            got_names = [text_of(node) for node in names]
            if set(got_names) != set(line_of):
                report.fail("web/" + page, "recording-classes.name",
                            "the four cells are not the kit's four classes",
                            "; ".join(sorted(set(got_names) ^ set(line_of))))
            # The name cell and the line cell of one row are the i-th of each list, because
            # a row prints its name before its line and the rows are read in page order.
            for node, name in zip(lines, got_names):
                want = line_of.get(name)
                if want is not None and text_of(node) != want:
                    report.fail("web/%s:%d" % (page, node.line),
                                "recording-classes.%s.line" % by_name[name]["id"],
                                "the cell is not the kit's string", text_of(node))
        report.ok("recording-classes → the four names and four lines in web/%s, in the "
                  "page's own order" % page)

    # The second /watches/ table ("What you ride with…") keeps its own shape and its own
    # columns; what it may not do is invent a class. Its Class cells — the ones the table
    # itself labels `data-th="Class"` — must each open one of the four names.
    letters = {row["name"].split(" · ")[0] for row in rows}
    page = "watches/index.html"
    cells = [n for n in descendants(site.tree[page])
             if n.tag == "td" and n.attrs.get("data-th") == "Class"]
    # A cell may name two classes ("Class B with a FIT, Class C with a GPX"); what it may
    # not do is name a class that is not one of the four, or none at all.
    named = re.compile(r"Class [A-Z]\+?(?![\w+])")
    unknown, silent = set(), []
    for cell in cells:
        spelled = named.findall(text_of(cell))
        if not spelled:
            silent.append(text_of(cell))
        unknown |= set(spelled) - letters
    if not cells:
        report.fail("web/" + page, "recording-classes.name",
                    'the "What you ride with" table has no <td data-th="Class"> cells')
    elif unknown or silent:
        report.fail("web/" + page, "recording-classes.name",
                    "a Class cell names %s"
                    % (", ".join(sorted(unknown)) if unknown
                       else "no class at all: " + "; ".join(silent)))
    else:
        report.ok("recording-classes → the %d Class cells of /watches/'s second table name "
                  "only %s" % (len(cells), ", ".join(sorted(letters))))


def pin_glossary(site: Site, glossary: dict, report: Report):
    page = "learn/index.html"
    entries = glossary["entries"]
    lists = marked(site.tree[page], "glossary")
    if len(lists) != 1:
        report.fail("web/" + page, "glossary",
                    'expected one <dl data-copy="glossary">, found %d' % len(lists))
        return
    terms = [(n, t) for n, t in descendants_marked(lists[0]) if n.tag in ("dt", "dd")]
    pairs, extra_at = [], None
    index = 0
    while index < len(terms):
        dt, dt_tokens = terms[index]
        dd, dd_tokens = terms[index + 1] if index + 1 < len(terms) else (None, frozenset())
        if dt.tag != "dt" or dd is None or dd.tag != "dd":
            report.fail("web/%s:%d" % (page, dt.line), "glossary",
                        "the definition list is not <dt>/<dd> pairs", text_of(dt))
            return
        is_extra = "glossary-extra" in (dt_tokens | dd_tokens)
        if is_extra and extra_at is None:
            extra_at = len(pairs)
        if not is_extra and extra_at is not None:
            report.fail("web/%s:%d" % (page, dt.line), "glossary",
                        "a pinned entry comes after a glossary-extra one — the kit's "
                        "eight come first, in order", text_of(dt))
            return
        pairs.append((dt, dd, is_extra))
        index += 2

    pinned = [p for p in pairs if not p[2]]
    if len(pinned) != len(entries):
        report.fail("web/" + page, "glossary",
                    "%d pinned entries, docs/copy has %d" % (len(pinned), len(entries)),
                    " / ".join(text_of(p[0]) for p in pinned))
        return
    for (dt, dd, _), entry in zip(pinned, entries):
        if text_of(dt) != entry["term"]:
            report.fail("web/%s:%d" % (page, dt.line), "glossary." + entry["id"],
                        "the term is not the kit's", text_of(dt))
        if text_of(dd) != entry["line"]:
            report.fail("web/%s:%d" % (page, dd.line), "glossary." + entry["id"],
                        "the line is not the kit's", text_of(dd))
    extras = [text_of(p[0]) for p in pairs if p[2]]
    report.ok("glossary → the %d terms and lines in web/%s%s"
              % (len(entries), page,
                 ", then %s (site's own)" % ", ".join(extras) if extras else ""))


MAILTO = re.compile(r'href="(mailto:[^"]+)"')


def pin_feedback(site: Site, feedback: dict, report: Report):
    bodies = 0
    for page in PAGES:
        for match in MAILTO.finditer(site.source[page]):
            url = html_module.unescape(match.group(1))
            query = urllib.parse.parse_qs(urllib.parse.urlparse(url).query,
                                          keep_blank_values=True)
            body = (query.get("body") or [""])[0]
            if not body:
                continue
            bodies += 1
            line = site.source[page][:match.start()].count("\n") + 1
            for prompt in feedback["prompts"]:
                if prompt not in body:
                    report.fail("web/%s:%d" % (page, line), "feedback.prompts",
                                "the mail body does not ask %r" % prompt,
                                nearest(body, prompt))
            if feedback["invitation"] not in body:
                report.fail("web/%s:%d" % (page, line), "feedback.invitation",
                            "the mail body does not close with the invitation", body[-120:])
    report.ok("feedback.prompts → the three questions in all %d mailto: bodies" % bodies)

    blocks = [(p, n) for p in PAGES for n in marked(site.tree[p], "feedback-invitation")]
    for page, node in blocks:
        if feedback["invitation"] not in text_of(node):
            report.fail("web/%s:%d" % (page, node.line), "feedback.invitation",
                        "the Tell us block does not say the invitation sentence",
                        text_of(node))
    if not blocks:
        report.fail("web/**", "feedback.invitation",
                    'no block marked data-copy="feedback-invitation"')
    else:
        report.ok("feedback.invitation → %d Tell us blocks" % len(blocks))


def pin_icu(site: Site, icu: dict, report: Report):
    page = "start/index.html"
    root = site.outside_guide(page)
    steps = marked(root, "icu-step")
    titles = [step["title"] for step in icu["steps"]]
    if len(steps) != len(titles):
        report.fail("web/" + page, "icu-setup.steps",
                    "%d elements marked data-copy=\"icu-step\" outside the guide block, "
                    "docs/copy has %d steps" % (len(steps), len(titles)),
                    " / ".join(text_of(n) for n in steps))
    else:
        for node, want in zip(steps, titles):
            got = text_of(node)
            if got != want:
                report.fail("web/%s:%d" % (page, node.line), "icu-setup.steps",
                            "the step title is not the kit's", got)
        report.ok("icu-setup.steps → the four titles on /start/, outside the guide block")

    saves = marked(root, "icu-save")
    if not saves:
        report.fail("web/" + page, "icu-setup.saveButton",
                    'no element marked data-copy="icu-save" outside the guide block')
    else:
        for node in saves:
            got = text_of(node)
            if got != icu["saveButton"]:
                report.fail("web/%s:%d" % (page, node.line), "icu-setup.saveButton",
                            "does not name the button the app shows", got)
        report.ok('icu-setup.saveButton → "%s" on /start/' % icu["saveButton"])


# ------------------------------------------------------------------------------ the run

def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--brief", action="store_true",
                        help="one summary line instead of one line per pin")
    args = parser.parse_args(argv)

    def load(name):
        return json.loads((COPY / name).read_text(encoding="utf-8"))

    phrases = load("phrases.json")
    channels = load("channels.json")
    classes = load("recording-classes.json")
    glossary = load("glossary.json")
    feedback = load("feedback.json")
    icu = load("icu-setup.json")

    site = Site()
    report = Report(args.brief)

    pin_promise(site, phrases, report)
    pin_branding(phrases, report)
    pin_strava(site, phrases, report)
    pin_ciq_title(site, phrases, report)
    pin_appstore_name(site, phrases, report)
    pin_channels(site, channels, report)
    pin_classes(site, classes, report)
    pin_glossary(site, glossary, report)
    pin_feedback(site, feedback, report)
    pin_icu(site, icu, report)
    pin_lexicon(site, phrases, report)

    if report.failures:
        print("\n%d COPY PROBLEM(S) — docs/copy/README.md says who owns each string:"
              % len(report.failures), file=sys.stderr)
        for failure in report.failures:
            print("  " + failure, file=sys.stderr)
        return 1
    print("copy pins: %d checks over %d pages, from 6 files in docs/copy"
          % (report.pins, len(PAGES)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
