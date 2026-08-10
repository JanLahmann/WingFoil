#!/usr/bin/env python3
"""Download original activity FITs from intervals.icu into fixtures/.

Auth: personal API key (intervals.icu → Settings → Developer → API Key).
    export ICU_API_KEY=xxxx        # or pass --key

Usage (from lab/):
    uv run python tools/download_icu.py --oldest 2025-08-01 [--dry-run]

Fetches the activity list, keeps watersport sessions (type Windsurf, or names matching
wing/foil/surf keywords — catches the Walk-typed FoilMotion/"Wingfoiling" recordings),
downloads each original file via GET /api/v1/activity/{id}/file, and writes
fixtures/sessions/{windsurf-native|other-apps|ciq}/YYYY-MM-DD_<slug>_<source>.fit
per the fixtures/README.md naming convention.
"""

from __future__ import annotations

import argparse
import gzip
import io
import os
import re
import sys
import zipfile
from datetime import date
from pathlib import Path

import requests

BASE = "https://intervals.icu/api/v1"
UA = {"User-Agent": "WingFoil-lab/0.1 (personal use)"}
FIXTURES = Path(__file__).resolve().parents[2] / "fixtures" / "sessions"

WATERSPORT_TYPES = {"Windsurf", "Kitesurf", "Sail", "Surfing", "StandUpPaddling"}
NAME_RE = re.compile(r"wing|foil|windsurf|kite|surf|sup", re.IGNORECASE)


def auth(key: str):
    return ("API_KEY", key)


def list_activities(key: str, oldest: str, newest: str) -> list[dict]:
    r = requests.get(
        f"{BASE}/athlete/0/activities",
        params={"oldest": oldest, "newest": newest},
        auth=auth(key), headers=UA, timeout=60,
    )
    r.raise_for_status()
    return r.json()


def is_watersport(a: dict) -> bool:
    if a.get("type") in WATERSPORT_TYPES:
        return True
    return bool(NAME_RE.search(a.get("name") or ""))


def source_of(a: dict) -> tuple[str, str]:
    """-> (subdir, source-slug) per fixtures/README.md."""
    name = (a.get("name") or "").lower()
    if a.get("type") == "Windsurf":
        return "windsurf-native", "native"
    if "foilmotion" in name:
        return "other-apps", "foilmotion"
    if "wingfoil" in name.replace(" ", ""):
        return "other-apps", "wingfoiling"
    return "other-apps", "unknown"


def unwrap(data: bytes) -> bytes:
    """/file may return raw FIT, gzip, or a ZIP containing the FIT."""
    if data[:2] == b"\x1f\x8b":
        data = gzip.decompress(data)
    if data[:2] == b"PK":
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            fits = [n for n in z.namelist() if n.lower().endswith(".fit")]
            if not fits:
                raise ValueError("ZIP contains no .fit")
            data = z.read(fits[0])
    if data[8:12] != b".FIT":
        raise ValueError(f"not a FIT file (header {data[:16]!r})")
    return data


def download(key: str, activity_id: str) -> bytes:
    r = requests.get(f"{BASE}/activity/{activity_id}/file", auth=auth(key), headers=UA, timeout=120)
    r.raise_for_status()
    return unwrap(r.content)


def slugify(name: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", (name or "session").lower()).strip("-")
    return slug[:40] or "session"


def _key_from_dotenv() -> str | None:
    """Read ICU_API_KEY from lab/.env (gitignored) so the key never lands in shell history."""
    env_file = Path(__file__).resolve().parents[1] / ".env"
    if not env_file.exists():
        return None
    for line in env_file.read_text().splitlines():
        if line.strip().startswith("ICU_API_KEY="):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    return None


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--key", default=os.environ.get("ICU_API_KEY") or _key_from_dotenv(),
                   help="intervals.icu API key (or ICU_API_KEY env / lab/.env)")
    p.add_argument("--oldest", default="2025-01-01")
    p.add_argument("--newest", default=date.today().isoformat())
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()
    if not args.key:
        p.error("no API key: set ICU_API_KEY or pass --key")

    acts = [a for a in list_activities(args.key, args.oldest, args.newest) if is_watersport(a)]
    print(f"{len(acts)} watersport activities between {args.oldest} and {args.newest}")
    got, skipped = 0, 0
    for a in acts:
        start = a.get("start_date_local") or a.get("start_date") or "unknown"
        day = start[:10]
        hhmm = start[11:16].replace(":", "") if len(start) >= 16 else "0000"
        subdir, source = source_of(a)
        slug = slugify(a.get("name"))
        dest = FIXTURES / subdir / f"{day}-{hhmm}_{slug}_{source}.fit"
        # Our CIQ app records type=Windsurf too; only the FIT bytes can tell it
        # from a native session, so a previously sniffed ciq/ copy also counts.
        ciq_dest = FIXTURES / "ciq" / f"{day}-{hhmm}_{slug}_ciq.fit"
        state = "->"
        if dest.exists() or ciq_dest.exists():
            skipped += 1
            state = "exists"
        print(f"  {a['id']:>12}  {a.get('type', '?'):10} {day}  {state} {dest.relative_to(FIXTURES.parent)}")
        if args.dry_run or state == "exists":
            continue
        try:
            data = download(args.key, a["id"])
            if b"foil_state" in data:  # our dev-field name: definitionally a WingFoil CIQ file
                dest = ciq_dest
                print(f"     ciq dev fields found -> {dest.relative_to(FIXTURES.parent)}")
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(data)
            got += 1
        except Exception as e:  # noqa: BLE001 - report and continue
            print(f"     !! {e}")
    print(f"downloaded {got}, skipped {skipped} existing")
    return 0


if __name__ == "__main__":
    sys.exit(main())
