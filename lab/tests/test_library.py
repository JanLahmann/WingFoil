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
    # The engine's rate (schema 6), consistent with whatever the overrides left behind —
    # a real digest is a projection of one analysis, so its rate and its counts agree.
    # An explicit `cleanJibesPerHour=` override wins, which is how the "the stored rate is
    # the answer" half of `_cph` gets tested.
    if "cleanJibesPerHour" not in overrides:
        clean, duration = e["turns"].get("jibesSuccessful"), e["durationS"]
        e["cleanJibesPerHour"] = (None if clean is None or not duration
                                  else clean * 3600.0 / duration)
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
    # Schema 6's rate is that same clean count over the hour, so a row that predates the
    # count predates the rate too — the fallback in `_cph` has nothing to divide either.
    old.pop("cleanJibesPerHour")
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


def test_cph_is_the_engines_own_rate_where_the_digest_carries_it():
    """CPH is `summary.cleanJibesPerHour` (engine 0.10.0, schema 6), copied and not
    re-derived — a metric with an engine field must have exactly one owner.

    The stored rate wins even where the counts would divide to something else: the digest
    is a projection of one analysis, and if the two ever disagreed it is the analysis that
    is right about what it measured.
    """
    half = entry("half", "2026-08-03", 1000.0, durationS=1800.0, cleanJibesPerHour=12.0,
                 turns={"jibes": 9, "jibesSuccessful": 6})
    assert records_of([half])["bestCph"]["value"] == 12.0
    stated = entry("stated", "2026-08-03", 1000.0, cleanJibesPerHour=7.5)
    assert records_of([stated])["bestCph"]["value"] == 7.5


def test_a_pre_schema_6_row_still_divides_for_its_cph():
    """The fallback, and the whole reason it stays: a library saved before the engine
    published the rate is still the rider's library, and its afternoons still hold
    records. Same arithmetic — clean jibes over elapsed hours — in the one place that is
    allowed to do it."""
    half = entry("half", "2026-08-03", 1000.0, durationS=1800.0,
                 turns={"jibes": 9, "jibesSuccessful": 6})
    half.pop("cleanJibesPerHour", None)
    assert records_of([half])["bestCph"]["value"] == 12.0
    zero = entry("zero", "2026-08-03", 1000.0, durationS=0.0)
    zero.pop("cleanJibesPerHour", None)
    assert "bestCph" not in records_of([zero])
    # A measured 0.0 is a value, not an absence: it must not fall through to the division
    # and arrive at the same number by a route that means something else.
    none = entry("none", "2026-08-03", 1000.0, cleanJibesPerHour=0.0,
                 turns={"jibes": 9, "jibesSuccessful": 6})
    assert library._cph(none) == 0.0


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
    # A row saved before schema 5: no clean count, and therefore — since the rate is the
    # count over the hour — no rate either. Both holes, not two zeroes.
    old["turns"] = {k: v for k, v in old["turns"].items() if k != "jibesSuccessful"}
    old.pop("cleanJibesPerHour")
    charts = {c["key"]: c for c in library.aggregate([good, old])["trends"]["charts"]}
    assert [c for c in charts] == ["foilPct", "longestFlight", "turnSuccess", "cleanJibes",
                                   "cph", "pumps", "turnSide"]
    assert [p["v"] for p in charts["cleanJibes"]["lines"][0]["points"]] == [5.0, None]
    assert [p["v"] for p in charts["cph"]["lines"][0]["points"]] == [5.0, None]


# ------------------------------------------------------------------------- periods
#
# Four ways of naming a set of afternoons, one aggregate block. These are the *rules* —
# the boundary cases, written down as arithmetic somebody can check by eye. The
# platform-to-platform contract is a file instead (`fixtures/periods/periods.expected.json`,
# generated from `library` and asserted by both apps), because two hand-written suites
# agreeing today is not two implementations that cannot drift.


def at(ident: str, day: str, spot: str, lat: float | None = 45.876,
       lon: float | None = 10.871, **overrides) -> dict:
    """A session on a day, at a place. The epoch is derived from the day so `_sorted`
    keeps the reading order, which is what every "oldest first" rule below depends on."""
    epoch = library._epoch(f"{day}T08:00:00Z")
    geo = None if lat is None else {"lat": lat, "lon": lon}
    return entry(ident, day, epoch, spot=spot, geo=geo,
                 rateDurationS=overrides.pop("rateDurationS", 3600.0), **overrides)


def test_a_trip_is_one_place_and_no_gap_wider_than_three_days():
    """Three days is still the same holiday — a trip has blown-out days in it. Four days
    apart is a second visit."""
    ds = [at("a", "2026-07-31", "Garda"), at("b", "2026-08-03", "Garda"),
          at("c", "2026-08-07", "Garda"), at("d", "2026-08-08", "Garda")]
    trips = library.periods(ds)["trips"]
    assert [t["sessionIds"] for t in trips] == [["c", "d"], ["a", "b"]]
    assert [t["title"] for t in trips] == ["Garda · 7 Aug – 8 Aug",
                                           "Garda · 31 Jul – 3 Aug"]


def test_one_afternoon_somewhere_is_not_a_trip():
    ds = [at("solo", "2026-06-13", "Rheinstetten", lat=48.97, lon=8.32),
          at("a", "2026-07-31", "Garda"), at("b", "2026-08-01", "Garda")]
    assert [t["sessionIds"] for t in library.periods(ds)["trips"]] == [["a", "b"]]


def test_trips_cluster_on_coordinates_not_on_the_filenames_spelling():
    """The corpus spells one beach three ways — `nago-torbole-windsurfen`, `-foilmotion`,
    `-wingfoiling` — because the spot is derived from the filename. A trip detected on the
    name alone would split one week at Garda into three holidays."""
    ds = [at("a", "2026-07-31", "Nago Torbole Windsurfen"),
          at("b", "2026-08-01", "Nago Torbole Foilmotion", lat=45.8765, lon=10.8715),
          at("c", "2026-08-02", "Nago Torbole Wingfoiling", lat=45.8755, lon=10.8705)]
    trips = library.periods(ds)["trips"]
    assert len(trips) == 1
    assert trips[0]["sessionIds"] == ["a", "b", "c"]
    # The heading takes the name most of the afternoons carry; ties go to the earliest.
    assert trips[0]["spot"] == "Nago Torbole Windsurfen"


def test_two_beaches_on_one_lake_are_two_places():
    """3 km, deliberately looser than the phone's 500 m and still far tighter than a lake:
    Torbole and Malcesine are one week at Garda and two different spots."""
    ds = [at("a", "2026-07-31", "Torbole"), at("b", "2026-08-01", "Torbole"),
          at("c", "2026-07-31", "Malcesine", lat=45.765, lon=10.810),
          at("d", "2026-08-01", "Malcesine", lat=45.765, lon=10.810)]
    trips = library.periods(ds)["trips"]
    assert sorted(t["spot"] for t in trips) == ["Malcesine", "Torbole"]


def test_a_session_with_no_anchor_is_placed_by_the_name_it_already_carries():
    """A library saved before schema 7 has no coordinates at all, and must still produce
    trips: the filename's guess is the only thing those rows have."""
    ds = [at("a", "2026-07-31", "Garda"), at("b", "2026-08-01", "Garda", lat=None, lon=None)]
    trips = library.periods(ds)["trips"]
    assert [t["sessionIds"] for t in trips] == [["a", "b"]]


def test_months_are_cut_on_the_riders_own_calendar_day():
    """22:30 UTC on 31 August at +02:00 is 1 September where the rider was standing, and
    a month bucketed on the UTC instant would file it under the month before it happened."""
    late = entry("late", "2026-08-31", library._epoch("2026-08-31T22:30:00Z"),
                 dateLocal="2026-09-01", spot="Garda")
    early = entry("early", "2026-08-30", library._epoch("2026-08-30T10:00:00Z"),
                  dateLocal="2026-08-30", spot="Garda")
    months = library.periods([early, late])["months"]
    assert [(m["key"], m["sessionIds"]) for m in months] \
        == [("2026-09", ["late"]), ("2026-08", ["early"])]


def test_the_season_runs_from_april_and_is_named_for_the_year_it_opened():
    """1 April → 31 March, the cut the Trends range picker has always used. A February
    afternoon belongs to the winter that started the previous April."""
    ds = [at("spring", "2026-04-01", "Garda"), at("winter", "2027-02-14", "Garda"),
          at("next", "2027-04-01", "Garda")]
    seasons = library.periods(ds)["seasons"]
    assert [(s["key"], s["title"], s["sessionIds"]) for s in seasons] == [
        ("2027", "Season 2027", ["next"]),
        ("2026", "Season 2026/27", ["spring", "winter"]),
    ]
    # March belongs to the season that opened the April before it, not to its own year.
    march = library.periods([at("march", "2027-03-31", "Garda")])["seasons"]
    assert [(s["key"], s["title"]) for s in march] == [("2026", "Season 2026/27")]


def test_a_season_that_has_not_crossed_a_year_is_just_the_year():
    ds = [at("a", "2026-05-01", "Garda"), at("b", "2026-09-01", "Garda")]
    assert library.periods(ds)["seasons"][0]["title"] == "Season 2026"


# ----------------------------------------------------------------- the aggregate block


def block_of(ds: list) -> dict:
    return {e["key"]: e["value"] for e in library.period_block(ds, spots=1)}


def test_the_block_is_the_one_list_in_the_one_order():
    keys = [k for k, _l, _f in library.PERIOD_BLOCK]
    assert keys == ["sessions", "hours", "distance", "flights", "foilPct", "cleanJibes",
                    "cph", "turns", "cleanJibeRate", "wph", "best2s", "best10s",
                    "longestFlight", "longestDryStreak", "spots"]
    # A preset may only ever drop an entry, so `lean` cannot name one the block lacks.
    assert set(library.PERIOD_LEAN_KEYS) <= set(keys)


def test_a_rate_over_a_period_divides_summed_by_summed():
    """Ten minutes with one clean jibe and three hours with three is not "6.0 and 1.0, so
    3.5 an hour" — it is four clean jibes in three hours and ten minutes."""
    short = at("short", "2026-08-01", "Garda", rateDurationS=600.0,
               turns={"jibes": 6, "jibesSuccessful": 1})
    long = at("long", "2026-08-02", "Garda", rateDurationS=10800.0,
              turns={"jibes": 12, "jibesSuccessful": 3})
    got = block_of([short, long])
    assert got["hours"] == "3.2 h"                       # 11400 s
    assert got["cleanJibes"] == "4"
    assert got["cph"] == "1.3"                           # 4 / (11400/3600) = 1.263
    # …and emphatically not the mean of the two sessions' own rates.
    assert got["cph"] != "3.5"


def test_the_period_divides_by_the_engines_own_span_so_one_session_agrees_with_itself():
    """`rateDurationS` is the denominator every session rate already uses; `durationS` is
    the FIT's elapsed time and is a third longer on one afternoon in the corpus. A month
    holding one session must report that session's CPH, not a second opinion about it."""
    one = at("one", "2026-08-01", "Garda", rateDurationS=3600.0, durationS=5400.0,
             turns={"jibes": 8, "jibesSuccessful": 5})
    assert block_of([one])["cph"] == "5.0"
    # A row saved before schema 7 has only the elapsed time, and that is what it divides by.
    old = dict(one)
    old.pop("rateDurationS")
    assert block_of([old])["cph"] == "3.3"


def test_on_foil_share_is_weighted_by_time_on_the_water():
    """Total foil time over total on-water time — not the mean of the percentages, which
    would let a ten-minute session swing the number as hard as a two-hour one."""
    big = at("big", "2026-08-01", "Garda", foilTimeS=3600.0, foilPct=50.0)
    small = at("small", "2026-08-02", "Garda", foilTimeS=90.0, foilPct=10.0)
    # 3690 s of foil over 7200 + 900 s on the water.
    assert block_of([big, small])["foilPct"] == "45.6 %"


def test_the_clean_jibe_rate_keeps_its_floor_over_the_periods_own_total():
    thin = at("thin", "2026-08-01", "Garda", turns={"jibes": 4, "jibesSuccessful": 4})
    assert "cleanJibeRate" not in block_of([thin])
    second = at("second", "2026-08-02", "Garda", turns={"jibes": 4, "jibesSuccessful": 1})
    # Eight jibes between them clear the floor neither afternoon could clear alone.
    assert block_of([thin, second])["cleanJibeRate"] == "62.5 %"


def test_a_fact_no_session_can_supply_is_dropped_and_never_zeroed():
    """The block's own half of "absent is never 0": a period whose rows all predate a
    field has no answer, and an entry that is not there cannot be misread as a verdict."""
    bare = at("bare", "2026-08-01", "Garda", wetExits=None,
              turns={"jibes": 8, "jibesSuccessful": 5, "longestDryStreak": None})
    got = block_of([bare])
    assert "wph" not in got and "longestDryStreak" not in got
    # A measured zero is still a value.
    dry = at("dry", "2026-08-01", "Garda", wetExits=0)
    assert block_of([dry])["wph"] == "0.0"


def test_the_custom_range_is_inclusive_at_both_ends():
    ds = [at("a", "2026-08-01", "Garda"), at("b", "2026-08-04", "Garda"),
          at("c", "2026-08-09", "Garda")]
    assert library.custom_period(ds, "2026-08-01", "2026-08-04")["sessionIds"] == ["a", "b"]
    assert library.custom_period(ds, None, "2026-08-04")["sessionIds"] == ["a", "b"]
    assert library.custom_period(ds, "2026-08-04", None)["sessionIds"] == ["b", "c"]
    empty = library.custom_period(ds, "2026-09-01", "2026-09-30")
    assert empty["sessionIds"] == []
    # An empty range still has a session count and a spot count — both measured zeroes.
    assert [e["key"] for e in empty["block"]] == ["sessions", "spots"]


def test_a_friends_afternoon_is_in_nobodys_holiday():
    """`counts_towards_records` is the one rule, applied here as it is in `aggregate` —
    a trip built out of a borrowed session would be a holiday somebody else had."""
    mine = at("mine", "2026-08-01", "Garda")
    theirs = at("theirs", "2026-08-02", "Garda", rider="Max")
    demo = at("demo", "2026-08-03", "Garda", example=True)
    ps = library.periods([mine, theirs, demo])
    assert ps["trips"] == []
    assert ps["months"][0]["sessionIds"] == ["mine"]
