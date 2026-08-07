"""Golden-file writer/loader — the cross-implementation contract (docs/testing.md).

Field names are camelCase verbatim. The lab is the authoritative reference: every number
here is re-derived by `ios/WingFoilKit` from the same original FIT and asserted against
this file (`GoldenTests`), so anything added here becomes a parity obligation.

Engine 0.2.0 fills the phases the 0.1.0 schema left as documented empties — `turns`,
`wind`, `takeoffs` — and adds `flightEnds` (docs/algorithms.md "Flight-end outcome", a
phase-2/3 output the original schema predates). Source capabilities still degrade the
same way the modules do: no accel ⇒ `pumps`/stroke counts null, no barometer ⇒ no
submersion evidence, Smart-Recording truncation ⇒ `unknown` outcomes excluded from tallies.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path

from . import ENGINE_VERSION, gp3s
from .filters import CleanTrack, FilterConfig, clean
from .flight import FlightConfig, FlightResult, segment_flights
from .flightend import (FlightEnd, FlightEndConfig, FlightEndSummary, OutcomeSplit,
                        classify_flight_ends, split_outcomes, summarize_flight_ends)
from .gp3s import GP3SRecords, RecordWindow
from .parse import RawTrack, parse_fit
from .pump import PumpConfig, PumpTrack, pump_track
from .takeoff import (Takeoff, TakeoffAnalysis, TakeoffConfig, TakeoffSummary,
                      analyze_takeoffs, summarize_takeoffs)
from .turns import (OutcomeCounts, Turn, TurnConfig, TurnSummary, detect_turns,
                    summarize_turns)
from .wind import WindConfig, WindEstimate, estimate_wind


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
    wind_config: WindConfig
    turn_config: TurnConfig
    flight_end_config: FlightEndConfig
    pump_config: PumpConfig
    takeoff_config: TakeoffConfig


def analyze(path: str | Path, filter_config: FilterConfig | None = None,
            flight_config: FlightConfig | None = None,
            wind_config: WindConfig | None = None,
            turn_config: TurnConfig | None = None,
            flight_end_config: FlightEndConfig | None = None,
            pump_config: PumpConfig | None = None,
            takeoff_config: TakeoffConfig | None = None) -> Analysis:
    """Full pipeline: parse -> clean -> flights -> records -> wind -> turns -> ends -> takeoffs."""
    fcfg = filter_config or FilterConfig()
    flcfg = flight_config or FlightConfig()
    wcfg = wind_config or WindConfig()
    tcfg = turn_config or TurnConfig()
    fecfg = flight_end_config or FlightEndConfig()
    pcfg = pump_config or PumpConfig()
    tocfg = takeoff_config or TakeoffConfig()

    track = parse_fit(path)
    ct = clean(track, fcfg)
    fr = segment_flights(ct, flcfg)
    rec = gp3s.records(ct)
    wind = estimate_wind(ct, fr, wcfg)
    pt = pump_track(track, pcfg)
    turns = detect_turns(ct, fr, wind, tcfg, pt)
    ends = classify_flight_ends(ct, fr, turns, fecfg, pt)
    takeoffs = analyze_takeoffs(ct, fr, turns, tocfg, pt)

    turn_summary = summarize_turns(turns)
    end_summary = summarize_flight_ends(ends)
    return Analysis(
        track=track, clean=ct, flights=fr, records=rec,
        filter_config=fcfg, flight_config=flcfg,
        wind=wind, turns=turns, turn_summary=turn_summary,
        flight_ends=ends, flight_end_summary=end_summary,
        outcome_split=split_outcomes(turn_summary, end_summary),
        takeoffs=takeoffs, takeoff_summary=summarize_takeoffs(takeoffs), pump=pt,
        wind_config=wcfg, turn_config=tcfg, flight_end_config=fecfg,
        pump_config=pcfg, takeoff_config=tocfg,
    )


def build_golden(a: Analysis) -> dict:
    caps = a.track.capabilities
    fr, rec = a.flights, a.records
    longest_s = fr.longest.duration_s if fr.longest else 0.0
    longest_m = max((f.dist_m for f in fr.flights), default=0.0)
    pumps = {k.flight_index: k.pumps_to_takeoff for k in a.takeoffs.takeoffs}
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
        "summary": {
            "foilTimeS": round(fr.foil_time_s, 1),
            "foilPct": round(fr.foil_pct, 2),
            "flightCount": fr.flight_count,
            "longestFlightS": round(longest_s, 1),
            "longestFlightM": round(longest_m, 1),
            "distanceKm": round(rec.distance_m / 1000.0, 3),
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
        # pumping
        "pumpBandLo": p.band_lo_hz,
        "pumpBandHi": p.band_hi_hz,
        "pumpResampleHz": p.resample_hz,
        "pumpFilterSpan": p.filter_span_s,
        "pumpStrokeAmp": p.stroke_amp_g,
        "pumpRefractory": p.refractory_s,
        "pumpStrokeMaxInterval": p.stroke_max_interval_s,
        "pumpMinStrokes": p.min_strokes,
        # takeoff
        "takeoffMaxRun": k.max_run_s,
        "takeoffRiseSlack": k.rise_slack_mps,
        "takeoffRestSpeed": k.rest_speed_mps,
        "takeoffAttemptWindow": k.attempt_window_s,
        "takeoffMinPreWindow": k.min_pre_window_s,
        "freeTakeoff": k.free_takeoff_strokes,
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
