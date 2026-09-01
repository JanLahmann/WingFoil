"""Golden-file writer/loader — the cross-implementation contract (docs/testing.md).

Field names are camelCase verbatim. The lab is the authoritative reference: every number
here is re-derived by `ios/WingFoilKit` from the same original FIT and asserted against
this file (`GoldenTests`), so anything added here becomes a parity obligation.

Engine 0.2.0 fills the phases the 0.1.0 schema left as documented empties — `turns`,
`wind`, `takeoffs` — and adds `flightEnds` (docs/algorithms.md "Flight-end outcome", a
phase-2/3 output the original schema predates). Source capabilities still degrade the
same way the modules do: no accel ⇒ `pumps`/stroke counts null, no barometer ⇒ no
submersion evidence, Smart-Recording truncation ⇒ `unknown` outcomes excluded from tallies.

Engine 0.3.0 adds `pumpEpisodes`. `takeoff.py` has classified every pumping effort since
0.2.0, but only the *tallies* of that classification reached the file, so the failed
attempts existed as a number and nowhere else — a consumer could say "14 of them" and not
say *when*, which is exactly what a map needs. The episodes are now serialized whole, in
detection order, every outcome: presentation decides what to draw, the schema carries the
evidence. Adding the key moves no pre-existing number, but it is still a schema change and
`ENGINE_VERSION` is what tells a stored analysis to re-derive itself.

Engine 0.4.0 adds `summary.turns.longestDryStreak` / `longestFlewStreak`. Same kind of
change again — nothing pre-existing moved — but the absence of a streak is not the same
statement as a streak of 0, and only the version bump keeps a 0.3.0 document from being
read as the latter.

Engine 0.5.0 adds the **default-turn-type prior** (docs/algorithms.md "Default turn type"):
`config.windDefaultTurnType` / `windTurnPriorWeight`, and the evidence trail it leaves on
the wind object (`turnTypeMargin`, `turnTypeDirDeg`, `turnTypeVotes`, `priorFlipped`).
Unlike the three bumps above this one *can* move pre-existing numbers — a session whose
no-go cones nearly tie can now have its wind direction resolved the other way, taking every
tack/jibe label with it — which is exactly why a stored document must re-derive rather than
be read as if the rider had never declared a habit. On the current corpus nothing moves:
every fixture's cone margin is already decisive, so the prior is never consulted.

Engine 0.6.0 adds the **session rate metrics** (docs/algorithms.md "Session rates"):
`summary.durationS` / `avgSpeedKmh` / `turnsPerHour` / `jibesPerHour` / `wetPerHour`. Nothing
pre-existing moves — they are arithmetic over numbers the summary already carried — but a
0.5.0 document cannot answer "how busy was that hour" at all, and a missing rate read as 0
would claim a session with no jibes in it. The denominator is elapsed session time, not
foiling time, so every one of them is a rate *per hour on the water*.

Engine 0.7.0 reworks that block twice over (docs/algorithms.md "Session rates"). First,
`jibesPerHour` counts **dry** jibes only — `turns.jibes - turns.jibeOutcomes.fellIn` — so the
number a rider reads as the measure of his afternoon stops counting the jibes he swam out of;
this *moves* a pre-existing value on every fixture with a fallen jibe in it, which is exactly
what the version bump is for. Second, `summary.windowRates` adds the rolling-window view of
the same two events (`config.windowRateMin`, 15 min): a session average over two hours cannot
say *when* the rider was going well, and the busiest quarter of an hour is the part he
remembers. Its peak is measured over full windows only — a three-minute burst scaled to the
hour is a lie, and this file does not tell it.

Engine 0.8.0 fixes `summary.takeoff.totalPumpStrokes` (docs/algorithms.md "The session
total"). It was the one pump metric that skipped `pumpMinStrokes`, so it reported the raw
output of the peak picker -- and chop, measured, runs at pumping cadence and clears
`pumpStrokeAmp` at its crests, so a flight contributed roughly one "stroke" per chop crest.
On the bundled 2026-08-30 example it read 286 against a hand count of about 26. It now counts
a stroke only inside a qualifying burst whose tallest peak reaches `pumpBurstPeakG` (0.8 g,
**provisional**) and whose speed clears `pumpMinSpeedKmh`, and the config echo gains both.
286 -> 31, 3091 -> 701, 1341 -> 395; every other field on every fixture is unchanged, and the
twelve accel-less goldens keep their null.

Engine 0.8.1 finishes that job on `takeoffs[].inFlightStrokes` (docs/algorithms.md "In-flight
strokes"). 0.8.0 left it on the burst-length rule alone, so the bundled example reported a
total of 31 beside an in-flight 60 -- a part larger than its whole, on the very count the
chop hurts most. It now takes the same `pumpBurstPeakG` gate (not the speed one: the window
is a flight, so the test could never fire). 60 -> 5, 293 -> 127, 430 -> 153, and
`summary.takeoff.inFlightPumpStrokes` follows; nothing else on any fixture moves.

Engine 0.9.0 opens the door to **GPX** (`gpx.py`, docs/plan.md's input class (c)). No field
is added, no rule is changed and no number on any existing fixture moves — the whole of the
change is that a second kind of file can now reach this writer, and that it arrives honestly
labelled: `capabilities.hasDoppler` is **false** for a GPX because its speed is
differentiated from positions rather than measured, which is the flag every surface reads
to mark those speed records *uncertified*. `pumps`/`takeoffPumps`/`pumpEpisodes` degrade to
their accel-less nulls and empties exactly as the twelve accel-less FIT goldens already do.
`ENGINE_VERSION` bumps because a stored 0.8.2 document was written by an engine that could
not have produced this one, and because that is the signal the apps re-derive on.

Engine 0.9.1 changes no number either. It adds one field *outside* the golden —
`RawTrack.start_utc_offset_source`, surfaced as `meta.utcOffsetSource` (docs/presentation.md
"Session time") — which records **which rung** of the UTC-offset ladder answered. The ladder
itself is unchanged; what was missing was the qualification, and without it a page printed
"times as recorded on the water" over an offset that was a solar guess from longitude, an
hour out under DST. That is a claim about the data, so it is engine-side, and a stored
document written before it cannot say which rung it used — which is why the version moves
and every golden is rewritten with the new stamp and identical numbers.

Engine 0.9.2 measures the **swim** (docs/algorithms.md "Swim distance"). Every `fell_in`
flight end has always known the rider got wet and never how far he then had to travel, and
the one number that was there to be read -- `offFoilS` -- is cut at the 60 s judging window,
which is right for a verdict and wrong for a swim. `flightEnds[]` gains `swimM` with the
window it was measured over (`swimStartTs`/`swimEndTs`), null on every outcome that is not a
swim; `summary` gains `swimDistanceM`, `longestSwimM` and that swim's window. The run is
walked **uncapped** -- until the rider is flying again or the recording stops -- which is the
end-of-session case the cap could not see at all: on 2026-09-01 pm the last swim read 48 m of
1847. No pre-existing number moves on any fixture, but the ends now carry a measurement they
did not, and a 0.9.1 document has no honest way to answer for it -- `null` there means "not a
swim", and a reader that took a missing key for the same thing would read every swim in the
corpus as dry."""

from __future__ import annotations

import json
import math
from dataclasses import dataclass, field
from pathlib import Path

from . import ENGINE_VERSION, gp3s
from .evidence import OffFoilEvidence, off_foil_evidence
from .filters import CleanTrack, FilterConfig, clean
from .flight import FlightConfig, FlightResult, segment_flights
from .flightend import (FlightEnd, FlightEndConfig, FlightEndSummary, OutcomeSplit,
                        classify_flight_ends, split_outcomes, summarize_flight_ends)
from .gp3s import GP3SRecords, RecordWindow
from .hrcost import (Coverage, FatigueBin, HrAnalysis, HrConfig, HrEvent, HrSummary,
                     PumpCruiseHr, analyze_hr)
from .parse import RawTrack, parse_track
from .pump import PumpConfig, PumpTrack, pump_track
from .takeoff import (PumpEpisode, Takeoff, TakeoffAnalysis, TakeoffConfig, TakeoffSummary,
                      analyze_takeoffs, summarize_takeoffs)
from .turns import (FELL_IN, JIBE, OutcomeCounts, Turn, TurnConfig, TurnSummary, detect_turns,
                    summarize_turns)
from .wind import WindConfig, WindEstimate, estimate_wind


@dataclass
class RateConfig:
    """Session-rate parameters (docs/algorithms.md "Session rates").

    One knob: the rolling window the per-hour series is measured over. 15 minutes is long
    enough that a single jibe cannot dominate it and short enough to separate the hour the
    wind filled in from the hour it did not.
    """

    window_rate_min: float = 15.0
    #: Spacing of the emitted series. Not a tuning knob -- it is how *finely* the same
    #: function is sampled for the file, and a minute keeps a two-hour session's series
    #: reviewable. The peak below is never read off this grid.
    grid_s: float = 60.0


@dataclass
class Analysis:
    track: RawTrack
    clean: CleanTrack
    flights: FlightResult
    records: GP3SRecords
    filter_config: FilterConfig
    flight_config: FlightConfig
    wind: WindEstimate
    turns: list[Turn]
    turn_summary: TurnSummary
    flight_ends: list[FlightEnd]
    flight_end_summary: FlightEndSummary
    outcome_split: OutcomeSplit
    takeoffs: TakeoffAnalysis
    takeoff_summary: TakeoffSummary
    pump: PumpTrack | None
    hr: HrAnalysis
    wind_config: WindConfig
    turn_config: TurnConfig
    flight_end_config: FlightEndConfig
    pump_config: PumpConfig
    takeoff_config: TakeoffConfig
    hr_config: HrConfig
    rate_config: RateConfig


def analyze(path: str | Path, filter_config: FilterConfig | None = None,
            flight_config: FlightConfig | None = None,
            wind_config: WindConfig | None = None,
            turn_config: TurnConfig | None = None,
            flight_end_config: FlightEndConfig | None = None,
            pump_config: PumpConfig | None = None,
            takeoff_config: TakeoffConfig | None = None,
            hr_config: HrConfig | None = None,
            rate_config: RateConfig | None = None) -> Analysis:
    """Full pipeline: parse -> clean -> flights -> records -> wind -> turns -> ends ->
    takeoffs -> HR cost."""
    fcfg = filter_config or FilterConfig()
    flcfg = flight_config or FlightConfig()
    wcfg = wind_config or WindConfig()
    tcfg = turn_config or TurnConfig()
    fecfg = flight_end_config or FlightEndConfig()
    pcfg = pump_config or PumpConfig()
    tocfg = takeoff_config or TakeoffConfig()
    hcfg = hr_config or HrConfig()
    rcfg = rate_config or RateConfig()

    track = parse_track(path)
    ct = clean(track, fcfg)
    fr = segment_flights(ct, flcfg)
    rec = gp3s.records(ct)
    # `tcfg` because the default-turn-type prior (docs/algorithms.md "Default turn type")
    # votes on the very sweeps `detect_turns` is about to report -- one turn config, or the
    # prior and the session would be talking about different turns.
    wind = estimate_wind(ct, fr, wcfg, tcfg)
    pt = pump_track(track, pcfg)

    # One off-foil evidence object for the whole session: turns, flight ends and takeoffs
    # all read the same three channels (evidence.py) and none of them mutate it. It is
    # shared only with the consumers whose thresholds match the ones it was built with --
    # the defaults are deliberately identical, but a caller may move one config alone.
    ev = off_foil_evidence(ct, fr, tcfg.foil_exit_speed_kmh, tcfg.baro_drop_m)

    def shared(exit_kmh: float, drop_m: float) -> OffFoilEvidence | None:
        same = exit_kmh == tcfg.foil_exit_speed_kmh and drop_m == tcfg.baro_drop_m
        return ev if same else None

    turns = detect_turns(ct, fr, wind, tcfg, pt, evidence=ev)
    ends = classify_flight_ends(ct, fr, turns, fecfg, pt,
                                evidence=shared(fecfg.foil_exit_speed_kmh, fecfg.baro_drop_m))
    takeoffs = analyze_takeoffs(ct, fr, turns, tocfg, pt,
                                evidence=shared(tocfg.foil_exit_speed_kmh, tocfg.baro_drop_m))

    # HR is the one channel read from the *raw* records rather than the cleaned track, and
    # it joins to three earlier phases at once (runs, ends, turns) -- so it runs last.
    hr = analyze_hr(track, fr, takeoffs, ends, pt, turns, hcfg)

    # `ends` because the streaks span both channels: a straight-line swim ends a run of
    # clean turns too (docs/algorithms.md "Turn streaks").
    turn_summary = summarize_turns(turns, ends)
    end_summary = summarize_flight_ends(ends)
    return Analysis(
        track=track, clean=ct, flights=fr, records=rec,
        filter_config=fcfg, flight_config=flcfg,
        wind=wind, turns=turns, turn_summary=turn_summary,
        flight_ends=ends, flight_end_summary=end_summary,
        outcome_split=split_outcomes(turn_summary, end_summary),
        takeoffs=takeoffs, takeoff_summary=summarize_takeoffs(takeoffs), pump=pt, hr=hr,
        wind_config=wcfg, turn_config=tcfg, flight_end_config=fecfg,
        pump_config=pcfg, takeoff_config=tocfg, hr_config=hcfg, rate_config=rcfg,
    )


@dataclass
class SessionRates:
    """Session basics and the per-hour rates (docs/algorithms.md "Session rates").

    All four rates share one denominator -- **elapsed** session time, first to last cleaned
    sample -- so they answer "per hour on the water", not "per hour of flight". A rider who
    jibes forty times in two hours of drifting and a rider who does it in one are not having
    the same session, and only a wall-clock denominator says so.

    Every rate is `None` rather than 0.0 when the session has no duration to divide by: a
    one-sample track has no answer, and a zero would read as "he did nothing".
    """

    duration_s: float = 0.0
    avg_speed_kmh: float | None = None
    turns_per_hour: float | None = None
    #: **Dry** jibes per hour: the ones he came out of still sailing. See `session_rates`.
    jibes_per_hour: float | None = None
    wet_per_hour: float | None = None


@dataclass
class WindowRate:
    """One evaluation of the rolling window: its start, and the two rates over it."""

    start_t: float
    jph: float
    wph: float


@dataclass
class WindowRates:
    """The rolling-window rate series and its two peaks (docs/algorithms.md "Session rates").

    `best_jph` / `best_wph` are the **true** sliding maxima, not the largest value in
    `series`: the count in a window can only be highest when the window opens on an event,
    so the peak search is anchored on the events and the series is a coarse sampling of the
    same function. `best_* >= max(series)` therefore always holds, and usually strictly.

    Every number here is measured over a **full** window. A session shorter than one window
    gets a single point over its actual elapsed span instead — an honest whole-session rate —
    and never a partial window scaled up to the hour, which is how three good minutes turn
    into a peak the rider never sailed.
    """

    window_min: float
    best_jph: float | None = None
    best_jph_start_t: float | None = None
    best_wph: float | None = None
    best_wph_start_t: float | None = None
    series: list[WindowRate] = field(default_factory=list)


def session_duration_s(ct: CleanTrack) -> float:
    """Elapsed wall-clock span of the cleaned track (s): last sample - first sample.

    The *cleaned* track, because that is the timeline every other number in the summary was
    measured on. It includes gaps -- a recording paused mid-session still spent that time on
    the water -- which is what separates it from `timer_time_s`, the foil-% denominator.
    """
    t = ct.records["t"]
    return 0.0 if len(t) < 2 else float(t.iloc[-1] - t.iloc[0])


def session_start_t(ct: CleanTrack) -> float:
    """First sample of the cleaned track -- where the session's clock starts, and therefore
    where the first rolling window opens."""
    t = ct.records["t"]
    return 0.0 if len(t) == 0 else float(t.iloc[0])


def session_rates(duration_s: float, distance_m: float, turns_counted: int, dry_jibes: int,
                  fell_in: int) -> SessionRates:
    """The rate block.

    `dry_jibes` is the jibes he came out of **still sailing** -- `jibes - jibeOutcomes.
    fellIn`, so flew-through and touchdown alike, since pumping straight back up out of a
    touchdown is a jibe he made. A jibe he swam out of is one he did not, and counting it
    would let a rider raise his headline number by falling more often. `turnsPerHour` beside
    it is deliberately still **all** counted turns: that one answers "how busy", which is a
    question about activity and not about quality.

    `fell_in` is **every** fell-in flight end, turn and straight-line alike -- the question
    is how often the rider got wet, and the water does not care whether he was mid-jibe at
    the time.
    """
    if duration_s <= 0:
        return SessionRates(duration_s=max(duration_s, 0.0))
    hours = duration_s / 3600.0
    return SessionRates(
        duration_s=duration_s,
        avg_speed_kmh=distance_m / duration_s * 3.6,
        turns_per_hour=turns_counted / hours,
        jibes_per_hour=dry_jibes / hours,
        wet_per_hour=fell_in / hours,
    )


def _count_in_window(events: list[float], start_t: float, window_s: float) -> int:
    """Events in the half-open window [start, start+window). Half-open so that sliding the
    window by exactly one event's spacing never counts that event twice."""
    return sum(1 for e in events if start_t <= e < start_t + window_s)


def _peak_rate(events: list[float], start_t: float, duration_s: float,
               window_s: float) -> tuple[float | None, float | None]:
    """(peak per-hour rate, the window start that achieved it) over **full** windows only.

    The count in `[s, s+W)` is a step function of `s` that can only reach a local maximum
    where the window opens exactly on an event, so those instants (plus the two ends of the
    allowed range, which is where a maximum can be clipped) are the whole candidate set --
    this is the true sliding maximum, not a sampled one.

    A session shorter than one window has no full window to search: its peak is its own
    whole-session rate over the span it actually lasted. Scaling a partial window up to the
    hour would be the flattering lie the rest of this file exists to avoid.
    """
    if duration_s <= 0:
        return None, None
    if duration_s < window_s:
        return len(events) / (duration_s / 3600.0), start_t
    last_start = start_t + duration_s - window_s
    candidates = sorted({start_t, last_start,
                         *(e for e in events if start_t <= e <= last_start)})
    best_n, best_start = -1, start_t
    for s in candidates:
        n = _count_in_window(events, s, window_s)
        if n > best_n:                      # ties keep the earliest window
            best_n, best_start = n, s
    return best_n / (window_s / 3600.0), best_start


def window_rates(dry_jibe_ts: list[float], wet_ts: list[float], start_t: float,
                 duration_s: float, cfg: RateConfig | None = None) -> WindowRates:
    """The rolling-window block: a `cfg.grid_s` series plus the two exact peaks.

    Both channels are the *same* events the session rates count, timestamped where the
    goldens already timestamp them -- a dry jibe at its turn's `ts`, a swim at its flight
    end's `ts` -- so a reader can find every event in the window by looking it up in the
    lists above.
    """
    cfg = cfg or RateConfig()
    window_s = cfg.window_rate_min * 60.0
    out = WindowRates(window_min=cfg.window_rate_min)
    if duration_s <= 0 or window_s <= 0:
        return out
    out.best_jph, out.best_jph_start_t = _peak_rate(dry_jibe_ts, start_t, duration_s, window_s)
    out.best_wph, out.best_wph_start_t = _peak_rate(wet_ts, start_t, duration_s, window_s)

    if duration_s < window_s:
        # One point over the span the session actually lasted: the series says what the
        # rates were, and says it once, rather than pretending to a window that never closed.
        hours = duration_s / 3600.0
        out.series = [WindowRate(start_t, len(dry_jibe_ts) / hours, len(wet_ts) / hours)]
        return out

    hours = window_s / 3600.0
    steps = int(math.floor((duration_s - window_s) / cfg.grid_s + 1e-9))
    out.series = [
        WindowRate(start_t + k * cfg.grid_s,
                   _count_in_window(dry_jibe_ts, start_t + k * cfg.grid_s, window_s) / hours,
                   _count_in_window(wet_ts, start_t + k * cfg.grid_s, window_s) / hours)
        for k in range(steps + 1)
    ]
    return out


def dry_jibe_times(turns: list[Turn]) -> list[float]:
    """When each **dry** jibe happened, in time order: a counted jibe he did not swim out
    of, at the turn's own `ts` (its start). The list's length is the `jibesPerHour`
    numerator -- one definition, spelled once."""
    return [t.start_t for t in turns
            if t.counted and t.kind == JIBE and t.outcome != FELL_IN]


def wet_times(ends: list[FlightEnd]) -> list[float]:
    """When each swim happened: every fell-in flight end, at the end's own `ts`."""
    return [e.t for e in ends if e.outcome == FELL_IN]


def build_golden(a: Analysis) -> dict:
    caps = a.track.capabilities
    fr, rec = a.flights, a.records
    longest_s = fr.longest.duration_s if fr.longest else 0.0
    longest_m = max((f.dist_m for f in fr.flights), default=0.0)
    dry_ts, wet_ts = dry_jibe_times(a.turns), wet_times(a.flight_ends)
    duration_s = session_duration_s(a.clean)
    rates = session_rates(duration_s, rec.distance_m, a.turn_summary.turns_counted,
                          len(dry_ts), a.flight_end_summary.all_ends.fell_in)
    windows = window_rates(dry_ts, wet_ts, session_start_t(a.clean), duration_s,
                           a.rate_config)
    pumps = {k.flight_index: k.pumps_to_takeoff for k in a.takeoffs.takeoffs}
    swims = a.flight_end_summary.swim
    return {
        "engineVersion": ENGINE_VERSION,
        "config": _config_dict(a),
        "capabilities": {
            "hasDoppler": bool(caps.has_speed),
            "hasDevFields": bool(caps.has_dev_fields),
            "hasWatchLaps": bool(caps.has_watch_laps),
            "hasAccel": bool(caps.has_accel),
            "hasHR": bool(caps.has_hr),
            "sampleRateHz": caps.sample_rate_hz,
        },
        "flights": [
            {"startTs": round(f.start_t, 2), "endTs": round(f.end_t, 2),
             "distM": round(f.dist_m, 1), "maxKn": round(f.max_kn, 3),
             "takeoffPumps": pumps.get(i)}
            for i, f in enumerate(fr.flights)
        ],
        "turns": [_turn_json(t) for t in a.turns],
        "flightEnds": [_end_json(e) for e in a.flight_ends],
        "records": {
            "best2sKn": round(rec.best2s_kn, 3),
            "best10sKn": round(rec.best10s_kn, 3),
            "best5x10sKn": round(rec.best5x10s_kn, 3),
            "best100mKn": round(rec.best100m_kn, 3),
            "best250mKn": round(rec.best250m_kn, 3),
            "best500mKn": round(rec.best500m_kn, 3),
            "bestNmKn": round(rec.best_nm_kn, 3),
            "bestHourKn": round(rec.best_hour_kn, 3),
            "alpha500Kn": round(rec.alpha500_kn, 3),
            "windows": {k: _window_json(w) for k, w in rec.windows.items()},
        },
        "wind": _wind_json(a.wind),
        "takeoffs": [_takeoff_json(k) for k in a.takeoffs.takeoffs],
        "pumpEpisodes": [_episode_json(e) for e in a.takeoffs.episodes],
        "hr": _hr_json(a.hr),
        "summary": {
            "foilTimeS": round(fr.foil_time_s, 1),
            "foilPct": round(fr.foil_pct, 2),
            "flightCount": fr.flight_count,
            "longestFlightS": round(longest_s, 1),
            "longestFlightM": round(longest_m, 1),
            "distanceKm": round(rec.distance_m / 1000.0, 3),
            # Session basics and the per-hour rates, all over elapsed session time.
            "durationS": round(rates.duration_s, 1),
            "avgSpeedKmh": _round(rates.avg_speed_kmh, 2),
            "turnsPerHour": _round(rates.turns_per_hour, 1),
            "jibesPerHour": _round(rates.jibes_per_hour, 1),   # DRY jibes (engine 0.7.0)
            "wetPerHour": _round(rates.wet_per_hour, 1),
            # How far the swims came to (engine 0.9.2, docs/algorithms.md "Swim distance").
            # Flat rather than inside `flightEnds`, which is a counts object: these are
            # metres, and a distance filed under a tally reads as one more count.
            "swimDistanceM": round(swims.distance_m, 1),
            "longestSwimM": round(swims.longest_m, 1),
            "longestSwimStartTs": _round(swims.longest_start_t, 2),
            "longestSwimEndTs": _round(swims.longest_end_t, 2),
            "windowRates": _window_rates_json(windows),
            "turns": _turn_summary_json(a.turn_summary),
            "flightEnds": _end_summary_json(a.flight_end_summary),
            "outcomeSplit": _split_json(a.outcome_split),
            "takeoff": _takeoff_summary_json(a.takeoff_summary),
        },
    }


def golden_path(fit_path: str | Path, goldens_dir: str | Path) -> Path:
    """fixtures/goldens/<fixture stem>.expected.json (stems are unique across the corpus)."""
    return Path(goldens_dir) / f"{Path(fit_path).stem}.expected.json"


def write_golden(golden: dict, path: str | Path) -> Path:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(golden, indent=2) + "\n")
    return path


def load_golden(path: str | Path) -> dict:
    return json.loads(Path(path).read_text())


def _config_dict(a: Analysis) -> dict:
    """Params actually used, docs/algorithms.md names (camelCase)."""
    fcfg, flcfg = a.filter_config, a.flight_config
    w, t, p, k = a.wind_config, a.turn_config, a.pump_config, a.takeoff_config
    h, r = a.hr_config, a.rate_config
    return {
        "foilEntrySpeed": flcfg.foil_entry_speed_kmh,
        "entryHold": flcfg.entry_hold_s,
        "foilExitSpeed": flcfg.foil_exit_speed_kmh,
        "exitHold": flcfg.exit_hold_s,
        "minFlightDuration": flcfg.min_flight_duration_s,
        "touchdownMergeGap": flcfg.touchdown_merge_gap_s,
        "maxHdop": fcfg.max_hdop,
        "minSatellites": fcfg.min_satellites,
        "maxAccel1Hz": fcfg.max_accel_1hz,
        "gapMinS": fcfg.gap_min_s,          # gap iff dt > max(gapMinS, gapFactor * median dt)
        "gapFactor": fcfg.gap_factor,
        "speedChannelRecords": "doppler",
        "speedChannelManeuvers": "hybrid",
        "alphaProximity": gp3s.ALPHA_PROXIMITY_M,
        "alphaMaxDistance": gp3s.ALPHA_MAX_DISTANCE_M,
        "alphaCandidatePruneMinPath": gp3s.ALPHA_MIN_PATH_M,
        "alphaCandidatePruneMinCogSpread": gp3s.ALPHA_MIN_COG_SPREAD_DEG,
        "minSpeedFilter": None,
        # turn detection & classification
        "turnMinAngle": t.min_angle_deg,
        "turnMaxDuration": t.max_duration_s,
        "turnPeakRate": t.peak_rate_deg_s,
        "turnContinueRate": t.continue_rate_deg_s,
        "turnCogSpeedFloor": t.min_cog_speed_mps,
        "turnMinArc": t.min_arc_m,
        "turnMinRadius": t.min_radius_m,
        "turnContext": t.context_after_s,
        "entrySpeedWindow": t.entry_speed_window_s,
        "minSpeedLag": t.min_speed_lag_s,
        "turnSuccessPct": t.success_pct,
        # 3-way outcome ladder (shared with the flight ends)
        "turnStopSpeedFloor": t.stop_speed_floor_mps,
        "turnTouchdownMaxStop": t.touchdown_max_stop_s,
        "turnFallStop": t.fall_stop_s,
        "turnOutcomeLookahead": t.outcome_lookahead_s,
        "turnRecoverPct": t.recover_pct,
        "turnRecoverHold": t.recover_hold_s,
        "turnOutcomeWindow": t.outcome_window_s,
        "turnBaroDrop": t.baro_drop_m,
        # wind axis
        "windMinSpeed": w.min_speed_mps,
        "windBinDeg": w.bin_deg,
        "windSmoothDeg": w.smooth_deg,
        "windLobeHalfWidth": w.lobe_half_width_deg,
        "windMinLobeSeparation": w.min_lobe_separation_deg,
        "windMaxLobeSeparation": w.max_lobe_separation_deg,
        "windMinDistance": w.min_distance_m,
        "windMinConfidence": w.min_confidence,
        "windNoGoHalfAngle": w.no_go_half_angle_deg,
        "windMinConeMass": w.min_cone_mass,
        "windFullMargin": w.full_margin,
        "windDefaultTurnType": w.default_turn_type,
        "windTurnPriorWeight": w.turn_prior_weight,
        # pumping
        "pumpBandLo": p.band_lo_hz,
        "pumpBandHi": p.band_hi_hz,
        "pumpResampleHz": p.resample_hz,
        "pumpFilterSpan": p.filter_span_s,
        "pumpStrokeAmp": p.stroke_amp_g,
        "pumpRefractory": p.refractory_s,
        "pumpStrokeMaxInterval": p.stroke_max_interval_s,
        "pumpMinStrokes": p.min_strokes,
        "pumpBurstPeakG": p.burst_peak_g,          # PROVISIONAL (docs/algorithms.md)
        "pumpMinSpeedKmh": p.min_speed_kmh,
        # takeoff
        "takeoffMaxRun": k.max_run_s,
        "takeoffRiseSlack": k.rise_slack_mps,
        "takeoffRestSpeed": k.rest_speed_mps,
        "takeoffAttemptWindow": k.attempt_window_s,
        "takeoffMinPreWindow": k.min_pre_window_s,
        "freeTakeoff": k.free_takeoff_strokes,
        # HR cost
        "hrCostPeakWindow": h.peak_window_s,
        "hrBaselineWindow": h.baseline_window_s,
        "hrMinCoverage": h.min_coverage,
        "hrFlatlineMax": h.flatline_max_s,
        "hrMinBpm": h.min_bpm,
        "hrMaxBpm": h.max_bpm,
        "hrLag": h.lag_s,
        "hrRecoveryWindow": h.recovery_window_s,
        "hrMinRise": h.min_rise_bpm,
        "hrBinMinutes": h.bin_minutes,
        "hrMaxSampleGap": h.max_sample_gap_s,
        # session rates
        "windowRateMin": r.window_rate_min,
    }


def _window_rates_json(w: WindowRates) -> dict:
    """The rolling-window block. The peaks are null -- never 0.0 -- on a session with no
    duration, for the same reason the four rates beside them are: there is no window to
    measure, which is not the same claim as a quarter of an hour in which nothing happened.
    """
    return {
        "windowMin": w.window_min,
        "bestJph": _round(w.best_jph, 1),
        "bestJphStartTs": _round(w.best_jph_start_t, 2),
        "bestWph": _round(w.best_wph, 1),
        "bestWphStartTs": _round(w.best_wph_start_t, 2),
        "series": [{"ts": round(p.start_t, 2), "jph": round(p.jph, 1), "wph": round(p.wph, 1)}
                   for p in w.series],
    }


def _window_json(w: RecordWindow | list[RecordWindow]) -> dict | list[dict]:
    if isinstance(w, list):
        return [_window_json(x) for x in w]
    return {"startTs": round(w.start_t, 2), "durS": round(w.duration_s, 2)}


def _turn_json(t: Turn) -> dict:
    """One detected turn. `ts`/`type`/`entryKn`/`minKn`/`score`/`side` keep the 0.1.0 names."""
    return {
        "ts": round(t.start_t, 2),
        "endTs": round(t.end_t, 2),
        "type": t.kind,
        "counted": bool(t.counted),
        "entryKn": round(t.entry_kn, 3),
        "minKn": round(t.min_kn, 3),
        "score": round(t.score, 4),
        "success": bool(t.success),
        "side": t.side,
        "direction": t.direction,
        "netDeg": round(t.net_deg, 2),
        "arcM": round(t.arc_m, 2),
        "radiusM": round(t.radius_m, 2),
        "outcome": t.outcome,
        "borderline": bool(t.borderline),
        "offFoilS": round(t.off_foil_s, 2),
        "stoppedS": round(t.stopped_s, 2),
        "pumped": bool(t.pumped),
        "submerged": bool(t.submerged),
        "outcomeWindowS": round(t.outcome_window_s, 2),
    }


def _end_json(e: FlightEnd) -> dict:
    return {
        "flightIndex": e.flight_index,
        "ts": round(e.t, 2),
        "outcome": e.outcome,
        "borderline": bool(e.borderline),
        "offFoilS": round(e.off_foil_s, 2),
        "stoppedS": round(e.stopped_s, 2),
        "minKn": None if not math.isfinite(e.min_speed_mps)
                 else round(e.min_speed_mps * 1.9438445, 3),
        "pumped": bool(e.pumped),
        "submerged": bool(e.submerged),
        "windowS": round(e.window_s, 2),
        "truncated": bool(e.truncated),
        "ownedByTurn": e.owned_by_turn,
        # The swim, on `fell_in` ends only (engine 0.9.2). Null on every other outcome:
        # a glide-out is a rider still making way, and 0.0 would say he swam nowhere.
        "swimM": _round(e.swim_m, 1),
        "swimStartTs": _round(e.swim_start_t, 2),
        "swimEndTs": _round(e.swim_end_t, 2),
    }


def _takeoff_json(k: Takeoff) -> dict:
    """One flight start. `startTs`/`pumps`/`success`/`timeToFoilS` keep the 0.1.0 names."""
    return {
        "startTs": round(k.t, 2),
        "runStartTs": round(k.run_start_t, 2),
        "pumps": k.pumps_to_takeoff,
        "success": True,                    # a flight happened; only its cost can be unknown
        "timeToFoilS": round(k.duration_s, 2),
        "speedRiseS": round(k.speed_rise_s, 2),
        "entryKn": round(k.entry_kn, 3),
        "cadenceSpm": None if k.cadence_spm is None else round(k.cadence_spm, 2),
        "inFlightStrokes": k.in_flight_strokes,
        "free": bool(k.free),
        "truncated": bool(k.truncated),
        "preWindowS": round(k.pre_window_s, 2),
    }


def _episode_json(e: PumpEpisode) -> dict:
    """One classified pumping effort (docs/algorithms.md "Takeoff analysis", the outcome
    ladder). Written for **every** outcome, not just `failed`.

    The summary already counts these five buckets; what it cannot carry is *when*. A failed
    attempt with a timestamp can be placed on a map, drawn on the speed chart and matched to
    a heart-rate window; the same attempt as a tally can only be apologized for. Filtering to
    the outcomes a given screen cares about is presentation's job — the file's job is to say
    what the classifier saw, once, in detection order.

    `durationS` is deliberately absent: it is `endTs - startTs`, and one fact spelled twice
    is one fact that can drift.
    """
    return {
        "startTs": round(e.start_t, 2),           # first stroke
        "endTs": round(e.end_t, 2),               # last stroke
        "strokes": e.strokes,
        "outcome": e.outcome,                     # success|failed|recovery|in_flight|unknown
        "bursts": e.bursts,
        "flightIndex": e.flight_index,            # the flight it produced, or happened in
        "turnIndex": e.turn_index,                # the turn whose recovery it is
        "lookaheadS": round(e.lookahead_s, 2),    # gap-free record past the last stroke
    }


def _hr_json(h: HrAnalysis) -> dict:
    """The HR-cost block (docs/algorithms.md "HR cost").

    Always written, never omitted: a source with no heart-rate channel is a *fact* about
    that source, and `hasHR: false` beside empty lists says it. Omitting the block would
    make "this session had no HR" indistinguishable from "this golden predates the block".
    """
    return {
        "hasHR": bool(h.summary.has_hr),
        "takeoffEvents": [_hr_event_json(e) for e in h.takeoff_events],
        "swimEvents": [_hr_event_json(e) for e in h.swim_events],
        "bins": [_hr_bin_json(b) for b in h.bins],
        "summary": _hr_summary_json(h.summary),
    }


def _hr_event_json(e: HrEvent) -> dict:
    """One anchored measurement. Every bpm field is null rather than 0 when the window
    failed its coverage test -- the coverages beside them say how badly."""
    return {
        "kind": e.kind,
        "index": e.index,
        "ts": round(e.t, 2),
        "approximate": bool(e.approximate),
        "strokes": e.strokes,
        "baselineBpm": _round(e.baseline_bpm, 3),
        "peakBpm": _round(e.peak_bpm, 3),
        "costBpm": _round(e.cost_bpm, 3),
        "peakLagS": _round(e.peak_lag_s, 2),
        "baselineCoverage": round(e.baseline_coverage, 4),
        "peakCoverage": round(e.peak_coverage, 4),
        "recoveryHalfS": _round(e.recovery_half_s, 2),
        "recoveryCensored": bool(e.recovery_censored),
    }


def _hr_bin_json(b: FatigueBin) -> dict:
    return {
        "startTs": round(b.start_t, 2),
        "endTs": round(b.end_t, 2),
        "attempts": b.attempts,
        "successes": b.successes,
        "failed": b.failed,
        "successPct": _round(b.success_pct, 2),
        "avgCostBpm": _round(b.avg_cost_bpm, 3),
        "medianCostBpm": _round(b.median_cost_bpm, 3),
        "costValid": b.cost_coverage.valid,
        "costTotal": b.cost_coverage.total,
        "avgBaselineBpm": _round(b.avg_baseline_bpm, 3),
        "avgPumps": _round(b.avg_pumps, 3),
        "meanBpm": _round(b.mean_bpm, 3),
    }


def _hr_summary_json(s: HrSummary) -> dict:
    """Session tallies. `Coverage` is flattened to a `<name>Valid`/`<name>Total` pair --
    no average here may be read without the count behind it. `has_hr` is deliberately not
    repeated: the block already carries it, and one fact spelled twice is one fact that
    can drift."""
    return {
        "usablePct": _round(s.usable_pct, 2),
        "avgTakeoffCostBpm": _round(s.avg_takeoff_cost_bpm, 3),
        "medianTakeoffCostBpm": _round(s.median_takeoff_cost_bpm, 3),
        **_coverage_json("takeoffCost", s.takeoff_cost_coverage),
        "approximateTakeoffs": s.approximate_takeoffs,
        "medianPeakLagS": _round(s.median_peak_lag_s, 2),
        "bpmPerStroke": _round(s.bpm_per_stroke, 4),
        "medianBpmPerStroke": _round(s.median_bpm_per_stroke, 4),
        **_coverage_json("bpmPerStroke", s.bpm_per_stroke_coverage),
        "pumpCruise": _pump_cruise_json(s.pump_cruise),
        "medianTakeoffRecoveryS": _round(s.median_takeoff_recovery_s, 2),
        **_coverage_json("takeoffRecovery", s.takeoff_recovery_coverage),
        "medianSwimRecoveryS": _round(s.median_swim_recovery_s, 2),
        **_coverage_json("swimRecovery", s.swim_recovery_coverage),
        "avgSwimCostBpm": _round(s.avg_swim_cost_bpm, 3),
        **_coverage_json("swimCost", s.swim_cost_coverage),
    }


def _pump_cruise_json(p: PumpCruiseHr) -> dict:
    return {
        "pumpingBpm": _round(p.pumping_bpm, 3),
        "cruisingBpm": _round(p.cruising_bpm, 3),
        "deltaBpm": _round(p.delta_bpm, 3),
        "pumpingSpans": p.pumping_spans,
        "cruisingSpans": p.cruising_spans,
        "pumpingCoveredS": round(p.pumping_covered_s, 2),
        "pumpingSpanS": round(p.pumping_span_s, 2),
        "cruisingCoveredS": round(p.cruising_covered_s, 2),
        "cruisingSpanS": round(p.cruising_span_s, 2),
    }


def _coverage_json(name: str, c: Coverage) -> dict:
    return {f"{name}Valid": c.valid, f"{name}Total": c.total}


def _wind_json(w: WindEstimate) -> dict | None:
    """The wind object, or null when the COG distribution yielded no usable axis."""
    if w.dir_deg is None:
        return None
    return {
        "dirDeg": round(w.dir_deg, 2),
        "confidence": round(w.confidence, 4),
        "source": w.source,
        "axisDeg": round(w.axis_deg, 2),
        "axisConfidence": round(w.axis_confidence, 4),
        "ambiguityMargin": round(w.ambiguity_margin, 4),
        "separationDeg": None if w.separation_deg is None else round(w.separation_deg, 2),
        "lobesDeg": None if w.lobes_deg is None else [round(v, 2) for v in w.lobes_deg],
        "lobeMass": None if w.lobe_mass is None else [round(v, 4) for v in w.lobe_mass],
        "speedAsymmetry": round(w.speed_asymmetry, 4),
        # The default-turn-type prior's evidence trail. `turnTypeDirDeg` is null whenever the
        # prior did not run (balanced, or a cone margin at/above `windFullMargin`) or found
        # no sweep that is a maneuver under both ends -- which is not the same statement as
        # a margin of 0, and a UI that wants to say "your jibe habit decided this" needs to
        # tell the two apart.
        "turnTypeMargin": round(w.turn_type_margin, 4),
        "turnTypeDirDeg": None if w.turn_type_dir_deg is None
                          else round(w.turn_type_dir_deg, 2),
        "turnTypeVotes": w.turn_type_votes,
        "priorFlipped": bool(w.prior_flipped),
        "distanceM": round(w.distance_m, 1),
        "usable": bool(w.usable),
    }


def _outcome_counts_json(c: OutcomeCounts) -> dict:
    return {"flewThrough": c.flew_through, "touchdown": c.touchdown,
            "fellIn": c.fell_in, "borderline": c.borderline}


def _turn_summary_json(s: TurnSummary) -> dict:
    return {
        "tacks": s.tacks,
        "tacksSuccessful": s.tacks_successful,
        "jibes": s.jibes,
        "jibesSuccessful": s.jibes_successful,
        "unclassified": s.unclassified,
        "turnsCounted": s.turns_counted,
        "turnsSuccessful": s.turns_successful,
        "successPct": round(s.success_pct, 2),
        "rejected": s.rejected,
        "port": s.port,
        "starboard": s.starboard,
        "unknownSide": s.unknown_side,
        "longestDryStreak": s.longest_dry_streak,
        "longestFlewStreak": s.longest_flew_streak,
        "outcomes": _outcome_counts_json(s.outcomes),
        "tackOutcomes": _outcome_counts_json(s.tack_outcomes),
        "jibeOutcomes": _outcome_counts_json(s.jibe_outcomes),
    }


def _end_counts_json(c) -> dict:
    return {"glideOut": c.glide_out, "touchdown": c.touchdown, "fellIn": c.fell_in,
            "unknown": c.unknown, "borderline": c.borderline}


def _end_summary_json(s: FlightEndSummary) -> dict:
    return {"all": _end_counts_json(s.all_ends),
            "straight": _end_counts_json(s.straight),
            "inTurn": _end_counts_json(s.in_turn)}


def _split_json(s: OutcomeSplit) -> dict:
    return {"turnFalls": s.turn_falls, "straightFalls": s.straight_falls,
            "turnTouchdowns": s.turn_touchdowns,
            "straightTouchdowns": s.straight_touchdowns,
            "glideOuts": s.glide_outs, "unknownEnds": s.unknown_ends}


def _takeoff_summary_json(s: TakeoffSummary) -> dict:
    """FIT session fields 35-38 first, then the phone-only detail (docs/algorithms.md)."""
    return {
        "takeoffAttempts": s.takeoff_attempts,        # field 35
        "takeoffSuccesses": s.takeoff_successes,      # field 36
        "avgPumpsToTakeoff": _round(s.avg_pumps_to_takeoff, 3),   # field 37 (x0.1 on the wire)
        "totalPumpStrokes": s.total_pump_strokes,     # field 38
        "successPct": _round(s.success_pct, 2),
        "failedAttempts": s.failed_attempts,
        "unknownAttempts": s.unknown_attempts,
        "recoveryEpisodes": s.recovery_episodes,
        "inFlightEpisodes": s.in_flight_episodes,
        "inFlightPumpStrokes": s.in_flight_pump_strokes,
        "runsJudged": s.runs_judged,
        "runsTruncated": s.runs_truncated,
        "freeTakeoffs": s.free_takeoffs,
        "pumpedTakeoffs": s.pumped_takeoffs,
        "medianPumpsToTakeoff": _round(s.median_pumps_to_takeoff, 3),
        "avgPumpsWhenPumped": _round(s.avg_pumps_when_pumped, 3),
        "avgTakeoffS": _round(s.avg_takeoff_s, 3),
        "medianTakeoffS": _round(s.median_takeoff_s, 3),
    }


def _round(v: float | None, places: int) -> float | None:
    return None if v is None else round(float(v), places)
