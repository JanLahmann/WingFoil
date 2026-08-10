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
    var alertTurn as Boolean = true;
    // Wind direction the wind blows FROM, degrees true. -1 = unset: turns stay generic
    // (no tack/jibe split). Settable in GCM or on the watch (BACK -> Session -> Wind).
    var windDirection as Number = -1;

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
        alertTurn = _bool("alertTurn", true);
        setWindDirection(_num("windDirDeg", -1.0).toNumber());
        // hysteresis sanity: exit must sit below entry
        if (foilExitMps >= foilEntryMps) {
            foilExitMps = foilEntryMps - 0.5;
        }
    }

    // Normalizes and persists the wind axis. Anything outside 0-359 means "unset".
    // Only turns detected from here on are classified — no retro pass on the watch.
    function setWindDirection(deg as Number) as Void {
        windDirection = (deg < 0 || deg > 359) ? -1 : deg;
    }

    function storeWindDirection(deg as Number) as Void {
        setWindDirection(deg);
        try {
            Properties.setValue("windDirDeg", windDirection);
        } catch (e) {
        }
    }

    const COMPASS = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
        "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"] as Array<String>;

    // 16-point label for a bearing; "--" when unset.
    function windLabel() as String {
        if (windDirection < 0) {
            return "--";
        }
        var i = ((windDirection + 11.25) / 22.5).toNumber() % 16;
        return COMPASS[i];
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
