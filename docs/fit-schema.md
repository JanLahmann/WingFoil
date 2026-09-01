# FIT Developer-Field Schema (contract)

**Single source of truth** for FIT developer fields written by the Garmin app and read by
`WingFoilKit/FitImport` and `lab/src/wingfoil_lab/parse.py`. Any change here bumps
`SCHEMA_VERSION` and must be reflected in all three implementations plus
`garmin/resources/fitcontributions/fit_contributions.xml`.

> ## ⚠️ HARD LIMIT: 16 developer fields per message type
>
> Measured on `fenix847mm`, **undocumented**, and applies to device apps and data fields
> alike. Exceeding it is **not a catchable exception** — the runtime kills the app with
> `Out Of Memory Error: New Field out of memory for FIT data`, or, from inside a loop, the
> unhelpful `System Error: Failed invoking <symbol>`. Shipped beta **0.5.0 crashed on every
> START** because its session message declared 20 fields; the 17th `createField` killed it.
>
> There is a byte budget too (256 B per message type for a device app, **32 B** for a data
> field), but for any schema built from small fields **the field count binds first**. That is
> why this schema bit-packs: `cfg_pack`(54), `takeoff_pack`(55), `longest_pack`(56) and the
> field variant's `turn_outcomes`(50) each spend one scarce slot instead of two or three.
>
> Both limits are asserted by unit tests over the single declaring table in each app —
> `garmin/source/fit/FitSchema.mc` (device app) and `garmin/field/source/SessionPack.mc`
> (data field). **Never call `createField` outside those tables.** A new field means a new
> row; if it does not fit, a test fails instead of a watch.

- `SCHEMA_VERSION`: **2** (carried in session field `app_version`, low byte = schema version)
- Developer data index: 0 (single developer)
- Field ID convention: **record 0–9 · lap 10–19 · session 20–49**
- All speeds: `uint16` in **cm/s** (0–655.35 m/s). Convert for display (kn = m/s × 1.9438445).
- Budgets (CIQ device app): 256 B **and 16 fields** per message type. Used: record 4 fields /
  4 B · lap 2 fields / 2 B · session **16 fields / 50 B** — *at* the field limit since app
  0.9.0 added `wind_dir_auto`(44). The headroom v2's packing bought back is spent, so **the
  next session field must pack**; see the box above and `FitSchema.SESSION_FIELD_TARGET`.
  The **data-field variant** (`garmin/field/`) has a far tighter budget and its own compact
  session schema — see "Field-variant FIT (class d)" below.
- Recording activity: `sport = 43 (windsurfing)`, `subSport = 0 (generic)`, session name `"Wingfoil"`.
  The session-level `discipline` string is the authoritative discipline tag, NOT the sport code.

## RECORD messages (written at 1 Hz) — 6 bytes budgeted, 4 B written

The device app writes `foil_state`(0) · `pump_cadence`(2) · `turn_marker`(3) · `tick`(4).
`flight_index`(1) is reserved but not written — laps already carry the flight structure.

| fieldId | name | type | units | enum / scale | GC render | notes |
|---|---|---|---|---|---|---|
| 0 | `foil_state` | uint8 | — | 0 = off-foil · 1 = pumping/attempt · 2 = flying | chart | drives phase coloring |
| 1 | `flight_index` | uint16 | count | 0 = not in flight, N = Nth flight (1-based) | — | joins records↔flights |
| 2 | `pump_cadence` | uint8 | strokes/min | 0 when not pumping / detector off | chart | **watch-written**: `PumpDetector` strokes over the trailing 10 s, rewritten every record. The refractory bounds it at 150; 255 is never written. Phone recomputes it from the raw accel stream |
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

> **Why Garmin Connect's feed card shows "-- Runs / -- longest":** that card reads native
> `split`/`split_summary` messages (FIT 312/313) that only Garmin's own activity apps can
> write — Connect IQ has no API for them, and GC deliberately ignores `:nativeNum`
> (staff-confirmed). Every CIQ windsurf app dashes those slots, and Garmin's own Windsurf
> profile does too in ~30% of real sessions (verified across the fixture corpus,
> 2026-09-01). Our per-run data lives in the developer fields on the activity detail page.
> The one improvable gap: `longest_flight_m` is bit-packed (field 56) and packed fields get
> no GC summary row — unpacking it costs a 17th session field against the 16-field limit.

## SESSION message (written once at save) — **schema v2**: 16 fields / 50 bytes

The binding constraint is the **16-field limit** (see the box at the top), not the 256 B
budget. v2 folds eight small v1 fields into three packed uint32s, which bought back one field
of headroom; app 0.9.0 spent it on `wind_dir_auto`(44). Declared in one place:
`garmin/source/fit/FitSchema.mc`.

### v2 — what the app writes today

| fieldId | name | type | units | GC render | notes |
|---|---|---|---|---|---|
| 20 | `discipline` | string(16) | — | — | `"wingfoil"` (settings may later allow `"windfoil"` etc.) |
| 21 | `foil_time` | uint32 | s | summary | |
| 22 | `foil_pct` | uint8 | % | summary | of timer time |
| 23 | `flight_count` | uint16 | count | summary | |
| 26 | `best_2s` | uint16 | cm/s | summary | shown in kn |
| 27 | `best_10s` | uint16 | cm/s | — | |
| 28 | `best_5x10s` | uint16 | cm/s | summary | mean of best 5 disjoint 10 s windows |
| 29 | `best_500m` | uint16 | cm/s | summary | |
| 30 | `best_nm` | uint16 | cm/s | — | 1852 m; 0 = no qualifying run |
| 31 | `alpha500_lite` | uint16 | cm/s | — | watch approximation; phone computes exact |
| 32 | `tack_count` | uint8 | count | summary | written only when the wind axis was set; saturates at 254 |
| 33 | `jibe_count` | uint8 | count | summary | as `tack_count` |
| 34 | `turn_success_pct` | uint8 | % | summary | successful / attempted turns (score ≥ `turnSuccessPct` and never off the foil), over *all* counted turns including the generic ones |
| 38 | `total_pump_strokes` | uint16 | strokes | — | **watch-written**: strokes in qualifying bursts (≥ `pumpMinStrokes`, burst peak ≥ `pumpBurstPeakG`, speed ≥ `pumpMinSpeedKmh` — engine ≥ 0.8.0's rules, live-approximated). Watches on app ≤ 0.9.2 still write every detected peak; the phone recomputes and is authoritative |
| 39 | `wind_dir_user` | uint16 | deg | — | the axis the **RIDER** set: direction the wind blows **from**, true; 65535 = unset. Set in GCM (`windDirDeg`) or on the watch (BACK → Session → Wind, 16 compass points). The value written is the one in effect at save; the watch classifies only turns detected *after* it was set, so a mid-session change can leave earlier turns generic — the phone re-runs classification over the whole track and is authoritative |
| 44 | `wind_dir_auto` | uint16 | deg | — | the axis the **WATCH** estimated for itself (device app ≥ 0.9.0, docs/algorithms.md "Watch approximation: auto wind"); 65535 = the estimator never locked or was switched off. Same units and meaning as 39, and deliberately a *separate* field: one is the rider's word and the other an inference from an hour of course headings, and only the first may be shown as fact. Either, both or neither may be present — both means the rider set an axis part-way through a session the watch had already estimated |
| 43 | `app_version` | uint16 | — | — | high byte = app minor version, low byte = SCHEMA_VERSION |
| 54 | `cfg_pack` | uint32 | — | — | **packed v2**, replaces 40/41/42. `entry_cms << 16 \| minFlight_s << 11 \| exit_cms` (entry 16 b cm/s · minFlight 5 b s 0–31 · exit 11 b cm/s 0–2047). Byte-for-byte the class-(d) encoding, so one unpacker serves both |
| 55 | `takeoff_pack` | uint32 | — | — | **packed v2**, replaces 35/36/37. `avgPumps_x10 << 16 \| attempts << 8 \| successes`, each a byte the `PumpDetector` saturates at 254 |
| 56 | `longest_pack` | uint32 | — | — | **packed v2**, replaces 24/25. `seconds << 16 \| metres`, each clamped to 65535 (18 h / 65 km in one flight — unreachable) |

Fields 28–31 (`best_5x10s`, `best_500m`, `best_nm`, `alpha500_lite`) are **reserved, not
written**: the phone computes them exactly and there is no field slot to spare.

**`tack_count`/`jibe_count` are written only when a wind axis was in effect — of EITHER
kind.** Naming a sweep a tack or a jibe needs a wind direction. Until device app 0.9.0 the
watch had exactly one source for one, the bearing the rider entered by hand
(`wind_dir_user`); since 0.9.0 it can also estimate one and writes that in `wind_dir_auto`
(docs/algorithms.md "Watch approximation: auto wind"). With neither, every turn it detects
stays generic. A **`0`/`0` pair with no `wind_dir_user` and no `wind_dir_auto`** — which is
what older builds wrote in that case, having no way to say "unknown" in a uint8 — therefore
means *unclassified*, not *none*, and the parser (`FitSessionParser.watchSummary`) treats the
pair as **absent**: it leaves `WatchSummary.tackCount`/`.jibeCount` nil so the divergence
check has nothing to compare. Reading them as literal zeros produced banners like "Jibes:
watch 0 vs phone 50" for a session of fifty clean jibes, which is docs/presentation.md's
missing-is-absent-never-0 rule being broken at the source. The demotion is deliberately
narrow: one non-zero count, or *either* wind field at all, means an axis **was** in effect,
and a 0 is then a real observation that still compares. (Both wind fields also read 65535 as
absent rather than as a bearing — the schema's sentinel is not a wind from 65535°.)

**The watch side of that rule (device app ≥ 0.8.0, widened in 0.9.0).**
`FitFields.updateSession` simply does not call `setData` on 32, 33, 39 or 44 unless a wind
axis was in effect at some point in the session, and a developer field that is never written
is not emitted — so new files carry the four fields **absent** rather than as a
`0`/`0`/`65535`/`65535` quadruple, which is what the paragraph above has to reconstruct for
older files. The gate is `AppSettings.windEverSet || AppSettings.autoWindEverSet`, both flags
sticky on purpose: a rider who sets the axis and later clears it has genuinely classified
turns, so the counts stay and only the axis falls back to its unset sentinel. When the gate
opens, **both** wind fields go out together, each carrying 65535 when that source had none —
so a reader can always tell which axis the counts were made on. Asserted by
`fitOmitsTurnCountsWhenNoWindAxisWasSet` and `manualWindAlwaysBeatsTheEstimate` in
`garmin/tests/WingfoilTests.mc`.

### v1 — historical, for files written by app ≤ 0.5.0

Beta 0.5.0 declared these as separate fields and **never recorded a single session** — the
20-field session message crashed the app on START (see the box at the top), so in practice
only pre-0.5.0 corpus files carry them. Parsers must still read them: the whole fixture corpus
is v1.

| fieldId | name | type | units | v2 replacement |
|---|---|---|---|---|
| 24 | `longest_flight_s` | uint16 | s | `longest_pack`(56) bits 31–16 |
| 25 | `longest_flight_m` | uint32 | m | `longest_pack`(56) bits 15–0 |
| 35 | `takeoff_attempts` | uint8 | count | `takeoff_pack`(55) bits 15–8 |
| 36 | `takeoff_successes` | uint8 | count | `takeoff_pack`(55) bits 7–0 |
| 37 | `avg_pumps_to_takeoff` | uint8 | strokes ×0.1 | `takeoff_pack`(55) bits 23–16 |
| 40 | `cfg_entry_speed` | uint16 | cm/s | `cfg_pack`(54) bits 31–16 |
| 41 | `cfg_exit_speed` | uint16 | cm/s | `cfg_pack`(54) bits 10–0 |
| 42 | `cfg_min_flight` | uint8 | s | `cfg_pack`(54) bits 15–11 |

Semantics are unchanged — `takeoff_attempts` is still successes + failed efforts,
`avg_pumps_to_takeoff` is still ×0.1 — only the carrier changed.

### The parser compatibility rule (all three implementations)

**Presence decides; `app_version` only corroborates.** Never gate on the schema version
alone: class-(d) files carry `cfg_pack` under schema v1, and a file may have no `app_version`
at all.

1. Read the v1 field names as before.
2. For each packed field **present and integer-valued**, unpack it and write the *same
   internal names and units* the v1 fields used. A packed field **wins** over a v1 field of
   the same meaning if both appear.
3. Never fail on a missing or malformed packed field — fail-soft, like the rest of the parser.

The result is that a v1 file and the equivalent v2 file parse to an **identical** internal
representation, so nothing downstream of the parser knows the schema changed. This is asserted
directly on the iOS side (`WatchSummary` is `Equatable`; the v1 and v2 summaries compare equal).

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
| 43 | `app_version` | uint16 | 2 | high byte app minor, low byte `SCHEMA_VERSION` — still **1** here: the class-(d) schema below is unchanged by the device app's v1→v2 packing, and it was already packed. This is exactly why a parser keys off field *presence*, not the version number |
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
