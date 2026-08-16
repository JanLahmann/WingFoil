#!/usr/bin/env python3
"""Fail when a generated presentation-token artifact no longer matches design/tokens.json.

Same shape as `web/tools/bundle_lab.py --check`: regenerate into a temporary directory,
compare byte for byte, exit 1 with the offending file named. A colour edited straight
into `EventMarkerStyle.swift` or `viz.js` — or a token edited without re-running the
generator — is caught here rather than by a rider noticing that the two apps disagree.

    python3 design/check_tokens.py --check

Exit 0 = the three artifacts are current; exit 1 = the message says which is stale.
"""

from __future__ import annotations

import argparse
import difflib
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import generate_tokens as gen                                    # noqa: E402

REPO = gen.REPO


def check() -> int:
    """Write the artifacts to a scratch tree, then compare bytes with what is committed."""
    stale: list[str] = []
    with tempfile.TemporaryDirectory(prefix="wingfoil-tokens-") as tmp:
        root = Path(tmp)
        for path, content in gen.artifacts().items():
            rel = path.relative_to(REPO)
            scratch = root / rel
            scratch.parent.mkdir(parents=True, exist_ok=True)
            scratch.write_text(content, encoding="utf-8")
            want = scratch.read_bytes()
            have = path.read_bytes() if path.exists() else None
            if have == want:
                continue
            stale.append(rel.as_posix())
            if have is None:
                print(f"MISSING {rel.as_posix()}", file=sys.stderr)
                continue
            diff = difflib.unified_diff(
                have.decode("utf-8", "replace").splitlines(),
                want.decode("utf-8", "replace").splitlines(),
                fromfile=f"committed/{rel.as_posix()}", tofile=f"generated/{rel.as_posix()}",
                lineterm="", n=1)
            print("\n".join(list(diff)[:40]), file=sys.stderr)

    if stale:
        print("design tokens are STALE — run: python3 design/generate_tokens.py",
              file=sys.stderr)
        for name in stale:
            print(f"  differs: {name}", file=sys.stderr)
        return 1
    print(f"design tokens are current ({len(gen.artifacts())} artifacts)")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true",
                    help="verify only (the default; the flag exists so CI reads plainly)")
    ap.parse_args(argv)
    return check()


if __name__ == "__main__":
    raise SystemExit(main())
