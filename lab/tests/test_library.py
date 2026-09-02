"""The session-library glue's arithmetic, in plain CPython.

`web/lab_bundle/library.py` is hand-written browser-side Python — it is not part of the
`wingfoil_lab` package and is not generated from it (`web/tools/bundle_lab.py` only copies
the engine). It is still Python, though, and the numbers it produces are the ones the
analyzer's Records and Trends screens show, so its rules belong under `pytest` with every
other rule in the project.

`web/tools/verify_library.py` covers the same module against the real FIT corpus and takes
~20 s doing it. These tests are the fast half: the *rules* — the records catalogue, the tie
rule, the >= 5 jibes floor and the ISO week buckets — asserted on synthetic digests, where
the expected answer can be written down rather than derived.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "web" / "lab_bundle"))

import library                                                          # noqa: E402


def entry(ident: str, day: str, epoch: float, **overrides) -> dict:
    """A stored library entry, thin but complete: everything `aggregate` reads is present,
    so an override is the only thing under test."""
    turns = {"counted": 12, "successful": 5, "successPct": 41.67, "jibes": 8, "tacks": 4,
             "jibesSuccessful": 5, "longestDryStreak": 6, "longestFlewStreak": 3,
             "outcomes": {"flewThrough": 3, "touchdown": 2, "fellIn": 7},
             "bySide": {"port": {"entries": 6, "successes": 3, "successPct": 50.0},
                        "starboard": {"entries": 6, "successes": 2, "successPct": 33.33}}}
    e = {"schema": library.SCHEMA, "id": ident, "fileName": f"{ident}.fit", "spot": ident,
         "startUtc": f"{day}T08:00:00Z", "startEpoch": epoch, "dateUtc": day,
         "dateLocal": day, "utcOffsetS": 7200, "durationS": 3600.0, "distanceKm": 12.0,
         "foilPct": 55.0, "foilTimeS": 1980.0, "flightCount": 9, "longestFlightS": 120.0,
         "longestFlightM": 640.0, "sourceClass": "b", "hasAccel": True,
         "records": {"best2sKn": 14.0}, "recordWindows": {"best2sKn": []},
         "turns": turns, "takeoff": {"attempts": 9, "successes": 9,
                                     "avgPumpsToTakeoff": 4.0}}
    turn_overrides = overrides.pop("turns", None)
    if turn_overrides:
        e["turns"] = {**turns, **turn_overrides}
    e.update(overrides)
    return e


def records_of(entries: list[dict]) -> dict:
    return {r["key"]: r for r in library.aggregate(entries)["sessionRecords"]}


# ------------------------------------------------------------------ the record catalogue


def test_session_records_are_the_ten_kinds_in_catalogue_order():
    """The list and its order are a contract with iOS's `SessionRecordKind`: the two
    tables show the same rows in the same sequence, or one of the apps is lying about
    what "your records" means."""
    keys = [k for k, *_ in library.SESSION_RECORD_KINDS]
    assert keys == ["longestFlight", "mostFlights", "bestFoilPct", "mostCleanJibes",
                    "bestCph", "bestCleanJibeRate", "longestDryStreak",
                    "longestFlewStreak", "longestSession", "mostDistance"]
    rows = library.aggregate([entry("a", "2026-08-03", 1000.0)])["sessionRecords"]
    assert [r["key"] for r in rows] == keys


def test_each_record_is_the_maximum_over_the_library():
    older = entry("older", "2026-08-03", 1000.0)
    newer = entry("newer", "2026-08-10", 2000.0, durationS=7200.0, distanceKm=30.0,
                  flightCount=4, foilPct=40.0, longestFlightS=90.0,
                  turns={"jibes": 20, "jibesSuccessful": 8, "longestDryStreak": 9,
                         "longestFlewStreak": 1})
    rows = records_of([older, newer])
    assert (rows["longestFlight"]["value"], rows["longestFlight"]["id"]) == (120.0, "older")
    assert (rows["mostFlights"]["value"], rows["mostFlights"]["id"]) == (9, "older")
    assert (rows["bestFoilPct"]["value"], rows["bestFoilPct"]["id"]) == (55.0, "older")
    assert (rows["mostCleanJibes"]["value"], rows["mostCleanJibes"]["id"]) == (8, "newer")
    # 5 clean in one hour beats 8 clean in two.
    assert (rows["bestCph"]["value"], rows["bestCph"]["id"]) == (5.0, "older")
    assert (rows["bestCleanJibeRate"]["value"], rows["bestCleanJibeRate"]["id"]) \
        == (62.5, "older")
    assert (rows["longestDryStreak"]["value"], rows["longestDryStreak"]["id"]) == (9, "newer")
    assert (rows["longestFlewStreak"]["value"], rows["longestFlewStreak"]["id"]) == (3, "older")
    assert (rows["longestSession"]["value"], rows["longestSession"]["id"]) == (7200, "newer")
    assert (rows["mostDistance"]["value"], rows["mostDistance"]["id"]) == (30.0, "newer")


def test_a_record_row_names_its_session_and_carries_no_certification():
    """A session record is not a speed claim: the `uncertified` badge the GP3S table wears
    would be answering a question nobody asked here."""
    rows = records_of([entry("only", "2026-08-03", 1000.0, sourceClass="c")])
    row = rows["mostDistance"]
    assert (row["id"], row["dateLocal"], row["spot"]) == ("only", "2026-08-03", "only")
    assert all("certified" not in r for r in rows.values())
    # …while the GP3S table still marks exactly that session.
    speed = library.aggregate([entry("only", "2026-08-03", 1000.0, sourceClass="c")])["records"]
    assert speed[0]["certified"] is False


def test_the_longest_flight_names_its_distance_in_a_caption():
    rows = records_of([entry("a", "2026-08-03", 1000.0, longestFlightM=642.4)])
    assert rows["longestFlight"]["caption"] == "642 m of it"


def test_a_kind_nobody_set_is_dropped_rather_than_shown_as_zero():
    flat = entry("flat", "2026-08-03", 1000.0, distanceKm=0.0, flightCount=0,
                 turns={"jibes": 0, "jibesSuccessful": 0, "longestDryStreak": 0,
                        "longestFlewStreak": 0})
    keys = set(records_of([flat]))
    assert "mostDistance" not in keys and "mostFlights" not in keys
    assert "mostCleanJibes" not in keys and "longestDryStreak" not in keys
    assert "longestSession" in keys, "the session still lasted an hour"


def test_a_digest_saved_before_schema_5_sets_no_jibe_record():
    """Absent is not zero. The three turn counts arrived with schema 5; a library saved
    before it must drop out of those records rather than claim a zero best."""
    old = entry("old", "2026-08-03", 1000.0)
    old["turns"] = {k: v for k, v in old["turns"].items()
                    if k not in ("jibesSuccessful", "longestDryStreak", "longestFlewStreak")}
    keys = set(records_of([old]))
    assert not keys & {"mostCleanJibes", "bestCph", "bestCleanJibeRate",
                       "longestDryStreak", "longestFlewStreak"}
    assert {"mostDistance", "longestSession", "longestFlight"} <= keys


# ---------------------------------------------------------------------- the tie rule


def test_a_tie_goes_to_the_earliest_session():
    """The record was set then, not re-set later — the same rule the GP3S table follows."""
    first = entry("first", "2026-08-03", 1000.0)
    second = entry("second", "2026-08-10", 2000.0)
    third = entry("third", "2026-08-17", 3000.0)
    for order in ([first, second, third], [third, second, first], [second, third, first]):
        rows = records_of(order)
        assert rows["longestSession"]["id"] == "first"
        assert rows["mostCleanJibes"]["id"] == "first"
    # And a later session that actually beats it does take the record.
    rows = records_of([first, entry("beat", "2026-08-10", 2000.0, durationS=3600.1)])
    assert rows["longestSession"]["id"] == "beat"


# ------------------------------------------------------------------- the >= 5 jibes floor


@pytest.mark.parametrize("jibes,clean,expected", [
    (0, 0, None), (1, 1, None), (4, 4, None),                 # under the floor
    (5, 4, 80.0), (5, 5, 100.0), (20, 3, 15.0),               # at it and above
])
def test_the_clean_jibe_rate_needs_five_jibes(jibes, clean, expected):
    """Four out of four is a good afternoon; it is not a rate. The floor is stated in
    `MIN_JIBES_FOR_RATE`, applied once, and printed in both apps' captions."""
    e = entry("a", "2026-08-03", 1000.0,
              turns={"jibes": jibes, "jibesSuccessful": clean})
    assert records_of([e]).get("bestCleanJibeRate", {}).get("value") == expected


def test_the_rate_record_ignores_a_perfect_thin_session_entirely():
    perfect = entry("perfect", "2026-08-03", 1000.0,
                    turns={"jibes": 3, "jibesSuccessful": 3})
    honest = entry("honest", "2026-08-10", 2000.0,
                   turns={"jibes": 10, "jibesSuccessful": 4})
    rows = records_of([perfect, honest])
    assert (rows["bestCleanJibeRate"]["id"], rows["bestCleanJibeRate"]["value"]) \
        == ("honest", 40.0)
    assert rows["bestCleanJibeRate"]["caption"] == "Sessions with at least 5 jibes."


def test_cph_is_clean_jibes_over_elapsed_hours():
    """The engine is gaining a `cleanJibesPerHour` of its own; until every stored digest
    carries it, this is the arithmetic, and it is this arithmetic that is pinned."""
    half = entry("half", "2026-08-03", 1000.0, durationS=1800.0,
                 turns={"jibes": 9, "jibesSuccessful": 6})
    assert records_of([half])["bestCph"]["value"] == 12.0
    zero = entry("zero", "2026-08-03", 1000.0, durationS=0.0)
    assert "bestCph" not in records_of([zero])


# ------------------------------------------------------------------- the ISO week buckets


@pytest.mark.parametrize("day,monday", [
    ("2026-08-01", "2026-07-27"),      # a Saturday belongs to the Monday behind it
    ("2026-08-02", "2026-07-27"),      # …and so does the Sunday after it
    ("2026-08-03", "2026-08-03"),      # the Monday opens the next week
    ("2026-08-09", "2026-08-03"),      # …which the following Sunday closes
    ("2026-01-01", "2025-12-29"),      # a week that straddles the new year
])
def test_a_week_starts_on_its_iso_monday(day, monday):
    assert library._week_start(day) == monday


def test_a_saturday_and_the_next_monday_are_different_weeks():
    """The one boundary a Sunday-first calendar gets wrong, stated as a test on both
    platforms: iOS pins the same pair in `LibraryTests`."""
    saturday = library._week_start("2026-08-01")
    sunday = library._week_start("2026-08-02")
    monday = library._week_start("2026-08-03")
    assert saturday == sunday
    assert saturday != monday


def test_weeks_are_zero_filled_between_the_first_session_and_the_last():
    entries = [entry("a", "2026-08-01", 1000.0),                  # week of 27 Jul
               entry("b", "2026-08-02", 2000.0),                  # same week (a Sunday)
               entry("c", "2026-08-24", 3000.0, durationS=7200.0)]  # week of 24 Aug
    weeks = library.aggregate(entries)["trends"]["weeks"]
    assert [w["weekStart"] for w in weeks] == ["2026-07-27", "2026-08-03",
                                               "2026-08-10", "2026-08-17", "2026-08-24"]
    assert [w["count"] for w in weeks] == [2, 0, 0, 0, 1]
    assert [w["hours"] for w in weeks] == [2.0, 0.0, 0.0, 0.0, 2.0]


def test_weeks_bucket_on_the_riders_own_day_not_on_utc():
    """A Sunday-evening session in Torbole is a Sunday-*UTC* session two months of the
    year and a Saturday-UTC one the rest of the time. The bucket follows the rider."""
    late = entry("late", "2026-08-02", 1000.0)
    late["startUtc"] = "2026-08-02T22:40:00Z"
    late["dateUtc"] = "2026-08-02"                # Sunday in UTC
    late["dateLocal"] = "2026-08-03"              # Monday where he was
    weeks = library.aggregate([late])["trends"]["weeks"]
    assert [w["weekStart"] for w in weeks] == ["2026-08-03"]


def test_a_digest_with_no_usable_date_is_left_out_of_the_weeks():
    dated = entry("dated", "2026-08-03", 1000.0)
    undated = entry("undated", "2026-08-04", 2000.0, dateLocal=None, dateUtc=None)
    weeks = library.aggregate([dated, undated])["trends"]["weeks"]
    assert [(w["weekStart"], w["count"]) for w in weeks] == [("2026-08-03", 1)]
    assert library.aggregate([undated])["trends"]["weeks"] == []


# ----------------------------------------------------------------- the new trend series


def test_the_clean_jibe_series_are_per_session_and_hole_tolerant():
    good = entry("good", "2026-08-03", 1000.0, turns={"jibesSuccessful": 5})
    old = entry("old", "2026-08-10", 2000.0)
    old["turns"] = {k: v for k, v in old["turns"].items() if k != "jibesSuccessful"}
    charts = {c["key"]: c for c in library.aggregate([good, old])["trends"]["charts"]}
    assert [c for c in charts] == ["foilPct", "longestFlight", "turnSuccess", "cleanJibes",
                                   "cph", "pumps", "turnSide"]
    assert [p["v"] for p in charts["cleanJibes"]["lines"][0]["points"]] == [5.0, None]
    assert [p["v"] for p in charts["cph"]["lines"][0]["points"]] == [5.0, None]
