import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;
import WingFoilCore;

// ---------------------------------------------------------------------------------------
// THROWAWAY screenshot harness. Not shipped, not committed, not referenced by any build.
//
// It subclasses the real WingfoilApp (so `getApp().controller` keeps working for every view
// unchanged), seeds the engine with one real session, and puts a single View on screen that
// delegates its onUpdate to StartView / RecordingView / SummaryView depending on which shot
// the timer is currently holding. Nothing under garmin/source is touched.
//
// The sim's buttons are HID-only, so paging is driven from here on a Timer.
// ---------------------------------------------------------------------------------------

// One shot = one screen. Order is the capture order.
enum {
    SHOT_START = 0,
    SHOT_MAIN = 1,
    SHOT_MAIN_PAUSED = 2,
    SHOT_GRID4 = 3,
    SHOT_RECORDS = 4,
    SHOT_TURNS = 5,
    SHOT_CLOCK = 6,
    SHOT_TIMELINE = 7,
    SHOT_SUM_VERDICT = 8,
    SHOT_SUM_SPEED = 9,
    SHOT_SUM_FLIGHTS = 10,
    SHOT_SUM_TURNS = 11,
    SHOT_SUM_TAKEOFFS = 12,
    SHOT_SUM_STORY = 13,
    SHOT_SUM_TRACK = 14,
    SHOT_COUNT = 15
}

const SHOT_DWELL_MS = 3000;

class ShotsApp extends WingfoilApp {

    function initialize() {
        WingfoilApp.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        AppSettings.load();
        PageModel.build(null);
        PageNav.index = 0;
        controller.engine.trackEnabled = true;
        ShotSeed.seed(controller);
    }

    function onStop(state as Dictionary?) as Void {
    }

    function onSettingsChanged() as Void {
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [new ShotsView(), new ShotsDelegate()];
    }
}

// The seeded session: Jan's 2026-08-24 real numbers, so every layout shows realistic digits.
module ShotSeed {

    function seed(c as SessionController) as Void {
        var e = c.engine;

        // ---- live / session totals ----
        e.speedMps = 24.5 / 3.6;            // 24.5 km/h live
        e.hr = 148;
        e.gpsQuality = 4;                   // GPS ready, four dots
        e.distM = 23100.0;                  // 23.1 km
        // foilTime / timerS is what foilPct() divides, and 63:24 of the MOVING time is 56 %.
        // The wall clock (1:57:09) rides on controller.elapsedS, which is what the summary's
        // "of ..." row prints.
        e.timerS = 6793.0;
        c.elapsedS = 7029;                  // 1:57:09

        // ---- flights ----
        var d = e.detector;
        d.state = FlightDetector.STATE_ON;  // flying: the state ring goes teal
        d.flightCount = 31;
        d.foilTimeS = 3804.0;               // 63:24
        // 14.1 of the 23.1 km covered on the foil: 61 % of the DISTANCE against 56 % of the
        // time, which is the whole point of the Session page's paired top band — flying is the
        // fast half of a session, so the two shares are never the same number.
        d.foilDistM = 14091.0;
        d.longestS = 424.0;                 // 7:04
        d.longestM = 2249.0;
        d.currentFlightS = 96.0;
        d.currentFlightM = 610.0;

        // ---- speed records ----
        e.records.best2sMps = 25.5 / 3.6;
        e.records.best10sMps = 24.3 / 3.6;

        // ---- turns: fly 35 / touch 8 / fell 8 ----
        var t = e.turns;
        t.flewCount = 35;
        t.touchdownCount = 8;
        t.fellCount = 8;
        t.turnCount = 51;
        // 35 of the 51 counted turns flew through: "68% flew" on the Turns page's bottom row.
        // successCount is the carried-speed score, which left the watch in 0.8.2 and now only
        // rides in the FIT/phone payload — seeded so those still have a realistic number.
        t.successCount = 25;
        t.tackCount = 27;
        t.jibeCount = 24;
        t.portEntryCount = 29;              // the entry-side split, P 29 / S 22
        t.starboardEntryCount = 22;
        t.rejectedCount = 6;
        t.borderlineCount = 3;
        t.lastKind = TurnDetector.KIND_JIBE;
        t.lastOutcome = TurnDetector.OUTCOME_FLEW;
        t.lastScorePct = 88;
        t.bestScorePct = 96;
        t.dryStreak = 7;                    // current no-fall run
        t.bestDryStreak = 11;               // session best
        t.flewStreak = 2;
        t.bestFlewStreak = 5;

        // ---- takeoffs: 69 attempts, 31 successes, 10.3 avg pumps ----
        var p = e.pump;
        p.available = true;
        p.successes = 31;
        p.failed = 38;
        p.pumpsSum = 320;                   // 320*10/31 = 103 -> "10.3 to foil"
        p.strokes = 742;
        p.inFlightStrokes = 96;
        p.recoveryEpisodes = 12;
        p.lastPumpsToTakeoff = 9;
        p.cadence = 84;

        // ---- HR price of the last takeoff ----
        e.hrCost.lastCostBpm = 19;

        // ---- the session arc, for the timeline / story page ----
        var h = e.history;
        var slots = 226;                    // ~ 113 min at 30 s
        for (var i = 0; i < slots; i++) {
            var u = i.toFloat() / slots;
            // three lulls and a strong middle, so the strip has a shape worth reading
            var duty = 0.62 + 0.30 * Math.sin(u * 9.0) - 0.18 * Math.sin(u * 2.3 + 0.7);
            if (duty < 0.0) { duty = 0.0; }
            if (duty > 1.0) { duty = 1.0; }
            var peak = 4.0 + 3.2 * duty + 0.6 * Math.sin(u * 21.0);
            // two samples per 30 s slot — the flying part and the rest. A tick per second
            // trips the simulator's watchdog and buys nothing: the slot only keeps the
            // fraction and the peak.
            var flyS = duty * 30.0;
            if (flyS > 0.0) {
                h.tick(flyS.toFloat(), true, peak.toFloat());
            }
            h.tick((30.0 - flyS).toFloat() + 0.01, false, 1.6);
        }
        // The real session's outcome sequence, oldest first: F = flew through, t = touchdown,
        // X = fell in. 35/8/8, the same counts the tally shows, and the clustering is the
        // point — the dot strip exists to show that the swims came in a run near the end.
        var seq = "FtXtFFttXttFFFFFFFFXFFFFFFFFFFXFFFFFFtFtFFFXFXFXFXF";
        for (var i = 0; i < seq.length(); i++) {
            var ch = seq.substring(i, i + 1);
            var o = TurnDetector.OUTCOME_FLEW;
            if (ch.equals("t")) { o = TurnDetector.OUTCOME_TOUCHDOWN; }
            if (ch.equals("X")) { o = TurnDetector.OUTCOME_FELL; }
            h.logTurn(o);
        }

        // ---- breadcrumb: six reaches back and forth with a downwind drift ----
        var n = 128;
        var lat = new [n] as Array<Float>;
        var lon = new [n] as Array<Float>;
        var fly = new [n] as Array<Boolean>;
        for (var i = 0; i < n; i++) {
            var u = i.toFloat() / (n - 1);          // 0..1 along the session
            var legs = 6.0;
            var q = u * legs;
            var leg = q.toNumber();
            var frac = q - leg;
            var across = (leg % 2 == 0) ? frac : 1.0 - frac;
            lon[i] = (10.8700 + 0.0180 * across).toFloat();
            lat[i] = (45.8700 + 0.0034 * u + 0.0009 * Math.sin(q * 3.1)).toFloat();
            // the turnarounds at each end are the bits he was NOT flying through
            fly[i] = frac > 0.06 && frac < 0.94;
        }
        e.trackLat = lat;
        e.trackLon = lon;
        e.trackFly = fly;
        e.trackN = n;

        c.state = SessionController.STATE_RECORDING;
    }
}

// The one view on screen. Everything it paints comes from the app's own renderers.
class ShotsView extends WatchUi.View {

    hidden var _rec as RecordingView = new RecordingView();
    hidden var _sum as SummaryView = new SummaryView();
    hidden var _start as StartView = new StartView();
    hidden var _timer as Timer.Timer?;
    hidden var _shot as Number = 0;

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        SummaryNav.build(getApp().controller);
        _timer = new Timer.Timer();
        (_timer as Timer.Timer).start(method(:advance), SHOT_DWELL_MS, true);
    }

    function onHide() as Void {
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
            _timer = null;
        }
    }

    function advance() as Void {
        _shot = (_shot + 1) % SHOT_COUNT;
        System.println("SHOT " + _shot.toString());
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        var c = getApp().controller;
        c.state = SessionController.STATE_RECORDING;

        // The start shot is the only one taken with NO wind axis: that page's new job is to
        // remind the rider to set one, and the reminder only exists when it is missing. Every
        // other page is shot with the real session's axis, because tack/jibe and the
        // port/starboard split are what the axis buys.
        AppSettings.cfg.setWindDirection(_shot == SHOT_START ? -1 : 30);

        if (_shot == SHOT_START) {
            _start.onUpdate(dc);
            return;
        }
        if (_shot <= SHOT_TIMELINE) {
            if (_shot == SHOT_MAIN_PAUSED) {
                c.state = SessionController.STATE_PAUSED;
                PageNav.index = 0;
            } else if (_shot == SHOT_MAIN) {
                PageNav.index = 0;
            } else {
                PageNav.index = _shot - 2;     // GRID4 .. TIMELINE are pages 1..5
            }
            _rec.onUpdate(dc);
            return;
        }
        c.state = SessionController.STATE_SAVED;
        SummaryNav.index = _shot - SHOT_SUM_VERDICT;
        _sum.onUpdate(dc);
    }
}

class ShotsDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Boolean {
        System.exit();
        return true;
    }
}
