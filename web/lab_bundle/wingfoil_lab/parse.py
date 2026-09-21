"""Parse activity files into a RawTrack (records DataFrame + laps + session + capabilities).

`parse_track` is the door: FIT here, GPX in `gpx.py` (engine 0.9.0, docs/plan.md's input
class (c)). Everything below concerns the FIT half.

Fail-soft by design: missing channels/dev fields reduce SourceCapabilities, never raise.
Developer-field names follow docs/fit-schema.md. Both schema versions are accepted: v2's
packed session fields are expanded into the v1 names here, at the parser boundary, so the
rest of the lab only ever sees one representation (`_unpack_session_v2`).

The `activity` message is read for one field only: `local_timestamp`. FIT timestamps are
UTC, and a session displayed in the *viewer's* current zone is right only while the viewer
and the session share one — which stops being true on the next DST boundary and on the
first flight to a different country. `activity.local_timestamp - activity.timestamp` is the
UTC offset the *watch* was wearing when it saved the file, and it is what every displayed
clock is formatted in (`RawTrack.start_utc_offset_s`, `docs/presentation.md` "Session
time"). Since engine 0.9.1 the parser also records **which rung of the ladder answered**
(`RawTrack.start_utc_offset_source`), because an offset guessed from longitude is a solar
guess that can be an hour out under DST and a page that prints it as fact is over-claiming.

Class-(a) files also carry the watch's SensorLogging accelerometer stream in
`accelerometer_data` messages (batched: one message per ~25 samples, each sample timed by
`timestamp` + `timestamp_ms` + its `sample_time_offset`). It is returned as a separate
`RawTrack.accel` frame on the *same* time base as the records, because it is two orders of
magnitude longer than the 1 Hz record frame and belongs to a different clock.

**Not every device gives that stream a clock** (engine 0.23.0, ADR-030). A tester's
fenix 5 Plus writes one `accelerometer_data` message after each 1 Hz record — and stamps
every one of them with a handful of constant `timestamp`s days away from the session, with
`sample_time_offset` flat at zero. Read literally that is a stream fifty days long starting
before the ride, which produced negative times, NaNs, and a pump grid nobody could
allocate. `_accel_frame` detects the shape and **times the batches from file order**
instead: each batch begins at the last `record` seen before it and its samples spread
evenly over that second. `SourceCapabilities.accel_clock_reconstructed` says so, because a
clock good to ±1 s against GPS and a clock the device wrote are different facts.
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
    #: The accel stream carried no usable clock and was timed from file order instead
    #: (engine 0.23.0). Good to ±1 s against GPS -- each batch starts at the record that
    #: precedes it -- which is ample for a 0.5-2.5 Hz pump band and not ample for anything
    #: that wants to align a sample with a wave. False on every stream the device timed.
    accel_clock_reconstructed: bool = False
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
            return "b"  # the file measured its own speed: a native/other FIT, or a TCX
                        # stating Extensions/TPX/Speed
        return "c"      # degraded: every GPX, and a TCX with no stated speed


@dataclass
class RawTrack:
    path: str
    records: pd.DataFrame            # index: seconds from start; columns below
    laps: list[dict] = field(default_factory=list)
    session: dict = field(default_factory=dict)
    capabilities: SourceCapabilities = field(default_factory=SourceCapabilities)
    accel: pd.DataFrame | None = None   # t (s, records' base) + ax/ay/az in g; None if absent
    #: The session's own UTC offset in **seconds**, from `activity.local_timestamp` minus
    #: `activity.timestamp`. None when the file carries no `activity` message (a converted
    #: GPX, a partial upload) — the caller then falls back to the coarse longitude estimate
    #: or, last of all, to the viewer's clock, flagged.
    start_utc_offset_s: int | None = None
    #: **Which rung of the ladder answered** (engine 0.9.1). See `UTC_OFFSET_SOURCES`.
    #:
    #: The offset alone cannot be read honestly: "+7200 because the watch said so" and
    #: "+7200 because the first fix was at 11°E" are the same number and different facts,
    #: and only the first licenses a surface to say *times as recorded on the water*. A GPX
    #: makes the difference routine rather than exotic — it usually carries no zone at all,
    #: so the longitude guess is the normal answer for it, and that guess is **solar**: an
    #: hour out under DST, and it is summer in half of every GPX corpus.
    #:
    #: None only on a track this parser did not fill in — a hand-built `RawTrack` in a test,
    #: or a document written before 0.9.1. "No source could say" is `"device"`, which is a
    #: statement, not an absence.
    start_utc_offset_source: str | None = None


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
    activity: dict = {}
    accel_frames = 0
    accel_batches: list[tuple] = []
    #: Epoch seconds of every record kept, in **file order** — the clock a clockless accel
    #: stream is timed against (`_accel_frame`).
    record_epochs: list[float] = []

    with fitdecode.FitReader(path, check_crc=fitdecode.CrcCheck.WARN) as reader:
        for frame in reader:
            if not isinstance(frame, fitdecode.FitDataMessage):
                continue
            if frame.name == "record":
                raw = _frame_fields(frame)
                row = {k: v for k, v in raw.items() if k in _RECORD_KEEP or k in DEV_RECORD_FIELDS}
                if row:
                    records.append(row)
                    ts = raw.get("timestamp")
                    if ts is not None:
                        try:
                            record_epochs.append(float(ts.timestamp()))
                        except (AttributeError, TypeError, ValueError, OSError):
                            pass
            elif frame.name == "lap":
                laps.append(_frame_fields(frame))
            elif frame.name == "session":
                session = _frame_fields(frame)
            elif frame.name == "activity" and not activity:
                activity = _frame_fields(frame)
            elif frame.name in ("accelerometer_data", "three_d_sensor_calibration"):
                accel_frames += 1
                if frame.name == "accelerometer_data":
                    batch = _accel_batch(_frame_fields(frame), len(record_epochs))
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

    accel, caps.accel_clock_reconstructed = _accel_frame(accel_batches, epoch0, record_epochs)
    offset, source = resolve_utc_offset(activity_utc_offset_s(activity), df, caps)
    return RawTrack(path=str(path), records=df, laps=laps, session=session, capabilities=caps,
                    accel=accel, start_utc_offset_s=offset, start_utc_offset_source=source)


def parse_track(path: str | Path) -> RawTrack:
    """Parse whatever this file is — FIT, GPX or TCX — into one `RawTrack`.

    The single door every consumer should come through (engine 0.9.0; TCX joined it later).
    The format is decided by **content**, with the extension as a last resort: each of the
    three announces itself at the front of the file — the `.FIT` signature at byte 8, a
    `<gpx` root element, a `<TrainingCenterDatabase>` one — so a mislabelled file is read
    for what it *is* rather than for what it is called. That matters more with three formats
    than it did with two: a browser unpacking a zip and a phone archiving an original both
    name the file from whatever the uploader called it, and "ride.gpx" holding TCX bytes is
    a real shape.

    Everything downstream — clean, flights, turns, records — is already written against
    `RawTrack` plus `SourceCapabilities` and needs to know nothing about which door the
    track came in by; that is the whole point of the class (a)/(b)/(c) split (docs/plan.md
    §3.3). A TCX is the one format that can be either (b) or (c), and `tcx.py` decides which
    from the file itself.
    """
    path = Path(path)
    from .gpx import is_gpx, parse_gpx        # local: gpx/tcx import this module
    from .tcx import is_tcx, parse_tcx
    with open(path, "rb") as fh:
        head = fh.read(2048)
    if is_tcx(head):
        return parse_tcx(path)
    if is_gpx(head):
        return parse_gpx(path)
    # Nothing announced itself — a truncated XML header, an exotic wrapper. The extension is
    # the only thing left to go on, and FIT stays the fallback it has always been.
    if path.suffix.lower() == ".tcx":
        return parse_tcx(path)
    if path.suffix.lower() == ".gpx":
        return parse_gpx(path)
    return parse_fit(path)


#: The rungs of the UTC-offset ladder, best answer first — the vocabulary of
#: `RawTrack.start_utc_offset_source`, `meta.utcOffsetSource` in the web document, and
#: `session.startUtcOffsetSource` in the iOS library (engine 0.9.1).
#:
#: * ``"activity"`` — the recording said so itself: a FIT `activity` message's
#:   `local_timestamp - timestamp`, or a GPX timestamp that carried a local offset. Exact,
#:   DST included, and a fact about *this session* rather than about where it is read.
#: * ``"icu"`` — intervals.icu's `timezone` for the activity, resolved at the session's own
#:   instant. Also exact; second only because it is a fact about the athlete's account.
#:   Set by the iOS ingest path, which is the only one with an intervals.icu to ask.
#: * ``"longitude"`` — `round(lon / 15°)` hours from the first fix. A **guess**: the solar
#:   offset, not the civil one.
#: * ``"device"`` — nothing could say, `start_utc_offset_s` is None, and whoever displays
#:   this falls back to the reader's own clock.
UTC_OFFSET_SOURCES = ("activity", "icu", "longitude", "device")


def resolve_utc_offset(declared, df, caps) -> tuple[int | None, str]:
    """The ladder, in one place: the offset **and** the rung that produced it.

    `declared` is whatever the file itself stated — a FIT `activity` offset, a GPX
    timestamp's own offset — or None. The longitude fallback is tried next, and "nothing"
    is an answer with a name (`"device"`) rather than a silence, so a reader can tell a
    document that never asked from one that asked and got nowhere.

    Returning the two together is the point. Two call sites (FIT and GPX) used to run the
    same two rungs independently, and neither recorded which one won — which is exactly how
    a solar guess ended up printed as "times as recorded on the water".
    """
    if declared is not None:
        return declared, "activity"
    if caps.has_position and "lon" in df:
        lon = df["lon"].dropna()
        if not lon.empty:
            guess = coarse_utc_offset_s(float(lon.iloc[0]))
            if guess is not None:
                return guess, "longitude"
    return None, "device"


def activity_utc_offset_s(activity: dict) -> int | None:
    """`activity.local_timestamp - activity.timestamp`, in whole seconds.

    The watch's own answer to "what time did the rider see", and the only exact one there
    is: both fields are written at save time from the same clock, so their difference is
    the offset that was in force *for this session* — DST included, and unaffected by where
    the file is read afterwards. Verified present and correct (+7200) on every fixture in
    the corpus, native recordings and our CIQ app alike.

    Returns None rather than 0 when either field is missing: "this file does not say" and
    "this session was recorded at UTC" are different facts, and only one of them licenses a
    fallback.
    """
    local, utc = activity.get("local_timestamp"), activity.get("timestamp")
    if local is None or utc is None:
        return None
    try:
        return int(round((local - utc).total_seconds()))
    except (AttributeError, TypeError):
        return None


def coarse_utc_offset_s(lon: float) -> int | None:
    """A whole-hour offset guessed from longitude — the fallback, and only ever that.

    **Precision.** `round(lon / 15°)` hours is the *solar* offset, not the civil one. It is
    right to the hour across most of Europe in winter and wrong by an hour there all summer
    (DST), wrong by up to two hours inside wide zones (China, Spain), and knows nothing of
    the half-hour zones (India, Newfoundland). It exists for one case: a source with GPS
    fixes and no `activity` message, where "within an hour or two of the truth" beats
    formatting an Italian afternoon in the reader's Californian morning. Anything that can
    answer exactly — the FIT's own `activity`, or intervals.icu's `timezone` — wins over it.
    """
    if lon is None or not math.isfinite(lon):
        return None
    return int(round(lon / 15.0)) * 3600


#: How long one `accelerometer_data` batch is taken to last when the stream carries no
#: clock of its own. The device writes one batch per 1 Hz record, so a second is what a
#: batch *is*; the samples inside it spread evenly across it (n samples -> i/n s).
ACCEL_BATCH_SPAN_S = 1.0


def _accel_batch(fields: dict, after_records: int) -> tuple | None:
    """One `accelerometer_data` message -> (base, offsets_ms, ax, ay, az, after_records).

    `base` is the batch's own epoch second (`timestamp` + `timestamp_ms`) and `offsets_ms`
    the per-sample offsets as written; both are kept *unapplied* so `_accel_frame` can
    decide whether to believe them. `after_records` is how many records had been read when
    this batch arrived — the file-order anchor a clockless stream is timed from.
    """
    ts = fields.get("timestamp")
    off = fields.get("sample_time_offset")
    axes = [fields.get(f"calibrated_accel_{a}") for a in "xyz"]
    if ts is None or off is None or any(a is None for a in axes):
        return None
    n = min(len(off), *(len(a) for a in axes))
    if n == 0:
        return None
    try:
        base = float(ts.timestamp()) + float(fields.get("timestamp_ms") or 0) / 1000.0
    except (AttributeError, TypeError, ValueError, OSError):
        return None
    offsets = np.asarray([x if isinstance(x, (int, float)) else np.nan for x in off[:n]],
                         dtype=float)
    return ((base, offsets)
            + tuple(np.asarray(a[:n], dtype=float) for a in axes)
            + (int(after_records),))


def _accel_clock_is_usable(batches: list[tuple], record_epochs: list[float]) -> bool:
    """Did the device *time* this accelerometer stream, or only stamp it?

    Two independent tests, either of which condemns the clock (engine 0.23.0, ADR-030):

    * **The bases are not on this session's clock.** Fewer than half the batch timestamps
      fall inside the records' own span. A tester's fenix 5 Plus reuses a handful of stale
      `timestamp`s days either side of the ride; a watch that timed the stream puts every
      batch inside the session, and our own recordings do — 2 580 of 2 580 and 16 588 of
      16 588 on the two corpus fixtures that carry the channel.
    * **There is no clock inside a batch either.** No batch of two or more samples has any
      spread in its `sample_time_offset`. Twenty-five samples all at offset 0 are
      twenty-five samples with one time, which is not a time.

    With no records to compare against the file is believed: there is nothing better.
    """
    if not batches:
        return True
    if record_epochs:
        lo, hi = record_epochs[0], record_epochs[-1]
        inside = sum(1 for b in batches if lo - 1.0 <= b[0] <= hi + 1.0)
        if inside * 2 < len(batches):
            return False
    for b in batches:
        off = b[1]
        if off.size >= 2 and np.isfinite(off).any() and np.nanmax(off) > np.nanmin(off):
            return True
    return False


def _accel_times(batches: list[tuple], record_epochs: list[float],
                 epoch0: float) -> tuple[np.ndarray, bool]:
    """Per-sample epoch times for every batch -> (times, the clock was reconstructed)."""
    if _accel_clock_is_usable(batches, record_epochs):
        return np.concatenate([b[0] + b[1] / 1000.0 for b in batches]), False
    # File order. Each batch starts at the record that precedes it and lasts one second,
    # monotonically — so several batches written after the same record queue up behind it
    # rather than landing on one instant.
    out: list[np.ndarray] = []
    prev_end = -np.inf
    for b in batches:
        idx = b[5]
        anchor = record_epochs[idx - 1] if 0 < idx <= len(record_epochs) else epoch0
        start = max(float(anchor), prev_end)
        n = int(b[2].size)
        out.append(start + np.arange(n, dtype=float) / n * ACCEL_BATCH_SPAN_S)
        prev_end = start + ACCEL_BATCH_SPAN_S
    return np.concatenate(out), True


def _accel_frame(batches: list[tuple], epoch0: float | None,
                 record_epochs: list[float] | None = None
                 ) -> tuple[pd.DataFrame | None, bool]:
    """Concatenate accel batches onto the records' time base, in g, sorted by time.

    Garmin writes `calibrated_accel_*` in milli-g even though the FIT profile names the unit
    "g"; a resting magnitude near 1000 rather than 1 gives it away, so the scale is sniffed
    rather than assumed and a device that really emits g still parses correctly.

    Returns `(frame, the clock was reconstructed)`. A sample whose time or whose axes did
    not survive the file — an invalid sentinel inside an array — is **dropped rather than
    carried as NaN**: a NaN reaches the pump resampler as a grid length, and
    `int(floor(nan))` is not a number of bins.
    """
    if not batches or epoch0 is None:
        return None, False
    t, reconstructed = _accel_times(batches, record_epochs or [], epoch0)
    t = t - epoch0
    ax, ay, az = (np.concatenate([b[i] for b in batches]) for i in (2, 3, 4))
    finite = np.isfinite(t) & np.isfinite(ax) & np.isfinite(ay) & np.isfinite(az)
    if not finite.all():
        t, ax, ay, az = t[finite], ax[finite], ay[finite], az[finite]
    if t.size == 0:
        return None, reconstructed
    order = np.argsort(t, kind="stable")
    t, ax, ay, az = t[order], ax[order], ay[order], az[order]
    mag = np.median(np.sqrt(ax * ax + ay * ay + az * az))
    scale = 1e-3 if mag > 20.0 else 1.0
    return pd.DataFrame({"t": t, "ax": ax * scale, "ay": ay * scale,
                         "az": az * scale}), reconstructed


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
