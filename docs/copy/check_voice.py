#!/usr/bin/env python3
"""**docs/voice.md, made checkable.** Every rider-facing string on every surface is measured
against the ten rules that a machine can hold:

  rule 1   one thought per sentence — mean sentence length under 14 words, no sentence over 20
  rule 4   no em-dash, no semicolon, no parenthesis inside a rider sentence
  rule 5   none of the banned shapes ("the one thing…", "the half only…", "exactly as…",
           "which is the whole point", "and that is why", "not X but Y" is left to the reader)

Run it:

    python3 docs/copy/check_voice.py            # PASS/FAIL per target, exit 1 on any FAIL
    python3 docs/copy/check_voice.py --report   # the numbers only, never fails (a baseline)

What is read, per target: the string literals of the kit's Help/ and Presentation/ sources
and of the watch's ui/ and alerts/ (Monkey C), the <string> values of the watch's strings.xml,
the visible text of the website's prose pages, and the live blocks of the two store texts.
Code comments are skipped; a literal under four words is skipped (labels are not sentences);
a literal that is a path, a URL or a format string is skipped.

Exemptions are `{path, text, why}` entries in `docs/copy/voice-exemptions.json` — `text` is a
substring of the offending sentence — and every one that fires is printed, like the lexicon's.
Store texts are ADVISORY while a version is in review (their live copy cannot move); they
print and never fail until the flag below is flipped.
"""

from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "docs" / "copy"))
from check_release_copy import _Text, fenced_block, string_literals  # noqa: E402

MEAN_MAX = 14.0
SENTENCE_MAX = 20
BANNED_SHAPES = [
    "the one thing", "the one place", "the one sentence", "the half only",
    "exactly as", "which is the whole point", "the whole point", "and that is why",
    "that is the point", "is the whole reason", "for exactly that reason",
]
EXEMPTIONS = REPO / "docs" / "copy" / "voice-exemptions.json"

# Pattern C (16 Sep 2026): facts that go stale by construction. A date or a version number in
# a rider sentence is wrong the day after it was typed unless a generator writes it. Generated
# spans (data-copy="garmin-…") are stripped before the pages are read; the release notes are
# generated out of docs/copy/whats-new.json, so their two surfaces — /whats-new and the kit's
# WhatsNew.swift — carry the `dated` flag instead of an exemption per sentence.
STALE = re.compile(r"\b\d{1,2} (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]* 20\d\d\b|\b20\d\d-\d\d-\d\d\b|\b0\.9\.\d+\b|\bbuild \d{2,3}\b|\bsince 0\.\d")

# Pattern I of the same day: paragraph length is ungoverned by the sentence rules. A rider
# paragraph is one authored block — a chain of `+`-joined literals, cut again at every line
# break the rider sees — and carries at most this many words. A Settings or Import footer
# says what you get and carries 25 (pattern K); a help summary carries 20 and is held by
# `HelpBudgetTests` in the kit, where the summary is a field rather than a literal.
#
# Strict since the second voice pass: a paragraph over its budget FAILS. The way under it is
# to split, never to compress — a fact that leaves a footer goes to the help body or to docs/
# (rule 10 of docs/voice.md).
PARAGRAPH_MAX = 40
FOOTER_MAX = 25
PARAGRAPH_STRICT = True


@dataclass
class Target:
    label: str
    path: str                 # file, or directory for a literal scan
    kind: str                 # "swift" | "mc" | "xml" | "html" | "md"
    blocks: list[str] | None = None
    strip: tuple[str, ...] = ()
    advisory: bool = False
    #: dated release notes are this page's purpose; the stale-fact rule does not apply
    dated: bool = False
    #: words a single paragraph of this target may carry. `None` means the target has no
    #: paragraph budget here: on a page a "paragraph" is what the text extractor rebuilt out
    #: of the markup rather than a block an author wrote, and the site's own budget is
    #: `web/tools/verify_unique.py` (a page's word count, and no sentence twice).
    paragraph_max: int | None = PARAGRAPH_MAX
    #: sub-paths of a directory target that belong to a target of their own
    exclude: tuple[str, ...] = ()


#: The generated release notes, read by their own target on the line below.
WHATS_NEW_SWIFT = "ios/WingFoilKit/Sources/WingFoilKit/Help/WhatsNew.swift"

TARGETS: list[Target] = [
    Target("kit · Help", "ios/WingFoilKit/Sources/WingFoilKit/Help", "swift",
           exclude=(WHATS_NEW_SWIFT,)),
    # **The app's one dated surface**, and the web page's twin. A release note that does
    # not say when it shipped is not a release note, and every date and build number in
    # this file is written by web/tools/make_whats_new.py out of docs/copy/whats-new.json
    # rather than typed — which is the condition the stale-fact rule is really about.
    # Every other voice rule still applies, and the generator holds the same ones on the
    # source so a bad line fails before it is written.
    Target("kit · What's new", WHATS_NEW_SWIFT, "swift", dated=True),
    Target("kit · Presentation", "ios/WingFoilKit/Sources/WingFoilKit/Presentation", "swift"),
    Target("app · Features", "ios/WingFoil/Features", "swift",
           exclude=("Settings", "Import")),
    # The two screens that are mostly footers. A footer says what you get in one line and
    # leaves the mechanism to a help link (pattern K), so its paragraph budget is 25.
    Target("app · Settings", "ios/WingFoil/Features/Settings", "swift",
           paragraph_max=FOOTER_MAX),
    Target("app · Import", "ios/WingFoil/Features/Import", "swift",
           paragraph_max=FOOTER_MAX),
    Target("watch · pages", "garmin/source/ui", "mc"),
    Target("watch · alerts", "garmin/source/alerts", "mc"),
    Target("watch · settings strings", "garmin/resources/strings/strings.xml", "xml"),
    # The pages keep the sentence rules. Their paragraph budget is verify_unique.py's, over
    # the page: what the extractor here calls a paragraph is a run of visible text between
    # two blank lines of markup, which is not the block the author typed.
    Target("web · /", "web/index.html", "html", strip=("channels-beta", "channels-dev"),
           paragraph_max=None),
    Target("web · /start/", "web/start/index.html", "html", paragraph_max=None),
    Target("web · /learn/", "web/learn/index.html", "html", paragraph_max=None),
    Target("web · /watches/", "web/watches/index.html", "html", paragraph_max=None),
    Target("web · /invite/", "web/invite/index.html", "html",
           strip=("channels-beta", "channels-dev"), paragraph_max=None),
    Target("web · /whats-new/", "web/whats-new/index.html", "html", dated=True,
           paragraph_max=None),
    Target("web · /app/", "web/app/index.html", "html", paragraph_max=None),
    Target("App Store · description", "ios/store/appstore.md", "md",
           blocks=["Promotional text", "Description"], advisory=True, paragraph_max=None),
    Target("Connect IQ · description", "garmin/store/listing.md", "md",
           blocks=["Description (live text)"], advisory=True, paragraph_max=None),
]

#: data-copy marks a generator writes; their text is never judged (it cannot go stale by hand).
GENERATED = ("garmin-version", "garmin-count", "ciq-title", "appstore-name")

SKIP_LITERAL = re.compile(r"^(https?://|[\w.]+/|%|[A-Za-z]+\.[A-Za-z]+$|\\\()|→|\{[^}]*\}")
#: The same, for a whole paragraph. A path notation inside it (`Settings → Garmin watch`)
#: is how the app names a route and does not stop the block being a paragraph a rider
#: reads, so the arrow is not a reason to look away from its length.
SKIP_PARAGRAPH = re.compile(r"^(https?://|[\w.]+/|%|[A-Za-z]+\.[A-Za-z]+$|\\\()|\{[^}]*\}")
SENTENCE_END = re.compile(r"(?<=[.!?])\s+(?=[A-Z0-9\"“(])")


def words(sentence: str) -> int:
    return len([w for w in re.split(r"\s+", sentence.strip()) if w])


def sentences_of(text: str) -> list[str]:
    text = re.sub(r"\s+", " ", text).strip()
    if not text:
        return []
    return [s.strip() for s in SENTENCE_END.split(text) if s.strip()]


def rider_literals(path: Path, kind: str) -> list[tuple[int, str]]:
    """(line, literal) pairs worth judging as sentences."""
    out = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith("///") or stripped.startswith("<!--"):
            continue
        if kind == "xml":
            m = re.search(r"<string id=\"[^\"]+\">(.*?)</string>", line)
            literals = [m.group(1)] if m else []
        else:
            literals = string_literals(line)
        for literal in literals:
            if words(literal) < 4 or SKIP_LITERAL.search(literal):
                continue
            out.append((number, literal))
    return out


def judge(sentences: list[tuple[str, str]], exemptions: list[dict], relative: str,
          dated: bool = False):
    """sentences: (where, sentence). Returns (failures, honoured, stats)."""
    failures, honoured = [], []
    lengths = []
    for where, s in sentences:
        n = words(s)
        lengths.append(n)
        problems = []
        if n > SENTENCE_MAX:
            problems.append(f"{n} words")
        if "—" in s or "–" in s:
            problems.append("dash")
        if ";" in s:
            problems.append("semicolon")
        if "(" in s and ")" in s:
            problems.append("parenthesis")
        low = s.lower()
        for shape in BANNED_SHAPES:
            if shape in low:
                problems.append(f"\"{shape}\"")
        if not dated and STALE.search(s):
            problems.append("a date or version typed by hand")
        if not problems:
            continue
        why = next((e["why"] for e in exemptions
                    if relative.startswith(e["path"]) and e["text"] in s), None)
        if why:
            honoured.append(f"    allowed  {where}: {', '.join(problems)} — {why}")
        else:
            failures.append(f"{where}: {', '.join(problems)} — \"{s[:110]}\"")
    mean = sum(lengths) / len(lengths) if lengths else 0.0
    return failures, honoured, (len(lengths), mean, max(lengths) if lengths else 0)


def rider_paragraphs(path: Path, kind: str) -> list[tuple[int, str]]:
    """(line, paragraph) pairs — the blocks a rider reads as one.

    A paragraph is one authored string: a chain of literals joined by `+` across as many
    lines as it takes, cut again at every line break inside it, because a blank line in a
    footer is a new block on the screen. Judging one source line at a time (what the
    sentence pass does) would measure the width of the editor, not the length of the text.
    """
    lines = path.read_text(encoding="utf-8").splitlines()

    def is_comment(line: str) -> bool:
        stripped = line.strip()
        return stripped.startswith("//") or stripped.startswith("<!--")

    def literals_of(line: str) -> list[str]:
        if is_comment(line):
            return []
        if kind == "xml":
            m = re.search(r"<string id=\"[^\"]+\">(.*?)</string>", line)
            return [m.group(1)] if m else []
        return string_literals(line)

    def continues(index: int, line: str) -> bool:
        """Does the chain go on after this line? `"a " + "b"`, or a `+` opening the next."""
        if line.rstrip().endswith("+"):
            return True
        for following in lines[index + 1:]:
            if not following.strip():
                return False
            if following.strip().startswith("//"):
                continue
            return following.strip().startswith("+")
        return False

    out: list[tuple[int, str]] = []
    chain: list[str] = []
    start = 0
    for index, line in enumerate(lines):
        # A comment between two halves of a `+` chain is the author talking to the next
        # author. It does not end the paragraph the rider reads.
        if is_comment(line):
            continue
        pieces = literals_of(line)
        if not pieces:
            if chain:
                out.append((start, "".join(chain)))
                chain = []
            continue
        if not chain:
            start = index + 1
        chain.extend(pieces)
        if not continues(index, line):
            out.append((start, "".join(chain)))
            chain = []
    if chain:
        out.append((start, "".join(chain)))

    paragraphs: list[tuple[int, str]] = []
    for number, text in out:
        for block in re.split(r"\n+", text):
            block = block.strip()
            if words(block) < 4 or SKIP_PARAGRAPH.search(block):
                continue
            paragraphs.append((number, block))
    return paragraphs


#: label → (where, words, text) for every paragraph over its target's budget.
PARAGRAPHS: dict[str, list[tuple[str, int, str]]] = {}


def note_paragraph(label: str, where: str, text: str, budget: int | None) -> None:
    if budget is None:
        return
    n = words(text)
    if n > budget:
        PARAGRAPHS.setdefault(label, []).append((where, n, text))


def collect(target: Target) -> list[tuple[str, str]]:
    base = REPO / target.path
    out: list[tuple[str, str]] = []
    if target.kind in ("swift", "mc", "xml"):
        files = [base] if base.is_file() else sorted(
            p for p in base.rglob("*") if p.suffix == {"swift": ".swift", "mc": ".mc", "xml": ".xml"}[target.kind])
        files = [f for f in files
                 if f.relative_to(REPO).as_posix() not in target.exclude]
        for f in files:
            rel = f.relative_to(REPO).as_posix()
            if any(part in target.exclude for part in f.relative_to(base).parts[:-1]):
                continue
            for number, paragraph in rider_paragraphs(f, target.kind):
                note_paragraph(target.label, f"{rel}:{number}", paragraph, target.paragraph_max)
            for number, literal in rider_literals(f, target.kind):
                for s in sentences_of(literal):
                    out.append((f"{rel}:{number}", s))
    elif target.kind == "html":
        raw = base.read_text(encoding="utf-8")
        # the generated guide block is the JSON's, judged where the JSON is used (the kit)
        raw = re.sub(r"<!-- guide:begin.*?<!-- guide:end -->", "", raw, flags=re.S)
        parser = _Text(target.strip + GENERATED)
        parser.feed(raw)
        parser.close()
        text = "\n".join(parser.parts)
        for para in re.split(r"\n\s*\n", text):
            note_paragraph(target.label, target.path, para, target.paragraph_max)
            for s in sentences_of(para):
                if words(s) >= 4:
                    out.append((target.path, s))
    elif target.kind == "md":
        raw = base.read_text(encoding="utf-8")
        for heading in target.blocks or []:
            block = fenced_block(raw, heading)
            if block:
                for s in sentences_of(block):
                    out.append((f"{target.path} · {heading}", s))
    return out


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    report = "--report" in argv
    exemptions = json.loads(EXEMPTIONS.read_text(encoding="utf-8")) if EXEMPTIONS.exists() else []
    failed = 0
    honoured_all: list[str] = []
    for target in TARGETS:
        sentences = collect(target)
        failures, honoured, (count, mean, longest) = judge(sentences, exemptions, target.path,
                                                           target.dated)
        honoured_all += honoured
        over_mean = mean > MEAN_MAX
        bad = bool(failures) or over_mean
        long_paras = PARAGRAPHS.get(target.label, [])
        # A paragraph carries the same exemptions a sentence does: the SVG path of the drawn
        # wordmark is geometry in a literal, and its length says nothing about the voice.
        kept = []
        for where, n, text in long_paras:
            why = next((e["why"] for e in exemptions
                        if target.path.startswith(e["path"]) and e["text"] in text), None)
            if why:
                honoured_all.append(f"    allowed  {where}: paragraph of {n} words — {why}")
            else:
                kept.append((where, n, text))
        long_paras = kept
        if long_paras and PARAGRAPH_STRICT:
            failures += [f"{w}: paragraph of {n} words (max {target.paragraph_max})"
                         f" — \"{t[:70]}\"" for w, n, t in long_paras]
        bad = bool(failures) or over_mean
        verdict = "PASS" if not bad else ("note" if (report or target.advisory) else "FAIL")
        print(f"{verdict}  {target.label}  ({target.path}) — {count} sentences, "
              f"mean {mean:.1f} words, longest {longest}, {len(failures)} problem(s)"
              + (f", {len(long_paras)} paragraph(s) over {target.paragraph_max} words"
                 + ("" if PARAGRAPH_STRICT else " [advisory]") if long_paras else "")
              + (" [advisory]" if target.advisory else ""))
        if bad and not report:
            for line in failures[:40]:
                print(f"    {line}")
            if len(failures) > 40:
                print(f"    … and {len(failures) - 40} more")
            if over_mean:
                print(f"    mean sentence length {mean:.1f} > {MEAN_MAX}")
            if not target.advisory:
                failed += 1
    if honoured_all:
        print("\nExemptions honoured (each one is written down):")
        for line in honoured_all:
            print(line)
    print()
    if failed and not report:
        print(f"FAILED — {failed} target(s) off the voice. docs/voice.md says what the rules are for.")
        return 1
    print("PASSED — every rider sentence inside the voice." if not report else "report only")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
