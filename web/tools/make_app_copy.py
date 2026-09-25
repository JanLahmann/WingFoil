#!/usr/bin/env python3
"""``web/js/appcopy.js`` — the shell's own words, generated from docs/.

    python3 web/tools/make_app_copy.py            # write web/js/appcopy.js
    python3 web/tools/make_app_copy.py --check    # exit 1 if it is stale

The same argument ``make_copy_js.py`` makes, for the strings the browser app's SHELL has to
render rather than the ones a session view has to say: there is no build step on this site
and no JSON fetch on the app path, so the lists are inlined here and ``verify_links.py``
fails while the file is stale. Stdlib only.

WHAT IS IN IT

  ``SHELL``      docs/copy/app-shell.json: the four tabs, the six menu rows, the four
                 session sub-tabs, the family section and the Beta page (with
                 docs/copy/channels.json's beta rows as its list), in the iPhone app's
                 own order and words. The Swift side is the author;
                 ``web/tools/verify_app_shell.py`` holds them against ``RootView.swift``,
                 ``AppMenuRows.swift``, ``SessionSection.swift``, ``CleanJibeFamily.swift``
                 and ``BetaGuide.swift`` so neither side can drift alone.
  ``WAYS_IN``    the empty Sessions tab. The ORDER and the TITLES are
                 docs/guide/getting-started.json's (pattern J: the ways in have one order
                 everywhere); the one line under each, and the two rows the phone does not
                 have, are docs/copy/app-shell.json's. Every row carries the ``/start/``
                 route it belongs to.
  ``GUIDE``      the same routes again, as the welcome screen's "Getting started" list:
                 title, status and summary out of the guide, with the same hrefs. Nothing
                 here is retyped — ``make_start.py`` writes /start/ from this file and this
                 reads it.
  ``SETTINGS``   the one sentence at the top of the intervals.icu and Strava sections, out
                 of the guide's ``settings`` block — the same two the phone's own Settings
                 prints (``GettingStartedGuide.settingsIcu`` / ``.settingsStrava``).
  ``SETTINGS_SECTIONS``
                 docs/copy/settings.json: every Settings section the phone has, in the
                 order ``SettingsView`` draws it, with the phone's header, the one-line
                 ``lead`` a rider reads by default, the phone's own footer paragraphs for
                 the *extensive* reading, and the help topic its ``?`` opens. The kit is
                 the author (``SettingsCopy``, exported by ``SettingsCopyExportTests``), so
                 the browser cannot write a second wording of a switch the phone already
                 explains (docs/review-checklist.md, pattern F). ``phoneOnly`` marks a
                 section a browser cannot do; the page draws its header and its line and
                 says where it is. ``storage`` and ``backup`` are left out, because the
                 browser's **Your data** is both of them and stands in their place.
  ``WELCOME``    docs/copy/phrases.json's ``headline`` and the four glossary ids the kit's
                 ``WelcomeGuide.highlights`` selects. The lines themselves come from
                 ``js/copy.js``'s ``GLOSSARY`` at run time, so the eleven words have one
                 home on this side of the site as well.
  ``WHATS_NEW``  docs/copy/whats-new.json, release and beta entries only — the same
                 ``WEB_CHANNELS`` filter ``make_whats_new.py`` applies to /whats-new/. A dev
                 card would name a door a handful of testers have.
  ``HELP``       docs/copy/help.json, rendered by the app's Help page.
  ``FEEDBACK``   docs/copy/feedback.json: the invitation, the three prompts, the subject
                 prefix and the door names. The footer's mail and the menu's Support row are
                 composed from them rather than typed.

WHY THE TEXT IS HERE AND NOT IN THE PAGE: ``docs/copy/check_voice.py`` reads
``web/app/index.html`` as a rider surface and fails a hand-typed date or build number
(``STALE``). What's New is nothing but dates and build numbers, so it is rendered from this
module at run time, where it is the generator's fact rather than an author's.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

WEB = Path(__file__).resolve().parents[1]
REPO = WEB.parent
COPY = REPO / "docs" / "copy"
GUIDE = REPO / "docs" / "guide" / "getting-started.json"
OUT = WEB / "js" / "appcopy.js"

#: What /whats-new/ may print, and therefore what the app may. `make_whats_new.WEB_CHANNELS`
#: is the author of this rule; it is repeated rather than imported so this generator stays a
#: file anybody can read top to bottom.
WEB_CHANNELS = ("release", "beta")

#: The route a ways-in row links to on the website. One place, so a renamed page is one edit.
START_ROUTE = "/start/#guide-%s"

#: The phone's Settings sections the browser answers under a name of its own, so they are
#: not drawn twice. **Your data** is Storage plus Library backup plus the site data only a
#: tab can lose a library to (docs/screens.md, deviation 18), and it sits where the two of
#: them sit in the phone's order. ``verify_app_shell.py`` holds the same list.
WEB_TWINS = ("storage", "backup")

HEADER = '''/* GENERATED by web/tools/make_app_copy.py from docs/ — do not edit.
 *
 * The browser app's shell, in the iPhone app's words: the four tabs, the app menu, the
 * session sub-tabs, the ways in, the welcome, What's new, Help and the feedback door.
 *
 * Regenerate after a deliberate wording change:
 *
 *     python3 web/tools/make_app_copy.py
 *
 * The lists are pinned from both sides. `web/tools/verify_app_shell.py` reads the kit's own
 * Swift and fails when this and the phone disagree, and reads web/app/index.html and fails
 * when the page has drifted from either.
 */

'''


def _js(value) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2)


def _ways_in(shell: dict, routes: dict) -> dict:
    """The empty Sessions tab, composed.

    A row whose id names a guide route takes that route's title verbatim, so the ways in
    read the same words in the same order on both surfaces. A row that names no route (the
    drop target, the example) carries its own title from the shell file.
    """
    rows = []
    for row in shell["waysIn"]["rows"]:
        route = routes.get(row["id"])
        entry = {
            "id": row["id"],
            "title": row.get("title") or route["title"],
            "line": row["line"],
            "here": bool(row["here"]),
        }
        if route is not None:
            entry["href"] = START_ROUTE % row["id"]
            entry["status"] = route["status"]
        rows.append(entry)
    return {"title": shell["waysIn"]["title"], "rows": rows}


def render() -> str:
    shell = json.loads((COPY / "app-shell.json").read_text(encoding="utf-8"))
    phrases = json.loads((COPY / "phrases.json").read_text(encoding="utf-8"))
    feedback = json.loads((COPY / "feedback.json").read_text(encoding="utf-8"))
    whats_new = json.loads((COPY / "whats-new.json").read_text(encoding="utf-8"))
    help_doc = json.loads((COPY / "help.json").read_text(encoding="utf-8"))
    guide = json.loads(GUIDE.read_text(encoding="utf-8"))

    routes = {r["id"]: r for r in guide["routes"]}

    shell_out = {key: shell[key]
                 for key in ("tabs", "menu", "sessionSections", "family", "beta")}
    # The Beta page lists what is in the beta: docs/copy/channels.json's beta rows, the
    # same list the phone's `ChannelFeatures.beta` is pinned to, so there is no second one.
    channels = json.loads((COPY / "channels.json").read_text(encoding="utf-8"))
    shell_out["beta"] = dict(shell["beta"],
                             features=[row["text"] for row in channels["beta"]])
    ways_in = _ways_in(shell, routes)

    guide_out = {
        "framing": guide["framing"],
        "lede": guide["sections"]["routes"]["lede"],
        "routes": [{"id": r["id"], "title": r["title"], "status": r["status"],
                    "summary": r["summary"], "href": START_ROUTE % r["id"]}
                   for r in guide["routes"]],
    }

    # The one sentence at the top of each Settings section. The app reads them from
    # `GettingStartedGuide`, so the phone's switch and the browser's say the same thing.
    settings = {key: guide["settings"][key] for key in ("intervalsIcu", "strava")}

    # The Settings page itself, section by section, in the phone's order — **every section
    # the phone has**, and only what the release channel may read: a section a channel
    # lacks has no UI at all (CLAUDE.md, "Three channels from one commit").
    #
    # `web` no longer decides whether a section is on the page, only whether a browser can
    # DO it (Jan, 23 September 2026: the browser app mirrors the phone page for page). A
    # section a browser cannot do is drawn with its header, its one line, and one more line
    # saying where it is — because a rider who cannot find Notifications here should be
    # told it is on the phone rather than be left to conclude it does not exist.
    #
    # The two exceptions are `storage` and `backup`, which already have a web twin: the
    # browser's **Your data** is the phone's Storage and Library backup plus the site data
    # a tab can lose them to (docs/screens.md, deviation 18). Drawing them as well would be
    # the same subject under three headings (docs/review-checklist.md, pattern F), and
    # `data` stands where they stand in the phone's order.
    settings_doc = json.loads((COPY / "settings.json").read_text(encoding="utf-8"))
    settings_sections = []
    for section in settings_doc["sections"]:
        if section["channel"] not in WEB_CHANNELS or section["id"] in WEB_TWINS:
            continue
        entry = {key: section[key] for key in ("id", "title", "lead", "footer", "help")
                 if key in section}
        if not section["web"]:
            entry["phoneOnly"] = True
        settings_sections.append(entry)

    # The four ids the kit's `WelcomeGuide.highlights` selects, in its order. The lines are
    # not copied: js/copy.js already carries the eleven glossary entries, and the welcome
    # looks its four up there.
    welcome = {
        "headline": phrases["headline"],
        "promise": phrases["promise"],
        "highlights": ["foilShare", "flights", "dryStreak", "speedRecords"],
        # `WelcomeGuide.measuresTitle`, the title over the four.
        "measuresTitle": "What CleanJibe measures",
    }

    entries = [{key: entry.get(key) for key in
                ("version", "build", "channel", "date", "title", "lines")}
               for entry in whats_new["entries"]
               if entry.get("channel") in WEB_CHANNELS]

    help_out = {"stub": bool(help_doc.get("stub")),
                "sections": [{key: section[key] for key in section if key != "_readme"}
                             for section in help_doc["sections"]]}

    feedback_out = {key: feedback[key]
                    for key in ("doors", "invitation", "prompts", "subjectPrefix")}

    # THE WORDS THE PRESENTATION DOCUMENT POINTS AT (ADR-033, round 3). The document
    # carries ids and raw values and no sentence at all, so every renderer on the session
    # path — the block, the card, the wrist-under callout, the divergence banner — resolves
    # them here. Copied whole, minus the file's two non-copy keys: the groups ARE the id
    # namespace (`presentation.<group>.<id>`), so a generator that picked groups would have
    # to be edited on the day the kit authors a sixth one.
    presentation = json.loads((COPY / "presentation.json").read_text(encoding="utf-8"))
    presentation_out = {key: value for key, value in presentation.items()
                        if key not in ("_readme", "schema")}

    return HEADER + (
        "/** The four tabs, the six menu rows, the four session sub-tabs, the family\n"
        " *  section and the Beta page (docs/copy/app-shell.json). One order, one wording,\n"
        " *  both surfaces. */\n"
        "export const SHELL = %s;\n\n"
        "/**\n"
        " * The empty Sessions tab: the iPhone's ways-in card, with the two doors only a\n"
        " * browser has at the top of it.\n"
        " *\n"
        " * `here` is false on a door a browser cannot open. Those rows say why in their own\n"
        " * line and still link to the route, because the route is real and the reader may\n"
        " * be about to take it on the phone.\n"
        " */\n"
        "export const WAYS_IN = %s;\n\n"
        "/** The five routes in, as the welcome screen lists them\n"
        " *  (docs/guide/getting-started.json, the order both surfaces print). */\n"
        "export const GUIDE = %s;\n\n"
        "/** The sentence at the top of a Settings section, the phone's own\n"
        " *  (`GettingStartedGuide.settingsIcu` / `.settingsStrava`). */\n"
        "export const SETTINGS = %s;\n\n"
        "/**\n"
        " * The Settings page, section by section, in the order the iPhone draws it\n"
        " * (docs/copy/settings.json, written out of the kit's `SettingsCopy`).\n"
        " *\n"
        " * `lead` is what a rider reads by default: what you get, in one line (pattern K).\n"
        " * `footer` is the phone's own paragraphs, shown only in the extensive reading.\n"
        " * `help` is the topic the section's `?` opens; a section without one has no `?`.\n"
        " */\n"
        "export const SETTINGS_SECTIONS = %s;\n\n"
        "/** The welcome's headline and promise, and the four glossary ids it shows.\n"
        " *  The lines come from `GLOSSARY` in ./copy.js, which is their one home. */\n"
        "export const WELCOME = %s;\n\n"
        "/** What's new, release and beta only — the filter /whats-new/ uses. */\n"
        "export const WHATS_NEW = %s;\n\n"
        "/** The help catalogue (docs/copy/help.json). `stub` is true while the kit's own\n"
        " *  export is still to come, and the page says so. */\n"
        "export const HELP = %s;\n\n"
        "/** The feedback door, word for word (docs/copy/feedback.json). */\n"
        "export const FEEDBACK = %s;\n\n"
        "/**\n"
        " * The words the presentation document points at (docs/copy/presentation.json,\n"
        " * authored by the kit's `PresentationCopy`).\n"
        " *\n"
        " * The document carries an **id** and the arguments a sentence interpolates, never\n"
        " * the sentence (ADR-033, rule 1). `js/presentation.js` is the resolver: it reads\n"
        " * this, the glossary in ./copy.js and the token catalogue in ./tokens.js, which\n"
        " * are the four namespaces a `labelId` may use and there are no others.\n"
        " */\n"
        "export const PRESENTATION = %s;\n"
        % (_js(shell_out), _js(ways_in), _js(guide_out), _js(settings),
           _js(settings_sections), _js(welcome),
           _js(entries), _js(help_out), _js(feedback_out), _js(presentation_out)))


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true",
                        help="exit 1 if web/js/appcopy.js is stale")
    args = parser.parse_args(argv)

    text = render()
    if args.check:
        if not OUT.exists() or OUT.read_text(encoding="utf-8") != text:
            print("stale, run `python3 web/tools/make_app_copy.py`: %s"
                  % OUT.relative_to(REPO), file=sys.stderr)
            return 1
        print("js/appcopy.js: the shell, the ways in, the welcome, What's new and Help")
        return 0

    OUT.write_text(text, encoding="utf-8")
    print("wrote %s" % OUT.relative_to(REPO))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
