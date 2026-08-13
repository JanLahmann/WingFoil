import Toybox.Application.Properties;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import WingFoilCore;

// The configurable data-screen model (docs/plan.md §3.2 "Pages").
//
// A page is a LAYOUT plus up to five METRIC slots. Both come from GCM properties
// (`pg<N>Layout`, `pg<N>s<M>`), so the rider re-orders, re-fills and removes screens from the
// phone; `build()` re-runs on every onSettingsChanged, which is the whole hot-reload story.
//
// The DEFAULTS below reproduce the five screens the app shipped with, pixel for pixel:
// 1 Speed hero · 2 Session grid · 3 Records · 4 Turns · 5 Clock · 6 off. Change them here and
// in resources/settings/properties.xml together — properties.xml wins on a real device, this
// table is the fallback and the thing the unit test asserts against.
//
// Slot semantics per layout:
//   HERO     s1 = giant number (+ its unit line), s2/s3 = the two rows under it
//   GRID4    s1 = giant number on top (optional), s2..s5 = the 2x2 cells (TL, TR, BL, BR)
//   CELLS2   s1/s2 = two side-by-side cells
//   CLOCK    s1 = the single cell under the giant time of day
//   RECORDS / TURNS / TIMELINE / MAP   bespoke renderers, slots unused
module PageModel {

    // Layout ids. Values are the GCM list values — append only, never renumber.
    enum {
        LAYOUT_OFF = 0,
        LAYOUT_HERO = 1,
        LAYOUT_GRID4 = 2,
        LAYOUT_CELLS2 = 3,
        LAYOUT_RECORDS = 4,
        LAYOUT_TURNS = 5,
        LAYOUT_CLOCK = 6,
        LAYOUT_MAP = 7,
        LAYOUT_TIMELINE = 8
    }
    const LAYOUT_MAX = 8;

    // Metric catalog. Values are the GCM list values — append only, never renumber.
    enum {
        M_NONE = 0,
        M_SPEED = 1,
        M_FOIL_PCT = 2,
        M_FLIGHTS = 3,
        M_FLIGHT_TIMER = 4,
        M_FOIL_TIME = 5,
        M_LONGEST = 6,
        M_DISTANCE = 7,
        M_TIMER = 8,
        M_HR = 9,
        M_BEST_2S = 10,
        M_BEST_10S = 11,
        M_TURNS = 12,
        M_TURN_SCORE = 13,
        M_CLOCK = 14,
        M_BATTERY = 15,
        M_PUMP_STROKES = 16,
        M_TAKEOFFS = 17,
        M_PUMPS_TO_TAKEOFF = 18,
        M_TAKEOFF_COST = 19
    }
    const M_MAX = 19;

    const MAX_PAGES = 6;
    const SLOTS = 5;

    // ---- the shipped five pages, as data ----
    var DEF_LAYOUT as Array<Number> = [
        LAYOUT_HERO, LAYOUT_GRID4, LAYOUT_RECORDS, LAYOUT_TURNS, LAYOUT_CLOCK, LAYOUT_TIMELINE
    ];
    var DEF_SLOTS as Array<Array<Number> > = [
        [M_SPEED, M_FLIGHT_TIMER, M_HR, M_NONE, M_NONE],
        [M_FOIL_PCT, M_FOIL_TIME, M_LONGEST, M_DISTANCE, M_FLIGHTS],
        [M_NONE, M_NONE, M_NONE, M_NONE, M_NONE],
        [M_NONE, M_NONE, M_NONE, M_NONE, M_NONE],
        [M_TIMER, M_NONE, M_NONE, M_NONE, M_NONE],
        [M_NONE, M_NONE, M_NONE, M_NONE, M_NONE]
    ];

    // ---- built state ----
    // `_layout`/`_slot` are indexed by CONFIG page (0..5); `_order` lists the configured pages
    // that are actually on, in order, and is what the UI cycles through.
    var _layout as Array<Number> = [0, 0, 0, 0, 0, 0];
    var _slot as Array<Array<Number> > = [
        [0, 0, 0, 0, 0], [0, 0, 0, 0, 0], [0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0], [0, 0, 0, 0, 0], [0, 0, 0, 0, 0]
    ];
    var _order as Array<Number> = [0];
    var mapPage as Boolean = false;      // any page asks for the breadcrumb map

    // MapTrackView is the native map view (Toybox.WatchUi, not a Toybox.Map module — see the
    // availability note in docs/plan.md). Every fenix 8 variant in the manifest has it; the
    // check keeps the page out of the cycle anywhere it is missing rather than crashing.
    function hasMap() as Boolean {
        return WatchUi has :MapTrackView;
    }

    // Rebuilds the model. `src` null = read GCM properties; a Dictionary = read that instead
    // (the unit tests inject one, so "defaults reproduce the shipped pages" is assertable
    // without a device).
    function build(src as Dictionary?) as Void {
        var order = [] as Array<Number>;
        mapPage = false;
        for (var p = 0; p < MAX_PAGES; p++) {
            var key = "pg" + (p + 1).toString();
            var lay = _clamp(_read(src, key + "Layout", DEF_LAYOUT[p]), 0, LAYOUT_MAX);
            if (lay == LAYOUT_MAP && !hasMap()) {
                lay = LAYOUT_OFF;
            }
            _layout[p] = lay;
            var row = _slot[p];
            var defRow = DEF_SLOTS[p];
            for (var s = 0; s < SLOTS; s++) {
                row[s] = _clamp(_read(src, key + "s" + (s + 1).toString(), defRow[s]), 0, M_MAX);
            }
            if (lay != LAYOUT_OFF) {
                order.add(p);
                if (lay == LAYOUT_MAP) {
                    mapPage = true;
                }
            }
        }
        // never leave the rider with a blank watch
        if (order.size() == 0) {
            _layout[0] = LAYOUT_HERO;
            _slot[0] = [M_SPEED, M_FLIGHT_TIMER, M_HR, M_NONE, M_NONE];
            order.add(0);
        }
        _order = order;
    }

    function count() as Number {
        return _order.size();
    }

    // Layout of the i-th visible page. Out-of-range indices wrap, so a settings change that
    // shrinks the page set can never strand the current index.
    function layoutAt(i as Number) as Number {
        return _layout[_order[wrap(i)]];
    }

    function slotAt(i as Number, s as Number) as Number {
        return _slot[_order[wrap(i)]][s];
    }

    // Does the i-th visible page carry metric `id` in any slot? Drives the foil-% bezel arc,
    // which is a property of the PAGE, not of one cell. Allocation-free: it walks the row that
    // is already there.
    function pageHasMetric(i as Number, id as Number) as Boolean {
        var row = _slot[_order[wrap(i)]];
        for (var s = 0; s < SLOTS; s++) {
            if (row[s] == id) {
                return true;
            }
        }
        return false;
    }

    function wrap(i as Number) as Number {
        var n = _order.size();
        var k = i % n;
        return k < 0 ? k + n : k;
    }

    function _clamp(v as Number, lo as Number, hi as Number) as Number {
        return v < lo || v > hi ? lo : v;
    }

    function _read(src as Dictionary?, key as String, dflt as Number) as Number {
        if (src != null) {
            var injected = src.hasKey(key) ? src[key] : null;
            return injected instanceof Lang.Number ? injected as Number : dflt;
        }
        try {
            var v = Properties.getValue(key);
            if (v instanceof Lang.Number) {
                return v as Number;
            }
            if (v instanceof Lang.Float) {
                return (v as Float).toNumber();
            }
        } catch (e) {
        }
        return dflt;
    }

    // ---- metric catalog ----

    // Short cell label. Doubles as the unit line under a HERO page's giant number, which is
    // why speed answers "km/h"/"kn" rather than "speed".
    function label(id as Number) as String {
        if (id == M_SPEED) { return AppSettings.speedLabel(); }
        if (id == M_FOIL_PCT) { return "foil %"; }
        if (id == M_FLIGHTS) { return "flights"; }
        if (id == M_FLIGHT_TIMER) { return "flight"; }
        if (id == M_FOIL_TIME) { return "foil"; }
        if (id == M_LONGEST) { return "longest"; }
        if (id == M_DISTANCE) { return "km"; }
        if (id == M_TIMER) { return "timer"; }
        if (id == M_HR) { return "bpm"; }
        if (id == M_BEST_2S) { return "best 2s"; }
        if (id == M_BEST_10S) { return "best 10s"; }
        if (id == M_TURNS) { return "turns"; }
        if (id == M_TURN_SCORE) { return "score"; }
        if (id == M_CLOCK) { return "time"; }
        if (id == M_BATTERY) { return "batt"; }
        if (id == M_PUMP_STROKES) { return "pumps"; }
        if (id == M_TAKEOFFS) { return "takeoffs"; }
        if (id == M_PUMPS_TO_TAKEOFF) { return "to foil"; }
        if (id == M_TAKEOFF_COST) { return "hr cost"; }
        return "";
    }

    // The symbol a cell shows beside (or, with showLabels off, instead of) its label.
    // Metrics that measure the same thing share a glyph on purpose — the label, when it is on,
    // is what separates "foil" from "longest"; the glyph says which FAMILY the number is from,
    // which is all the eye needs at 25 kn.
    function glyph(id as Number) as Number {
        if (id == M_SPEED || id == M_BEST_2S || id == M_BEST_10S) { return Glyphs.G_BOLT; }
        if (id == M_FOIL_PCT || id == M_FLIGHTS) { return Glyphs.G_WING; }
        if (id == M_FLIGHT_TIMER || id == M_FOIL_TIME || id == M_LONGEST || id == M_TIMER
            || id == M_CLOCK) {
            return Glyphs.G_WATCH;
        }
        if (id == M_DISTANCE) { return Glyphs.G_RULER; }
        // the takeoff cost is a heartbeat number before it is a pumping one: what the eye is
        // being told is "this is your heart", and the label says which of the two it is
        if (id == M_HR || id == M_TAKEOFF_COST) { return Glyphs.G_HEART; }
        if (id == M_TURNS || id == M_TURN_SCORE) { return Glyphs.G_TURN; }
        if (id == M_PUMP_STROKES || id == M_TAKEOFFS || id == M_PUMPS_TO_TAKEOFF) {
            return Glyphs.G_PUMP;
        }
        if (id == M_BATTERY) { return Glyphs.G_BATTERY; }
        return Glyphs.G_NONE;
    }

    // Bare value, safe for the digit-only number fonts wherever a layout uses one.
    function value(id as Number, c as SessionController) as String {
        var e = c.engine;
        if (id == M_SPEED) {
            return AppSettings.speedToDisplay(e.speedMps).format("%.1f");
        }
        if (id == M_FOIL_PCT) {
            return e.foilPct().format("%.0f") + "%";
        }
        if (id == M_FLIGHTS) {
            return e.detector.flightCount.toString();
        }
        if (id == M_FLIGHT_TIMER) {
            return e.detector.state == FlightDetector.STATE_ON
                ? fmtTime(e.detector.currentFlightS) : "--:--";
        }
        if (id == M_FOIL_TIME) { return fmtTime(e.detector.foilTimeS); }
        if (id == M_LONGEST) { return fmtTime(e.detector.longestS); }
        if (id == M_DISTANCE) { return (e.distM / 1000.0).format("%.1f"); }
        if (id == M_TIMER) { return fmtTime(e.timerS); }
        if (id == M_HR) {
            var hr = e.hr;
            return hr != null ? hr.toString() : "--";
        }
        if (id == M_BEST_2S) {
            return AppSettings.speedToDisplay(e.records.best2sMps).format("%.1f");
        }
        if (id == M_BEST_10S) {
            return AppSettings.speedToDisplay(e.records.best10sMps).format("%.1f");
        }
        if (id == M_TURNS) { return e.turns.turnCount.toString(); }
        if (id == M_TURN_SCORE) {
            return e.turns.lastOutcome == TurnDetector.OUTCOME_NONE
                ? "--" : e.turns.lastScorePct.toString() + "%";
        }
        if (id == M_CLOCK) { return clockString(); }
        if (id == M_BATTERY) {
            return System.getSystemStats().battery.format("%.0f") + "%";
        }
        if (id == M_PUMP_STROKES) { return e.pump.strokes.toString(); }
        if (id == M_TAKEOFFS) {
            // attempts > successes, e.g. "14>9": how often he pumped and how often he got up.
            // The digit-only number fonts may drop the separator in a HERO giant slot, the
            // same trade-off M_TURN_SCORE's "%" already makes.
            return e.pump.attempts().toString() + ">" + e.pump.successes.toString();
        }
        if (id == M_PUMPS_TO_TAKEOFF) {
            return e.pump.lastPumpsToTakeoff < 0
                ? "--" : e.pump.lastPumpsToTakeoff.toString();
        }
        if (id == M_TAKEOFF_COST) {
            // "--" until a takeoff has been priced: no accelerometer, a wrist the optical
            // sensor lost, or a rise too small to charge for all read the same, and all of
            // them mean "not measured" rather than "it cost nothing".
            return e.hrCost.lastCostBpm < 0 ? "--" : e.hrCost.lastCostBpm.toString();
        }
        return "";
    }

    // Appended in HERO sub-rows only (they carry no label of their own). Cells put the unit
    // in the label instead, which is what keeps a 2x2 grid inside the round glass.
    function suffix(id as Number) as String {
        return id == M_HR || id == M_TAKEOFF_COST ? " bpm" : "";
    }

    function color(id as Number, c as SessionController) as Number {
        if (id == M_FLIGHT_TIMER) {
            return c.engine.detector.state == FlightDetector.STATE_ON
                ? Graphics.COLOR_GREEN : Graphics.COLOR_DK_GRAY;
        }
        if (id == M_HR || id == M_TAKEOFF_COST) { return Graphics.COLOR_RED; }
        if (id == M_FOIL_PCT) { return Graphics.COLOR_GREEN; }
        return Graphics.COLOR_WHITE;
    }

    // Widest string each metric can realistically produce. Used only by the layout tests —
    // it is the "worst-case content" they measure, so keep it honest when a formatter changes.
    function worstValue(id as Number) as String {
        if (id == M_NONE) { return ""; }
        if (id == M_SPEED || id == M_BEST_2S || id == M_BEST_10S || id == M_DISTANCE) {
            return "99.9";
        }
        if (id == M_FOIL_PCT || id == M_TURN_SCORE || id == M_BATTERY) { return "100%"; }
        if (id == M_FLIGHTS || id == M_TURNS) { return "999"; }
        // the cost is a difference inside the 30-220 bpm plausibility band, so three digits is
        // its honest ceiling even though a real takeoff costs 7
        if (id == M_HR || id == M_PUMPS_TO_TAKEOFF || id == M_TAKEOFF_COST) { return "199"; }
        if (id == M_PUMP_STROKES) { return "9999"; }
        if (id == M_TAKEOFFS) { return "99>99"; }
        if (id == M_CLOCK) { return "23:59"; }
        return "199:59";   // every timer: >3 h sessions still read m:ss
    }

    function worstLabel(id as Number) as String {
        return id == M_SPEED ? "km/h" : label(id);
    }

    // m:ss. Shared by every timer metric and by SummaryView.
    function fmtTime(seconds as Float) as String {
        var s = seconds.toNumber();
        return (s / 60).format("%d") + ":" + (s % 60).format("%02d");
    }

    function clockString() as String {
        var ct = System.getClockTime();
        var hour = ct.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
        }
        return hour.format("%d") + ":" + ct.min.format("%02d");
    }
}
