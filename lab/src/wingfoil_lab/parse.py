"""Parse FIT activity files into a RawTrack (records DataFrame + laps + session + capabilities).

Fail-soft by design: missing channels/dev fields reduce SourceCapabilities, never raise.
Developer-field names follow docs/fit-schema.md.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from pathlib import Path

import fitdecode
import pandas as pd

SEMICIRCLE = 180.0 / 2**31
MPS_TO_KN = 1.9438445

# Developer fields we emit from the watch (docs/fit-schema.md). Presence of any marks class (a).
DEV_RECORD_FIELDS = {"foil_state", "flight_index", "pump_cadence", "turn_marker", "tick"}
DEV_SESSION_DISCIPLINE = "discipline"


@dataclass
class SourceCapabilities:
    has_speed: bool = False          # device speed channel present (Doppler-based on Garmin)
    has_position: bool = False
    has_dev_fields: bool = False     # our schema's record fields present -> source class (a)
    has_watch_laps: bool = False     # more than one lap
    has_accel: bool = False          # SensorLogging accelerometer stream present
    has_hr: bool = False
    sample_rate_hz: float = 0.0
    discipline: str | None = None    # from session dev field, e.g. "wingfoil"
    sport: str | None = None         # FIT session sport name, e.g. "windsurfing"
    sub_sport: str | None = None

    @property
    def source_class(self) -> str:
        if self.has_dev_fields:
            return "a"  # our CIQ app
        if self.has_speed:
            return "b"  # native/other FIT
        return "c"      # degraded (e.g. GPX-derived)


@dataclass
class RawTrack:
    path: str
    records: pd.DataFrame            # index: seconds from start; columns below
    laps: list[dict] = field(default_factory=list)
    session: dict = field(default_factory=dict)
    capabilities: SourceCapabilities = field(default_factory=SourceCapabilities)


_RECORD_KEEP = {
    "timestamp", "position_lat", "position_long", "speed", "enhanced_speed",
    "heart_rate", "altitude", "enhanced_altitude", "distance", "temperature",
}


def _frame_fields(frame: fitdecode.FitDataMessage) -> dict:
    out = {}
    for f in frame.fields:
        if f.value is None:
            continue
        out[f.name] = f.value
    return out


def parse_fit(path: str | Path) -> RawTrack:
    path = Path(path)
    records: list[dict] = []
    laps: list[dict] = []
    session: dict = {}
    accel_frames = 0

    with fitdecode.FitReader(path, check_crc=fitdecode.CrcCheck.WARN) as reader:
        for frame in reader:
            if not isinstance(frame, fitdecode.FitDataMessage):
                continue
            if frame.name == "record":
                raw = _frame_fields(frame)
                row = {k: v for k, v in raw.items() if k in _RECORD_KEEP or k in DEV_RECORD_FIELDS}
                if row:
                    records.append(row)
            elif frame.name == "lap":
                laps.append(_frame_fields(frame))
            elif frame.name == "session":
                session = _frame_fields(frame)
            elif frame.name in ("accelerometer_data", "three_d_sensor_calibration"):
                accel_frames += 1

    df = pd.DataFrame(records)
    caps = SourceCapabilities()
    if not df.empty and "timestamp" in df:
        df = df.dropna(subset=["timestamp"]).reset_index(drop=True)
        t0 = df["timestamp"].iloc[0]
        df["t"] = (df["timestamp"] - t0).dt.total_seconds()
        # unify speed: prefer enhanced_speed, fall back to speed (both m/s on Garmin)
        if "enhanced_speed" in df or "speed" in df:
            df["speed_mps"] = df.get("enhanced_speed", pd.Series(dtype=float)).combine_first(
                df.get("speed", pd.Series(dtype=float))
            )
            caps.has_speed = df["speed_mps"].notna().any()
        if "position_lat" in df and "position_long" in df:
            df["lat"] = df["position_lat"] * SEMICIRCLE
            df["lon"] = df["position_long"] * SEMICIRCLE
            caps.has_position = df["lat"].notna().any()
        caps.has_hr = "heart_rate" in df and df["heart_rate"].notna().any()
        caps.has_dev_fields = any(c in df.columns for c in DEV_RECORD_FIELDS)
        if len(df) > 1:
            dt = df["t"].diff().dropna()
            med = float(dt.median()) if not dt.empty else 0.0
            caps.sample_rate_hz = round(1.0 / med, 3) if med > 0 else 0.0

    caps.has_watch_laps = len(laps) > 1
    caps.has_accel = accel_frames > 0
    sport = session.get("sport")
    caps.sport = str(sport) if sport is not None else None
    sub = session.get("sub_sport")
    caps.sub_sport = str(sub) if sub is not None else None
    disc = session.get(DEV_SESSION_DISCIPLINE)
    caps.discipline = str(disc) if disc is not None else None

    return RawTrack(path=str(path), records=df, laps=laps, session=session, capabilities=caps)


def summarize(track: RawTrack) -> dict:
    """Quick human-readable summary for notebooks / smoke tests."""
    df = track.records
    out = {
        "file": Path(track.path).name,
        "samples": int(len(df)),
        "sample_rate_hz": track.capabilities.sample_rate_hz,
        "source_class": track.capabilities.source_class,
        "sport": track.capabilities.sport,
        "discipline": track.capabilities.discipline,
        "laps": len(track.laps),
    }
    if track.capabilities.has_speed:
        sp = df["speed_mps"].dropna()
        out["max_speed_kn"] = round(float(sp.max()) * MPS_TO_KN, 2) if not sp.empty else None
        out["duration_min"] = round(float(df["t"].iloc[-1]) / 60.0, 1) if len(df) else 0.0
    if "distance" in df and df["distance"].notna().any():
        out["distance_km"] = round(float(df["distance"].dropna().iloc[-1]) / 1000.0, 2)
    return out
