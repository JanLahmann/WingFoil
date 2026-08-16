#!/usr/bin/env python3
"""Copy `lab/src/wingfoil_lab` into `web/lab_bundle/` so Pyodide can import it.

The web app runs the *identical* lab code — there is no third implementation of the
analysis. GitHub Pages cannot build a wheel, so the package is shipped as plain sources
and mounted into the Pyodide virtual filesystem at load time.

    cd web && python3 tools/bundle_lab.py

Re-run this whenever anything under `lab/src/wingfoil_lab/` changes. The generated
`lab_bundle/MANIFEST.json` records the source hashes; `--check` verifies the bundle is
current without writing anything (exit 1 = stale).

The hand-written glue modules (`web_entry.py`, `library.py`) are never touched by this
script — it only lists them in `FILES.json` so the worker knows to mount them.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

WEB = Path(__file__).resolve().parents[1]
REPO = WEB.parent
SRC = REPO / "lab" / "src" / "wingfoil_lab"
DEST = WEB / "lab_bundle" / "wingfoil_lab"
MANIFEST = WEB / "lab_bundle" / "MANIFEST.json"

# Hand-written, not generated: the browser-only Python that sits on top of the lab.
# Listed here so `FILES.json` (the worker's mount list) stays complete.
GLUE = ["web_entry.py", "library.py"]


def _sources() -> list[Path]:
    return sorted(p for p in SRC.rglob("*.py") if "__pycache__" not in p.parts)


def _manifest() -> dict:
    files = {}
    for p in _sources():
        files[p.relative_to(SRC).as_posix()] = hashlib.sha256(p.read_bytes()).hexdigest()[:16]
    return {
        "source": "lab/src/wingfoil_lab",
        "generator": "web/tools/bundle_lab.py",
        "note": "Generated — do not edit by hand. Re-run bundle_lab.py after lab changes.",
        "files": files,
    }


def check() -> int:
    want = _manifest()
    if not MANIFEST.exists():
        print("lab_bundle/MANIFEST.json missing — run: python3 tools/bundle_lab.py", file=sys.stderr)
        return 1
    have = json.loads(MANIFEST.read_text())
    if have.get("files") != want["files"]:
        print("lab_bundle is STALE — run: python3 tools/bundle_lab.py", file=sys.stderr)
        for name in sorted(set(want["files"]) | set(have.get("files", {}))):
            if want["files"].get(name) != have.get("files", {}).get(name):
                print(f"  differs: {name}", file=sys.stderr)
        return 1
    print(f"lab_bundle is current ({len(want['files'])} modules)")
    return 0


def bundle() -> int:
    if not SRC.is_dir():
        print(f"lab sources not found: {SRC}", file=sys.stderr)
        return 1
    if DEST.exists():
        shutil.rmtree(DEST)
    DEST.mkdir(parents=True)
    for p in _sources():
        target = DEST / p.relative_to(SRC)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(p, target)
    man = _manifest()
    MANIFEST.write_text(json.dumps(man, indent=2) + "\n")
    names = sorted(man["files"])
    print(f"copied {len(names)} modules -> {DEST.relative_to(REPO)}")
    for n in names:
        print(f"  {n}")
    # The loader needs an explicit file list (no directory listing over HTTP).
    listing = WEB / "lab_bundle" / "FILES.json"
    for g in GLUE:
        if not (WEB / "lab_bundle" / g).exists():
            print(f"missing hand-written glue: lab_bundle/{g}", file=sys.stderr)
            return 1
    listing.write_text(json.dumps(GLUE + [f"wingfoil_lab/{n}" for n in names],
                                  indent=2) + "\n")
    print(f"wrote {listing.relative_to(REPO)} and {MANIFEST.relative_to(REPO)}")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true",
                    help="verify the bundle matches lab/ (exit 1 if stale), write nothing")
    args = ap.parse_args(argv)
    return check() if args.check else bundle()


if __name__ == "__main__":
    raise SystemExit(main())
