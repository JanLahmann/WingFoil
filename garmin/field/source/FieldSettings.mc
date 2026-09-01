import Toybox.Application;
import Toybox.Application.Properties;
import Toybox.Graphics;
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
//
// 0.9.5 adds the SLOT settings: which metric each configurable row of a small or wide cell
// carries. The slot ids are FieldMetrics'; the defaults are the 0.9.4 rows, so an install that
// never opens the settings page sees exactly what it saw before. The full-screen cell is not
// among them — it draws the device app's Main page and nothing else, because a rider who has
// given the field the whole glass has asked for the app's face, not for a form to fill in.
module FieldSettings {
    var cfg as WingFoilCore.Config = new WingFoilCore.Config();

    var smallSlot as Number = FieldMetrics.M_FOIL_PCT;
    var widePrimary as Number = FieldMetrics.M_FOIL_PCT;
    var wideSecondary as Number = FieldMetrics.M_FLIGHT_LINE;

    function load() as Void {
        cfg.foilEntryMps = _num("foilEntryKmh", 12.0) / 3.6;
        cfg.foilExitMps = _num("foilExitKmh", 8.0) / 3.6;
        cfg.entryHoldS = _num("entryHoldS", 2.0).toNumber();
        cfg.exitHoldS = _num("exitHoldS", 3.0).toNumber();
        cfg.minFlightS = _num("minFlightS", 5.0).toNumber();
        cfg.useKnots = _bool("useKnots", false);
        cfg.setWindDirection(_num("windDirDeg", -1.0).toNumber());
        cfg.sanitize();

        smallSlot = FieldMetrics.sanitize(_num("smallSlot",
            FieldMetrics.M_FOIL_PCT.toFloat()).toNumber());
        widePrimary = FieldMetrics.sanitize(_num("widePrimary",
            FieldMetrics.M_FOIL_PCT.toFloat()).toNumber());
        wideSecondary = FieldMetrics.sanitize(_num("wideSecondary",
            FieldMetrics.M_FLIGHT_LINE.toFloat()).toNumber());
        applySlots();
    }

    // Push the chosen slots into the layout's worst-case table.
    //
    // This is the one place the configuration becomes geometry, and it is a WRITE into
    // FieldLayout rather than a lookup on the way past for a reason: FieldLayout.WIDEST is
    // read by fitCell (to decide whether a cell can carry three rows), by the drawing code
    // (to know which font each row got) and by the layout suite (to prove nothing clips).
    // Three readers, one table — the moment the configuration were consulted separately by
    // each of them, a slot could be fitted as one string and drawn as another, which is
    // precisely the class of bug the table exists to make impossible.
    //
    // The bottom row of each size is not configurable and is not written here: a SMALL cell
    // always ends on the flight line and a WIDE cell always ends on the turn line. Those are
    // the field's signature — the two things it knows that the watch's own fields do not — and
    // a rider who wanted the cell without them would be better served by a Garmin field.
    function applySlots() as Void {
        FieldLayout.WIDEST[FieldLayout.SIZE_SMALL] = [
            FieldMetrics.worst(smallSlot),
            FieldMetrics.worst(FieldMetrics.M_FLIGHT_LINE)] as Array<String>;
        FieldLayout.LADDERS[FieldLayout.SIZE_SMALL] = [
            FieldMetrics.ladder(smallSlot),
            FieldMetrics.ladder(FieldMetrics.M_FLIGHT_LINE)] as Array;
        FieldLayout.CAPS[FieldLayout.SIZE_SMALL] = [
            FieldMetrics.cap(smallSlot),
            FieldMetrics.cap(FieldMetrics.M_FLIGHT_LINE)] as Array<Array<String> >;
        FieldLayout.WIDEST[FieldLayout.SIZE_WIDE] = [
            FieldMetrics.worst(widePrimary),
            FieldMetrics.worst(wideSecondary),
            FieldMetrics.worst(FieldMetrics.M_TURN_LINE)] as Array<String>;
        FieldLayout.LADDERS[FieldLayout.SIZE_WIDE] = [
            FieldMetrics.ladder(widePrimary),
            FieldMetrics.ladder(wideSecondary),
            FieldMetrics.ladder(FieldMetrics.M_TURN_LINE)] as Array;
        FieldLayout.CAPS[FieldLayout.SIZE_WIDE] = [
            FieldMetrics.cap(widePrimary),
            FieldMetrics.cap(wideSecondary),
            FieldMetrics.cap(FieldMetrics.M_TURN_LINE)] as Array<Array<String> >;
    }

    // The metric each row of `size` carries, in draw order. The bottom row is the fixed one.
    function slotsFor(size as Number) as Array<Number> {
        if (size == FieldLayout.SIZE_WIDE) {
            return [widePrimary, wideSecondary, FieldMetrics.M_TURN_LINE] as Array<Number>;
        }
        return [smallSlot, FieldMetrics.M_FLIGHT_LINE] as Array<Number>;
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
