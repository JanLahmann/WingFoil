import Toybox.ActivityRecording;
import Toybox.FitContributor;
import Toybox.Lang;
import WingFoilCore;

// Sole writer of FIT developer fields. Field IDs/types are the docs/fit-schema.md contract —
// change both together. Scope: record 0+3+4, lap 15-16, session 20-27 + 32-34 + 39-43.
class FitFields {
    const SCHEMA_VERSION = 1;
    const APP_MINOR = 1;

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

    hidden var _foilState as FitContributor.Field;
    hidden var _turnMarker as FitContributor.Field;
    hidden var _tick as FitContributor.Field;
    hidden var _lapTurns as FitContributor.Field;
    hidden var _lapBestScore as FitContributor.Field;
    hidden var _tackCount as FitContributor.Field;
    hidden var _jibeCount as FitContributor.Field;
    hidden var _turnSuccess as FitContributor.Field;
    hidden var _windDir as FitContributor.Field;
    hidden var _discipline as FitContributor.Field;
    hidden var _foilTime as FitContributor.Field;
    hidden var _foilPct as FitContributor.Field;
    hidden var _flightCount as FitContributor.Field;
    hidden var _longestS as FitContributor.Field;
    hidden var _longestM as FitContributor.Field;
    hidden var _best2s as FitContributor.Field;
    hidden var _best10s as FitContributor.Field;
    hidden var _cfgEntry as FitContributor.Field;
    hidden var _cfgExit as FitContributor.Field;
    hidden var _cfgMinFlight as FitContributor.Field;
    hidden var _appVersion as FitContributor.Field;

    function initialize(session as ActivityRecording.Session) {
        _foilState = session.createField("foil_state", 0, FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_RECORD});
        _turnMarker = session.createField("turn_marker", 3, FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_RECORD});
        _tick = session.createField("tick", 4, FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_RECORD});

        _lapTurns = session.createField("turn_count", 15, FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_LAP});
        _lapBestScore = session.createField("best_turn_score", 16,
            FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "%"});

        _discipline = session.createField("discipline", 20, FitContributor.DATA_TYPE_STRING,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :count => 16});
        _foilTime = session.createField("foil_time", 21, FitContributor.DATA_TYPE_UINT32,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "s"});
        _foilPct = session.createField("foil_pct", 22, FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "%"});
        _flightCount = session.createField("flight_count", 23, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_SESSION});
        _longestS = session.createField("longest_flight_s", 24, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "s"});
        _longestM = session.createField("longest_flight_m", 25, FitContributor.DATA_TYPE_UINT32,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "m"});
        _best2s = session.createField("best_2s", 26, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "cm/s"});
        _best10s = session.createField("best_10s", 27, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "cm/s"});
        _tackCount = session.createField("tack_count", 32, FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_SESSION});
        _jibeCount = session.createField("jibe_count", 33, FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_SESSION});
        _turnSuccess = session.createField("turn_success_pct", 34,
            FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "%"});
        _windDir = session.createField("wind_dir_user", 39, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "deg"});
        _cfgEntry = session.createField("cfg_entry_speed", 40, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "cm/s"});
        _cfgExit = session.createField("cfg_exit_speed", 41, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "cm/s"});
        _cfgMinFlight = session.createField("cfg_min_flight", 42, FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "s"});
        _appVersion = session.createField("app_version", 43, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_SESSION});

        _discipline.setData("wingfoil");
        _appVersion.setData(APP_MINOR * 256 + SCHEMA_VERSION);
        _foilState.setData(0);
        _turnMarker.setData(MARK_NONE);
        _tick.setData(0);
        _lapTurns.setData(0);
        _lapBestScore.setData(0);
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

    hidden function _cms(mps as Float) as Number {
        var v = (mps * 100.0).toNumber();
        return v < 0 ? 0 : (v > 65535 ? 65535 : v);
    }

    // Called every engine tick (values persist at last level between writes) — turnMarker is
    // therefore rewritten every second, so a marker marks exactly its own second.
    function setRecord(foilState as Number, tick as Number, turnMarker as Number) as Void {
        _foilState.setData(foilState);
        _turnMarker.setData(turnMarker);
        // 0xFF is FIT's uint8 invalid sentinel -- roll 0-254 so no tick decodes as absent.
        _tick.setData(tick % 255);
    }

    // Called just before addLap(): the lap message takes the values set at that moment.
    function setLap(turns as TurnDetector) as Void {
        _lapTurns.setData(turns.lapTurnCount > 254 ? 254 : turns.lapTurnCount);
        _lapBestScore.setData(turns.lapBestScorePct);
    }

    // Called continuously while recording (session msg is written once at save with last values).
    function updateSession(detector as FlightDetector, records as SpeedRecords,
            timerS as Float, turns as TurnDetector) as Void {
        _foilTime.setData(detector.foilTimeS.toNumber());
        var pct = timerS > 0 ? (detector.foilTimeS / timerS * 100.0).toNumber() : 0;
        _foilPct.setData(pct > 100 ? 100 : pct);
        _flightCount.setData(detector.flightCount);
        _longestS.setData(detector.longestS.toNumber());
        _longestM.setData(detector.longestM.toNumber());
        _best2s.setData(_cms(records.best2sMps));
        _best10s.setData(_cms(records.best10sMps));
        _tackCount.setData(turns.tackCount > 254 ? 254 : turns.tackCount);
        _jibeCount.setData(turns.jibeCount > 254 ? 254 : turns.jibeCount);
        _turnSuccess.setData(turns.successPct());
        // 65535 = unset, per docs/fit-schema.md session field 39
        _windDir.setData(AppSettings.cfg.windDirection < 0 ? 65535 : AppSettings.cfg.windDirection);
        _cfgEntry.setData(_cms(AppSettings.cfg.foilEntryMps));
        _cfgExit.setData(_cms(AppSettings.cfg.foilExitMps));
        _cfgMinFlight.setData(AppSettings.cfg.minFlightS);
    }
}
