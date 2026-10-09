#!/usr/bin/env python3
"""The browser app's first run is fast, and what it downloads it keeps (rider review move 8).

Stdlib only, instant. Four promises the analyzer makes to a first visitor, each of which a
later edit could break without any other check noticing:

1. **The example needs no engine.** `web/example/ExampleSession.analysis.json` is stamped
   with the lab's `ENGINE_VERSION` and the hash of the sources it was built from, it
   describes the FIT that ships beside it, the service worker precaches both, and the page
   asks for it under the name the generator used (X4). The byte-for-byte regeneration
   needs the engine and is `verify_web_entry.py`'s; this is the stamp.
2. **The runtime survives a deploy.** sw.js names its runtime cache after the Pyodide and
   fitdecode pins, never after `VERSION`, and its two pins are the worker's (X5).
3. **The library asks to be kept.** js/store.js calls `navigator.storage.persist()` (X3).
4. **Safari's seven days are said.** Settings → Your data carries the line (X3).

    python3 web/tools/verify_first_run.py

Exit 0 = all held; exit 1 = the failures are listed.
"""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

WEB = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(WEB / "tools"))
import make_example                                                     # noqa: E402

failures: list[str] = []


def check(ok: bool, message: str) -> None:
    if not ok:
        failures.append(message)


def const(text: str, name: str) -> str | None:
    m = re.search(rf'^const {name} = "([^"]+)";', text, re.M)
    return m.group(1) if m else None


def main() -> int:
    sw = (WEB / "sw.js").read_text()
    worker = (WEB / "js" / "worker.js").read_text()
    app = (WEB / "js" / "app.js").read_text()
    store = (WEB / "js" / "store.js").read_text()
    page = (WEB / "app" / "index.html").read_text()

    # 1. the example
    for p in make_example.stamp_problems():
        failures.append(f"example analysis: {p}. Run python3 web/tools/bundle_lab.py")
    if make_example.OUT.exists():
        pre = json.loads(make_example.OUT.read_text())
        raw = make_example.FIT.read_bytes()
        check(pre.get("fitBytes") == len(raw)
              and pre.get("fitSha256") == hashlib.sha256(raw).hexdigest(),
              "example analysis: describes another recording than web/example/ExampleSession.fit")
        check(set(pre.get("presentations", {})) ==
              {"onlyVerified", "preferVerified", "includeUnverified"},
              "example analysis: one presentation per Speed records choice is missing")
        check(bool(pre.get("digest")), "example analysis: no library digest")
    for path in ("example/ExampleSession.fit", "example/ExampleSession.analysis.json"):
        check(f'"{path}"' in sw, f"sw.js does not precache {path}")
    check(const(app, "EXAMPLE_NAME") == make_example.NAME,
          f"js/app.js EXAMPLE_NAME is not make_example.NAME ({make_example.NAME})")
    check("ExampleSession.analysis.json" in app, "js/app.js does not read the example analysis")

    # 2. the runtime cache
    sw_pyodide, sw_fit = const(sw, "PYODIDE_VERSION"), const(sw, "FITDECODE_VERSION")
    wk_pyodide = const(worker, "PYODIDE_VERSION")
    wk_fit = (const(worker, "FITDECODE") or "").partition("==")[2] or None
    check(sw_pyodide is not None and sw_pyodide == wk_pyodide,
          f"sw.js PYODIDE_VERSION {sw_pyodide} is not js/worker.js's {wk_pyodide}")
    check(sw_fit is not None and sw_fit == wk_fit,
          f"sw.js FITDECODE_VERSION {sw_fit} is not js/worker.js's fitdecode pin {wk_fit}")
    runtime = re.search(r"^const RUNTIME = `([^`]+)`;", sw, re.M)
    check(runtime is not None, "sw.js has no RUNTIME cache name")
    if runtime:
        name = runtime.group(1)
        check("${VERSION}" not in name, "sw.js keys the runtime cache to VERSION again")
        check("${PYODIDE_VERSION}" in name and "${FITDECODE_VERSION}" in name,
              "sw.js runtime cache name does not carry both pins")
    check(re.search(r"keep = new Set\(\[[^\]]*\bRUNTIME\b", sw) is not None,
          "sw.js activate does not keep the runtime cache")

    # 3. persist
    check("navigator.storage.persist()" in store, "js/store.js never asks for persistent storage")

    # 4. Safari
    check('id="safari-note"' in page and "seven days" in page,
          "app/index.html lost the Safari seven-day line in Your data")

    if failures:
        for f in failures:
            print(f"FAIL  {f}", file=sys.stderr)
        return 1
    print(f"first run: example pre-analysed (engine {make_example.engine_version()}), "
          f"runtime cache keyed to pyodide {sw_pyodide} + fitdecode {sw_fit}, "
          "persist asked, Safari line present")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
