import Toybox.Application;
import Toybox.Application.Properties;
import Toybox.Lang;

// Cached, typed access to GCM-editable settings (resources/settings/*.xml).
// Defaults mirror docs/algorithms.md — change both together.
module AppSettings {
    var foilEntryMps as Float = 3.33;   // 12 km/h
    var foilExitMps as Float = 2.22;    // 8 km/h
    var entryHoldS as Number = 2;
    var exitHoldS as Number = 3;
    var minFlightS as Number = 5;
    var useKnots as Boolean = false;
    var sportChoice as Number = 0;      // 0 windsurf(43), 1 kitesurf(44), 2 generic
    var accelLogging as Boolean = true;
    var alertPb as Boolean = true;
    var alertFlight as Boolean = true;

    function load() as Void {
        foilEntryMps = _num("foilEntryKmh", 12.0) / 3.6;
        foilExitMps = _num("foilExitKmh", 8.0) / 3.6;
        entryHoldS = _num("entryHoldS", 2.0).toNumber();
        exitHoldS = _num("exitHoldS", 3.0).toNumber();
        minFlightS = _num("minFlightS", 5.0).toNumber();
        useKnots = _bool("useKnots", false);
        sportChoice = _num("sportChoice", 0.0).toNumber();
        accelLogging = _bool("accelLogging", true);
        alertPb = _bool("alertPb", true);
        alertFlight = _bool("alertFlight", true);
        // hysteresis sanity: exit must sit below entry
        if (foilExitMps >= foilEntryMps) {
            foilExitMps = foilEntryMps - 0.5;
        }
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

    // Display helpers
    function speedLabel() as String {
        return useKnots ? "kn" : "km/h";
    }

    function speedToDisplay(mps as Float) as Float {
        return useKnots ? mps * 1.9438445 : mps * 3.6;
    }
}
