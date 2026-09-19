#!/usr/bin/env python3
"""Reference encoder and decoder for the direct-transfer stream (`docs/transfer-format.md`).

The watch encodes in Monkey C and the phone decodes in Swift; this file is the third,
plain-Python statement of the same bytes, the one the two ends are tested against. It has
no dependency beyond the stdlib on purpose, so `python3 lab/tools/cjr_ref.py` prints the
worked example the format document quotes, and `--check` re-derives it.

Only stream 0 (`rec.v1`, one record per GPS fix) is defined here. Stream 1, the wrist
magnitudes, is dev3's and gets its own encoding name when it exists.
"""
from __future__ import annotations

import struct
import sys
from dataclasses import dataclass

MAGIC = b"CJR1"
SCHEMA = 2                # 2: the 20-byte header carries the watch's clock offset
STREAM_RECORD = 0
HEADER_BYTES = 20
HEADER_BYTES_V1 = 16      # schema 1 streams, read but no longer written
UTC_OFFSET_NONE = 0x7FFF
KEYFRAME_TAG = 0xFF
KEYFRAME_BYTES = 22
DELTA_BYTES = 13
DT_MAX = 254            # a gap longer than this forces a keyframe
KEYFRAME_EVERY = 60     # samples; a page also always opens with one
PAGE_BYTES = 8000       # payload per Communications.transmit; the ceiling measured is 8 KB
LAT_LON_KEY_UNIT = 1e-7  # keyframe: int32 in 1e-7 deg
LAT_LON_DELTA_UNIT = 1e-6  # delta: int16 in 1e-6 deg, so ±0.032 deg ≈ ±3.6 km per step
KEY_SCALE = 10_000_000     # degrees × this, rounded half away from zero, is the keyframe unit
DELTA_SCALE = 1_000_000
ALT_NONE = 0x7FFF


@dataclass
class Header:
    stream: int
    app_version: int       # minor << 8 | fit schema, as SES_APP_VERSION
    start_epoch_s: int
    wind_dir: int          # 0..359, or -1 when unset
    discipline: int        # 0 wingfoil (the only value 0.9.x writes)
    flags: int = 0
    utc_offset_min: int | None = None   # the watch's clock offset at start, minutes east of UTC

    def pack(self) -> bytes:
        off = UTC_OFFSET_NONE if self.utc_offset_min is None else self.utc_offset_min
        return MAGIC + struct.pack("<BBHIhBBhH", SCHEMA, self.stream, self.app_version,
                                   self.start_epoch_s, self.wind_dir, self.discipline,
                                   self.flags, off, 0)

    @classmethod
    def unpack(cls, b: bytes) -> "Header":
        if b[:4] != MAGIC:
            raise ValueError("not a CJR1 stream")
        schema, stream, app, start, wind, disc, flags = struct.unpack("<BBHIhBB", b[4:16])
        if schema == 1:
            return cls(stream, app, start, wind, disc, flags, None)
        if schema != SCHEMA:
            raise ValueError(f"schema {schema}")
        off, _reserved = struct.unpack("<hH", b[16:20])
        return cls(stream, app, start, wind, disc, flags, None if off == UTC_OFFSET_NONE else off)

    @property
    def size(self) -> int:
        return HEADER_BYTES


def header_size(b: bytes) -> int:
    """16 for a schema-1 stream, 20 from schema 2."""
    return HEADER_BYTES_V1 if b[4] == 1 else HEADER_BYTES


@dataclass
class Sample:
    t: int                 # epoch seconds
    lat: float             # degrees
    lon: float
    speed_cms: int         # Doppler, cm/s
    alt_m: int | None
    hr: int                # 0 = none
    foil: int              # REC_FOIL_STATE
    cadence: int           # REC_PUMP_CADENCE
    marker: int            # REC_TURN_MARKER
    tick: int              # REC_TICK, mod 256


def _q(deg: float, unit: float) -> int:
    """Degrees to integer units, rounded half away from zero — the arithmetic a 32-bit
    watch does with `(deg * scale ± 0.5).toNumber()`, spelled the same way here so the two
    ends agree on every last digit."""
    scale = KEY_SCALE if unit == LAT_LON_KEY_UNIT else DELTA_SCALE
    x = deg * scale
    return int(x + 0.5) if x >= 0 else int(x - 0.5)


def _base6(q7: int) -> int:
    """The tracked 1e-7 position as a 1e-6 base for a delta: half away from zero, with the
    truncating integer division C and Monkey C share."""
    n = q7 + 5 if q7 >= 0 else q7 - 5
    return -((-n) // 10) if n < 0 else n // 10


class Encoder:
    """Feeds samples in, yields closed pages. `close()` yields the last one."""

    def __init__(self, header: Header):
        self._pages: list[bytes] = []
        self._buf = bytearray(header.pack())
        self._since_key = KEYFRAME_EVERY  # the first sample keys
        self._state: Sample | None = None
        self._qlat = 0
        self._qlon = 0

    def _keyframe(self, s: Sample) -> bytes:
        alt = ALT_NONE if s.alt_m is None else s.alt_m
        self._qlat = _q(s.lat, LAT_LON_KEY_UNIT)
        self._qlon = _q(s.lon, LAT_LON_KEY_UNIT)
        return struct.pack("<BIiiHhBBBBB", KEYFRAME_TAG, s.t, self._qlat, self._qlon,
                           s.speed_cms, alt, s.hr, s.foil, s.cadence, s.marker, s.tick)

    def _delta(self, s: Sample) -> bytes | None:
        p = self._state
        assert p is not None
        dt = s.t - p.t
        if dt < 1 or dt > DT_MAX:
            return None
        dlat = _q(s.lat, LAT_LON_DELTA_UNIT) - _base6(self._qlat)
        dlon = _q(s.lon, LAT_LON_DELTA_UNIT) - _base6(self._qlon)
        if not (-32768 <= dlat <= 32767 and -32768 <= dlon <= 32767):
            return None
        if s.alt_m is None or p.alt_m is None:
            dalt = 0 if (s.alt_m is None and p.alt_m is None) else None
        else:
            dalt = s.alt_m - p.alt_m
        if dalt is None or not (-128 <= dalt <= 127):
            return None
        self._qlat += dlat * 10
        self._qlon += dlon * 10
        return struct.pack("<BhhHbBBBBB", dt, dlat, dlon, s.speed_cms, dalt, s.hr,
                           s.foil, s.cadence, s.marker, s.tick)

    def push(self, s: Sample) -> None:
        rec = None
        if self._state is not None and self._since_key < KEYFRAME_EVERY:
            rec = self._delta(s)
        if rec is None:
            rec = self._keyframe(s)
            self._since_key = 0
        if len(self._buf) + len(rec) > PAGE_BYTES:
            self._pages.append(bytes(self._buf))
            self._buf = bytearray()
            if rec[0] != KEYFRAME_TAG:
                rec = self._keyframe(s)
            self._since_key = 0
        self._buf += rec
        self._since_key += 1
        self._state = s

    def close(self) -> list[bytes]:
        if self._buf:
            self._pages.append(bytes(self._buf))
            self._buf = bytearray()
        return self._pages


def decode(data: bytes) -> tuple[Header, list[Sample]]:
    """Decodes the concatenation of a stream's pages, in order."""
    header = Header.unpack(data[:HEADER_BYTES])
    i = header_size(data)
    out: list[Sample] = []
    qlat = qlon = 0
    prev: Sample | None = None
    while i < len(data):
        if data[i] == KEYFRAME_TAG:
            (_, t, qlat, qlon, spd, alt, hr, foil, cad, mark, tick) = struct.unpack(
                "<BIiiHhBBBBB", data[i:i + KEYFRAME_BYTES])
            i += KEYFRAME_BYTES
            s = Sample(t, qlat * LAT_LON_KEY_UNIT, qlon * LAT_LON_KEY_UNIT, spd,
                       None if alt == ALT_NONE else alt, hr, foil, cad, mark, tick)
        else:
            if prev is None:
                raise ValueError("delta before any keyframe")
            (dt, dlat, dlon, spd, dalt, hr, foil, cad, mark, tick) = struct.unpack(
                "<BhhHbBBBBB", data[i:i + DELTA_BYTES])
            i += DELTA_BYTES
            qlat += dlat * 10
            qlon += dlon * 10
            alt = None if prev.alt_m is None else prev.alt_m + dalt
            s = Sample(prev.t + dt, qlat * LAT_LON_KEY_UNIT, qlon * LAT_LON_KEY_UNIT, spd,
                       alt, hr, foil, cad, mark, tick)
        out.append(s)
        prev = s
    return header, out


# ------------------------------------------------------------------ the worked example
EXAMPLE_HEADER = Header(stream=STREAM_RECORD, app_version=9 * 256 + 2,
                        start_epoch_s=1756556820, wind_dir=200, discipline=0,
                        utc_offset_min=120)
EXAMPLE_SAMPLES = [
    Sample(1756556820, 45.8710000, 10.8630000, 0, 66, 98, 0, 0, 0, 0),
    Sample(1756556821, 45.8710050, 10.8630120, 310, 66, 101, 1, 0, 0, 1),
    Sample(1756556822, 45.8710110, 10.8630250, 640, 65, 104, 2, 12, 3, 2),
]
EXAMPLE_HEX = (
    "434a5231" "02" "00" "0209" "14eeb268" "c800" "00" "00" "7800" "0000"         # header
    "ff" "14eeb268" "f05b571b" "f08f7906" "0000" "4200" "62" "00" "00" "00" "00"  # keyframe
    "01" "0500" "0c00" "3601" "00" "65" "01" "00" "00" "01"                        # delta
    "01" "0600" "0d00" "8002" "ff" "68" "02" "0c" "03" "02"                        # delta
)


def example_bytes() -> bytes:
    enc = Encoder(EXAMPLE_HEADER)
    for s in EXAMPLE_SAMPLES:
        enc.push(s)
    pages = enc.close()
    assert len(pages) == 1
    return pages[0]


def main(argv: list[str]) -> int:
    b = example_bytes()
    if "--check" in argv:
        ok = b.hex() == EXAMPLE_HEX
        h, back = decode(b)
        ok = ok and h == EXAMPLE_HEADER and len(back) == 3
        ok = ok and all(abs(a.lat - e.lat) < 6e-7 and abs(a.lon - e.lon) < 6e-7
                        and a.t == e.t and a.speed_cms == e.speed_cms and a.alt_m == e.alt_m
                        and a.hr == e.hr and a.tick == e.tick
                        for a, e in zip(back, EXAMPLE_SAMPLES))
        print("cjr reference: PASS" if ok else "cjr reference: FAIL")
        return 0 if ok else 1
    print(b.hex())
    print(len(b), "bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
