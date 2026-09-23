#!/usr/bin/env python3
"""The browser app's shell against the iPhone app's, and against its own page.

    python3 web/tools/verify_app_shell.py
    python3 web/tools/verify_app_shell.py --brief

Jan, 19 September 2026: *"iOS is the reference, the web is the port"*. A port is only a port
while somebody checks, so this holds three lists from both ends at once:

  THE FOUR TABS         ios/WingFoil/App/RootView.swift    ->  docs/copy/app-shell.json
  THE FIVE MENU ROWS    ios/WingFoilKit/.../AppMenuRows.swift (the last row's title is
                        FeedbackDoors.menuRow, so docs/copy/feedback.json is read for it)
  THE SESSION SUB-TABS  ios/WingFoilKit/.../SessionSection.swift
  THE SETTINGS SECTIONS ios/WingFoilKit/.../SettingsCopy.swift -> docs/copy/settings.json
                        (written by ``SettingsCopyExportTests``; the page declares each
                        section with ``data-settings`` and renders the header and the
                        one-line lead from the JSON rather than typing either)

and then holds ``web/app/index.html`` to the JSON: the tab bar, the menu rows and the
ways-in rows have to be in the page, in that order, with those words. It is the smoke test
for a page no verifier could otherwise open — there is no browser here, so this parses the
markup and asserts that the structure a reader needs is in it.

It also checks the two orders that are not the phone's to give:

  * the ways in are in docs/guide/getting-started.json's order, with its titles
    (docs/review-checklist.md, pattern J: one thing, one order);
  * every ``data-section`` on a session panel is one of the four session ids, so a panel
    cannot quietly leave the switcher.

Stdlib only, and no network — the same contract every other verifier in this directory
keeps. ``verify_links.py`` runs it.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

WEB = Path(__file__).resolve().parents[1]
REPO = WEB.parent
COPY = REPO / "docs" / "copy"
GUIDE = REPO / "docs" / "guide" / "getting-started.json"
PAGE = WEB / "app" / "index.html"

#: The phone's Settings sections the browser draws under one name of its own: **Your
#: data** is Storage plus Library backup plus the site data only a tab can lose a library
#: to (docs/screens.md, deviation 18). ``web/tools/make_app_copy.py`` holds the same list.
WEB_TWINS = ("storage", "backup")

ROOT_VIEW = REPO / "ios" / "WingFoil" / "App" / "RootView.swift"
KIT = REPO / "ios" / "WingFoilKit" / "Sources" / "WingFoilKit" / "Presentation"
MENU_ROWS = KIT / "AppMenuRows.swift"
SESSION_SECTION = KIT / "SessionSection.swift"

#: The pages the shell routes to. A missing one is a tab that opens nothing.
PAGE_IDS = ["page-sessions", "page-session", "page-records", "page-trends", "page-periods",
            "page-period", "page-gear", "page-settings", "page-help"]

# --------------------------------------------------------------- the ported screens

#: **A screen the web took from the phone, with the name it took and the empty state it
#: owes** (docs/screens.md, "The web after the port").
#:
#: Every one of these was a "missing" row in that table until it was ported, and each is a
#: block of markup in ``web/app/index.html`` carrying two attributes: ``data-screen`` is
#: what the phone calls it, ``data-empty`` is the sentence it shows with nothing in it.
#: Putting both in the markup rather than in JavaScript is what makes them checkable here —
#: there is no browser in this directory, and an empty state that only exists inside a
#: template literal is an empty state nobody can hold to the phone's.
#:
#: ``swift`` is the file that NAMES the screen on iOS; the name has to be in it, verbatim.
#: ``empty_from`` is the file the empty sentence is authored in, where iOS has one — several
#: of these screens are absent on the phone when they are empty (the gear card's note is
#: shown, the divergence card is not), so the sentence is the browser's own and is held
#: only to the markup.
PORTED_SCREENS = [
    ("log-gear", "Gear", "ios/WingFoil/Features/Gear/SessionGearCard.swift",
     "Add wings, boards and foils on the Gear tab to correlate sessions with what you rode.",
     "ios/WingFoil/Features/Gear/SessionGearCard.swift"),
    ("log-divergence", "Watch vs phone",
     "ios/WingFoil/Features/SessionDetail/SessionLogView.swift",
     "Watch and phone agree.", None),
    ("deleted-body", "Deleted sessions",
     "ios/WingFoil/Features/Import/ReAddDeletedSheet.swift",
     "No deleted sessions yet.", None),
    ("restore-body", "Restore library",
     "ios/WingFoil/Features/Settings/LibraryBackupSection.swift",
     "No backup picked yet.", None),
    ("gear-quiver", "Gear & spots", "ios/WingFoil/Features/Gear/GearView.swift",
     "No wings yet", None),
    ("gear-dialog", "New gear", "ios/WingFoil/Features/Gear/GearView.swift", "", None),
    ("trends-range", "Custom range",
     "ios/WingFoil/Features/Library/LibraryFilterMenu.swift",
     "Nothing in this range", "ios/WingFoil/Features/Trends/TrendsView.swift"),
    ("periods-body", "Periods", "ios/WingFoil/Features/Periods/PeriodsView.swift",
     "No periods yet", "ios/WingFoil/Features/Periods/PeriodsView.swift"),
]

#: A Swift string split over two literals is one authored sentence. Joining the halves
#: before the search is what lets a verifier read a `+`-chained line the way a rider does —
#: the same thing docs/copy/check_voice.py does to judge one.
_CHAIN = re.compile(r'"\s*\+\s*"')


def swift_text(path: Path) -> str:
    return _flat(_CHAIN.sub("", path.read_text(encoding="utf-8")))


# ------------------------------------------------------------------- the page reader


class Shell(HTMLParser):
    """What the markup says the shell is: the tabs, the menu rows, the ways in, the ids.

    Text is collected per element rather than per document, because what is being checked
    is a label — "Sessions" on a tab, "Settings" on a menu row — and a label is the text of
    the one element it is on.
    """

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids = set()
        self.tabs: list[tuple[str, str]] = []           # (data-tab, text)
        self.menu: list[tuple[str, str, bool]] = []     # (data-menu, text, after divider)
        self.ways: list[tuple[str, str, str]] = []      # (data-way, title, line)
        self.sections: list[str] = []
        #: the Settings sections the page carries, in the order it draws them
        self.settings: list[str] = []
        #: id -> (data-screen, data-empty), the ported screens and their empty states.
        self.screens: dict[str, tuple[str, str]] = {}
        self._stack: list[dict] = []
        self._divider_next = False
        self._way: dict | None = None
        self._cls: str | None = None

    def handle_starttag(self, tag, attrs):
        d = dict(attrs)
        if d.get("id"):
            self.ids.add(d["id"])
        if d.get("data-section"):
            self.sections.append(d["data-section"])
        if d.get("data-settings"):
            self.settings.append(d["data-settings"])
        if d.get("data-screen"):
            self.screens[d.get("id") or ""] = (_flat(d["data-screen"]),
                                               _flat(d.get("data-empty") or ""))
        if tag == "li" and "after-divider" in (d.get("class") or ""):
            self._divider_next = True
        if d.get("data-way"):
            self._way = {"id": d["data-way"], "title": "", "line": ""}
        if self._way is not None and tag == "p":
            classes = (d.get("class") or "").split()
            self._cls = ("title" if "way-title" in classes
                         else "line" if "way-line" in classes else None)
        if d.get("data-tab") or d.get("data-menu"):
            self._stack.append({"tab": d.get("data-tab"), "menu": d.get("data-menu"),
                                "text": ""})

    def handle_endtag(self, tag):
        if tag == "p" and self._cls:
            self._cls = None
        if tag == "li" and self._way is not None:
            self.ways.append((self._way["id"], _flat(self._way["title"]),
                              _flat(self._way["line"])))
            self._way = None
        if tag in ("button", "a") and self._stack:
            item = self._stack.pop()
            text = _flat(item["text"])
            if item["tab"]:
                self.tabs.append((item["tab"], text))
            elif item["menu"]:
                self.menu.append((item["menu"], text, self._divider_next))
                self._divider_next = False

    def handle_data(self, data):
        for item in self._stack:
            item["text"] += data
        if self._way is not None and self._cls:
            self._way[self._cls] += data


#: A page prints the typographic apostrophe the way `make_start.html_text` does; the JSON
#: authors the plain one. The mark is the same word, so it is normalised rather than
#: demanded in one spelling.
QUOTES = {"’": "'", "‘": "'", "“": '"', "”": '"'}


def _flat(text: str) -> str:
    """Collapse whitespace and normalise the quote marks a renderer curls."""
    for curly, plain in QUOTES.items():
        text = text.replace(curly, plain)
    return re.sub(r"\s+", " ", text).strip()


# ------------------------------------------------------------------ the Swift readers


def _switch_cases(source: str, func: str) -> dict[str, str]:
    """`case .ride: "Ride"` pairs inside the `var <func>` computed property."""
    start = source.find(f"var {func}:")
    if start < 0:
        return {}
    body = source[start:]
    end = body.find("\n    }")
    body = body[:end if end > 0 else len(body)]
    return {m.group(1): m.group(2)
            for m in re.finditer(r'case \.(\w+):\s*"([^"]*)"', body)}


def _ordered(source: str, name: str) -> list[str]:
    """The `static let <name>: [...] = [.a, .b, …]` list, in its order."""
    m = re.search(rf"static let {name}[^=]*=\s*\[(.*?)\]", source, re.S)
    return re.findall(r"\.(\w+)", m.group(1)) if m else []


def ios_tabs() -> list[str]:
    """The four `tabItem` labels of `RootView`, in the order they are declared."""
    source = ROOT_VIEW.read_text(encoding="utf-8")
    return re.findall(r'\.tabItem \{ Label\("([^"]*)"', source)


def ios_menu() -> list[tuple[str, str, bool]]:
    source = MENU_ROWS.read_text(encoding="utf-8")
    titles = _switch_cases(source, "title")
    order = _ordered(source, "ordered")
    divider = re.search(r"opensAfterDivider: Bool \{ self == \.(\w+) \}", source)
    after = divider.group(1) if divider else ""
    feedback = json.loads((COPY / "feedback.json").read_text(encoding="utf-8"))
    # `.support`'s title is `FeedbackDoors.menuRow`, not a literal, so the switch has no
    # string for it. docs/copy/feedback.json already pins that constant from the kit side.
    doors = feedback["doors"]["app"]
    menu_row = doors.split("→")[-1].strip()
    out = []
    for case in order:
        title = titles.get(case) or (menu_row if case == "support" else "")
        out.append((case, title, case == after))
    return out


def ios_sections() -> list[tuple[str, str]]:
    source = SESSION_SECTION.read_text(encoding="utf-8")
    labels = _switch_cases(source, "label")
    # `allCases` is declaration order for a plain CaseIterable enum, so the cases are read
    # where they are written rather than from a list that does not exist.
    body = source[source.find("public enum SessionSection"):]
    cases = re.findall(r"^    case (\w+)$", body, re.M)
    return [(c, labels.get(c, "")) for c in cases]


# ------------------------------------------------------------------------- the checks


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--brief", action="store_true",
                        help="print only the failures and a one-line verdict")
    args = parser.parse_args(argv)

    problems: list[str] = []
    notes: list[str] = []

    shell = json.loads((COPY / "app-shell.json").read_text(encoding="utf-8"))
    guide = json.loads(GUIDE.read_text(encoding="utf-8"))
    parsed = Shell()
    parsed.feed(PAGE.read_text(encoding="utf-8"))
    parsed.close()

    def same(what, actual, expected):
        if actual == expected:
            notes.append(f"ok    {what}: {expected}")
        else:
            problems.append(f"{what}\n        page/json: {actual}\n        expected:  {expected}")

    # 1 · the three lists, against the phone
    json_tabs = [(t["id"], t["title"]) for t in shell["tabs"]]
    same("the four tabs are the phone's", [t for _, t in json_tabs], ios_tabs())

    json_menu = [(m["id"], m["title"], bool(m.get("afterDivider")))
                 for m in shell["menu"]]
    same("the five menu rows are the phone's", json_menu, ios_menu())

    json_sections = [(s["id"], s["title"]) for s in shell["sessionSections"]]
    same("the session sub-tabs are the phone's", json_sections, ios_sections())

    # 2 · the ways in, against the guide (pattern J)
    routes = {r["id"]: r for r in guide["routes"]}
    rows = shell["waysIn"]["rows"]
    guide_rows = [r["id"] for r in rows if r["id"] in routes]
    same("the ways in follow the guide's order", guide_rows, [r["id"] for r in guide["routes"]])
    for row in rows:
        route = routes.get(row["id"])
        if route is not None and row.get("title") not in (None, route["title"]):
            problems.append(f"ways-in row {row['id']}: a title of its own\n"
                            f"        json:  {row['title']}\n"
                            f"        guide: {route['title']}")

    # 3 · the page carries them
    same("the tab bar", parsed.tabs, json_tabs)
    same("the app menu", parsed.menu, json_menu)

    want_ways = []
    for row in rows:
        route = routes.get(row["id"])
        want_ways.append((row["id"], _flat(row.get("title") or route["title"]),
                          _flat(row["line"])))
    same("the ways-in rows", parsed.ways, want_ways)

    # 3b · THE SETTINGS PAGE, against the phone's own sections
    # docs/copy/settings.json is written out of the kit's `SettingsCopy` by
    # `SettingsCopyExportTests`, so the phone authors every header and every line. What the
    # page owes is the same sections in the same order, and no section of its own: a
    # browser that invented a Settings heading would be the drift docs/screens.md calls a
    # gap rather than a deviation. Since 23 September 2026 that is EVERY section the phone
    # has, in the phone's order: `web` says only whether a browser can do the thing, and a
    # section it cannot do is drawn with its header, its line, and one more saying where it
    # is. `channel` still keeps a beta-only section off a page every stranger can open, and
    # WEB_TWINS is the two the browser answers under a name of its own.
    settings = json.loads((COPY / "settings.json").read_text(encoding="utf-8"))
    want_settings = [s["id"] for s in settings["sections"]
                     if s["channel"] == "release" and s["id"] not in WEB_TWINS]
    same("the Settings sections are the phone's, in its order",
         parsed.settings, want_settings)
    for section in settings["sections"]:
        if len(section["lead"].split()) > 20:
            problems.append(f"settings section {section['id']}: the lead is "
                            f"{len(section['lead'].split())} words, and a lead is one line")

    missing = [i for i in PAGE_IDS if i not in parsed.ids]
    if missing:
        problems.append("the page is missing: " + ", ".join(missing))
    else:
        notes.append(f"ok    all {len(PAGE_IDS)} pages are in the markup")

    known = {s["id"] for s in shell["sessionSections"]}
    stray = sorted({s for s in parsed.sections if s not in known})
    if stray:
        problems.append("a session panel carries a section that is not one of the four: "
                        + ", ".join(stray))
    else:
        notes.append(f"ok    every session panel is on one of the four sub-tabs")

    # 4 · the ported screens: the phone's name, and an empty state that is in the markup
    before = len(problems)
    for host_id, name, swift, empty, empty_from in PORTED_SCREENS:
        found = parsed.screens.get(host_id)
        if found is None:
            problems.append(f"the ported screen {host_id} is not in the page\n"
                            f"        expected:  data-screen=\"{name}\"")
            continue
        page_name, page_empty = found
        if page_name != name:
            problems.append(f"{host_id} is called something the phone does not call it\n"
                            f"        page:      {page_name}\n"
                            f"        expected:  {name}")
        source = (REPO / swift)
        if not source.exists():
            problems.append(f"{host_id}: {swift} is gone, so the name has no source")
        elif f'"{name}"' not in swift_text(source):
            problems.append(f"{host_id}: {swift} does not name it \"{name}\"")
        if empty and page_empty != empty:
            problems.append(f"{host_id} has the wrong empty state\n"
                            f"        page:      {page_empty}\n"
                            f"        expected:  {empty}")
        elif empty and empty_from and empty not in swift_text(REPO / empty_from):
            problems.append(f"{host_id}: the empty state is not the phone's\n"
                            f"        page:      {page_empty}\n"
                            f"        not in:    {empty_from}")
        elif not empty and page_empty:
            problems.append(f"{host_id} carries an empty state the table does not know")
    if len(problems) == before:
        notes.append(f"ok    all {len(PORTED_SCREENS)} ported screens carry the phone's "
                     "name and their empty state")

    if not args.brief:
        for note in notes:
            print(note)

    if problems:
        print("\n%d PROBLEM(S):" % len(problems))
        for p in problems:
            print("  " + p)
        return 1
    print("app shell: the tabs, the menu and the ways in match the phone and the page")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
