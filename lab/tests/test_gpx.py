"""GPX parsing (engine 0.9.0): the class-(c) door.

Two things are being pinned down here. First that a GPX becomes the *same* `RawTrack` a
FIT becomes — same columns, same units, same clock — so nothing downstream has to know
which door a track came in by. Second, and more important, that everything a GPX cannot
say stays unsaid: no Doppler claim, no accelerometer, no developer fields. A parser that
quietly filled those in would be the one bug this whole source class exists to prevent.
"""

from pathlib import Path

import numpy as np
import pytest

from wingfoil_lab.filters import clean
from wingfoil_lab.gpx import is_gpx, parse_gpx, parse_gpx_bytes
from wingfoil_lab.parse import parse_track

FIXTURES = Path(__file__).resolve().parents[2] / "fixtures"
GPX = FIXTURES / "sessions" / "gpx" / "2026-08-30-1407_nago-torbole.gpx"
CIQ = (FIXTURES / "sessions" / "ciq"
       / "2026-08-30-1407_nago-torbole-windsurfen_ciq.fit")

HEAD = ('<?xml version="1.0" encoding="UTF-8"?>\n'
        '<gpx version="1.1" creator="test" '
        'xmlns="http://www.topografix.com/GPX/1/1" '
        'xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">')


def _doc(body: str) -> bytes:
    return f"{HEAD}{body}</gpx>".encode()


def _pt(lat: float, lon: float, time: str | None = "2026-08-30T12:00:00Z",
        ele: float | None = None, hr: int | None = None) -> str:
    inner = ""
    if ele is not None:
        inner += f"<ele>{ele}</ele>"
    if time is not None:
        inner += f"<time>{time}</time>"
    if hr is not None:
        inner += ("<extensions><gpxtpx:TrackPointExtension>"
                  f"<gpxtpx:hr>{hr}</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions>")
    return f'<trkpt lat="{lat}" lon="{lon}">{inner}</trkpt>'


def _line(n: int, *, start: str = "2026-08-30T12:00:00Z", step_deg: float = 0.0001,
          hr: int | None = None) -> str:
    """`n` points a second apart, walking north — a track with a speed to derive."""
    import datetime as dt
    t0 = dt.datetime.fromisoformat(start.replace("Z", "+00:00"))
    return "".join(
        _pt(45.86 + i * step_deg, 10.87,
            time=(t0 + dt.timedelta(seconds=i)).strftime("%Y-%m-%dT%H:%M:%SZ"), hr=hr)
        for i in range(n))


# ------------------------------------------------------------------ minimal documents


def test_a_minimal_gpx_becomes_a_track():
    """Three points, three columns, and a speed the file never carried."""
    track = parse_gpx_bytes(_doc(f"<trk><trkseg>{_line(3)}</trkseg></trk>"))
    df = track.records
    assert len(df) == 3
    assert list(df.columns) == ["timestamp", "lat", "lon", "altitude", "heart_rate",
                                "t", "speed_mps", "gap_before"]
    assert df["t"].tolist() == [0.0, 1.0, 2.0]
    # ~0.0001° of latitude is ~11 m, walked in a second.
    assert df["speed_mps"].between(10.0, 12.0).all()
    assert track.session["gpxTracks"] == 1 and track.session["gpxSegments"] == 1


def test_the_speed_column_is_not_a_doppler_claim():
    """THE invariant of source class (c): a derived number, and a flag that says so.

    `speed_mps` is populated (the analysis has something to work with) and `has_speed` is
    False (the file never measured it). That pair is what makes `source_class` "c", which
    is what every surface reads to label these speed records uncertified.
    """
    track = parse_gpx_bytes(_doc(f"<trk><trkseg>{_line(5)}</trkseg></trk>"))
    caps = track.capabilities
    assert track.records["speed_mps"].notna().all()
    assert caps.has_speed is False
    assert caps.source_class == "c"
    assert caps.has_position is True
    assert caps.has_dev_fields is False
    assert caps.has_accel is False
    assert track.accel is None
    assert track.laps == []


def test_a_trkpt_without_a_time_is_not_a_sample():
    """Every phase of the analysis is a function of time. A point that cannot say when it
    happened is skipped rather than guessed at — which is also what makes a waypoint-only
    or route-only GPX come back empty instead of coming back wrong."""
    body = (f'<trk><trkseg>{_pt(45.86, 10.87)}'
            f'{_pt(45.8601, 10.87, time=None)}'
            f'{_pt(45.8602, 10.87, time="2026-08-30T12:00:02Z")}</trkseg></trk>')
    df = parse_gpx_bytes(_doc(body)).records
    assert len(df) == 2
    assert df["t"].tolist() == [0.0, 2.0]

    empty = parse_gpx_bytes(_doc("<trk><trkseg></trkseg></trk>"))
    assert len(empty.records) == 0
    assert empty.capabilities.source_class == "c"
    assert empty.capabilities.has_position is False


def test_a_point_without_coordinates_is_skipped():
    body = (f'<trk><trkseg>{_pt(45.86, 10.87)}'
            '<trkpt><time>2026-08-30T12:00:01Z</time></trkpt>'
            f'{_pt(45.8602, 10.87, time="2026-08-30T12:00:02Z")}</trkseg></trk>')
    assert len(parse_gpx_bytes(_doc(body)).records) == 2


# ------------------------------------------------------------------------- extensions


def test_heart_rate_comes_off_the_trackpoint_extension():
    with_hr = parse_gpx_bytes(_doc(f"<trk><trkseg>{_line(4, hr=142)}</trkseg></trk>"))
    assert with_hr.capabilities.has_hr is True
    assert with_hr.records["heart_rate"].tolist() == [142.0] * 4

    without = parse_gpx_bytes(_doc(f"<trk><trkseg>{_line(4)}</trkseg></trk>"))
    assert without.capabilities.has_hr is False
    assert without.records["heart_rate"].isna().all()


def test_elevation_is_carried_through_for_the_barometer_rule():
    body = (f'<trk><trkseg>{_pt(45.86, 10.87, ele=66.6)}'
            f'{_pt(45.8601, 10.87, time="2026-08-30T12:00:01Z", ele=65.1)}</trkseg></trk>')
    df = parse_gpx_bytes(_doc(body)).records
    assert df["altitude"].tolist() == [66.6, 65.1]


# --------------------------------------------------------------------- multi-structure


def test_segments_are_joined_and_the_join_is_a_gap():
    """A `<trkseg>` boundary is the recorder saying it stopped.

    The two sides here abut in time (one second apart), so the dt-aware gap rule alone
    would see one continuous motion. The parser's `gap_before` mark is what keeps them
    apart — and `clean` ORs it into its own rule, so the cleaned track really is two
    segments and the speed is never differentiated across the join.
    """
    seg_a = _line(4)
    seg_b = _line(4, start="2026-08-30T12:00:04Z", step_deg=0.0002)
    track = parse_gpx_bytes(_doc(f"<trk><trkseg>{seg_a}</trkseg>"
                                 f"<trkseg>{seg_b}</trkseg></trk>"))
    df = track.records
    assert len(df) == 8
    assert track.session["gpxSegments"] == 2
    assert df["gap_before"].tolist() == [False] * 4 + [True] + [False] * 3
    assert df["t"].tolist() == [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0]

    ct = clean(track)
    assert ct.records["segment"].tolist() == [0] * 4 + [1] * 4
    assert bool(ct.records["gap_before"].iloc[4]) is True
    # Each segment's speed is its own: the second walks twice as fast, and no sample
    # straddles the join.
    first = ct.records["pos_mps"].to_numpy()[:4]
    second = ct.records["pos_mps"].to_numpy()[4:]
    assert np.nanmax(first) * 1.7 < np.nanmin(second)


def test_only_the_first_track_is_analysed_and_the_count_is_reported():
    """Two `<trk>`s are two activities, not two halves of one. The first is the session;
    the count is written down so a caller can say "this file held 2 tracks"."""
    body = (f"<trk><name>morning</name><trkseg>{_line(3)}</trkseg></trk>"
            f'<trk><name>afternoon</name><trkseg>'
            f'{_line(5, start="2026-08-30T15:00:00Z")}</trkseg></trk>')
    track = parse_gpx_bytes(_doc(body))
    assert len(track.records) == 3
    assert track.session["gpxTracks"] == 2
    assert track.session["gpxName"] == "morning"


# ------------------------------------------------------------------------- time zones


def test_a_z_timestamp_states_an_instant_and_falls_back_to_longitude():
    """`Z` says *when*, never *what the rider's clock read*. Longitude then answers, coarsely
    — the 0.8.2 resolution ladder, one rung down (docs/algorithms.md "Session time")."""
    track = parse_gpx_bytes(_doc(f"<trk><trkseg>{_line(3)}</trkseg></trk>"))
    assert track.start_utc_offset_s == 3600      # lon 10.87° -> round(10.87/15) = 1 h
    # …and it is labelled a guess (engine 0.9.1). This is the common GPX case and the one
    # the honest wording exists for: the true answer that day was +2 h.
    assert track.start_utc_offset_source == "longitude"
    assert str(track.records["timestamp"].iloc[0]) == "2026-08-30 12:00:00+00:00"


def test_a_stated_offset_beats_the_longitude_guess():
    """`+02:00` is the exporter telling us the local clock. Where a guess and an answer
    disagree, the answer wins — and here they do disagree, by an hour of DST."""
    body = (f'<trk><trkseg>{_pt(45.86, 10.87, time="2026-08-30T14:00:00+02:00")}'
            f'{_pt(45.8601, 10.87, time="2026-08-30T14:00:01+02:00")}</trkseg></trk>')
    track = parse_gpx_bytes(_doc(body))
    assert track.start_utc_offset_s == 7200
    # The file said so, so it ranks with a FIT's `activity` message, not with the guess.
    assert track.start_utc_offset_source == "activity"
    # The instant is still stored in UTC, exactly as a FIT's is.
    assert str(track.records["timestamp"].iloc[0]) == "2026-08-30 12:00:00+00:00"


def test_a_naive_timestamp_is_read_as_utc_and_claims_no_clock():
    body = (f'<trk><trkseg>{_pt(45.86, 10.87, time="2026-08-30T12:00:00")}'
            f'{_pt(45.8601, 10.87, time="2026-08-30T12:00:01")}</trkseg></trk>')
    track = parse_gpx_bytes(_doc(body))
    assert str(track.records["timestamp"].iloc[0]) == "2026-08-30 12:00:00+00:00"
    assert track.start_utc_offset_s == 3600      # no claim -> the longitude fallback
    assert track.start_utc_offset_source == "longitude"


# ------------------------------------------------------------------------- the fixture


def test_is_gpx_sniffs_content_not_names():
    assert is_gpx(_doc(f"<trk><trkseg>{_line(2)}</trkseg></trk>")) is True
    assert is_gpx(b"\x0e\x10\xd9\x07....\x2eFIT\x00\x00") is False
    assert is_gpx(b"") is False
    assert is_gpx(b"<html><body>not a track</body></html>") is False


@pytest.mark.skipif(not GPX.exists(), reason="gpx fixture missing")
def test_parse_track_routes_the_fixture_by_itself():
    """One door for both formats — the property every caller (make_goldens, web_entry,
    the ingest path) relies on rather than sniffing extensions of its own."""
    track = parse_track(GPX)
    assert track.capabilities.source_class == "c"
    assert track.capabilities.has_hr is True
    assert len(track.records) == 640
    assert parse_gpx(GPX).records.equals(track.records)


@pytest.mark.skipif(not (GPX.exists() and CIQ.exists()), reason="fixtures missing")
def test_the_converted_fixture_still_describes_the_same_afternoon():
    """The GPX fixture is the CIQ fixture with the channels a GPX cannot carry removed
    (lab/tools/fit_to_gpx.py), so the positions and the clock must survive the round trip
    exactly. Only the derived channels are allowed to move — and the golden pair is where
    that is measured."""
    gpx, fit = parse_track(GPX), parse_track(CIQ)
    assert gpx.records["timestamp"].iloc[0] == fit.records["timestamp"].iloc[0]
    # Every GPX point is a FIT record that carried a fix; six of the FIT's 646 did not.
    fixes = fit.records.dropna(subset=["lat", "lon"])
    assert len(gpx.records) == len(fixes)
    assert np.allclose(gpx.records["lat"].to_numpy(), fixes["lat"].to_numpy(), atol=1e-6)
    assert np.allclose(gpx.records["lon"].to_numpy(), fixes["lon"].to_numpy(), atol=1e-6)
    # …and the two agree about the clock, from opposite ends of the ladder: the FIT's
    # `activity` message says +2 h outright, the GPX gets +1 h from longitude alone.
    assert fit.start_utc_offset_s == 7200
    assert gpx.start_utc_offset_s == 3600
    # The pair is the whole argument for engine 0.9.1: same afternoon, same rider, two
    # offsets an hour apart, and only the provenance tells a reader which to believe.
    assert fit.start_utc_offset_source == "activity"
    assert gpx.start_utc_offset_source == "longitude"
