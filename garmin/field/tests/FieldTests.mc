import Toybox.Activity;
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
    vals[SessionPack.SLOT_CLEAN_JIBES] = 61;            // 0.9.6, field 51
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
    vals[SessionPack.SLOT_CLEAN_JIBES] = 900;           // uint8 count
    vals[SessionPack.SLOT_FLIGHT_COUNT] = 200000;       // uint16 count
    vals[SessionPack.SLOT_TURN_SUCCESS] = -5;           // never negative on the wire
    vals[SessionPack.SLOT_WIND_DIR] = 65535;            // the "unset" sentinel is legal
    vals[SessionPack.SLOT_OUTCOMES] = SessionPack.packOutcomes(300, 5, -2);
    var back = SessionPack.decode(SessionPack.encode(vals));
    Test.assertMessage(back[SessionPack.SLOT_JIBES] == 254,
        "uint8 count saturates at 254, got " + back[SessionPack.SLOT_JIBES].toString());
    Test.assertMessage(back[SessionPack.SLOT_CLEAN_JIBES] == 254,
        "and so does the clean count, got "
        + back[SessionPack.SLOT_CLEAN_JIBES].toString());
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
    // 0.9.6: field 51 is the detector's own clean count, taken straight off TurnDetector and
    // not re-derived here. Nothing in this 36 s of straight-line riding is a jibe, so the
    // honest value is 0 — and the assertion is that the field is WRITTEN, at the detector's
    // number, which is what a parser reading a session with no jibes in it has to see.
    Test.assertMessage(vals[SessionPack.SLOT_CLEAN_JIBES] == e.turns.cleanJibeCount,
        "clean count comes off the detector, got "
        + vals[SessionPack.SLOT_CLEAN_JIBES].toString());
    e.turns.cleanJibeCount = 25;
    Test.assertMessage(SessionPack.fromEngine(e, cfg, 257)[SessionPack.SLOT_CLEAN_JIBES] == 25,
        "and follows it");
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
    // 0.9.5: this one keeps its three rows where the 454 px glass gives them up. Both
    // stacks bottom out at the same font here, so the centred/leaned choice is decided on FIT
    // rather than on ink (FieldLayout.fitStack), and leaning up off the bottom rim is enough
    // chord for the turn row on a 260 px circle.
    ["2F lower",       260, 129, 13, FieldLayout.SIZE_WIDE,  0],
    ["3A upper",       260,  83,  7, FieldLayout.SIZE_WIDE,  0],
    ["3A middle",      260,  91,  5, FieldLayout.SIZE_WIDE,  0],
    ["3A lower",       260,  82, 13, FieldLayout.SIZE_SMALL, 0],
    ["3B upper",       260,  90,  7, FieldLayout.SIZE_WIDE,  0],
    ["3B middle",      260,  74,  5, FieldLayout.SIZE_SMALL, 0],
    ["3B lower",       260,  93, 13, FieldLayout.SIZE_WIDE,  0],
    ["3C lower left",  129, 129,  9, FieldLayout.SIZE_SMALL, 0],
    ["3C lower right", 129, 129, 12, FieldLayout.SIZE_SMALL, 0],
    ["4A upper",       260,  64,  7, FieldLayout.SIZE_SMALL, 0],
    ["4A middle",      260,  63,  5, FieldLayout.SIZE_SMALL, 0],
    ["4A lower",       260,  64, 13, FieldLayout.SIZE_SMALL, 0],
    ["4B upper",       260,  92,  7, FieldLayout.SIZE_WIDE,  0],
    ["4B mid left",    129,  77,  1, FieldLayout.SIZE_SMALL, 0],
    ["4B mid right",   129,  77,  4, FieldLayout.SIZE_SMALL, 0],
    ["4B lower",       260,  87, 13, FieldLayout.SIZE_WIDE,  0],
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
        var fonts = cell[1] as Array<Graphics.FontType>;
        var caps = cell[3] as Array<Array<String> >;
        var heights = FieldLayout.heightsOf(dc, fonts);
        var lean = cell[2] as Number;
        var blind = 0;
        var prevBottom = 0;
        for (var i = 0; i < texts.size(); i++) {
            var y = FieldLayout.stackY(h, heights, i, lean);
            var win = FieldLayout.rowWindow(w, y, heights[i], g);
            // the row's INK, not just its string: a caption riding beside the value is width
            // the glass has to give it too
            var tw = FieldLayout.rowInk(dc, texts[i], fonts[i], caps[i]);
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
            + " caps " + (caps[0].size() > 0) + " heights " + heights.toString());
    }
    return true;
}

// The defect this geometry exists for, stated as an assertion.
//
// The lower half of a 2-field page is the bottom of the circle. Fitted to its own rectangle it
// takes the three-row layout and draws "TOUCH 100% · 99/99" across 420 px of a chord that is
// nothing like that wide down there — which is what the store screenshots caught: FLEW and the
// last of the tack/jibe split were both eaten by the bezel.
//
// What it does INSTEAD is glass-dependent, and deliberately not pinned here: on a 454 px fenix
// 8 it steps down to the two rows it can hold, and on a 260 px fr255 it keeps all three by
// leaning up off the rim (0.9.5 — where the centred and leaned stacks tie on font size, the
// one that FITS wins). Both are the machinery working. What is pinned is the part that is not
// allowed to vary: the old rule overflowed, and whatever this cell ends up with, it fits.
(:test)
function bottomBezelCellsGiveUpTheTurnRow(logger as Test.Logger) as Boolean {
    var s = System.getDeviceSettings();
    if (s.screenShape != System.SCREEN_SHAPE_ROUND) {
        return true;
    }
    var dc = scratchDc();
    var w = s.screenWidth;
    var h = s.screenHeight - s.screenHeight / 2;
    var g = FieldLayout.place(w, h, s.screenWidth, s.screenHeight,
        FieldLayout.EDGE_LEFT | FieldLayout.EDGE_RIGHT | FieldLayout.EDGE_BOTTOM, true);
    Test.assertMessage(FieldLayout.classify(w, h, s.screenWidth, s.screenHeight)
        == FieldLayout.SIZE_WIDE, "room alone still says WIDE");

    // What the old rule did: three rows fitted to the full rectangle, centred, turn row last.
    var old = FieldLayout.fitRows(dc, w, h, FieldLayout.WIDEST[FieldLayout.SIZE_WIDE],
        FieldLayout.LADDERS[FieldLayout.SIZE_WIDE],
        FieldLayout.noCaps(FieldLayout.WIDEST[FieldLayout.SIZE_WIDE].size()), null, 0, -1);
    var heights = FieldLayout.heightsOf(dc, old);
    var y = FieldLayout.stackY(h, heights, 2, 0);
    var wide = dc.getTextWidthInPixels("TOUCH 100% · 99/99", old[2]);
    var glass = FieldLayout.rowWindow(w, y, heights[2], g)[1];
    logger.debug("old turn row: " + wide + " px at y " + y + ", glass gives " + glass);
    Test.assertMessage(wide > glass,
        "the bug: the turn row was " + wide + " px and the chord there is " + glass);

    // What the new one does: whichever trade it makes, the result holds.
    var cell = FieldLayout.fitCell(dc, w, h, s.screenWidth, s.screenHeight, g);
    var size = cell[0] as Number;
    logger.debug("bottom half -> size " + size + " lean " + cell[2]);
    Test.assertMessage(size == FieldLayout.SIZE_SMALL || (cell[2] as Number) == -1,
        "a cell that kept three rows down there must be leaning up off the bezel");
    assertStackHolds(dc, "2-field lower half", w, h, size,
        cell[3] as Array<Array<String> >, [cell[1], cell[2]] as Array, g);
    return true;
}

// ---- 0.9.5: the app's face, and the slots under it ----

// A scratch Dc to measure real device fonts on. Deliberately 8x8: font metrics do not depend
// on the canvas they are measured on, and a data field has 128 KB — a screen-sized buffer is
// enough to take the whole heap with it, which is how the layout tests first killed the
// simulator.
function scratchDc() as Graphics.Dc {
    var ref = Graphics.createBufferedBitmap({:width => 8, :height => 8});
    return (ref.get() as Graphics.BufferedBitmap).getDc();
}

// Every row of a fitted stack, checked the way layoutRowsNeverClip checks a cell's: inside the
// cell, not overlapping its neighbour, and its INK (value plus caption) inside the chord. The
// return is how many rows had no window at all.
function assertStackHolds(dc as Graphics.Dc, name as String, w as Number, h as Number,
        idx as Number, caps as Array<Array<String> >, stack as Array,
        g as FieldLayout.Glass?) as Number {
    var texts = FieldLayout.WIDEST[idx];
    var fonts = stack[0] as Array<Graphics.FontType>;
    var lean = stack[1] as Number;
    var heights = FieldLayout.heightsOf(dc, fonts);
    var blind = 0;
    var prevBottom = 0;
    for (var i = 0; i < texts.size(); i++) {
        var y = FieldLayout.stackY(h, heights, i, lean);
        var win = FieldLayout.rowWindow(w, y, heights[i], g);
        Test.assertMessage(y - heights[i] / 2 >= 0 && y + heights[i] / 2 <= h,
            name + " row " + i + " is outside its cell");
        Test.assertMessage(y - heights[i] / 2 >= prevBottom,
            name + " row " + i + " overlaps the row above it");
        prevBottom = y + heights[i] / 2;
        if (win[1] == 0) {
            blind++;
            continue;
        }
        var ink = FieldLayout.rowInk(dc, texts[i], fonts[i], caps[i]);
        Test.assertMessage(ink <= win[1], name + " row " + i + ": \"" + texts[i]
            + "\" + caption " + caps[i].toString() + " is " + ink + " px, the glass gives it "
            + win[1] + " at y " + y + " (font " + fonts[i] + ", lean " + lean + ")");
    }
    return blind;
}

// The face itself. A 1-field page must carry the whole Main-page composition at worst case —
// five rows, the two-line caption beside the giant, and a dot ladder with room for a strip
// worth calling one.
(:test)
function fullScreenCarriesTheAppMainPage(logger as Test.Logger) as Boolean {
    var dc = scratchDc();
    var s = System.getDeviceSettings();
    var w = s.screenWidth;
    var h = s.screenHeight;
    var round = s.screenShape == System.SCREEN_SHAPE_ROUND;
    var g = FieldLayout.place(w, h, w, h, 15, round);
    var cell = FieldLayout.fitCell(dc, w, h, w, h, g);
    Test.assertMessage((cell[0] as Number) == FieldLayout.SIZE_FULL,
        "the 1-field page is FULL");
    var caps = cell[3] as Array<Array<String> >;
    Test.assertMessage(FieldLayout.hasCaps(caps),
        "and it keeps its captions — this is the cell that has room for them");
    var stack = [cell[1], cell[2]] as Array;
    var blind = assertStackHolds(dc, "1 field", w, h, FieldLayout.SIZE_FULL, caps,
        stack, g);
    Test.assertMessage(blind == 0, "no row of the main page is blind");

    // the giant is a NUMBER font, i.e. the row really is giant and not a text line
    var fonts = cell[1] as Array<Graphics.FontType>;
    var ladder = "";
    for (var i = 0; i < FieldLayout.NUM_FONTS.size(); i++) {
        ladder += FieldLayout.NUM_FONTS[i] + ":"
            + dc.getFontHeight(FieldLayout.NUM_FONTS[i]) + " ";
    }
    logger.debug("number ladder heights " + ladder);
    Test.assertMessage(fonts[1] == Graphics.FONT_NUMBER_THAI_HOT
        || fonts[1] == Graphics.FONT_NUMBER_HOT
        || fonts[1] == Graphics.FONT_NUMBER_MEDIUM
        || fonts[1] == Graphics.FONT_NUMBER_MILD,
        "the giant walks the number ladder, got font " + fonts[1]);
    // the giant's caption is the two-line block, and it fits its row
    Test.assertMessage(FieldLayout.capLines(dc, caps[1], dc.getFontHeight(fonts[1])) == 2,
        "the giant carries both the unit and the word");

    // and the dot ladder has a usable strip: the band is a real font's height and the chord at
    // that depth holds a double-figure run of turns
    var heights = FieldLayout.heightsOf(dc, fonts);
    var y = FieldLayout.stackY(h, heights, 2, cell[2] as Number);
    var win = FieldLayout.rowWindow(w, y, heights[2], g);
    var r = FieldLayout.dotRadius(heights[2], w);
    var gap = FieldLayout.dotGap(w);
    var shown = FieldLayout.dotsShown(FieldEngine.TURN_LOG,
        win[1] - FieldLayout.capWidth(dc, caps[2]), r, gap);
    logger.debug("main page " + w + "x" + h + " heights " + heights.toString()
        + ", dots r " + r + " gap " + gap + " -> " + shown + " of "
        + FieldEngine.TURN_LOG);
    Test.assertMessage(r >= 2, "the dots are big enough to be dots, r = " + r);
    Test.assertMessage(shown >= 10,
        "the strip holds a readable run of turns, got " + shown);
    return true;
}

// The two pages a stopped rider sees. Same assertions, at the same worst case: the summary is
// the screen most likely to be read at length, so it is the last one allowed to clip.
(:test)
function summaryPagesFitTheFullScreenCell(logger as Test.Logger) as Boolean {
    var dc = scratchDc();
    var s = System.getDeviceSettings();
    var w = s.screenWidth;
    var h = s.screenHeight;
    var round = s.screenShape == System.SCREEN_SHAPE_ROUND;
    var g = FieldLayout.place(w, h, w, h, 15, round);
    var pages = [FieldLayout.REND_SUM_A, FieldLayout.REND_SUM_B] as Array<Number>;
    for (var p = 0; p < pages.size(); p++) {
        var idx = pages[p];
        var stack = FieldLayout.fitRendition(dc, w, h, idx, g);
        Test.assertMessage(stack != null,
            "summary page " + idx + " does not survive the 1-field cell");
        var blind = assertStackHolds(dc, "summary " + idx, w, h, idx, FieldLayout.CAPS[idx],
            stack as Array, g);
        Test.assertMessage(blind == 0, "no summary row is blind");
        logger.debug("summary " + idx + " heights "
            + FieldLayout.heightsOf(dc, (stack as Array)[0]
                as Array<Graphics.FontType>).toString());
        // every summary row is labelled: this is the page a stranger reads
        var caps = FieldLayout.CAPS[idx];
        for (var i = 0; i < caps.size(); i++) {
            Test.assertMessage(caps[i].size() > 0,
                "summary page " + idx + " row " + i + " has no word to say what it is");
        }
    }
    return true;
}

// The cadence: page A, then page B, then A again, every SUMMARY_TICKS paused seconds. A data
// field has no buttons, so this counter is the only paging there is.
(:test)
function summaryPagesAlternateWhilePaused(logger as Test.Logger) as Boolean {
    var n = FieldLayout.SUMMARY_TICKS;
    Test.assertMessage(FieldLayout.summaryPage(0) == FieldLayout.REND_SUM_A,
        "a stop opens on the session page");
    Test.assertMessage(FieldLayout.summaryPage(n - 1) == FieldLayout.REND_SUM_A,
        "and holds it for the whole dwell");
    Test.assertMessage(FieldLayout.summaryPage(n) == FieldLayout.REND_SUM_B,
        "then the turns page");
    Test.assertMessage(FieldLayout.summaryPage(2 * n) == FieldLayout.REND_SUM_A,
        "and back");
    return true;
}

// The timer state is what chooses between them, and it comes off Activity.Info — the only
// input a data field has. TIMER_STATE_ON is riding; everything else (paused, stopped, never
// started) is a rider who is looking at the watch, and gets the summary.
(:test)
function timerStateChoosesTheFace(logger as Test.Logger) as Boolean {
    var e = new FieldEngine(fieldCfg());
    var info = new Activity.Info();
    var states = [Activity.TIMER_STATE_ON, Activity.TIMER_STATE_PAUSED,
        Activity.TIMER_STATE_STOPPED, Activity.TIMER_STATE_OFF]
        as Array<Activity.TimerState>;
    var wantRunning = [true, false, false, false] as Array<Boolean>;
    for (var i = 0; i < states.size(); i++) {
        info.timerState = states[i];
        info.timerTime = 1000 * (i + 1);
        info.currentSpeed = 6.0;
        e.onCompute(info);
        Test.assertMessage(e.running == wantRunning[i],
            "timerState " + states[i] + " -> running " + e.running);
    }
    // and a paused tick must not move the counters: the summary is a picture of a session
    // that has stopped happening
    info.timerState = Activity.TIMER_STATE_PAUSED;
    var flights = e.detector.flightCount;
    for (var i = 0; i < 30; i++) {
        info.timerTime = 10000 + i * 1000;
        e.onCompute(info);
    }
    Test.assertMessage(e.detector.flightCount == flights, "a paused activity gains no flight");
    return true;
}

// Heart rate reaches the field the same way, and its absence is a null rather than a zero.
(:test)
function heartRateComesThroughActivityInfo(logger as Test.Logger) as Boolean {
    var e = new FieldEngine(fieldCfg());
    var info = new Activity.Info();
    info.timerState = Activity.TIMER_STATE_ON;
    info.timerTime = 1000;
    info.currentHeartRate = 142;
    e.onCompute(info);
    Test.assertMessage(e.hr != null && e.hr == 142, "the pulse arrives");
    Test.assertMessage(FieldMetrics.value(FieldMetrics.M_HR, e, fieldCfg()).equals("142 bpm"),
        "and reads as a heart rate");
    info.timerTime = 2000;
    info.currentHeartRate = null;
    e.onCompute(info);
    Test.assertMessage(e.hr == null, "a lost strap is null, not zero");
    Test.assertMessage(FieldMetrics.value(FieldMetrics.M_HR, e, fieldCfg()).equals("-- bpm"),
        "and says so");
    return true;
}

// The outcome ladder's memory: one entry per RESOLVED turn, oldest dropped past the cap.
(:test)
function outcomeLogFeedsTheDotLadder(logger as Test.Logger) as Boolean {
    var e = new FieldEngine(fieldCfg());
    Test.assertMessage(e.outcomeCount == 0, "nothing before the first turn");
    // drive the log directly through the event word the detector returns, which is what feed()
    // hands it — the detector's own semantics are the barrel suite's business
    var events = [TurnDetector.EVENT_TURN, TurnDetector.EVENT_FLEW,
        TurnDetector.EVENT_TOUCHDOWN, TurnDetector.EVENT_NONE,
        TurnDetector.EVENT_FELL] as Array<Number>;
    for (var i = 0; i < events.size(); i++) {
        e.logOutcome(events[i]);
    }
    Test.assertMessage(e.outcomeCount == 3,
        "only resolved outcomes join the strip, got " + e.outcomeCount);
    Test.assertMessage(e.outcomes[0] == TurnDetector.OUTCOME_FLEW
        && e.outcomes[1] == TurnDetector.OUTCOME_TOUCHDOWN
        && e.outcomes[2] == TurnDetector.OUTCOME_FELL, "in the order they happened");
    // past the cap the OLDEST goes, so the strip is always the most recent turns
    for (var i = 0; i < FieldEngine.TURN_LOG + 5; i++) {
        e.logOutcome(TurnDetector.EVENT_FLEW);
    }
    Test.assertMessage(e.outcomeCount == FieldEngine.TURN_LOG, "the log is capped");
    Test.assertMessage(e.outcomes[FieldEngine.TURN_LOG - 1] == TurnDetector.OUTCOME_FLEW,
        "newest last");
    e.reset();
    Test.assertMessage(e.outcomeCount == 0, "and a new activity starts with an empty strip");
    return true;
}

// The catalog behind the slot settings. Every id the settings list offers must have a word, a
// worst case and a ladder — a slot the field cannot fill would draw an empty row, which reads
// as a crashed field.
(:test)
function metricCatalogIsComplete(logger as Test.Logger) as Boolean {
    var dc = scratchDc();
    var cfg = fieldCfg();
    var e = new FieldEngine(cfg);
    e.timerS = 6793.0;
    e.distM = 23100.0;
    e.speedMps = 24.5 / 3.6;
    e.detector.flightCount = 31;
    e.detector.foilTimeS = 3804.0;
    e.detector.longestS = 424.0;
    e.records.best2sMps = 25.5 / 3.6;
    e.records.best10sMps = 24.3 / 3.6;
    e.turns.turnCount = 51;
    e.turns.tackCount = 27;
    e.turns.jibeCount = 24;
    e.turns.flewCount = 35;
    e.turns.touchdownCount = 8;
    e.turns.fellCount = 8;
    e.turns.lastOutcome = TurnDetector.OUTCOME_TOUCHDOWN;
    e.turns.lastScorePct = 61;
    e.turns.cleanJibeCount = 25;                 // 2026-08-29 pm, the corpus session
    for (var i = 0; i < FieldMetrics.LIST.size(); i++) {
        var id = FieldMetrics.LIST[i];
        var worst = FieldMetrics.worst(id);
        var label = FieldMetrics.label(id);
        var live = FieldMetrics.value(id, e, cfg);
        Test.assertMessage(worst.length() > 0, "metric " + id + " has no worst case");
        Test.assertMessage(label.length() > 0, "metric " + id + " has no word");
        Test.assertMessage(live.length() > 0, "metric " + id + " draws nothing");
        Test.assertMessage(FieldMetrics.sanitize(id) == id, "metric " + id + " is in LIST");
        // the seeded session must not be wider than the table says it can be, or the fit is
        // measuring one string and the field is drawing another
        var lw = dc.getTextWidthInPixels(live, Graphics.FONT_MEDIUM);
        var ww = dc.getTextWidthInPixels(worst, Graphics.FONT_MEDIUM);
        Test.assertMessage(lw <= ww, "metric " + id + ": \"" + live + "\" (" + lw
            + " px) is wider than its worst case \"" + worst + "\" (" + ww + " px)");
        logger.debug("metric " + id + " \"" + label + "\" -> \"" + live + "\" worst \""
            + worst + "\"");
    }
    // and an id from a build that no longer exists falls back rather than blanking a row
    Test.assertMessage(FieldMetrics.sanitize(999) == FieldMetrics.FALLBACK, "junk id");
    Test.assertMessage(FieldMetrics.sanitize(16) == FieldMetrics.FALLBACK,
        "the app's pump metrics are not offered here: Sensor.* crashes a data field");
    return true;
}

// The never-clip promise, kept for every slot the rider can actually choose. This is
// layoutRowsNeverClip's loop run once per metric, with that metric in EVERY configurable slot
// at once — the widest configuration it can produce — across every cell of every layout.
//
// The tabled SIZE is not asserted here and must not be: a wider metric legitimately steps a
// cell down, which is the machinery working. What is asserted is the invariant that survives
// any configuration — nothing is drawn outside its cell, over its neighbour, or off the glass.
(:test)
function configuredSlotsNeverClip(logger as Test.Logger) as Boolean {
    var dc = scratchDc();
    var s = System.getDeviceSettings();
    var round = s.screenShape == System.SCREEN_SHAPE_ROUND;
    var cells = cellsFor(s.screenWidth, s.screenHeight);
    var wasSmall = FieldSettings.smallSlot;
    var wasPri = FieldSettings.widePrimary;
    var wasSec = FieldSettings.wideSecondary;
    var capped = 0;
    var bare = 0;

    for (var m = 0; m < FieldMetrics.LIST.size(); m++) {
        var id = FieldMetrics.LIST[m];
        FieldSettings.smallSlot = id;
        FieldSettings.widePrimary = id;
        FieldSettings.wideSecondary = id;
        FieldSettings.applySlots();
        for (var c = 0; c < cells.size(); c++) {
            var name = "metric " + id + " in " + (cells[c][0] as String);
            var w = cells[c][1] as Number;
            var h = cells[c][2] as Number;
            var g = FieldLayout.place(w, h, s.screenWidth, s.screenHeight,
                cells[c][3] as Number, round);
            var cell = FieldLayout.fitCell(dc, w, h, s.screenWidth, s.screenHeight, g);
            var size = cell[0] as Number;
            if (size == FieldLayout.SIZE_FULL) {
                continue;       // not configurable, and its own test covers it
            }
            if (FieldLayout.hasCaps(cell[3] as Array<Array<String> >)) {
                capped++;
            } else {
                bare++;
            }
            assertStackHolds(dc, name, w, h, size, cell[3] as Array<Array<String> >,
                [cell[1], cell[2]] as Array, g);
        }
    }

    FieldSettings.smallSlot = wasSmall;
    FieldSettings.widePrimary = wasPri;
    FieldSettings.wideSecondary = wasSec;
    FieldSettings.applySlots();
    logger.debug(FieldMetrics.LIST.size() + " metrics x " + cells.size() + " cells: "
        + capped + " captioned, " + bare + " bare");
    // both halves of the caption trade must actually happen somewhere on this glass, or the
    // rule that decides it is untested in the only place it runs
    Test.assertMessage(capped > 0, "no configuration anywhere kept its words");
    Test.assertMessage(bare > 0, "no configuration anywhere gave them up");
    return true;
}

// ---- 0.9.6: the clean jibe ----

// CPH is a division and a floor, and the floor is the half that is easy to get wrong. The four
// corners are pinned here the way the barrel suite pins the detector's: below the minute there
// is no rate at all, at the minute there is, and the arithmetic in between is a rate per HOUR
// and not per anything else.
(:test)
function cphIsARatePerHourWithAMinuteFloor(logger as Test.Logger) as Boolean {
    // the arithmetic: 25 clean jibes in 7029 s of a real afternoon (docs/algorithms.md's
    // corpus row for 2026-08-29 pm, where the phone's cleaned-track denominator gives 12.8)
    var v = FieldMetrics.cleanPerHour(25, 7029.0);
    Test.assertMessage(v > 12.7 && v < 12.9, "25 in 7029 s is ~12.8 an hour, got " + v);
    Test.assertMessage(FieldMetrics.fmtCph(25, 7029.0).equals("12.8"),
        "and prints to one decimal, got " + FieldMetrics.fmtCph(25, 7029.0));
    // an hour exactly is the identity case, and it is worth pinning because it is the one
    // value that would still look right if the constant were seconds-per-minute
    Test.assertMessage(FieldMetrics.fmtCph(7, 3600.0).equals("7.0"),
        "seven in an hour is seven an hour, got " + FieldMetrics.fmtCph(7, 3600.0));
    Test.assertMessage(FieldMetrics.fmtCph(3, 1800.0).equals("6.0"),
        "three in half an hour is six an hour, got " + FieldMetrics.fmtCph(3, 1800.0));

    // THE FLOOR. One clean jibe forty seconds in is not ninety an hour — it is one clean jibe
    // and not enough afternoon to divide by. Below 60 s the rate is refused outright, and what
    // the row shows is the field's own unmeasured mark, never a number and never a 0.0.
    Test.assertMessage(FieldMetrics.cleanPerHour(1, 40.0) < 0.0,
        "no rate before a minute");
    Test.assertMessage(FieldMetrics.fmtCph(1, 40.0).equals(FieldMetrics.CPH_NONE),
        "and it prints as \"--\", got " + FieldMetrics.fmtCph(1, 40.0));
    Test.assertMessage(FieldMetrics.fmtCph(0, 0.0).equals(FieldMetrics.CPH_NONE),
        "a session that has not started has no rate either");
    // the floor is a floor and not a gate: at exactly 60 s the rate exists
    Test.assertMessage(FieldMetrics.cleanPerHour(0, 59.9) < 0.0, "59.9 s is still below it");
    Test.assertMessage(FieldMetrics.fmtCph(1, 60.0).equals("60.0"),
        "at 60 s it lifts, got " + FieldMetrics.fmtCph(1, 60.0));
    // ...and a zero above the floor is a real observation, not a missing one: an hour with no
    // clean jibe in it is a fact about the hour, and dashing it would hide a hard session.
    Test.assertMessage(FieldMetrics.fmtCph(0, 3600.0).equals("0.0"),
        "zero clean jibes in an hour is 0.0, not \"--\"");
    // a negative count cannot arise from the detector, but the guard must not invent a rate
    // from one if some future caller passes it
    Test.assertMessage(FieldMetrics.cleanPerHour(-1, 3600.0) < 0.0, "no rate from a negative");
    logger.debug("cph 25/7029 s = " + FieldMetrics.fmtCph(25, 7029.0) + ", 1/40 s = "
        + FieldMetrics.fmtCph(1, 40.0));
    return true;
}

// The two metrics as the field actually reads them: off TurnDetector.cleanJibeCount and off
// the engine's own timer, which is the denominator a data field has (there is no
// SessionController here — see FieldMetrics' CPH header and the divergence list in
// docs/algorithms.md).
(:test)
function cleanMetricsReadTheDetectorAndTheTimer(logger as Test.Logger) as Boolean {
    var cfg = fieldCfg();
    var e = new FieldEngine(cfg);
    Test.assertMessage(FieldMetrics.value(FieldMetrics.M_CLEAN, e, cfg).equals("0"),
        "a session with no jibes in it has counted none");
    Test.assertMessage(FieldMetrics.value(FieldMetrics.M_CPH, e, cfg)
        .equals(FieldMetrics.CPH_NONE), "and has no rate, because it has no minute");
    e.turns.cleanJibeCount = 12;
    e.timerS = 3600.0;
    Test.assertMessage(FieldMetrics.value(FieldMetrics.M_CLEAN, e, cfg).equals("12"),
        "the count is the detector's");
    Test.assertMessage(FieldMetrics.value(FieldMetrics.M_CPH, e, cfg).equals("12.0"),
        "the rate divides by the engine timer, got "
        + FieldMetrics.value(FieldMetrics.M_CPH, e, cfg));
    // the denominator is the TIMER, not foil time: a rider who flew for ten minutes of his
    // hour still rode those twelve jibes in an hour on the water
    e.detector.foilTimeS = 600.0;
    Test.assertMessage(FieldMetrics.value(FieldMetrics.M_CPH, e, cfg).equals("12.0"),
        "foil time is not the denominator");
    // a new activity starts both over
    e.reset();
    Test.assertMessage(e.turns.cleanJibeCount == 0, "reset clears the clean count");
    Test.assertMessage(FieldMetrics.value(FieldMetrics.M_CPH, e, cfg)
        .equals(FieldMetrics.CPH_NONE), "and the rate with it");
    return true;
}

// The star's row, on both screens that draw it. Its worst case is measured with the glyph
// budgeted as one character, so what has to hold is that the character really is what the
// drawing code reserves — otherwise the fitter is sizing a row the field does not draw.
(:test)
function cleanRowsBudgetTheStarAsOneCharacter(logger as Test.Logger) as Boolean {
    var dc = scratchDc();
    var full = FieldLayout.WIDEST[FieldLayout.SIZE_FULL][3];
    var sumB = FieldLayout.WIDEST[FieldLayout.REND_SUM_B][3];
    Test.assertMessage(full.equals("99 · 99 · 99" + FieldLayout.CLEAN_GAP
        + FieldLayout.STAR_STANDIN + " 99 99.9"),
        "the Main tally row's worst case is the tally, the gap, the star and the two numbers: "
        + full);
    Test.assertMessage(sumB.equals(FieldLayout.STAR_STANDIN + " 99 99.9"),
        "and the summary's clean row is the star and the two numbers: " + sumB);
    // the stand-in must be a glyph with width in every font on the ladder, or the star's box
    // would be budgeted at zero on some rung and the row would overflow only there
    for (var i = 0; i < FieldLayout.TEXT_FONTS.size(); i++) {
        var w = dc.getTextWidthInPixels(FieldLayout.STAR_STANDIN, FieldLayout.TEXT_FONTS[i]);
        Test.assertMessage(w > 0, "the star's stand-in measures 0 px in font "
            + FieldLayout.TEXT_FONTS[i] + " — the box it reserves would vanish");
    }
    // and the live strings must fit inside the tabled ones: the count and the rate are the
    // two halves that grow during a session
    var cfg = fieldCfg();
    var e = new FieldEngine(cfg);
    e.turns.cleanJibeCount = 99;
    e.timerS = 3600.0;
    var live = FieldLayout.STAR_STANDIN + " " + e.turns.cleanJibeCount.toString() + " "
        + FieldMetrics.cphText(e);
    var lw = dc.getTextWidthInPixels(live, Graphics.FONT_MEDIUM);
    var ww = dc.getTextWidthInPixels(sumB, Graphics.FONT_MEDIUM);
    logger.debug("clean row live \"" + live + "\" " + lw + " px vs worst \"" + sumB + "\" "
        + ww + " px");
    Test.assertMessage(lw <= ww, "a 99/99.0 session is wider than the tabled worst case");
    return true;
}

// The defaults are the 0.9.4 rows, character for character. This is the promise the release
// makes to an install that never opens the settings page.
(:test)
function slotDefaultsAreTheOldRows(logger as Test.Logger) as Boolean {
    Test.assertMessage(FieldSettings.smallSlot == FieldMetrics.M_FOIL_PCT, "small = foil %");
    Test.assertMessage(FieldSettings.widePrimary == FieldMetrics.M_FOIL_PCT, "wide 1 = foil %");
    Test.assertMessage(FieldSettings.wideSecondary == FieldMetrics.M_FLIGHT_LINE,
        "wide 2 = the flight line");
    FieldSettings.applySlots();
    var small = FieldLayout.WIDEST[FieldLayout.SIZE_SMALL];
    var wide = FieldLayout.WIDEST[FieldLayout.SIZE_WIDE];
    Test.assertMessage(small[0].equals("100%") && small[1].equals("99 · 88:88"),
        "the SMALL worst case is 0.9.4's: " + small.toString());
    Test.assertMessage(wide[0].equals("100%") && wide[1].equals("99 · 88:88")
        && wide[2].equals("TOUCH 100% · 99/99"),
        "and so is the WIDE one: " + wide.toString());
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
