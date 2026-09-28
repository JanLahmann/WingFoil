#!/usr/bin/env python3
"""**No rider sentence is typed into the browser app.** It is said through the app's words.

    python3 web/tools/check_web_literals.py            # PASS, or every offending sentence
    python3 web/tools/check_web_literals.py --list     # every sentence the allow-list keeps

Jan, 28 September 2026: *"the iPhone app is the golden master for layout and wording; the
web is generated from it or mostly identical"*. The kit authors every sentence the phone
shows (``AppShellCopy`` and the constants its export test names), ``AppShellCopyExportTests``
writes them to docs/copy/app-words.json, and ``web/tools/make_app_copy.py`` turns that into
``WORDS`` and ``say()`` in web/js/appcopy.js — and into the text of every ``data-w`` element
of web/app/index.html. This check holds the browser to it:

  1. **web/js/*.js** — every authored string that carries a sentence (the rule is
     ``check_voice.js_rider_blocks``: four words closed by ``.``, ``?`` or ``!``, or eight
     words) FAILS, unless docs/web-parity/web-only.json keeps it with a reason. The two
     generated modules (``appcopy.js``, ``copy.js``) are the words' home and are not read.
  2. **web/app/index.html** — the same rule over the page's typed blocks and its rider
     attributes (``placeholder``, ``aria-label``, ``title``, ``alt``, ``content``,
     ``data-empty``). A ``data-w`` element is generated and is not read.
  3. **Every key said is a key the kit wrote.** ``say("group.key")`` and
     ``data-w="group.key"`` must name an entry of ``WORDS``.
  4. **The allow-list stays true.** An entry that no longer matches anything FAILS, so a
     sentence that moved to the kit takes its exemption with it.

An allow-list entry is ``{path, text, reason}``: ``path`` is the file, ``text`` a substring
of the offending block (placeholders read as ``…``), ``reason`` why the phone has no twin
for it — a browser-only function (storage, the engine download, a mail link), or a twin
another verifier already pins. docs/web-parity/words.md is the full inventory.

Stdlib only, no network, like every verifier in this directory.
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
sys.path.insert(0, str(REPO / "docs" / "copy"))
from check_voice import SKIP_LITERAL, js_rider_blocks, words  # noqa: E402

JS = WEB / "js"
PAGE = WEB / "app" / "index.html"
ALLOW = REPO / "docs" / "web-parity" / "web-only.json"
WORDS_JSON = REPO / "docs" / "copy" / "app-words.json"
CLASSES_JSON = REPO / "docs" / "copy" / "recording-classes.json"

#: The generated modules: the words' home on this side, written from docs/copy.
GENERATED = {"appcopy.js", "copy.js"}

#: The attributes a rider reads or hears.
RIDER_ATTRS = {"placeholder", "aria-label", "title", "alt", "content", "data-empty"}

#: The elements a sentence is typed into. The innermost open one owns the text.
BLOCKS = {"p", "li", "dd", "dt", "figcaption", "summary", "td", "th", "h1", "h2", "h3",
          "h4", "h5", "h6", "label", "button", "legend", "option", "div", "section",
          "header", "footer", "article", "dialog", "form", "title"}
SILENT = {"script", "style", "svg", "template", "noscript"}
VOID = {"br", "img", "input", "meta", "link", "hr", "source", "wbr", "area", "base", "col",
        "embed", "param", "track"}

SAY = re.compile(r"""\bsay\(\s*["']([\w]+\.[\w]+)["']""")


def is_sentence(block: str) -> bool:
    """`check_voice.js_rider_blocks`' bar, for a block that did not come from a script."""
    if SKIP_LITERAL.search(block):
        return False
    closed = any(words(part) >= 4 and part.strip()[-1:] in ".?!"
                 for part in re.split(r"(?<=[.?!])\s+", block) if part.strip())
    return closed or words(block) >= 8


class Page(HTMLParser):
    """`(line, text)` per typed block and per rider attribute, skipping `data-w` subtrees."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.blocks: list[tuple[int, str]] = []
        self.keys: list[tuple[int, str]] = []
        self._stack: list[tuple[str, int, list[str], bool]] = []   # tag, line, parts, quiet

    def _quiet(self) -> bool:
        return any(entry[3] for entry in self._stack)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        line = self.getpos()[0]
        generated = "data-w" in attrs
        if generated:
            self.keys.append((line, attrs["data-w"]))
        quiet = self._quiet() or generated or tag in SILENT
        if not quiet and not (tag == "meta" and attrs.get("name") in ("viewport",)):
            for name in RIDER_ATTRS:
                value = attrs.get(name)
                if value and is_sentence(value):
                    self.blocks.append((line, value))
        if tag in VOID:
            return
        if tag in BLOCKS or tag in SILENT or generated:
            self._stack.append((tag, line, [], quiet))
        else:
            self._stack.append((tag, line, None, quiet))  # inline: text goes to the block

    def handle_endtag(self, tag):
        if tag in VOID:
            return
        while self._stack:
            name, line, parts, quiet = self._stack.pop()
            if parts is not None and not quiet:
                text = re.sub(r"\s+", " ", "".join(parts)).strip()
                if text and is_sentence(text):
                    self.blocks.append((line, text))
            if name == tag:
                break

    def handle_data(self, data):
        for name, line, parts, quiet in reversed(self._stack):
            if parts is not None:
                parts.append(data)
                return


def known_keys() -> set[str]:
    groups = json.loads(WORDS_JSON.read_text(encoding="utf-8"))["groups"]
    keys = {f"{group}.{key}" for group, lines in groups.items() for key in lines}
    classes = json.loads(CLASSES_JSON.read_text(encoding="utf-8"))["classes"]
    keys |= {f"recordingClass.{entry['id']}" for entry in classes}
    return keys


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--list", action="store_true",
                        help="print every sentence the allow-list keeps, with its reason")
    args = parser.parse_args(argv)

    allow = json.loads(ALLOW.read_text(encoding="utf-8"))["entries"]
    used = [0] * len(allow)
    keys = known_keys()
    failures: list[str] = []
    kept: list[str] = []

    def judge(path: str, line: int, block: str) -> None:
        for index, entry in enumerate(allow):
            if entry["path"] == path and entry["text"] in block:
                used[index] += 1
                kept.append(f"{path}:{line}  [{entry['reason']}]  {block[:90]}")
                return
        failures.append(f"{path}:{line}: a rider sentence typed into web code: {block!r}")

    for script in sorted(JS.glob("*.js")):
        if script.name in GENERATED:
            continue
        rel = str(script.relative_to(REPO))
        for line, block in js_rider_blocks(script):
            judge(rel, line, block)
        source = script.read_text(encoding="utf-8")
        for match in SAY.finditer(source):
            if match.group(1) not in keys:
                number = source.count("\n", 0, match.start()) + 1
                failures.append(f"{rel}:{number}: say({match.group(1)!r}) is not in "
                                "docs/copy/app-words.json")

    page = Page()
    page.feed(PAGE.read_text(encoding="utf-8"))
    page.close()
    rel = str(PAGE.relative_to(REPO))
    for line, block in page.blocks:
        judge(rel, line, block)
    for line, key in page.keys:
        if key not in keys:
            failures.append(f"{rel}:{line}: data-w={key!r} is not in docs/copy/app-words.json")

    for entry, count in zip(allow, used):
        if not entry.get("reason"):
            failures.append(f"docs/web-parity/web-only.json: {entry['text']!r} has no reason")
        if count == 0:
            failures.append(f"docs/web-parity/web-only.json: {entry['path']} no longer says "
                            f"{entry['text']!r}. Remove the entry.")

    if args.list:
        print("\n".join(kept))
    if failures:
        print("\n".join(failures), file=sys.stderr)
        print(f"\nFAIL: {len(failures)} — say the sentence through say('group.key') from "
              "js/appcopy.js (the kit writes it: AppShellCopy, then COPY_WRITE=1 swift test "
              "--filter AppShellCopyExportTests, then make_app_copy.py), or keep it in "
              "docs/web-parity/web-only.json with the reason the phone has no twin.",
              file=sys.stderr)
        return 1
    print(f"web literals: no rider sentence typed into web/js or web/app "
          f"({len(kept)} kept by docs/web-parity/web-only.json, {len(allow)} entries)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
