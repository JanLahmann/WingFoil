"""`lab/tools/cjr_ref.py` is the third statement of the direct transfer's bytes
(docs/transfer-format.md). The watch encodes them in Monkey C and the phone decodes them in
Swift; nothing keeps three implementations in step by being read, so the worked examples are
pinned here as well as by `--check`, by the kit's `DirectStreamTests` and by the watch's
`WingfoilTests`.

The reference is stdlib-only and lives under `tools/`, not in the package, so it is imported
by path rather than by name.
"""
from __future__ import annotations

import importlib.util
import random
import sys
from pathlib import Path

import pytest

_REF = Path(__file__).resolve().parents[1] / "tools" / "cjr_ref.py"
_spec = importlib.util.spec_from_file_location("cjr_ref", _REF)
assert _spec is not None and _spec.loader is not None
cjr = importlib.util.module_from_spec(_spec)
# Registered before it runs: `@dataclass` resolves `int | None` against the module's own
# namespace, and a module that is not in `sys.modules` has none to resolve against.
sys.modules["cjr_ref"] = cjr
_spec.loader.exec_module(cjr)


def test_the_reference_checks_itself():
    assert cjr._check()


# ------------------------------------------------------------------ stream 0, `rec.v1`

def test_worked_example_is_the_documented_hex():
    assert cjr.example_bytes().hex() == cjr.EXAMPLE_HEX


def test_round_trip_holds_every_field_and_a_micro_degree():
    header = cjr.Header(stream=0, app_version=9 * 256 + 2, start_epoch_s=1_756_556_820,
                        wind_dir=200, discipline=0, utc_offset_min=120)
    rng = random.Random(27)
    samples = []
    lat, lon = 45.871, 10.863
    for i in range(2000):
        lat += rng.uniform(-2e-5, 2e-5)
        lon += rng.uniform(-2e-5, 2e-5)
        samples.append(cjr.Sample(
            t=1_756_556_820 + i + (400 if i >= 900 else 0),   # a pause the dt cannot say
            lat=lat, lon=lon,
            speed_cms=rng.randrange(0, 1400),
            alt_m=None if 1200 <= i < 1300 else 60 + (i % 7),  # altitude disappears and returns
            hr=rng.randrange(90, 180), foil=i % 3, cadence=i % 60,
            marker=i % 4, tick=i % 256))
    enc = cjr.Encoder(header)
    for s in samples:
        enc.push(s)
    pages = enc.close()
    assert len(pages) > 1
    assert all(len(p) <= cjr.PAGE_BYTES for p in pages)
    # Every page after the first opens with a keyframe; page 0 opens with the header.
    assert pages[0][:4] == cjr.MAGIC
    assert all(p[0] == cjr.KEYFRAME_TAG for p in pages[1:])

    back_header, back = cjr.decode(b"".join(pages))
    assert back_header == header
    assert len(back) == len(samples)
    for a, e in zip(back, samples):
        assert a.t == e.t
        assert a.speed_cms == e.speed_cms
        assert a.alt_m == e.alt_m
        assert a.hr == e.hr
        assert (a.foil, a.cadence, a.marker, a.tick) == (e.foil, e.cadence, e.marker, e.tick)
        assert abs(a.lat - e.lat) < 1.1e-6
        assert abs(a.lon - e.lon) < 1.1e-6


# ------------------------------------------------------------------ stream 1, `wrist.v1`

def test_wrist_worked_example_is_the_documented_hex():
    assert cjr.wrist_example_bytes().hex() == cjr.WRIST_EXAMPLE_HEX


def test_wrist_page_zero_is_the_header_alone():
    enc = cjr.WristEncoder(cjr.WRIST_EXAMPLE_HEADER)
    enc.push(cjr.WRIST_EXAMPLE_WINDOW)
    pages = enc.close()
    assert len(pages[0]) == cjr.HEADER_BYTES
    assert pages[0][:4] == cjr.MAGIC
    assert pages[0][5] == cjr.STREAM_WRIST


def test_every_wrist_page_opens_with_a_window_and_decodes_on_its_own():
    header = cjr.Header(stream=cjr.STREAM_WRIST, app_version=9 * 256 + 2,
                        start_epoch_s=1_756_556_820, wind_dir=200, discipline=0,
                        utc_offset_min=120)
    rng = random.Random(31)
    enc = cjr.WristEncoder(header)
    windows = []
    t = 1_756_556_820_000
    for _ in range(200):
        mag = 100
        mags = []
        for _ in range(cjr.WINDOW_MAX_SAMPLES):
            mag = max(0, mag + rng.randrange(-40, 41))
            mags.append(mag)
        w = cjr.Window(t0_ms=t, mags=mags)
        windows.append(w)
        enc.push(w)
        t += 30_000
    pages = enc.close()
    assert len(pages) > 2
    assert all(len(p) <= cjr.PAGE_BYTES for p in pages)
    assert all(p[0] == cjr.WINDOW_TAG for p in pages[1:])
    back_header, back = cjr.decode_wrist(b"".join(pages))
    assert back_header.stream == cjr.STREAM_WRIST
    assert back == windows


def test_a_step_the_delta_cannot_say_escapes():
    w = cjr.Window(t0_ms=1_000_000, mags=[100, 100 + cjr.DELTA_MAX, 0, 65535])
    body = cjr.encode_window(w)
    # first escape, one delta of +127, then two escapes
    assert len(body) == cjr.WINDOW_HEADER_BYTES + 3 + 1 + 3 + 3
    _, back = cjr.decode_wrist(cjr.WRIST_EXAMPLE_HEADER.pack() + body)
    assert back == [w]


def test_a_torn_wrist_window_is_refused_rather_than_guessed():
    whole = cjr.wrist_example_bytes()
    for cut in range(cjr.HEADER_BYTES + 1, len(whole)):
        with pytest.raises(ValueError):
            cjr.decode_wrist(whole[:cut])


def test_windows_carry_the_twenty_five_hertz_grid():
    assert cjr.WRIST_HZ * cjr.WRIST_STEP_MS == 1000


# --------------------------------------------------- the fenix 5 Plus packed page

@pytest.mark.parametrize("n", [0, 1, 2, 3, 4, 5, 7, 8, 4001, 8000])
def test_packed_words_round_trip_at_every_remainder(n: int):
    rng = random.Random(n)
    payload = bytes(rng.randrange(256) for _ in range(n))
    words = cjr.pack_words(payload)
    assert len(words) == (n + 3) // 4
    assert all(-(2 ** 31) <= w < 2 ** 31 for w in words)   # a Monkey C Number is signed
    assert cjr.unpack_words(words, n) == payload


def test_a_packed_page_that_lies_about_its_length_is_refused():
    words = cjr.pack_words(b"\x01\x02\x03\x04\x05")
    assert len(words) == 2
    for claimed in (-1, 4, 9):
        with pytest.raises(ValueError):
            cjr.unpack_words(words, claimed)
    for claimed in (5, 6, 7, 8):
        assert len(cjr.unpack_words(words, claimed)) == claimed


def test_the_high_bit_survives_the_word():
    payload = bytes([0x00, 0x00, 0x00, 0x80])
    assert cjr.pack_words(payload) == [-(2 ** 31)]
    assert cjr.unpack_words([-(2 ** 31)], 4) == payload
