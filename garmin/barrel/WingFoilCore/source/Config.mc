import Toybox.Lang;

module WingFoilCore {

// 16-point compass labels, module scope so both UIs can walk them (class consts are
// instance-scoped in Monkey C and cannot be read off the class).
const COMPASS = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
    "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"] as Array<String>;

// The detector thresholds, as a plain injected object.
//
// The detectors used to read a device-app `AppSettings` module directly, which welded the
// core to one app's settings source. They now take a Config in initialize(): the device app
// fills one from Application.Properties (garmin/source/settings/AppSettings.mc), the data
// field fills one from its own properties (garmin/field/source/FieldSettings.mc), and unit
// tests fill one by hand. Defaults mirror docs/algorithms.md — change both together.
class Config {
    var foilEntryMps as Float = 3.33;   // 12 km/h
    var foilExitMps as Float = 2.22;    // 8 km/h
    var entryHoldS as Number = 2;
    var exitHoldS as Number = 3;
    var minFlightS as Number = 5;
    var useKnots as Boolean = false;
    // Wind direction the wind blows FROM, degrees true. -1 = unset: turns stay generic
    // (no tack/jibe split).
    var windDirection as Number = -1;

    function initialize() {
    }

    // Normalizes the wind axis. Anything outside 0-359 means "unset".
    // Only turns detected from here on are classified — no retro pass on the watch.
    function setWindDirection(deg as Number) as Void {
        windDirection = (deg < 0 || deg > 359) ? -1 : deg;
    }

    // Hysteresis sanity: exit must sit below entry, whatever the settings source said.
    function sanitize() as Void {
        if (foilExitMps >= foilEntryMps) {
            foilExitMps = foilEntryMps - 0.5;
        }
    }

    // ---- display helpers (both UIs need the same unit maths) ----

    function speedLabel() as String {
        return useKnots ? "kn" : "km/h";
    }

    function speedToDisplay(mps as Float) as Float {
        return useKnots ? mps * 1.9438445 : mps * 3.6;
    }

    // 16-point label for the wind axis; "--" when unset.
    function windLabel() as String {
        if (windDirection < 0) {
            return "--";
        }
        var i = ((windDirection + 11.25) / 22.5).toNumber() % 16;
        return COMPASS[i];
    }
}

}
