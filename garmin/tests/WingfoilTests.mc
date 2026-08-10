import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Test;

// Unit tests for the W1 logic cores (docs/testing.md layer 3). Semantics must mirror
// lab/src/wingfoil_lab/flight.py — parameters set directly on AppSettings, no Properties.

(:test)
function ringBufferMeanAndEviction(logger as Test.Logger) as Boolean {
    var rb = new RingBuffer(3);
    rb.push(1.0);
    Test.assert(!rb.isFull());
    rb.push(2.0);
    rb.push(3.0);
    Test.assert(rb.isFull());
    Test.assertMessage((rb.mean() - 2.0).abs() < 0.0001, "mean of 1,2,3");
    rb.push(5.0);   // evicts 1.0 -> [2,3,5]
    Test.assertMessage((rb.mean() - 3.3333).abs() < 0.001, "mean after eviction");
    rb.reset();
    Test.assert(!rb.isFull());
    return true;
}

(:test)
function flightDetectorFullCycle(logger as Test.Logger) as Boolean {
    AppSettings.foilEntryMps = 12.0 / 3.6;
    AppSettings.foilExitMps = 8.0 / 3.6;
    AppSettings.entryHoldS = 2;
    AppSettings.exitHoldS = 3;
    AppSettings.minFlightS = 5;

    var d = new FlightDetector();

    // 10 s slow taxi: nothing happens
    for (var i = 0; i < 10; i++) {
        Test.assert(d.tick(1.0, 2.0, 2.0) == FlightDetector.EVENT_NONE);
    }
    Test.assert(d.state == FlightDetector.STATE_OFF);
    Test.assert(d.flightCount == 0);

    // 20 s at 5 m/s (18 km/h): ON after 2 s entry hold, EVENT_START at >= minFlight
    var sawStart = false;
    for (var i = 0; i < 20; i++) {
        var ev = d.tick(1.0, 5.0, 5.0);
        if (ev == FlightDetector.EVENT_START) {
            Test.assertMessage(!sawStart, "start fires once");
            sawStart = true;
        }
    }
    Test.assertMessage(sawStart, "flight confirmed");
    Test.assert(d.state == FlightDetector.STATE_ON);
    Test.assert(d.flightCount == 1);

    // drop to 1 m/s: EVENT_END after 3 s exit hold, end backdated
    var sawEnd = false;
    for (var i = 0; i < 5; i++) {
        if (d.tick(1.0, 1.0, 1.0) == FlightDetector.EVENT_END) {
            sawEnd = true;
        }
    }
    Test.assertMessage(sawEnd, "flight ended");
    Test.assert(d.state == FlightDetector.STATE_OFF);
    // foil time: 2 s backdated entry + 18 s flying (exit hold added then backdated away)
    Test.assertMessage(d.foilTimeS >= 19.0 && d.foilTimeS <= 21.0,
        "foilTime ~20, got " + d.foilTimeS.format("%.1f"));
    Test.assertMessage(d.longestS >= 19.0, "longest ~20");
    return true;
}

(:test)
function flightDetectorDiscardsShortFlights(logger as Test.Logger) as Boolean {
    AppSettings.foilEntryMps = 12.0 / 3.6;
    AppSettings.foilExitMps = 8.0 / 3.6;
    AppSettings.entryHoldS = 2;
    AppSettings.exitHoldS = 3;
    AppSettings.minFlightS = 5;

    var d = new FlightDetector();
    // 3 s burst above entry (2 s hold -> ON with 2 s backdate, but never reaches 5 s)
    for (var i = 0; i < 3; i++) {
        Test.assert(d.tick(1.0, 5.0, 5.0) != FlightDetector.EVENT_START);
    }
    // straight back down
    for (var i = 0; i < 6; i++) {
        Test.assert(d.tick(1.0, 1.0, 1.0) != FlightDetector.EVENT_END);
    }
    Test.assert(d.state == FlightDetector.STATE_OFF);
    Test.assert(d.flightCount == 0);
    Test.assertMessage(d.foilTimeS < 0.5, "discarded flight leaves no foil time, got "
        + d.foilTimeS.format("%.1f"));
    return true;
}

(:test)
function flightDetectorEntryHoldIsBothEndsQualifying(logger as Test.Logger) as Boolean {
    // lab/src/wingfoil_lab/flight.py `_flight_spans`: the first qualifying sample opens the
    // run with the accumulator at ZERO, so a hold of `entryHold` seconds needs
    // entryHold + 1 qualifying samples at 1 Hz. The dt spanning the last non-qualifying
    // sample must never count -- otherwise ON_FOIL confirms a sample early and the
    // backdated flight time contains an interval the rider was not flying.
    AppSettings.foilEntryMps = 12.0 / 3.6;
    AppSettings.foilExitMps = 8.0 / 3.6;
    AppSettings.entryHoldS = 2;
    AppSettings.exitHoldS = 3;
    AppSettings.minFlightS = 5;

    var d = new FlightDetector();
    d.tick(1.0, 1.0, 1.0);          // one slow sample: the interval leaving it never counts
    Test.assert(d.state == FlightDetector.STATE_OFF);

    d.tick(1.0, 5.0, 5.0);          // qualifying sample 1: opens the run, accumulator 0
    Test.assertMessage(d.state == FlightDetector.STATE_OFF,
        "1 qualifying sample is 0 s of hold");
    d.tick(1.0, 5.0, 5.0);          // qualifying sample 2: entryHold - 1 = 1 s of hold
    Test.assertMessage(d.state == FlightDetector.STATE_OFF,
        "entryHold samples is entryHold - 1 s of hold: must NOT confirm here");
    d.tick(1.0, 5.0, 5.0);          // qualifying sample 3 = entryHold + 1: 2 s of hold
    Test.assertMessage(d.state == FlightDetector.STATE_ON,
        "ON_FOIL on the entryHold + 1 -th qualifying sample");

    // backdated to the FIRST qualifying sample: exactly entryHold, not entryHold + 1
    Test.assertMessage((d.foilTimeS - 2.0).abs() < 0.0001,
        "backdate = entryHold, got " + d.foilTimeS.format("%.2f"));
    Test.assertMessage((d.currentFlightS - 2.0).abs() < 0.0001,
        "flight length = entryHold, got " + d.currentFlightS.format("%.2f"));
    return true;
}

(:test)
function flightDetectorExitHoldIsBothEndsQualifying(logger as Test.Logger) as Boolean {
    // Same convention on the way out: exitHold + 1 sub-exit samples at 1 Hz, and the end is
    // backdated to the FIRST sub-exit sample, so the last flying interval stays in the flight.
    AppSettings.foilEntryMps = 12.0 / 3.6;
    AppSettings.foilExitMps = 8.0 / 3.6;
    AppSettings.entryHoldS = 2;
    AppSettings.exitHoldS = 3;
    AppSettings.minFlightS = 5;

    var d = new FlightDetector();
    for (var i = 0; i < 11; i++) {          // 11 qualifying samples: flight spans t0..t10
        d.tick(1.0, 5.0, 5.0);
    }
    Test.assert(d.state == FlightDetector.STATE_ON && d.flightCount == 1);
    Test.assertMessage((d.currentFlightS - 10.0).abs() < 0.0001,
        "10 s of flight so far, got " + d.currentFlightS.format("%.2f"));

    var ev = FlightDetector.EVENT_NONE;
    for (var i = 1; i <= 3; i++) {          // exitHold sub-exit samples: 2 s of hold, still ON
        ev = d.tick(1.0, 1.0, 1.0);
        Test.assertMessage(d.state == FlightDetector.STATE_ON,
            "exitHold sub-exit samples must NOT end the flight (sample " + i.toString() + ")");
    }
    ev = d.tick(1.0, 1.0, 1.0);             // exitHold + 1: 3 s of hold -> OFF_FOIL
    Test.assertMessage(ev == FlightDetector.EVENT_END,
        "OFF_FOIL on the exitHold + 1 -th sub-exit sample, event " + ev.toString());
    Test.assert(d.state == FlightDetector.STATE_OFF);
    // end backdated to the first sub-exit sample: 11 s from the first qualifying sample
    Test.assertMessage((d.foilTimeS - 11.0).abs() < 0.0001,
        "foilTime = 11 (t0 -> first sub-exit sample), got " + d.foilTimeS.format("%.2f"));
    Test.assertMessage((d.longestS - 11.0).abs() < 0.0001,
        "longest = 11, got " + d.longestS.format("%.2f"));
    return true;
}

// ---- TurnDetector (docs/algorithms.md "Turn detection & classification") ----
// Synthetic 1 Hz arrays, no clock calls: every helper below drives the detector one
// second at a time with an explicit COG/speed, exactly as MetricsEngine would.

function turnDefaults() as Void {
    AppSettings.foilEntryMps = 12.0 / 3.6;
    AppSettings.foilExitMps = 8.0 / 3.6;
    AppSettings.windDirection = -1;
}

// n seconds of straight running at `speed`, holding `cog`.
function runStraight(d as TurnDetector, n as Number, cog as Float,
        speed as Float) as Number {
    var ev = TurnDetector.EVENT_NONE;
    for (var i = 0; i < n; i++) {
        var e = d.tick(1.0, cog, speed, speed, true, false);
        if (e != TurnDetector.EVENT_NONE) {
            ev = e;
        }
    }
    return ev;
}

// A COG sweep of `steps` seconds at `rate` deg/s starting from `cog`; returns the last event.
function runSweep(d as TurnDetector, startCog as Float, rate as Float, steps as Number,
        speed as Float) as Number {
    var ev = TurnDetector.EVENT_NONE;
    for (var i = 1; i <= steps; i++) {
        var e = d.tick(1.0, startCog + rate * i, speed, speed, true, false);
        if (e != TurnDetector.EVENT_NONE) {
            ev = e;
        }
    }
    return ev;
}

(:test)
function turnCleanJibeFliesThrough(logger as Test.Logger) as Boolean {
    turnDefaults();
    var d = new TurnDetector();
    runStraight(d, 5, 90.0, 8.0);               // approach at 8 m/s
    runSweep(d, 90.0, 30.0, 6, 8.0);            // 180 deg in 6 s, speed carried
    var ev = runStraight(d, 6, 270.0, 8.0);     // powers out -> recovery closes the window
    Test.assertMessage(d.turnCount == 1, "one turn, got " + d.turnCount.toString());
    Test.assertMessage(d.lastKind == TurnDetector.KIND_TURN, "no wind axis -> generic turn");
    Test.assertMessage(ev == TurnDetector.EVENT_FLEW,
        "flew through, event " + ev.toString());
    Test.assertMessage(d.flewCount == 1 && d.fellCount == 0 && d.touchdownCount == 0,
        "outcome tally");
    Test.assertMessage(d.lastScorePct >= 95, "score kept, got " + d.lastScorePct.toString());
    return true;
}

(:test)
function turnSlowSpellIsTouchdown(logger as Test.Logger) as Boolean {
    turnDefaults();
    var d = new TurnDetector();
    runStraight(d, 5, 90.0, 8.0);
    runSweep(d, 90.0, 30.0, 6, 8.0);
    // 3 s below the stop floor (2 s of measurable spell), then back on the foil
    runStraight(d, 3, 270.0, 0.5);
    var ev = runStraight(d, 6, 270.0, 8.0);
    Test.assertMessage(d.turnCount == 1, "one turn");
    Test.assertMessage(ev == TurnDetector.EVENT_TOUCHDOWN,
        "touchdown, event " + ev.toString());
    Test.assertMessage(d.touchdownCount == 1 && d.fellCount == 0, "outcome tally");
    Test.assertMessage(d.lastScorePct < 20, "score collapsed, got "
        + d.lastScorePct.toString());
    return true;
}

(:test)
function turnCollapseIsFellIn(logger as Test.Logger) as Boolean {
    turnDefaults();
    var d = new TurnDetector();
    runStraight(d, 5, 90.0, 8.0);
    runSweep(d, 90.0, 30.0, 6, 8.0);
    // never gets going again: the window runs to the 12 s lookahead cap
    var ev = runStraight(d, 14, 270.0, 0.2);
    Test.assertMessage(d.turnCount == 1, "one turn");
    Test.assertMessage(ev == TurnDetector.EVENT_FELL, "fell in, event " + ev.toString());
    Test.assertMessage(d.fellCount == 1 && d.touchdownCount == 0, "outcome tally");
    return true;
}

(:test)
function turnSuccessIsScoreOnlyNotOutcome(logger as Test.Logger) as Boolean {
    // lab/src/wingfoil_lab/turns.py `_build_turn`: success = score >= turnSuccessPct AND the
    // minimum over [start, end + minSpeedLag] stayed above foilExitSpeed. It is computed from
    // that window alone -- a loss of foil LATER in the recovery-gated outcome window sets the
    // outcome to `touchdown` and must not retract the success. The two used to be coupled.
    turnDefaults();
    var d = new TurnDetector();
    // 180 deg jibe at 4.2 m/s with the speed carried all the way through the sweep
    runStraight(d, 5, 90.0, 4.2);
    runSweep(d, 90.0, 30.0, 6, 4.2);
    // 4 s of mush at 3.1 m/s: above foilExit and >= 70 % of the entry speed, so the score
    // window closes clean, but below the recovery threshold, so the window stays open
    runStraight(d, 4, 270.0, 3.1);
    // ... and only THEN, 5 s past the sweep, he touches down
    runStraight(d, 3, 270.0, 0.5);
    var ev = runStraight(d, 4, 270.0, 8.0);     // pumps back up: the window closes

    Test.assertMessage(d.turnCount == 1, "one turn, got " + d.turnCount.toString());
    Test.assertMessage(ev == TurnDetector.EVENT_TOUCHDOWN,
        "outcome is a touchdown, event " + ev.toString());
    Test.assertMessage(d.touchdownCount == 1 && d.fellCount == 0 && d.flewCount == 0,
        "outcome tally");
    Test.assertMessage(d.lastScorePct >= 70,
        "score kept through the sweep, got " + d.lastScorePct.toString());
    Test.assertMessage(d.successCount == 1,
        "a carried turn stays successful despite the later touchdown, successCount "
        + d.successCount.toString());
    return true;
}

(:test)
function turnWallowIsNotDetected(logger as Test.Logger) as Boolean {
    turnDefaults();
    var d = new TurnDetector();
    // 2.5 m/s drift (clears the COG speed floor) spinning 180 deg in 4 s: 10 m of arc,
    // 3.2 m radius -> the spatial gate drops it. Angle alone would call this a jibe.
    runStraight(d, 5, 0.0, 2.5);
    runSweep(d, 0.0, 45.0, 4, 2.5);
    runStraight(d, 6, 180.0, 2.5);
    Test.assertMessage(d.turnCount == 0, "wallow not a turn, got " + d.turnCount.toString());
    Test.assertMessage(d.rejectedCount == 0, "dropped, not rejected");
    return true;
}

(:test)
function turnBearAwayNotCountedAsJibe(logger as Test.Logger) as Boolean {
    turnDefaults();
    AppSettings.windDirection = 0;              // wind from north
    var d = new TurnDetector();
    // 60 -> 150 deg: TWA 60 -> 150, crosses neither head-to-wind nor dead downwind
    runStraight(d, 5, 60.0, 8.0);
    runSweep(d, 60.0, 30.0, 3, 8.0);
    runStraight(d, 6, 150.0, 8.0);
    Test.assertMessage(d.jibeCount == 0 && d.tackCount == 0, "bear-away is not a maneuver");
    Test.assertMessage(d.turnCount == 0, "not counted, got " + d.turnCount.toString());
    Test.assertMessage(d.rejectedCount == 1, "rejected as a course change");
    AppSettings.windDirection = -1;
    return true;
}

(:test)
function turnJibeClassifiedWithWind(logger as Test.Logger) as Boolean {
    turnDefaults();
    AppSettings.windDirection = 0;              // wind from north -> downwind is 180
    var d = new TurnDetector();
    // 120 -> 240 deg sweeps through dead downwind: a jibe
    runStraight(d, 5, 120.0, 8.0);
    runSweep(d, 120.0, 30.0, 4, 8.0);
    runStraight(d, 6, 240.0, 8.0);
    Test.assertMessage(d.jibeCount == 1, "one jibe, got " + d.jibeCount.toString());
    Test.assertMessage(d.tackCount == 0, "not a tack");
    Test.assertMessage(d.turnCount == 1 && d.successCount == 1, "counted and successful");
    AppSettings.windDirection = -1;
    return true;
}

(:test)
function turnSubmersionForcesFellIn(logger as Test.Logger) as Boolean {
    turnDefaults();
    var d = new TurnDetector();
    runStraight(d, 5, 90.0, 8.0);
    runSweep(d, 90.0, 30.0, 6, 8.0);
    // speed says he kept moving, the barometer says the wrist went under: fell in outright
    var ev = TurnDetector.EVENT_NONE;
    for (var i = 0; i < 8; i++) {
        var e = d.tick(1.0, 270.0, 8.0, 8.0, true, i == 0);
        if (e != TurnDetector.EVENT_NONE) {
            ev = e;
        }
    }
    Test.assertMessage(ev == TurnDetector.EVENT_FELL,
        "baro evidence wins, event " + ev.toString());
    Test.assertMessage(d.fellCount == 1, "counted as a fall");
    return true;
}

(:test)
function turnOffFoilNotCounted(logger as Test.Logger) as Boolean {
    turnDefaults();
    var d = new TurnDetector();
    // same geometry as the clean jibe, but never near a flight (turnContext)
    for (var i = 0; i < 5; i++) {
        d.tick(1.0, 90.0, 8.0, 8.0, false, false);
    }
    for (var i = 1; i <= 6; i++) {
        d.tick(1.0, 90.0 + 30.0 * i, 8.0, 8.0, false, false);
    }
    for (var i = 0; i < 6; i++) {
        d.tick(1.0, 270.0, 8.0, 8.0, false, false);
    }
    Test.assertMessage(d.turnCount == 0, "turns while swimming don't count");
    return true;
}

(:test)
function speedRecordsPbEvents(logger as Test.Logger) as Boolean {
    var r = new SpeedRecords();
    Test.assert(r.tick(5.0) == SpeedRecords.PB_NONE);          // 2 s window not full yet
    Test.assert((r.tick(5.0) & SpeedRecords.PB_2S) != 0);      // first full 2 s window
    for (var i = 0; i < 7; i++) {
        Test.assert(r.tick(5.0) == SpeedRecords.PB_NONE);      // flat speed: no new PBs
    }
    Test.assert((r.tick(5.0) & SpeedRecords.PB_10S) != 0);     // first full 10 s window
    var ev = r.tick(7.0);                                      // burst: both windows rise
    Test.assert((ev & SpeedRecords.PB_2S) != 0);
    Test.assert((ev & SpeedRecords.PB_10S) != 0);
    Test.assertMessage((r.best2sMps - 6.0).abs() < 0.0001, "best2s = mean(5,7)");
    r.onGap();
    Test.assert(r.tick(9.0) == SpeedRecords.PB_NONE);          // windows restart after gap
    return true;
}

// ---- Turns page layout ----
// Round displays clip at the corners, not at a bounding box: a block that fits the width at
// the vertical centre can still lose its ends four rows down. This measures every row of the
// Turns page with the device's real font metrics (a buffered-bitmap Dc) at its worst-case
// content and asserts all four corners of each text box sit inside the glass. It is the
// headless twin of eyeballing a screenshot, and unlike a screenshot it runs on every device.

// The furthest corner of a w x h text box centred at (cx, y), as a radius from the centre.
function cornerRadius(w as Number, h as Number, y as Number, cy as Number) as Float {
    var dy = (y - cy).abs() + h / 2.0;
    var dx = w / 2.0;
    return Math.sqrt(dx * dx + dy * dy);
}

(:test)
function turnsPageFitsRoundDisplay(logger as Test.Logger) as Boolean {
    var ref = Graphics.createBufferedBitmap({:width => 454, :height => 454});
    var bmp = ref.get();
    Test.assertMessage(bmp != null, "buffered bitmap");
    var dc = (bmp as Graphics.BufferedBitmap).getDc();
    var cy = 227;
    var radius = 227.0 - 4.0;      // 4 px of bezel margin

    var hT = dc.getFontHeight(Graphics.FONT_XTINY);
    var hHot = dc.getFontHeight(Graphics.FONT_NUMBER_HOT);
    var hL = dc.getFontHeight(Graphics.FONT_LARGE);
    var hS = dc.getFontHeight(Graphics.FONT_SMALL);

    // row 0: header, widest with a wind axis set
    var header = "tack / jibe  NNE";
    var r = cornerRadius(dc.getTextWidthInPixels(header, Graphics.FONT_XTINY), hT,
        RecordingView.turnsRowY(cy, hT, hHot, hL, hS, 0), cy);
    Test.assertMessage(r <= radius, "header corner " + r.format("%.0f") + " > " + radius);

    // row 1: two 2-digit counts and the separator
    r = cornerRadius(RecordingView.splitCountWidth(dc, "99", "99"), hHot,
        RecordingView.turnsRowY(cy, hT, hHot, hL, hS, 1), cy);
    Test.assertMessage(r <= radius, "counts corner " + r.format("%.0f") + " > " + radius);

    // row 2: longest outcome word next to the longest score
    r = cornerRadius(RecordingView.outcomeWidth(dc, "TOUCH", "100%"), hL,
        RecordingView.turnsRowY(cy, hT, hHot, hL, hS, 2), cy);
    Test.assertMessage(r <= radius, "outcome corner " + r.format("%.0f") + " > " + radius);

    // row 3: three 2-digit tallies
    r = cornerRadius(RecordingView.tallyWidth(dc, "99", "99", "99"), hS,
        RecordingView.turnsRowY(cy, hT, hHot, hL, hS, 3), cy);
    Test.assertMessage(r <= radius, "tally corner " + r.format("%.0f") + " > " + radius);

    // and the rows must not collide
    var y0 = RecordingView.turnsRowY(cy, hT, hHot, hL, hS, 0);
    var y1 = RecordingView.turnsRowY(cy, hT, hHot, hL, hS, 1);
    var y2 = RecordingView.turnsRowY(cy, hT, hHot, hL, hS, 2);
    var y3 = RecordingView.turnsRowY(cy, hT, hHot, hL, hS, 3);
    Test.assertMessage(y1 - y0 >= (hT + hHot) / 2, "header/counts gap");
    Test.assertMessage(y2 - y1 >= (hHot + hL) / 2, "counts/outcome gap");
    Test.assertMessage(y3 - y2 >= (hL + hS) / 2, "outcome/tally gap");
    logger.debug("turns page rows y=" + y0.toString() + "," + y1.toString() + ","
        + y2.toString() + "," + y3.toString() + " heights " + hT.toString() + ","
        + hHot.toString() + "," + hL.toString() + "," + hS.toString());
    return true;
}

