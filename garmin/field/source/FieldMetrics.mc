import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import WingFoilCore;

// The catalog of numbers a data field can put in a configurable slot — the field's twin of the
// device app's PageModel metric table, and deliberately the same vocabulary: the ids that exist
// in both carry the DEVICE APP'S id (M_SPEED is 1 here because it is 1 there), so a rider who
// has set up the app's pages reads the same words in the field's settings and means the same
// thing by them. The composites at 22+ are field-only, because the field's rows are composites:
// its whole history is "two numbers in a cell you did not choose the size of".
//
// What is NOT here is as deliberate. Pump strokes, takeoffs, pumps-to-takeoff and takeoff cost
// (the app's 16-19) all come off the accelerometer, and Sensor.* crashes a data field
// (docs/fit-schema.md); battery (15) is the watch's business, not the session's; foil distance %
// (21) would need the odometer split the field does not keep. A slot the field cannot fill is
// worse than a slot that is not offered — it would read as a bug.
//
// Three functions per metric, and the whole design rests on the third:
//   value()   what to draw right now
//   ladder()  which font ladder the row walks (a string with letters or a '/' cannot use the
//             digit-only NUMBER fonts)
//   worst()   the WIDEST string this metric will ever produce
// worst() is what FieldSettings feeds into FieldLayout.WIDEST, so a cell is fitted against the
// end of a long session rather than against the minute it is being looked at — which is the one
// rule that keeps a configured field from starting to clip in hour two.
module FieldMetrics {
    // Ids 1-20 are the device app's own (garmin/source/ui/PageModel.mc); 22+ are field-only.
    enum {
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
        M_TURN_LAST = 13,
        M_CLOCK = 14,
        M_STREAK = 20,
        // ---- field-only composites ----
        M_FLIGHT_LINE = 22,     // "31 · 1:36" — flights so far, and the flight you are in
        M_TACK_JIBE = 23,       // "27/24"
        M_OUTCOMES = 24,        // "35·8·8" — flew, touched down, swam
        M_TURN_LINE = 25,       // "FLEW 88% · 27/24" — the WIDE cell's bottom row
        // 0.9.6, the clean jibe. These two are NOT in the 1-20 band even though they are the
        // device app's own metric, because the app's catalog stops at 21 (M_FOIL_DIST_PCT) and
        // has no id for either: the watch draws CPH as part of its bespoke Turns page rather
        // than as a slot. So they are field-only ids, allocated after M_TURN_LINE, and the day
        // the app gives them slot numbers of its own these two keep theirs — the settings list
        // is append-only, and a renumber would silently move every rider's configured row.
        M_CLEAN = 26,           // "12" — clean jibes this session
        M_CPH = 27              // "4.5" — clean jibes per hour, or "--" inside the first minute
    }

    // Every id a slot setting may hold, in the order resources/settings/settings.xml lists
    // them. M_TURN_LINE is absent on purpose: it IS the WIDE cell's fixed bottom row, so
    // offering it as a slot would let a rider ask for the same line twice.
    var LIST as Array<Number> = [M_SPEED, M_FOIL_PCT, M_FLIGHTS, M_FLIGHT_TIMER, M_FOIL_TIME,
        M_LONGEST, M_DISTANCE, M_TIMER, M_HR, M_BEST_2S, M_BEST_10S, M_TURNS, M_TURN_LAST,
        M_CLOCK, M_STREAK, M_FLIGHT_LINE, M_TACK_JIBE, M_OUTCOMES, M_CLEAN,
        M_CPH] as Array<Number>;

    // A slot that arrives out of range (an old property, a firmware that hands us junk) falls
    // back to this rather than drawing an empty row: a blank cell reads as a crashed field.
    const FALLBACK = M_FOIL_PCT;

    function known(id as Number) as Boolean {
        for (var i = 0; i < LIST.size(); i++) {
            if (LIST[i] == id) {
                return true;
            }
        }
        return false;
    }

    function sanitize(id as Number) as Number {
        return known(id) ? id : FALLBACK;
    }

    // ---- what to draw ----

    function value(id as Number, e as FieldEngine, cfg as WingFoilCore.Config) as String {
        var d = e.detector;
        var t = e.turns;
        if (id == M_SPEED) {
            return speedText(e.speedMps, cfg);
        }
        if (id == M_FOIL_PCT) {
            return e.foilPct().format("%.0f") + "%";
        }
        if (id == M_FLIGHTS) {
            return d.flightCount.toString();
        }
        if (id == M_FLIGHT_TIMER) {
            return flightTimer(e);
        }
        if (id == M_FOIL_TIME) {
            return fmtTime(d.foilTimeS);
        }
        if (id == M_LONGEST) {
            return fmtTime(d.longestS);
        }
        if (id == M_DISTANCE) {
            return (e.distM / 1000.0).format("%.1f") + " km";
        }
        if (id == M_TIMER) {
            return fmtTime(e.timerS);
        }
        if (id == M_HR) {
            // "--" and not "0": a watch that has not found the wrist yet has not measured a
            // resting heart of zero, it has measured nothing.
            return e.hr == null ? "-- bpm" : (e.hr as Number).toString() + " bpm";
        }
        if (id == M_BEST_2S) {
            return speedText(e.records.best2sMps, cfg);
        }
        if (id == M_BEST_10S) {
            return speedText(e.records.best10sMps, cfg);
        }
        if (id == M_TURNS) {
            return t.turnCount.toString();
        }
        if (id == M_TURN_LAST) {
            return turnLast(t);
        }
        if (id == M_CLOCK) {
            var c = System.getClockTime();
            return c.hour.format("%d") + ":" + c.min.format("%02d");
        }
        if (id == M_STREAK) {
            return t.dryStreak.toString() + " / " + t.bestDryStreak.toString();
        }
        if (id == M_FLIGHT_LINE) {
            return d.flightCount.toString() + " · " + flightTimer(e);
        }
        if (id == M_TACK_JIBE) {
            return t.tackCount.toString() + "/" + t.jibeCount.toString();
        }
        if (id == M_OUTCOMES) {
            return outcomesText(t);
        }
        if (id == M_CLEAN) {
            return t.cleanJibeCount.toString();
        }
        if (id == M_CPH) {
            return cphText(e);
        }
        if (id == M_TURN_LINE) {
            return turnLast(t) + " · " + t.tackCount.toString() + "/"
                + t.jibeCount.toString();
        }
        return "";
    }

    // The widest string this metric can ever produce. Deliberately pessimistic where the count
    // has no ceiling — 99 turns of one kind and a 199:59 timer are both past anything Jan has
    // ridden, and the cost of being wrong here is a clipped row three hours into a session
    // nobody is going to reproduce on land.
    function worst(id as Number) as String {
        if (id == M_SPEED || id == M_BEST_2S || id == M_BEST_10S) {
            // km/h is wider than kn, so the km/h form is the worst case in both unit settings
            // and the table stays a constant rather than a function of the rider's units.
            return "88.8 km/h";
        }
        if (id == M_FOIL_PCT) {
            return "100%";
        }
        if (id == M_FLIGHTS || id == M_TURNS) {
            return "999";
        }
        if (id == M_FLIGHT_TIMER || id == M_FOIL_TIME || id == M_LONGEST || id == M_TIMER) {
            return "199:59";
        }
        if (id == M_DISTANCE) {
            return "88.8 km";
        }
        if (id == M_HR) {
            return "199 bpm";
        }
        if (id == M_TURN_LAST) {
            return "TOUCH 100%";
        }
        if (id == M_CLOCK) {
            return "88:88";
        }
        if (id == M_STREAK) {
            return "99 / 99";
        }
        if (id == M_FLIGHT_LINE) {
            return "99 · 88:88";
        }
        if (id == M_TACK_JIBE) {
            return "99/99";
        }
        if (id == M_OUTCOMES) {
            return "99·99·99";
        }
        if (id == M_CLEAN) {
            return "999";
        }
        if (id == M_CPH) {
            // Two digits before the point is already absurd — 99 clean jibes an hour is one
            // every 36 seconds — but the rate is at its wildest just after the 60 s floor
            // lifts, where two clean jibes in the first minute and a bit read as 90-odd. The
            // worst case has to survive that minute, not the afternoon.
            return "99.9";
        }
        if (id == M_TURN_LINE) {
            return "TOUCH 100% · 99/99";
        }
        return "";
    }

    // The small word that says WHAT this row is — the caption FieldLayout draws beside the
    // value. Same vocabulary as the device app's PageModel.label(): lowercase, one or two
    // short words, and never the unit twice (the field's speed and distance values carry their
    // own unit, so their words name the QUANTITY instead — "speed", "dist" — where the app,
    // whose values are bare, uses "km/h" and "km").
    //
    // Short on purpose. A caption is width taken out of the value's window (FieldLayout.
    // rowInk), and in a 129 px quadrant every character of it is a character the number does
    // not get. "longest", not "longest flight".
    function label(id as Number) as String {
        if (id == M_SPEED) { return "speed"; }
        if (id == M_FOIL_PCT) { return "foil"; }
        if (id == M_FLIGHTS || id == M_FLIGHT_LINE) { return "flights"; }
        if (id == M_FLIGHT_TIMER) { return "flight"; }
        if (id == M_FOIL_TIME) { return "foil time"; }
        if (id == M_LONGEST) { return "longest"; }
        if (id == M_DISTANCE) { return "dist"; }
        if (id == M_TIMER) { return "timer"; }
        if (id == M_HR) { return "hr"; }
        if (id == M_BEST_2S) { return "best 2s"; }
        if (id == M_BEST_10S) { return "best 10s"; }
        if (id == M_TURNS) { return "turns"; }
        if (id == M_TURN_LAST || id == M_TURN_LINE) { return "last turn"; }
        if (id == M_CLOCK) { return "time"; }
        if (id == M_STREAK) { return "dry run"; }
        if (id == M_TACK_JIBE) { return "tack/jibe"; }
        if (id == M_OUTCOMES) { return "outcomes"; }
        if (id == M_CLEAN) { return "clean"; }
        // Not "clean/h": the letters would knock the value off the digit-only NUMBER ladder's
        // sibling row and, more to the point, "cph" is what the app, the phone and the web all
        // call it (docs/presentation.md, key metrics). One word for one number, everywhere.
        if (id == M_CPH) { return "cph"; }
        return "";
    }

    // The caption as the layout tables want it: a one-line block, empty when the metric has
    // no word of its own.
    function cap(id as Number) as Array<String> {
        var l = label(id);
        return l.length() == 0 ? ([] as Array<String>) : ([l] as Array<String>);
    }

    // The digit-only NUMBER fonts are worth two rungs of size, so a metric takes them whenever
    // every glyph it can print is a digit, a '.', a ':' or a '-'. Anything carrying a letter, a
    // '%', a '/' or the middle dot walks the text ladder instead — a number font would drop
    // those characters silently, which is worse than a smaller row.
    function ladder(id as Number) as Array<Graphics.FontType> {
        if (id == M_FOIL_PCT || id == M_FLIGHTS || id == M_FLIGHT_TIMER || id == M_FOIL_TIME
                || id == M_LONGEST || id == M_TIMER || id == M_TURNS || id == M_CLOCK
                || id == M_CLEAN || id == M_CPH) {
            // M_CPH belongs here by the rule as written: every glyph it can print is a digit,
            // a '.' or a '-' ("99.9" and the "--" of the first minute), and those the NUMBER
            // fonts all carry.
            return FieldLayout.NUM_FONTS;
        }
        return FieldLayout.TEXT_FONTS;
    }

    // Row ink. The field keeps the app's two rules: the flight state tints the numbers that are
    // ABOUT the flight, and the outcome ladder (green flew, orange touched, red swam) is a
    // verdict scale nothing else borrows.
    function color(id as Number, e as FieldEngine, bg as Graphics.ColorType)
            as Graphics.ColorType {
        if (id == M_FOIL_PCT || id == M_FLIGHT_TIMER) {
            return e.flying() ? Graphics.COLOR_GREEN : fg(bg);
        }
        if (id == M_TURN_LAST || id == M_TURN_LINE) {
            return outcomeColor(e.turns.lastOutcome, bg);
        }
        // The clean count and its rate are the same fact twice, so they are one ink — and it is
        // the strict verdict's own, never the ladder's green.
        if (id == M_CLEAN || id == M_CPH) {
            return cleanInk();
        }
        return fg(bg);
    }

    // ---- shared bits ----

    // Foreground that survives both the light and the dark data-field theme.
    function fg(bg as Graphics.ColorType) as Graphics.ColorType {
        return bg == Graphics.COLOR_BLACK ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
    }

    // The clean jibe's ink — the device app's `clean.jibe` token, which the field now compiles
    // in (garmin/source/DesignTokens.mc, reached through the jungle's sourcePath). Deliberately
    // NOT the outcome ladder's green: "flew through" and "flew through and carried it" are
    // different questions, and one green for both is the distinction the metric exists to make
    // being thrown away (docs/presentation.md "Clean jibe").
    //
    // This is Ink.cleanJibe() written out rather than called, because Ink.mc is the app's whole
    // colour vocabulary and the field wants one token out of it. The MIP twin still gets picked
    // — an 8 bpp watch quantises the AMOLED literal to it anyway, and naming the value the
    // glass will actually show is the point of the twins existing (DesignTokens.mc's header).
    const AMOLED_MIN_PX = 416;

    function cleanInk() as Graphics.ColorType {
        return System.getDeviceSettings().screenWidth < AMOLED_MIN_PX
            ? DesignTokens.CLEAN_JIBE_MIP : DesignTokens.CLEAN_JIBE;
    }

    // ---- CPH: clean jibes per hour ----
    //
    // The device app's PageModel.cleanPerHour/fmtCph, with the SAME floor and the same "--",
    // over the one clock a data field has. Not shared code and it cannot be: PageModel.mc is
    // the app's page catalog and reaches into AppSettings, Ink and half the app besides. What
    // IS shared is the contract, and it is short enough to state in full — a rate, a 60 s floor
    // and a dash below it — so both copies are pinned by tests on both sides rather than by a
    // comment asking the next reader to keep them equal.
    //
    // THE DENOMINATOR IS `FieldEngine.timerS`, i.e. Activity.Info.timerTime: the NATIVE
    // activity's own timer, which stops when the rider pauses and resumes when he starts again.
    // A data field has no SessionController and therefore no `elapsedNowS` to borrow — it does
    // not own the recording and cannot ask Garmin for the wall clock since START. So the field
    // divides by moving time where the device app divides by elapsed time, and both divide by
    // something narrower than the phone's cleaned-track span. The gap only opens on a session
    // with a long pause in it, and it opens the flattering way (a smaller denominator reads as
    // a higher rate), which is why it is written down in docs/algorithms.md's watch-divergence
    // list rather than left for someone to find on the water.
    const CPH_MIN_ELAPSED_S = 60.0;
    const CPH_NONE = "--";

    // Clean jibes per hour, or a NEGATIVE value when there is no hour to divide by yet.
    function cleanPerHour(cleanJibes as Number, elapsedS as Float) as Float {
        if (elapsedS < CPH_MIN_ELAPSED_S || cleanJibes < 0) {
            return -1.0;
        }
        return cleanJibes * 3600.0 / elapsedS;
    }

    // The same as a row: one decimal, or "--" while there is no rate to state. "--" and not
    // "0.0" — one clean jibe forty seconds in is not ninety an hour, it is one clean jibe and
    // not enough afternoon to divide by — and "--" rather than "-" because "--" is already what
    // this field prints wherever a value was not measured (the heart rate with no strap).
    function fmtCph(cleanJibes as Number, elapsedS as Float) as String {
        var v = cleanPerHour(cleanJibes, elapsedS);
        return v < 0.0 ? CPH_NONE : v.format("%.1f");
    }

    function cphText(e as FieldEngine) as String {
        return fmtCph(e.turns.cleanJibeCount, e.timerS);
    }

    function outcomeColor(o as Number, bg as Graphics.ColorType) as Graphics.ColorType {
        if (o == TurnDetector.OUTCOME_FLEW) {
            return Graphics.COLOR_GREEN;
        }
        if (o == TurnDetector.OUTCOME_TOUCHDOWN) {
            return Graphics.COLOR_ORANGE;
        }
        return o == TurnDetector.OUTCOME_FELL ? Graphics.COLOR_RED : fg(bg);
    }

    function speedText(mps as Float, cfg as WingFoilCore.Config) as String {
        return cfg.speedToDisplay(mps).format("%.1f") + " " + cfg.speedLabel();
    }

    function flightTimer(e as FieldEngine) as String {
        return e.flying() ? fmtTime(e.detector.currentFlightS) : "--:--";
    }

    function turnLast(t as TurnDetector) as String {
        if (t.lastOutcome == TurnDetector.OUTCOME_NONE) {
            return t.turnCount > 0 ? "TURN" : "--";
        }
        return outcomeWord(t.lastOutcome) + " " + t.lastScorePct.toString() + "%";
    }

    function outcomeWord(o as Number) as String {
        if (o == TurnDetector.OUTCOME_FLEW) {
            return "FLEW";
        }
        if (o == TurnDetector.OUTCOME_TOUCHDOWN) {
            return "TOUCH";
        }
        return o == TurnDetector.OUTCOME_FELL ? "SWIM" : "--";
    }

    function outcomesText(t as TurnDetector) as String {
        return t.flewCount.toString() + "·" + t.touchdownCount.toString() + "·"
            + t.fellCount.toString();
    }

    function fmtTime(seconds as Float) as String {
        var s = seconds.toNumber();
        return (s / 60).format("%d") + ":" + (s % 60).format("%02d");
    }
}
