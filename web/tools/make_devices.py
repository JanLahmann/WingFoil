#!/usr/bin/env python3
"""The Garmin product list has one source: the three Connect IQ manifests.

    python3 web/tools/make_devices.py            # write the JSON, rewrite the web spans
    python3 web/tools/make_devices.py --check    # exit 1 if the JSON or a page is stale

Source: ``garmin/manifest.xml`` and its ``-beta`` / ``-dev`` twins. All three ship the same
binary to the same watches under three app ids (docs/channels.md, "The watch — the same
three streams"), so the three product sets are asserted **identical** here: a product added
to one jungle and not the others is a watch that can install the beta and not the release,
which is the kind of thing nobody notices until a rider writes in.

Output: ``docs/copy/garmin-devices.json`` — the version, the count, the minimum Connect IQ
level, the product ids in sorted order, and the ids grouped into the families
``web/watches/`` prints. ``docs/presentation.md`` used to say the product list was "kept in
step with garmin/manifest.xml by hand"; on 15 September 2026 the tree shipped 42 products at
0.9.11 and five web pages still said 39 at 0.9.10. This is the file that ends that.

The pages that print them moved on 19 September 2026: /watches/ and /whats-new/ were
absorbed by /start/ and /invite/, and /learn/ became /help/, which prints no count at all —
the Garmin family table on /watches/ became **one generated sentence** on /start/#watches,
because thirteen rows of model names on a marketing page is the Connect IQ listing typed
out by hand, and the store's install button is the only honest answer to "is mine on the
list".

Consumers: the three pages that name the number or the version carry it in a
``<span data-copy="garmin-count">`` / ``<span data-copy="garmin-version">`` so the check can
be exact rather than a guess at the surrounding prose, and so a bump rewrites them rather
than asking somebody to remember six places. ``web/tools/verify_links.py`` runs ``--check``
the same way it runs ``make_start.py --check``.

Note on ``tactix / quatix``: those watches have **no product id of their own** — Garmin
ships them under the fenix 7X, fenix 7 Pro and epix 2 ids (see the manifest's own comments),
so the family is declared and empty on purpose rather than missing.

Stdlib only, on purpose: it runs with plain ``python3`` beside ``verify_links.py``.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

WEB = Path(__file__).resolve().parents[1]
REPO = WEB.parent

MANIFESTS = [
    REPO / "garmin" / "manifest.xml",
    REPO / "garmin" / "manifest-beta.xml",
    REPO / "garmin" / "manifest-dev.xml",
]
OUT = REPO / "docs" / "copy" / "garmin-devices.json"

IQ = "{http://www.garmin.com/xml/connectiq}"

# Family name -> the id prefixes Garmin uses for it, most specific first. The names are the
# ones the table on /watches/ prints, spelled the way Garmin spells them (the accent in
# "vívoactive" included).
FAMILIES = [
    ("fenix 8", ("fenix8",)),
    ("fenix 7", ("fenix7",)),
    ("fenix 5 Plus", ("fenix5plus", "fenix5splus", "fenix5xplus")),
    ("epix 2", ("epix2",)),
    ("Forerunner", ("fr",)),
    ("MARQ 2", ("marq2",)),
    ("Enduro", ("enduro",)),
    ("D2", ("d2",)),
    ("Descent", ("descent",)),
    ("Venu", ("venu",)),
    ("vívoactive", ("vivoactive",)),
    ("Instinct 3 AMOLED", ("instinct3amoled",)),
    ("tactix / quatix", ("tactix", "quatix")),
]

# The pages that print the number or the version, and which of the two each one owes.
# A page listed for a kind must carry at least one span of it, and every span it carries
# must say what the manifests say.
PAGES = {
    "index.html": ("count",),
    "start/index.html": ("count", "version"),
    "invite/index.html": ("count", "version"),
}

# What the PUBLIC listing installs today, which is not always the tree: a version sits on the
# private dev listing for Jan's water test before it reaches the open beta. The spans on the
# pages say what a rider can install, so they take the store's version and count; the JSON
# carries both. The store line is the header of garmin/store/listing.md, kept in this shape:
#   * Type: device app · Version **0.9.10** on the store, **39** products (…)
LISTING = REPO / "garmin" / "store" / "listing.md"
STORE_LINE = re.compile(r"Version \*\*([0-9.]+)\*\* on the store, \*\*(\d+)\*\* products")

SPAN = re.compile(r'(<span data-copy="garmin-(count|version)">)([^<]*)(</span>)')


def read_manifest(path):
    """(version, minApiLevel, product ids) out of one manifest."""
    app = ET.parse(path).getroot().find(IQ + "application")
    if app is None:
        raise SystemExit("%s: no <iq:application>" % path)
    ids = [p.get("id") for p in app.iter(IQ + "product")]
    return app.get("version", ""), app.get("minApiLevel", ""), ids


def group(ids):
    families = dict((name, []) for name, _ in FAMILIES)
    other = []
    for pid in ids:
        for name, prefixes in FAMILIES:
            if any(pid.startswith(p) for p in prefixes):
                families[name].append(pid)
                break
        else:
            other.append(pid)
    for name in families:
        families[name].sort()
    return families, sorted(other)


def read_store():
    """(version, count) the public Connect IQ listing offers today, from listing.md's header."""
    m = STORE_LINE.search(LISTING.read_text(encoding="utf-8"))
    if not m:
        raise SystemExit("%s: no 'Version **x** on the store, **n** products' line"
                         % LISTING.relative_to(REPO))
    return m.group(1), int(m.group(2))


def build():
    version, min_api, ids = read_manifest(MANIFESTS[0])
    base = set(ids)
    for path in MANIFESTS[1:]:
        v, m, other_ids = read_manifest(path)
        if set(other_ids) != base:
            missing = sorted(base - set(other_ids))
            extra = sorted(set(other_ids) - base)
            raise SystemExit(
                "%s lists a different product set than %s%s%s" % (
                    path.relative_to(REPO), MANIFESTS[0].relative_to(REPO),
                    ("\n  missing: " + ", ".join(missing)) if missing else "",
                    ("\n  extra:   " + ", ".join(extra)) if extra else ""))
        if (v, m) != (version, min_api):
            raise SystemExit(
                "%s is %s / minApiLevel %s, %s is %s / %s — garmin/tools/package.sh "
                "refuses to run on that too" % (
                    path.relative_to(REPO), v, m,
                    MANIFESTS[0].relative_to(REPO), version, min_api))

    families, other = group(ids)
    if other:
        print("UNGROUPED product ids (add a family in make_devices.py FAMILIES): "
              + ", ".join(other), file=sys.stderr)
    store = read_store()
    doc = {
        "version": version,
        "count": len(ids),
        "minApiLevel": min_api,
        "store": {"version": store[0], "count": store[1]},
        "products": sorted(ids),
        "families": families,
    }
    if other:
        doc["families"]["other"] = other
    return doc


def render(doc):
    return json.dumps(doc, indent=2, ensure_ascii=False) + "\n"


def rewrite(page_src, count, version):
    def sub(m):
        value = count if m.group(2) == "count" else version
        return m.group(1) + value + m.group(4)
    return SPAN.sub(sub, page_src)


def page_problems(page, src, owes, count, version):
    found = {"count": 0, "version": 0}
    bad = []
    for m in SPAN.finditer(src):
        kind, text = m.group(2), m.group(3)
        found[kind] += 1
        want = count if kind == "count" else version
        if text != want:
            bad.append('web/%s: <span data-copy="garmin-%s"> says "%s", '
                       'the store listing says "%s"' % (page, kind, text, want))
    for kind in owes:
        if not found[kind]:
            bad.append('web/%s: no <span data-copy="garmin-%s"> on the page'
                       % (page, kind))
    return bad


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true",
                    help="exit 1 if the JSON or any of the three pages is stale")
    args = ap.parse_args(argv)

    doc = build()
    text = render(doc)
    # The pages print what the store installs; the tree's own numbers stay in the JSON.
    count, version = str(doc["store"]["count"]), doc["store"]["version"]

    stale = []
    if not OUT.exists() or OUT.read_text(encoding="utf-8") != text:
        stale.append("%s is stale" % OUT.relative_to(REPO))
    for page, owes in PAGES.items():
        src = (WEB / page).read_text(encoding="utf-8")
        stale += page_problems(page, src, owes, count, version)

    if args.check:
        if stale:
            print("stale, run `python3 web/tools/make_devices.py`:", file=sys.stderr)
            for line in stale:
                print("  " + line, file=sys.stderr)
            return 1
        tree = "" if doc["version"] == version else " (tree: %s, %d products)" % (
            doc["version"], doc["count"])
        print("garmin devices: the store's %s products at %s on all %d pages%s"
              % (count, version, len(PAGES), tree))
        return 0

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text, encoding="utf-8")
    touched = []
    for page in PAGES:
        path = WEB / page
        src = path.read_text(encoding="utf-8")
        new = rewrite(src, count, version)
        if new != src:
            path.write_text(new, encoding="utf-8")
            touched.append("web/" + page)
    named = ", ".join("%s (%d)" % (n, len(v)) for n, v in doc["families"].items() if v)
    print("wrote %s: tree %s products at %s — %s; store %s at %s"
          % (OUT.relative_to(REPO), doc["count"], doc["version"], named, count, version))
    if touched:
        print("rewrote " + ", ".join(touched))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
