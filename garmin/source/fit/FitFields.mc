import Toybox.ActivityRecording;
import Toybox.FitContributor;
import Toybox.Lang;
import WingFoilCore;

// Sole writer of FIT developer fields. WHAT fields exist is `FitSchema`'s table (the
// docs/fit-schema.md contract); this class only creates them from that table and feeds them
// values. Scope: record 0+2+3+4, lap 15-16, session 20-23 + 26-27 + 32-34 + 38-39 + 43 +
// 54-56.
//
// Schema v2: the session message packs three groups of small fields into three uint32s
// (54/55/56) because the runtime accepts only 16 developer fields per message type and v1's
// 20 crashed the app on START. See FitSchema's header for the whole story.
class FitFields {
    const SCHEMA_VERSION = FitSchema.SCHEMA_VERSION;
    const APP_MINOR = FitSchema.APP_MINOR;

    // record turn_marker enum (docs/fit-schema.md record field 3)
    enum {
        MARK_NONE = 0,
        MARK_TACK = 1,
        MARK_JIBE = 2,
        MARK_TURN = 3,
        MARK_FLEW = 4,
        MARK_TOUCHDOWN = 5,
        MARK_FELL = 6
    }

    // One entry per FitSchema slot, in slot order. Indexed by the SES_*/REC_*/LAP_* enum, so
    // a renamed or reordered row cannot silently write to the wrong field.
    hidden var _f as Array<FitContributor.Field>;

    function initialize(session as ActivityRecording.Session) {
        _f = new Array<FitContributor.Field>[FitSchema.SLOT_COUNT];
        for (var i = 0; i < FitSchema.SLOT_COUNT; i++) {
            _f[i] = session.createField(FitSchema.NAMES[i], FitSchema.IDS[i],
                FitSchema.fitDataType(i), FitSchema.optionsFor(i));
        }

        _f[FitSchema.SES_DISCIPLINE].setData("wingfoil");
        _f[FitSchema.SES_APP_VERSION].setData(APP_MINOR * 256 + SCHEMA_VERSION);
        _f[FitSchema.REC_FOIL_STATE].setData(0);
        _f[FitSchema.REC_PUMP_CADENCE].setData(0);
        _f[FitSchema.REC_TURN_MARKER].setData(MARK_NONE);
        _f[FitSchema.REC_TICK].setData(0);
        _f[FitSchema.LAP_TURN_COUNT].setData(0);
        _f[FitSchema.LAP_BEST_TURN_SCORE].setData(0);
    }

    // Record marker for a TurnDetector event: kind at confirmation, outcome when resolved.
    static function markerFor(turnEvent as Number, kind as Number) as Number {
        if (turnEvent == TurnDetector.EVENT_TURN) {
            return kind;                    // KIND_TACK/JIBE/TURN == MARK_TACK/JIBE/TURN
        }
        if (turnEvent == TurnDetector.EVENT_FLEW) {
            return MARK_FLEW;
        }
        if (turnEvent == TurnDetector.EVENT_TOUCHDOWN) {
            return MARK_TOUCHDOWN;
        }
        if (turnEvent == TurnDetector.EVENT_FELL) {
            return MARK_FELL;
        }
        return MARK_NONE;
    }

    hidden function _u8(v as Number) as Number {
        return v < 0 ? 0 : (v > 254 ? 254 : v);
    }

    hidden function _cms(mps as Float) as Number {
        var v = (mps * 100.0).toNumber();
        return v < 0 ? 0 : (v > 65535 ? 65535 : v);
    }

    // Called every engine tick (values persist at last level between writes) — turnMarker is
    // therefore rewritten every second, so a marker marks exactly its own second.
    function setRecord(foilState as Number, tick as Number, turnMarker as Number,
            pumpCadence as Number) as Void {
        _f[FitSchema.REC_FOIL_STATE].setData(foilState);
        // 0 = not pumping (or no detector); 254 caps a uint8 that can never legitimately
        // exceed ~150 spm anyway (pumpRefractory bounds it at 150).
        _f[FitSchema.REC_PUMP_CADENCE].setData(_u8(pumpCadence));
        _f[FitSchema.REC_TURN_MARKER].setData(turnMarker);
        // 0xFF is FIT's uint8 invalid sentinel -- roll 0-254 so no tick decodes as absent.
        _f[FitSchema.REC_TICK].setData(tick % 255);
    }

    // Called just before addLap(): the lap message takes the values set at that moment.
    function setLap(turns as TurnDetector) as Void {
        _f[FitSchema.LAP_TURN_COUNT].setData(_u8(turns.lapTurnCount));
        _f[FitSchema.LAP_BEST_TURN_SCORE].setData(turns.lapBestScorePct);
    }

    // Called continuously while recording (session msg is written once at save with last values).
    function updateSession(detector as FlightDetector, records as SpeedRecords,
            timerS as Float, turns as TurnDetector, pump as PumpDetector) as Void {
        _f[FitSchema.SES_FOIL_TIME].setData(detector.foilTimeS.toNumber());
        var pct = timerS > 0 ? (detector.foilTimeS / timerS * 100.0).toNumber() : 0;
        _f[FitSchema.SES_FOIL_PCT].setData(pct > 100 ? 100 : pct);
        _f[FitSchema.SES_FLIGHT_COUNT].setData(detector.flightCount);
        _f[FitSchema.SES_BEST_2S].setData(_cms(records.best2sMps));
        _f[FitSchema.SES_BEST_10S].setData(_cms(records.best10sMps));
        _f[FitSchema.SES_TACK_COUNT].setData(_u8(turns.tackCount));
        _f[FitSchema.SES_JIBE_COUNT].setData(_u8(turns.jibeCount));
        _f[FitSchema.SES_TURN_SUCCESS].setData(turns.successPct());
        _f[FitSchema.SES_PUMP_STROKES].setData(pump.strokes > 65534 ? 65534 : pump.strokes);
        // 65535 = unset, per docs/fit-schema.md session field 39
        _f[FitSchema.SES_WIND_DIR].setData(
            AppSettings.cfg.windDirection < 0 ? 65535 : AppSettings.cfg.windDirection);

        // ---- the three v2 packed fields (docs/fit-schema.md session 54/55/56) ----
        // The longest flight, was 24 (s) + 25 (m).
        _f[FitSchema.SES_LONGEST_PACK].setData(FitSchema.packLongest(
            detector.longestS.toNumber(), detector.longestM.toNumber()));
        // Takeoff/pump block, was 35 + 36 + 37. Every counter is a live watch value; the
        // phone recomputes all of them from the raw accel stream and the divergence check
        // compares them.
        _f[FitSchema.SES_TAKEOFF_PACK].setData(FitSchema.packTakeoff(
            pump.avgPumpsX10(), pump.attempts(), pump.successes));
        // The thresholds actually in effect, was 40 + 41 + 42. Same encoding as the data
        // field's SessionPack.packCfg.
        _f[FitSchema.SES_CFG_PACK].setData(FitSchema.packCfg(
            _cms(AppSettings.cfg.foilEntryMps), _cms(AppSettings.cfg.foilExitMps),
            AppSettings.cfg.minFlightS));
    }
}
