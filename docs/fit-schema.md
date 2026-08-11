# FIT Developer-Field Schema (contract)

**Single source of truth** for FIT developer fields written by the Garmin app and read by
`WingFoilKit/FitImport` and `lab/src/wingfoil_lab/parse.py`. Any change here bumps
`SCHEMA_VERSION` and must be reflected in all three implementations plus
`garmin/resources/fitcontributions/fit_contributions.xml`.

- `SCHEMA_VERSION`: **1** (carried in session field `app_version`, low byte = schema version)
- Developer data index: 0 (single developer)
- Field ID convention: **record 0–9 · lap 10–19 · session 20–49**
- All speeds: `uint16` in **cm/s** (0–655.35 m/s). Convert for display (kn = m/s × 1.9438445).
- Budgets (CIQ device app): 256 B per message type. Used: record 6 B · lap 11 B · session ~57 B.
  The **data-field variant** (`garmin/field/`) has a far tighter budget and its own compact
  session schema — see "Field-variant FIT (class d)" below.
- Recording activity: `sport = 43 (windsurfing)`, `subSport = 0 (generic)`, session name `"Wingfoil"`.
  The session-level `discipline` string is the authoritative discipline tag, NOT the sport code.

## RECORD messages (written at 1 Hz) — 6 bytes

| fieldId | name | type | units | enum / scale | GC render | notes |
|---|---|---|---|---|---|---|
| 0 | `foil_state` | uint8 | — | 0 = off-foil · 1 = pumping/attempt · 2 = flying | chart | drives phase coloring |
| 1 | `flight_index` | uint16 | count | 0 = not in flight, N = Nth flight (1-based) | — | joins records↔flights |
| 2 | `pump_cadence` | uint8 | strokes/min | 0 when detector unarmed | chart | live detector value; phone recomputes from accel |
| 3 | `turn_marker` | uint8 | — | 0 = none · 1 = tack · 2 = jibe · 3 = turn (wind unknown) · 4 = flew_through · 5 = touchdown · 6 = fell_in | — | see below |
| 4 | `tick` | uint8 | — | rolling 0–254 | — | changes every second → defeats smart-recording collapse; 255 = FIT uint8 invalid sentinel, never written |

**`turn_marker` is two events on two different seconds, not one.** 1–3 mark the second the COG
sweep is *confirmed* and say what kind of maneuver it was; 4–6 mark the second its *outcome*
resolves — the end of the recovery-gated window, which is 2–14 s later (docs/algorithms.md
"Turn outcome"). A detected turn therefore writes exactly two non-zero markers, and the
watch's `tack_count`/`jibe_count` equal the number of 1/2 markers. The field is rewritten
every record, so a marker never bleeds into the following second. Values 4–6 are an addition
within `SCHEMA_VERSION` 1: readers written against the original 0–3 enum keep working
(1/2/3 unchanged) and must ignore markers they do not know rather than fail.
Bear-aways and round-ups (a course change that crosses neither wind-axis end) are dropped by
the watch and write no marker at all.

## LAP messages (laps alternate: flight / off-foil segment) — 11 bytes

Native lap fields (start time, elapsed, distance, avg/max speed) come free from `addLap()`.

| fieldId | name | type | units | GC render | notes |
|---|---|---|---|---|---|
| 10 | `lap_type` | uint8 | — (0 = off-foil · 1 = flight) | laps | |
| 11 | `flight_num` | uint16 | count | laps | 0 for off-foil laps |
| 12 | `takeoff_pumps` | uint16 | strokes | laps | flight laps: strokes in the attempt that launched it; 0 = free takeoff |
| 13 | `takeoff_time` | uint16 | s | — | attempt start → foil entry |
| 14 | `pump_strokes` | uint16 | strokes | — | strokes within this lap |
| 15 | `turn_count` | uint8 | count | laps | turns confirmed inside this lap (bear-aways excluded) |
| 16 | `best_turn_score` | uint8 | % | — | best min/entry ratio among turns whose outcome **resolved** in this lap |

## SESSION message (written once at save) — ~57 bytes

| fieldId | name | type | units | GC render | notes |
|---|---|---|---|---|---|
| 20 | `discipline` | string(16) | — | — | `"wingfoil"` (settings may later allow `"windfoil"` etc.) |
| 21 | `foil_time` | uint32 | s | summary | |
| 22 | `foil_pct` | uint8 | % | summary | of timer time |
| 23 | `flight_count` | uint16 | count | summary | |
| 24 | `longest_flight_s` | uint16 | s | summary | |
| 25 | `longest_flight_m` | uint32 | m | summary | |
| 26 | `best_2s` | uint16 | cm/s | summary | shown in kn |
| 27 | `best_10s` | uint16 | cm/s | — | |
| 28 | `best_5x10s` | uint16 | cm/s | summary | mean of best 5 disjoint 10 s windows |
| 29 | `best_500m` | uint16 | cm/s | summary | |
| 30 | `best_nm` | uint16 | cm/s | — | 1852 m; 0 = no qualifying run |
| 31 | `alpha500_lite` | uint16 | cm/s | — | watch approximation; phone computes exact |
| 32 | `tack_count` | uint8 | count | summary | only ≠0 when wind axis known; saturates at 254 |
| 33 | `jibe_count` | uint8 | count | summary | |
| 34 | `turn_success_pct` | uint8 | % | summary | successful / attempted turns (score ≥ `turnSuccessPct` and never off the foil), over *all* counted turns including the generic ones |
| 35 | `takeoff_attempts` | uint8 | count | summary | |
| 36 | `takeoff_successes` | uint8 | count | summary | |
| 37 | `avg_pumps_to_takeoff` | uint8 | strokes ×0.1 | summary | value 87 = 8.7 strokes |
| 38 | `total_pump_strokes` | uint16 | strokes | — | |
| 39 | `wind_dir_user` | uint16 | deg | — | direction the wind blows **from**, true; 65535 = unset. Set in GCM (`windDirDeg`) or on the watch (BACK → Session → Wind, 16 compass points). The value written is the one in effect at save; the watch classifies only turns detected *after* it was set, so a mid-session change can leave earlier turns generic — the phone re-runs classification over the whole track and is authoritative |
| 40 | `cfg_entry_speed` | uint16 | cm/s | — | thresholds in effect (phone needs them to reconcile) |
| 41 | `cfg_exit_speed` | uint16 | cm/s | — | |
| 42 | `cfg_min_flight` | uint8 | s | — | |
| 43 | `app_version` | uint16 | — | — | high byte = app minor version, low byte = SCHEMA_VERSION |

## Field-variant FIT (class d) — written by the **WingFoil Field** data field

`garmin/field/` is a CIQ **data field** that runs inside a *native* activity (Jan's usual
fenix 8 **Windsurf** profile). Garmin owns the recording, the sport code, the GPS and the
laps; the data field only computes and contributes developer fields. It shares the detection
core with the device app through the `WingFoilCore` barrel, so flights and turns mean exactly
the same thing in both — what differs is the plumbing and the budget.

**Platform budget (measured on `fenix847mm`, not assumed).** A probe build created developer
fields one at a time until the runtime refused. Two limits apply **per message type**:

| limit | value | evidence |
|---|---|---|
| developer data bytes | **32 B** | 8 × uint32 session fields (32 B) accepted, 9th refused |
| developer field count | **16** | 16 × uint8 (16 B) accepted, 17th refused; 5 × uint32 + 11 × uint8 (31 B) accepted, 17th refused |

The field-count limit is undocumented and bites first for a schema of small fields. Exceeding
either kills the app (`Out Of Memory Error: New Field out of memory for FIT data`, or from
inside a loop the unhelpful `System Error: Failed invoking <symbol>`) — it is **not** a
catchable exception. `garmin/field/source/SessionPack.mc` is the single table that encodes the
schema, and `sessionSchemaFitsDataFieldBudget` fails the build's tests before the watch can.

### RECORD messages (1 Hz) — 3 fields / 3 bytes

Identical ids, types and meanings to the device app: `foil_state`(0) · `turn_marker`(3) ·
`tick`(4). `flight_index`(1) and `pump_cadence`(2) are **not** written — there is no lap
structure to index against and no accelerometer (below).

### SESSION message — 14 fields / **29 bytes** (limit 32 B / 16 fields)

| fieldId | name | type | B | notes |
|---|---|---|---|---|
| 21 | `foil_time` | uint32 | 4 | as the device app |
| 22 | `foil_pct` | uint8 | 1 | of timer time |
| 23 | `flight_count` | uint16 | 2 | saturates at 65534 |
| 24 | `longest_flight_s` | uint16 | 2 | |
| 26 | `best_2s` | uint16 | 2 | cm/s |
| 27 | `best_10s` | uint16 | 2 | cm/s |
| 32 | `tack_count` | uint8 | 1 | saturates at 254 |
| 33 | `jibe_count` | uint8 | 1 | |
| 34 | `turn_success_pct` | uint8 | 1 | |
| 39 | `wind_dir_user` | uint16 | 2 | 65535 = unset |
| 43 | `app_version` | uint16 | 2 | high byte app minor, low byte `SCHEMA_VERSION` |
| 50 | `turn_outcomes` | uint32 | 4 | **packed**: `flew << 16 \| touchdown << 8 \| fell`, each uint8 saturating at 254 |
| 53 | `discipline_id` | uint8 | 1 | 1 = wingfoil — the compact form of the app's `discipline`(20) string |
| 54 | `cfg_pack` | uint32 | 4 | **packed**: `entry_cms << 16 \| minFlight_s << 11 \| exit_cms` (entry 16 b cm/s · minFlight 5 b s · exit 11 b cm/s) — the compact form of `cfg_entry_speed`(40)/`cfg_min_flight`(42)/`cfg_exit_speed`(41) |

Ids **21–43 keep the device app's meaning and type exactly**; 50–59 is a new band reserved for
field-variant-only fields. 50 and 54 are bit-packed because *fields*, not bytes, are the
binding constraint. Fields the device app writes and the data field cannot: `discipline`(20)
as a string (16 B and a scarce slot), `longest_flight_m`(25), `best_5x10s`(28)…`alpha500_lite`
(31), every takeoff/pump field (35–38) and every LAP field (10–16).

### What a parser needs (source class **d**)

- **Recognition:** `session.sport == 43` **and** `discipline_id == 1` (field 53). The device
  app's class-(a) marker is the `discipline` *string* (field 20) — a class-d file has the enum
  instead, never both. Presence of field 54 (`cfg_pack`) is a second, equivalent tell.
- **No laps of ours.** The native activity's laps are the user's own button presses; they are
  *not* flight boundaries. Flight segmentation must be re-derived from `foil_state`(0) or from
  speed. (Class (a): laps alternate flight/off-foil and are hints.)
- **No accelerometer stream and no pump metrics, ever.** Every `Toybox.Sensor` entry point —
  `registerSensorDataListener`, `enableSensorEvents`, `getInfo`, `enableSensorType`,
  `getMaxSampleRate` — is documented in the fenix 8 `api.debug.xml` as *"Will cause an app
  crash if called from a data field app"*, and `SensorLogging` cannot be attached to a session
  the app does not own. So takeoff/pump analysis degrades to "unknown" (null, never 0), exactly
  like source class (b).
- **Barometric submersion evidence exists**: `Activity.Info.rawAmbientPressure` /
  `ambientPressure` are available to data fields, so turn outcomes still distinguish
  touchdown from fell-in.
- **Unpack** 50 and 54 with the shifts above before comparing them to class-(a) fields; then
  `turn_outcomes` maps to the same flew/touchdown/fell tallies the phone derives from the
  record-level `turn_marker` values 4–6, and `cfg_pack` to the same three thresholds.

## Parsing rules (phone/lab)

- Missing developer fields ⇒ source class (b)/(c); never fail the parse (`SourceCapabilities` fail-soft).
- Developer fields present but `discipline_id`(53) instead of `discipline`(20) ⇒ source class
  (d), the data-field variant: no laps of ours, no accel, packed fields 50/54.
- `session.sport == 43` alone does NOT mean wingfoil — require `discipline == "wingfoil"` to
  distinguish from Jan's real windsurf sessions.
- Watch lap boundaries are hints; the phone's `FlightSegmenter` output is authoritative.
- intervals.icu shows session-level developer fields as empty — expected; user-facing GC display
  uses the `displayInActivitySummary` flags, our pipeline reads the raw FIT.
