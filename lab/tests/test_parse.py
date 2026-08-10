"""Parse smoke tests.

test_synthetic_roundtrip needs no fixtures (encodes a tiny FIT with fit_tool, parses it back).
test_real_fixtures runs over whatever is in fixtures/sessions/ and skips when empty.
"""

from pathlib import Path

import pytest

from wingfoil_lab.parse import parse_fit, summarize

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
