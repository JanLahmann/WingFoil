#!/usr/bin/env python
"""Cut a time span out of a FIT file, for simulator replay.

Keeps the file_id / device_info / (optional) developer field definitions from the
source and copies through only the `record` messages whose timestamp falls inside
[--start, --end] (seconds relative to the first record of the source file).
Timestamps are preserved as-is; the Connect IQ simulator replays record-by-record
so only the ordering and the 1 Hz spacing matter.

Usage:
    cd lab && uv run python tools/clip_fit.py SRC.fit OUT.fit --start 4000 --end 4610
    cd lab && uv run python tools/clip_fit.py SRC.fit --list      # show span + density
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from fit_tool.fit_file import FitFile
from fit_tool.fit_file_builder import FitFileBuilder
from fit_tool.profile.messages.record_message import RecordMessage
from fit_tool.profile.messages.file_id_message import FileIdMessage
from fit_tool.profile.messages.developer_data_id_message import DeveloperDataIdMessage
from fit_tool.profile.messages.field_description_message import FieldDescriptionMessage

# copied through ahead of the records so developer fields on `record` stay resolvable
PREAMBLE = (FileIdMessage, DeveloperDataIdMessage, FieldDescriptionMessage)


def _record_ts(msg) -> float | None:
    ts = getattr(msg, "timestamp", None)
    return None if ts is None else float(ts) / 1000.0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src", type=Path)
    ap.add_argument("out", type=Path, nargs="?")
    ap.add_argument("--start", type=float, default=0.0, help="seconds from first record")
    ap.add_argument("--end", type=float, default=float("inf"))
    ap.add_argument("--list", action="store_true", help="only report the source span")
    args = ap.parse_args(argv)

    src = FitFile.from_file(str(args.src))
    msgs = [r.message for r in src.records]

    recs = [m for m in msgs if isinstance(m, RecordMessage) and _record_ts(m) is not None]
    if not recs:
        print("no record messages with timestamps", file=sys.stderr)
        return 1
    t0 = _record_ts(recs[0])
    span = _record_ts(recs[-1]) - t0

    if args.list or args.out is None:
        print(f"{args.src.name}: {len(recs)} records, span {span:.0f}s")
        return 0

    keep = [m for m in recs if args.start <= _record_ts(m) - t0 <= args.end]
    if not keep:
        print("empty selection", file=sys.stderr)
        return 1

    builder = FitFileBuilder(auto_define=True)
    for m in msgs:
        if isinstance(m, PREAMBLE):
            builder.add(m)
    for m in keep:
        builder.add(m)

    out = builder.build()
    out.to_file(str(args.out))
    kept_span = _record_ts(keep[-1]) - _record_ts(keep[0])
    print(f"wrote {args.out} — {len(keep)} records, {kept_span:.0f}s "
          f"(source t {args.start:.0f}..{min(args.end, span):.0f})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
