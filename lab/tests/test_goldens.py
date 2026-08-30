"""Golden writer/loader: exact docs/testing.md schema, roundtrip stability."""

import json
from collections import Counter
from pathlib import Path

import pytest

from wingfoil_lab.goldens import (_hr_json, analyze, build_golden, golden_path, load_golden,
                                  session_rates, write_golden)
from wingfoil_lab.hrcost import HrAnalysis

SMOKE = Path(__file__).resolve().parents[2] / "fixtures" / "synthetic" / "smoke-60s.fit"
CIQ = (Path(__file__).resolve().parents[2] / "fixtures" / "sessions" / "ciq"
       / "2026-08-07-0754_nago-torbole-windsurfen_ciq.fit")
# The long afternoon session, the one the app bundles: 51 counted turns and 25 swims, of
# which only 8 happen inside a counted turn -- which is what makes it the fixture that can
# tell "wet per hour" apart from "fell-in jibes per hour".
CIQ_LONG = (Path(__file__).resolve().parents[2] / "fixtures" / "sessions" / "ciq"
            / "2026-08-29-1440_nago-torbole-windsurfen_ciq.fit")

TOP_KEYS = ["engineVersion", "config", "capabilities", "flights", "turns", "flightEnds",
            "records", "wind", "takeoffs", "pumpEpisodes", "hr", "summary"]
EPISODE_KEYS = {"startTs", "endTs", "strokes", "outcome", "bursts", "flightIndex",
                "turnIndex", "lookaheadS"}
CAP_KEYS = {"hasDoppler", "hasDevFields", "hasWatchLaps", "hasAccel", "hasHR", "sampleRateHz"}
RECORD_KEYS = {"best2sKn", "best10sKn", "best5x10sKn", "best100mKn", "best250mKn",
               "best500mKn", "bestNmKn", "bestHourKn", "alpha500Kn", "windows"}
SUMMARY_KEYS = {"foilTimeS", "foilPct", "flightCount", "longestFlightS",
                "longestFlightM", "distanceKm", "durationS", "avgSpeedKmh",
                "turnsPerHour", "jibesPerHour", "wetPerHour",
                "turns", "flightEnds", "outcomeSplit", "takeoff"}
TURN_SUMMARY_KEYS = {"tacks", "tacksSuccessful", "jibes", "jibesSuccessful", "unclassified",
                     "turnsCounted", "turnsSuccessful", "successPct", "rejected", "port",
                     "starboard", "unknownSide", "longestDryStreak", "longestFlewStreak",
                     "outcomes", "tackOutcomes", "jibeOutcomes"}
END_COUNT_KEYS = {"glideOut", "touchdown", "fellIn", "unknown", "borderline"}
TAKEOFF_SUMMARY_KEYS = {"takeoffAttempts", "takeoffSuccesses", "avgPumpsToTakeoff",
                        "totalPumpStrokes", "successPct", "failedAttempts", "unknownAttempts",
                        "recoveryEpisodes", "inFlightEpisodes", "inFlightPumpStrokes",
                        "runsJudged", "runsTruncated", "freeTakeoffs", "pumpedTakeoffs",
                        "medianPumpsToTakeoff", "avgPumpsWhenPumped", "avgTakeoffS",
                        "medianTakeoffS"}
HR_KEYS = {"hasHR", "takeoffEvents", "swimEvents", "bins", "summary"}
HR_EVENT_KEYS = {"kind", "index", "ts", "approximate", "strokes", "baselineBpm", "peakBpm",
                 "costBpm", "peakLagS", "baselineCoverage", "peakCoverage", "recoveryHalfS",
                 "recoveryCensored"}
HR_BIN_KEYS = {"startTs", "endTs", "attempts", "successes", "failed", "successPct",
               "avgCostBpm", "medianCostBpm", "costValid", "costTotal", "avgBaselineBpm",
               "avgPumps", "meanBpm"}
HR_SUMMARY_KEYS = {"usablePct", "avgTakeoffCostBpm", "medianTakeoffCostBpm", "takeoffCostValid",
                   "takeoffCostTotal", "approximateTakeoffs", "medianPeakLagS",
                   "bpmPerStroke", "medianBpmPerStroke", "bpmPerStrokeValid",
                   "bpmPerStrokeTotal", "pumpCruise", "medianTakeoffRecoveryS",
                   "takeoffRecoveryValid", "takeoffRecoveryTotal", "medianSwimRecoveryS",
                   "swimRecoveryValid", "swimRecoveryTotal", "avgSwimCostBpm",
                   "swimCostValid", "swimCostTotal"}
HR_PUMP_CRUISE_KEYS = {"pumpingBpm", "cruisingBpm", "deltaBpm", "pumpingSpans",
                       "cruisingSpans", "pumpingCoveredS", "pumpingSpanS",
                       "cruisingCoveredS", "cruisingSpanS"}


@pytest.fixture(scope="module")
def smoke_golden():
    if not SMOKE.exists():
        pytest.skip("synthetic smoke fixture missing")
    return build_golden(analyze(SMOKE))


def test_schema_shape(smoke_golden):
    g = smoke_golden
    assert list(g.keys()) == TOP_KEYS
    assert g["engineVersion"] == "0.6.0"
    assert set(g["capabilities"].keys()) == CAP_KEYS
    assert set(g["records"].keys()) == RECORD_KEYS
    assert set(g["summary"].keys()) == SUMMARY_KEYS
    assert set(g["summary"]["turns"].keys()) == TURN_SUMMARY_KEYS
    assert set(g["summary"]["flightEnds"].keys()) == {"all", "straight", "inTurn"}
    for family in g["summary"]["flightEnds"].values():
        assert set(family.keys()) == END_COUNT_KEYS
    assert set(g["summary"]["takeoff"].keys()) == TAKEOFF_SUMMARY_KEYS
    # A 60 s straight-line synthetic has no turns and no wind axis; every flight start
    # still gets a takeoff run, with `pumps` null because there is no accel stream.
    assert g["turns"] == []
    assert g["wind"] is None
    assert len(g["takeoffs"]) == len(g["flights"])
    assert len(g["flightEnds"]) == len(g["flights"])
    assert g["config"]["foilEntrySpeed"] == 12.0
    assert g["config"]["maxAccel1Hz"] == 4.0
    assert g["config"]["turnMinArc"] == 12.0
    assert g["config"]["turnMinRadius"] == 6.0
    assert g["config"]["pumpMinStrokes"] == 4
    assert g["config"]["takeoffAttemptWindow"] == 10.0
    assert g["config"]["hrCostPeakWindow"] == 30.0
    assert g["config"]["hrMinCoverage"] == 0.6
    assert set(g["hr"].keys()) == HR_KEYS
    assert set(g["hr"]["summary"].keys()) == HR_SUMMARY_KEYS
    assert set(g["hr"]["summary"]["pumpCruise"].keys()) == HR_PUMP_CRUISE_KEYS
    for e in g["hr"]["takeoffEvents"] + g["hr"]["swimEvents"]:
        assert set(e.keys()) == HR_EVENT_KEYS
    for b in g["hr"]["bins"]:
        assert set(b.keys()) == HR_BIN_KEYS
    for f in g["flights"]:
        assert set(f.keys()) == {"startTs", "endTs", "distM", "maxKn", "takeoffPumps"}
        assert f["takeoffPumps"] is None          # no accel stream in the synthetic
    for k in g["takeoffs"]:
        assert k["pumps"] is None and k["success"] is True
    # An accel-less source has no bursts to classify, so the block is an empty *list* —
    # the same way `turns` degrades. Never null: "no episodes" and "this golden predates
    # the block" must not look the same, which is the whole reason the key is written.
    assert g["pumpEpisodes"] == []
    for e in g["flightEnds"]:
        assert e["outcome"] in {"glide_out", "touchdown", "fell_in", "unknown"}


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


def test_session_rates_on_a_synthetic_session():
    """Two hours, 40 km, 60 counted turns of which 44 jibes, 9 swims.

    Every rate is per hour of *elapsed* session, so the arithmetic is deliberately trivial
    and hand-checkable: 60 turns in 2 h is 30/h, 9 swims is 4.5/h, 40 km in 2 h is 20 km/h.
    """
    r = session_rates(7200.0, 40_000.0, turns_counted=60, jibes=44, fell_in=9)
    assert r.duration_s == 7200.0
    assert r.avg_speed_kmh == pytest.approx(20.0)
    assert r.turns_per_hour == pytest.approx(30.0)
    assert r.jibes_per_hour == pytest.approx(22.0)
    assert r.wet_per_hour == pytest.approx(4.5)

    # Unrounded inputs, rounded only for JSON: a half-hour session divides by 0.5, not by 1.
    half = session_rates(1800.0, 9_000.0, turns_counted=7, jibes=7, fell_in=1)
    assert half.avg_speed_kmh == pytest.approx(18.0)
    assert half.turns_per_hour == pytest.approx(14.0)
    assert half.wet_per_hour == pytest.approx(2.0)


@pytest.mark.parametrize("duration", [0.0, -12.0])
def test_session_rates_without_a_duration_are_none_not_zero(duration):
    """A one-sample track has no hour to divide by. Every rate is null -- 0.0 would read as
    "he did nothing in an hour on the water", which is a different (and wrong) claim."""
    r = session_rates(duration, 1234.0, turns_counted=7, jibes=5, fell_in=2)
    assert r.duration_s == 0.0
    assert r.avg_speed_kmh is None
    assert r.turns_per_hour is None
    assert r.jibes_per_hour is None
    assert r.wet_per_hour is None


def test_rates_reconcile_with_the_numbers_beside_them(smoke_golden):
    s = smoke_golden["summary"]
    assert s["durationS"] == pytest.approx(60.0, abs=1.5)
    hours = s["durationS"] / 3600.0
    assert s["avgSpeedKmh"] == pytest.approx(s["distanceKm"] / hours, abs=0.05)
    assert s["turnsPerHour"] == pytest.approx(s["turns"]["turnsCounted"] / hours, abs=0.05)
    assert s["jibesPerHour"] == pytest.approx(s["turns"]["jibes"] / hours, abs=0.05)
    assert s["wetPerHour"] == pytest.approx(s["flightEnds"]["all"]["fellIn"] / hours, abs=0.05)


@pytest.mark.skipif(not CIQ_LONG.exists(), reason="ciq fixture missing")
def test_wet_per_hour_counts_straight_falls_as_well_as_turn_falls():
    """"How often did he get wet" is a question about the rider, not about the turn channel.

    2026-08-29 is the session that proves the difference matters: 25 fell-in flight ends, and
    only 8 of them inside a counted turn. A rate built from turn outcomes alone would tell
    this rider he swam a third as often as he did.
    """
    g = build_golden(analyze(CIQ_LONG))
    s = g["summary"]
    ends, turns = s["flightEnds"], s["turns"]

    # Both channels, once each: every fell-in end is either owned by a turn or it is not.
    assert ends["all"]["fellIn"] == ends["straight"]["fellIn"] + ends["inTurn"]["fellIn"]
    assert ends["straight"]["fellIn"] > 0 and ends["inTurn"]["fellIn"] > 0
    # Strictly more than the turn ladder sees -- the straight-line swims are the difference.
    assert ends["all"]["fellIn"] > turns["outcomes"]["fellIn"]

    hours = s["durationS"] / 3600.0
    assert hours > 0
    assert s["wetPerHour"] == pytest.approx(ends["all"]["fellIn"] / hours, abs=0.05)
    assert s["wetPerHour"] > turns["outcomes"]["fellIn"] / hours
    # And the other three rates still speak for their own channels.
    assert s["turnsPerHour"] == pytest.approx(turns["turnsCounted"] / hours, abs=0.05)
    assert s["jibesPerHour"] == pytest.approx(turns["jibes"] / hours, abs=0.05)
    assert s["avgSpeedKmh"] == pytest.approx(s["distanceKm"] / hours, abs=0.05)


def test_a_source_without_hr_still_gets_the_block():
    """`hasHR: false` is written, never a missing key: "this source had no heart rate" and
    "this golden predates the HR block" must not look the same to a reader or to Swift."""
    block = _hr_json(HrAnalysis())
    assert set(block.keys()) == HR_KEYS
    assert block["hasHR"] is False
    assert block["summary"]["usablePct"] is None
    assert block["takeoffEvents"] == [] and block["swimEvents"] == [] and block["bins"] == []
    assert set(block["summary"].keys()) == HR_SUMMARY_KEYS
    assert block["summary"]["avgTakeoffCostBpm"] is None
    assert block["summary"]["takeoffCostValid"] == 0


@pytest.mark.skipif(not CIQ.exists(), reason="ciq fixture missing")
def test_pump_episodes_are_serialized_whole():
    """2026-08-07, the one accel fixture: what the classifier saw reaches the file.

    This is the block that lets a consumer *place* a failed attempt, so the contract is
    both directions of it -- the counts reconcile with the tallies beside them, and every
    episode carries the instants a lookup needs. The 14 failed attempts of this session
    were the point: they were counted from 0.2.0 onward and locatable from 0.3.0.
    """
    a = analyze(CIQ)
    g = build_golden(a)
    eps, tk = g["pumpEpisodes"], g["summary"]["takeoff"]

    assert len(eps) == len(a.takeoffs.episodes)     # every episode, not just the failed ones
    assert all(set(e.keys()) == EPISODE_KEYS for e in eps)
    counts = Counter(e["outcome"] for e in eps)
    assert counts["failed"] == tk["failedAttempts"] == 14
    assert counts["success"] == tk["takeoffSuccesses"] == len(g["flights"]) == 23
    assert counts["in_flight"] == tk["inFlightEpisodes"]
    assert counts["unknown"] == tk["unknownAttempts"]
    assert counts["recovery"] == tk["recoveryEpisodes"]

    # Detection order, which is time order: an iOS map positions a marker by looking
    # `startTs` up in the track, so a shuffled list would silently move every marker.
    assert [e["startTs"] for e in eps] == sorted(e["startTs"] for e in eps)
    assert all(e["endTs"] >= e["startTs"] for e in eps)
    assert all(e["strokes"] >= g["config"]["pumpMinStrokes"] for e in eps)

    # The successes point at the flights they produced, one each; only a recovery names a
    # turn. Cross-referencing is the whole reason the indices are in the file.
    produced = sorted(e["flightIndex"] for e in eps if e["outcome"] == "success")
    assert produced == list(range(len(g["flights"])))
    assert all(e["turnIndex"] is None for e in eps if e["outcome"] != "recovery")

    # Every failed attempt is locatable: a timestamp inside the recording, and enough
    # gap-free record after it that "he did not get up" is evidence rather than a gap.
    span = (g["flights"][0]["startTs"], g["flights"][-1]["endTs"])
    for e in eps:
        if e["outcome"] != "failed":
            continue
        assert e["lookaheadS"] == g["config"]["takeoffAttemptWindow"]
        assert e["flightIndex"] is None and e["turnIndex"] is None
        assert span[0] - 600.0 <= e["startTs"] <= span[1] + 600.0


def test_roundtrip(tmp_path, smoke_golden):
    out = golden_path(SMOKE, tmp_path)
    assert out.name == "smoke-60s.expected.json"
    write_golden(smoke_golden, out)
    assert load_golden(out) == json.loads(json.dumps(smoke_golden))
