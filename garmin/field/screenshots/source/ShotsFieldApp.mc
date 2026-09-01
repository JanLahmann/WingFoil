import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;
import WingFoilCore;

// ---------------------------------------------------------------------------------------
// THROWAWAY screenshot harness for the DATA FIELD. Not shipped: ../monkey.jungle does not
// name this directory, so nothing here can reach a store build.
//
// A data field cannot be paged the way the device app can — it owns one view and the system
// hands it whatever cell the user dropped it into. So the harness does not cycle anything:
// it seeds the engine once with a real session and makes compute() inert, and the LAYOUT is
// switched from outside, in the simulator's "Data Fields > Layout" menu (1 Field, 2 Fields,
// 3 Fields A/B/C, 4 Fields A/B/C, ...). Each menu pick re-runs onUpdate() with a different
// dc, which is exactly the SIZE_FULL / SIZE_WIDE / SIZE_SMALL fork in WingFoilDataField.
//
// compute() must be inert rather than merely unseeded: the simulator feeds a data field its
// own Activity.Info every second (timerTime climbing from zero, currentSpeed whatever the
// Simulation > Activity Data panel holds), and one tick of that would divide the seeded
// foil time by a two-second timer and print 100 %.
// ---------------------------------------------------------------------------------------
class ShotsFieldApp extends WingFoilFieldApp {

    function initialize() {
        WingFoilFieldApp.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [new ShotsField()] as [Views];
    }
}

class ShotsField extends WingFoilDataField {
    // compute() is the simulator's own 1 Hz clock, and the only clock a data field is allowed
    // to have (Timer would be a second one; there is no need for it). Counting ticks here is
    // what lets ONE build show both seeds: the harness re-seeds every DWELL ticks and prints
    // the shot number, which is the line the capture script synchronises on.
    const DWELL = 8;

    hidden var _tick as Number = 0;
    hidden var _shot as Number = -1;
    hidden var _cellW as Number = 0;
    hidden var _cellH as Number = 0;
    hidden var _cellFlags as Number = -1;

    function initialize() {
        WingFoilDataField.initialize();
        show(0);
    }

    // Inert as far as the engine is concerned: nothing from Activity.Info reaches it, because
    // one tick of the simulator's own data would divide the seeded foil time by a two-second
    // timer and print 100 %.
    function compute(info as Activity.Info) as Void {
        _tick++;
        var want = (_tick / DWELL) % FieldShotSeed.COUNT;
        if (want != _shot) {
            show(want);
            WatchUi.requestUpdate();
        }
    }

    // The cell the system just handed us, printed on every layout change. This is where the
    // FieldLayout geometry tests get their numbers from: walk the simulator's
    // Data Fields > Layout menu with this build running and the log names, for every layout
    // the device offers, the exact rectangle and the exact obscurity flags the shipped field
    // will see. Guessing them from "half of 454" is how the bottom-bezel clipping survived a
    // whole suite of unit tests.
    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var flags = getObscurityFlags();
        if (w != _cellW || h != _cellH || flags != _cellFlags) {
            _cellW = w;
            _cellH = h;
            _cellFlags = flags;
            System.println("CELL " + w + "x" + h + " flags " + flags);
        }
        WingFoilDataField.onUpdate(dc);
    }

    hidden function show(shot as Number) as Void {
        _shot = shot;
        FieldShotSeed.seed(engine(), shot);
        System.println("SHOT " + shot);
    }
}

// Jan's 2026-08-24 session, the same numbers garmin/screenshots/ShotsApp.mc seeds into the
// device app, restricted to what a data field can actually know: no heart rate, no pump
// metrics, no accelerometer (Sensor.* crashes a data field — docs/fit-schema.md).
module FieldShotSeed {
    // Two moments of the same session, three minutes apart. The field's whole colour
    // vocabulary lives in the difference between them: SHOT_FLYING is green twice (on the
    // foil, and the jibe before it flew through), SHOT_TOUCH is white and orange (back on
    // the water, the jibe after it touched down).
    enum {
        SHOT_FLYING = 0,
        SHOT_TOUCH = 1,
        COUNT = 2
    }

    function seed(e as FieldEngine, shot as Number) as Void {
        // 63:24 of foil time inside 1:53:13 of moving time = the 56 % both shots print.
        e.timerS = 6793.0;
        e.distM = 23100.0;
        e.gpsQuality = 4;
        e.running = true;

        var d = e.detector;
        d.flightCount = 31;
        d.foilTimeS = 3804.0;                // 63:24
        d.foilDistM = 14091.0;
        d.longestS = 424.0;
        d.longestM = 2249.0;

        e.records.best2sMps = 25.5 / 3.6;
        e.records.best10sMps = 24.3 / 3.6;

        // 51 counted turns: 35 flew through, 8 touched down, 8 ended in the water.
        var t = e.turns;
        t.turnCount = 51;
        t.tackCount = 27;
        t.jibeCount = 24;
        t.flewCount = 35;
        t.touchdownCount = 8;
        t.fellCount = 8;
        t.successCount = 25;
        t.lastKind = TurnDetector.KIND_JIBE;
        t.bestScorePct = 96;

        if (shot == SHOT_TOUCH) {
            // Off the foil: the % goes white, the flight timer goes --:--, and the jibe that
            // just ended is the orange one. Its touchdown is already in the tally (9 now).
            e.speedMps = 9.6 / 3.6;
            d.state = FlightDetector.STATE_OFF;
            d.currentFlightS = 0.0;
            d.currentFlightM = 0.0;
            t.touchdownCount = 9;
            t.lastOutcome = TurnDetector.OUTCOME_TOUCHDOWN;
            t.lastScorePct = 61;
            return;
        }
        // Flying, mid-flight, and the last jibe carried 88 % of its entry speed through.
        e.speedMps = 24.5 / 3.6;
        d.state = FlightDetector.STATE_ON;
        d.currentFlightS = 96.0;             // the flight you are in right now: 1:36
        d.currentFlightM = 610.0;
        t.lastOutcome = TurnDetector.OUTCOME_FLEW;
        t.lastScorePct = 88;
    }
}
