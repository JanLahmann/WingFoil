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

# The generated half of /start/ is a link problem of its own kind: a guide block that no
# longer matches docs/guide/getting-started.json is a page saying something the app does
# not. `make_start.py --check` is stdlib-only and takes milliseconds, so it runs here,
# with the cheapest check the site has.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_start                                                        # noqa: E402

if make_start.main(["--check"]) != 0:
    errors.append("web/start/index.html or GettingStartedGuide.swift is stale — "
                  "run `python3 web/tools/make_start.py`")

if errors:
    print("\n%d PROBLEM(S):" % len(errors))
    for e in errors:
        print("  " + e)
    sys.exit(1)
print("all internal links resolve; no unbalanced tags")
