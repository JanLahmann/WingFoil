"""TCX parsing: the door that can be either input class.

`test_gpx.py` pins down one source class; this file pins down the *choice* between two.
A TCX carries positions and a clock like a GPX, and it may also carry the receiver's own
speed in `Extensions/TPX/Speed`. One element decides whether the analysis may call the
speed records certified, so that one element is what most of these tests are about:

    TPX/Speed present  -> has_speed True,  source_class "b", the speed is the file's own
    TPX/Speed absent   -> has_speed False, source_class "c", the speed is differentiated

Everything else a TCX shares with a GPX and the code is shared with it, so the tests that
matter next are the ones that prove the sharing really happened — the same positional
speed, the same zone ladder, the same "no time, no sample" rule.
"""

from pathlib import Path

import numpy as np
import pytest

from wingfoil_lab.filters import clean
from wingfoil_lab.gpx import parse_gpx
from wingfoil_lab.parse import parse_track
from wingfoil_lab.tcx import is_tcx, parse_tcx, parse_tcx_bytes

FIXTURES = Path(__file__).resolve().parents[2] / "fixtures"
TCX_DIR = FIXTURES / "sessions" / "tcx"
TCX_SPEED = TCX_DIR / "2026-08-30-1407_nago-torbole-speed.tcx"
TCX_NOSPEED = TCX_DIR / "2026-08-30-1407_nago-torbole-nospeed.tcx"
GPX = FIXTURES / "sessions" / "gpx" / "2026-08-30-1407_nago-torbole.gpx"
CIQ = (FIXTURES / "sessions" / "ciq"
       / "2026-08-30-1407_nago-torbole-windsurfen_ciq.fit")

HEAD = ('<?xml version="1.0" encoding="UTF-8"?>\n'
        '<TrainingCenterDatabase '
        'xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" '
        'xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2">')


def _doc(body: str) -> bytes:
    return f"{HEAD}{body}</TrainingCenterDatabase>".encode()


def _activity(laps: str, sport: str = "Other") -> str:
    return (f'<Activities><Activity Sport="{sport}">'
            f"<Id>2026-08-30T12:00:00Z</Id>{laps}</Activity></Activities>")


def _lap(tracks: str, start: str = "2026-08-30T12:00:00Z") -> str:
    return f'<Lap StartTime="{start}"><TotalTimeSeconds>10.0</TotalTimeSeconds>{tracks}</Lap>'


def _pt(lat: float | None, lon: float | None, time: str | None = "2026-08-30T12:00:00Z",
        ele: float | None = None, hr: int | None = None,
        speed: float | None = None) -> str:
    inner = ""
    if time is not None:
        inner += f"<Time>{time}</Time>"
    if lat is not None and lon is not None:
        inner += (f"<Position><LatitudeDegrees>{lat}</LatitudeDegrees>"
                  f"<LongitudeDegrees>{lon}</LongitudeDegrees></Position>")
    if ele is not None:
        inner += f"<AltitudeMeters>{ele}</AltitudeMeters>"
    if hr is not None:
        inner += f"<HeartRateBpm><Value>{hr}</Value></HeartRateBpm>"
    if speed is not None:
        inner += ("<Extensions><ns3:TPX>"
                  f"<ns3:Speed>{speed}</ns3:Speed></ns3:TPX></Extensions>")
    return f"<Trackpoint>{inner}</Trackpoint>"


def _line(n: int, *, start: str = "2026-08-30T12:00:00Z", step_deg: float = 0.0001,
          hr: int | None = None, speed: float | None = None) -> str:
    """`n` points a second apart, walking north — a track with a speed to derive."""
    import datetime as dt
    t0 = dt.datetime.fromisoformat(start.replace("Z", "+00:00"))
    return "".join(
        _pt(45.86 + i * step_deg, 10.87,
            time=(t0 + dt.timedelta(seconds=i)).strftime("%Y-%m-%dT%H:%M:%SZ"),
            hr=hr, speed=speed)
        for i in range(n))


def _track(body: str) -> str:
    return f"<Track>{body}</Track>"


def _simple(n: int = 5, **kw) -> bytes:
    return _doc(_activity(_lap(_track(_line(n, **kw)))))


# ------------------------------------------------------------------ the class rule


def test_a_tcx_without_tpx_speed_is_class_c():
    """No stated speed: the column is populated by differentiation, the flag is not.

    The same invariant `test_gpx.py` states — a derived number and a flag that says so —
    reached by the other door. `has_speed` False is what makes `source_class` "c", which
    is what every surface reads to mark these speed records uncertified.
    """
    track = parse_tcx_bytes(_simple(5))
    caps = track.capabilities
    assert track.records["speed_mps"].notna().all()
    assert caps.has_speed is False
    assert caps.source_class == "c"
    assert caps.has_position is True
    assert caps.has_dev_fields is False
    assert caps.has_accel is False
    assert track.accel is None


def test_a_tcx_with_tpx_speed_is_class_b():
    """`Extensions/TPX/Speed` is the receiver's own measurement, so the file certifies.

    This is the one thing a TCX can say that a GPX cannot, and the whole reason the format
    needed a rule of its own rather than being filed under "XML, therefore class (c)".
    """
    track = parse_tcx_bytes(_simple(5, speed=6.25))
    caps = track.capabilities
    assert caps.has_speed is True
    assert caps.source_class == "b"
    assert track.records["speed_mps"].tolist() == [6.25] * 5


def test_the_stated_speed_is_carried_through_untouched():
    """A class-(b) TCX's speed column is the file's, not a differentiation of positions.

    The points below walk ~11 m/s; the file says 3.0. If the parser ever silently preferred
    its own arithmetic the column would read 11, and the session would be reporting a speed
    nobody recorded.
    """
    track = parse_tcx_bytes(_simple(4, speed=3.0))
    assert track.records["speed_mps"].tolist() == [3.0] * 4
    assert not track.records["speed_mps"].between(10.0, 12.0).any()


def test_a_single_stated_speed_is_enough_to_make_the_file_class_b():
    """The capability is a question about the *file*, not about coverage.

    A speed on one point and none on the rest is a recording with a speed channel that has
    holes in it, which is exactly what a FIT with dropped samples is; the rows without one
    carry NaN and `clean` drops them, the same treatment they would get from a FIT.
    """
    body = _track(_pt(45.86, 10.87, speed=4.0)
                  + _pt(45.8601, 10.87, time="2026-08-30T12:00:01Z")
                  + _pt(45.8602, 10.87, time="2026-08-30T12:00:02Z"))
    track = parse_tcx_bytes(_doc(_activity(_lap(body))))
    assert track.capabilities.source_class == "b"
    assert track.records["speed_mps"].notna().tolist() == [True, False, False]


def test_a_negative_or_unreadable_speed_is_not_a_speed():
    """Fail-soft: a malformed number is dropped rather than raised on, and a negative one
    is not a measurement of anything — either way the file has said nothing."""
    body = _track(_pt(45.86, 10.87) .replace("</Trackpoint>",
                  "<Extensions><ns3:TPX><ns3:Speed>-1</ns3:Speed></ns3:TPX>"
                  "</Extensions></Trackpoint>")
                  + _pt(45.8601, 10.87, time="2026-08-30T12:00:01Z"))
    track = parse_tcx_bytes(_doc(_activity(_lap(body))))
    assert track.capabilities.source_class == "c"


# ------------------------------------------------------------- shared with the GPX door


def test_a_minimal_tcx_becomes_a_track():
    track = parse_tcx_bytes(_simple(3))
    df = track.records
    assert len(df) == 3
    assert list(df.columns) == ["timestamp", "lat", "lon", "altitude", "heart_rate",
                                "t", "speed_mps", "gap_before"]
    assert df["t"].tolist() == [0.0, 1.0, 2.0]
    # ~0.0001° of latitude is ~11 m, walked in a second — the GPX module's arithmetic.
    assert df["speed_mps"].between(10.0, 12.0).all()
    assert track.session["tcxActivities"] == 1 and track.session["tcxTracks"] == 1


def test_a_trackpoint_without_a_time_is_not_a_sample():
    body = _track(_pt(45.86, 10.87)
                  + _pt(45.8601, 10.87, time=None)
                  + _pt(45.8602, 10.87, time="2026-08-30T12:00:02Z"))
    df = parse_tcx_bytes(_doc(_activity(_lap(body)))).records
    assert df["t"].tolist() == [0.0, 2.0]


def test_a_trackpoint_without_a_position_is_skipped():
    """TCX's own commonest degenerate shape: an indoor trackpoint with a clock, a heart
    rate and nowhere at all."""
    body = _track(_pt(45.86, 10.87)
                  + _pt(None, None, time="2026-08-30T12:00:01Z", hr=140)
                  + _pt(45.8602, 10.87, time="2026-08-30T12:00:02Z"))
    assert len(parse_tcx_bytes(_doc(_activity(_lap(body)))).records) == 2


def test_heart_rate_and_altitude_come_off_the_trackpoint():
    body = _track(_pt(45.86, 10.87, ele=66.6, hr=142)
                  + _pt(45.8601, 10.87, time="2026-08-30T12:00:01Z", ele=65.1, hr=143))
    track = parse_tcx_bytes(_doc(_activity(_lap(body))))
    assert track.capabilities.has_hr is True
    assert track.records["heart_rate"].tolist() == [142.0, 143.0]
    assert track.records["altitude"].tolist() == [66.6, 65.1]


def test_a_second_track_element_is_a_gap_and_a_second_lap_is_not():
    """The two container levels mean different things, and only one of them is a stop.

    A `<Lap>` is a marker the rider pressed — the board kept moving through it — so the
    samples either side are one motion. A second `<Track>` is the recorder having stopped,
    which is what a GPX `<trkseg>` boundary says, so that is the join `gap_before` marks
    and the join `clean` refuses to differentiate across.
    """
    lap_a = _lap(_track(_line(4)))
    lap_b = _lap(_track(_line(4, start="2026-08-30T12:00:04Z", step_deg=0.0002)),
                 start="2026-08-30T12:00:04Z")
    two_laps = parse_tcx_bytes(_doc(_activity(lap_a + lap_b)))
    assert two_laps.records["gap_before"].tolist() == [False] * 4 + [True] + [False] * 3
    assert two_laps.session["tcxTracks"] == 2
    assert two_laps.capabilities.has_watch_laps is True
    assert len(two_laps.laps) == 2

    # One lap, one track, eight points: nothing to mark, because nothing stopped.
    one = parse_tcx_bytes(_doc(_activity(_lap(_track(_line(8))))))
    assert one.records["gap_before"].tolist() == [False] * 8
    assert one.capabilities.has_watch_laps is False

    ct = clean(two_laps)
    assert ct.records["segment"].tolist() == [0] * 4 + [1] * 4
    first = ct.records["pos_mps"].to_numpy()[:4]
    second = ct.records["pos_mps"].to_numpy()[4:]
    assert np.nanmax(first) * 1.7 < np.nanmin(second)


def test_only_the_first_activity_is_analysed_and_the_count_is_reported():
    """Two `<Activity>`s are two sessions, not two halves of one — `gpx.py`'s rule for
    several `<trk>`s, applied one level up."""
    body = (f'<Activities><Activity Sport="Other"><Id>morning</Id>{_lap(_track(_line(3)))}'
            "</Activity>"
            f'<Activity Sport="Other"><Id>afternoon</Id>'
            f'{_lap(_track(_line(5, start="2026-08-30T15:00:00Z")))}</Activity></Activities>')
    track = parse_tcx_bytes(_doc(body))
    assert len(track.records) == 3
    assert track.session["tcxActivities"] == 2
    assert track.session["tcxId"] == "morning"


def test_the_sport_attribute_is_not_read_as_a_sport():
    """TCX admits Running | Biking | Other, so every watersport session is `Other`.

    Filing that as the session's sport would turn "this file cannot say" into a claim, and
    a watersport gate downstream would then act on it. Silence is the honest answer, and
    it is also what keeps a hand-picked TCX importable at all.
    """
    track = parse_tcx_bytes(_simple(3, ))
    assert track.capabilities.sport is None
    assert track.capabilities.sub_sport is None
    assert track.capabilities.discipline is None


# ------------------------------------------------------------------------- time zones


def test_a_z_timestamp_states_an_instant_and_falls_back_to_longitude():
    track = parse_tcx_bytes(_simple(3))
    assert track.start_utc_offset_s == 3600      # lon 10.87° -> round(10.87/15) = 1 h
    assert track.start_utc_offset_source == "longitude"
    assert str(track.records["timestamp"].iloc[0]) == "2026-08-30 12:00:00+00:00"


def test_a_stated_offset_beats_the_longitude_guess():
    body = _track(_pt(45.86, 10.87, time="2026-08-30T14:00:00+02:00")
                  + _pt(45.8601, 10.87, time="2026-08-30T14:00:01+02:00"))
    track = parse_tcx_bytes(_doc(_activity(_lap(body))))
    assert track.start_utc_offset_s == 7200
    assert track.start_utc_offset_source == "activity"
    assert str(track.records["timestamp"].iloc[0]) == "2026-08-30 12:00:00+00:00"


# ------------------------------------------------------------------------- the sniffer


def test_is_tcx_sniffs_content_not_names():
    assert is_tcx(_simple(2)) is True
    assert is_tcx(b'<?xml version="1.0"?><gpx version="1.1"><trk/></gpx>') is False
    assert is_tcx(b"\x0e\x10\xd9\x07....\x2eFIT\x00\x00") is False
    assert is_tcx(b"") is False
    assert is_tcx(b"<html><body>not a track</body></html>") is False


# ------------------------------------------------------------------------ the fixtures


@pytest.mark.skipif(not (TCX_SPEED.exists() and TCX_NOSPEED.exists()),
                    reason="tcx fixtures missing")
def test_parse_track_routes_both_fixtures_by_itself():
    """One door for every format — what `make_goldens`, `web_entry` and the ingest path
    all rely on rather than sniffing extensions of their own."""
    fast, slow = parse_track(TCX_SPEED), parse_track(TCX_NOSPEED)
    assert fast.capabilities.source_class == "b"
    assert slow.capabilities.source_class == "c"
    assert len(fast.records) == len(slow.records) == 640
    assert fast.capabilities.has_hr is slow.capabilities.has_hr is True
    assert parse_tcx(TCX_SPEED).records.equals(fast.records)


@pytest.mark.skipif(not (TCX_NOSPEED.exists() and GPX.exists()),
                    reason="fixtures missing")
def test_the_speedless_tcx_and_the_gpx_are_the_same_session_twice():
    """Both are the 2026-08-30 CIQ afternoon with its speed channel removed, in the two XML
    formats. They must land on the *same* derived speed to the last digit — that is the
    whole claim of sharing `gpx._segment_speed` rather than writing it twice."""
    tcx, gpx = parse_track(TCX_NOSPEED), parse_gpx(GPX)
    assert len(tcx.records) == len(gpx.records)
    assert np.allclose(tcx.records["lat"].to_numpy(), gpx.records["lat"].to_numpy())
    assert np.allclose(tcx.records["speed_mps"].to_numpy(),
                       gpx.records["speed_mps"].to_numpy(), equal_nan=True)
    assert tcx.capabilities.source_class == gpx.capabilities.source_class == "c"


@pytest.mark.skipif(not (TCX_SPEED.exists() and CIQ.exists()), reason="fixtures missing")
def test_the_speed_bearing_tcx_keeps_the_fits_own_channel():
    """The class-(b) fixture is the CIQ FIT's Doppler written into `TPX/Speed`, so the two
    describe the same afternoon with the same speeds — six of the FIT's 646 records carried
    no fix and are the only samples missing."""
    tcx, fit = parse_track(TCX_SPEED), parse_track(CIQ)
    fixes = fit.records.dropna(subset=["lat", "lon"])
    assert len(tcx.records) == len(fixes)
    assert np.allclose(tcx.records["speed_mps"].to_numpy(),
                       fixes["speed_mps"].to_numpy(float), atol=5e-4, equal_nan=True)
    # The FIT is class (a) because of our developer fields; the TCX is (b) because it has
    # a measured speed and nothing of ours. Both certify.
    assert fit.capabilities.source_class == "a"
    assert tcx.capabilities.source_class == "b"
