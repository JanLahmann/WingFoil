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
    // 0.9.5: its own rhythm for a clean jibe, in place of the plain fly-through tick
    // (AlertManager.turnResolved). Default ON — it is the metric the app is named after, and a
    // rider who does not want it turns it off and gets the 0.9.4 buzz back, not silence.
    var alertCleanJibe as Boolean = true;
    var mapAfterSave as Boolean = false;     // 0.9.9 experiment, GitHub #4
    var alertTakeoff as Boolean = true;
    // 0.9.11: the visual half of every alert above (EventFlash). One switch, on by default;
    // the per-alert switches gate the picture exactly as they gate the buzz.
    var visualAlerts as Boolean = true;
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

    // ---- the page SET (0.9.16) ----
    // standard = the eight shipped screens; large = seven screens with one
    // giant number each (PageModel.buildLarge). It is ONE enum, in EVERY stream, which is the
    // whole design: the per-page editor went `(:dev)` in the same round, so this is the page
    // control a release or beta rider has — and a rider who says "I need my glasses" wants a
    // switch, not a page list. Out of range reads as standard, the way every other enum here
    // takes its default rather than a clamp that would invent a set nobody chose.
    var pageSet as Number = PageModel.PAGE_SET_STANDARD;

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

    // Every numeric property is read through `_clamped`, with the SAME min/max
    // resources/settings/settings.xml declares. Garmin Connect enforces those bounds on the
    // slider; nothing enforces them on the value that actually arrives. A property store
    // survives an app update, a settings sync can carry a value the current settings.xml no
    // longer allows, and `Properties.setValue` from our own code is unchecked — so a
    // `minFlightS` of 0, a `foilEntryKmh` of 0 (which sanitize() then turns into a NEGATIVE
    // exit speed) or a `windDefaultTurnType` of 7 all reach the detectors without this.
    // Clamping here, once, is what keeps every threshold inside docs/algorithms.md whatever
    // the store says. Change a bound here and in settings.xml together.
    function load() as Void {
        cfg.foilEntryMps = _clamped("foilEntryKmh", 12.0, 6.0, 25.0) / 3.6;
        cfg.foilExitMps = _clamped("foilExitKmh", 8.0, 4.0, 20.0) / 3.6;
        cfg.entryHoldS = _clamped("entryHoldS", 2.0, 1.0, 10.0).toNumber();
        cfg.exitHoldS = _clamped("exitHoldS", 3.0, 1.0, 10.0).toNumber();
        cfg.minFlightS = _clamped("minFlightS", 5.0, 2.0, 30.0).toNumber();
        cfg.useKnots = _bool("useKnots", false);
        sportChoice = _clamped("sportChoice", 0.0, 0.0, 2.0).toNumber();
        accelLogging = _bool("accelLogging", true);
        pumpDetection = _bool("pumpDetection", true);
        alertPb = _bool("alertPb", true);
        alertFlight = _bool("alertFlight", true);
        alertTurn = _bool("alertTurn", true);
        alertCleanJibe = _bool("alertCleanJibe", true);
        mapAfterSave = readMapAfterSave();
        alertTakeoff = _bool("alertTakeoff", true);
        visualAlerts = _bool("visualAlerts", true);
        alertIntervalMin = _clamped("alertIntervalMin", 0.0, 0.0, 120.0).toNumber();
        alertIntervalKm = _clamped("alertIntervalKm", 0.0, 0.0, 50.0);
        autoPause = _bool("autoPause", false);
        autoPauseDelayS = _clamped("autoPauseDelayS", 5.0, 2.0, 60.0).toNumber();
        showLabels = _bool("showLabels", true);
        phonePush = _bool("phonePush", false);
        pageSet = _num("pageSet", PageModel.PAGE_SET_STANDARD.toFloat()).toNumber();
        if (pageSet != PageModel.PAGE_SET_LARGE) {
            pageSet = PageModel.PAGE_SET_STANDARD;
        }
        // NOT `_clamped`, and the two exceptions are the same exception. A wind axis of 400
        // clamped to 359 is a bearing the rider never gave, and it would relabel every tack
        // as a jibe rather than leaving the turns generic; `Config.setWindDirection` reads
        // anything outside 0-359 as UNSET, which is the honest answer and the documented one.
        cfg.setWindDirection(_num("windDirDeg", -1.0).toNumber());
        if (cfg.windManual >= 0) {
            windEverSet = true;
        }
        autoWind = _bool("autoWind", true);
        // Likewise: a turn habit of 7 is not "balanced" (which switches the prior OFF), it is
        // a store nobody wrote on purpose. It takes the default habit.
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

    // `_num` with the property's documented bounds applied. Out of range does NOT fall back
    // to the default — it clamps to the nearest bound, because a rider who set 40 km/h meant
    // "as high as it goes", not "put it back to twelve". A value that is not a number at all
    // (a String, a null, a store the firmware could not read) still takes the default.
    function _clamped(key as String, dflt as Float, lo as Float, hi as Float) as Float {
        var v = _num(key, dflt);
        if (v < lo) {
            return lo;
        }
        return v > hi ? hi : v;
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

    // "Reset pages to defaults" is a switch that behaves like a button: the rider turns it on
    // in Garmin Connect, the watch consumes it in onSettingsChanged — restores the pages and
    // turns the switch back off — and the next settings sync shows it off again. The same
    // write-back pattern as storeWindDirection above. Returns true exactly once per press.
    (:dev)
    function consumeResetPages() as Boolean {
        if (!_bool("resetPages", false)) {
            return false;
        }
        try {
            Properties.setValue("resetPages", false);
        } catch (e) {
        }
        return true;
    }

    // No page editor outside the dev stream means no switch to reset it with: the property
    // lives in resources-dev/base/settings/ since 0.9.16 and a release or beta build carries
    // neither the Garmin Connect row nor this read. Never pressed, so never true.
    (:notdev)
    function consumeResetPages() as Boolean {
        return false;
    }

    // ---- the dev stream's experiments (docs/channels.md, "The watch") ----
    // Monkey C has no #if; the jungles exclude annotations instead. The dev jungle excludes
    // `notdev`, every other jungle excludes `dev`, so exactly one of each pair compiles and
    // a release or beta build carries neither the switch nor the code behind it.
    (:dev)
    function readMapAfterSave() as Boolean {
        return _bool("mapAfterSave", false);       // the property lives in resources-dev/base
    }

    (:notdev)
    function readMapAfterSave() as Boolean {
        return false;                              // no map experiment outside the dev stream
    }
}
