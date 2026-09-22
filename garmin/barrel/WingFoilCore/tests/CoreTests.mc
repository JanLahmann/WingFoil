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

// ---- TurnDetector (docs/algorithms/turns.md "Turn detection & classification") ----
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
    // never gets going again: the window runs to the NOT-RECOVERED cap (0.9.19; it was the
    // 12 s lookahead until then, and the stop was already long enough by either clock)
    var ev = runStraight(d, 32, 270.0, 0.2);
    Test.assertMessage(d.turnCount == 1, "one turn");
    Test.assertMessage(ev == TurnDetector.EVENT_FELL, "fell in, event " + ev.toString());
    Test.assertMessage(d.fellCount == 1 && d.touchdownCount == 0, "outcome tally");
    return true;
}

// n seconds of tail at `speed`, with the flight state and the wrist said explicitly: the
// helper the outcome-window tests need and `runStraight` (always flying, never wet) is not.
function runTail(d as TurnDetector, n as Number, cog as Float, speed as Float,
        flying as Boolean, submerged as Boolean) as Number {
    var ev = TurnDetector.EVENT_NONE;
    for (var i = 0; i < n; i++) {
        var e = d.tick(1.0, cog, speed, speed, flying, submerged);
        if (e != TurnDetector.EVENT_NONE) {
            ev = e;
        }
    }
    return ev;
}

// ---- A FALL THE TURN CAUSED IS THE TURN'S FALL (ADR-032, watch 0.9.19) ----
//
// The learner's mush-out: he comes out of the jibe making way but never flying, and coasts
// to a stop well past the 12 s lookahead. Until 0.9.19 the window closed at 12 s with the
// foil merely lost, so the wrist said `touchdown` and the stop that ended it was seen by
// nobody at all -- the phone, re-reading the same FIT, said `fell in`. Now the window
// follows a rider who has not recovered to LOOKAHEAD_NOT_RECOVERED_S and the fall is the
// turn's.
(:test)
function turnMushOutPastTheLookaheadIsTheTurnsFall(logger as Test.Logger) as Boolean {
    var d = new TurnDetector(coreDefaults());
    runStraight(d, 5, 90.0, 8.0);
    runSweep(d, 90.0, 30.0, 6, 8.0);
    // The first tail sample ends the sweep and confirms the turn; the outcome is still open.
    var ev = runTail(d, 1, 270.0, 1.5, false, false);
    Test.assertMessage(ev == TurnDetector.EVENT_TURN,
        "the sweep confirms the turn, event " + ev.toString());
    // 20 s of mush: below foilExit (so the foil is lost) but above the stop floor, and
    // nowhere near RECOVER_PCT of the entry speed, so nothing closes the window.
    ev = runTail(d, 19, 270.0, 1.5, false, false);
    Test.assertMessage(ev == TurnDetector.EVENT_NONE,
        "the window is still open 20 s past the sweep, event " + ev.toString());
    // ...and THIS is what books the fall once rather than twice: while the turn is judging,
    // the straight-line flight-end channel cannot open a window of its own for the same loss.
    Test.assertMessage(d.state == TurnDetector.ST_OUTCOME,
        "the turn still owns the loss at 20 s, state " + d.state.toString());
    // Only then does he stop, and the window is still open to see it.
    ev = runTail(d, 12, 270.0, 0.2, false, false);
    Test.assertMessage(ev == TurnDetector.EVENT_FELL,
        "the mush-out is the turn's fall, event " + ev.toString());
    Test.assertMessage(d.turnCount == 1, "one turn, got " + d.turnCount.toString());
    Test.assertMessage(d.fellCount == 1 && d.touchdownCount == 0 && d.flewCount == 0,
        "one fall, booked once: " + d.fellCount.toString() + " / "
        + d.touchdownCount.toString() + " / " + d.flewCount.toString());
    Test.assertMessage(d.dryStreak == 0, "he swam, so the dry run is over");
    return true;
}

// The other half of the same rule: RECOVERY still closes the tail wherever it happens, so a
// stop long after it belongs to the straight-line channel and not to the turn. Without this
// the 30 s cap would charge a maneuver with a fall it had nothing to do with.
(:test)
function turnRecoveryClosesTheTailBeforeALaterStop(logger as Test.Logger) as Boolean {
    var d = new TurnDetector(coreDefaults());
    runStraight(d, 5, 90.0, 8.0);
    runSweep(d, 90.0, 30.0, 6, 8.0);
    // 6 s off the foil -- the turn is a touchdown whatever happens next
    runTail(d, 6, 270.0, 1.5, false, false);
    // flying again at 8 s: 70 % of 8 m/s held for RECOVER_HOLD_S closes the window
    var ev = runStraight(d, 4, 270.0, 8.0);
    Test.assertMessage(ev == TurnDetector.EVENT_TOUCHDOWN,
        "recovery closes the tail on a touchdown, event " + ev.toString());
    Test.assertMessage(d.touchdownCount == 1 && d.fellCount == 0, "outcome tally");
    Test.assertMessage(d.dryStreak == 1, "a touchdown does not end the dry run");

    // ...and 25 s past the sweep he ventilates on a straight reach and stops. That is a swim,
    // and it breaks the run -- but it is NOT the turn's fall: the ladder is untouched.
    runStraight(d, 5, 270.0, 8.0);
    runTail(d, 12, 270.0, 0.2, false, false);
    runStraight(d, 3, 270.0, 8.0);      // up again: the flight-end window closes and is called
    Test.assertMessage(d.touchdownCount == 1 && d.fellCount == 0,
        "the later stop is not the turn's: " + d.touchdownCount.toString() + " / "
        + d.fellCount.toString());
    Test.assertMessage(d.dryStreak == 0, "the straight-line swim still ends the dry run");
    return true;
}

// ---- THE VERDICT LANDS AT THE STOP (Jan, 22 September 2026) ----
//
// The 30 s tail buys a slow mush-out its fall; it must not make the rider wait for it. A fall
// is monotonic — once the stop spell passes FALL_STOP_S nothing later can make it anything
// else — so the window ends on that tick and the buzz arrives while he is still in the water.
// Before this the wrist sat silent for the rest of the tail and then buzzed about something
// that had happened half a minute earlier.
//
// The arithmetic the test pins: he stops 14 s past the sweep, the first stopped sample buys no
// spell (the both-ends convention needs two), so the spell passes 5 s on the SEVENTH stopped
// sample — 21 s past the sweep, 9 s before the tail would have run out.
(:test)
function turnFallIsCalledTheTickTheStopIsLongEnough(logger as Test.Logger) as Boolean {
    var d = new TurnDetector(coreDefaults());
    runStraight(d, 5, 90.0, 8.0);
    runSweep(d, 90.0, 30.0, 6, 8.0);
    var ev = runTail(d, 1, 270.0, 1.5, false, false);
    Test.assertMessage(ev == TurnDetector.EVENT_TURN,
        "the sweep confirms the turn, event " + ev.toString());
    // 13 s more of mush: off the foil, still making way, nowhere near recovery. Nothing is
    // decided while he is still moving — the tail is doing its job.
    ev = runTail(d, 13, 270.0, 1.5, false, false);
    Test.assertMessage(ev == TurnDetector.EVENT_NONE,
        "nothing is decided while he is still making way, event " + ev.toString());
    // ...and now he stops, one tick at a time, so the ANSWER'S MOMENT is what is asserted and
    // not merely the answer.
    var fellAt = -1;
    for (var i = 1; i <= 16; i++) {
        var e = d.tick(1.0, 270.0, 0.2, 0.2, false, false);
        if (e == TurnDetector.EVENT_FELL && fellAt < 0) {
            fellAt = i;
        }
    }
    Test.assertMessage(fellAt == 7,
        "the fall must land on the stopped sample that carries the spell past FALL_STOP_S "
        + "(the 7th), got " + fellAt.toString());
    Test.assertMessage(d.fellCount == 1 && d.touchdownCount == 0 && d.flewCount == 0,
        "one fall, booked once: " + d.fellCount.toString() + " / "
        + d.touchdownCount.toString() + " / " + d.flewCount.toString());
    Test.assertMessage(d.turnCount == 1, "one turn, got " + d.turnCount.toString());
    Test.assertMessage(d.dryStreak == 0, "he swam, so the dry run is over");
    // Sixteen stopped samples is past the 30 s cap this window used to wait for, and the fall
    // was still booked exactly once: ending the window early is the same verdict, not a second.
    logger.debug("fell at stopped sample " + fellAt.toString() + ", tail cap was 30 s");
    return true;
}

// The straight-line half of the same rule: a swim no turn is judging breaks the run on the
// tick its stop is long enough, rather than at the end of FLIGHT_END_WINDOW_S. One physical
// question, one set of numbers, one moment (docs/algorithms/turns.md "Speed kept").
(:test)
function aStraightLineSwimBreaksTheRunWhenItIsLongEnough(logger as Test.Logger) as Boolean {
    var d = new TurnDetector(coreDefaults());
    streakFlyThrough(d, 0.0);
    Test.assertEqual(d.dryStreak, 1);

    // He ventilates and stops. Sample by sample again: the run must survive the short spell
    // and end on the one that carries it past FALL_STOP_S.
    var brokeAt = -1;
    for (var i = 1; i <= 12; i++) {
        d.tick(1.0, 0.0, 0.2, 0.2, false, false);
        if (d.dryStreak == 0 && brokeAt < 0) {
            brokeAt = i;
        }
    }
    Test.assertMessage(brokeAt == 7,
        "the dry run must end on the 7th stopped sample, got " + brokeAt.toString());
    Test.assertMessage(d.turnCount == 1, "a straight-line swim must not become a turn");
    Test.assertEqual(d.bestDryStreak, 1);
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

// ---- the per-kind LADDER adds up (device app 0.9.18) ----
//
// The Tacks & jibes page draws each kind's whole outcome ladder now, so the six per-kind
// counters owe the page an arithmetic guarantee: for every turn typed while the axis was
// known, a kind's three rungs sum to exactly that kind's count. A page whose row does not add
// up to the number above it is a page arguing with itself, and it is the kind of drift a
// counter incremented in three branches invites.
//
// It holds THROUGH an axis change too, which is 0.9.18's doing: `rebuildWindSplit` throws
// all eleven per-kind counters away and recomputes them together from the turn log, so a
// kind's count and its rungs can never come from different populations. Until then a
// one-shot backfill added to `tackCount` and `jibeCount` alone and the invariant was a `<=`
// that only closed for the turns typed after the lock.
(:test)
function perKindOutcomesAddUpToTheKind(logger as Test.Logger) as Boolean {
    var cfg = coreDefaults();
    cfg.setWindDirection(0);            // wind from north: downwind is 180, upwind is 0
    var d = new TurnDetector(cfg);

    // three jibes, one of each rung: 120 -> 240 sweeps through dead downwind
    runStraight(d, 5, 120.0, 8.0);
    runSweep(d, 120.0, 30.0, 4, 8.0);
    runStraight(d, 6, 240.0, 8.0);                      // flew through
    runStraight(d, 5, 120.0, 8.0);
    runSweep(d, 120.0, 30.0, 4, 8.0);
    runStraight(d, 3, 240.0, 0.5);
    runStraight(d, 6, 240.0, 8.0);                      // touched down
    runStraight(d, 5, 120.0, 8.0);
    runSweep(d, 120.0, 30.0, 4, 8.0);
    runStraight(d, 14, 240.0, 0.2);                     // fell in
    runStraight(d, 6, 240.0, 8.0);

    // two tacks: 300 -> 60 sweeps through dead upwind
    runStraight(d, 5, 300.0, 8.0);
    runSweep(d, 300.0, 30.0, 4, 8.0);
    runStraight(d, 6, 60.0, 8.0);                       // flew through
    runStraight(d, 5, 300.0, 8.0);
    runSweep(d, 300.0, 30.0, 4, 8.0);
    runStraight(d, 3, 60.0, 0.5);
    runStraight(d, 6, 60.0, 8.0);                       // touched down

    Test.assertMessage(d.jibeCount == 3,
        "three jibes, got " + d.jibeCount.toString());
    Test.assertMessage(d.tackCount == 2,
        "two tacks, got " + d.tackCount.toString());

    // THE INVARIANT, per kind
    var jibes = d.jibeFlewCount + d.jibeTouchCount + d.jibeFellCount;
    var tacks = d.tackFlewCount + d.tackTouchCount + d.tackFellCount;
    Test.assertMessage(jibes == d.jibeCount,
        "the jibes' rungs sum to " + jibes.toString() + ", not " + d.jibeCount.toString()
            + " (" + d.jibeFlewCount.toString() + "/" + d.jibeTouchCount.toString() + "/"
            + d.jibeFellCount.toString() + ")");
    Test.assertMessage(tacks == d.tackCount,
        "the tacks' rungs sum to " + tacks.toString() + ", not " + d.tackCount.toString()
            + " (" + d.tackFlewCount.toString() + "/" + d.tackTouchCount.toString() + "/"
            + d.tackFellCount.toString() + ")");
    // each rung is the session's own rung asked of one kind, so the two kinds can never
    // together exceed it
    Test.assertMessage(d.jibeFlewCount + d.tackFlewCount <= d.flewCount,
        "the kinds claim more fly-throughs than the session had");
    Test.assertMessage(d.jibeTouchCount + d.tackTouchCount <= d.touchdownCount,
        "the kinds claim more touchdowns than the session had");
    Test.assertMessage(d.jibeFellCount + d.tackFellCount <= d.fellCount,
        "the kinds claim more falls than the session had");

    // ...and a REBUILD keeps it an equality (0.9.18). The pass throws all eleven per-kind
    // counters away and recomputes them together from the turn log, so there is no way for a
    // kind's count and its rungs to come from different populations — which is exactly what
    // the 0.9.17 one-shot backfill did, and why this used to be a `<=`.
    d.rebuildWindSplit();
    Test.assertMessage(
        d.jibeFlewCount + d.jibeTouchCount + d.jibeFellCount == d.jibeCount,
        "the jibes' rungs do not add up after a rebuild: "
            + d.jibeFlewCount.toString() + "/" + d.jibeTouchCount.toString() + "/"
            + d.jibeFellCount.toString() + " of " + d.jibeCount.toString());
    Test.assertMessage(
        d.tackFlewCount + d.tackTouchCount + d.tackFellCount == d.tackCount,
        "the tacks' rungs do not add up after a rebuild: "
            + d.tackFlewCount.toString() + "/" + d.tackTouchCount.toString() + "/"
            + d.tackFellCount.toString() + " of " + d.tackCount.toString());
    // ...and an axis the rider moves keeps it an equality too
    cfg.setWindDirection(90);
    d.rebuildWindSplit();
    Test.assertMessage(
        d.jibeFlewCount + d.jibeTouchCount + d.jibeFellCount == d.jibeCount
            && d.tackFlewCount + d.tackTouchCount + d.tackFellCount == d.tackCount,
        "the rungs stopped adding up when the axis moved");
    logger.debug("per-kind ladder: jibes " + d.jibeFlewCount.toString() + "/"
        + d.jibeTouchCount.toString() + "/" + d.jibeFellCount.toString() + " of "
        + d.jibeCount.toString() + ", tacks " + d.tackFlewCount.toString() + "/"
        + d.tackTouchCount.toString() + "/" + d.tackFellCount.toString() + " of "
        + d.tackCount.toString());
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

// ---- THE LADDER AGAINST A GOLDEN (watch 0.9.19) ----
//
// One taxonomy: what the wrist says about a turn has to be what the phone says about it. The
// three unit tests above each pin one rung; this one pins the SHAPE OF A SESSION, against the
// phone's own answer for a real afternoon.
//
// The table is the counted turns of `fixtures/goldens/2026-08-07-0754_nago-torbole-
// windsurfen_ciq.expected.json` (engine 0.24.0, read 22 Sep 2026), and it carries the phone's
// EVIDENCE, never its verdict: per turn the entry speed, how long the outcome window ran, how
// long the foil was lost, how long the longest stop inside it was, and whether the wrist went
// under. A 1 Hz track is built from those five numbers and replayed through the detector; the
// verdict is the watch's own, and the three counts it comes out with must be the golden's.
//
// WHAT IT IS AND IS NOT. It is a synthetic track shaped like a golden, not the golden's own
// samples: every turn is handed a sweep the detector can see (180 deg at 30 deg/s), so this
// exercises the OUTCOME LADDER and the windows, not the geometry gates, the non-maximum
// suppression the watch does not have, or the aborted-turn pass it does not have either
// (docs/algorithms/turns.md, "Watch approximation"). The two aborted turns in this golden are
// therefore given ordinary sweeps.
//
// WHY IT FAILED BEFORE 0.9.19: five of these turns — the mush-outs whose stop begins after
// the 12 s lookahead — came out `touchdown` on the wrist and `fell_in` on the phone, so the
// watch's ladder read 11 / 13 / 8 against the golden's 11 / 8 / 13. It is the commonest
// single disagreement on the corpus and it is what ADR-032 was written for.
const GOLDEN_FLEW = 11;
const GOLDEN_TOUCH = 8;
const GOLDEN_FELL = 13;

// [entryKn, outcomeWindowS, offFoilS, stoppedS, submerged] per counted turn.
function goldenTurnEvidence() as Array<Array<Number> > {
    return [
        [1114, 11, 8, 1, 0], [957, 30, 30, 28, 0],
        [883, 19, 24, 6, 0], [972, 4, 3, 0, 1],
        [992, 17, 13, 0, 0], [876, 26, 23, 1, 0],
        [1053, 16, 2, 0, 0], [914, 9, 2, 0, 0],
        [1077, 2, 0, 0, 0], [1012, 30, 31, 28, 0],
        [989, 30, 28, 21, 0], [1024, 1, 0, 0, 0],
        [1070, 17, 24, 11, 0], [959, 2, 0, 0, 0],
        [839, 30, 28, 27, 0], [1074, 7, 0, 0, 0],
        [1155, 30, 28, 26, 0], [1065, 30, 24, 22, 0],
        [1017, 3, 0, 0, 0], [1005, 30, 25, 18, 0],
        [996, 8, 0, 0, 1], [994, 6, 0, 0, 0],
        [1051, 30, 23, 20, 0], [972, 8, 0, 0, 0],
        [1080, 6, 0, 0, 0], [959, 2, 0, 0, 0],
        [1054, 30, 29, 1, 0], [970, 3, 3, 0, 1],
        [1073, 16, 3, 0, 0], [941, 5, 0, 0, 0],
        [1069, 0, 0, 0, 0], [1013, 30, 29, 1, 0],
    ] as Array<Array<Number> >;
}

// One turn of that track: an approach, a 180 deg sweep, and a tail written from the row.
// `cruise` is the mush — above `foilExit`, so the foil is not lost by it, and below
// RECOVER_PCT of the entry speed, so it does not close the window either. The stop is placed
// where the phone found it (window - stopped), which is the whole point: a stop that begins
// past the 12 s lookahead is only seen at all because the window now follows him.
function replayGoldenTurn(d as TurnDetector, cfg as Config, cog as Float,
        row as Array<Number>) as Void {
    var v = row[0] / 100.0 / 1.9438445;
    var winS = row[1];
    var offFoil = row[2];
    var stopped = row[3];
    var wet = row[4] == 1;
    var cruise = (cfg.foilExitMps + 0.7 * v) / 2.0;
    var stopAt = winS - stopped;
    var out = cog + 180.0;
    if (out >= 360.0) {
        out -= 360.0;
    }

    runStraight(d, 5, cog, v);
    runSweep(d, cog, 30.0, 6, v);
    for (var s = 1; s <= winS; s++) {
        var speed = cruise;
        if (stopped > 0 && s >= stopAt) {
            speed = 0.2;
        } else if (s <= offFoil) {
            speed = 1.5;
        }
        d.tick(1.0, out, speed, speed, speed > cfg.foilExitMps, wet && s == 1);
    }
    // Back on the foil: the recovery the phone's window closed on, and the approach the next
    // maneuver is ridden out of. A turn whose window ran the full cap has already resolved.
    runStraight(d, 6, out, v);
}

(:test)
function turnLadderMatchesTheGoldenOnASyntheticReplay(logger as Test.Logger) as Boolean {
    var cfg = coreDefaults();
    var d = new TurnDetector(cfg);
    var rows = goldenTurnEvidence();
    var cog = 0.0;
    for (var i = 0; i < rows.size(); i++) {
        replayGoldenTurn(d, cfg, cog, rows[i]);
        cog += 180.0;
        if (cog >= 360.0) {
            cog -= 360.0;
        }
    }
    logger.debug("2026-08-07 ciq — watch " + d.flewCount.toString() + " / "
        + d.touchdownCount.toString() + " / " + d.fellCount.toString()
        + " flew/touch/fell over " + d.turnCount.toString() + " turns; golden "
        + GOLDEN_FLEW.toString() + " / " + GOLDEN_TOUCH.toString() + " / "
        + GOLDEN_FELL.toString() + " over " + rows.size().toString());
    Test.assertMessage(d.turnCount == rows.size(),
        "every turn counted once: " + d.turnCount.toString() + " of " + rows.size().toString());
    Test.assertMessage(d.flewCount == GOLDEN_FLEW && d.touchdownCount == GOLDEN_TOUCH
        && d.fellCount == GOLDEN_FELL,
        "the wrist's ladder is not the golden's: " + d.flewCount.toString() + " / "
        + d.touchdownCount.toString() + " / " + d.fellCount.toString() + " against "
        + GOLDEN_FLEW.toString() + " / " + GOLDEN_TOUCH.toString() + " / "
        + GOLDEN_FELL.toString());
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


// ---- Turn streaks (docs/algorithms/pumping.md "Turn streaks") ----
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

// A jibe he swam out of: never gets going again, so the window runs to the not-recovered cap.
function streakFellIn(d as TurnDetector, cog as Float) as Void {
    runStraight(d, 5, cog, 8.0);
    runSweep(d, cog, 30.0, 6, 8.0);
    runStraight(d, 32, cog + 180.0, 0.2);
}

// n seconds OFF the foil at `speed`, holding `cog`. The flight-end half of the streak rule
// needs the flying flag to actually fall, which runStraight never lets it do.
function runOffFoil(d as TurnDetector, n as Number, cog as Float, speed as Float) as Void {
    runTail(d, n, cog, speed, false, false);
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

// ---- The quiet tail (device app 0.9.9, engine 0.17.0, docs/algorithms/turns.md "The quiet tail") ----
// A clean candidate is held for CLEAN_QUIET_S past the sweep end. The phone's rule: no off-foil
// spell of 1 s, no flight end, no wrist under in that tail, or the jibe is not clean; the
// outcome itself is untouched. Three corners: lost the foil inside the tail, dunked the wrist
// inside the tail, and a GPS gap inside the tail (which grants, as the phone's window stops at
// a gap and calls what it saw).
(:test)
function quietTailWithdrawsTheStarButNotTheOutcome(logger as Test.Logger) as Boolean {
    var cfg = coreDefaults();
    cfg.setWindDirection(0);

    // (a) carried jibe, recovered at t = 15, then 2 s below foilExit at t = 16..17: withdrawn
    var d = new TurnDetector(cfg);
    runStraight(d, 5, 120.0, 8.0);
    runSweep(d, 120.0, 30.0, 4, 8.0);           // sweep ends t = 9, tail runs to t = 19
    var ev = runStraight(d, 6, 240.0, 8.0);     // t = 15: EVENT_FLEW, star pending
    Test.assertMessage(ev == TurnDetector.EVENT_FLEW && d.cleanPending, "pending after FLEW");
    ev = runStraight(d, 2, 240.0, 1.5);         // 1.5 m/s < foilExit 2.2: a 1 s spell, both ends
    Test.assertMessage(ev == TurnDetector.EVENT_CLEAN_SETTLED,
        "the loss must settle the tail, got " + ev.toString());
    Test.assertMessage(!d.cleanPending && !d.lastCleanJibe && d.cleanJibeCount == 0,
        "a jibe followed by a loss inside 10 s is not clean, count "
        + d.cleanJibeCount.toString());
    Test.assertMessage(d.flewCount == 1 && d.touchdownCount == 0,
        "the outcome stays flew through: the tail only touches the star");
    runStraight(d, 10, 240.0, 8.0);
    Test.assertMessage(d.cleanJibeCount == 0, "a withdrawn star must not come back");

    // (b) a single sub-exit sample is not a spell: the star survives it
    var s = new TurnDetector(cfg);
    runStraight(s, 5, 120.0, 8.0);
    runSweep(s, 120.0, 30.0, 4, 8.0);
    runStraight(s, 6, 240.0, 8.0);
    runStraight(s, 1, 240.0, 1.5);              // one sample: no both-ends spell yet
    ev = runStraight(s, 4, 240.0, 8.0);         // t = 20: tail ran out
    Test.assertMessage(ev == TurnDetector.EVENT_CLEAN_SETTLED && s.cleanJibeCount == 1,
        "one dropped sample must not cost the star, count " + s.cleanJibeCount.toString());

    // (c) the wrist goes under inside the tail: withdrawn on that sample
    var w = new TurnDetector(cfg);
    runStraight(w, 5, 120.0, 8.0);
    runSweep(w, 120.0, 30.0, 4, 8.0);
    runStraight(w, 6, 240.0, 8.0);
    ev = w.tick(1.0, 240.0, 8.0, 8.0, true, true);
    Test.assertMessage(ev == TurnDetector.EVENT_CLEAN_SETTLED && w.cleanJibeCount == 0
        && !w.lastCleanJibe, "a dunk inside the tail is not clean");

    // (d) a GPS gap inside the tail grants: missing evidence is not a loss
    var g = new TurnDetector(cfg);
    runStraight(g, 5, 120.0, 8.0);
    runSweep(g, 120.0, 30.0, 4, 8.0);
    runStraight(g, 6, 240.0, 8.0);
    g.onGap();
    ev = g.tick(1.0, null, 8.0, 8.0, true, false);
    Test.assertMessage(ev == TurnDetector.EVENT_CLEAN_SETTLED && g.cleanJibeCount == 1
        && g.lastCleanJibe, "a gap settles the tail as clean, count "
        + g.cleanJibeCount.toString());
    logger.debug("quiet tail: withdrawn by a 1 s spell or a dunk, granted by the clock or a gap");
    return true;
}

// ---- Clean jibes (device app 0.9.5, docs/presentation/clean-jibe.md "Clean jibe") ----
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
    var ev = runStraight(d, 6, 240.0, 8.0);
    Test.assertMessage(d.jibeCount == 1, "not a jibe: " + d.jibeCount.toString());
    Test.assertMessage(d.successCount == 1, "a jibe carried at 8 m/s throughout is successful");
    // 0.9.9: the outcome is final here (EVENT_FLEW at recovery), the star is not — the quiet
    // tail runs to 10 s past the sweep end, which is t = 19 and this is t = 15.
    Test.assertMessage(ev == TurnDetector.EVENT_FLEW, "flew through, event " + ev.toString());
    Test.assertMessage(d.cleanPending && d.cleanJibeCount == 0,
        "the star must wait for the quiet tail, got " + d.cleanJibeCount.toString());
    ev = runStraight(d, 5, 240.0, 8.0);         // t = 20: the tail ran out with nothing against it
    Test.assertMessage(ev == TurnDetector.EVENT_CLEAN_SETTLED,
        "the tail must settle with its own event, got " + ev.toString());
    Test.assertMessage(d.cleanJibeCount == 1,
        "a successful jibe must be a clean jibe, got " + d.cleanJibeCount.toString());
    Test.assertMessage(d.lastCleanJibe && !d.cleanPending,
        "lastCleanJibe was not published for a clean jibe");

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
    runStraight(w, 32, 240.0, 0.2);
    Test.assertMessage(w.jibeCount == 1, "the swim was still a jibe");
    Test.assertMessage(w.cleanJibeCount == 0, "a jibe he swam out of is not clean");
    Test.assertMessage(!w.lastCleanJibe,
        "lastCleanJibe must go false again on the next turn that is not one");

    // (4) NO WIND AXIS, the same carried 180: a generic turn, successful, and not a clean jibe,
    // because nothing named it a jibe. This is the shape of the watch's auto-wind session
    // before the estimator locks — CPH under-reads there, deliberately and conservatively
    // (TurnDetector.rebuildWindSplit).
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

    // THE SAME FIVE TURNS, split by kind (device app 0.9.17, the Tacks & jibes page). The
    // per-kind fly-throughs are the ladder's green asked of one kind, so every case above
    // answers twice: the carried jibe is a jibe he flew through, the carried tack a tack he
    // flew through, and the swim, the touchdown and the unnamed turn are on neither counter.
    Test.assertMessage(d.jibeFlewCount == 1 && d.tackFlewCount == 0,
        "the carried jibe was not counted as a jibe he flew through");
    Test.assertMessage(t.tackFlewCount == 1 && t.jibeFlewCount == 0,
        "the carried tack was not counted as a tack he flew through");
    Test.assertMessage(w.jibeFlewCount == 0, "a jibe he swam out of did not fly through");
    Test.assertMessage(x.jibeFlewCount == 0, "a jibe that touched down did not fly through");
    Test.assertMessage(g.jibeFlewCount == 0 && g.tackFlewCount == 0,
        "there was no axis to put the turn on either counter");
    // ...and the invariant the page draws on: a kind's fly-throughs are a subset of that
    // kind, and of the session's fly-throughs
    Test.assertMessage(d.jibeFlewCount <= d.jibeCount && d.jibeFlewCount <= d.flewCount,
        "jibes flown through must be a subset of the jibes AND of the fly-throughs");
    Test.assertMessage(t.tackFlewCount <= t.tackCount && t.tackFlewCount <= t.flewCount,
        "tacks flown through must be a subset of the tacks AND of the fly-throughs");

    // ---- THE OTHER TWO RUNGS, PER KIND (device app 0.9.18) ----
    // The Tacks & jibes page draws a kind's WHOLE ladder now, so the split has to hold for
    // the other two outcomes as well as for the green one. The swim was a jibe and the
    // touchdown was a jibe, so each lands on exactly one of the jibe counters and on neither
    // tack counter; the turn with no axis lands on none of the six.
    Test.assertMessage(w.jibeFellCount == 1 && w.jibeTouchCount == 0,
        "a jibe he swam out of was not counted as a jibe he fell in");
    Test.assertMessage(w.tackFellCount == 0 && w.tackTouchCount == 0,
        "a jibe landed on a tack counter");
    Test.assertMessage(x.jibeTouchCount == 1 && x.jibeFellCount == 0,
        "a jibe that touched down was not counted as one");
    Test.assertMessage(g.jibeTouchCount == 0 && g.jibeFellCount == 0
        && g.tackTouchCount == 0 && g.tackFellCount == 0,
        "a turn with no axis landed on a kind's counter");
    logger.debug("per-kind ladder: jibe " + d.jibeFlewCount.toString() + "/"
        + w.jibeFellCount.toString() + "/" + x.jibeTouchCount.toString()
        + ", tack " + t.tackFlewCount.toString());

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
    // 32 s, because the flight-end window is the turn window's cap and that is the
    // NOT-RECOVERED one since 0.9.19: a rider who never gets up again is judged when it
    // runs out, not before.
    runOffFoil(d, 32, 0.0, 0.2);
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

    runOffFoil(d, 32, 0.0, 0.2);                 // he goes in, no maneuver involved
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

// ---- AutoWind (docs/algorithms/wind.md "Watch approximation: auto wind") ----
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

// ---- OPPOSED LOBES (engine 0.23.0, watch 0.9.18) ----
//
// One beam reach and its reciprocal. The watch refused this outright until 0.9.18 — above a
// 179 deg separation it returned `_unconfirmed()` — because the bisector was the two lobes'
// circular MEAN and at 180 deg the unit vectors cancel: `atan2(0, 0)` is 0 deg, a bearing
// read off nothing. The half-angle form is defined everywhere and answers the PERPENDICULAR
// of the lobe axis, which is where the wind is when a rider sailed only that one reach.
//
// The fixture is at exactly 180 deg, and that is the whole refusal band rather than a corner
// of it: the old gate was `sep > 179.0`, so everything it turned away was within a degree of
// opposed. A 179.2 deg separation cannot be built through this door anyway — the histogram
// has 10 deg bins and a lobe refines to a mass-weighted mean inside +-2 of them, so a fixture
// lands on a bin centre (180 apart, exactly) or several degrees off it and nothing between.
// The degenerate case is the one worth having: it is where the old arithmetic did not merely
// refuse but could not have answered.
//
// TWO PASSES, because the two halves of the answer fail differently. The AXIS is geometry and
// it is available now at every separation; WHICH END of it is upwind is the no-go cone's
// question, and on a session with no upwind or downwind work at all there is genuinely
// nothing to answer it with. That is the engine's point: the doubt rides in `confidence`,
// where a reader can see it, and not in a refusal that throws the axis away with it.
(:test)
function autoWindOpposedLobesStillResolve(logger as Test.Logger) as Boolean {
    // PASS 1 — nothing but the one reach and its reciprocal, ON the bin centres and with no
    // tails, so both lobes refine to exactly 90 and 270. Both cones are empty, so the
    // DIRECTION stays unresolved; what must not happen is the separation gate firing.
    var bare = new AutoWind();
    autoWindRun(bare, [90.0, 270.0] as Array<Float>, 200, 10.0);
    Test.assertMessage(bare.lastSepDeg > 179.0,
        "the fixture did not produce opposed lobes — and above 179 is exactly what the "
            + "retired gate refused: sep " + bare.lastSepDeg.format("%.1f"));
    Test.assertMessage(bare.lastAxisConf > 0.0,
        "the axis was refused on its separation, conf " + bare.lastAxisConf.format("%.2f"));

    // PASS 2 — the same two reaches with a little DOWNWIND running in the mix. The two lobes
    // are unchanged (180 deg is 90 deg from both, outside the +-2 bin refinement window), but
    // the 180 cone holds mass now and the 0 cone holds none, so the end is decided and the
    // axis has to come out on the PERPENDICULAR of the reach.
    var aw = new AutoWind();
    var cogs = [90.0, 90.0, 90.0, 270.0, 270.0, 270.0, 180.0] as Array<Float>;
    var ev = autoWindRun(aw, cogs, 350, 10.0);
    Test.assertMessage(aw.lastSepDeg > 179.0,
        "pass 2 lost the opposed lobes: sep " + aw.lastSepDeg.format("%.1f"));
    Test.assertMessage(aw.dirDeg >= 0,
        "no axis with a cone to decide on, conf " + aw.confidence.format("%.2f")
            + " (ev " + ev.toString() + ")");
    Test.assertMessage(autoWindOffBy(aw, 0.0) <= 20.0,
        "the axis is not the perpendicular: " + aw.dirDeg.toString() + " deg");
    // ...and never a LOBE, which is what `atan2(0, 0)` would have handed back dressed as an
    // answer if the old circular mean had been asked this question
    Test.assertMessage(autoWindOffBy(aw, 90.0) > 20.0 && autoWindOffBy(aw, 270.0) > 20.0,
        "the axis landed ON a lobe: " + aw.dirDeg.toString() + " deg");
    logger.debug("opposed lobes: sep " + aw.lastSepDeg.format("%.1f") + " -> wind from "
        + aw.dirDeg.toString() + " deg, conf " + aw.confidence.format("%.2f")
        + "; with no cone at all, axis conf " + bare.lastAxisConf.format("%.2f")
        + " and direction " + bare.dirDeg.toString());
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
// split rebuilt against the wrong axis and the vibe on it.
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

// ---- the REBUILD (TurnDetector.rebuildWindSplit) ----
//
// The watch never re-judges an outcome, but since 0.9.18 it always re-NAMES: every time the
// effective wind axis changes, every logged turn is typed against it again and all eleven
// per-kind counters are rebuilt. A rider who sets the wind at minute forty gets the whole
// session split, not the last twenty minutes of it, and the estimator's own first turns are
// named by the axis they taught.
(:test)
function rebuildSplitsTheTurnsTheAxisWasLearnedFrom(logger as Test.Logger) as Boolean {
    var cfg = coreDefaults();
    var d = new TurnDetector(cfg);

    // Three 120 -> 240 deg sweeps with no wind axis: counted, but generic.
    for (var i = 0; i < 3; i++) {
        runStraight(d, 5, 120.0, 8.0);
        runSweep(d, 120.0, 30.0, 4, 8.0);
        runStraight(d, 6, 240.0, 8.0);
    }
    // ...and one more straight run, long enough for the LAST turn's quiet tail to run out.
    // The star is granted CLEAN_QUIET_S after the sweep end (0.9.9) and the six seconds each
    // iteration ends with is not that, so without this the third turn would still be pending
    // when the rebuild ran — which is a real behaviour and not what this test is about.
    runStraight(d, 12, 240.0, 8.0);
    Test.assertMessage(d.turnCount == 3, "three turns, got " + d.turnCount.toString());
    Test.assertMessage(d.tackCount == 0 && d.jibeCount == 0, "no axis: nothing is split");
    Test.assertMessage(d.portEntryCount == 0 && d.starboardEntryCount == 0,
        "no axis: there is no side to be on");
    Test.assertMessage(d.logCount() == 3,
        "three turns logged, got " + d.logCount().toString());

    // The estimator adopts north; the rebuild re-types every logged turn.
    cfg.setAutoWind(0);
    var turnsBefore = d.turnCount;
    var flewBefore = d.flewCount;
    d.rebuildWindSplit();
    Test.assertMessage(d.jibeCount == 3,
        "120 -> 240 through dead downwind is a jibe, got " + d.jibeCount.toString());
    Test.assertMessage(d.tackCount == 0, "none of them is a tack");
    Test.assertMessage(d.turnCount == turnsBefore,
        "the rebuild must not re-count turns: " + d.turnCount.toString());
    Test.assertMessage(d.flewCount == flewBefore,
        "the rebuild must not re-judge outcomes");
    Test.assertMessage(d.portEntryCount + d.starboardEntryCount == 3,
        "each re-typed maneuver gets its entry side");
    // ...and the rungs came with the count, which is what 0.9.17's one-shot backfill could
    // not do: it added to jibeCount alone and left these three behind.
    Test.assertMessage(
        d.jibeFlewCount + d.jibeTouchCount + d.jibeFellCount == d.jibeCount,
        "the jibes' rungs do not add up after a rebuild: "
            + d.jibeFlewCount.toString() + "/" + d.jibeTouchCount.toString() + "/"
            + d.jibeFellCount.toString() + " of " + d.jibeCount.toString());
    // a clean-eligible fly-through that this axis calls a jibe IS a clean jibe, and the star
    // arrives with the axis rather than being lost for ever
    Test.assertMessage(d.cleanJibeCount == 3,
        "the rebuild did not award the stars: " + d.cleanJibeCount.toString());

    // IDEMPOTENT: rebuilding against the same axis twice changes nothing. The counters are
    // thrown away and recomputed, never added to, which is the whole difference from a
    // backfill — and the guard MetricsEngine keeps is the axis, so a repeat is cheap, not
    // wrong.
    d.rebuildWindSplit();
    Test.assertMessage(d.jibeCount == 3 && d.cleanJibeCount == 3
        && d.portEntryCount + d.starboardEntryCount == 3,
        "a second rebuild against the same axis double-counted");

    // ...and an axis the rider CHANGES re-types them again rather than adding. From due east
    // the same 120 -> 240 sweep crosses neither axis end: they are course changes now.
    cfg.setWindDirection(90);
    d.rebuildWindSplit();
    Test.assertMessage(d.jibeCount == 0 && d.tackCount == 0,
        "a changed axis must re-type, not accumulate: " + d.jibeCount.toString()
            + " jibes, " + d.tackCount.toString() + " tacks");
    Test.assertMessage(d.cleanJibeCount == 0, "no jibes, no stars");
    Test.assertMessage(d.turnCount == turnsBefore, "and still three counted turns");

    logger.debug("rebuild: 3 generic turns became " + d.logCount().toString()
        + " logged records, turnCount held at " + d.turnCount.toString());
    return true;
}

// A sweep that turns out to be a BEAR-AWAY under the new axis stays the generic turn it was
// counted as. Retracting it would move turnCount, the success percentage and every streak
// that spanned it — i.e. re-judge, on hindsight evidence, observations made at the time.
(:test)
function rebuildLeavesBearAwaysAsTheGenericTurnsTheyWere(logger as Test.Logger) as Boolean {
    var cfg = coreDefaults();
    var d = new TurnDetector(cfg);

    // 60 -> 150 deg: with wind from north this crosses neither axis end.
    runStraight(d, 5, 60.0, 8.0);
    runSweep(d, 60.0, 30.0, 3, 8.0);
    runStraight(d, 6, 150.0, 8.0);
    Test.assertMessage(d.turnCount == 1, "with no axis it is a counted generic turn");

    cfg.setAutoWind(0);
    d.rebuildWindSplit();
    Test.assertMessage(d.tackCount == 0 && d.jibeCount == 0, "a bear-away is neither");
    Test.assertMessage(d.turnCount == 1,
        "the rebuild retracted a counted turn: " + d.turnCount.toString());
    Test.assertMessage(d.rejectedCount == 0, "and it did not retro-reject it either");
    logger.debug("rebuild: bear-away stayed a generic turn, turnCount "
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
