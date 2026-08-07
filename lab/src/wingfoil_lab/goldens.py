"""Golden-file writer/loader — exact JSON schema from docs/testing.md.

Field names are camelCase verbatim. Phases not yet implemented in the lab emit their
schema-mandated empties: `turns: []`, `takeoffs: []`, and `wind: null` (deviation from
the schema's wind object — expected until the wind phase lands). `takeoffPumps` is
null per flight (needs class-(a) dev fields / accel).
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from . import ENGINE_VERSION, gp3s
from .filters import CleanTrack, FilterConfig, clean
from .flight import FlightConfig, FlightResult, segment_flights
from .gp3s import GP3SRecords, RecordWindow
from .parse import RawTrack, parse_fit


@dataclass
class Analysis:
    track: RawTrack
    clean: CleanTrack
    flights: FlightResult
    records: GP3SRecords
    filter_config: FilterConfig
    flight_config: FlightConfig


def analyze(path: str | Path, filter_config: FilterConfig | None = None,
            flight_config: FlightConfig | None = None) -> Analysis:
    """Full L1 pipeline: parse -> clean -> flights -> records."""
    fcfg = filter_config or FilterConfig()
    flcfg = flight_config or FlightConfig()
    track = parse_fit(path)
    ct = clean(track, fcfg)
    fr = segment_flights(ct, flcfg)
    rec = gp3s.records(ct)
    return Analysis(track, ct, fr, rec, fcfg, flcfg)


def build_golden(a: Analysis) -> dict:
    caps = a.track.capabilities
    fr, rec = a.flights, a.records
    longest_s = fr.longest.duration_s if fr.longest else 0.0
    longest_m = max((f.dist_m for f in fr.flights), default=0.0)
    return {
        "engineVersion": ENGINE_VERSION,
        "config": _config_dict(a.filter_config, a.flight_config),
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
             "takeoffPumps": None}
            for f in fr.flights
        ],
        "turns": [],
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
        "wind": None,
        "takeoffs": [],
        "summary": {
            "foilTimeS": round(fr.foil_time_s, 1),
            "foilPct": round(fr.foil_pct, 2),
            "flightCount": fr.flight_count,
            "longestFlightS": round(longest_s, 1),
            "longestFlightM": round(longest_m, 1),
            "distanceKm": round(rec.distance_m / 1000.0, 3),
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


def _config_dict(fcfg: FilterConfig, flcfg: FlightConfig) -> dict:
    """Params actually used, docs/algorithms.md names (camelCase)."""
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
        "alphaProximity": gp3s.ALPHA_PROXIMITY_M,
        "alphaMaxDistance": gp3s.ALPHA_MAX_DISTANCE_M,
        "alphaCandidatePruneMinPath": gp3s.ALPHA_MIN_PATH_M,
        "alphaCandidatePruneMinCogSpread": gp3s.ALPHA_MIN_COG_SPREAD_DEG,
        "minSpeedFilter": None,
    }


def _window_json(w: RecordWindow | list[RecordWindow]) -> dict | list[dict]:
    if isinstance(w, list):
        return [_window_json(x) for x in w]
    return {"startTs": round(w.start_t, 2), "durS": round(w.duration_s, 2)}
