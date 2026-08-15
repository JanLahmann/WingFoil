import Toybox.Application;
import Toybox.Application.Properties;
import Toybox.Lang;
import WingFoilCore;

// Cached, typed access to GCM-editable settings (resources/settings/*.xml).
// Defaults mirror docs/algorithms.md — change both together.
//
// The detector thresholds live in `cfg`, a WingFoilCore.Config handed to the barrel
// detectors at construction. This module is the device app's settings SOURCE; the data field
// has its own (garmin/field/source/FieldSettings.mc) and the barrel knows about neither.
// App-only settings (sport, accel logging, alert toggles) stay here.
module AppSettings {
    var cfg as WingFoilCore.Config = new WingFoilCore.Config();

    var sportChoice as Number = 0;      // 0 windsurf(43), 1 kitesurf(44), 2 generic
    var accelLogging as Boolean = true;     // raw accel into the FIT (phone/lab validation)
    var pumpDetection as Boolean = true;    // live PumpDetector (a second accel consumer)
    var alertPb as Boolean = true;
    var alertFlight as Boolean = true;
    var alertTurn as Boolean = true;
    var alertTakeoff as Boolean = true;
    var alertIntervalMin as Number = 0;     // 0 = off
    var alertIntervalKm as Float = 0.0;     // 0 = off
    var autoPause as Boolean = false;
    var autoPauseDelayS as Number = 5;
    // Phase-5 companion link: push a summary card to the paired iPhone app after a save.
    // Default OFF until the BLE hop has been proven on real hardware. The push costs a few
    // hundred bytes once per session and the FIT arrives regardless, so the feature earns its
    // default-on the moment it works — but `Communications.transmit` has never run against a
    // real phone from this code, and the fenix 7 family has already shown (see PhoneLink.mc)
    // that an unexercised Communications call can take the whole app down with no error at
    // all. Testers should not be the ones to discover that. Flip it on in Garmin Connect to
    // test the link deliberately.
    var phonePush as Boolean = false;
    // Cells draw a glyph for the metric family; this decides whether the XTINY word stays
    // beside it. Off = glyph only, which buys the value row its width back on the tight
    // bottom row of a 2x2 grid.
    var showLabels as Boolean = true;

    function load() as Void {
        cfg.foilEntryMps = _num("foilEntryKmh", 12.0) / 3.6;
        cfg.foilExitMps = _num("foilExitKmh", 8.0) / 3.6;
        cfg.entryHoldS = _num("entryHoldS", 2.0).toNumber();
        cfg.exitHoldS = _num("exitHoldS", 3.0).toNumber();
        cfg.minFlightS = _num("minFlightS", 5.0).toNumber();
        cfg.useKnots = _bool("useKnots", false);
        sportChoice = _num("sportChoice", 0.0).toNumber();
        accelLogging = _bool("accelLogging", true);
        pumpDetection = _bool("pumpDetection", true);
        alertPb = _bool("alertPb", true);
        alertFlight = _bool("alertFlight", true);
        alertTurn = _bool("alertTurn", true);
        alertTakeoff = _bool("alertTakeoff", true);
        alertIntervalMin = _num("alertIntervalMin", 0.0).toNumber();
        alertIntervalKm = _num("alertIntervalKm", 0.0);
        autoPause = _bool("autoPause", false);
        autoPauseDelayS = _num("autoPauseDelayS", 5.0).toNumber();
        showLabels = _bool("showLabels", true);
        phonePush = _bool("phonePush", false);
        if (autoPauseDelayS < 2) {
            autoPauseDelayS = 2;
        }
        cfg.setWindDirection(_num("windDirDeg", -1.0).toNumber());
        // hysteresis sanity: exit must sit below entry
        cfg.sanitize();
    }

    // Normalizes and persists the wind axis. Anything outside 0-359 means "unset".
    // Only turns detected from here on are classified — no retro pass on the watch.
    function storeWindDirection(deg as Number) as Void {
        cfg.setWindDirection(deg);
        try {
            Properties.setValue("windDirDeg", cfg.windDirection);
        } catch (e) {
        }
    }

    const COMPASS = WingFoilCore.COMPASS;

    // 16-point label for a bearing; "--" when unset.
    function windLabel() as String {
        return cfg.windLabel();
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
        return cfg.speedLabel();
    }

    function speedToDisplay(mps as Float) as Float {
        return cfg.speedToDisplay(mps);
    }
}
