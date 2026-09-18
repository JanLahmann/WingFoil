"""Every internal link on the site resolves, and every document is well-formed.

Needs nothing: no browser, no server, no dependency outside the standard library. Run it
after touching any .html under web/ — it is the cheapest of the checks in web/README.md and
the only one that catches the two failures a static site actually dies of, a link to a page
that was renamed and a tag that was never closed.

    python3 web/tools/verify_links.py

WHAT IT CHECKS, per document:

  1. Every relative and root-relative href/src points at a file that exists. A path ending in
     "/" is satisfied by "<path>/index.html", which is how GitHub Pages serves it.
  2. Every same-page "#frag" names an id that is on that page, and every cross-page one names
     an id on the page it lands on.
  3. Tags nest and close. html.parser is not a validator, but an unclosed <section> or a
     </div> too many is exactly the mistake a hand-edited page makes, and it finds those.
  4. The site nav between <!-- sitenav:begin --> and <!-- sitenav:end --> is byte-identical
     on all nine reader-facing documents, once `aria-current="page"` is taken out, and so is
     the footer block between <!-- sitefoot:begin --> and <!-- sitefoot:end -->. Both are
     copied markup rather than a template — this site has no build step — so the only thing
     keeping nine copies in step is this check.

  5. The words. `verify_copy.py --brief` holds every page to `docs/copy/*.json`,
     `make_copy_js.py --check` to the generated `js/copy.js`, and `verify_unique.py --brief`
     to the sentences nobody owns — no prose sentence on two pages, and no page over its
     word budget — the same way `make_start.py` and `make_devices.py` run below: a page that
     has drifted from the copy contract is a link to a promise nobody made, and a page that
     says something twice is a page one of whose copies is already out of date.

WHAT IT DOES NOT: http(s), mailto and the cleanjibe:// scheme are somebody else's to answer
for. And "#example" on /app/ is a ROUTE rather than an anchor (js/app.js runs the bundled
session on arrival), so the analyzer's routes are listed rather than looked up.
"""
import io
import os
import re
import sys
from html.parser import HTMLParser

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # web/

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

SKIP = re.compile(r"^(https?:|mailto:|tel:|data:|javascript:|cleanjibe:|//)", re.I)


class Refs(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.refs = []          # (attr, value)
        self.ids = set()
        self.stack = []
        self.bad_nesting = []
        self.void = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link",
                     "meta", "param", "source", "track", "wbr", "path", "circle", "rect",
                     "line", "polyline", "polygon", "use", "stop", "ellipse"}

    def handle_starttag(self, tag, attrs):
        d = dict(attrs)
        for a in ("href", "src"):
            if a in d and d[a] is not None:
                self.refs.append((a, d[a]))
        if d.get("id"):
            self.ids.add(d["id"])
        if d.get("name") and tag == "a":
            self.ids.add(d["name"])
        if tag not in self.void and not self.get_starttag_text().rstrip().endswith("/>"):
            self.stack.append((tag, self.getpos()))

    def handle_endtag(self, tag):
        if tag in self.void:
            return
        if not self.stack:
            self.bad_nesting.append("</%s> with nothing open at %s" % (tag, self.getpos()))
            return
        if self.stack[-1][0] == tag:
            self.stack.pop()
        else:
            self.bad_nesting.append(
                "</%s> at %s closes <%s> opened at %s"
                % (tag, self.getpos(), self.stack[-1][0], self.stack[-1][1]))
            # resync: pop until we find it, if it is open at all
            for i in range(len(self.stack) - 1, -1, -1):
                if self.stack[i][0] == tag:
                    del self.stack[i:]
                    break


def resolve(page, ref):
    base = os.path.dirname(os.path.join(ROOT, page))
    if ref.startswith("/"):
        target = os.path.join(ROOT, ref.lstrip("/"))
    else:
        target = os.path.normpath(os.path.join(base, ref))
    return target


errors = []
checked = 0

for page in PAGES:
    path = os.path.join(ROOT, page)
    if not os.path.exists(path):
        errors.append("PAGE MISSING: " + page)
        continue
    src = io.open(path, encoding="utf-8").read()
    p = Refs()
    p.feed(src)
    p.close()

    for tag, pos in p.stack:
        errors.append("%s: <%s> opened at %s never closed" % (page, tag, pos))
    for msg in p.bad_nesting:
        errors.append("%s: %s" % (page, msg))

    for attr, ref in p.refs:
        ref = ref.strip()
        if not ref or SKIP.match(ref):
            continue
        checked += 1
        if ref.startswith("#"):
            frag = ref[1:]
            if frag and frag not in p.ids:
                errors.append("%s: %s=\"%s\" -> no such id on this page" % (page, attr, ref))
            continue
        path_part, _, frag = ref.partition("#")
        if not path_part:
            continue
        target = resolve(page, path_part)
        cands = [target]
        if path_part.endswith("/") or os.path.isdir(target):
            cands.append(os.path.join(target, "index.html"))
        if not any(os.path.exists(c) for c in cands):
            errors.append("%s: %s=\"%s\" -> %s does not exist" % (page, attr, ref, target))
            continue
        # cross-page fragment: check it where the target is one of our own pages
        if frag:
            tgt = cands[-1]
            rel = os.path.relpath(tgt, ROOT)
            if rel in PAGES:
                tp = Refs()
                tp.feed(io.open(tgt, encoding="utf-8").read())
                tp.close()
                # `#example` is a ROUTE, not an anchor: js/app.js runs the bundled session
                # on arrival. Same for anything else the analyzer routes on.
                if rel == "app/index.html" and frag in ("example", "library", "trends"):
                    continue
                if frag not in tp.ids:
                    errors.append("%s: %s=\"%s\" -> no id #%s in %s" % (page, attr, ref, frag, rel))

print("pages: %d   internal references checked: %d" % (len(PAGES), checked))

# ---------------------------------------------------------------- the site nav
# One navigation row, copied into nine documents by hand because a static site has nowhere
# to put a partial. The block between the two markers must be the same bytes everywhere;
# the only licensed difference is which link says it is the page you are on.
NAV_PAGES = [p for p in PAGES if p != "strava/callback/index.html"]
NAV_BEGIN = "<!-- sitenav:begin"
NAV_END = "<!-- sitenav:end -->"
CURRENT_ATTR = ' aria-current="page"'

navs = {}
for page in NAV_PAGES:
    path = os.path.join(ROOT, page)
    if not os.path.exists(path):
        continue
    src = io.open(path, encoding="utf-8").read()
    start = src.find(NAV_BEGIN)
    end = src.find(NAV_END)
    if start < 0 or end < 0:
        errors.append("%s: no site nav (<!-- sitenav:begin --> … <!-- sitenav:end -->)" % page)
        continue
    if src.count(NAV_BEGIN) != 1 or src.count(NAV_END) != 1:
        errors.append("%s: the site nav markers appear more than once" % page)
        continue
    block = src[start:end + len(NAV_END)]
    if block.count(CURRENT_ATTR) > 1:
        errors.append('%s: more than one aria-current="page" in the site nav' % page)
    navs[page] = block.replace(CURRENT_ATTR, "")

if navs:
    reference_page = NAV_PAGES[0]
    reference = navs.get(reference_page)
    for page, block in navs.items():
        if reference is not None and block != reference:
            errors.append("%s: the site nav differs from %s — it is copied markup and must "
                          "be byte-identical apart from aria-current" % (page, reference_page))
    print("site nav: identical on %d of %d pages" % (
        sum(1 for b in navs.values() if b == reference), len(NAV_PAGES)))

# ---------------------------------------------------------------- the footer
# The same argument one screen down. Until 15 September 2026 every footer named a different
# subset of the site — /privacy/ three pages, /impressum/ one — and the footer is where a
# reader goes when the sticky bar has scrolled away and when JavaScript never ran. One block,
# copied nine times because a static site has nowhere to put a partial, compared here exactly
# the way the site nav above is. No aria-current: a footer marks no current page.
FOOT_BEGIN = "<!-- sitefoot:begin"
FOOT_END = "<!-- sitefoot:end -->"

feet = {}
for page in NAV_PAGES:
    path = os.path.join(ROOT, page)
    if not os.path.exists(path):
        continue
    src = io.open(path, encoding="utf-8").read()
    start = src.find(FOOT_BEGIN)
    end = src.find(FOOT_END)
    if start < 0 or end < 0:
        errors.append("%s: no footer block (<!-- sitefoot:begin --> … <!-- sitefoot:end -->)"
                      % page)
        continue
    if src.count(FOOT_BEGIN) != 1 or src.count(FOOT_END) != 1:
        errors.append("%s: the footer markers appear more than once" % page)
        continue
    feet[page] = src[start:end + len(FOOT_END)]

if feet:
    reference_page = NAV_PAGES[0]
    reference = feet.get(reference_page)
    for page, block in feet.items():
        if reference is not None and block != reference:
            errors.append("%s: the footer block differs from %s — it is copied markup and "
                          "must be byte-identical" % (page, reference_page))
    print("footer: identical on %d of %d pages" % (
        sum(1 for b in feet.values() if b == reference), len(NAV_PAGES)))

# The generated half of /start/ is a link problem of its own kind: a guide block that no
# longer matches docs/guide/getting-started.json is a page saying something the app does
# not. `make_start.py --check` is stdlib-only and takes milliseconds, so it runs here,
# with the cheapest check the site has.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_start                                                        # noqa: E402

if make_start.main(["--check"]) != 0:
    errors.append("web/start/index.html or GettingStartedGuide.swift is stale — "
                  "run `python3 web/tools/make_start.py`")

# The release notes are the same kind of generated half, on /whats-new/: the cards, the
# app's What's new screen and the TestFlight "What to Test" text are three renderings of
# docs/copy/whats-new.json, and a page that has drifted from it is the changelog disagreeing
# with the app the reader just installed.
import make_whats_new                                                    # noqa: E402

if make_whats_new.main(["--check"]) != 0:
    errors.append("web/whats-new/index.html or WhatsNew.swift is stale — "
                  "run `python3 web/tools/make_whats_new.py`")

# Same argument for the Garmin product count and the watch app's version: five pages print
# them, garmin/manifest.xml decides them, and a page that says 39 products at 0.9.10 when
# the tree ships 42 at 0.9.11 is a link to a watch that will not install.
import make_devices                                                      # noqa: E402

if make_devices.main(["--check"]) != 0:
    errors.append("a garmin-count/garmin-version span is stale — "
                  "run `python3 web/tools/make_devices.py`")

# And the same argument once more for the words themselves. docs/copy holds the sentences
# the app and the site both say; a page that has drifted from one of them is a link to a
# promise nobody made — the beta list that still offered the Garmin export ZIP seven hours
# after it became a release door was exactly that, and it resolved perfectly.
import verify_copy                                                       # noqa: E402

if verify_copy.main(["--brief"]) != 0:
    errors.append("a page has drifted from docs/copy — "
                  "run `python3 web/tools/verify_copy.py` for the list")

# web/js/copy.js is generated from docs/copy too, and a stale one is a session view saying
# something the app does not.
import make_copy_js                                                      # noqa: E402

if make_copy_js.main(["--check"]) != 0:
    errors.append("web/js/copy.js is stale — run `python3 web/tools/make_copy_js.py`")

# And the sentences nobody owns. verify_copy holds the pages to docs/copy; what it cannot
# see is the site's own prose written twice and then corrected once. verify_unique.py is
# that check, plus the per-page word budget that stops /start/ walking back to 3500 words
# one honest paragraph at a time.
import verify_unique                                                     # noqa: E402

if verify_unique.main(["--brief"]) != 0:
    errors.append("a sentence has two homes, or a page is over its word budget — "
                  "run `python3 web/tools/verify_unique.py` for the list")

# The same two questions, asked of the app rather than of the site: is every rider sentence
# inside docs/voice.md (length, dashes, the banned shapes, a paragraph inside its budget),
# and does any sentence have two homes in the kit and the app. They run here because this is
# the one command a web change is checked with, and the app's copy and the site's are the
# same product's words. `CopyLintTests` in ios/WingFoilKit runs both from the Swift side.
sys.path.insert(0, os.path.join(os.path.dirname(ROOT), "docs", "copy"))
import check_voice                                                       # noqa: E402
import check_duplicates                                                  # noqa: E402

if check_voice.main([]) != 0:
    errors.append("a rider sentence is off the voice — "
                  "run `python3 docs/copy/check_voice.py` for the list")

if check_duplicates.main([]) != 0:
    errors.append("a sentence has two homes in the app — "
                  "run `python3 docs/copy/check_duplicates.py` for the list")

if errors:
    print("\n%d PROBLEM(S):" % len(errors))
    for e in errors:
        print("  " + e)
    sys.exit(1)
print("all internal links resolve; no unbalanced tags")
