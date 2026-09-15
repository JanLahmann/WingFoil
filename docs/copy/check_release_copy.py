#!/usr/bin/env python3
"""**The release never names a door it lacks** — docs/channels.md, "Before the release is
submitted", made checkable.

Three rules, run over every piece of copy a stranger can read:

1. **No beta or dev door in release copy.** `channels.json` → `forbiddenInRelease`, matched
   case-insensitively as a substring. The App Store description promised .gpx imports, Apple
   Health and an Apple Watch app for eleven days after those became beta-only doors; the
   release build has no GPX parser path, no HealthKit entitlement and no watch extension.
   This is the check that stops a rejection.
2. **The Strava sentence stays inside its rule.** `phrases.json` → `stravaForbidden`. The
   rider-facing text never says what Strava has or has not reviewed
   (docs/channels.md): "Strava lets a new app connect a limited number of riders".
3. **The vocabulary.** `phrases.json` → `lexicon.banned`, matched as whole words. *flew
   through*, *clean*, *dry* are the product's words; "carried" and "success" are the
   engine's, and "clean-jibe percentage" is a metric this product does not have — it is CPH,
   clean jibes per *hour*.

Run it:

    python3 docs/copy/check_release_copy.py

Nothing but the standard library, and one line of PASS/FAIL per target.

**Adding a target** is one entry in `TARGETS` below — a path, which blocks of it to read,
which of the three rule sets apply, and (for a page) which marked elements to cut out
first. `.md` targets can name fenced code blocks by the heading above them; `.html` targets
are read as visible text, minus every element whose `data-copy` carries one of the target's
`strip` tokens. The website's two release-facing pages are targets here for exactly that
reason: the beta lists say what is *not* in the release, and reading them would be reading
the exception as the rule. `web/tools/verify_copy.py` is the other half of the web's pin —
it holds the pages to the JSON's words and reads this file's `allow` map so an exemption is
written down once.

**Exemptions** are per (word, path prefix), written down in `phrases.json` →
`lexicon.exemptions` for the vocabulary, and in a target's own `allow` map for the other two.
Every one carries a `why`, and every one that fires is printed, so an exemption cannot quietly
become the rule.
"""

from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass, field
from html.parser import HTMLParser
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
COPY = REPO / "docs" / "copy"

# The three rule sets, by the name a target asks for.
FORBIDDEN_DOORS = "doors"
STRAVA = "strava"
LEXICON = "lexicon"


@dataclass
class Target:
    """One piece of copy, and what may not be in it."""

    label: str
    path: str
    #: Markdown headings whose fenced block is the copy. `None` reads the whole file.
    blocks: list[str] | None = None
    rules: tuple[str, ...] = (FORBIDDEN_DOORS, STRAVA, LEXICON)
    #: term → why it is allowed here. Printed whenever it fires.
    allow: dict[str, str] = field(default_factory=dict)
    #: `data-copy` tokens whose elements are cut out of an `.html` target before it is
    #: read. The channel lists say what is NOT in the release on purpose, and so does
    #: anything marked `beta-door`; scanning them would be reading the exception as the
    #: rule. The same tokens are what `web/tools/verify_copy.py` pins the lists by.
    strip: tuple[str, ...] = ()


# ---------------------------------------------------------------------------- the targets

TARGETS: list[Target] = [
    Target(
        label="App Store · what the rider reads",
        path="ios/store/appstore.md",
        blocks=["App name", "Subtitle", "Promotional text", "Description", "Keywords"],
        allow={
            "windsurf": (
                "Garmin's own Windsurf activity profile, named as a recording source, and "
                "the keyword riders search with — not the dev windsurf discipline"
            ),
        },
    ),
    Target(
        label="App Store · review notes",
        path="ios/store/appstore.md",
        blocks=["Review notes for Apple"],
        # Not rider-facing: these notes are addressed to one App Review engineer, and telling
        # him what Strava's cap is and why a connection may be refused is exactly what they
        # are for. The vocabulary and the doors still apply.
        rules=(FORBIDDEN_DOORS, LEXICON),
        allow={
            term: (
                "the notes exist to explain the Settings section that lists what is in the "
                "TestFlight beta and not in this build; naming those doors to the reviewer "
                "is the explanation, not a promise"
            )
            for term in ("gpx", "tcx", "Apple Health", "Apple Watch app",
                         "home-screen widget", "video export", "grouping")
        },
    ),
    Target(
        label="App Store · the notes around it",
        path="ios/store/appstore.md",
        blocks=None,
        # The prose around the live blocks is this repository's own working notes, not copy
        # anybody ships, so only the vocabulary applies — and it applies for the same reason
        # it applies everywhere: a note that calls CPH a percentage is how the next
        # description comes to call it one.
        rules=(LEXICON,),
        allow={
            "clean-jibe percentage": "named as the mistake it was, so it is not made again",
            "success rate": "named as the takeoff metric it is, beside the one it is not",
            "carried": "named as a word the copy does not use",
        },
    ),
    # The website is copy a stranger reads before he has anything installed, so the same
    # three rules apply to it — with one scope. /invite/, /watches/ and /start/ EXIST to
    # describe the beta and to walk a tester into it; running the door rule over them would
    # be running it over the exception. The two pages below are the ones that speak for the
    # product rather than for the beta: the front door and the analyzer.
    Target(
        label="the front door · what the site promises",
        path="web/index.html",
        strip=("channels-beta", "channels-dev", "beta-door"),
        allow={
            "gpx": (
                "the BROWSER ANALYZER reads .gpx and .tcx itself — it is not the App Store "
                "app and has no channels — and the class C row names the two formats as a "
                "kind of recording, not as a door. The iPhone's GPX door is in the beta "
                "list, which is stripped above"
            ),
            "tcx": "the same two places as \"gpx\", for the same reason",
            "windsurf": (
                "Garmin's own Windsurf activity profile, named in the class B row as a "
                "recording source — not the dev windsurf discipline, which is in the dev "
                "list and stripped above"
            ),
        },
    ),
    Target(
        label="the browser analyzer",
        path="web/app/index.html",
        # The door rule does not apply here and is not exempted away: /app/ is a DIFFERENT
        # PRODUCT. It is the zero-server analyzer, it ships from this repository to a static
        # host with no channels at all, and it reads .fit, .gpx and .tcx today. A promise it
        # makes about file formats is one it keeps in the tab the reader already has open.
        # The Strava sentence and the vocabulary are the site's everywhere, this page too.
        rules=(STRAVA, LEXICON),
        strip=("channels-beta", "channels-dev", "beta-door"),
    ),
    Target(
        label="Connect IQ listing · what the rider reads",
        path="garmin/store/listing.md",
        blocks=["Description (live text)", "What's New (live text)"],
        # The archival transcription of the live store text (docs/channels.md). The
        # description still says "no-fall streak" on the store; it is edited there next,
        # and this exemption goes the day the file's transcription follows.
        rules=(STRAVA, LEXICON),
        allow={
            "carried": (
                "the 0.9.6 What's New row, dated store history: \"carried its speed\" is the "
                "ordinary verb, and a shipped note is not reworded"
            ),
        },
    ),
    Target(
        label="TestFlight metadata",
        path="ios/store/testflight.md",
        blocks=None,
        # The beta's own fields: they are *supposed* to name the beta doors. Only the
        # vocabulary is checked.
        rules=(LEXICON,),
    ),
]

#: Kit sources whose **string literals** carry rider-facing copy. Scanned for the vocabulary
#: only; `CopyContractTests.noBannedWordReachesTheRiderFacingKit` runs the same check inside
#: the Swift suite, so a kit author fails before a release engineer does.
KIT_SOURCE_DIRS = [
    "ios/WingFoilKit/Sources/WingFoilKit/Presentation",
    "ios/WingFoilKit/Sources/WingFoilKit/Help",
]

#: The watch (15 Sep 2026, the audit's B3.3: "the watch is outside every copy mechanism").
#: Monkey C string literals in the pages, the alerts and the settings' strings.xml are the
#: on-water and Garmin Connect words a rider reads; the same `"…"` scanner works on them.
#: Scanned for the vocabulary only — the watch has no channel doors to promise.
WATCH_SOURCE_DIRS = [
    "garmin/source/ui",
    "garmin/source/alerts",
    "garmin/resources/strings",
]
WATCH_SOURCE_SUFFIXES = (".mc", ".xml")

#: The Connect IQ listing's title line in garmin/store/listing.md must be the live store
#: name `phrases.json` → `ciqListingTitle` pins on the website; the header is the one part
#: of that archival file that tracks the tree.
WATCH_LISTING = "garmin/store/listing.md"
WATCH_TITLE_LINE = re.compile(r"^## Watch app — `([^`]+)`", re.M)


# ---------------------------------------------------------------------------- reading copy


class _Text(HTMLParser):
    """Visible text of an HTML page: no tags, no script, no style.

    `strip` is a set of `data-copy` tokens; an element carrying one of them contributes no
    text at all, nor do its children. `data-copy` is a space-separated token list like
    `class`, so one cell can be both a `class-name` and a `beta-door`.
    """

    #: Elements that never have an end tag, so the stack below must not wait for one.
    VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta",
            "param", "source", "track", "wbr", "path", "circle", "rect", "line",
            "polyline", "polygon", "use", "stop", "ellipse"}

    def __init__(self, strip: tuple[str, ...] = ()) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self._strip = set(strip)
        #: The open elements, and whether each one silences the text inside it.
        self._stack: list[tuple[str, bool]] = []

    def _silent(self) -> bool:
        return any(quiet for _, quiet in self._stack)

    def handle_starttag(self, tag, attrs):
        tokens = set((dict(attrs).get("data-copy") or "").split())
        quiet = tag in ("script", "style") or bool(tokens & self._strip)
        if tag in self.VOID or (self.get_starttag_text() or "").rstrip().endswith("/>"):
            return
        self._stack.append((tag, quiet))

    def handle_endtag(self, tag):
        for index in range(len(self._stack) - 1, -1, -1):
            if self._stack[index][0] == tag:
                del self._stack[index:]
                return

    def handle_data(self, data):
        if not self._silent():
            self.parts.append(data)


def fenced_block(markdown: str, heading: str) -> str | None:
    """The first ``` fence after the heading that STARTS with `heading` (any level), or None."""
    lines = markdown.splitlines()
    start = None
    for index, line in enumerate(lines):
        stripped = line.lstrip("#").strip() if line.startswith("#") else None
        if stripped is not None and stripped.startswith(heading):
            start = index
            break
    if start is None:
        return None
    inside, out = False, []
    for line in lines[start + 1:]:
        if line.startswith("```"):
            if inside:
                return "\n".join(out)
            inside = True
            continue
        if line.startswith("#") and not inside:
            return None
        if inside:
            out.append(line)
    return None


def copy_of(target: Target) -> tuple[str | None, list[str]]:
    """The text to check, and any complaint about getting at it."""
    path = REPO / target.path
    if not path.exists():
        return None, [f"missing file: {target.path}"]
    raw = path.read_text(encoding="utf-8")
    if path.suffix == ".html":
        parser = _Text(target.strip)
        parser.feed(raw)
        parser.close()
        return "\n".join(parser.parts), []
    if target.blocks is None:
        return raw, []
    chunks, problems = [], []
    for heading in target.blocks:
        block = fenced_block(raw, heading)
        if block is None:
            problems.append(f"no fenced block under \"## {heading}\"")
        else:
            chunks.append(block)
    return "\n".join(chunks), problems


def string_literals(line: str) -> list[str]:
    """Every "…" on a Swift line, escapes left alone."""
    out, current, inside, escaped = [], "", False, False
    for character in line:
        if escaped:
            if inside:
                current += character
            escaped = False
            continue
        if character == "\\":
            escaped = True
            continue
        if character == '"':
            if inside:
                out.append(current)
                current = ""
            inside = not inside
            continue
        if inside:
            current += character
    return out


# ---------------------------------------------------------------------------- the matching

WORDISH = re.compile(r"[\w-]")


def whole_word(term: str, text: str) -> bool:
    """`term` as a whole word, case-insensitively. "carried" fires, "carriedness" does not."""
    lowered, needle = text.lower(), term.lower()
    start = 0
    while (found := lowered.find(needle, start)) >= 0:
        before = lowered[found - 1] if found else ""
        after = lowered[found + len(needle):found + len(needle) + 1]
        if not WORDISH.match(before or " ") and not WORDISH.match(after or " "):
            return True
        start = found + 1
    return False


def substring(term: str, text: str) -> bool:
    return term.lower() in text.lower()


# ---------------------------------------------------------------------------- the run


def main() -> int:
    channels = json.loads((COPY / "channels.json").read_text(encoding="utf-8"))
    phrases = json.loads((COPY / "phrases.json").read_text(encoding="utf-8"))
    rules = {
        FORBIDDEN_DOORS: (channels["forbiddenInRelease"], substring,
                          "a door this build does not have"),
        STRAVA: (phrases["stravaForbidden"], substring,
                 "says what Strava has or has not reviewed"),
        LEXICON: (phrases["lexicon"]["banned"], whole_word,
                  "not a word this product uses"),
    }
    exemptions = phrases["lexicon"].get("exemptions", [])

    failures: list[str] = []
    honoured: list[str] = []

    for target in TARGETS:
        text, problems = copy_of(target)
        hits = list(problems)
        if text is not None:
            for rule in target.rules:
                terms, matches, why = rules[rule]
                for term in terms:
                    if not matches(term, text):
                        continue
                    if term in target.allow:
                        honoured.append(
                            f"    allowed  \"{term}\" in {target.label}: "
                            f"{target.allow[term]}")
                        continue
                    hits.append(f"\"{term}\" — {why}")
        verdict = "FAIL" if hits else "PASS"
        print(f"{verdict}  {target.label}  ({target.path})")
        for hit in hits:
            print(f"    {hit}")
            failures.append(f"{target.path}: {hit}")

    # The kit's own rider-facing literals, for the vocabulary only.
    banned, _, why = rules[LEXICON]
    for folder in KIT_SOURCE_DIRS:
        hits: list[str] = []
        for source in sorted((REPO / folder).rglob("*.swift")):
            relative = source.relative_to(REPO).as_posix()
            allowed = {
                exemption["word"].lower()
                for exemption in exemptions
                if relative.startswith(exemption["path"])
            }
            for number, line in enumerate(source.read_text(encoding="utf-8").splitlines(), 1):
                if line.strip().startswith("//"):
                    continue
                for literal in string_literals(line):
                    for term in banned:
                        if term.lower() in allowed:
                            continue
                        if whole_word(term, literal):
                            hits.append(f"{relative}:{number} says \"{term}\" — {why}")
        verdict = "FAIL" if hits else "PASS"
        print(f"{verdict}  kit string literals  ({folder})")
        for hit in hits:
            print(f"    {hit}")
            failures.append(hit)

    # The watch's own words, the same rule.
    for folder in WATCH_SOURCE_DIRS:
        hits = []
        for source in sorted((REPO / folder).rglob("*")):
            if source.suffix not in WATCH_SOURCE_SUFFIXES:
                continue
            relative = source.relative_to(REPO).as_posix()
            allowed = {
                exemption["word"].lower()
                for exemption in exemptions
                if relative.startswith(exemption["path"])
            }
            for number, line in enumerate(source.read_text(encoding="utf-8").splitlines(), 1):
                if line.strip().startswith("//") or line.strip().startswith("<!--"):
                    continue
                literals = string_literals(line) if source.suffix == ".mc" else [line]
                for literal in literals:
                    for term in banned:
                        if term.lower() in allowed:
                            continue
                        if whole_word(term, literal):
                            hits.append(f"{relative}:{number} says \"{term}\" — {why}")
        verdict = "FAIL" if hits else "PASS"
        print(f"{verdict}  watch string literals  ({folder})")
        for hit in hits:
            print(f"    {hit}")
            failures.append(hit)

    # The listing's title line is the store's name, the one the website pins too.
    listing = (REPO / WATCH_LISTING).read_text(encoding="utf-8")
    found = WATCH_TITLE_LINE.search(listing)
    want = phrases["ciqListingTitle"]
    if found is None or found.group(1) != want:
        got = found.group(1) if found else "(no '## Watch app — `…`' line)"
        print(f"FAIL  Connect IQ listing title  ({WATCH_LISTING})")
        print(f"    header says \"{got}\", phrases.json → ciqListingTitle says \"{want}\"")
        failures.append(f"{WATCH_LISTING}: listing title")
    else:
        print(f"PASS  Connect IQ listing title  ({WATCH_LISTING})")

    if honoured:
        print("\nExemptions honoured (each one is a debt, written down):")
        for line in honoured:
            print(line)

    print()
    if failures:
        print(f"FAILED — {len(failures)} problem(s). "
              f"docs/copy/README.md says what each rule is for.")
        return 1
    print(f"PASSED — {len(TARGETS) + len(KIT_SOURCE_DIRS) + len(WATCH_SOURCE_DIRS) + 1} targets clean.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
