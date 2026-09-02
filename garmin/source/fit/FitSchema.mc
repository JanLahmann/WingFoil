import Toybox.FitContributor;
import Toybox.Lang;

// The DEVICE APP's developer-field schema, in one table. `FitFields` creates every field by
// walking this table and nothing else, so the table *is* the schema — adding a field means
// adding a row, and a row that breaks a platform limit fails a unit test instead of the app.
//
// WHY THIS TABLE EXISTS (schema v1 -> v2). v1 declared 20 SESSION developer fields. The
// runtime accepts **16 developer fields per message type** — an undocumented limit, measured
// on fenix847mm with a probe build (see garmin/field/source/SessionPack.mc for the full
// measurement) and *not* a catchable exception: the 17th `createField` killed the app on START
// with "System Error: Failed invoking <symbol>". Shipped beta 0.5.0 crashed the moment the
// user pressed START, every time.
//
// v2 buys the headroom back by bit-packing three groups of small fields into three uint32s,
// the same trick and the same 54 `cfg_pack` encoding the data-field variant already uses:
//     40 + 41 + 42            -> 54 `cfg_pack`      entry_cms<<16 | minFlight_s<<11 | exit_cms
//     35 + 36 + 37            -> 55 `takeoff_pack`  avgPumpsX10<<16 | attempts<<8 | successes
//     24 + 25                 -> 56 `longest_pack`  seconds<<16 | metres
// SESSION was then 15 fields / 48 B: one field of headroom under the hard limit.
//
// App 0.9.0 spends it. `wind_dir_auto`(44) carries the axis the watch worked out for itself
// (docs/algorithms.md "Watch approximation: auto wind") beside `wind_dir_user`(39), which
// stays exactly what it always was: the bearing the RIDER entered. Two fields rather than one
// because the two are different claims and the phone has to be able to tell them apart —
// a manual axis is a fact, an estimate is an inference, and the divergence check, the wind
// source label and any future re-analysis all care which one a session was classified on.
// SESSION is now 16 fields / 50 B, i.e. AT the limit; see SESSION_FIELD_TARGET.
// RECORD and LAP are unchanged.
module FitSchema {
    // Schema version, carried in the low byte of session field 43 `app_version`. A parser
    // keys its v1-direct vs v2-packed handling off it (docs/fit-schema.md).
    const SCHEMA_VERSION = 2;
    // High byte of session field 43 `app_version`: the device app's MINOR version, i.e. the 8
    // of 0.8.0. It is the app's release number and nothing else — a parser that wants to know
    // which fields exist reads their PRESENCE, and SCHEMA_VERSION in the low byte when it
    // needs to disambiguate an encoding (docs/fit-schema.md).
    const APP_MINOR = 9;
    // The full version string, so "what is this build" has exactly one answer in the source
    // tree. `appVersionMatchesMinor()` in the test suite holds the two together.
    const APP_VERSION = "0.9.5";

    // ---- platform limits (measured, see the header) ----
    // Fields per message type. HARD: exceeding it kills the app, uncatchably.
    const LIMIT_FIELDS = 16;
    // Developer bytes per message type for a device app (docs/plan.md §2).
    const LIMIT_BYTES = 256;
    // The SESSION message is now AT the hard limit: 0.9.0's `wind_dir_auto`(44) spent the
    // field of slack v2 bought back, and there is no slack left.
    //
    // It was spent knowingly. The alternative was to fold 39 + 44 into one `wind_pack` uint32
    // the way 54/55/56 fold their groups, which keeps a slot free but takes `wind_dir_user`
    // off the wire under its own name — a field every parser in the tree, the whole fixture
    // corpus and the bundled example session already carry. Spending the slot changes no
    // existing byte; packing would have changed one that four readers depend on.
    //
    // So: THE NEXT SESSION FIELD MUST PACK. `fits()` still refuses a 17th row and the test
    // still fails before the watch does — what is gone is the warning shot, and this comment
    // is it. The wind pair is the obvious candidate: two uint16s, neither with a Garmin
    // Connect summary row to lose.
    const SESSION_FIELD_TARGET = 16;
    // The 1 Hz record message is also a battery/storage budget, not just a platform one
    // (docs/fit-schema.md: 6 B/s).
    const RECORD_BYTES_TARGET = 6;

    // ---- message types ----
    enum {
        MSG_RECORD = 0,
        MSG_LAP = 1,
        MSG_SESSION = 2,
        MSG_COUNT = 3
    }

    // ---- base types (our codes; `fitDataType` maps them to FitContributor's) ----
    enum {
        T_UINT8 = 0,
        T_UINT16 = 1,
        T_UINT32 = 2,
        T_STRING = 3
    }

    // ---- slots: one per developer field, in creation order ----
    enum {
        REC_FOIL_STATE = 0,     // 0  uint8
        REC_PUMP_CADENCE,       // 2  uint8  spm
        REC_TURN_MARKER,        // 3  uint8
        REC_TICK,               // 4  uint8

        LAP_TURN_COUNT,         // 15 uint8
        LAP_BEST_TURN_SCORE,    // 16 uint8  %

        SES_DISCIPLINE,         // 20 string(16)
        SES_FOIL_TIME,          // 21 uint32 s
        SES_FOIL_PCT,           // 22 uint8  %
        SES_FLIGHT_COUNT,       // 23 uint16
        SES_BEST_2S,            // 26 uint16 cm/s
        SES_BEST_10S,           // 27 uint16 cm/s
        SES_TACK_COUNT,         // 32 uint8
        SES_JIBE_COUNT,         // 33 uint8
        SES_TURN_SUCCESS,       // 34 uint8  %
        SES_PUMP_STROKES,       // 38 uint16
        SES_WIND_DIR,           // 39 uint16 deg (65535 = unset)  — the RIDER's bearing
        SES_WIND_DIR_AUTO,      // 44 uint16 deg (65535 = unset)  — the WATCH's estimate
        SES_APP_VERSION,        // 43 uint16 (minor<<8 | schema)
        SES_CFG_PACK,           // 54 uint32 packed (v2, was 40/41/42)
        SES_TAKEOFF_PACK,       // 55 uint32 packed (v2, was 35/36/37)
        SES_LONGEST_PACK,       // 56 uint32 packed (v2, was 24/25)

        SLOT_COUNT
    }

    // ---- the table: one entry per slot, parallel arrays (Monkey C has no struct const) ----
    const MSGS = [
        MSG_RECORD, MSG_RECORD, MSG_RECORD, MSG_RECORD,
        MSG_LAP, MSG_LAP,
        MSG_SESSION, MSG_SESSION, MSG_SESSION, MSG_SESSION, MSG_SESSION, MSG_SESSION,
        MSG_SESSION, MSG_SESSION, MSG_SESSION, MSG_SESSION, MSG_SESSION, MSG_SESSION,
        MSG_SESSION, MSG_SESSION, MSG_SESSION, MSG_SESSION
    ] as Array<Number>;

    const IDS = [
        0, 2, 3, 4,
        15, 16,
        20, 21, 22, 23, 26, 27, 32, 33, 34, 38, 39, 44, 43, 54, 55, 56
    ] as Array<Number>;

    const NAMES = [
        "foil_state", "pump_cadence", "turn_marker", "tick",
        "turn_count", "best_turn_score",
        "discipline", "foil_time", "foil_pct", "flight_count", "best_2s", "best_10s",
        "tack_count", "jibe_count", "turn_success_pct", "total_pump_strokes",
        "wind_dir_user", "wind_dir_auto", "app_version", "cfg_pack", "takeoff_pack",
        "longest_pack"
    ] as Array<String>;

    const TYPES = [
        T_UINT8, T_UINT8, T_UINT8, T_UINT8,
        T_UINT8, T_UINT8,
        T_STRING, T_UINT32, T_UINT8, T_UINT16, T_UINT16, T_UINT16, T_UINT8, T_UINT8,
        T_UINT8, T_UINT16, T_UINT16, T_UINT16, T_UINT16, T_UINT32, T_UINT32, T_UINT32
    ] as Array<Number>;

    // Wire width in bytes. For T_STRING it is the declared `:count`.
    const WIDTHS = [
        1, 1, 1, 1,
        1, 1,
        16, 4, 1, 2, 2, 2, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4
    ] as Array<Number>;

    // "" = no unit declared.
    const UNITS = [
        "", "spm", "", "",
        "", "%",
        "", "s", "%", "", "cm/s", "cm/s", "", "", "%", "", "deg", "deg", "", "", "", ""
    ] as Array<String>;

    // ---- table queries ----

    function fitMesgType(slot as Number) as Number {
        var m = MSGS[slot];
        if (m == MSG_RECORD) {
            return FitContributor.MESG_TYPE_RECORD;
        }
        return m == MSG_LAP ? FitContributor.MESG_TYPE_LAP
            : FitContributor.MESG_TYPE_SESSION;
    }

    function fitDataType(slot as Number) as FitContributor.DataType {
        var t = TYPES[slot];
        if (t == T_UINT8) {
            return FitContributor.DATA_TYPE_UINT8;
        }
        if (t == T_UINT16) {
            return FitContributor.DATA_TYPE_UINT16;
        }
        return t == T_UINT32 ? FitContributor.DATA_TYPE_UINT32
            : FitContributor.DATA_TYPE_STRING;
    }

    // The options dict `createField` wants for this slot — the one place mesgType/units/count
    // are assembled, so the table cannot disagree with what is actually created.
    function optionsFor(slot as Number) as Dictionary {
        var opts = {:mesgType => fitMesgType(slot)};
        if (!UNITS[slot].equals("")) {
            opts[:units] = UNITS[slot];
        }
        if (TYPES[slot] == T_STRING) {
            opts[:count] = WIDTHS[slot];
        }
        return opts;
    }

    function fieldCount(msg as Number) as Number {
        var n = 0;
        for (var i = 0; i < SLOT_COUNT; i++) {
            if (MSGS[i] == msg) {
                n++;
            }
        }
        return n;
    }

    function byteCount(msg as Number) as Number {
        var n = 0;
        for (var i = 0; i < SLOT_COUNT; i++) {
            if (MSGS[i] == msg) {
                n += WIDTHS[i];
            }
        }
        return n;
    }

    // Every message type inside both limits, and SESSION inside its self-imposed target.
    function fits() as Boolean {
        for (var m = 0; m < MSG_COUNT; m++) {
            if (fieldCount(m) > LIMIT_FIELDS || byteCount(m) > LIMIT_BYTES) {
                return false;
            }
        }
        return fieldCount(MSG_SESSION) <= SESSION_FIELD_TARGET
            && byteCount(MSG_RECORD) <= RECORD_BYTES_TARGET;
    }

    // ---- the three v2 packed fields ----
    //
    // Each folds fields that were separate in v1 into one uint32, because *field slots*, not
    // bytes, are the binding constraint. A v2 reader unpacks these into exactly the v1 names
    // and units, so nothing downstream of the parser changes (docs/fit-schema.md).

    // 54 `cfg_pack` — byte-for-byte the data field's SessionPack.packCfg encoding:
    //     bits 31..16  entry speed, cm/s (0-65535)
    //     bits 15..11  min flight duration, s (0-31)
    //     bits 10..0   exit speed, cm/s (0-2047 = 73 km/h, far above any usable setting)
    function packCfg(entryCms as Number, exitCms as Number, minFlightS as Number) as Number {
        var e = _clamp(entryCms, 65535);
        var x = _clamp(exitCms, 2047);
        var m = _clamp(minFlightS, 31);
        return (e << 16) | (m << 11) | x;
    }

    function cfgEntryCms(p as Number) as Number { return (p >> 16) & 0xFFFF; }
    function cfgMinFlightS(p as Number) as Number { return (p >> 11) & 0x1F; }
    function cfgExitCms(p as Number) as Number { return p & 0x7FF; }

    // 55 `takeoff_pack` — the v1 takeoff triple (35/36/37):
    //     bits 23..16  avg pumps to takeoff, strokes x0.1 (87 = 8.7)
    //     bits 15..8   takeoff attempts
    //     bits 7..0    takeoff successes
    // Each is a byte the detectors already saturate at 254; 255 is not a sentinel here
    // because the field on the wire is a uint32 bit pattern, not a uint8 count.
    function packTakeoff(avgPumpsX10 as Number, attempts as Number,
            successes as Number) as Number {
        return (_clamp(avgPumpsX10, 255) << 16) | (_clamp(attempts, 255) << 8)
            | _clamp(successes, 255);
    }

    function takeoffAvgPumpsX10(p as Number) as Number { return (p >> 16) & 0xFF; }
    function takeoffAttempts(p as Number) as Number { return (p >> 8) & 0xFF; }
    function takeoffSuccesses(p as Number) as Number { return p & 0xFF; }

    // 56 `longest_pack` — the v1 longest-flight pair (24/25):
    //     bits 31..16  duration, s
    //     bits 15..0   distance, m
    // 65535 s is 18 h and 65535 m is 65 km *in a single flight*; neither is reachable.
    function packLongest(seconds as Number, metres as Number) as Number {
        return (_clamp(seconds, 65535) << 16) | _clamp(metres, 65535);
    }

    function longestS(p as Number) as Number { return (p >> 16) & 0xFFFF; }
    function longestM(p as Number) as Number { return p & 0xFFFF; }

    function _clamp(v as Number, hi as Number) as Number {
        return v < 0 ? 0 : (v > hi ? hi : v);
    }
}
