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
// The DEFAULTS below are the seven screens 0.8.2 ships with:
// 1 Main · 2 Foil · 3 Records · 4 Turns · 5 Clock · 6 Timeline · 7 Map. Change them here and
// in resources/settings/properties.xml together — properties.xml wins on a real device, this
// table is the fallback and the thing the unit test asserts against.
//
// Page 1 changed in 0.8.0 from the speed HERO (speed / flight timer / HR) to LAYOUT_MAIN.
// The flight timer and heart rate did not disappear: they are catalog metrics and go in any
// slot on any other page. What page 1 owes the rider is the four things he glances at
// between two jibes — how the last run went, how the turns are going, whether he is still
// dry, and what time it is — and a duration is explicitly not one of them.
//
// Its giant became a SLOT in 0.8.2, defaulting to M_BEST_10S rather than live speed: a rider
// looks at the watch when he is not moving, and the live number at that moment reads 4 km/h
// and says nothing about the run he just finished. Anyone who wants the speedometer back sets
// pg1s1 to M_SPEED in Garmin Connect — the renderer does not know the difference.
//
// Slot semantics per layout:
//   MAIN     s1 = the giant (+ its inline unit and caption); the rest of the page is fixed
//   HERO     s1 = giant number (+ its unit line), s2/s3 = the two rows under it
//   GRID4    s1 = giant number on top (optional), s2..s5 = the 2x2 cells (TL, TR, BL, BR).
//            s1 = M_FOIL_PCT makes that band a PAIR — foil time % beside foil dist %
//            (bandPartner below) — which is what the shipped Session page draws.
//   CELLS2   s1/s2 = two side-by-side cells
//   CLOCK    s1 = the single cell under the giant time of day
//   FOIL / RECORDS / TURNS / TIMELINE / MAP   bespoke renderers, slots unused
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
        LAYOUT_TIMELINE = 8,
        // The default page 1 since 0.8.0: a giant (slot 1, best 10 s by default), the outcome
        // ladder as three counts, the turn-outcome strip, the no-fall streak and the time of
        // day. Bespoke like RECORDS/TURNS — everything but the giant is the point of the
        // screen, so only slot 1 is read.
        LAYOUT_MAIN = 9,
        // The default page 2 since 0.8.2: the foil TABLE. Three rows of two — the two shares,
        // the two totals, the two bests — under one "min / km" pair of column headers. Bespoke
        // like MAIN/RECORDS/TURNS: no slot is read, because every cell on it is a foil number
        // and a configurable cell could only make it a worse version of the grid it replaced.
        LAYOUT_FOIL = 10
    }
    const LAYOUT_MAX = 10;

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
        M_TAKEOFF_COST = 19,
        // "now/best" no-fall streak (docs/algorithms.md "Turn streaks"). On the main screen
        // it has its own row; here it is a cell like any other, for a rider who wants it on
        // page 3 instead.
        M_STREAK = 20,
        // The distance twin of M_FOIL_PCT: what share of the KILOMETRES was flown, against
        // M_FOIL_PCT's share of the MINUTES. The two are one fact seen from two sides and the
        // default Session page shows them side by side (see bandPair below).
        M_FOIL_DIST_PCT = 21
    }
    const M_MAX = 21;

    // Seven configurable pages since 0.8.2. The seventh exists so the BREADCRUMB MAP can ship
    // ON by default: the page has been in the app since 0.7 but was never in the shipped set,
    // and a rider who has to find "Map" in a Garmin Connect layout list never learns it is
    // there. It goes LAST because it is the least glanceable, not because it is special: since
    // 0.9.2 the trail is drawn by RecordingView like every other page (TrackDraw), so it needs
    // no firmware map support, carries the PAUSED banner, and exists on every product.
    const MAX_PAGES = 7;
    const SLOTS = 5;

    // ---- the shipped five pages, as data ----
    var DEF_LAYOUT as Array<Number> = [
        LAYOUT_MAIN, LAYOUT_FOIL, LAYOUT_RECORDS, LAYOUT_TURNS, LAYOUT_CLOCK, LAYOUT_TIMELINE,
        LAYOUT_MAP
    ];
    // Page 2's slots are LEFT AT THE OLD SESSION GRID even though LAYOUT_FOIL reads none of
    // them. Two reasons: a rider who sets page 2 back to "Grid" in Garmin Connect gets exactly
    // the page he had, cell for cell; and pg2s1 = M_FOIL_PCT is what the bezel-arc rule keys
    // on, so the arc survives that switch in both directions.
    var DEF_SLOTS as Array<Array<Number> > = [
        [M_BEST_10S, M_NONE, M_NONE, M_NONE, M_NONE],
        [M_FOIL_PCT, M_FOIL_TIME, M_LONGEST, M_DISTANCE, M_FLIGHTS],
        [M_NONE, M_NONE, M_NONE, M_NONE, M_NONE],
        [M_NONE, M_NONE, M_NONE, M_NONE, M_NONE],
        [M_TIMER, M_NONE, M_NONE, M_NONE, M_NONE],
        [M_NONE, M_NONE, M_NONE, M_NONE, M_NONE],
        [M_NONE, M_NONE, M_NONE, M_NONE, M_NONE]
    ];

    // ---- built state ----
    // `_layout`/`_slot` are indexed by CONFIG page (0..5); `_order` lists the configured pages
    // that are actually on, in order, and is what the UI cycles through.
    var _layout as Array<Number> = [0, 0, 0, 0, 0, 0, 0];
    var _slot as Array<Array<Number> > = [
        [0, 0, 0, 0, 0], [0, 0, 0, 0, 0], [0, 0, 0, 0, 0], [0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0], [0, 0, 0, 0, 0], [0, 0, 0, 0, 0]
    ];
    var _order as Array<Number> = [0];
    var mapPage as Boolean = false;      // any page asks for the breadcrumb map

    // Rebuilds the model. `src` null = read GCM properties; a Dictionary = read that instead
    // (the unit tests inject one, so "defaults reproduce the shipped pages" is assertable
    // without a device).
    function build(src as Dictionary?) as Void {
        var order = [] as Array<Number>;
        mapPage = false;
        for (var p = 0; p < MAX_PAGES; p++) {
            var key = "pg" + (p + 1).toString();
            var lay = _clamp(_read(src, key + "Layout", DEF_LAYOUT[p]), 0, LAYOUT_MAX);
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

    // Does the i-th visible page draw the foil-% bezel arc? Two ways to earn it: carry foil %
    // in a slot (any configurable layout), or BE the foil page — LAYOUT_FOIL reads no slots,
    // and a page whose every number is a foil number does not need a cell to prove it.
    function pageDrawsFoilArc(i as Number) as Boolean {
        return layoutAt(i) == LAYOUT_FOIL || pageHasMetric(i, M_FOIL_PCT);
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
        if (id == M_STREAK) { return "dry run"; }
        if (id == M_FOIL_DIST_PCT) { return "foil dist"; }
        return "";
    }

    // ---- the paired top band ----
    // A GRID4 giant slot holding M_FOIL_PCT does not draw one number: it draws BOTH foil
    // shares, time on the left and distance on the right, because the pair is the fact and
    // either half alone is half of it. Riders read "56 % of the session" and hear "and barely
    // moving the rest of it" — the distance share (61 %) is what says how much of the WATER he
    // covered on the foil, and the two are only meaningful against each other.
    //
    // It is a CONVENTION, not a layout: no new page type, no sixth slot, no default to move in
    // properties.xml — page 2 still ships `pg2s1 = 2` and every watch already carrying that
    // value gets the pair on the next update. Only M_FOIL_PCT opens the band, so a rider who
    // puts the distance share anywhere (a cell, another page's giant) gets exactly the single
    // metric he asked for, and the foil-% bezel arc's rule — "this page carries M_FOIL_PCT" —
    // needs no special case either.
    function bandPartner(id as Number) as Number {
        return id == M_FOIL_PCT ? M_FOIL_DIST_PCT : M_NONE;
    }

    // The word under each half of that band. Deliberately NOT the catalog labels: side by side
    // the only thing the eye has to separate two "61 %" is which one is which, and "time" /
    // "dist" is that distinction with nothing else in the way. Both halves are foil shares —
    // the word "foil" would be printed twice and separate nothing.
    function bandCaption(id as Number) as String {
        if (id == M_FOIL_PCT) { return "time"; }
        if (id == M_FOIL_DIST_PCT) { return "dist"; }
        return caption(id);
    }

    // The symbol a cell shows beside (or, with showLabels off, instead of) its label.
    // Metrics that measure the same thing share a glyph on purpose — the label, when it is on,
    // is what separates "foil" from "longest"; the glyph says which FAMILY the number is from,
    // which is all the eye needs at 25 kn.
    function glyph(id as Number) as Number {
        if (id == M_SPEED || id == M_BEST_2S || id == M_BEST_10S) { return Glyphs.G_BOLT; }
        if (id == M_FOIL_PCT || id == M_FLIGHTS || id == M_FOIL_DIST_PCT) {
            return Glyphs.G_WING;
        }
        if (id == M_FLIGHT_TIMER || id == M_FOIL_TIME || id == M_LONGEST || id == M_TIMER
            || id == M_CLOCK) {
            return Glyphs.G_WATCH;
        }
        if (id == M_DISTANCE) { return Glyphs.G_RULER; }
        // the takeoff cost is a heartbeat number before it is a pumping one: what the eye is
        // being told is "this is your heart", and the label says which of the two it is
        if (id == M_HR || id == M_TAKEOFF_COST) { return Glyphs.G_HEART; }
        if (id == M_TURNS || id == M_TURN_SCORE || id == M_STREAK) { return Glyphs.G_TURN; }
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
        if (id == M_FOIL_DIST_PCT) {
            // "--" until the odometer has anything to take a share OF. A "0%" before the
            // first metre is not a fact about the session, it is a division that has not
            // happened yet — the same rule M_PUMPS_TO_TAKEOFF and M_TAKEOFF_COST keep.
            return e.distM > 0 ? e.foilDistPct().format("%.0f") + "%" : "--";
        }
        if (id == M_STREAK) { return streakText(e.turns); }
        return "";
    }

    // Appended in HERO sub-rows only (they carry no label of their own). Cells put the unit
    // in the label instead, which is what keeps a 2x2 grid inside the round glass.
    function suffix(id as Number) as String {
        return id == M_HR || id == M_TAKEOFF_COST ? " bpm" : "";
    }

    // ---- the MAIN giant's inline suffix ----
    // The MAIN page spends no row on a unit line: the unit sits beside the digits, and under
    // it a caption saying WHAT the number is. The two are split because they answer different
    // questions — "24.3 what?" and "24.3 when?" — and because a metric whose label already IS
    // its unit (speed, distance) must not print it twice.

    // The unit that belongs behind the digits, "" when the metric has none.
    function unitOf(id as Number) as String {
        if (id == M_SPEED || id == M_BEST_2S || id == M_BEST_10S) {
            return AppSettings.speedLabel();
        }
        if (id == M_DISTANCE) { return "km"; }
        if (id == M_HR || id == M_TAKEOFF_COST) { return "bpm"; }
        return "";
    }

    // The word that says which number this is, "" when the label is already the unit and
    // would only be printed twice.
    function caption(id as Number) as String {
        var l = label(id);
        return l.equals(unitOf(id)) ? "" : l;
    }

    // "now / best" — the live dry streak beside the session's longest. One string so it fits
    // a cell; the main screen draws the two halves separately so it can colour them.
    function streakText(t as TurnDetector) as String {
        return t.dryStreak.toString() + "/" + t.bestDryStreak.toString();
    }

    // Cell/row ink. Two rules from docs/presentation.md decide every line here:
    // the phase tint is TEAL and not the ladder's green (green means "flew through", and a
    // page that says green for both is lying about one of them), and the outcome ladder is a
    // verdict scale nothing else may borrow — which is why heart rate is no longer the
    // ladder's red. A pulse is not a swim.
    function color(id as Number, c as SessionController) as Number {
        if (id == M_FLIGHT_TIMER) {
            return c.engine.detector.state == FlightDetector.STATE_ON
                ? Ink.phaseFlying() : Ink.dim();
        }
        if (id == M_HR || id == M_TAKEOFF_COST) { return Ink.effortPumping(); }
        if (id == M_FOIL_PCT || id == M_FOIL_DIST_PCT) { return Ink.phaseFlying(); }
        return Graphics.COLOR_WHITE;
    }

    // Widest string each metric can realistically produce. Used only by the layout tests —
    // it is the "worst-case content" they measure, so keep it honest when a formatter changes.
    function worstValue(id as Number) as String {
        if (id == M_NONE) { return ""; }
        if (id == M_SPEED || id == M_BEST_2S || id == M_BEST_10S || id == M_DISTANCE) {
            return "99.9";
        }
        if (id == M_FOIL_PCT || id == M_FOIL_DIST_PCT || id == M_TURN_SCORE
            || id == M_BATTERY) {
            return "100%";
        }
        if (id == M_FLIGHTS || id == M_TURNS) { return "999"; }
        // the cost is a difference inside the 30-220 bpm plausibility band, so three digits is
        // its honest ceiling even though a real takeoff costs 7
        if (id == M_HR || id == M_PUMPS_TO_TAKEOFF || id == M_TAKEOFF_COST) { return "199"; }
        if (id == M_PUMP_STROKES) { return "9999"; }
        if (id == M_TAKEOFFS) { return "99>99"; }
        if (id == M_STREAK) { return "99/99"; }
        if (id == M_CLOCK) { return "23:59"; }
        return "199:59";   // every timer: >3 h sessions still read m:ss
    }

    function worstLabel(id as Number) as String {
        return id == M_SPEED ? "km/h" : label(id);
    }

    // ---- CPH: clean jibes per hour (device app 0.9.5) ----
    //
    // A tally answers "how many", a rate answers "how busy" (docs/algorithms.md "Session
    // rates"). The phone divides by the elapsed span of the CLEANED TRACK, gaps included; the
    // watch has no cleaned track, so it divides by the session's own wall clock — the same
    // number the post-save verdict page already prints as "of 1:47:12". That divergence is
    // recorded in docs/algorithms.md's watch-divergence list; it is small (the two differ only
    // by whatever the phone's cleaner drops off the ends) and it is the only denominator the
    // watch actually has.
    //
    // NO RATE BEFORE A MINUTE. One clean jibe forty seconds in is not "ninety an hour", it is
    // one clean jibe and not enough afternoon to divide by — the same never-a-flattering-zero
    // rule the engine applies at `durationS <= 0`, moved up to where a watch needs it, because
    // the watch is asked the question live and the first minute is where the answer is silliest.
    // Below the floor the caller gets a negative, which `fmtCph` prints as the app's own
    // "unmeasured" mark rather than as a number nobody should read.
    const CPH_MIN_ELAPSED_S = 60.0;
    const CPH_NONE = "--";

    // Clean jibes per hour, or a NEGATIVE value when there is no hour to divide by yet.
    function cleanPerHour(cleanJibes as Number, elapsedS as Float) as Float {
        if (elapsedS < CPH_MIN_ELAPSED_S || cleanJibes < 0) {
            return -1.0;
        }
        return cleanJibes * 3600.0 / elapsedS;
    }

    // The same, formatted for a row: one decimal, or "--" while there is no rate to state.
    // "--" and not "0.0", for the reason above, and not "-" because "--" is already what this
    // watch prints everywhere a value was not measured (SummaryView's takeoff rows, the HR
    // cost). One idiom for one meaning.
    function fmtCph(cleanJibes as Number, elapsedS as Float) as String {
        var v = cleanPerHour(cleanJibes, elapsedS);
        return v < 0.0 ? CPH_NONE : v.format("%.1f");
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
