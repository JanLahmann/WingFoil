import Toybox.Lang;
import Toybox.Test;

// Unit tests for the shared detection core (docs/testing.md layer 3). Semantics must mirror
// lab/src/wingfoil_lab/{flight,turns}.py. They live in the barrel, so both consumers (the
// device app and the WingFoil Field data field) run exactly these tests against exactly the
// sources they ship.
//
// The only thing the barrel extraction changed: thresholds are set on an injected
// WingFoilCore.Config instead of the device app's AppSettings module. Every assertion below
// is the one it was before.
//
// They live INSIDE the barrel namespace: a packaged .barrel refuses any symbol outside its
// module, so a test at file scope would break `barrelbuild`.
module WingFoilCore {

function coreDefaults() as Config {
    var cfg = new Config();
    cfg.foilEntryMps = 12.0 / 3.6;
    cfg.foilExitMps = 8.0 / 3.6;
    cfg.entryHoldS = 2;
    cfg.exitHoldS = 3;
    cfg.minFlightS = 5;
    cfg.windDirection = -1;
    return cfg;
}

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
    var d = new FlightDetector(coreDefaults());

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
    var d = new FlightDetector(coreDefaults());
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
    var d = new FlightDetector(coreDefaults());
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
    var d = new FlightDetector(coreDefaults());
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
    var d = new TurnDetector(coreDefaults());
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
    var d = new TurnDetector(coreDefaults());
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
    var d = new TurnDetector(coreDefaults());
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
    var d = new TurnDetector(coreDefaults());
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
    var d = new TurnDetector(coreDefaults());
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
    var cfg = coreDefaults();
    cfg.windDirection = 0;                      // wind from north
    var d = new TurnDetector(cfg);
    // 60 -> 150 deg: TWA 60 -> 150, crosses neither head-to-wind nor dead downwind
    runStraight(d, 5, 60.0, 8.0);
    runSweep(d, 60.0, 30.0, 3, 8.0);
    runStraight(d, 6, 150.0, 8.0);
    Test.assertMessage(d.jibeCount == 0 && d.tackCount == 0, "bear-away is not a maneuver");
    Test.assertMessage(d.turnCount == 0, "not counted, got " + d.turnCount.toString());
    Test.assertMessage(d.rejectedCount == 1, "rejected as a course change");
    return true;
}

(:test)
function turnJibeClassifiedWithWind(logger as Test.Logger) as Boolean {
    var cfg = coreDefaults();
    cfg.windDirection = 0;                      // wind from north -> downwind is 180
    var d = new TurnDetector(cfg);
    // 120 -> 240 deg sweeps through dead downwind: a jibe
    runStraight(d, 5, 120.0, 8.0);
    runSweep(d, 120.0, 30.0, 4, 8.0);
    runStraight(d, 6, 240.0, 8.0);
    Test.assertMessage(d.jibeCount == 1, "one jibe, got " + d.jibeCount.toString());
    Test.assertMessage(d.tackCount == 0, "not a tack");
    Test.assertMessage(d.turnCount == 1 && d.successCount == 1, "counted and successful");
    return true;
}

(:test)
function turnSubmersionForcesFellIn(logger as Test.Logger) as Boolean {
    var d = new TurnDetector(coreDefaults());
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
    var d = new TurnDetector(coreDefaults());
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

}
