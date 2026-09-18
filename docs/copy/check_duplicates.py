#!/usr/bin/env python3
"""Pattern F, made checkable: **one sentence, one home — inside the app.**

`web/tools/verify_unique.py` holds the site to it; this holds the kit's Help/ and
Presentation/ sources and the app's Features. Every string literal is split into sentences;
a sentence of eight or more words that appears in two different files fails, unless it is one
the copy contract deliberately shares (docs/copy/*.json — the promise, the invitation, the
prompts, the glossary lines, the class lines, the door names) or is written down in
`docs/copy/duplicate-exemptions.json` as `{text, why}`.

    python3 docs/copy/check_duplicates.py            # exit 1 on any duplicate
    python3 docs/copy/check_duplicates.py --report   # list only
"""
from __future__ import annotations

import json
import re
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "docs" / "copy"))
from check_voice import rider_paragraphs, sentences_of, words  # noqa: E402

DIRS = ["ios/WingFoilKit/Sources/WingFoilKit/Help", "ios/WingFoilKit/Sources/WingFoilKit/Presentation",
        "ios/WingFoil/Features"]
MIN_WORDS = 8
EXEMPTIONS = REPO / "docs" / "copy" / "duplicate-exemptions.json"


def shared_sentences() -> set[str]:
    """Every sentence docs/copy owns, normalised; those may appear anywhere."""
    out = set()
    for f in (REPO / "docs" / "copy").glob("*.json"):
        def walk(x):
            if isinstance(x, dict):
                for v in x.values():
                    walk(v)
            elif isinstance(x, list):
                for v in x:
                    walk(v)
            elif isinstance(x, str):
                for s in sentences_of(x):
                    out.add(norm(s))
        walk(json.loads(f.read_text(encoding="utf-8")))
    return out


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s.strip().lower().rstrip(".:"))


def main(argv=None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    report = "--report" in argv
    shared = shared_sentences()
    exempt = {norm(e["text"]): e["why"] for e in (
        json.loads(EXEMPTIONS.read_text(encoding="utf-8")) if EXEMPTIONS.exists() else [])}
    homes: dict[str, set[str]] = defaultdict(set)
    sample: dict[str, str] = {}
    for d in DIRS:
        for f in sorted((REPO / d).rglob("*.swift")):
            rel = f.relative_to(REPO).as_posix()
            # One paragraph reader for both lints (`check_voice.rider_paragraphs`): a
            # sentence that runs across three source lines is one sentence, and half of it
            # is not a sentence that has two homes.
            for _, paragraph in rider_paragraphs(f, "swift"):
                for s in sentences_of(paragraph):
                    if words(s) >= MIN_WORDS:
                        key = norm(s)
                        homes[key].add(rel)
                        sample.setdefault(key, s)
    dups = [(k, sorted(v)) for k, v in homes.items() if len(v) > 1 and k not in shared]
    honoured, failures = [], []
    for k, files in sorted(dups):
        if k in exempt:
            honoured.append(f"    allowed  \"{sample[k][:80]}\" in {', '.join(files)} — {exempt[k]}")
        else:
            failures.append(f"  \"{sample[k][:90]}\"\n      {', '.join(files)}")
    print(f"app sentences of {MIN_WORDS}+ words: {len(homes)}; shared by docs/copy: ignored; "
          f"duplicates: {len(failures)} ({len(honoured)} allowed)")
    for line in failures:
        print(line)
    for line in honoured:
        print(line)
    if failures and not report:
        print("\nFAILED — one sentence, one home (docs/review-checklist.md, pattern F).")
        return 1
    print("PASSED — no sentence has two homes in the app." if not report else "report only")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
