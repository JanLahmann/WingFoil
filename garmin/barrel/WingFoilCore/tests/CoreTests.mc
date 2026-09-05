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
    cfg.setWindDirection(-1);
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

// The session's FLYING distance, metre by metre, on a feed whose every segment is known.
// foilDistM is the twin of foilTimeS, so this asserts the three places they are written
// together — accumulate, backdate the end, discard a short flight — with exact numbers rather
// than a tolerance: at 1 Hz with a constant distDelta the arithmetic is closed-form.
(:test)
function flightDetectorTracksFlyingDistance(logger as Test.Logger) as Boolean {
    var d = new FlightDetector(coreDefaults());
    Test.assertMessage(d.foilDistM == 0.0, "a fresh session has flown no metres");

    // 10 s of slow taxi at 2 m/s: off foil throughout, 20 m that must not count
    for (var i = 0; i < 10; i++) {
        d.tick(1.0, 2.0, 2.0);
    }
    Test.assertMessage(d.foilDistM == 0.0, "taxiing is not flying, got "
        + d.foilDistM.format("%.1f"));

    // 20 samples at 5 m/s. Sample 3 confirms ON (entryHold + 1) and is backdated in TIME
    // only, so the metres start with sample 4: 17 samples x 5 m = 85 m.
    for (var i = 0; i < 20; i++) {
        d.tick(1.0, 5.0, 5.0);
    }
    Test.assert(d.state == FlightDetector.STATE_ON && d.flightCount == 1);
    Test.assertMessage((d.foilDistM - 85.0).abs() < 0.0001,
        "17 flying samples x 5 m = 85, got " + d.foilDistM.format("%.2f"));

    // 4 samples at 1 m/s: the end backdates to the FIRST sub-exit sample, so exactly one of
    // those metres stays on the foil and three come back off it. 85 + 4 - 3 = 86.
    for (var i = 0; i < 4; i++) {
        d.tick(1.0, 1.0, 1.0);
    }
    Test.assert(d.state == FlightDetector.STATE_OFF && d.flightCount == 1);
    Test.assertMessage((d.foilDistM - 86.0).abs() < 0.0001,
        "exit backdate leaves 86 m, got " + d.foilDistM.format("%.2f"));
    Test.assertMessage((d.longestM - 86.0).abs() < 0.0001,
        "the one flight IS the longest, got " + d.longestM.format("%.2f"));

    // A second burst too short to count: 4 samples up (3 s of flight, under minFlight 5) and
    // 4 back down. It is never a flight, so it must leave the session total untouched — the
    // same rule foilTimeS keeps, and the reason the discard branch subtracts currentFlightM.
    for (var i = 0; i < 4; i++) {
        d.tick(1.0, 5.0, 5.0);
    }
    for (var i = 0; i < 4; i++) {
        d.tick(1.0, 1.0, 1.0);
    }
    Test.assert(d.state == FlightDetector.STATE_OFF);
    Test.assertMessage(d.flightCount == 1, "the short burst was counted as a flight");
    Test.assertMessage((d.foilDistM - 86.0).abs() < 0.0001,
        "a discarded flight leaves no metres behind, got " + d.foilDistM.format("%.2f"));
    // and the share is a share: 86 m of the 20 + 100 + 4 + 20 + 4 = 148 m the odometer saw
    logger.debug("foilDist " + d.foilDistM.format("%.0f") + " m of 148 m fed");
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
    cfg.setWindDirection(0);                    // wind from north
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
    cfg.setWindDirection(0);                    // wind from north -> downwind is 180
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

// ---- Odometer teleport guard ----

// The session page read 37 986 km in the simulator: distance was the firmware odometer
// reading itself, and FIT replay opens at the simulator's default location before jumping to
// the clip's, so one tick booked a continent. A watch does the same in miniature every time a
// fix returns far from where it was lost.
(:test)
function odometerRejectsTeleports(logger as Test.Logger) as Boolean {
    // an ordinary tick: the odometer step is what counts, not the Doppler estimate
    Test.assertEqual(Odometer.gate(8.4, 8.2, 1.0), 8.4);
    // a slow tick with a stationary rider still counts the metre the odometer moved
    Test.assertEqual(Odometer.gate(1.0, 0.0, 1.0), 1.0);
    // firmware smoothing may run ahead of Doppler for a tick; up to 3x is still believed
    Test.assertEqual(Odometer.gate(24.0, 8.0, 1.0), 24.0);
    // ... beyond that the tick falls back to the Doppler integral
    Test.assertEqual(Odometer.gate(35.0, 8.0, 1.0), 8.0);
    // the teleport itself: a whole continent in one second becomes one second of riding
    Test.assertEqual(Odometer.gate(8000000.0, 8.2, 1.0), 8.2);
    // a backwards odometer (activity reset, lap rollover) never subtracts distance
    Test.assertEqual(Odometer.gate(-500.0, 8.2, 1.0), 8.2);
    // no speed and no movement adds nothing at all
    Test.assertEqual(Odometer.gate(0.0, 0.0, 1.0), 0.0);
    // the cap scales with the tick, so a 3 s gap is not judged as a 1 s one
    Test.assertEqual(Odometer.gate(28.0, 0.0, 3.0), 28.0);
    Test.assertEqual(Odometer.gate(28.0, 0.0, 1.0), 0.0);

    // ... and through the stateful path: joining a clip cut out of a longer session, whose
    // odometer already reads 9.5 km, must not count those 9.5 km as ours.
    var odo = new Odometer();
    Test.assertEqual(odo.step(9469.6, 8.2, 1.0), 8.2);        // first reading: origin only
    var total = 0.0;
    total += odo.step(9477.9, 8.3, 1.0);                       // 8.3 m of real riding
    total += odo.step(4000000.0, 8.1, 1.0);                    // teleport -> Doppler
    total += odo.step(4000008.0, 8.0, 1.0);                    // continues from the new origin
    Test.assertMessage((total - 24.4).abs() < 0.01,
        "odometer total " + total.toString() + " m, expected 24.4");
    logger.debug("odometer: teleports fall back to Doppler, normal steps pass through");
    return true;
}

// ---- Speed plausibility ----

// One impossible sample is enough to ruin a session: SpeedRecords latches the best value it
// ever saw and distance integrates it. FIT replay produced 1.4e7 m/s, which showed as a
// 50 675 121 km/h best-2 s and 14 934 km of distance on the store screenshots.
(:test)
function implausibleSpeedIsNotARecord(logger as Test.Logger) as Boolean {
    Test.assert(speedPlausible(0.0));
    Test.assert(speedPlausible(9.4));                  // a very fast wing run
    Test.assert(speedPlausible(MAX_SPEED_MPS));        // the boundary is still believed
    Test.assert(!speedPlausible(MAX_SPEED_MPS + 0.1));
    Test.assert(!speedPlausible(14076422.0));          // the sample the simulator produced
    Test.assert(!speedPlausible(-1.0));                // a negative speed is not a speed

    // and it must not survive into a record: the gap path is the one a bad sample takes
    var r = new SpeedRecords();
    for (var i = 0; i < 5; i++) {
        r.tick(9.0);
    }
    var before = r.best2sMps;
    r.onGap();                                          // what the engines call for a bad sample
    for (var i = 0; i < 5; i++) {
        r.tick(9.0);
    }
    Test.assertMessage((r.best2sMps - before).abs() < 0.001,
        "best2s moved across a gap: " + before.toString() + " -> " + r.best2sMps.toString());
    logger.debug("speed gate: band is 0.." + MAX_SPEED_MPS.toString() + " m/s");
    return true;
}


// ---- Turn streaks (docs/algorithms.md "Turn streaks") ----
// A tally says how the session went; a streak says how it FELT. These assert the exact two
// rules from the contract — dry survives a touchdown and dies on a fall, flew dies on
// anything that is not a clean fly-through — plus the one that is easy to get wrong: a
// rejected sweep is INVISIBLE to both, neither extending nor breaking a run.

// One clean 180 deg jibe carried all the way through, at `speed`.
function streakFlyThrough(d as TurnDetector, cog as Float) as Void {
    runStraight(d, 5, cog, 8.0);
    runSweep(d, cog, 30.0, 6, 8.0);
    runStraight(d, 6, cog + 180.0, 8.0);
}

// A jibe with a brief touch: off the foil, then pumped straight back up. Never swam.
function streakTouchdown(d as TurnDetector, cog as Float) as Void {
    runStraight(d, 5, cog, 8.0);
    runSweep(d, cog, 30.0, 6, 8.0);
    runStraight(d, 3, cog + 180.0, 0.5);
    runStraight(d, 6, cog + 180.0, 8.0);
}

// A jibe he swam out of: never gets going again inside the lookahead cap.
function streakFellIn(d as TurnDetector, cog as Float) as Void {
    runStraight(d, 5, cog, 8.0);
    runSweep(d, cog, 30.0, 6, 8.0);
    runStraight(d, 14, cog + 180.0, 0.2);
}

// n seconds OFF the foil at `speed`, holding `cog`. The flight-end half of the streak rule
// needs the flying flag to actually fall, which runStraight never lets it do.
function runOffFoil(d as TurnDetector, n as Number, cog as Float, speed as Float) as Void {
    for (var i = 0; i < n; i++) {
        d.tick(1.0, cog, speed, speed, false, false);
    }
}

(:test)
function turnStreaksFollowTheOutcomeLadder(logger as Test.Logger) as Boolean {
    var d = new TurnDetector(coreDefaults());
    Test.assertEqual(d.dryStreak, 0);
    Test.assertEqual(d.bestDryStreak, 0);
    Test.assertEqual(d.flewStreak, 0);
    Test.assertEqual(d.bestFlewStreak, 0);

    // two clean ones: both runs advance together
    streakFlyThrough(d, 0.0);
    streakFlyThrough(d, 0.0);
    Test.assertMessage(d.flewCount == 2, "two fly-throughs, got " + d.flewCount.toString());
    Test.assertEqual(d.dryStreak, 2);
    Test.assertEqual(d.flewStreak, 2);

    // a touchdown: he stayed OUT OF THE WATER, so dry survives and only flew resets
    streakTouchdown(d, 0.0);
    Test.assertMessage(d.touchdownCount == 1, "one touchdown");
    Test.assertMessage(d.dryStreak == 3,
        "a touchdown must not end a dry run, got " + d.dryStreak.toString());
    Test.assertEqual(d.flewStreak, 0);
    Test.assertEqual(d.bestFlewStreak, 2);
    Test.assertEqual(d.bestDryStreak, 3);

    // he swims: both runs end
    streakFellIn(d, 0.0);
    Test.assertMessage(d.fellCount == 1, "one fall");
    Test.assertEqual(d.dryStreak, 0);
    Test.assertEqual(d.flewStreak, 0);
    Test.assertEqual(d.bestDryStreak, 3);       // the best survives the reset

    // ... and a shorter run afterwards does not lower the session best
    streakFlyThrough(d, 0.0);
    Test.assertEqual(d.dryStreak, 1);
    Test.assertEqual(d.bestDryStreak, 3);
    Test.assertEqual(d.bestFlewStreak, 2);

    // the invariant the contract states: flew <= dry, always
    Test.assertMessage(d.bestFlewStreak <= d.bestDryStreak,
        "flew streak " + d.bestFlewStreak.toString() + " > dry streak "
            + d.bestDryStreak.toString());
    logger.debug("streaks: dry " + d.bestDryStreak.toString() + " best, flew "
        + d.bestFlewStreak.toString() + " best over " + d.turnCount.toString() + " turns");
    return true;
}

(:test)
function rejectedSweepsAreInvisibleToStreaks(logger as Test.Logger) as Boolean {
    var cfg = coreDefaults();
    cfg.setWindDirection(0);                    // wind from north
    var d = new TurnDetector(cfg);

    // Two clean jibes with a BEAR-AWAY between them. A course change is not a maneuver the
    // rider attempted: counting it either way would make the streak depend on how far he bore
    // away between two jibes, which is not what the number claims.
    runStraight(d, 5, 120.0, 8.0);
    runSweep(d, 120.0, 30.0, 4, 8.0);           // 120 -> 240 through dead downwind: a jibe
    runStraight(d, 6, 240.0, 8.0);
    Test.assertMessage(d.jibeCount == 1, "first jibe, got " + d.jibeCount.toString());
    Test.assertEqual(d.dryStreak, 1);

    // 60 -> 150: crosses neither axis end, so KIND_REJECT
    runStraight(d, 5, 60.0, 8.0);
    runSweep(d, 60.0, 30.0, 3, 8.0);
    runStraight(d, 6, 150.0, 8.0);
    Test.assertMessage(d.rejectedCount == 1,
        "expected one rejected sweep, got " + d.rejectedCount.toString());
    Test.assertMessage(d.dryStreak == 1,
        "a rejected sweep moved the streak: " + d.dryStreak.toString());
    Test.assertMessage(d.flewStreak == 1, "a rejected sweep moved the flew streak");

    // the next real jibe continues the run rather than starting a new one
    runStraight(d, 5, 120.0, 8.0);
    runSweep(d, 120.0, 30.0, 4, 8.0);
    runStraight(d, 6, 240.0, 8.0);
    Test.assertMessage(d.jibeCount == 2, "second jibe, got " + d.jibeCount.toString());
    Test.assertMessage(d.dryStreak == 2,
        "the run must span the course change, got " + d.dryStreak.toString());
    Test.assertEqual(d.bestDryStreak, 2);
    // and the streaks count exactly the population turnCount does
    Test.assertEqual(d.turnCount, 2);
    logger.debug("bear-away between two jibes: streak " + d.dryStreak.toString()
        + " over " + d.turnCount.toString() + " counted turns, "
        + d.rejectedCount.toString() + " rejected");
    return true;
}

// ---- Clean jibes (device app 0.9.5, docs/presentation.md "Clean jibe") ----
// `cleanJibeCount` is the count the watch's CPH divides by an hour, and it is the INTERSECTION
// of two facts decided at two different moments: the sweep was classified a JIBE when it
// closed, and it was SUCCESSFUL when its outcome window resolved. Every way of getting that
// intersection wrong looks like a plausible number on a page, so all four corners are pinned
// here — a clean jibe, a successful TACK, a jibe he swam out of, and a jibe with no axis to
// name it.
(:test)
function cleanJibesAreSuccessfulJibesAndNothingElse(logger as Test.Logger) as Boolean {
    var cfg = coreDefaults();
    cfg.setWindDirection(0);                    // wind from north

    // (1) 120 -> 240 through dead downwind at a constant 8 m/s: a jibe, carried, so a clean one
    var d = new TurnDetector(cfg);
    runStraight(d, 5, 120.0, 8.0);
    runSweep(d, 120.0, 30.0, 4, 8.0);
    runStraight(d, 6, 240.0, 8.0);
    Test.assertMessage(d.jibeCount == 1, "not a jibe: " + d.jibeCount.toString());
    Test.assertMessage(d.successCount == 1, "a jibe carried at 8 m/s throughout is successful");
    Test.assertMessage(d.cleanJibeCount == 1,
        "a successful jibe must be a clean jibe, got " + d.cleanJibeCount.toString());
    Test.assertMessage(d.lastCleanJibe, "lastCleanJibe was not published for a clean jibe");

    // (2) 300 -> 60, the same shape through HEAD to wind: a tack, equally well carried, and
    // NOT a clean jibe. This is the assertion that stops cleanJibeCount drifting into being a
    // second spelling of successCount.
    var t = new TurnDetector(cfg);
    runStraight(t, 5, 300.0, 8.0);
    runSweep(t, 300.0, 30.0, 4, 8.0);
    runStraight(t, 6, 60.0, 8.0);
    Test.assertMessage(t.tackCount == 1, "not a tack: " + t.tackCount.toString());
    Test.assertMessage(t.successCount == 1, "the tack was carried just as well");
    Test.assertMessage(t.cleanJibeCount == 0,
        "a successful TACK was counted as a clean jibe");
    Test.assertMessage(!t.lastCleanJibe, "lastCleanJibe was published for a tack");

    // (3) a jibe he swam out of: classified, counted, and not clean — the speed floor is the
    // whole point of the word.
    var w = new TurnDetector(cfg);
    runStraight(w, 5, 120.0, 8.0);
    runSweep(w, 120.0, 30.0, 4, 8.0);
    runStraight(w, 14, 240.0, 0.2);
    Test.assertMessage(w.jibeCount == 1, "the swim was still a jibe");
    Test.assertMessage(w.cleanJibeCount == 0, "a jibe he swam out of is not clean");
    Test.assertMessage(!w.lastCleanJibe,
        "lastCleanJibe must go false again on the next turn that is not one");

    // (4) NO WIND AXIS, the same carried 180: a generic turn, successful, and not a clean jibe,
    // because nothing named it a jibe. This is the shape of the watch's auto-wind session
    // before the estimator locks — CPH under-reads there, deliberately and conservatively
    // (TurnDetector.backfillWindSplit).
    var g = new TurnDetector(coreDefaults());
    runStraight(g, 5, 120.0, 8.0);
    runSweep(g, 120.0, 30.0, 4, 8.0);
    runStraight(g, 6, 240.0, 8.0);
    Test.assertMessage(g.turnCount == 1, "the sweep was not counted at all");
    Test.assertMessage(g.jibeCount == 0, "there was no axis to call it a jibe");
    Test.assertMessage(g.successCount == 1, "it was carried, axis or no axis");
    Test.assertMessage(g.cleanJibeCount == 0,
        "an unclassified turn cannot be a clean JIBE");

    // (5) the sweep carried at 8 m/s, then the foil lost in the recovery tail and pumped
    // back: a jibe, scored a success, resolved a TOUCHDOWN — and NOT clean (engine 0.12.0:
    // clean = success AND flew through). This is the page Jan photographed: "Jibe 13 ·
    // fell in" wearing a star.
    var x = new TurnDetector(cfg);
    runStraight(x, 5, 120.0, 8.0);
    runSweep(x, 120.0, 30.0, 4, 8.0);
    runStraight(x, 2, 240.0, 8.0);
    runStraight(x, 4, 240.0, 1.0);              // off the foil, still making way
    runStraight(x, 8, 240.0, 8.0);              // and back up: a touchdown, not a fall
    Test.assertMessage(x.jibeCount == 1, "the touchdown jibe was still a jibe");
    Test.assertMessage(x.touchdownCount == 1,
        "expected one touchdown, got " + x.touchdownCount.toString());
    Test.assertMessage(x.cleanJibeCount == 0,
        "a jibe that touched down after the sweep must not be clean");
    Test.assertMessage(!x.lastCleanJibe, "lastCleanJibe was published for a touchdown jibe");

    // and the invariant every page draws on: clean jibes are a subset of both populations
    Test.assertMessage(d.cleanJibeCount <= d.jibeCount && d.cleanJibeCount <= d.successCount,
        "clean jibes must be a subset of the jibes AND of the successful turns");

    logger.debug("clean jibes: jibe " + d.cleanJibeCount.toString() + "/"
        + d.jibeCount.toString() + ", tack " + t.cleanJibeCount.toString() + "/"
        + t.tackCount.toString() + ", swim " + w.cleanJibeCount.toString() + "/"
        + w.jibeCount.toString() + ", no axis " + g.cleanJibeCount.toString() + "/"
        + g.turnCount.toString());
    return true;
}


// The amendment: a swim that no turn explains still ends the run. A rider who ventilates the
// foil on a straight reach and goes in HAS been in the water, and a "dry" streak that counted
// only turn outcomes was quietly claiming otherwise — it overcounted, on the corpus by one
// (12 rather than 11 dry) and by twice that on the strict run (10 rather than 5 flew).
(:test)
function straightLineFallsBreakTheStreaks(logger as Test.Logger) as Boolean {
    var d = new TurnDetector(coreDefaults());

    streakFlyThrough(d, 0.0);
    streakFlyThrough(d, 0.0);
    Test.assertEqual(d.dryStreak, 2);
    Test.assertEqual(d.flewStreak, 2);

    // ...and now he ventilates on a straight reach and swims. No sweep, no turn, no counter
    // moves — and both runs are over anyway.
    var turnsBefore = d.turnCount;
    var flewBefore = d.flewCount;
    runOffFoil(d, 14, 0.0, 0.2);
    Test.assertMessage(d.turnCount == turnsBefore,
        "a straight-line fall must not become a turn");
    Test.assertMessage(d.flewCount == flewBefore, "no outcome may be tallied for it");
    Test.assertMessage(d.dryStreak == 0,
        "a swim outside a turn left the dry run at " + d.dryStreak.toString());
    Test.assertEqual(d.flewStreak, 0);
    Test.assertEqual(d.bestDryStreak, 2);       // the best still stands

    // the run restarts from the next clean turn
    runStraight(d, 5, 0.0, 8.0);
    streakFlyThrough(d, 0.0);
    Test.assertEqual(d.dryStreak, 1);
    Test.assertEqual(d.flewStreak, 1);

    // A straight-line TOUCHDOWN — off the foil, briefly slow, up again — is not a swim: dry
    // survives it, the strict run does not. Same asymmetry as a turn's touchdown.
    runOffFoil(d, 2, 0.0, 0.5);
    runStraight(d, 4, 0.0, 8.0);                 // flying again closes the window
    Test.assertMessage(d.dryStreak == 1,
        "a straight-line touchdown ended the dry run: " + d.dryStreak.toString());
    Test.assertEqual(d.flewStreak, 0);

    // A GLIDE-OUT changes nothing at all: he came off the foil and kept making way.
    streakFlyThrough(d, 0.0);
    var dry = d.dryStreak;
    runOffFoil(d, 6, 0.0, 5.0);                  // never reaches the stop floor
    runStraight(d, 4, 0.0, 8.0);
    Test.assertMessage(d.dryStreak == dry,
        "a glide-out broke the dry run: " + d.dryStreak.toString());
    Test.assertMessage(d.flewStreak > 0, "a glide-out broke the flew run");
    logger.debug("straight-line ends: fall resets both, touchdown resets flew only, "
        + "glide-out resets neither");
    return true;
}

// The case the amendment was written for, stated on its own: a fall BETWEEN two clean turns
// must reset both runs, so the two fly-throughs either side never read as a run of two.
(:test)
function aFallBetweenTwoFlewTurnsResetsBothStreaks(logger as Test.Logger) as Boolean {
    var d = new TurnDetector(coreDefaults());
    streakFlyThrough(d, 0.0);
    Test.assertEqual(d.dryStreak, 1);

    runOffFoil(d, 14, 0.0, 0.2);                 // he goes in, no maneuver involved
    Test.assertEqual(d.dryStreak, 0);
    Test.assertEqual(d.flewStreak, 0);

    runStraight(d, 5, 0.0, 8.0);
    streakFlyThrough(d, 0.0);
    Test.assertMessage(d.flewCount == 2, "both turns still flew through");
    Test.assertMessage(d.bestDryStreak == 1,
        "the two fly-throughs were merged into a run of " + d.bestDryStreak.toString());
    Test.assertEqual(d.bestFlewStreak, 1);
    logger.debug("2 fly-throughs split by one swim: best run "
        + d.bestDryStreak.toString() + ", not 2");
    return true;
}

// ---- AutoWind (docs/algorithms.md "Watch approximation: auto wind") ----
//
// Synthetic histograms, driven one second at a time exactly as MetricsEngine would. The
// against-real-data half of the acceptance — the two `ciq` fixtures replayed through this
// same class — lives in garmin/tests/WingfoilTests.mc, because the recorded arrays are
// kilobytes the data field's unit-test build has no reason to carry.

// `ticks` seconds of flying at `speed`, cycling through `cogs`. Returns the last event.
function autoWindRun(aw as AutoWind, cogs as Array<Float>, ticks as Number,
        speed as Float) as Number {
    var last = AutoWind.EV_NONE;
    for (var i = 0; i < ticks; i++) {
        var e = aw.tick(1.0, cogs[i % cogs.size()], speed, true);
        if (e != AutoWind.EV_NONE) {
            last = e;
        }
    }
    return last;
}

function autoWindOffBy(aw as AutoWind, deg as Float) as Float {
    return wrapDeg180(aw.dirDeg.toFloat() - deg).abs();
}

// The ordinary case, and the one the fixtures exercise at scale: two reach lobes with real
// separation, one no-go cone holding distance and the other empty. The cone decides alone —
// the prior is not even consulted — and the answer is the empty end.
(:test)
function autoWindTwoLobesResolveTheAxis(logger as Test.Logger) as Boolean {
    var aw = new AutoWind();
    // Reaches at 110-160 and 200-250 deg: the axis line is 0/180, and the 180 cone catches
    // the inner tails of both lobes while nothing at all runs within 45 deg of north.
    var cogs = [110.0, 120.0, 130.0, 140.0, 150.0, 160.0,
        200.0, 210.0, 220.0, 230.0, 240.0, 250.0] as Array<Float>;
    var ev = autoWindRun(aw, cogs, 200, 10.0);

    Test.assertMessage(ev == AutoWind.EV_LOCK || aw.dirDeg >= 0,
        "the estimator never locked, event " + ev.toString());
    Test.assertMessage(autoWindOffBy(aw, 0.0) <= 20.0,
        "wind should read ~0 deg, got " + aw.dirDeg.toString());
    Test.assertMessage(aw.lastMargin >= aw.FULL_MARGIN,
        "the cone should be decisive here, margin " + aw.lastMargin.format("%.3f"));
    Test.assertMessage(aw.lastPriorVotes == 0,
        "a decisive cone must not consult the prior at all");
    Test.assertMessage(aw.confidence >= 0.5,
        "confidence " + aw.confidence.format("%.2f"));
    logger.debug("two lobes -> wind from " + aw.dirDeg.toString() + " deg, margin "
        + aw.lastMargin.format("%.2f") + " over " + aw.distanceM.format("%.0f") + " m");
    return true;
}

// Nothing is accumulated off the foil or below the COG speed floor — the engine's two
// `foiling_courses` filters, live. Without them a rider drifting sideways on a swim would
// vote in the histogram with whatever the GPS calls his heading.
(:test)
function autoWindIgnoresSwimmingAndSlowDrift(logger as Test.Logger) as Boolean {
    var aw = new AutoWind();
    for (var i = 0; i < 400; i++) {
        aw.tick(1.0, i % 2 == 0 ? 130.0 : 230.0, 10.0, false);      // fast, but not flying
    }
    Test.assertMessage(aw.distanceM == 0.0,
        "off-foil distance reached the histogram: " + aw.distanceM.toString());
    for (var i = 0; i < 400; i++) {
        aw.tick(1.0, i % 2 == 0 ? 130.0 : 230.0, 1.5, true);        // flying, below the floor
    }
    Test.assertMessage(aw.distanceM == 0.0,
        "sub-floor distance reached the histogram: " + aw.distanceM.toString());
    Test.assertMessage(aw.dirDeg < 0, "nothing to estimate from, yet it estimated");
    logger.debug("gates hold: 800 excluded samples, 0 m of histogram mass");
    return true;
}

// Two opposed broad reaches and no upwind work at all: BOTH no-go cones are empty, the
// margin is 0 and the axis line is perfectly usable while its direction is a coin flip.
// This is the case the default-turn-type prior exists for. Under one end of the axis every
// sweep is a tack, under the other every one is a jibe — so a rider who says "I mostly jibe"
// has told the watch which end he was sailing in, and that is the only evidence there is.
(:test)
function autoWindPriorBreaksACoinFlip(logger as Test.Logger) as Boolean {
    var cogs = [100.0, 260.0] as Array<Float>;
    var aw = new AutoWind();
    aw.defaultTurnType = TURN_TYPE_JIBES;
    // Four sweeps 100 -> 260 deg. Under the cone's own pick (the 185 deg end) each crosses
    // head-to-wind and is a TACK; under the other end each crosses dead downwind and is a
    // JIBE. Declared habit "jibes" therefore points at the other end.
    for (var i = 0; i < 4; i++) {
        aw.logSweep(100.0, 160.0);
    }
    autoWindRun(aw, cogs, 200, 10.0);

    Test.assertMessage(aw.dirDeg >= 0, "the prior should have resolved the coin flip");
    Test.assertMessage(aw.lastMargin == 0.0,
        "this case is meant to have empty cones, margin " + aw.lastMargin.format("%.3f"));
    Test.assertMessage(aw.lastPriorVotes == 4,
        "every sweep is a maneuver under both ends, votes " + aw.lastPriorVotes.toString());
    Test.assertMessage(aw.lastPriorFlipped, "the prior should have overturned the cone");
    Test.assertMessage(autoWindOffBy(aw, 5.0) <= 20.0,
        "jibes point at the ~5 deg end, got " + aw.dirDeg.toString());

    // The same session declared the other way round picks the OTHER end. Nothing else moves:
    // the prior touches the 180 deg call and only that.
    var tacky = new AutoWind();
    tacky.defaultTurnType = TURN_TYPE_TACKS;
    for (var i = 0; i < 4; i++) {
        tacky.logSweep(100.0, 160.0);
    }
    autoWindRun(tacky, cogs, 200, 10.0);
    Test.assertMessage(tacky.dirDeg >= 0, "the tack-declaring rider gets an answer too");
    Test.assertMessage(!tacky.lastPriorFlipped, "tacks agree with the cone's own pick");
    Test.assertMessage(autoWindOffBy(tacky, 185.0) <= 20.0,
        "tacks point at the ~185 deg end, got " + tacky.dirDeg.toString());
    logger.debug("coin flip: jibes -> " + aw.dirDeg.toString() + " deg, tacks -> "
        + tacky.dirDeg.toString() + " deg, from the same track");
    return true;
}

// ...and `balanced` switches the prior off, which on a coin flip means NO ANSWER. A wind
// axis the watch cannot justify is worse than none: it would relabel every sweep in the
// session, and the rider has no way to tell a guess from a measurement.
(:test)
function autoWindBalancedLeavesACoinFlipUnresolved(logger as Test.Logger) as Boolean {
    var aw = new AutoWind();
    aw.defaultTurnType = TURN_TYPE_BALANCED;
    for (var i = 0; i < 4; i++) {
        aw.logSweep(100.0, 160.0);
    }
    autoWindRun(aw, [100.0, 260.0] as Array<Float>, 300, 10.0);
    Test.assertMessage(aw.dirDeg < 0,
        "balanced must not resolve an empty-cone session, got " + aw.dirDeg.toString());
    Test.assertMessage(aw.distanceM > aw.MIN_DISTANCE_M,
        "the test needs to have got past the distance floor");
    Test.assertMessage(aw.lastAxisConf >= 0.99,
        "the AXIS is fine, it is the direction that is not: " + aw.lastAxisConf.toString());
    logger.debug("balanced + empty cones: axis conf " + aw.lastAxisConf.format("%.2f")
        + ", no direction adopted");
    return true;
}

// A lock is CONFIRMED: two consecutive qualifying evaluations, 60 s apart, agreeing within
// CONFIRM_DEG. It costs a minute and it is what keeps one freak evaluation from spending the
// one-shot backfill and the vibe on the wrong axis.
(:test)
function autoWindLockNeedsTwoAgreeingEvaluations(logger as Test.Logger) as Boolean {
    var aw = new AutoWind();
    var cogs = [110.0, 120.0, 130.0, 140.0, 150.0, 160.0,
        200.0, 210.0, 220.0, 230.0, 240.0, 250.0] as Array<Float>;
    // 60 s at 10 m/s = 600 m: past the distance floor, so the first evaluation qualifies...
    autoWindRun(aw, cogs, 60, 10.0);
    Test.assertMessage(aw.distanceM >= aw.MIN_DISTANCE_M, "past the floor");
    Test.assertMessage(aw.dirDeg < 0,
        "one qualifying evaluation must not lock, got " + aw.dirDeg.toString());
    // ...and the second confirms it.
    var ev = autoWindRun(aw, cogs, 60, 10.0);
    Test.assertMessage(ev == AutoWind.EV_LOCK, "the second evaluation locks, event "
        + ev.toString());
    Test.assertMessage(aw.dirDeg >= 0, "a direction was adopted");
    logger.debug("lock at " + aw.distanceM.format("%.0f") + " m, two evaluations");
    return true;
}

// Once adopted the readout holds. The estimate keeps converging underneath — it is the whole
// session so far and every minute moves it a little — but a wind bearing that creeps by two
// degrees a minute is unreadable, so only a move of HYSTERESIS_DEG or more is adopted.
(:test)
function autoWindHysteresisHoldsTheReadout(logger as Test.Logger) as Boolean {
    var aw = new AutoWind();
    var cogs = [110.0, 120.0, 130.0, 140.0, 150.0, 160.0,
        200.0, 210.0, 220.0, 230.0, 240.0, 250.0] as Array<Float>;
    autoWindRun(aw, cogs, 200, 10.0);
    var locked = aw.dirDeg;
    Test.assertMessage(locked >= 0, "locked first");

    // Nudge the whole distribution ~10 deg clockwise for another ten minutes. The estimate
    // shifts, the readout does not.
    var shifted = new Array<Float>[cogs.size()];
    for (var i = 0; i < cogs.size(); i++) {
        shifted[i] = cogs[i] + 10.0;
    }
    autoWindRun(aw, shifted, 600, 10.0);
    Test.assertMessage(aw.dirDeg == locked,
        "a sub-threshold drift moved the readout from " + locked.toString() + " to "
        + aw.dirDeg.toString());

    // A real shift does move it: rotate the whole session 90 deg and keep going long enough
    // for the new reaches to dominate the histogram.
    var turned = new Array<Float>[cogs.size()];
    for (var i = 0; i < cogs.size(); i++) {
        turned[i] = cogs[i] + 90.0;
    }
    autoWindRun(aw, turned, 3600, 10.0);
    Test.assertMessage(aw.dirDeg != locked,
        "a 90 deg shift left the readout at " + aw.dirDeg.toString());
    logger.debug("hysteresis: held at " + locked.toString()
        + " deg through a 10 deg drift, moved to " + aw.dirDeg.toString()
        + " deg on a 90 deg shift");
    return true;
}

// The sweep log is capped like SessionHistory's turn log and drops the OLDEST entry: a full
// log means a long session, and the recent turns are the ones the current axis has to explain.
(:test)
function autoWindSweepLogCapsAndDropsOldest(logger as Test.Logger) as Boolean {
    var aw = new AutoWind();
    for (var i = 0; i < aw.SWEEP_MAX + 10; i++) {
        aw.logSweep(i.toFloat(), 160.0);
    }
    Test.assertMessage(aw.sweepCount == aw.SWEEP_MAX,
        "log should saturate at " + aw.SWEEP_MAX.toString() + ", got "
        + aw.sweepCount.toString());
    var entries = aw.sweepEntries();
    Test.assertMessage(entries[aw.SWEEP_MAX - 1] == aw.SWEEP_MAX + 9,
        "the newest sweep must be last, got "
        + entries[aw.SWEEP_MAX - 1].toString());
    Test.assertMessage(entries[0] == 10, "the ten oldest must have fallen off, got "
        + entries[0].toString());
    return true;
}

// ---- the one-shot backfill (TurnDetector.backfillWindSplit) ----
//
// The watch never re-runs classification, with exactly one exception: the first time AutoWind
// adopts an axis, the sweeps it learned that axis FROM are re-named, so the session's counts
// do not start from zero at minute two. It adds splits and moves nothing else.
(:test)
function backfillSplitsTheTurnsTheAxisWasLearnedFrom(logger as Test.Logger) as Boolean {
    var cfg = coreDefaults();
    var d = new TurnDetector(cfg);
    var aw = new AutoWind();

    // Three 120 -> 240 deg sweeps with no wind axis: counted, but generic. The sweep is
    // CONFIRMED a second or two after the rotation stops (that is what the trailing straight
    // run is for), so the log entry is taken after it, exactly where MetricsEngine takes it.
    for (var i = 0; i < 3; i++) {
        var before = d.turnCount;
        runStraight(d, 5, 120.0, 8.0);
        runSweep(d, 120.0, 30.0, 4, 8.0);
        runStraight(d, 6, 240.0, 8.0);
        if (d.turnCount > before) {
            aw.logSweep(d.lastEntryU, d.lastNetDeg);
        }
    }
    Test.assertMessage(d.turnCount == 3, "three turns, got " + d.turnCount.toString());
    Test.assertMessage(d.tackCount == 0 && d.jibeCount == 0, "no axis: nothing is split");
    Test.assertMessage(d.portEntryCount == 0 && d.starboardEntryCount == 0,
        "no axis: there is no side to be on");
    Test.assertMessage(aw.sweepCount == 3, "three sweeps logged, got "
        + aw.sweepCount.toString());

    // The estimator adopts north, and the backfill replays the log once.
    cfg.setAutoWind(0);
    var turnsBefore = d.turnCount;
    var flewBefore = d.flewCount;
    d.backfillWindSplit(aw.sweepEntries(), aw.sweepNets(), aw.sweepCount);
    Test.assertMessage(d.jibeCount == 3,
        "120 -> 240 through dead downwind is a jibe, got " + d.jibeCount.toString());
    Test.assertMessage(d.tackCount == 0, "none of them is a tack");
    Test.assertMessage(d.turnCount == turnsBefore,
        "the backfill must not re-count turns: " + d.turnCount.toString());
    Test.assertMessage(d.flewCount == flewBefore,
        "the backfill must not re-judge outcomes");
    Test.assertMessage(d.portEntryCount + d.starboardEntryCount == 3,
        "each backfilled maneuver gets its entry side");
    logger.debug("backfill: 3 generic turns became " + d.jibeCount.toString()
        + " jibes, turnCount held at " + d.turnCount.toString());
    return true;
}

// A sweep that turns out to be a BEAR-AWAY under the new axis stays the generic turn it was
// counted as. Retracting it would move turnCount, the success percentage and every streak
// that spanned it — i.e. re-judge, on hindsight evidence, observations made at the time.
(:test)
function backfillLeavesBearAwaysAsTheGenericTurnsTheyWere(logger as Test.Logger) as Boolean {
    var cfg = coreDefaults();
    var d = new TurnDetector(cfg);
    var aw = new AutoWind();

    // 60 -> 150 deg: with wind from north this crosses neither axis end.
    runStraight(d, 5, 60.0, 8.0);
    runSweep(d, 60.0, 30.0, 3, 8.0);
    runStraight(d, 6, 150.0, 8.0);
    Test.assertMessage(d.turnCount == 1, "with no axis it is a counted generic turn");
    aw.logSweep(d.lastEntryU, d.lastNetDeg);

    cfg.setAutoWind(0);
    d.backfillWindSplit(aw.sweepEntries(), aw.sweepNets(), aw.sweepCount);
    Test.assertMessage(d.tackCount == 0 && d.jibeCount == 0, "a bear-away is neither");
    Test.assertMessage(d.turnCount == 1,
        "the backfill retracted a counted turn: " + d.turnCount.toString());
    Test.assertMessage(d.rejectedCount == 0, "and it did not retro-reject it either");
    logger.debug("backfill: bear-away stayed a generic turn, turnCount "
        + d.turnCount.toString());
    return true;
}

// A GPS gap is missing evidence, not a swim. An end the detector cannot judge must be
// dropped, exactly as an unjudgeable takeoff effort is — "he might have gone in" must never
// break a run the rider actually kept.
(:test)
function anUnjudgeableFlightEndDoesNotBreakAStreak(logger as Test.Logger) as Boolean {
    var d = new TurnDetector(coreDefaults());
    streakFlyThrough(d, 0.0);
    streakFlyThrough(d, 0.0);
    Test.assertEqual(d.dryStreak, 2);

    runOffFoil(d, 3, 0.0, 0.4);                  // the end opens, evidence starts collecting
    d.onGap();                                    // ...and the fixes stop arriving
    runOffFoil(d, 14, 0.0, 0.4);
    Test.assertMessage(d.dryStreak == 2,
        "a gap was read as a swim, run fell to " + d.dryStreak.toString());
    logger.debug("gap during a flight end: run held at " + d.dryStreak.toString());
    return true;
}

}
