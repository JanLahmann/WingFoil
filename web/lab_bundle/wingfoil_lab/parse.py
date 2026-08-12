"""Parse FIT activity files into a RawTrack (records DataFrame + laps + session + capabilities).

Fail-soft by design: missing channels/dev fields reduce SourceCapabilities, never raise.
Developer-field names follow docs/fit-schema.md. Both schema versions are accepted: v2's
packed session fields are expanded into the v1 names here, at the parser boundary, so the
rest of the lab only ever sees one representation (`_unpack_session_v2`).

Class-(a) files also carry the watch's SensorLogging accelerometer stream in
`accelerometer_data` messages (batched: one message per ~25 samples, each sample timed by
`timestamp` + `timestamp_ms` + its `sample_time_offset`). It is returned as a separate
`RawTrack.accel` frame on the *same* time base as the records, because it is two orders of
magnitude longer than the 1 Hz record frame and belongs to a different clock.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from pathlib import Path

import fitdecode
import numpy as np
import pandas as pd

SEMICIRCLE = 180.0 / 2**31
MPS_TO_KN = 1.9438445

# Developer fields we emit from the watch (docs/fit-schema.md). Presence of any marks class (a).
DEV_RECORD_FIELDS = {"foil_state", "flight_index", "pump_cadence", "turn_marker", "tick"}
DEV_SESSION_DISCIPLINE = "discipline"

# Schema v2 folds eight small session fields into three uint32s, because the device allows
# **16 developer fields per message type** and v1's 20 killed the app on START — uncatchably
# (docs/fit-schema.md; beta 0.5.0). Layouts: packed field -> (v1 name, shift, mask), high bits
# first. `cfg_pack` is also what the class-(d) data field writes, so unpacking is keyed on
# presence, never on the schema version.
_SESSION_PACKS = {
    "cfg_pack": (                                # 54, was 40/41/42
        ("cfg_entry_speed", 16, 0xFFFF),         # cm/s
        ("cfg_min_flight", 11, 0x1F),            # s
        ("cfg_exit_speed", 0, 0x7FF),            # cm/s
    ),
    "takeoff_pack": (                            # 55, was 35/36/37
        ("avg_pumps_to_takeoff", 16, 0xFF),      # strokes x0.1, as in v1
        ("takeoff_attempts", 8, 0xFF),
        ("takeoff_successes", 0, 0xFF),
    ),
    "longest_pack": (                            # 56, was 24/25
        ("longest_flight_s", 16, 0xFFFF),        # s
        ("longest_flight_m", 0, 0xFFFF),         # m
    ),
}


def _unpack_session_v2(session: dict) -> None:
    """Expand v2's packed session fields into their v1 names and units, in place.

    A packed field wins over a v1 direct field of the same name (v2 is the authoritative
    encoding); anything absent or non-integer is skipped rather than raised on. After this
    the session dict looks identical for v1 and v2 files, so nothing downstream knows.
    """
    for packed_name, layout in _SESSION_PACKS.items():
        packed = session.get(packed_name)
        if not isinstance(packed, int) or isinstance(packed, bool):
            continue
        for name, shift, mask in layout:
            session[name] = (packed >> shift) & mask


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
    schema_version: int | None = None   # low byte of session `app_version`; None if absent

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
    accel: pd.DataFrame | None = None   # t (s, records' base) + ax/ay/az in g; None if absent


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
    accel_batches: list[tuple] = []

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
                if frame.name == "accelerometer_data":
                    batch = _accel_batch(_frame_fields(frame))
                    if batch is not None:
                        accel_batches.append(batch)

    _unpack_session_v2(session)

    df = pd.DataFrame(records)
    caps = SourceCapabilities()
    epoch0: float | None = None
    if not df.empty and "timestamp" in df:
        df = df.dropna(subset=["timestamp"]).reset_index(drop=True)
        t0 = df["timestamp"].iloc[0]
        epoch0 = t0.timestamp()
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
    app_ver = session.get("app_version")
    caps.schema_version = int(app_ver) & 0xFF if isinstance(app_ver, (int, float)) else None

    accel = _accel_frame(accel_batches, epoch0)
    return RawTrack(path=str(path), records=df, laps=laps, session=session, capabilities=caps,
                    accel=accel)


def _accel_batch(fields: dict) -> tuple | None:
    """One `accelerometer_data` message -> (epoch seconds, ax, ay, az) arrays, or None."""
    ts = fields.get("timestamp")
    off = fields.get("sample_time_offset")
    axes = [fields.get(f"calibrated_accel_{a}") for a in "xyz"]
    if ts is None or off is None or any(a is None for a in axes):
        return None
    n = min(len(off), *(len(a) for a in axes))
    if n == 0:
        return None
    base = ts.timestamp() + float(fields.get("timestamp_ms") or 0) / 1000.0
    t = base + np.asarray(off[:n], dtype=float) / 1000.0
    return (t,) + tuple(np.asarray(a[:n], dtype=float) for a in axes)


def _accel_frame(batches: list[tuple], epoch0: float | None) -> pd.DataFrame | None:
    """Concatenate accel batches onto the records' time base, in g, sorted by time.

    Garmin writes `calibrated_accel_*` in milli-g even though the FIT profile names the unit
    "g"; a resting magnitude near 1000 rather than 1 gives it away, so the scale is sniffed
    rather than assumed and a device that really emits g still parses correctly.
    """
    if not batches or epoch0 is None:
        return None
    t = np.concatenate([b[0] for b in batches]) - epoch0
    ax, ay, az = (np.concatenate([b[i] for b in batches]) for i in (1, 2, 3))
    order = np.argsort(t, kind="stable")
    t, ax, ay, az = t[order], ax[order], ay[order], az[order]
    mag = np.median(np.sqrt(ax * ax + ay * ay + az * az))
    scale = 1e-3 if mag > 20.0 else 1.0
    return pd.DataFrame({"t": t, "ax": ax * scale, "ay": ay * scale, "az": az * scale})


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
