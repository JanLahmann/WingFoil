import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Position;
import Toybox.Test;
import WingFoilCore;

// Data-field unit tests. The detector semantics themselves are covered by the barrel suite
// (barrel/WingFoilCore/tests/CoreTests.mc), which is compiled into this binary too — what is
// tested here is everything the FIELD adds: the compact session schema, the per-tick feed
// path that replaces the device app's Position callback, and the adaptive layout.

function fieldCfg() as WingFoilCore.Config {
    var cfg = new WingFoilCore.Config();
    cfg.foilEntryMps = 12.0 / 3.6;
    cfg.foilExitMps = 8.0 / 3.6;
    cfg.entryHoldS = 2;
    cfg.exitHoldS = 3;
    cfg.minFlightS = 5;
    cfg.setWindDirection(-1);
    return cfg;
}

// ---- compact SESSION schema ----

(:test)
function sessionSchemaFitsDataFieldBudget(logger as Test.Logger) as Boolean {
    // The reason this schema exists. Both limits were measured on fenix847mm with a probe
    // build (see SessionPack's header): 32 bytes AND 16 fields per message type, and going
    // over either one does not throw — it kills the app. So the schema is guarded here.
    var total = SessionPack.totalBytes();
    logger.debug("session " + total.toString() + " B in "
        + SessionPack.SLOT_COUNT.toString() + " fields; record "
        + SessionPack.RECORD_BYTES.toString() + " B in "
        + SessionPack.RECORD_FIELDS.toString() + " fields; limits "
        + SessionPack.LIMIT_BYTES.toString() + " B / "
        + SessionPack.LIMIT_FIELDS.toString() + " fields");
    Test.assertMessage(total <= SessionPack.LIMIT_BYTES,
        "session message is " + total.toString() + " B, budget is "
        + SessionPack.LIMIT_BYTES.toString());
    Test.assertMessage(SessionPack.SLOT_COUNT <= SessionPack.LIMIT_FIELDS,
        "session message has " + SessionPack.SLOT_COUNT.toString()
        + " developer fields, the device accepts " + SessionPack.LIMIT_FIELDS.toString());
    Test.assertMessage(SessionPack.RECORD_BYTES <= SessionPack.LIMIT_BYTES
        && SessionPack.RECORD_FIELDS <= SessionPack.LIMIT_FIELDS,
        "record message over budget");
    Test.assertMessage(SessionPack.fits(), "fits() agrees");
    // the table must be complete: one width and one field id per slot
    Test.assertMessage(SessionPack.WIDTHS.size() == SessionPack.SLOT_COUNT,
        "a width per slot");
    Test.assertMessage(SessionPack.FIELD_IDS.size() == SessionPack.SLOT_COUNT,
        "a field id per slot");
    // and the ids must be unique, or two fields would collide in the FIT
    for (var i = 0; i < SessionPack.SLOT_COUNT; i++) {
        for (var j = i + 1; j < SessionPack.SLOT_COUNT; j++) {
            Test.assertMessage(SessionPack.FIELD_IDS[i] != SessionPack.FIELD_IDS[j],
                "duplicate field id " + SessionPack.FIELD_IDS[i].toString());
        }
    }
    return true;
}

(:test)
function sessionPackRoundTrips(logger as Test.Logger) as Boolean {
    // Every value must survive the width the schema table claims for it.
    var vals = new Array<Number>[SessionPack.SLOT_COUNT];
    vals[SessionPack.SLOT_FOIL_TIME] = 7263;            // 2 h 1 m of foil time
    vals[SessionPack.SLOT_FOIL_PCT] = 63;
    vals[SessionPack.SLOT_FLIGHT_COUNT] = 412;          // needs the uint16
    vals[SessionPack.SLOT_LONGEST_S] = 1234;
    vals[SessionPack.SLOT_BEST_2S] = 1543;              // cm/s = 30.0 kn
    vals[SessionPack.SLOT_BEST_10S] = 1401;
    vals[SessionPack.SLOT_TACKS] = 37;
    vals[SessionPack.SLOT_JIBES] = 122;
    vals[SessionPack.SLOT_TURN_SUCCESS] = 71;
    vals[SessionPack.SLOT_WIND_DIR] = 197;
    vals[SessionPack.SLOT_APP_VERSION] = 257;           // minor 1, schema 1
    vals[SessionPack.SLOT_OUTCOMES] = SessionPack.packOutcomes(90, 44, 25);
    vals[SessionPack.SLOT_DISCIPLINE] = SessionPack.DISCIPLINE_WINGFOIL;
    vals[SessionPack.SLOT_CFG] = SessionPack.packCfg(333, 222, 5);

    var bytes = SessionPack.encode(vals);
    Test.assertMessage(bytes.size() == SessionPack.totalBytes(),
        "encoded " + bytes.size().toString() + " B, table says "
        + SessionPack.totalBytes().toString());
    var back = SessionPack.decode(bytes);
    for (var i = 0; i < SessionPack.SLOT_COUNT; i++) {
        Test.assertMessage(back[i] == vals[i], "slot " + i.toString() + ": wrote "
            + vals[i].toString() + ", read " + back[i].toString());
    }
    // the two bit-packed fields must unpack to what went in
    var o = back[SessionPack.SLOT_OUTCOMES];
    Test.assertMessage(SessionPack.outcomeFlew(o) == 90, "flew");
    Test.assertMessage(SessionPack.outcomeTouchdown(o) == 44, "touchdown");
    Test.assertMessage(SessionPack.outcomeFell(o) == 25, "fell");
    var c = back[SessionPack.SLOT_CFG];
    Test.assertMessage(SessionPack.cfgEntryCms(c) == 333, "entry cm/s");
    Test.assertMessage(SessionPack.cfgExitCms(c) == 222, "exit cm/s");
    Test.assertMessage(SessionPack.cfgMinFlightS(c) == 5, "min flight s");
    return true;
}

(:test)
function sessionPackSaturatesInsteadOfWrapping(logger as Test.Logger) as Boolean {
    // A count that overflows its field must saturate one below the FIT invalid sentinel,
    // never wrap to a small number and never decode as "field absent".
    var vals = new Array<Number>[SessionPack.SLOT_COUNT];
    for (var i = 0; i < SessionPack.SLOT_COUNT; i++) {
        vals[i] = 0;
    }
    vals[SessionPack.SLOT_JIBES] = 9000;                // uint8 count
    vals[SessionPack.SLOT_FLIGHT_COUNT] = 200000;       // uint16 count
    vals[SessionPack.SLOT_TURN_SUCCESS] = -5;           // never negative on the wire
    vals[SessionPack.SLOT_WIND_DIR] = 65535;            // the "unset" sentinel is legal
    vals[SessionPack.SLOT_OUTCOMES] = SessionPack.packOutcomes(300, 5, -2);
    var back = SessionPack.decode(SessionPack.encode(vals));
    Test.assertMessage(back[SessionPack.SLOT_JIBES] == 254,
        "uint8 count saturates at 254, got " + back[SessionPack.SLOT_JIBES].toString());
    Test.assertMessage(back[SessionPack.SLOT_FLIGHT_COUNT] == 65534,
        "uint16 count saturates at 65534, got "
        + back[SessionPack.SLOT_FLIGHT_COUNT].toString());
    Test.assertMessage(back[SessionPack.SLOT_TURN_SUCCESS] == 0, "no negatives");
    Test.assertMessage(back[SessionPack.SLOT_WIND_DIR] == 65535,
        "wind_dir keeps its unset sentinel");
    // packed sub-counters saturate inside their byte, without bleeding into the neighbour
    var o = back[SessionPack.SLOT_OUTCOMES];
    Test.assertMessage(SessionPack.outcomeFlew(o) == 254, "packed flew saturates");
    Test.assertMessage(SessionPack.outcomeTouchdown(o) == 5, "neighbour intact");
    Test.assertMessage(SessionPack.outcomeFell(o) == 0, "packed fell floors at 0");
    // and the cfg pack clamps its narrow exit/minFlight lanes the same way
    var c = SessionPack.packCfg(694, 9999, 99);
    Test.assertMessage(SessionPack.cfgEntryCms(c) == 694, "entry kept");
    Test.assertMessage(SessionPack.cfgExitCms(c) == 2047, "exit clamped to its 11 bits");
    Test.assertMessage(SessionPack.cfgMinFlightS(c) == 31, "min flight clamped to 5 bits");
    return true;
}

(:test)
function sessionValuesComeFromTheDetectors(logger as Test.Logger) as Boolean {
    // The mapping detector counters -> session fields, end to end: fly for a while, then
    // check the packed summary says what the detectors say.
    var cfg = fieldCfg();
    cfg.setWindDirection(210);
    var e = new FieldEngine(cfg);
    e.timerS = 100.0;
    for (var i = 0; i < 30; i++) {               // 30 s at 5 m/s: one flight
        e.feed(1.0, 5.0, 90.0, 5.0, Position.QUALITY_GOOD, null);
    }
    for (var i = 0; i < 6; i++) {                // and back down
        e.feed(1.0, 1.0, null, 1.0, Position.QUALITY_GOOD, null);
    }
    var vals = SessionPack.fromEngine(e, cfg, 257);
    Test.assertMessage(vals[SessionPack.SLOT_FLIGHT_COUNT] == 1, "one flight");
    Test.assertMessage(vals[SessionPack.SLOT_FOIL_TIME] == e.detector.foilTimeS.toNumber(),
        "foil time passed through");
    // 30 s of samples produce exactly 30 s of foil time under the both-ends-qualify holds:
    // 2 s backdated at the entry, 27 s flying, then the 3 s exit hold added and backdated
    // away again (docs/algorithms.md; the barrel suite owns the arithmetic).
    Test.assertMessage(vals[SessionPack.SLOT_FOIL_PCT] == 30,
        "30 % of a 100 s timer, got " + vals[SessionPack.SLOT_FOIL_PCT].toString());
    Test.assertMessage(vals[SessionPack.SLOT_BEST_2S] == 500, "best 2 s = 5.00 m/s");
    Test.assertMessage(vals[SessionPack.SLOT_WIND_DIR] == 210, "wind axis echoed");
    var c = vals[SessionPack.SLOT_CFG];
    Test.assertMessage(SessionPack.cfgEntryCms(c) == 333, "entry threshold echoed");
    Test.assertMessage(SessionPack.cfgExitCms(c) == 222, "exit threshold echoed");
    Test.assertMessage(SessionPack.cfgMinFlightS(c) == 5, "min flight echoed");
    Test.assertMessage(vals[SessionPack.SLOT_DISCIPLINE] == SessionPack.DISCIPLINE_WINGFOIL,
        "discipline marker present — this is what tells a parser the session is ours");
    // and it still round-trips at those values
    var back = SessionPack.decode(SessionPack.encode(vals));
    Test.assertMessage(back[SessionPack.SLOT_FOIL_TIME] == vals[SessionPack.SLOT_FOIL_TIME],
        "round trip");
    return true;
}

// ---- per-tick feed logic ----

(:test)
function feedGatesOnGpsQuality(logger as Test.Logger) as Boolean {
    // A data field is handed Activity.Info every second whether or not the fix is any good.
    // Feeding an unusable fix into the detectors would fabricate flights out of GPS noise.
    var e = new FieldEngine(fieldCfg());
    for (var i = 0; i < 20; i++) {
        var ev = e.feed(1.0, 5.0, 90.0, 5.0, Position.QUALITY_LAST_KNOWN, null);
        Test.assertMessage(ev == 0, "no events while the fix is unusable");
    }
    Test.assertMessage(e.detector.flightCount == 0, "no flight from an unusable fix");
    Test.assertMessage(e.detector.foilTimeS < 0.001, "no foil time either");
    Test.assertMessage(e.records.best2sMps < 0.001, "and no speed record");
    Test.assertMessage(e.tickCount() == 20, "the tick counter still advances");
    return true;
}

(:test)
function feedDrivesFlightAndRecords(logger as Test.Logger) as Boolean {
    var e = new FieldEngine(fieldCfg());
    e.timerS = 60.0;
    var sawStart = false;
    for (var i = 0; i < 30; i++) {
        var ev = e.feed(1.0, 6.0, 90.0, 6.0, Position.QUALITY_GOOD, null);
        if ((ev & 0x0F) == FlightDetector.EVENT_START) {
            sawStart = true;
        }
    }
    Test.assertMessage(sawStart, "flight start event surfaced through the packed word");
    Test.assertMessage(e.flying(), "still on the foil");
    Test.assertMessage(e.detector.flightCount == 1, "one flight");
    Test.assertMessage((e.records.best2sMps - 6.0).abs() < 0.0001, "best 2 s = 6 m/s");
    Test.assertMessage((e.foilPct() - 50.0).abs() < 2.0,
        "30 s of foil in a 60 s timer, got " + e.foilPct().format("%.1f"));
    Test.assertMessage(e.speedMps == 6.0 && e.gpsQuality == Position.QUALITY_GOOD,
        "live values for the view");
    return true;
}

(:test)
function feedDetectsSubmersionFromPressure(logger as Test.Logger) as Boolean {
    // The barometer is the only extra evidence channel a data field has left (no accel), so
    // the baseline behaviour matters: slow drift is weather, a jump is a wrist under water.
    var e = new FieldEngine(fieldCfg());
    e.feed(1.0, 5.0, 90.0, 5.0, Position.QUALITY_GOOD, 101000.0);   // baseline
    Test.assertMessage(!e.submerged, "first sample only establishes the baseline");
    for (var i = 0; i < 5; i++) {
        e.feed(1.0, 5.0, 90.0, 5.0, Position.QUALITY_GOOD, 101020.0);   // weather drift
        Test.assertMessage(!e.submerged, "20 Pa of drift is not a dunk");
    }
    e.feed(1.0, 5.0, 90.0, 5.0, Position.QUALITY_GOOD, 101500.0);       // ~5 hPa jump
    Test.assertMessage(e.submerged, "500 Pa above baseline is a submersion");
    e.feed(1.0, 5.0, 90.0, 5.0, Position.QUALITY_GOOD, null);
    Test.assertMessage(!e.submerged, "no pressure channel = no evidence, not a dunk");
    return true;
}

(:test)
function resetClearsEverythingForANewActivity(logger as Test.Logger) as Boolean {
    // onTimerReset means a new activity in the same app instance: nothing may survive.
    var e = new FieldEngine(fieldCfg());
    for (var i = 0; i < 20; i++) {
        e.feed(1.0, 6.0, 90.0, 6.0, Position.QUALITY_GOOD, null);
    }
    Test.assert(e.detector.flightCount == 1);
    e.reset();
    Test.assertMessage(e.detector.flightCount == 0, "flights cleared");
    Test.assertMessage(e.detector.foilTimeS == 0.0, "foil time cleared");
    Test.assertMessage(e.records.best2sMps == 0.0, "records cleared");
    Test.assertMessage(e.turns.turnCount == 0, "turns cleared");
    Test.assertMessage(e.tickCount() == 0, "tick counter cleared");
    Test.assertMessage(!e.flying(), "not flying");
    return true;
}

(:test)
function tickCounterRollsBelowTheFitSentinel(logger as Test.Logger) as Boolean {
    // record field 4 is a uint8 that must never take the 0xFF "invalid" value.
    var e = new FieldEngine(fieldCfg());
    for (var i = 0; i < 300; i++) {
        e.feed(1.0, 1.0, null, 1.0, Position.QUALITY_GOOD, null);
    }
    Test.assertMessage(e.tickCount() == 300, "raw counter keeps counting");
    Test.assertMessage(e.tickCount() % 255 == 45, "the value written to FIT wraps 0-254");
    return true;
}

// ---- adaptive layout ----
//
// The cell rectangles below are not invented, and that matters: guessing them from "half of
// 454" is exactly how a clipped turn row survived this suite for two releases. They are what
// Garmin's own layouts really hand a data field, read off the simulator by walking
// Data Fields > Layout with the screenshot harness (garmin/field/screenshots) running — it
// prints "CELL wxh flags n" on every change for this purpose. The bottom cell of a 2-field
// page is 226 px tall and starts at y 228, not 227 and 227; a 4-field quadrant is 225 px
// wide, not 227; and the flags are how the field knows which of those edges is bezel.
//
// Both ends of the product list are tabled: fenix847mm, the largest glass (454 px), and
// fr255, the smallest round one (260 px). Columns are
//   label, w, h, obscurity flags, the SIZE_* the cell must end up with, and how many of its
//   rows may come out with no window at all (see layoutRowsNeverClip).
const CELLS_454 = [
    ["1 field",        454, 454, 15, FieldLayout.SIZE_FULL,  0],
    ["2F upper",       454, 225,  7, FieldLayout.SIZE_WIDE,  0],
    ["2F lower",       454, 226, 13, FieldLayout.SIZE_SMALL, 0],
    ["3A upper",       454, 158,  7, FieldLayout.SIZE_WIDE,  0],
    ["3A middle",      454, 128,  5, FieldLayout.SIZE_SMALL, 0],
    ["3A lower",       454, 163, 13, FieldLayout.SIZE_SMALL, 0],
    ["3B upper",       454, 146,  7, FieldLayout.SIZE_WIDE,  0],
    ["3B middle",      454, 157,  5, FieldLayout.SIZE_WIDE,  0],
    ["3B lower",       454, 145, 13, FieldLayout.SIZE_SMALL, 0],
    ["3C upper",       454, 225,  7, FieldLayout.SIZE_WIDE,  0],
    ["3C lower left",  225, 226,  9, FieldLayout.SIZE_SMALL, 0],
    ["3C lower right", 225, 226, 12, FieldLayout.SIZE_SMALL, 0],
    ["4A upper",       454, 161,  7, FieldLayout.SIZE_WIDE,  0],
    ["4A mid left",    225, 135,  1, FieldLayout.SIZE_SMALL, 0],
    ["4A mid right",   225, 135,  4, FieldLayout.SIZE_SMALL, 0],
    ["4A lower",       454, 152, 13, FieldLayout.SIZE_SMALL, 0],
    ["4B upper left",  225, 225,  3, FieldLayout.SIZE_SMALL, 0],
    ["4B upper right", 225, 225,  6, FieldLayout.SIZE_SMALL, 0],
    ["4B lower left",  225, 226,  9, FieldLayout.SIZE_SMALL, 0],
    ["4B lower right", 225, 226, 12, FieldLayout.SIZE_SMALL, 0],
    ["4C upper",       454, 113,  7, FieldLayout.SIZE_SMALL, 0],
    ["4C second",      454, 109,  5, FieldLayout.SIZE_SMALL, 0],
    ["4C third",       454, 112,  5, FieldLayout.SIZE_SMALL, 0],
    ["4C lower",       454, 111, 13, FieldLayout.SIZE_SMALL, 0],
    ["5F mid left",    225, 112,  1, FieldLayout.SIZE_SMALL, 0],
    ["5F mid right",   225, 112,  4, FieldLayout.SIZE_SMALL, 0],
    ["6F 2nd left",    225, 109,  1, FieldLayout.SIZE_SMALL, 0],
    ["6F 2nd right",   225, 109,  4, FieldLayout.SIZE_SMALL, 0],
    ["7F upper",       454,  78,  7, FieldLayout.SIZE_SMALL, 1],
    ["7F 2nd left",    225,  94,  1, FieldLayout.SIZE_SMALL, 0],
    ["7F 2nd right",   225,  94,  4, FieldLayout.SIZE_SMALL, 0],
    ["7F fourth",      454,  82,  5, FieldLayout.SIZE_SMALL, 0],
    ["7F lower",       454,  78, 13, FieldLayout.SIZE_SMALL, 1]
];
const CELLS_260 = [
    ["1 field",        260, 260, 15, FieldLayout.SIZE_FULL,  0],
    ["2F upper",       260, 129,  7, FieldLayout.SIZE_WIDE,  0],
    ["2F lower",       260, 129, 13, FieldLayout.SIZE_SMALL, 0],
    ["3A upper",       260,  83,  7, FieldLayout.SIZE_WIDE,  0],
    ["3A middle",      260,  91,  5, FieldLayout.SIZE_WIDE,  0],
    ["3A lower",       260,  82, 13, FieldLayout.SIZE_SMALL, 0],
    ["3B upper",       260,  90,  7, FieldLayout.SIZE_WIDE,  0],
    ["3B middle",      260,  74,  5, FieldLayout.SIZE_SMALL, 0],
    ["3B lower",       260,  93, 13, FieldLayout.SIZE_SMALL, 0],
    ["3C lower left",  129, 129,  9, FieldLayout.SIZE_SMALL, 0],
    ["3C lower right", 129, 129, 12, FieldLayout.SIZE_SMALL, 0],
    ["4A upper",       260,  64,  7, FieldLayout.SIZE_SMALL, 0],
    ["4A middle",      260,  63,  5, FieldLayout.SIZE_SMALL, 0],
    ["4A lower",       260,  64, 13, FieldLayout.SIZE_SMALL, 0],
    ["4B upper",       260,  92,  7, FieldLayout.SIZE_WIDE,  0],
    ["4B mid left",    129,  77,  1, FieldLayout.SIZE_SMALL, 0],
    ["4B mid right",   129,  77,  4, FieldLayout.SIZE_SMALL, 0],
    ["4B lower",       260,  87, 13, FieldLayout.SIZE_SMALL, 0],
    ["4C upper left",  129, 129,  3, FieldLayout.SIZE_SMALL, 0],
    ["4C upper right", 129, 129,  6, FieldLayout.SIZE_SMALL, 0],
    ["5F mid left",    129,  63,  1, FieldLayout.SIZE_SMALL, 0],
    ["5F mid right",   129,  63,  4, FieldLayout.SIZE_SMALL, 0],
    ["7F upper",       260,  44,  7, FieldLayout.SIZE_SMALL, 1],
    ["7F 2nd left",    129,  54,  1, FieldLayout.SIZE_SMALL, 0],
    ["7F fourth",      260,  47,  5, FieldLayout.SIZE_SMALL, 0],
    ["7F lower",       260,  44, 13, FieldLayout.SIZE_SMALL, 1]
];

// The cells to drive on the glass this binary was built for. Off the two tabled glasses the
// invariants still run, on a synthetic 1/2/4-field split, but without the expected sizes:
// those are readings, not predictions, and inventing them for an untested watch would be the
// original sin of this file all over again.
function cellsFor(screenW as Number, screenH as Number) as Array {
    if (screenW == 454 && screenH == 454) {
        return CELLS_454;
    }
    if (screenW == 260 && screenH == 260) {
        return CELLS_260;
    }
    return [
        ["1 field", screenW, screenH, 15, -1, 0],
        ["upper half", screenW, screenH / 2, 7, -1, 0],
        ["lower half", screenW, screenH - screenH / 2, 13, -1, 0],
        ["upper left quadrant", screenW / 2, screenH / 2, 3, -1, 0],
        ["lower right quadrant", screenW / 2, screenH - screenH / 2, 12, -1, 0]
    ] as Array;
}

(:test)
function layoutClassifiesCellSizes(logger as Test.Logger) as Boolean {
    var w = 454;
    var h = 454;
    Test.assertMessage(FieldLayout.classify(w, h, w, h) == FieldLayout.SIZE_FULL,
        "1-field page is FULL");
    Test.assertMessage(FieldLayout.classify(w, 227, w, h) == FieldLayout.SIZE_WIDE,
        "half screen is WIDE");
    Test.assertMessage(FieldLayout.classify(w, 151, w, h) == FieldLayout.SIZE_WIDE,
        "a 3-field row is still WIDE");
    Test.assertMessage(FieldLayout.classify(227, 113, w, h) == FieldLayout.SIZE_SMALL,
        "a quarter cell is SMALL");
    // classify() is height-only above SMALL and always has been: a quadrant is half the
    // screen tall, so it asks for the three-row layout however narrow it is. That is the
    // question fitCell() exists to overrule, and layoutRowsNeverClip is where it does.
    Test.assertMessage(FieldLayout.classify(227, 227, w, h) == FieldLayout.SIZE_WIDE,
        "a 2x2 quadrant asks for WIDE on room alone");
    return true;
}

(:test)
function layoutReadsTheObscurityFlags(logger as Test.Logger) as Boolean {
    // The whole glass: both rims, so nothing to lean towards.
    var g = FieldLayout.place(454, 454, 454, 454, 15, true);
    Test.assertMessage(g != null && g.y0 == 0 && g.lean == 0 && g.cx == 227.0,
        "the 1-field cell is the glass itself");
    // Upper half: y0 0, and a stack in it leans DOWN, away from the top rim.
    g = FieldLayout.place(454, 225, 454, 454, 7, true);
    Test.assertMessage(g != null && g.y0 == 0 && g.lean == 1, "upper half leans down");
    // Lower half: the system says 226 tall against the bottom, so it starts at 228.
    g = FieldLayout.place(454, 226, 454, 454, 13, true);
    Test.assertMessage(g != null && g.y0 == 228 && g.lean == -1, "lower half leans up");
    // A right-hand quadrant: the glass's centre is off to the LEFT of the cell's own.
    g = FieldLayout.place(225, 226, 454, 454, 12, true);
    Test.assertMessage(g != null && g.y0 == 228 && (g.cx - -2.0).abs() < 0.01,
        "a right quadrant starts at x 229, so the glass centre is 2 px left of its edge");
    g = FieldLayout.place(225, 226, 454, 454, 9, true);
    Test.assertMessage(g != null && (g.cx - 227.0).abs() < 0.01, "and 227 in for a left one");
    // A band that touches neither rim cannot be located, and is not guessed at.
    Test.assertMessage(FieldLayout.place(454, 128, 454, 454, 5, true) == null,
        "a middle band keeps its rectangle");
    // Nor is a square screen corrected for at all.
    Test.assertMessage(FieldLayout.place(454, 226, 454, 454, 13, false) == null,
        "a rectangular glass has no missing corners");
    return true;
}

// Every row of every cell of every layout the user can actually pick must sit inside its cell
// and inside the GLASS. This is the headless twin of eyeballing a screenshot, and unlike a
// screenshot it runs against the worst-case strings — the counts that turn up at the end of a
// long session, not the ones on the shot.
(:test)
function layoutRowsNeverClip(logger as Test.Logger) as Boolean {
    // A tiny scratch bitmap: font metrics do not depend on the canvas they are measured on,
    // and a data field only has 128 KB — a screen-sized buffer (454x454) is enough to take the
    // whole heap with it, which is exactly how this test first killed the simulator.
    var ref = Graphics.createBufferedBitmap({:width => 8, :height => 8});
    var dc = (ref.get() as Graphics.BufferedBitmap).getDc();
    var s = System.getDeviceSettings();
    var round = s.screenShape == System.SCREEN_SHAPE_ROUND;
    var cells = cellsFor(s.screenWidth, s.screenHeight);
    logger.debug("glass " + s.screenWidth + "x" + s.screenHeight + " round=" + round
        + ", " + cells.size() + " cells");

    for (var c = 0; c < cells.size(); c++) {
        var name = cells[c][0] as String;
        var w = cells[c][1] as Number;
        var h = cells[c][2] as Number;
        var g = FieldLayout.place(w, h, s.screenWidth, s.screenHeight,
            cells[c][3] as Number, round);
        var cell = FieldLayout.fitCell(dc, w, h, s.screenWidth, s.screenHeight, g);
        var size = cell[0] as Number;
        var want = cells[c][4] as Number;
        Test.assertMessage(want < 0 || size == want,
            name + " came out SIZE " + size + ", the simulator says it must be " + want);
        var texts = FieldLayout.WIDEST[size];
        var heights = FieldLayout.heightsOf(dc, cell[1] as Array<Graphics.FontType>);
        var lean = cell[2] as Number;
        var blind = 0;
        var prevBottom = 0;
        for (var i = 0; i < texts.size(); i++) {
            var y = FieldLayout.stackY(h, heights, i, lean);
            var win = FieldLayout.rowWindow(w, y, heights[i], g);
            var tw = dc.getTextWidthInPixels(texts[i],
                (cell[1] as Array<Graphics.FontType>)[i]);
            Test.assertMessage(y - heights[i] / 2 >= 0 && y + heights[i] / 2 <= h,
                name + " row " + i + " is outside its cell");
            Test.assertMessage(y - heights[i] / 2 >= prevBottom,
                name + " row " + i + " overlaps the row above it");
            prevBottom = y + heights[i] / 2;
            // A window of zero means the row's font BOX has no overlap with the glass at all,
            // which is not the same as the row being invisible: the box is a good deal taller
            // than the ink in it. It happens only in the 78 px end bands of a 7-field page, the
            // fitter has already walked to the smallest font it has, and there is nothing left
            // to trade — so it is counted rather than asserted, and the count is pinned.
            if (win[1] == 0) {
                blind++;
                continue;
            }
            Test.assertMessage(tw <= win[1], name + " row " + i + ": \"" + texts[i]
                + "\" is " + tw + " px wide, the glass gives it " + win[1]
                + " at y " + y);
        }
        Test.assertMessage(blind == (cells[c][5] as Number),
            name + " has " + blind + " row(s) with no window, expected " + cells[c][5]);
        logger.debug(name + " " + w + "x" + h + " -> size " + size + " lean " + lean
            + " heights " + heights.toString());
    }
    return true;
}

// The defect this geometry exists for, stated as an assertion.
//
// The lower half of a 2-field page is the bottom of the circle. Fitted to its own rectangle it
// takes the three-row layout and draws "TOUCH 100% · 99/99" across 420 px of a chord that is
// nothing like that wide down there — which is what the store screenshots caught: FLEW and the
// last of the tack/jibe split were both eaten by the bezel. It must now step down to the two
// rows it can hold, and hold them.
(:test)
function bottomBezelCellsGiveUpTheTurnRow(logger as Test.Logger) as Boolean {
    var s = System.getDeviceSettings();
    if (s.screenShape != System.SCREEN_SHAPE_ROUND) {
        return true;
    }
    var ref = Graphics.createBufferedBitmap({:width => 8, :height => 8});
    var dc = (ref.get() as Graphics.BufferedBitmap).getDc();
    var w = s.screenWidth;
    var h = s.screenHeight - s.screenHeight / 2;
    var g = FieldLayout.place(w, h, s.screenWidth, s.screenHeight,
        FieldLayout.EDGE_LEFT | FieldLayout.EDGE_RIGHT | FieldLayout.EDGE_BOTTOM, true);
    Test.assertMessage(FieldLayout.classify(w, h, s.screenWidth, s.screenHeight)
        == FieldLayout.SIZE_WIDE, "room alone still says WIDE");

    // What the old rule did: three rows fitted to the full rectangle, turn row last.
    var old = FieldLayout.fitRows(dc, w, h, FieldLayout.WIDEST[FieldLayout.SIZE_WIDE],
        FieldLayout.LADDERS[FieldLayout.SIZE_WIDE], null, 0);
    var heights = FieldLayout.heightsOf(dc, old);
    var y = FieldLayout.stackY(h, heights, 2, 0);
    var wide = dc.getTextWidthInPixels("TOUCH 100% · 99/99", old[2]);
    var glass = FieldLayout.rowWindow(w, y, heights[2], g)[1];
    logger.debug("old turn row: " + wide + " px at y " + y + ", glass gives " + glass);
    Test.assertMessage(wide > glass,
        "the bug: the turn row was " + wide + " px and the chord there is " + glass);

    // What the new one does: the cell cannot carry three rows, so it carries two.
    var cell = FieldLayout.fitCell(dc, w, h, s.screenWidth, s.screenHeight, g);
    Test.assertMessage((cell[0] as Number) == FieldLayout.SIZE_SMALL,
        "the bottom half steps down to two rows");
    Test.assertMessage((cell[2] as Number) == -1,
        "and leans up, away from the bezel it is sitting on");
    return true;
}

// ---- Invite-beta unlock gate (docs/decisions.md ADR-012) ----
// The field compiles garmin/source/lock/LockGate.mc verbatim, so the arithmetic below is the
// device app's arithmetic. These vectors are copied CHARACTER FOR CHARACTER from
// garmin/tests/WingfoilTests.mc, which shares them with lab/tools/make_unlock.py --check:
// three implementations, one table, and any drift reddens at least one suite.

const UNLOCK_VEC_PEPPER = [0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef];
const UNLOCK_VEC_IDS = ["wingfoil", "ac915d426451c88e8ea691fa412f9af9c21b4d12", ""];
const UNLOCK_VEC_CODES = ["PTMDBDNY", "N3J986JP", "SFS9SS44"];
const UNLOCK_VEC_KEYS = ["MWTSPKVB", "MJFJ4PD4", "1PT5WKZK"];

(:test)
function fieldUnlockGateIsOffWithoutAPepper(logger as Test.Logger) as Boolean {
    // This binary is built from field/monkey.jungle, i.e. the ../source-nopepper stub. The
    // private-beta field must never show a lock screen or stop contributing to the FIT, and
    // this is the assertion that says the invite channel cannot leak into it.
    var p = UnlockPepper.bytes();
    Test.assertMessage(p.size() == 8, "pepper is 8 bytes");
    Test.assertMessage(LockGate.isZero(p), "the ordinary field must ship a ZERO pepper");
    Test.assertMessage(!LockGate.enabled(), "gate must be disabled in the ordinary field");
    Test.assertMessage(LockGate.refresh(), "a disabled gate reports unlocked");
    Test.assertMessage(WingFoilDataField.unlocked(), "so the field computes and draws");
    logger.debug("zero pepper -> gate bypassed");
    return true;
}

(:test)
function fieldUnlockKeyMatchesKeygenVectors(logger as Test.Logger) as Boolean {
    // If the field and the app ever disagreed here, Jan would mail a tester a key minted for
    // the device app that the data field refuses — on a build he cannot debug remotely.
    for (var i = 0; i < UNLOCK_VEC_IDS.size(); i++) {
        var code = LockGate.requestCodeFor(UNLOCK_VEC_IDS[i]);
        var key = LockGate.keyFor(UNLOCK_VEC_PEPPER, code);
        logger.debug("id=\"" + UNLOCK_VEC_IDS[i] + "\" code=" + code + " key=" + key);
        Test.assertMessage(code.equals(UNLOCK_VEC_CODES[i]),
            "request code " + code + " != keygen " + UNLOCK_VEC_CODES[i]);
        Test.assertMessage(key.equals(UNLOCK_VEC_KEYS[i]),
            "unlock key " + key + " != keygen " + UNLOCK_VEC_KEYS[i]);
        Test.assertMessage(LockGate.matches(UNLOCK_VEC_PEPPER, code, key.toLower()),
            "and the watch reads back what a tester typed");
    }
    // The 64-bit FNV state is carried in two 32-bit halves precisely so no multiply can
    // overflow; if a device ever wrapped or saturated differently, these two would drift.
    var h = LockGate.fnv1a64([] as Array<Number>);
    Test.assertMessage(h[0] == 0xcbf29ce4l && h[1] == 0x84222325l, "FNV offset basis");
    h = LockGate.fnv1a64([0] as Array<Number>);
    Test.assertMessage(h[0] == 0xaf63bd4cl && h[1] == 0x8601b7dfl,
        "FNV of one zero byte drifted: " + h[0].format("%08x") + h[1].format("%08x"));
    return true;
}

(:test)
function lockedFieldContributesNothing(logger as Test.Logger) as Boolean {
    // The promise the invite channel makes: a field nobody unlocked records NOTHING. Not a
    // zeroed session, not a partial one — the compute() path never runs, so the activity's
    // FIT carries no developer fields at all.
    //
    // The gate state is forced rather than peppered, because this binary carries the zero
    // pepper on purpose (see fieldUnlockGateIsOffWithoutAPepper) and there is no other way to
    // reach the locked branch from here.
    var was = LockGate._unlocked;
    LockGate._unlocked = false;
    var e = new FieldEngine(fieldCfg());
    e.timerS = 60.0;
    for (var i = 0; i < 30; i++) {
        if (WingFoilDataField.unlocked()) {     // the guard compute() runs, verbatim
            e.feed(1.0, 6.0, 90.0, 6.0, Position.QUALITY_GOOD, null);
        }
    }
    Test.assertMessage(e.detector.flightCount == 0, "no flight while locked");
    Test.assertMessage(e.detector.foilTimeS < 0.001, "no foil time while locked");
    Test.assertMessage(e.detector.currentFlightM < 0.001, "no distance while locked");
    Test.assertMessage(e.records.best2sMps < 0.001, "no speed record while locked");
    Test.assertMessage(e.tickCount() == 0, "not even a tick");

    // ...and the same 30 samples DO accumulate once the key lands, or the assertions above
    // would also pass on an engine that simply never worked.
    LockGate._unlocked = true;
    for (var i = 0; i < 30; i++) {
        if (WingFoilDataField.unlocked()) {
            e.feed(1.0, 6.0, 90.0, 6.0, Position.QUALITY_GOOD, null);
        }
    }
    Test.assertMessage(e.detector.flightCount == 1, "unlocking starts the engine");
    Test.assertMessage(e.detector.foilTimeS > 20.0, "and the foil time with it");
    LockGate._unlocked = was;
    return true;
}
