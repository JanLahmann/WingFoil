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

    // Did a wind axis EVER hold a real bearing this run? Sticky, and deliberately not the
    // same question as `cfg.windDirection >= 0`.
    //
    // It gates the FIT's tack_count / jibe_count / wind_dir_user (FitFields.updateSession).
    // Without an axis the classifier calls every sweep a generic turn, so both counters are
    // structurally 0 — and a FIT that says "0 tacks, 0 jibes" is indistinguishable from a
    // session where the rider genuinely never tacked. Absent is the honest encoding, and the
    // phone's parser already treats a missing pair as "unclassified" (docs/fit-schema.md).
    // Sticky rather than live because the counts, once classified, stay meaningful even if
    // the rider clears the axis afterwards.
    var windEverSet as Boolean = false;

    // ---- on-watch automatic wind estimation (device app 0.9.0) ----
    // The feature switch (default ON: it costs a handful of float operations per fix and it is
    // the difference between a session of generic "turns" and a session of tacks and jibes for
    // every rider who forgets the menu), and the rider's declared turn habit, which is the
    // 180-degree tiebreaker on a weak no-go cone. Both mirror the engine
    // (docs/algorithms.md "Default turn type"); `windDefaultTurnType` is the same vocabulary
    // in the same order as `WingFoilCore.TURN_TYPE_*`.
    var autoWind as Boolean = true;
    var windDefaultTurnType as Number = WingFoilCore.TURN_TYPE_JIBES;

    // Did the WATCH'S OWN ESTIMATE ever hold a bearing this run? The sibling of `windEverSet`,
    // kept apart from it on purpose: the two arm the same FIT fields but they are different
    // claims, and only one of them is the rider's word (FitFields.writesTurnCounts).
    var autoWindEverSet as Boolean = false;

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
        if (cfg.windManual >= 0) {
            windEverSet = true;
        }
        autoWind = _bool("autoWind", true);
        windDefaultTurnType = _num("windDefaultTurnType",
            WingFoilCore.TURN_TYPE_JIBES.toFloat()).toNumber();
        if (windDefaultTurnType < WingFoilCore.TURN_TYPE_JIBES
            || windDefaultTurnType > WingFoilCore.TURN_TYPE_BALANCED) {
            windDefaultTurnType = WingFoilCore.TURN_TYPE_JIBES;
        }
        // hysteresis sanity: exit must sit below entry
        cfg.sanitize();
    }

    // Normalizes and persists the wind axis. Anything outside 0-359 means "unset".
    // Only turns detected from here on are classified — no retro pass on the watch.
    function storeWindDirection(deg as Number) as Void {
        cfg.setWindDirection(deg);
        if (cfg.windManual >= 0) {
            windEverSet = true;      // sticky: clearing the axis does not unclassify the past
        }
        try {
            Properties.setValue("windDirDeg", cfg.windManual);
        } catch (e) {
        }
    }

    // The watch's own estimate has been adopted. NOT persisted: it is this session's
    // inference, and a stale one restored at the next START would classify tomorrow's turns
    // against yesterday's wind. `windDirDeg` stays the rider's property and nothing else
    // writes it.
    function applyAutoWind(deg as Number) as Void {
        cfg.setAutoWind(deg);
        if (cfg.windAuto >= 0) {
            autoWindEverSet = true;  // sticky, for the same reason `windEverSet` is
        }
    }

    const COMPASS = WingFoilCore.COMPASS;

    // 16-point label for the axis in effect, with a leading "~" when it is the watch's own
    // estimate rather than the rider's bearing; "--" when unset.
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
