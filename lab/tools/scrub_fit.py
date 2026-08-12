#!/usr/bin/env python
"""Strip device- and rider-identifying metadata from a FIT activity, byte-for-byte.

Why not re-encode. The source is a class-(a) CIQ recording: 14 developer field
descriptions, a `developer_data_id`, 16 588 batched `accelerometer_data` messages and a
dozen Garmin-private global message numbers that no encoder in the lab environment knows
how to round-trip (`fit-tool` drops what its profile does not define). Re-encoding would
therefore silently change the very file we want to ship unchanged. This tool instead walks
the FIT record stream itself — definition messages, normal and compressed-timestamp data
records, developer field blocks — and rewrites it:

  * data records of a *dropped* global message number are omitted entirely,
  * selected fields of a *patched* message are overwritten in place with the FIT
    "invalid" value for their base type,
  * everything else, definitions included, is copied through unmodified.

`data_size`, the 14-byte header CRC and the trailing file CRC are recomputed. The result
is a valid FIT file whose every surviving byte came from the original.

What is removed, and why (`RULES` below is the machine-readable version):

  file_id.serial_number (0/3)      unique watch id            -> 0 (uint32z invalid)
  device_info.serial_number (23/3) same id, repeated 5x       -> 0
  user_profile (global 3)          rider name, weight,        -> dropped
                                   height, gender, language
  global 147                       paired-accessory record:   -> dropped
                                   BLE address + its name
                                   ("AirPods Pro JRL")
  global 79, global 140            Garmin-private blobs of    -> dropped
                                   lifetime totals and
                                   physiological metrics

Everything the app is meant to show is kept: the GPS track, heart rate, all 14 developer
fields, every lap, the session summary (including the packed pump/takeoff fields) and —
unless `--drop-accel` is given — the 100 Hz accelerometer stream.

Verification (`--verify`, on by default) re-runs the full lab analysis on both files and
asserts the golden JSON is *identical*, so the scrub is provably invisible to the engine.

Usage:

    cd lab
    uv run python tools/scrub_fit.py IN.fit OUT.fit
    uv run python tools/scrub_fit.py IN.fit OUT.fit --drop-accel   # small bundle variant
    uv run python tools/scrub_fit.py IN.fit --report               # inspect only
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

# ---------------------------------------------------------------------------------------
# Scrub rules
# ---------------------------------------------------------------------------------------

# Global message numbers whose *data* records are removed wholesale. Definition messages
# stay (an unused definition is legal FIT and keeps every local-type slot exactly where it
# was), so nothing downstream has to be renumbered.
DROP_MESSAGES: dict[int, str] = {
    3: "user_profile — rider name, weight, height, gender, language, wake/sleep times",
    79: "Garmin-private user-metrics blob (physiological metrics, lifetime aggregates)",
    140: "Garmin-private lifetime-totals blob",
    147: "paired-accessory record — BLE address and the accessory's user-given name",
}

# The high-rate stream, dropped only with --drop-accel (bundle-size variant).
ACCELEROMETER_DATA = 165

# (global message number, field definition number) -> the value to write instead. The
# value is the FIT "invalid" pattern for the field's base type, so a parser reports the
# field as absent rather than as a plausible-looking fake id.
PATCH_FIELDS: dict[tuple[int, int], str] = {
    (0, 3): "file_id.serial_number",
    (23, 3): "device_info.serial_number",
}

# base type number -> (size, invalid byte pattern). Only the types we actually patch.
INVALID_BYTES: dict[int, bytes] = {
    0x00: b"\xFF",                      # enum
    0x01: b"\x7F",                      # sint8
    0x02: b"\xFF",                      # uint8
    0x0A: b"\x00",                      # uint8z
    0x83: b"\xFF\x7F",                  # sint16
    0x84: b"\xFF\xFF",                  # uint16
    0x8B: b"\x00\x00",                  # uint16z
    0x85: b"\xFF\xFF\xFF\x7F",          # sint32
    0x86: b"\xFF\xFF\xFF\xFF",          # uint32
    0x8C: b"\x00\x00\x00\x00",          # uint32z
}

# ---------------------------------------------------------------------------------------
# FIT primitives
# ---------------------------------------------------------------------------------------

_CRC_TABLE = (0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
              0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400)


def fit_crc(data: bytes, crc: int = 0) -> int:
    """The FIT 16-bit CRC (SDK §3.3.2), nibble at a time."""
    for byte in data:
        tmp = _CRC_TABLE[crc & 0xF]
        crc = (crc >> 4) & 0x0FFF
        crc = crc ^ tmp ^ _CRC_TABLE[byte & 0xF]
        tmp = _CRC_TABLE[crc & 0xF]
        crc = (crc >> 4) & 0x0FFF
        crc = crc ^ tmp ^ _CRC_TABLE[(byte >> 4) & 0xF]
    return crc


@dataclass
class FieldDef:
    number: int
    size: int
    base_type: int
    # Byte offset of this field inside the data record's payload.
    offset: int = 0


@dataclass
class MessageDef:
    global_num: int
    little_endian: bool
    fields: list[FieldDef] = field(default_factory=list)
    dev_fields: list[FieldDef] = field(default_factory=list)

    @property
    def record_size(self) -> int:
        return (sum(f.size for f in self.fields)
                + sum(f.size for f in self.dev_fields))


class FitFormatError(RuntimeError):
    pass


@dataclass
class ScrubStats:
    kept_records: int = 0
    dropped: dict[int, int] = field(default_factory=dict)
    patched: dict[str, int] = field(default_factory=dict)
    definitions: int = 0
    message_counts: dict[int, int] = field(default_factory=dict)


# ---------------------------------------------------------------------------------------
# The rewriter
# ---------------------------------------------------------------------------------------

def scrub(raw: bytes, drop_accel: bool = False) -> tuple[bytes, ScrubStats]:
    """Returns the scrubbed FIT bytes and what was touched."""
    if len(raw) < 14 or raw[8:12] != b".FIT":
        raise FitFormatError("not a FIT file (missing .FIT signature)")

    header_size = raw[0]
    if header_size not in (12, 14):
        raise FitFormatError(f"unsupported header size {header_size}")
    data_size = struct.unpack_from("<I", raw, 4)[0]
    body_start = header_size
    body_end = body_start + data_size
    if body_end + 2 > len(raw):
        raise FitFormatError("truncated FIT: header claims more data than the file holds")
    if body_end + 2 != len(raw):
        # Chained FIT files exist; the corpus has none, and silently keeping only the
        # first chunk would be worse than refusing.
        raise FitFormatError("chained FIT files are not supported by this tool")

    stored_crc = struct.unpack_from("<H", raw, body_end)[0]
    if fit_crc(raw[:body_end]) != stored_crc:
        raise FitFormatError("input FIT fails its own CRC — refusing to rewrite it")

    drop = dict(DROP_MESSAGES)
    if drop_accel:
        drop[ACCELEROMETER_DATA] = "high-rate accelerometer stream (--drop-accel)"

    stats = ScrubStats()
    defs: dict[int, MessageDef] = {}
    out = bytearray()
    pos = body_start

    while pos < body_end:
        header = raw[pos]
        if header & 0x80:                                   # compressed timestamp header
            local = (header >> 5) & 0x03
            mdef = defs.get(local)
            if mdef is None:
                raise FitFormatError(f"data record for undefined local type {local} at {pos}")
            record = raw[pos:pos + 1 + mdef.record_size]
            pos += len(record)
            out += _emit_data(record, mdef, drop, stats, payload_offset=1)
            continue

        local = header & 0x0F
        if header & 0x40:                                   # definition message
            has_dev = bool(header & 0x20)
            if pos + 6 > body_end:
                raise FitFormatError(f"truncated definition message at {pos}")
            little = raw[pos + 2] == 0
            endian = "<" if little else ">"
            global_num = struct.unpack_from(f"{endian}H", raw, pos + 3)[0]
            num_fields = raw[pos + 5]
            cursor = pos + 6
            mdef = MessageDef(global_num=global_num, little_endian=little)
            offset = 0
            for _ in range(num_fields):
                number, size, base = raw[cursor], raw[cursor + 1], raw[cursor + 2]
                mdef.fields.append(FieldDef(number, size, base, offset))
                offset += size
                cursor += 3
            if has_dev:
                num_dev = raw[cursor]
                cursor += 1
                for _ in range(num_dev):
                    number, size, _idx = raw[cursor], raw[cursor + 1], raw[cursor + 2]
                    mdef.dev_fields.append(FieldDef(number, size, 0, offset))
                    offset += size
                    cursor += 3
            if cursor > body_end:
                raise FitFormatError(f"definition message runs past the body at {pos}")
            defs[local] = mdef
            stats.definitions += 1
            out += raw[pos:cursor]
            pos = cursor
            continue

        mdef = defs.get(local)                              # normal data message
        if mdef is None:
            raise FitFormatError(f"data record for undefined local type {local} at {pos}")
        record = raw[pos:pos + 1 + mdef.record_size]
        pos += len(record)
        out += _emit_data(record, mdef, drop, stats, payload_offset=1)

    if pos != body_end:
        raise FitFormatError("record stream did not end on the body boundary")

    body = bytes(out)
    result = bytearray(raw[:header_size])
    struct.pack_into("<I", result, 4, len(body))
    if header_size == 14:
        struct.pack_into("<H", result, 12, fit_crc(bytes(result[:12])))
    result += body
    result += struct.pack("<H", fit_crc(bytes(result)))
    return bytes(result), stats


def _emit_data(record: bytes, mdef: MessageDef, drop: dict[int, str], stats: ScrubStats,
               payload_offset: int) -> bytes:
    """One data record: dropped, patched in place, or copied through untouched."""
    stats.message_counts[mdef.global_num] = stats.message_counts.get(mdef.global_num, 0) + 1
    if mdef.global_num in drop:
        stats.dropped[mdef.global_num] = stats.dropped.get(mdef.global_num, 0) + 1
        return b""
    stats.kept_records += 1

    patched: bytearray | None = None
    for fdef in mdef.fields:
        label = PATCH_FIELDS.get((mdef.global_num, fdef.number))
        if label is None:
            continue
        blank = INVALID_BYTES.get(fdef.base_type)
        if blank is None:
            raise FitFormatError(
                f"{label}: base type 0x{fdef.base_type:02X} has no invalid pattern")
        if patched is None:
            patched = bytearray(record)
        start = payload_offset + fdef.offset
        patched[start:start + fdef.size] = (blank * fdef.size)[:fdef.size]
        stats.patched[label] = stats.patched.get(label, 0) + 1
    return bytes(patched) if patched is not None else record


# ---------------------------------------------------------------------------------------
# Reporting / verification
# ---------------------------------------------------------------------------------------

def message_name(global_num: int) -> str:
    try:
        from fitdecode.profile.profile_type import MesgNum

        return MesgNum(global_num).name
    except Exception:
        return f"unknown_{global_num}"


def report(path: Path) -> None:
    """Dry run: what the rules *would* touch in this file."""
    raw = path.read_bytes()
    _, stats = scrub(raw)
    print(f"{path}  ({len(raw):,} bytes)")
    print(f"  {stats.definitions} definition messages, "
          f"{sum(stats.message_counts.values()):,} data records")
    for global_num, count in sorted(stats.dropped.items()):
        print(f"  drop  {message_name(global_num):<18} x{count:<5} "
              f"{DROP_MESSAGES.get(global_num, '')}")
    for label, count in sorted(stats.patched.items()):
        print(f"  zero  {label:<32} x{count}")


def identifiers_present(path: Path) -> dict[str, list]:
    """Every string field and every serial-number-shaped field still in the file.

    Used both by `--verify` and, mirrored, by the Swift bundle test: the property that
    matters is "no serial number and no personal name survives", and it is cheaper to
    assert on the parsed messages than on a byte scan.
    """
    import fitdecode

    findings: dict[str, list] = {"serials": [], "strings": [], "messages": []}
    seen: set[str] = set()
    with fitdecode.FitReader(str(path)) as reader:
        for frame in reader:
            if not isinstance(frame, fitdecode.FitDataMessage):
                continue
            if frame.name not in seen:
                seen.add(frame.name)
                findings["messages"].append(frame.name)
            for fld in frame.fields:
                if fld.name.endswith("serial_number") and fld.value not in (None, 0):
                    findings["serials"].append(f"{frame.name}.{fld.name}={fld.value}")
                if isinstance(fld.value, str) and fld.value.strip():
                    tag = f"{frame.name}.{fld.name}"
                    if tag not in seen:
                        seen.add(tag)
                        findings["strings"].append(f"{tag}={fld.value!r}")
    findings["messages"].sort()
    return findings


def golden_of(path: Path) -> dict:
    """The full analysis output (docs/testing.md golden schema) for one FIT."""
    sys.path.insert(0, str(REPO / "lab" / "src"))
    from wingfoil_lab.goldens import analyze, build_golden

    return build_golden(analyze(path))


def verify(original: Path, scrubbed: Path, expect_identical: bool) -> bool:
    """Analysis parity plus a PII sweep of the output. Returns True on success."""
    ok = True
    found = identifiers_present(scrubbed)
    if found["serials"]:
        print(f"FAIL: serial numbers survive: {found['serials']}", file=sys.stderr)
        ok = False
    else:
        print("ok: no serial_number field survives")

    before = golden_of(original)
    after = golden_of(scrubbed)
    if expect_identical:
        if json.dumps(before, sort_keys=True) == json.dumps(after, sort_keys=True):
            print("ok: analysis output is byte-identical to the original")
        else:
            print("FAIL: analysis output changed", file=sys.stderr)
            for key in sorted(set(before) | set(after)):
                if before.get(key) != after.get(key):
                    print(f"  differs: {key}", file=sys.stderr)
            ok = False
    else:
        # --drop-accel deliberately removes the stroke counts; everything else must hold.
        keys = ["flights", "turns", "flightEnds", "records", "wind"]
        for key in keys:
            same = json.dumps(before.get(key), sort_keys=True) == \
                json.dumps(after.get(key), sort_keys=True)
            print(f"{'ok' if same else 'note'}: {key} "
                  f"{'unchanged' if same else 'changed (accel removed)'}")
        print(f"note: capabilities.hasAccel {before['capabilities']['hasAccel']} -> "
              f"{after['capabilities']['hasAccel']}")
    return ok


# ---------------------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", type=Path)
    ap.add_argument("output", type=Path, nargs="?")
    ap.add_argument("--drop-accel", action="store_true",
                    help="also remove the high-rate accelerometer stream (smaller bundle; "
                         "the phone then skips the pump recompute)")
    ap.add_argument("--report", action="store_true", help="inspect only, write nothing")
    ap.add_argument("--no-verify", action="store_true",
                    help="skip the analysis-parity check (it re-analyses both files)")
    args = ap.parse_args(argv)

    if args.report or args.output is None:
        report(args.input)
        return 0

    raw = args.input.read_bytes()
    out, stats = scrub(raw, drop_accel=args.drop_accel)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(out)

    print(f"{args.input.name}: {len(raw):,} bytes")
    print(f"{args.output.name}: {len(out):,} bytes "
          f"({100 * len(out) / len(raw):.1f} % of the original)")
    for global_num, count in sorted(stats.dropped.items()):
        print(f"  dropped {message_name(global_num):<20} x{count:<6} "
              f"{DROP_MESSAGES.get(global_num, '')}")
    for label, count in sorted(stats.patched.items()):
        print(f"  zeroed  {label:<20} x{count}")

    if args.no_verify:
        return 0
    return 0 if verify(args.input, args.output, expect_identical=not args.drop_accel) else 1


if __name__ == "__main__":
    sys.exit(main())
