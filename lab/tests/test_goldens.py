"""Golden writer/loader: exact docs/testing.md schema, roundtrip stability."""

import json
from pathlib import Path

import pytest

from wingfoil_lab.goldens import analyze, build_golden, golden_path, load_golden, write_golden

SMOKE = Path(__file__).resolve().parents[2] / "fixtures" / "synthetic" / "smoke-60s.fit"

TOP_KEYS = ["engineVersion", "config", "capabilities", "flights", "turns",
            "records", "wind", "takeoffs", "summary"]
CAP_KEYS = {"hasDoppler", "hasDevFields", "hasWatchLaps", "hasAccel", "hasHR", "sampleRateHz"}
RECORD_KEYS = {"best2sKn", "best10sKn", "best5x10sKn", "best100mKn", "best250mKn",
               "best500mKn", "bestNmKn", "bestHourKn", "alpha500Kn", "windows"}
SUMMARY_KEYS = {"foilTimeS", "foilPct", "flightCount", "longestFlightS",
                "longestFlightM", "distanceKm"}


@pytest.fixture(scope="module")
def smoke_golden():
    if not SMOKE.exists():
        pytest.skip("synthetic smoke fixture missing")
    return build_golden(analyze(SMOKE))


def test_schema_shape(smoke_golden):
    g = smoke_golden
    assert list(g.keys()) == TOP_KEYS
    assert g["engineVersion"] == "0.1.0"
    assert set(g["capabilities"].keys()) == CAP_KEYS
    assert set(g["records"].keys()) == RECORD_KEYS
    assert set(g["summary"].keys()) == SUMMARY_KEYS
    # phases not implemented yet -> schema-mandated empties (wind: null is the
    # documented deviation from the schema's wind object)
    assert g["turns"] == []
    assert g["takeoffs"] == []
    assert g["wind"] is None
    assert g["config"]["foilEntrySpeed"] == 12.0
    assert g["config"]["maxAccel1Hz"] == 4.0
    for f in g["flights"]:
        assert set(f.keys()) == {"startTs", "endTs", "distM", "maxKn", "takeoffPumps"}
        assert f["takeoffPumps"] is None


def test_smoke_content(smoke_golden):
    g = smoke_golden
    assert g["capabilities"]["hasDoppler"] is True
    assert g["capabilities"]["sampleRateHz"] == pytest.approx(1.0, abs=0.01)
    assert g["summary"]["flightCount"] == 1
    assert 25.0 <= g["summary"]["longestFlightS"] <= 35.0
    assert g["records"]["best2sKn"] == pytest.approx(22 / 3.6 * 1.9438445, abs=0.05)
    assert g["records"]["bestHourKn"] == 0.0
    assert g["records"]["bestNmKn"] == 0.0
    w = g["records"]["windows"]
    assert "best2s" in w and w["best2s"]["durS"] == 2
    assert "bestHour" not in w and "bestNm" not in w


def test_roundtrip(tmp_path, smoke_golden):
    out = golden_path(SMOKE, tmp_path)
    assert out.name == "smoke-60s.expected.json"
    write_golden(smoke_golden, out)
    assert load_golden(out) == json.loads(json.dumps(smoke_golden))
