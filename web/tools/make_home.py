#!/usr/bin/env python3
"""The cleanjibe.org homepage, rendered from the kit's welcome sections.

    python3 web/tools/make_home.py            # write web/index.html's block and the parity doc
    python3 web/tools/make_home.py --check    # write nothing; exit 1 if either is stale

Jan, 28 September 2026: the homepage and the iPhone app's *What CleanJibe does* share ONE
basis, so the parts they have in common cannot drift. The basis is ``WelcomeSections`` in
the kit (``ios/WingFoilKit/Sources/WingFoilKit/Help/WelcomeSections.swift``), exported to
``docs/copy/welcome.json`` by ``WelcomeSectionsExportTests``
(``COPY_WRITE=1 swift test --filter WelcomeSectionsExportTests``). Every section says where it
is drawn: ``app``, ``web`` or ``both``.

WHAT THIS WRITES

1. ``web/index.html`` between ``<!-- home:begin -->`` and ``<!-- home:end -->``: every
   section marked ``web`` or ``both``, in the kit's order. Three groups are drawn as one
   block each, because on a page they are one thing:

   * **the hero** = ``hero`` + ``legend`` + ``example``: the promise, the three verdicts,
     the example button and the real share card it makes;
   * **the chooser** = ``family`` + ``chooser``: each card prints the family's own line for
     each app it names, so the honest sentence about each app has one home;
   * **trust** = ``trust`` + ``community``.

   The words are the export's. What is this file's own is the markup, the links (a section
   names an action by id, and ``ACTIONS`` below says where each id goes on the web), the
   card's alt text and the watch count, which ``make_devices.py`` owns.
2. ``docs/web-parity/welcome-vs-homepage.md``: the list of differences between the two
   doors, written from ``surfaces``.

WHAT ``--check`` ALSO HOLDS

The app side. ``WelcomeView.swift`` must draw every ``app`` and ``both`` section through
``WelcomeSections`` (a ``case .<id>`` in its switch) and must not type any word a ``both``
section owns as a string literal: a typed copy is the copy that drifts.

Stdlib only; ``verify_links.py`` runs ``--check`` beside ``make_start.py`` and
``make_help.py``.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
from pathlib import Path

WEB = Path(__file__).resolve().parents[1]
REPO = WEB.parent
SOURCE = REPO / "docs" / "copy" / "welcome.json"
PAGE = WEB / "index.html"
PARITY = REPO / "docs" / "web-parity" / "welcome-vs-homepage.md"
WELCOME_VIEW = REPO / "ios" / "WingFoil" / "Features" / "Onboarding" / "WelcomeView.swift"

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_devices                                                      # noqa: E402

BEGIN = "<!-- home:begin -->"
END = "<!-- home:end -->"

TESTFLIGHT = "https://testflight.apple.com/join/nygqGGcn"
CONNECT_IQ = "https://apps.garmin.com/apps/e77867b5-e972-4eb2-be1b-90077cfac806"
GITHUB = "https://github.com/JanLahmann/WingFoil"
#: The footer's own mail, byte for byte: verify_copy.py holds every mailto body to the three
#: prompts and the invitation of docs/copy/feedback.json.
MAIL = ("mailto:info@cleanjibe.org?subject=CleanJibe%20feedback&amp;body=What%20happened%2C%20"
        "or%20what%20you%20would%20like%3A%0A%0A%0AWhat%20you%20expected%20instead%3A%0A%0A%0A"
        "Which%20session%2C%20its%20date%20and%20spot%2C%20if%20it%20is%20about%20one%3A%0A%0A"
        "Your%20watch%20and%20phone%20%28model%2C%20software%20version%29%3A%0A%0ACleanJibe%20"
        "version%20%28Settings%2C%20About%29%3A%0A%0AIdeas%20and%20wishes%20are%20as%20welcome"
        "%20as%20bugs.%20Attach%20a%20screenshot%20or%20the%20session%27s%20.fit%20file%20if%20"
        "you%20can.%0A")

#: Where each action id goes on the web. The app maps the same ids to its own screens.
ACTIONS = {
    "example": "app/#example",
    "browser": "app/",
    "iphone": TESTFLIGHT,
    "garmin": CONNECT_IQ,
    "chooser": "#way-in",
    "guideGarmin": "start/#guide-garmin",
    "watches": "start/#garmin-list",  # the watches by name (rider review S8)
    "mail": MAIL,
    "github": GITHUB,
}

#: The share card's alt text. It names what the picture shows, number for number, because a
#: reader who cannot see the card should get the same session. The numbers are the example
#: session's through engine 0.25; web/tools/hero_card.html says how the picture is made, and
#: an engine bump that moves a number moves this line in the same change.
CARD_ALT = (
    "A real CleanJibe share card: Nago Torbole Wingfoil, 30 August 2026 at 14:07, drawn over "
    "an OpenStreetMap map of the north end of Lake Garda. The whole track, with a green dot "
    "for every jibe flown through and a red one for each fall. A star and 5 clean jibes of "
    "10. 8 flew through, no touchdown, 2 fell in, and a best streak of 8. 28.3 clean jibes "
    "per hour, 45.4 dry jibes per hour, 13.47 knots best 2 seconds, 10 minutes 45 and 2.6 km. "
    "The CleanJibe mark, cleanjibe.org and a QR code in the footer.")

#: The ladder's marks, by the legend's item ids.
MARKS = {"flew": "flew", "touchdown": "touch", "fellIn": "fell",
         "flewThrough": "flew", "clean": "clean"}


def esc(text: str) -> str:
    return html.escape(text, quote=False)


def attr(text: str) -> str:
    return html.escape(text, quote=True)


def inline(text: str, count: str) -> str:
    """Escape, then the two things a kit sentence may carry that the web draws: the watch
    count span make_devices.py keeps current, and a file extension as code."""
    out = esc(text)
    out = out.replace("{garmin-count}", '<span data-copy="garmin-count">%s</span>' % count)
    out = re.sub(r"(?<![\w/])(\.(?:fit|gpx|tcx))\b", r"<code>\1</code>", out)
    return out


def button(action: dict, primary: bool, where: str) -> str:
    href = ACTIONS[action["id"]]
    external = href.startswith("http")
    return ('<a class="btn %s" href="%s"%s data-umami-event="CleanJibe: home-%s-%s">%s</a>'
            % ("primary" if primary else "ghost", href,
               ' rel="noopener"' if external else "", where, action["id"],
               esc(action["title"])))


def buttons(actions: list, where: str, first_primary: bool = True) -> str:
    return "\n".join("        " + button(a, first_primary and i == 0, where)
                     for i, a in enumerate(actions))


def terms(items: list, count: str, cls: str, marks: bool = False) -> str:
    rows = []
    for item in items:
        mark = ""
        if marks:
            kind = MARKS.get(item["id"], "")
            mark = ('<span class="fp-mark fp-mark-%s" aria-hidden="true"></span>' % kind
                    if kind else "")
        rows.append('      <div class="fp-term">\n'
                    '        <dt>%s%s</dt>\n'
                    '        <dd>%s</dd>\n'
                    '      </div>' % (mark, esc(item["term"]), inline(item["detail"], count)))
    return '    <dl class="%s">\n%s\n    </dl>' % (cls, "\n".join(rows))


# ------------------------------------------------------------------ the blocks

def render_hero(hero: dict, legend: dict, example: dict) -> str:
    ladder = "\n".join(
        '        <li><span class="fp-mark fp-mark-%s" aria-hidden="true"></span>%s</li>'
        % (MARKS[item["id"]], esc(item["term"])) for item in legend["items"])
    chooser = hero["actions"][0]
    return f"""  <section class="fp-hero" aria-labelledby="fp-title">
    <div class="fp-hero-copy">
      <p class="fp-kicker">{esc(hero["kicker"])}</p>
      <!-- The promise, split where it asks its question. The wrapper carries the pin, so
           verify_copy.py still reads docs/copy/phrases.json's whole sentence. -->
      <div data-copy="promise">
        <h1 id="fp-title">{esc(hero["title"])}</h1>
        <p class="fp-lede">{esc(hero["lede"])}</p>
      </div>
      <ul class="fp-ladder" aria-label="The three verdicts">
{ladder}
      </ul>
      <p class="fp-cta">
        <a class="btn primary fp-go" href="{ACTIONS["example"]}" data-umami-event="CleanJibe: example-cta">{esc(example["title"])}</a>
        <a class="btn ghost" href="{ACTIONS[chooser["id"]]}" data-umami-event="CleanJibe: home-hero-chooser">{esc(chooser["title"])}</a>
      </p>
      <p class="fp-note">{esc(example["lede"])} {esc(hero["note"])}</p>
    </div>
    <figure class="fp-card">
      <a href="{ACTIONS["example"]}" data-umami-event="CleanJibe: example-card">
        <img src="img/share-card.png" srcset="img/share-card.png 1x, img/share-card@2x.png 2x"
             width="440" height="550" loading="eager" fetchpriority="high" decoding="async"
             alt="{attr(CARD_ALT)}">
      </a>
      <figcaption>{esc(example["note"])}</figcaption>
    </figure>
  </section>"""


def render_get(measures: dict, verdicts: dict, count: str) -> str:
    return f"""  <section class="fp-band fp-get" id="what-you-get">
    <div class="fp-get-col">
    <h2>{esc(measures["title"])}</h2>
{terms(measures["items"], count, "fp-terms")}
    </div>
    <div class="fp-get-col">
    <h2>{esc(verdicts["title"])}</h2>
{terms(verdicts["items"], count, "fp-terms fp-verdicts", marks=True)}
    </div>
  </section>"""


def render_chooser(family: dict, chooser: dict, count: str) -> str:
    apps = {app["id"]: app for app in family["items"]}
    badge = "Beta"
    cards = []
    for item in chooser["items"]:
        lines = "\n".join(
            '          <li><b>%s</b> %s</li>' % (esc(apps[a]["term"]), inline(apps[a]["detail"], count))
            for a in item["apps"])
        pill = ' <span class="tag beta">%s</span>' % badge if item["beta"] else ""
        mark = ' data-copy="beta-door"' if item["beta"] else ""
        cards.append(f"""      <article class="fp-way" id="way-{item["id"]}"{mark}>
        <h3>{esc(item["term"])}{pill}</h3>
        <p>{inline(item["detail"], count)}</p>
        <ul class="fp-apps">
{lines}
        </ul>
        <p class="fp-actions">
{buttons(item["actions"], "way-" + item["id"])}
        </p>
      </article>""")
    return f"""  <section class="fp-band" id="way-in" aria-labelledby="way-in-title">
    <h2 id="way-in-title">{esc(chooser["title"])}</h2>
    <p class="fp-section-lede">{esc(family["lede"])}</p>
    <div class="fp-ways">
{chr(10).join(cards)}
    </div>
    <p class="fp-small">{esc(chooser["note"])}</p>
  </section>"""


def render_list(section: dict, count: str, anchor: str, primary: bool) -> str:
    lede = ('\n    <p class="fp-section-lede">%s</p>' % inline(section["lede"], count)
            if section["lede"] else "")
    note = ('\n    <p class="fp-small">%s</p>' % inline(section["note"], count)
            if section["note"] else "")
    return f"""  <section class="fp-band" id="{anchor}">
    <h2>{esc(section["title"])}</h2>{lede}
{terms(section["items"], count, "fp-terms fp-steps")}{note}
    <p class="fp-actions">
{buttons(section["actions"], anchor, first_primary=primary)}
    </p>
  </section>"""


def render_trust(trust: dict, community: dict, count: str) -> str:
    return f"""  <section class="fp-band fp-trust" id="we-ride-too">
    <h2>{esc(trust["title"])}</h2>
{terms(trust["items"], count, "fp-terms fp-steps")}
    <p class="fp-community">{esc(community["lede"])}</p>
    <p class="fp-actions">
{buttons(trust["actions"], "trust", first_primary=False)}
    </p>
  </section>"""


def render_html(doc: dict, count: str) -> str:
    s = {sec["id"]: sec for sec in doc["sections"]}
    web = [sec["id"] for sec in doc["sections"] if sec["surfaces"] in ("web", "both")]
    # The groups, and the order they are drawn in: the kit's own, a group standing where
    # its first member stands.
    groups = {
        "hero": ("hero", "legend", "example"),
        "measures": ("measures", "verdicts"),
        "family": ("family", "chooser"),
        "oldSessions": ("oldSessions",),
        "watchApp": ("watchApp",),
        "trust": ("trust", "community"),
    }
    grouped = [m for g in groups.values() for m in g]
    missing = [i for i in web if i not in grouped]
    if missing:
        raise SystemExit("web sections with no renderer in make_home.py: " + ", ".join(missing))
    order = [i for i in web if i in groups]
    for lead, members in groups.items():
        if list(members) != [i for i in web if i in members]:
            raise SystemExit("make_home.py: the %s group is not in the kit's order" % lead)
    blocks = {
        "hero": lambda: render_hero(s["hero"], s["legend"], s["example"]),
        "measures": lambda: render_get(s["measures"], s["verdicts"], count),
        "family": lambda: render_chooser(s["family"], s["chooser"], count),
        "oldSessions": lambda: render_list(s["oldSessions"], count, "old-sessions", primary=False),
        "watchApp": lambda: render_list(s["watchApp"], count, "watch-app", primary=True),
        "trust": lambda: render_trust(s["trust"], s["community"], count),
    }
    body = "\n\n".join(blocks[g]() for g in order)
    return (BEGIN + "\n"
            "  <!-- GENERATED by web/tools/make_home.py from docs/copy/welcome.json, the kit's\n"
            "       WelcomeSections: the same list the app's What CleanJibe does is drawn\n"
            "       from. Do not edit between the markers: change the kit, re-export, and\n"
            "       regenerate. `make_home.py --check` fails while this block is stale. -->\n\n"
            + body + "\n  " + END)


def splice(page: str, block: str) -> str:
    start, end = page.find(BEGIN), page.find(END)
    if start < 0 or end < 0:
        raise SystemExit("web/index.html: no %s … %s block" % (BEGIN, END))
    return page[:start] + block + page[end + len(END):]


# ------------------------------------------------------------------ the parity doc

WHERE = {"both": "both", "app": "app only", "web": "homepage only"}
HOW_WEB = {
    "hero": "the hero: the tagline over the promise, split at its question",
    "legend": "the three verdicts under the promise, as coloured marks",
    "example": "the hero's first button, the line under it, and the card's caption",
    "measures": "What you get, left column",
    "verdicts": "What you get, right column, with the clean star",
    "family": "inside the chooser: its intro is the lede, each card prints its apps' lines",
    "chooser": "Which way in is yours?, one card per rider's kit",
    "oldSessions": "its own band",
    "watchApp": "its own band, with the watch count make_devices.py keeps",
    "trust": "the last band",
    "community": "the last band's closing sentence",
}
HOW_APP = {
    "identity": "the mark, the name, the tagline and one paragraph",
    "legend": "under the track drawing",
    "example": "the green button, its line, and the small card beside its caption",
    "measures": "the vocabulary card",
    "getStarted": "the white button that opens Getting started",
    "family": "the family cards, with the app it is marked as this one",
    "community": "the footer's first sentence",
    "footerLinks": "the footer's second sentence, release or beta wording",
}


def render_parity(doc: dict) -> str:
    rows = []
    for sec in doc["sections"]:
        rows.append("| `%s` | %s | %s | %s |" % (
            sec["id"], WHERE[sec["surfaces"]],
            HOW_APP.get(sec["id"], "—") if sec["surfaces"] != "web" else "—",
            HOW_WEB.get(sec["id"], "—") if sec["surfaces"] != "app" else "—"))
    both = [sec["id"] for sec in doc["sections"] if sec["surfaces"] == "both"]
    return f"""# What CleanJibe does vs the homepage

GENERATED by `web/tools/make_home.py` from `docs/copy/welcome.json` (the kit's
`WelcomeSections`). Do not edit by hand: change the kit, re-export
(`COPY_WRITE=1 swift test --filter WelcomeSectionsExportTests`), and run
`python3 web/tools/make_home.py`.

The iPhone app's *What CleanJibe does* and the cleanjibe.org homepage are drawn from one
ordered list of sections (Jan, 28 September 2026). A section marked **both** prints the same
words on both doors; `make_home.py --check` fails when the homepage's block is stale, and
when `WelcomeView.swift` types a word a shared section owns instead of reading the kit.

**Shared:** {", ".join("`%s`" % i for i in both)}.

| section | drawn on | in the app | on the homepage |
|---|---|---|---|
{chr(10).join(rows)}

## What is the homepage's own, and why

- **The hero leads with the question.** A stranger arrives with one, so the promise is the
  headline; the app opens on its identity, because the rider there already has the app.
- **The chooser replaces Get started.** A visitor has not picked an app yet. Each card names
  a rider's kit, the apps that fit it, in the family's own words, and the buttons.
- **Old sessions, the watch app, trust.** A reader deciding whether to install needs these;
  a rider inside the app has already decided.
- **Links, the card's alt text, the watch count.** Markup, not words: a section names its
  actions by id, and `make_home.py` says where each goes on the web.

## What is the app's own, and why

- **Identity, Get started and the menu path.** The app names its own menu and its own
  Getting started; the web has neither.
"""


# ------------------------------------------------------------------ the app side

LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')


def app_problems(doc: dict) -> list[str]:
    source = WELCOME_VIEW.read_text(encoding="utf-8")
    problems = []
    literals = set(LITERAL.findall(source))
    for sec in doc["sections"]:
        if sec["surfaces"] == "web":
            continue
        if not re.search(r"case[^\n]*\.%s\b" % re.escape(sec["id"]), source):
            problems.append("%s: no `case .%s` in view(for:) — the app does not draw the "
                            "kit's section" % (WELCOME_VIEW.relative_to(REPO), sec["id"]))
        if sec["surfaces"] != "both":
            continue
        words = [sec["kicker"], sec["title"], sec["lede"], sec["note"]]
        words += [w for item in sec["items"] for w in (item["term"], item["detail"])]
        for word in words:
            if word and word in literals:
                problems.append('%s types "%s", which the `%s` section owns — read it from '
                                'WelcomeSections' % (WELCOME_VIEW.relative_to(REPO), word,
                                                     sec["id"]))
    return problems


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true",
                    help="write nothing; exit 1 if the page or the parity doc is stale")
    args = ap.parse_args(argv)

    doc = json.loads(SOURCE.read_text(encoding="utf-8"))
    count = str(make_devices.read_store()[1])
    page = splice(PAGE.read_text(encoding="utf-8"), render_html(doc, count))
    parity = render_parity(doc)

    problems = app_problems(doc)
    stale = []
    if PAGE.read_text(encoding="utf-8") != page:
        stale.append(PAGE)
    if not PARITY.exists() or PARITY.read_text(encoding="utf-8") != parity:
        stale.append(PARITY)

    if args.check:
        for line in problems:
            print("  " + line, file=sys.stderr)
        if stale:
            print("stale, run `python3 web/tools/make_home.py`:", file=sys.stderr)
            for path in stale:
                print("  %s" % path.relative_to(REPO), file=sys.stderr)
        if stale or problems:
            return 1
        shared = sum(1 for sec in doc["sections"] if sec["surfaces"] == "both")
        print("homepage: %d sections from docs/copy/welcome.json, %d shared with the app's "
              "What CleanJibe does, none typed twice" %
              (sum(1 for sec in doc["sections"] if sec["surfaces"] != "app"), shared))
        return 0

    if problems:
        for line in problems:
            print("  " + line, file=sys.stderr)
        return 1
    PAGE.write_text(page, encoding="utf-8")
    PARITY.parent.mkdir(parents=True, exist_ok=True)
    PARITY.write_text(parity, encoding="utf-8")
    print("wrote %s and %s" % (PAGE.relative_to(REPO), PARITY.relative_to(REPO)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
