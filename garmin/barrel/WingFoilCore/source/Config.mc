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
    // The wind axis the turn classifier actually uses: degrees the wind blows FROM,
    // -1 = unset (turns stay generic, no tack/jibe split).
    //
    // It is DERIVED, never assigned from outside. Two sources feed it and the precedence
    // between them is the whole rule: **manual always wins**. A bearing the rider entered by
    // hand (watch menu, GCM, or the phone's push) is a statement of fact; the on-watch
    // estimate is an inference from an hour of course headings, and an inference must never
    // overwrite a fact — least of all silently, mid-session, on a rider who set the axis
    // precisely because he did not trust a guess.
    var windDirection as Number = -1;
    var windManual as Number = -1;      // rider-entered, -1 = unset
    var windAuto as Number = -1;        // AutoWind's adopted estimate, -1 = nothing adopted

    function initialize() {
    }

    // Normalizes the MANUAL wind axis. Anything outside 0-359 means "unset".
    // Only turns detected from here on are classified — no retro pass on the watch.
    function setWindDirection(deg as Number) as Void {
        windManual = (deg < 0 || deg > 359) ? -1 : deg;
        _resolveWind();
    }

    // The on-watch estimate. Fills the axis only while no manual bearing is set; setting one
    // afterwards takes over instantly, and clearing it hands the axis back to the estimate.
    function setAutoWind(deg as Number) as Void {
        windAuto = (deg < 0 || deg > 359) ? -1 : deg;
        _resolveWind();
    }

    // Is the axis in effect an ESTIMATE? Everything that displays a wind bearing marks it
    // with a leading "~" when this is true, because an estimate the rider cannot tell from a
    // measurement is worse than no estimate at all.
    function windIsAuto() as Boolean {
        return windManual < 0 && windAuto >= 0;
    }

    hidden function _resolveWind() as Void {
        windDirection = windManual >= 0 ? windManual : windAuto;
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

    // 16-point label for the wind axis, marked "~" when it is the watch's own estimate;
    // "--" when unset. E.g. "NW" (rider said so) vs "~NW" (the watch worked it out).
    function windLabel() as String {
        return windMark() + compassLabel();
    }

    // The estimate mark on its own, for the call sites that print the bearing in degrees and
    // would otherwise carry the "~" twice (the start screen's "wind ~200° SSW").
    function windMark() as String {
        return windIsAuto() ? "~" : "";
    }

    // Unmarked 16-point label; "--" when unset.
    function compassLabel() as String {
        if (windDirection < 0) {
            return "--";
        }
        var i = ((windDirection + 11.25) / 22.5).toNumber() % 16;
        return COMPASS[i];
    }
}

}
