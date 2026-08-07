import Toybox.ActivityRecording;
import Toybox.FitContributor;
import Toybox.Lang;

// Sole writer of FIT developer fields. Field IDs/types are the docs/fit-schema.md contract —
// change both together. W1 scope: record 0+4, session 20-27 + 40-43.
class FitFields {
    const SCHEMA_VERSION = 1;
    const APP_MINOR = 1;

    hidden var _foilState as FitContributor.Field;
    hidden var _tick as FitContributor.Field;
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
        _tick = session.createField("tick", 4, FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_RECORD});

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
        _tick.setData(0);
    }

    hidden function _cms(mps as Float) as Number {
        var v = (mps * 100.0).toNumber();
        return v < 0 ? 0 : (v > 65535 ? 65535 : v);
    }

    // Called every engine tick (values persist at last level between writes).
    function setRecord(foilState as Number, tick as Number) as Void {
        _foilState.setData(foilState);
        // 0xFF is FIT's uint8 invalid sentinel -- roll 0-254 so no tick decodes as absent.
        _tick.setData(tick % 255);
    }

    // Called continuously while recording (session msg is written once at save with last values).
    function updateSession(detector as FlightDetector, records as SpeedRecords,
            timerS as Float) as Void {
        _foilTime.setData(detector.foilTimeS.toNumber());
        var pct = timerS > 0 ? (detector.foilTimeS / timerS * 100.0).toNumber() : 0;
        _foilPct.setData(pct > 100 ? 100 : pct);
        _flightCount.setData(detector.flightCount);
        _longestS.setData(detector.longestS.toNumber());
        _longestM.setData(detector.longestM.toNumber());
        _best2s.setData(_cms(records.best2sMps));
        _best10s.setData(_cms(records.best10sMps));
        _cfgEntry.setData(_cms(AppSettings.foilEntryMps));
        _cfgExit.setData(_cms(AppSettings.foilExitMps));
        _cfgMinFlight.setData(AppSettings.minFlightS);
    }
}
