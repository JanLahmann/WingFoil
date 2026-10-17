#!/usr/bin/env python3
"""The ideas riders told Ask CleanJibe, as a digest for the team (docs/channels.md, "Ask CleanJibe").

The assistant Worker (JanLahmann/Fun-with-Quantum, assistant/src/ideas.ts) keeps every idea a
year; this reads the new ones and prints them as Markdown, newest last.

    python3 web/tools/ideas_digest.py                  # the ideas not yet read
    python3 web/tools/ideas_digest.py --since 2026-10-01 --all
    python3 web/tools/ideas_digest.py --mark-read      # print, then mark them read
    python3 web/tools/ideas_digest.py --json           # raw, for a script

The export token is Jan's: ~/.config/cleanjibe/ideas.json ({"token": "..."}, folder 700, file
600) or CJ_IDEAS_TOKEN. It is the Worker secret IDEAS_EXPORT_TOKEN; never commit it.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.request
from collections import defaultdict
from pathlib import Path

BASE = "https://fwq-assistant.jan-35c.workers.dev"
CONFIG = Path.home() / ".config" / "cleanjibe" / "ideas.json"


def token() -> str:
    if os.environ.get("CJ_IDEAS_TOKEN"):
        return os.environ["CJ_IDEAS_TOKEN"]
    try:
        return json.loads(CONFIG.read_text())["token"]
    except (OSError, KeyError, ValueError):
        sys.exit(f"No export token: put {{\"token\": \"…\"}} in {CONFIG} or set CJ_IDEAS_TOKEN.")


def call(path: str, body: dict | None = None) -> dict | None:
    req = urllib.request.Request(BASE + path, method="POST" if body else "GET",
                                 data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": f"Bearer {token()}",
                                          "Content-Type": "application/json",
                                          "User-Agent": "cleanjibe-ideas-digest"})
    with urllib.request.urlopen(req, timeout=30) as r:
        raw = r.read()
    return json.loads(raw) if raw else None


def digest(ideas: list[dict]) -> str:
    if not ideas:
        return "No new ideas."
    by_week: dict[str, list[dict]] = defaultdict(list)
    for i in ideas:
        by_week[i["ts"][:10]].append(i)
    out = [f"# Ideas from riders · {len(ideas)}", ""]
    for day in sorted(by_week):
        out.append(f"## {day}")
        for i in by_week[day]:
            where = " · ".join(str(x) for x in (i.get("surface"), i.get("channel"),
                                                i.get("app_version") and f"{i['app_version']} ({i.get('build') or '–'})",
                                                i.get("context"), i.get("locale")) if x)
            out.append(f"- **{i['summary']}**  \n  “{i['words']}”  \n  {where} · `{i['id'][:8]}`")
        out.append("")
    return "\n".join(out)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--since", help="ISO date, default: all")
    ap.add_argument("--all", action="store_true", help="read and noted ones too")
    ap.add_argument("--mark-read", action="store_true", help="mark the printed ideas read")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    q = "site=cleanjibe" + ("" if a.all else "&status=new") + (f"&since={a.since}" if a.since else "")
    ideas = call(f"/ideas/export?{q}")["ideas"]
    print(json.dumps(ideas, indent=2, ensure_ascii=False) if a.json else digest(ideas))
    if a.mark_read:
        for i in ideas:
            if i["status"] == "new":
                call("/ideas/mark", {"id": i["id"], "status": "read"})
        print(f"\n{sum(i['status'] == 'new' for i in ideas)} marked read.", file=sys.stderr)


if __name__ == "__main__":
    main()
