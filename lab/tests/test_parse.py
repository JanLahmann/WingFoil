"""Parse smoke tests.

test_synthetic_roundtrip needs no fixtures (encodes a tiny FIT with fit_tool, parses it back).
test_real_fixtures runs over whatever is in fixtures/sessions/ and skips when empty.
The schema v1/v2 tests drive `_unpack_session_v2` on synthetic session dicts — the unpacking
is pure dict work, and encoding FITs to exercise it would only test fitdecode.
"""

import datetime as dt
from pathlib import Path

import pandas as pd
import pytest

from wingfoil_lab.parse import (UTC_OFFSET_SOURCES, SourceCapabilities, _unpack_session_v2,
                                activity_utc_offset_s, coarse_utc_offset_s, parse_fit,
                                resolve_utc_offset, summarize)

FIXTURES = Path(__file__).resolve().parents[2] / "fixtures" / "sessions"


def _build_synthetic_fit(path: Path, seconds: int = 60) -> None:
    from fit_tool.fit_file_builder import FitFileBuilder
    from fit_tool.profile.messages.file_id_message import FileIdMessage
    from fit_tool.profile.messages.record_message import RecordMessage
    from fit_tool.profile.messages.session_message import SessionMessage
    from fit_tool.profile.profile_type import FileType, Sport

    builder = FitFileBuilder(auto_define=True)
    fid = FileIdMessage()
    fid.type = FileType.ACTIVITY
    fid.time_created = 1_722_945_600_000  # ms
    builder.add(fid)

    t0 = 1_722_945_600_000
    lat0, lon0 = 45.87, 10.87  # Torbole-ish
    for i in range(seconds):
        r = RecordMessage()
        r.timestamp = t0 + i * 1000
        r.position_lat = lat0 + i * 1e-5
        r.position_long = lon0
        # taxi 5 km/h for 20 s, foil 22 km/h for 30 s, sink back for 10 s
        r.speed = 5 / 3.6 if i < 20 else (22 / 3.6 if i < 50 else 6 / 3.6)
        r.distance = float(i * 4)
        r.heart_rate = 120 + (i % 10)
        builder.add(r)

    s = SessionMessage()
    s.sport = Sport.WINDSURFING
    builder.add(s)
    builder.build().to_file(str(path))


def test_synthetic_roundtrip(tmp_path):
    fit = tmp_path / "synthetic.fit"
    _build_synthetic_fit(fit)
    track = parse_fit(fit)
    caps = track.capabilities
    assert len(track.records) == 60
    assert caps.has_speed and caps.has_position and caps.has_hr
    assert caps.sample_rate_hz == pytest.approx(1.0, abs=0.01)
    assert caps.source_class == "b"  # no dev fields
    assert "windsurfing" in (caps.sport or "").lower()
    top_kn = track.records["speed_mps"].max() * 1.9438445
    assert top_kn == pytest.approx(22 / 3.6 * 1.9438445, abs=0.05)


V1_SESSION = {
    "discipline": "wingfoil",
    "longest_flight_s": 214, "longest_flight_m": 1780,
    "takeoff_attempts": 31, "takeoff_successes": 24, "avg_pumps_to_takeoff": 87,
    "cfg_entry_speed": 1200, "cfg_exit_speed": 900, "cfg_min_flight": 3,
    "app_version": 0x0101,
}


def test_v2_unpacks_all_three_packs():
    s = {
        "cfg_pack": (1200 << 16) | (3 << 11) | 900,
        "takeoff_pack": (87 << 16) | (31 << 8) | 24,
        "longest_pack": (214 << 16) | 1780,
    }
    _unpack_session_v2(s)
    assert (s["cfg_entry_speed"], s["cfg_exit_speed"], s["cfg_min_flight"]) == (1200, 900, 3)
    assert (s["takeoff_attempts"], s["takeoff_successes"]) == (31, 24)
    assert s["avg_pumps_to_takeoff"] == 87              # strokes x0.1, as on the v1 wire
    assert (s["longest_flight_s"], s["longest_flight_m"]) == (214, 1780)


def test_v2_boundary_values():
    """Every field at the top of its bit range, and the all-zero session."""
    s = {
        "cfg_pack": (65535 << 16) | (31 << 11) | 2047,
        "takeoff_pack": (255 << 16) | (255 << 8) | 255,
        "longest_pack": (65535 << 16) | 65535,
    }
    _unpack_session_v2(s)
    assert (s["cfg_entry_speed"], s["cfg_exit_speed"], s["cfg_min_flight"]) == (65535, 2047, 31)
    assert (s["avg_pumps_to_takeoff"], s["takeoff_attempts"], s["takeoff_successes"]) == \
        (255, 255, 255)
    assert (s["longest_flight_s"], s["longest_flight_m"]) == (65535, 65535)

    zero = {"cfg_pack": 0, "takeoff_pack": 0, "longest_pack": 0}
    _unpack_session_v2(zero)
    assert all(v == 0 for v in zero.values())
    assert zero["cfg_min_flight"] == 0 and zero["longest_flight_m"] == 0


def test_v1_session_is_untouched():
    s = dict(V1_SESSION)
    _unpack_session_v2(s)
    assert s == V1_SESSION


def test_packed_wins_over_v1_direct():
    """If both encodings appear, v2 is the newer and authoritative one."""
    s = dict(V1_SESSION, cfg_pack=(1400 << 16) | (5 << 11) | 1000,
             longest_pack=(300 << 16) | 2500)
    _unpack_session_v2(s)
    assert (s["cfg_entry_speed"], s["cfg_exit_speed"], s["cfg_min_flight"]) == (1400, 1000, 5)
    assert (s["longest_flight_s"], s["longest_flight_m"]) == (300, 2500)
    assert s["takeoff_attempts"] == 31          # no takeoff_pack -> v1 value stands


@pytest.mark.parametrize("s", [
    {},
    {"cfg_pack": None, "takeoff_pack": None, "longest_pack": None},
    {"cfg_pack": "1234", "takeoff_pack": 1.5, "longest_pack": [1, 2]},
])
def test_fail_soft_on_missing_or_bad_packs(s):
    before = dict(s)
    _unpack_session_v2(s)                       # never raises
    assert s == before                          # and derives nothing it cannot trust


def test_real_fixtures():
    fits = sorted(FIXTURES.rglob("*.fit"))
    if not fits:
        pytest.skip("no session fixtures downloaded yet (see lab/tools/download_icu.py)")
    for f in fits:
        track = parse_fit(f)
        info = summarize(track)
        assert info["samples"] > 0, f"{f.name}: no records"
        assert track.capabilities.has_position, f"{f.name}: no GPS"
        print(info)


# --------------------------------------------------------------- the session's own clock


def test_activity_offset_is_the_watchs_own_answer():
    """`activity.local_timestamp - activity.timestamp`, in whole seconds."""
    base = dt.datetime(2026, 8, 30, 12, 7, 30, tzinfo=dt.timezone.utc)
    assert activity_utc_offset_s(
        {"timestamp": base, "local_timestamp": base + dt.timedelta(hours=2)}) == 7200
    assert activity_utc_offset_s(
        {"timestamp": base, "local_timestamp": base - dt.timedelta(hours=8)}) == -28800
    # A session really recorded at UTC says 0 — which is a fact, not an absence.
    assert activity_utc_offset_s({"timestamp": base, "local_timestamp": base}) == 0


@pytest.mark.parametrize("activity", [
    {},
    {"timestamp": dt.datetime(2026, 8, 30, tzinfo=dt.timezone.utc)},
    {"local_timestamp": dt.datetime(2026, 8, 30, tzinfo=dt.timezone.utc)},
    {"timestamp": "2026-08-30", "local_timestamp": "2026-08-30"},
])
def test_missing_activity_fields_are_none_and_never_zero(activity):
    """"This file does not say" and "this was UTC" are different facts.

    Only one of them licenses a fallback, so the parser must never turn the first into the
    second — a 0 here would be a claim about the session that nothing measured.
    """
    assert activity_utc_offset_s(activity) is None


def test_coarse_offset_from_longitude_is_solar_and_says_so():
    """The fallback rung: `round(lon / 15)` hours. Documented as approximate for a reason."""
    assert coarse_utc_offset_s(10.87) == 3600        # Torbole — an hour out under CEST
    assert coarse_utc_offset_s(0.0) == 0
    assert coarse_utc_offset_s(-118.24) == -8 * 3600  # Los Angeles, and right this time
    assert coarse_utc_offset_s(float("nan")) is None


def _ladder(declared, lons):
    """`resolve_utc_offset` with the smallest inputs that exercise a rung."""
    df = pd.DataFrame({"lon": lons}) if lons is not None else pd.DataFrame()
    caps = SourceCapabilities(has_position=lons is not None)
    return resolve_utc_offset(declared, df, caps)


def test_the_ladder_records_which_rung_answered():
    """Engine 0.9.1: the offset and its provenance, together, always.

    The offset alone cannot be read honestly. +7200 from an `activity` message and +7200
    from a longitude at 30°E are the same number and different facts, and only the first
    licenses a surface to print "times as recorded on the water" — the second is the
    *solar* offset and is an hour out under DST. Every rung is pinned here because the bug
    this fixes was not a wrong number, it was a missing qualification.
    """
    # 1. the recording said so itself, and it wins even where the guess disagrees
    assert _ladder(7200, [10.87]) == (7200, "activity")
    # A real 0 is an answer, not an absence: it must not fall through to the guess.
    assert _ladder(0, [10.87]) == (0, "activity")
    # 2. nothing declared, but there are fixes -> the solar guess, labelled as one
    assert _ladder(None, [10.87]) == (3600, "longitude")
    assert _ladder(None, [-118.24]) == (-8 * 3600, "longitude")
    # 3. no fixes at all -> nobody could say, and that is itself the answer
    assert _ladder(None, None) == (None, "device")
    # A position column with nothing in it is the same "could not say".
    assert _ladder(None, [float("nan")]) == (None, "device")


def test_every_source_name_is_one_the_contract_knows():
    """The vocabulary is closed, and shared with the Swift and JS mirrors."""
    assert UTC_OFFSET_SOURCES == ("activity", "icu", "longitude", "device")
    for declared, lons in [(7200, [10.87]), (None, [10.87]), (None, None)]:
        assert _ladder(declared, lons)[1] in UTC_OFFSET_SOURCES


def test_every_fixture_carries_its_recorded_offset():
    """The corpus was ridden in CEST, and every file in it says so — CIQ and native alike.

    This is the fact the whole per-session-timezone change rests on: the offset is not
    something we infer, it is something the watch wrote down.
    """
    fits = sorted(FIXTURES.rglob("*.fit"))
    if not fits:
        pytest.skip("no session fixtures downloaded yet (see lab/tools/download_icu.py)")
    for f in fits:
        track = parse_fit(f)
        assert track.start_utc_offset_s == 7200, f"{f.name}: lost its recorded offset"
        # …and says so: every FIT in the corpus answers on the top rung, so nothing in the
        # corpus is entitled to the softened wording (engine 0.9.1).
        assert track.start_utc_offset_source == "activity", f"{f.name}: wrong rung"
