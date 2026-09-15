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
and which of the three rule sets apply. `.md` targets can name fenced code blocks by the
heading above them; `.html` targets are read as visible text. The web verifier
(`web/tools/verify_links.py`) runs this file over `web/**.html` the same way.

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
                         "home-screen widget", "video export")
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


# ---------------------------------------------------------------------------- reading copy


class _Text(HTMLParser):
    """Visible text of an HTML page: no tags, no script, no style."""

    def __init__(self) -> None:
        super().__init__()
        self.parts: list[str] = []
        self._skip = 0

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style"):
            self._skip += 1

    def handle_endtag(self, tag):
        if tag in ("script", "style") and self._skip:
            self._skip -= 1

    def handle_data(self, data):
        if not self._skip:
            self.parts.append(data)


def fenced_block(markdown: str, heading: str) -> str | None:
    """The first ``` block under `## <heading>`, or None when the heading is not there."""
    pattern = re.compile(
        r"^#{1,6}\s+" + re.escape(heading) + r"\s*$(.*?)^```",
        re.MULTILINE | re.DOTALL)
    match = pattern.search(markdown)
    if not match:
        return None
    rest = markdown[match.end():]
    end = rest.find("```")
    return rest if end < 0 else rest[:end]


def copy_of(target: Target) -> tuple[str | None, list[str]]:
    """The text to check, and any complaint about getting at it."""
    path = REPO / target.path
    if not path.exists():
        return None, [f"missing file: {target.path}"]
    raw = path.read_text(encoding="utf-8")
    if path.suffix == ".html":
        parser = _Text()
        parser.feed(raw)
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

    if honoured:
        print("\nExemptions honoured (each one is a debt, written down):")
        for line in honoured:
            print(line)

    print()
    if failures:
        print(f"FAILED — {len(failures)} problem(s). "
              f"docs/copy/README.md says what each rule is for.")
        return 1
    print(f"PASSED — {len(TARGETS) + len(KIT_SOURCE_DIRS)} targets clean.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
