"""Golden writer/loader: exact docs/testing.md schema, roundtrip stability."""

import json
from collections import Counter
from pathlib import Path

import pytest

from wingfoil_lab.goldens import (RateConfig, _hr_json, analyze, build_golden, dry_jibe_times,
                                  golden_path, load_golden, session_rates, window_rates,
                                  write_golden)
from wingfoil_lab.hrcost import HrAnalysis
from wingfoil_lab.turns import TurnConfig

FIXTURES = Path(__file__).resolve().parents[2] / "fixtures"
SMOKE = Path(__file__).resolve().parents[2] / "fixtures" / "synthetic" / "smoke-60s.fit"
CIQ = (Path(__file__).resolve().parents[2] / "fixtures" / "sessions" / "ciq"
       / "2026-08-07-0754_nago-torbole-windsurfen_ciq.fit")
# The long afternoon session: 51 counted turns and 25 swims, of which only 8 happen inside
# a counted turn -- which is what makes it the fixture that can tell "wet per hour" apart
# from "fell-in jibes per hour". (The session the apps *bundle* is the short 2026-08-30
# one; this is the one long enough to separate the two rates.)
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
                "turnsPerHour", "jibesPerHour", "cleanJibesPerHour", "wetPerHour",
                "windowRates",
                "turns", "flightEnds", "outcomeSplit", "takeoff"}
WINDOW_RATE_KEYS = {"windowMin", "bestJph", "bestJphStartTs", "bestWph", "bestWphStartTs",
                    "series"}
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
    assert g["engineVersion"] == "0.12.0"
    assert set(g["capabilities"].keys()) == CAP_KEYS
    assert set(g["records"].keys()) == RECORD_KEYS
    assert set(g["summary"].keys()) == SUMMARY_KEYS
    assert set(g["summary"]["turns"].keys()) == TURN_SUMMARY_KEYS
    assert set(g["summary"]["flightEnds"].keys()) == {"all", "straight", "inTurn"}
    for family in g["summary"]["flightEnds"].values():
        assert set(family.keys()) == END_COUNT_KEYS
    assert set(g["summary"]["takeoff"].keys()) == TAKEOFF_SUMMARY_KEYS
    assert set(g["summary"]["windowRates"].keys()) == WINDOW_RATE_KEYS
    assert g["config"]["windowRateMin"] == 15.0
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
    """Two hours, 40 km, 60 counted turns of which 44 dry jibes, 9 swims.

    Every rate is per hour of *elapsed* session, so the arithmetic is deliberately trivial
    and hand-checkable: 60 turns in 2 h is 30/h, 9 swims is 4.5/h, 40 km in 2 h is 20 km/h.
    """
    r = session_rates(7200.0, 40_000.0, turns_counted=60, dry_jibes=44, fell_in=9,
                      clean_jibes=22)
    assert r.duration_s == 7200.0
    assert r.avg_speed_kmh == pytest.approx(20.0)
    assert r.turns_per_hour == pytest.approx(30.0)
    assert r.jibes_per_hour == pytest.approx(22.0)
    # CPH is the strict reading of the same set, over the same hour: 22 clean in 2 h is 11/h.
    assert r.clean_jibes_per_hour == pytest.approx(11.0)
    assert r.wet_per_hour == pytest.approx(4.5)

    # Unrounded inputs, rounded only for JSON: a half-hour session divides by 0.5, not by 1.
    half = session_rates(1800.0, 9_000.0, turns_counted=7, dry_jibes=7, fell_in=1)
    assert half.avg_speed_kmh == pytest.approx(18.0)
    assert half.turns_per_hour == pytest.approx(14.0)
    assert half.wet_per_hour == pytest.approx(2.0)


@pytest.mark.parametrize("duration", [0.0, -12.0])
def test_session_rates_without_a_duration_are_none_not_zero(duration):
    """A one-sample track has no hour to divide by. Every rate is null -- 0.0 would read as
    "he did nothing in an hour on the water", which is a different (and wrong) claim."""
    r = session_rates(duration, 1234.0, turns_counted=7, dry_jibes=5, fell_in=2,
                      clean_jibes=3)
    assert r.duration_s == 0.0
    assert r.avg_speed_kmh is None
    assert r.turns_per_hour is None
    assert r.jibes_per_hour is None
    assert r.clean_jibes_per_hour is None
    assert r.wet_per_hour is None


def test_rates_reconcile_with_the_numbers_beside_them(smoke_golden):
    s = smoke_golden["summary"]
    assert s["durationS"] == pytest.approx(60.0, abs=1.5)
    hours = s["durationS"] / 3600.0
    assert s["avgSpeedKmh"] == pytest.approx(s["distanceKm"] / hours, abs=0.05)
    assert s["turnsPerHour"] == pytest.approx(s["turns"]["turnsCounted"] / hours, abs=0.05)
    dry = s["turns"]["jibes"] - s["turns"]["jibeOutcomes"]["fellIn"]
    assert s["jibesPerHour"] == pytest.approx(dry / hours, abs=0.05)
    assert s["cleanJibesPerHour"] == pytest.approx(
        s["turns"]["jibesSuccessful"] / hours, abs=0.05)
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
    dry = turns["jibes"] - turns["jibeOutcomes"]["fellIn"]
    assert s["jibesPerHour"] == pytest.approx(dry / hours, abs=0.05)
    assert s["avgSpeedKmh"] == pytest.approx(s["distanceKm"] / hours, abs=0.05)


@pytest.mark.skipif(not CIQ_LONG.exists(), reason="ciq fixture missing")
def test_jibes_per_hour_counts_only_the_jibes_he_sailed_out_of():
    """The 0.7.0 numerator: dry jibes, not every jibe the detector named.

    2026-08-29 is the session that shows the size of it -- 50 jibes, 7 of them swum, so the
    headline reads 22.0 an hour and not 25.6. A rider cannot raise this number by falling
    more often, which is the whole point of the change.
    """
    a = analyze(CIQ_LONG)
    g = build_golden(a)
    s = g["summary"]
    jibes, fell = s["turns"]["jibes"], s["turns"]["jibeOutcomes"]["fellIn"]
    assert (jibes, fell) == (50, 7)

    # The per-turn list and the tally agree on what "dry" means -- flew-through and
    # touchdown alike, because pumping back up out of a touchdown is a jibe he made.
    dry = dry_jibe_times(a.turns)
    assert len(dry) == jibes - fell == 43
    assert dry == sorted(dry)
    outcomes = s["turns"]["jibeOutcomes"]
    assert len(dry) == outcomes["flewThrough"] + outcomes["touchdown"]

    hours = s["durationS"] / 3600.0
    assert s["jibesPerHour"] == pytest.approx(len(dry) / hours, abs=0.05) == 22.0
    # `turnsPerHour` is untouched: it answers "how busy", not "how well".
    assert s["turnsPerHour"] == pytest.approx(s["turns"]["turnsCounted"] / hours, abs=0.05)
    assert s["jibesPerHour"] < jibes / hours

    # And CPH is the stricter reading of the same 50 jibes: 24 he rode all the way through,
    # 12.3 an hour against the dry 22.0. Never above JPH -- since engine 0.12.0 a clean jibe
    # is a `flew_through` one by *definition* and not merely in practice, so the nesting is
    # structural: every clean jibe is one of the 43 dry ones.
    clean = s["turns"]["jibesSuccessful"]
    assert clean == 24
    assert s["cleanJibesPerHour"] == pytest.approx(clean / hours, abs=0.05) == 12.3
    assert s["cleanJibesPerHour"] < s["jibesPerHour"]
    assert clean <= outcomes["flewThrough"]
    # 0.12.0's whole point: `success` alone starred jibes the rider swam out of. One of the
    # 25 turns that passed the score verdict did not fly through, and is no longer clean.
    assert sum(1 for t in a.turns if t.counted and t.kind == "jibe" and t.success) == 25


def test_window_peak_never_scales_a_partial_window_up():
    """A three-minute burst is not a 60-an-hour session.

    A session shorter than the window has no full window to search, so its peak is its own
    whole-session rate over the span it actually lasted -- the mirror of the never-a-
    flattering-zero rule the four session rates follow (docs/testing.md).
    """
    # 3 minutes, 3 dry jibes: 60/h over the span it lasted, and not one more.
    short = window_rates([10.0, 60.0, 120.0], [30.0], start_t=0.0, duration_s=180.0)
    assert short.best_jph == pytest.approx(60.0)
    assert short.best_jph_start_t == 0.0
    assert short.best_wph == pytest.approx(20.0)
    assert [ (p.start_t, p.jph, p.wph) for p in short.series ] == [(0.0, 60.0, 20.0)]

    # The same burst inside an hour-long session is what it really was: three jibes in the
    # busiest 15 minutes, 12 an hour -- never the 60 the burst alone would have claimed.
    long = window_rates([10.0, 60.0, 120.0], [30.0], start_t=0.0, duration_s=3600.0)
    assert long.best_jph == pytest.approx(12.0)
    assert long.best_jph_start_t == 0.0
    assert long.best_wph == pytest.approx(4.0)


def test_window_peak_finds_the_burst_at_its_own_start():
    """The peak is the true sliding maximum, so it opens on the event that starts the burst.

    Three jibes spanning 899 s inside an hour: exactly one quarter-hour window holds all
    three, and it starts on the first of them. No window on the 60 s grid can -- the one
    that opens at 1980 has closed by 2880 and misses the last -- so the grid sees 2 where
    the rider sailed 3, which is why the peak is anchored on the events and not read off
    the series.
    """
    burst = [2000.0, 2450.0, 2899.0]
    w = window_rates(burst, [], start_t=0.0, duration_s=3600.0)

    assert w.best_jph_start_t == 2000.0                  # the first jibe of the burst
    assert w.best_jph == pytest.approx(12.0)             # 3 in a quarter hour
    # The grid is a sampling of the same function: it can only be lower, never higher.
    assert max(p.jph for p in w.series) == pytest.approx(8.0)
    assert w.best_jph > max(p.jph for p in w.series)
    # Nothing wet happened: a measured 0.0, at the first window there was.
    assert w.best_wph == 0.0 and w.best_wph_start_t == 0.0


def test_window_series_walks_a_60_s_grid_of_full_windows():
    """One point a minute, the first at the session's own start, the last a full window
    before its end -- so every value in the series is a rate over 15 real minutes."""
    w = window_rates([100.0, 200.0], [], start_t=0.0, duration_s=3600.0)
    starts = [p.start_t for p in w.series]
    assert starts[0] == 0.0
    assert starts[-1] == 2700.0                          # 3600 - 900, the last full window
    assert starts == [60.0 * k for k in range(46)]
    assert all(p.jph in (0.0, 4.0, 8.0) for p in w.series)   # 0, 1 or 2 jibes / 0.25 h

    # A session that starts at a non-zero clock keeps the grid anchored to its own start.
    off = window_rates([], [], start_t=1234.5, duration_s=1800.0, cfg=RateConfig())
    assert [p.start_t for p in off.series] == [1234.5 + 60.0 * k for k in range(16)]

    # No duration, no window: null peaks and an empty series, never a flattering 0.0.
    empty = window_rates([1.0], [2.0], start_t=0.0, duration_s=0.0)
    assert empty.best_jph is None and empty.best_wph is None
    assert empty.best_jph_start_t is None and empty.series == []


@pytest.mark.skipif(not CIQ_LONG.exists(), reason="ciq fixture missing")
def test_window_rates_on_the_corpus_reconcile_with_the_events_beside_them():
    """Every window value is a count off the two lists the golden already carries."""
    a = analyze(CIQ_LONG)
    g = build_golden(a)
    w = g["summary"]["windowRates"]
    assert w["windowMin"] == 15.0

    dry = dry_jibe_times(a.turns)
    wet = [e["ts"] for e in g["flightEnds"] if e["outcome"] == "fell_in"]
    span = 900.0

    def count(events, start):
        return sum(1 for e in events if start <= e < start + span)

    for p in w["series"]:
        assert p["jph"] == pytest.approx(count(dry, p["ts"]) * 4, abs=0.05)
        assert p["wph"] == pytest.approx(count(wet, p["ts"]) * 4, abs=0.05)
    # The peaks are the true maxima: at least the best the grid saw, and reproducible by
    # counting the events in the window each one names.
    assert w["bestJph"] >= max(p["jph"] for p in w["series"])
    assert w["bestWph"] >= max(p["wph"] for p in w["series"])
    assert w["bestJph"] == pytest.approx(count(dry, w["bestJphStartTs"]) * 4, abs=0.05)
    assert w["bestWph"] == pytest.approx(count(wet, w["bestWphStartTs"]) * 4, abs=0.05)
    # Every window sits wholly inside the session.
    last_start = g["summary"]["durationS"] - span
    assert 0.0 <= w["bestJphStartTs"] <= last_start
    assert 0.0 <= w["bestWphStartTs"] <= last_start
    assert w["series"][-1]["ts"] <= last_start
    # The busiest quarter hour is busier than the session average -- that is what it is for.
    assert w["bestJph"] > g["summary"]["jibesPerHour"]


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


def test_the_360_detector_is_dark_in_the_document():
    """`detectThreeSixty` off ⇒ the serialized document is the committed golden, exactly.

    Byte-for-byte, not "the numbers agree": the point of a dark detector is that a consumer
    cannot tell it exists. The fixture is chosen for teeth — it is one of the three sessions
    that *does* yield a candidate with the flag up (docs/algorithms.md "360 spins"), so the
    second half of the test proves the first half is not passing by accident.
    """
    golden = load_golden(golden_path(CIQ_LONG, FIXTURES / "goldens"))
    assert build_golden(analyze(CIQ_LONG)) == golden               # shipped defaults
    off = TurnConfig(detect_three_sixty=False)
    assert build_golden(analyze(CIQ_LONG, turn_config=off)) == golden

    on = build_golden(analyze(CIQ_LONG, turn_config=TurnConfig(detect_three_sixty=True)))
    assert on["summary"]["turns"]["threeSixties"] == 1
    assert "threeSixties" not in golden["summary"]["turns"]        # absent, never null
    assert on["config"]["detectThreeSixty"] is True
    assert not set(golden["config"]) & {"detectThreeSixty", "threeSixtyMinDeg",
                                        "threeSixtyMaxS", "threeSixtyReversalDeg",
                                        "threeSixtyMinKmh"}
    # The spin is an extra turn in the list and nothing else: every maneuver tally, the
    # ladders, the streaks and the rates read exactly as they do with the flag down.
    assert len(on["turns"]) == len(golden["turns"]) + 1
    assert [t for t in on["turns"] if t["type"] != "three_sixty"] == golden["turns"]
    assert {k: v for k, v in on["summary"]["turns"].items() if k != "threeSixties"} \
        == golden["summary"]["turns"]
    assert on["summary"]["outcomeSplit"] == golden["summary"]["outcomeSplit"]
    assert on["summary"]["flightEnds"] == golden["summary"]["flightEnds"]
    for key in ("turnsPerHour", "jibesPerHour", "wetPerHour", "windowRates"):
        assert on["summary"][key] == golden["summary"][key]


def test_roundtrip(tmp_path, smoke_golden):
    out = golden_path(SMOKE, tmp_path)
    assert out.name == "smoke-60s.expected.json"
    write_golden(smoke_golden, out)
    assert load_golden(out) == json.loads(json.dumps(smoke_golden))
