#!/usr/bin/env python3
"""The Garmin product list has one source: the three Connect IQ manifests.

    python3 web/tools/make_devices.py            # write the JSON, the list, the web spans
    python3 web/tools/make_devices.py --check    # exit 1 if the JSON or a page is stale

Source: ``garmin/manifest.xml`` and its ``-beta`` / ``-dev`` twins. All three ship the same
binary under three app ids (docs/channels.md, "The watch — the same three streams"). The
beta and dev sets are asserted **identical**, and the release set a **subset** of them: a
watch nobody has ridden yet goes to the beta and dev manifests first and reaches the release
once a real wrist has proved it (0.9.23, rider review S8: the fenix 6 Pro family and the
Forerunner 245 Music / 945 / 945 LTE). Anything else is a jungle edited by halves. The JSON
lists the beta set, which is what the public listing installs, with ``betaOnly`` naming the
watches the release does not have yet.

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

THE WATCHES BY NAME, since 9 October 2026 (rider review S8: "The store says my fenix 6 is not
compatible, and the site never says what to do then"). /start/#watches printed the count and
sent the reader to the store; it prints every watch by family now, between
``<!-- devices:begin -->`` and ``<!-- devices:end -->``, and ends on what to do when yours is
not there. The names are ``MODELS`` and ``ALSO`` below — Garmin's own device names out of the
Connect IQ SDK's ``compiler.json``, in this site's spelling — and the JSON carries them as
``models``. A product id in the manifests with no name here fails the run, so a watch added
to the jungles cannot reach the store without reaching the page. ``ALSO`` is the watches that
install under another one's id (a quatix 7 is a fenix 7 to the store), listed in their own
family, because a rider looks for the name on his wrist.

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
    ("fenix 6 Pro", ("fenix6",)),
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

# Every product id, by the name a rider knows it by: Garmin's device name from the Connect IQ
# SDK (`Devices/<id>/compiler.json` → displayName), trademarks dropped, "fēnix" spelled the
# way this site spells it, and no brackets (docs/voice.md, rule 4). The order inside a family
# is the order of this table.
MODELS = {
    "fenix843mm": "fenix 8 43 mm",
    "fenix847mm": "fenix 8 47 mm and 51 mm",
    "fenix8solar47mm": "fenix 8 Solar 47 mm",
    "fenix8solar51mm": "fenix 8 Solar 51 mm",
    "fenix8pro47mm": "fenix 8 Pro 47 mm and 51 mm, and fenix 8 MicroLED",
    "fenix7": "fenix 7",
    "fenix7s": "fenix 7S",
    "fenix7x": "fenix 7X",
    "fenix7pro": "fenix 7 Pro",
    "fenix7spro": "fenix 7S Pro",
    "fenix7xpro": "fenix 7X Pro",
    "fenix7pronowifi": "fenix 7 Pro Solar without Wi-Fi",
    "fenix7xpronowifi": "fenix 7X Pro Solar without Wi-Fi",
    "fenix6pro": "fenix 6 Pro, 6 Sapphire, 6 Pro Solar and 6 Pro Dual Power",
    "fenix6spro": "fenix 6S Pro, 6S Sapphire, 6S Pro Solar and 6S Pro Dual Power",
    "fenix6xpro": "fenix 6X Pro, 6X Sapphire and 6X Pro Solar",
    "fenix5plus": "fenix 5 Plus",
    "fenix5splus": "fenix 5S Plus",
    "fenix5xplus": "fenix 5X Plus",
    "epix2": "epix Gen 2",
    "epix2pro42mm": "epix Pro Gen 2 42 mm",
    "epix2pro47mm": "epix Pro Gen 2 47 mm",
    "epix2pro51mm": "epix Pro Gen 2 51 mm",
    "fr245m": "Forerunner 245 Music",
    "fr945": "Forerunner 945",
    "fr945lte": "Forerunner 945 LTE",
    "fr255": "Forerunner 255",
    "fr265": "Forerunner 265",
    "fr57042mm": "Forerunner 570 42 mm",
    "fr57047mm": "Forerunner 570 47 mm",
    "fr955": "Forerunner 955 and 955 Solar",
    "fr965": "Forerunner 965",
    "fr970": "Forerunner 970",
    "marq2": "MARQ Gen 2 Athlete, Adventurer, Captain, Golfer, Carbon and Commander",
    "marq2aviator": "MARQ Gen 2 Aviator",
    "enduro3": "Enduro 3",
    "d2mach1": "D2 Mach 1",
    "d2mach2": "D2 Mach 2",
    "descentmk343mm": "Descent Mk3 43 mm and Mk3i 43 mm",
    "venu2": "Venu 2",
    "venu2s": "Venu 2S",
    "venu2plus": "Venu 2 Plus",
    "venu3": "Venu 3",
    "venu3s": "Venu 3S",
    "vivoactive5": "vívoactive 5",
    "vivoactive6": "vívoactive 6",
    "instinct3amoled45mm": "Instinct 3 AMOLED 45 mm",
    "instinct3amoled50mm": "Instinct 3 AMOLED 50 mm",
}

# The watches that install under another one's product id, as the SDK's displayName lists
# them: (family, name). They are the same binary on the same hardware, so they are on the
# list — under the name on the rider's wrist, in the family he would look in.
ALSO = {
    "fenix847mm": [("tactix / quatix", "tactix 8 47 mm and 51 mm"),
                   ("tactix / quatix", "quatix 8 47 mm and 51 mm")],
    "fenix8solar51mm": [("tactix / quatix", "tactix 8 Solar 51 mm")],
    "fenix8pro47mm": [("tactix / quatix", "quatix 8 Pro 47 mm and 51 mm")],
    "fenix7": [("tactix / quatix", "quatix 7")],
    "fenix7x": [("tactix / quatix", "tactix 7"), ("tactix / quatix", "quatix 7X Solar"),
                ("Enduro", "Enduro 2")],
    "epix2": [("tactix / quatix", "quatix 7 Sapphire")],
    "fenix6pro": [("tactix / quatix", "quatix 6")],
    "fenix6xpro": [("tactix / quatix", "tactix Delta Sapphire, Solar and Solar Ballistics"),
                   ("tactix / quatix", "quatix 6X, 6X Solar and 6X Dual Power")],
    "epix2pro47mm": [("tactix / quatix", "quatix 7 Pro")],
    "epix2pro51mm": [("tactix / quatix", "tactix 7 AMOLED"), ("D2", "D2 Mach 1 Pro")],
}

# The list on /start/#watches, between these two markers, and what the reader does when his
# watch is not on it (Jan, 9 Oct 2026: the stock profile still gets every verdict).
LIST_PAGE = "start/index.html"
LIST_BEGIN = "<!-- devices:begin -->"
LIST_END = "<!-- devices:end -->"
NOT_LISTED = ("Not on the list? Ride with Garmin's Windsurf profile. "
              "You still get every verdict.")

# The pages that print the number or the version, and which of the two each one owes.
# A page listed for a kind must carry at least one span of it, and every span it carries
# must say what the manifests say.
# /invite/ became a redirect on 20 September 2026 and its install panel is /start/#apps,
# which already owed both spans for the "Which watch" table further down the same page.
PAGES = {
    "index.html": ("count",),
    "start/index.html": ("count", "version"),
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
    version, min_api, release_ids = read_manifest(MANIFESTS[0])
    _, _, ids = read_manifest(MANIFESTS[1])
    base = set(ids)
    not_in_beta = sorted(set(release_ids) - base)
    if not_in_beta:
        raise SystemExit("%s lists watches %s does not: %s" % (
            MANIFESTS[0].relative_to(REPO), MANIFESTS[1].relative_to(REPO),
            ", ".join(not_in_beta)))
    for path in MANIFESTS[1:]:
        v, m, other_ids = read_manifest(path)
        if set(other_ids) != base:
            missing = sorted(base - set(other_ids))
            extra = sorted(set(other_ids) - base)
            raise SystemExit(
                "%s lists a different product set than %s%s%s" % (
                    path.relative_to(REPO), MANIFESTS[1].relative_to(REPO),
                    ("\n  missing: " + ", ".join(missing)) if missing else "",
                    ("\n  extra:   " + ", ".join(extra)) if extra else ""))
        if (v, m) != (version, min_api):
            raise SystemExit(
                "%s is %s / minApiLevel %s, %s is %s / %s — garmin/tools/package.sh "
                "refuses to run on that too" % (
                    path.relative_to(REPO), v, m,
                    MANIFESTS[0].relative_to(REPO), version, min_api))

    families, other = group(ids)
    unnamed = sorted(pid for pid in ids if pid not in MODELS)
    if unnamed:
        raise SystemExit("product ids with no name in make_devices.py MODELS: "
                         + ", ".join(unnamed)
                         + " — take the displayName from the SDK's Devices/<id>/compiler.json")
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
        "betaOnly": sorted(base - set(release_ids)),
        "families": families,
        "models": models(ids),
    }
    if other:
        doc["families"]["other"] = other
    return doc


def models(ids):
    """{family: [model names]} — every product by its name, plus the ones that share its id."""
    present = set(ids)
    out = dict((name, []) for name, _ in FAMILIES)
    families, _ = group(ids)
    family_of = dict((pid, fam) for fam, pids in families.items() for pid in pids)
    for pid, name in MODELS.items():
        if pid in present:
            out[family_of.get(pid, "other")].append(name)
    for pid, extra in ALSO.items():
        if pid in present:
            for fam, name in extra:
                out[fam].append(name)
    return dict((fam, names) for fam, names in out.items() if names)


def html_text(text):
    return (text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            .replace("'", "&rsquo;").replace("í", "&iacute;"))


def render_list(doc):
    """The block on /start/#watches: a term per family, its watches, and the way round."""
    lines = [
        LIST_BEGIN,
        "    <!-- GENERATED by web/tools/make_devices.py from garmin/manifest*.xml, through",
        "         docs/copy/garmin-devices.json `models`. Do not edit between the markers:",
        "         regenerate, and `make_devices.py --check` fails while it is stale. The list is",
        "         the tree's, which is the store's whenever the two counts agree. -->",
        '    <h3 id="garmin-list">The Garmin watches, by family</h3>',
        '    <dl class="terms device-list">',
    ]
    for family, names in doc["models"].items():
        lines += [
            '      <div class="term">',
            "        <dt>%s</dt>" % html_text(family),
            # One <li> a watch, and the list marked `garmin-models`: a model name is a
            # name, not a sentence, so docs/copy/check_voice.py skips it the way it skips
            # the generated count and version spans.
            '        <dd><ul class="device-models" data-copy="garmin-models">%s</ul></dd>'
            % "".join("<li>%s</li>" % html_text(n) for n in names),
            "      </div>",
        ]
    lines += [
        "    </dl>",
        '    <p class="note"><strong>%s</strong> <a href="#guide-garmin">The Garmin card</a> '
        "shows how.</p>" % html_text(NOT_LISTED),
        "    " + LIST_END,
    ]
    return "\n".join(lines)


def splice_list(src, block):
    start, end = src.find(LIST_BEGIN), src.find(LIST_END)
    if start < 0 or end < 0:
        raise SystemExit("web/%s: the %s / %s markers are not both there"
                         % (LIST_PAGE, LIST_BEGIN, LIST_END))
    return src[:start] + block + src[end + len(LIST_END):]


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
    list_src = (WEB / LIST_PAGE).read_text(encoding="utf-8")
    if splice_list(list_src, render_list(doc)) != list_src:
        stale.append("web/%s: the Garmin list between %s and %s is stale"
                     % (LIST_PAGE, LIST_BEGIN, LIST_END))

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
        if page == LIST_PAGE:
            new = splice_list(new, render_list(doc))
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
