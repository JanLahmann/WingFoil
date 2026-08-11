import Toybox.Application;
import Toybox.Application.Properties;
import Toybox.Lang;
import WingFoilCore;

// The data field's settings source (resources/settings/*.xml, edited in Garmin Connect
// Mobile). It fills the same WingFoilCore.Config the device app's AppSettings fills, and the
// barrel detectors read nothing else — that is the whole point of the extraction.
//
// Only the detector-relevant settings exist here. The device app's sport choice, accel
// logging and vibration alerts have no meaning in a data field: the native activity owns the
// sport, Sensor.* crashes a data field, and alerts would need DataFieldAlert + a view.
// Defaults mirror docs/algorithms.md — change both together.
module FieldSettings {
    var cfg as WingFoilCore.Config = new WingFoilCore.Config();

    function load() as Void {
        cfg.foilEntryMps = _num("foilEntryKmh", 12.0) / 3.6;
        cfg.foilExitMps = _num("foilExitKmh", 8.0) / 3.6;
        cfg.entryHoldS = _num("entryHoldS", 2.0).toNumber();
        cfg.exitHoldS = _num("exitHoldS", 3.0).toNumber();
        cfg.minFlightS = _num("minFlightS", 5.0).toNumber();
        cfg.useKnots = _bool("useKnots", false);
        cfg.setWindDirection(_num("windDirDeg", -1.0).toNumber());
        cfg.sanitize();
    }

    function _num(key as String, dflt as Float) as Float {
        try {
            var v = Properties.getValue(key);
            if (v instanceof Lang.Number || v instanceof Lang.Float) {
                return v.toFloat();
            }
        } catch (e) {
        }
        return dflt;
    }

    function _bool(key as String, dflt as Boolean) as Boolean {
        try {
            var v = Properties.getValue(key);
            if (v instanceof Lang.Boolean) {
                return v;
            }
        } catch (e) {
        }
        return dflt;
    }
}
