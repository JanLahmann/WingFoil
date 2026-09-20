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
the visible text of the website's prose pages, the rider sentences web/js/*.js writes at run
time, and the live blocks of the two store texts.
Code comments are skipped. Sentences are judged over the CHAINED text — a `+`-joined chain of
literals is one authored string, so a sentence split across two literals is still one sentence
— and the message points at the chain's first line. A block under four words is skipped
(labels are not sentences); a block that is a path, a URL or a format string is skipped.

PARAGRAPHS are judged over the block an author typed, on every surface. In a source file
that is the chain, cut at every line break inside it. On a page it is the block element the
text was typed into — `<p>`, `<li>`, `<dd>`, `<figcaption>`, `<summary>`, a table cell — cut
again at every `<br>`; inline tags and entities are not the reader's business (`_Blocks`).
A script that builds markup is read the same way, so a `<p>` in web/js and a `<p>` on a page
sit under one budget. JavaScript is scanned like Swift: `+`-chains and template literals are
authored strings, `${…}` is one placeholder, and a literal is read only when it carries a
sentence (four words closed by `.`, `?` or `!`, or eight words). `// voice: skip` on a line
hands the next authored string back to the code, for a selector, a declaration or a strip of
counts no sentence rule fits.

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
from check_release_copy import ESCAPED_TEXT, _Text, fenced_block  # noqa: E402

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
    kind: str                 # "swift" | "mc" | "xml" | "html" | "js" | "md"
    blocks: list[str] | None = None
    strip: tuple[str, ...] = ()
    advisory: bool = False
    #: dated release notes are this page's purpose; the stale-fact rule does not apply
    dated: bool = False
    #: words a single paragraph of this target may carry. `None` switches the paragraph
    #: rule off for a target whose blocks are not blocks an author typed (the store texts,
    #: which are one fenced slab each).
    paragraph_max: int | None = PARAGRAPH_MAX
    #: sub-paths of a directory target that belong to a target of their own, or —
    #: for a "js" target — the file names that hold no rider prose
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
    # The pages keep the sentence rules AND the paragraph rule. What a paragraph is on a
    # page is `_Blocks` below: the block element an author typed into — a `<p>`, a `<li>`,
    # a `<dd>`, a `<figcaption>`, a `<summary>`, a table cell — cut again at every `<br>`.
    # Until 19 September 2026 these five carried `paragraph_max=None`, on the grounds that
    # the extractor could not see the typed block; it can now, so pattern I reaches the
    # site (Jan, from his phone: "Is this text in our new style?").
    Target("web · /", "web/index.html", "html", strip=("channels-beta", "channels-dev")),
    # **The site's one dated surface**, since /start/ absorbed /invite/ on 20 September
    # 2026 (which had absorbed /whats-new/ the day before). The release notes are
    # generated into a block marked `data-copy="whats-new"`, stripped below exactly the
    # way a generated garmin-count span is, so the rest of the page is still held to the
    # stale-fact rule. The `dated` flag is the second belt on the same trousers: a date
    # that escapes the block still has to be a date a generator wrote.
    Target("web · /start/", "web/start/index.html", "html", dated=True,
           strip=("channels-beta", "channels-dev", "whats-new")),
    # **The app's help, rendered** (web/tools/make_help.py out of docs/copy/help.json).
    # Every sentence on it is already judged one target above, in the kit's Help sources,
    # which is where it can be edited; it is read again here because the page also carries
    # its own hero and its own section ledes, and those are nobody else's.
    # `related` is the row of "Read next" links under a topic: navigation, not a sentence.
    Target("web · /help/", "web/help/index.html", "html", strip=("related",)),
    Target("web · /app/", "web/app/index.html", "html"),
    # **The rider text the browser app writes at run time.** A page is linted where it is
    # typed; a sentence a script builds out of literals was linted nowhere until now, and
    # the storage line under Sessions proved it (a dash and a bracket, 19 September 2026).
    # Judged the way the kit's Swift literals are: `+`-joined chains and template literals
    # are one authored string, and a literal is read only when it carries a sentence.
    # `exclude` names the files whose strings are not this target's to judge. It is one
    # file long on purpose: the drawing and glue modules (rpc, track, cardmap, trackmap,
    # maneuverfigure) yield no rider block at all, so excluding them would only hide the
    # day they do.
    Target("web · app JS", "web/js", "js", exclude=(
        # GENERATED out of docs/copy/*.json by make_app_copy.py. Every sentence in it is
        # judged where it is written — the kit's Help/ and Presentation/ sources, and the
        # JSON beside them — and it cannot be edited here anyway.
        "appcopy.js",
    )),
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


#: What a `\(…)` interpolation leaves behind in the text a rider reads: one value, one word.
#: Reading the code inside it would count identifiers as words and, worse, would hand the
#: parenthesis rule a bracket no author typed. The chained pass needs this: a lone `"\(n)"`
#: used to be its own short literal and fell under the four-word floor.
INTERPOLATION = "…"


def rider_literals_of(line: str) -> list[str]:
    r"""Every `"…"` on a Swift or Monkey C line, interpolations reduced to one placeholder.

    Same contract as `check_release_copy.string_literals` — escapes left alone, `\n` kept as
    a line break — except that `\(expr)` becomes `…` and the code inside it, nested string
    literals included, is not text.
    """
    out, current, inside, escaped, depth = [], "", False, False, 0
    for character in line:
        if depth:
            if character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
            continue
        if escaped:
            if character == "(":
                if inside:
                    current += INTERPOLATION
                depth = 1
            elif inside:
                current += ESCAPED_TEXT.get(character, character)
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


def words(sentence: str) -> int:
    return len([w for w in re.split(r"\s+", sentence.strip()) if w])


def sentences_of(text: str) -> list[str]:
    text = re.sub(r"\s+", " ", text).strip()
    if not text:
        return []
    return [s.strip() for s in SENTENCE_END.split(text) if s.strip()]


def rider_sentence_blocks(path: Path, kind: str) -> list[tuple[int, str]]:
    """(line, block) pairs worth judging as sentences.

    The block is the CHAINED text — the same `+`-joined authored string the paragraph pass
    reads — not one source literal. A sentence that runs across two literals is one sentence
    to the rider, so it is one sentence to the 20-word rule. The line is the chain's first
    line, so the message still points at an editable place.
    """
    return [(number, block) for number, block in chained_blocks(path, kind)
            if words(block) >= 4 and not SKIP_LITERAL.search(block)]


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
        # An exemption names the target's path (a directory of Swift sources) or the file
        # the sentence is actually in, which is the only way to exempt one file of a
        # directory target rather than all of them.
        why = next((e["why"] for e in exemptions
                    if (relative.startswith(e["path"]) or where.startswith(e["path"]))
                    and e["text"] in s), None)
        if why:
            honoured.append(f"    allowed  {where}: {', '.join(problems)} — {why}")
        else:
            failures.append(f"{where}: {', '.join(problems)} — \"{s[:110]}\"")
    mean = sum(lengths) / len(lengths) if lengths else 0.0
    return failures, honoured, (len(lengths), mean, max(lengths) if lengths else 0)


def chained_blocks(path: Path, kind: str) -> list[tuple[int, str]]:
    """(line, block) pairs — the blocks a rider reads as one, before any skip rule.

    A block is one authored string: a chain of literals joined by `+` across as many
    lines as it takes, cut again at every line break inside it, because a blank line in a
    footer is a new block on the screen. Judging one source line at a time would measure the
    width of the editor, not the length of the text, so both passes read this.
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
        return rider_literals_of(line)

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

    blocks: list[tuple[int, str]] = []
    for number, text in out:
        for block in re.split(r"\n+", text):
            block = block.strip()
            if block:
                blocks.append((number, block))
    return blocks


#: The elements a page author types prose into. Everything else — a `<div>`, a `<section>`,
#: a heading — is layout or a label, and the run of text a stack of them produces is the
#: shape of the markup rather than a paragraph anyone wrote.
BLOCK_TAGS = {"p", "li", "dd", "figcaption", "summary", "td", "th"}


class _Blocks(_Text):
    """The typed blocks of a page: `(line, text)` per `<p>`, `<li>`, `<dd>`, `<figcaption>`,
    `<summary>` and per table cell.

    Inline tags inside a block (`<strong>`, `<a>`, `<code>`, `<span>`) are part of the same
    sentence and vanish; entities are already unescaped by the parser. A newline in the
    source is where the author's editor wrapped and is whitespace like any other, while a
    `<br>` is a line break the rider sees: only the `<br>` cuts the block in two, exactly as
    `\\n` does in a Swift literal. `strip` silences a generated block and every block
    inside it, the way it does for the sentence pass, so both passes read the page
    through the same filter.
    """

    def __init__(self, strip: tuple[str, ...] = ()) -> None:
        super().__init__(strip)
        self.blocks: list[tuple[int, str]] = []
        #: the open typed blocks, innermost last: (tag, line, parts)
        self._open: list[tuple[str, int, list[str]]] = []

    #: A `<br>`, kept apart from the whitespace the markup is wrapped in.
    BREAK = "\x00"

    def handle_starttag(self, tag, attrs):
        if tag == "br" and self._open and not self._silent():
            self._open[-1][2].append(self.BREAK)
        super().handle_starttag(tag, attrs)
        if tag in BLOCK_TAGS and not self._silent():
            self._open.append((tag, self.getpos()[0], []))

    def handle_endtag(self, tag):
        super().handle_endtag(tag)
        # `</ul>` closes an `<li>` whose end tag the author left out, and the stack has
        # already forgotten it: whatever is open past the stack's depth is finished text.
        depth = sum(1 for name, _ in self._stack if name in BLOCK_TAGS)
        while len(self._open) > depth:
            self._emit(*self._open.pop()[1:])

    def handle_data(self, data):
        super().handle_data(data)
        if self._open and not self._silent():
            self._open[-1][2].append(data)

    def close(self):
        super().close()
        while self._open:
            self._emit(*self._open.pop()[1:])

    def _emit(self, line: int, parts: list[str]) -> None:
        for chunk in "".join(parts).split(self.BREAK):
            text = re.sub(r"\s+", " ", chunk).strip()
            if text:
                self.blocks.append((line, text))


#: A line carrying this comment hands its literals back to the code: a selector, a CSS
#: declaration or an id the regexes below cannot tell from a sentence.
JS_SKIP_MARK = "voice: skip"
#: Literals that are code however many words they hold: a URL, a path, a selector, a CSS
#: declaration, a chunk of markup, a MIME type, a date format.
SKIP_JS_LITERAL = re.compile(
    r"^(?:https?://|/|\./|\.\./|#[\w-]|\.[A-Za-z][\w-]*[\s.#\[]|[\w-]+/[\w-]+$)"
    r"|[<>=]|\{\}|&&|\|\||;\s*$|\b[\w-]+\s*:\s*(?:\d|#|var\(|calc\()"
)
#: A chain that carries markup: read it the way a page is read, not as flat text.
JS_MARKUP = re.compile(r"<(?:p|li|dd|figcaption|summary|td|th)\b")
#: A `/` here opens a regular expression rather than dividing. Anything else after a value
#: (`)`, a name, a number) is division, and its body is not text.
JS_REGEX_HEAD = re.compile(
    r"(?:[(,=:\[!&|?{};+\-*%^~]|\b(?:return|typeof|case|in|of|do|else))\s*$")


def _js_string(source: str, i: int, line: int) -> tuple[str, int, int]:
    """The literal starting at `source[i]`, as the rider reads it: `(text, index, line)`.

    Escapes follow `ESCAPED_TEXT` (a `\\n` stays a line break), and a template's `${…}`
    becomes one placeholder the way a Swift `\\(…)` does — the code inside it is not text,
    and counting it would hand the parenthesis rule a bracket no author typed.
    """
    quote = source[i]
    i += 1
    out: list[str] = []
    end = len(source)
    while i < end:
        character = source[i]
        if character == "\\":
            following = source[i + 1] if i + 1 < end else ""
            if following == "\n":
                line += 1
            else:
                out.append(ESCAPED_TEXT.get(following, following))
            i += 2
            continue
        if character == quote:
            return "".join(out), i + 1, line
        if quote == "`" and character == "$" and source[i + 1:i + 2] == "{":
            out.append(INTERPOLATION)
            i, depth = i + 2, 1
            while i < end and depth:
                inner = source[i]
                if inner == "\n":
                    line += 1
                elif inner == "{":
                    depth += 1
                elif inner == "}":
                    depth -= 1
                elif inner in "'\"`":
                    _, i, line = _js_string(source, i, line)
                    continue
                i += 1
            continue
        if character == "\n":
            if quote != "`":          # an unterminated quote: not a literal, give up on it
                return "".join(out), i, line
            line += 1
        out.append(character)
        i += 1
    return "".join(out), i, line


def js_chained_blocks(path: Path) -> list[tuple[int, str, bool]]:
    """`(line, block, markup)` for every authored string in a JavaScript file.

    The same contract as `chained_blocks`: a chain of literals joined by `+` is one block
    and a template literal is one block. A flat block is cut again at every line break
    inside it; a block that builds markup is read by `_Blocks` instead and comes back one
    typed element at a time, with `markup` true. Comments, regular expressions and the
    code inside an interpolation are not text.
    """
    source = path.read_text(encoding="utf-8")
    skipped = {number for number, line in enumerate(source.splitlines(), 1)
               if JS_SKIP_MARK in line}
    chains: list[tuple[int, str]] = []
    chain: list[str] = []
    start = 0
    plus = False                       # only a `+` has been seen since the last literal
    hush = False                       # a `// voice: skip` line inside the chain
    armed = False                      # a `// voice: skip` comment waiting for its string
    i, line, end = 0, 1, len(source)
    head = ""                          # the code before the cursor, for the regex question

    def flush() -> None:
        nonlocal chain, hush, armed
        if chain and not hush:
            chains.append((start, "".join(chain)))
        if chain:
            armed = False              # the marker is spent on the string it named
        chain, hush = [], False

    while i < end:
        character = source[i]
        if character == "\n":
            line, i = line + 1, i + 1
            continue
        if character in " \t\r":
            i += 1
            continue
        if source.startswith("//", i):
            stop = end if source.find("\n", i) < 0 else source.find("\n", i)
            if JS_SKIP_MARK in source[i:stop]:
                armed = True           # hands the next authored string back to the code
            i = stop
            continue
        if source.startswith("/*", i):
            stop = source.find("*/", i + 2)
            stop = end if stop < 0 else stop + 2
            line += source.count("\n", i, stop)
            i = stop
            continue
        if character in "'\"`":
            opened = line
            text, i, line = _js_string(source, i, line)
            if chain and not plus:
                flush()
            if not chain:
                start = opened
            # One marker anywhere in a chain hands the whole chain back to the code: a
            # chain is one authored string, and half of one is not a sentence either.
            hush = hush or armed or any(number in skipped
                                        for number in range(opened, line + 1))
            chain.append(text)
            plus, head = False, "\"\""
            continue
        if character == "+":
            plus = bool(chain)
            i, head = i + 1, head + "+"
            continue
        if character == "/" and JS_REGEX_HEAD.search(head[-16:]):
            i += 1                     # the body of a regular expression, escapes and all
            inside = False
            while i < end and (inside or source[i] != "/"):
                if source[i] == "\\":
                    i += 1
                elif source[i] == "[":
                    inside = True
                elif source[i] == "]":
                    inside = False
                elif source[i] == "\n":
                    break
                i += 1
            i += 1
            flush()
            plus, head = False, "/"
            continue
        flush()
        plus = False
        head += character
        i += 1
    flush()

    blocks: list[tuple[int, str, bool]] = []
    for number, text in chains:
        # **A chain that builds markup is read as markup.** Half this app's rider text is
        # written as a template of `<p>`s, and its newlines are where the editor wrapped,
        # not where the reader's line ends: measured raw it would be a handful of
        # fragments. `_Blocks` is the page extractor, so a `<p>` in a script and a `<p>` on
        # a page are the same paragraph under the same budget.
        if JS_MARKUP.search(text):
            parser = _Blocks()
            parser.feed(text)
            parser.close()
            blocks += [(number, block, True) for _, block in parser.blocks]
            continue
        for block in re.split(r"\n+", text):
            block = block.strip()
            if block:
                blocks.append((number, re.sub(r"\s+", " ", block), False))
    return blocks


def js_rider_blocks(path: Path) -> list[tuple[int, str]]:
    """The blocks of a script that carry a sentence a rider reads.

    A sentence is a run of four words or more closed by `.`, `?` or `!`, or a block of
    eight words and up (a headline with no full stop is still a sentence to the reader).
    A label, a key, a unit and a class name never reach either bar.
    """
    out = []
    for number, block, markup in js_chained_blocks(path):
        # Text lifted out of a `<p>` is prose by construction: only the URL rule applies
        # to it. A flat literal has to clear the wider net, where an `=` or a `<` is a
        # declaration or a tag rather than a sentence.
        if SKIP_LITERAL.search(block) or (not markup and SKIP_JS_LITERAL.search(block)):
            continue
        closed = any(words(part) >= 4 and part.strip()[-1:] in ".?!"
                     for part in re.split(r"(?<=[.?!])\s+", block) if part.strip())
        if closed or words(block) >= 8:
            out.append((number, block))
    return out


def rider_paragraphs(path: Path, kind: str) -> list[tuple[int, str]]:
    """The chained blocks worth measuring as paragraphs."""
    return [(number, block) for number, block in chained_blocks(path, kind)
            if words(block) >= 4 and not SKIP_PARAGRAPH.search(block)]


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
            for number, block in rider_sentence_blocks(f, target.kind):
                for s in sentences_of(block):
                    out.append((f"{rel}:{number}", s))
    elif target.kind == "js":
        for f in sorted(base.glob("*.js")):
            if f.name in target.exclude:
                continue
            rel = f.relative_to(REPO).as_posix()
            for number, block in js_rider_blocks(f):
                note_paragraph(target.label, f"{rel}:{number}", block, target.paragraph_max)
                for s in sentences_of(block):
                    if words(s) >= 4:
                        out.append((f"{rel}:{number}", s))
    elif target.kind == "html":
        raw = base.read_text(encoding="utf-8")
        # **Paragraphs: the blocks the author typed.** Sentences: the page's visible text,
        # headings and labels included, which is the wider net of the two.
        blocks = _Blocks(target.strip + GENERATED)
        blocks.feed(raw)
        blocks.close()
        for number, block in blocks.blocks:
            note_paragraph(target.label, f"{target.path}:{number}", block,
                           target.paragraph_max)
        parser = _Text(target.strip + GENERATED)
        parser.feed(raw)
        parser.close()
        text = "\n".join(parser.parts)
        for para in re.split(r"\n\s*\n", text):
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
                        if (target.path.startswith(e["path"]) or where.startswith(e["path"]))
                        and e["text"] in text), None)
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
