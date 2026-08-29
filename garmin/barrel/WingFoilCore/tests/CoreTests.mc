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
    cfg.windDirection = 0;                      // wind from north
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
