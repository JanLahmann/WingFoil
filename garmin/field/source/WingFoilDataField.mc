import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import WingFoilCore;

// The on-water face of the data field. The system hands us a cell and never says what it is
// for, so everything here is chosen from that rectangle (FieldLayout.fitCell — how much room
// it has AND how much of that room is glass):
//
//   SMALL (3-4 field cell)  a slot of the rider's choosing + flights · flight timer
//   WIDE  (2 field cell)    two slots of his choosing      + the turn line
//   FULL  (1 field page)    the device app's Main page
//
// 0.9.5 is where the last of those three stopped being a list of numbers. It used to stack
// five values — speed, foil %, flights, last turn, tally — one under the other with nothing to
// say what any of them was, and Jan's verdict on the store screenshots of exactly that was
// "hard to understand for a user — what's being shown there?". It is now the app's own Main
// page: foil %, a giant number, the outcome dot ladder, the coloured tally, the dry run, each
// with the small XTINY word beside it that says what it is. Same composition, same colour
// vocabulary, same order as the app — a rider who knows one knows the other.
//
// The smaller cells went the other way in the same release: they cannot afford a caption (a
// 129 x 129 px quadrant on an fr255 is already trading font rungs against the chord), so
// instead the rider chooses what they carry — one metric for a SMALL cell, two for a WIDE row,
// out of everything a data field can compute.
//
// In the invite build (docs/decisions.md ADR-012) all of that is replaced by the lock state
// until the tester enters their key. The device app can switch to a whole LockView for this;
// a data field owns one view and one cell, so the lock lives here as a fourth layout.
class WingFoilDataField extends WatchUi.DataField {
    hidden var _engine as FieldEngine;
    hidden var _fit as FieldFit?;
    hidden var _screenW as Number = 0;
    hidden var _screenH as Number = 0;
    hidden var _round as Boolean = false;
    // Seconds the activity timer has been off. compute() is the only clock a data field is
    // allowed (a Timer would be a second one, and the system's 1 Hz call is already the beat
    // everything else runs on), and this is the one thing it is used for that is not a metric:
    // which summary page a stopped rider is looking at.
    hidden var _pausedTicks as Number = 0;

    function initialize() {
        DataField.initialize();
        // Belt to WingFoilFieldApp.onStart's braces. The gate answers "locked" until someone
        // calls refresh(), so an ordering where the view is built before onStart runs would
        // put a lock screen on the ORDINARY field — the one build that must never show one.
        // With the zero pepper this costs one array scan and settles the question here.
        LockGate.refresh();
        _engine = new FieldEngine(FieldSettings.cfg);
        var s = System.getDeviceSettings();
        _screenW = s.screenWidth;
        _screenH = s.screenHeight;
        // Only a round glass eats the corners of a cell. Every product in the manifest is
        // round today, so this is a guard rather than a branch anyone exercises — but the
        // chord maths is nonsense on a rectangle and must not run there.
        _round = s.screenShape == System.SCREEN_SHAPE_ROUND;
        try {
            _fit = new FieldFit(self);
        } catch (e) {
            _fit = null;        // no FitContributor permission: still a useful live display
        }
    }

    function engine() as FieldEngine {
        return _engine;
    }

    // ---- activity lifecycle ----

    function onTimerReset() as Void {
        _engine.reset();        // a new activity: every counter starts over
        _pausedTicks = 0;
    }

    // ---- the invite gate ----

    // The one check compute() and onUpdate() share. Static and free of Dc and Activity.Info
    // so the unit suite can drive the locked path with nothing but a FieldEngine.
    //
    // Deliberately NOT `!LockGate.enabled() || LockGate.isUnlocked()`: the gate reports
    // unlocked by itself as soon as refresh() sees a zero pepper, so the short-circuit would
    // buy nothing and would make the locked path untestable in a zero-pepper test binary.
    static function unlocked() as Boolean {
        return LockGate.isUnlocked();
    }

    // ---- 1 Hz compute ----

    function compute(info as Activity.Info) as Void {
        // A locked field is INERT, not merely blank: no engine tick and no FitContributor
        // write, so the recorded activity carries no wingfoil fields at all. A half-computed
        // FIT from a tester who never entered their key would be worse than none — it would
        // look like real data in Garmin Connect and in the lab parser.
        if (!unlocked()) {
            return;
        }
        var events = _engine.onCompute(info);
        // The paused clock. It advances on the seconds the ACTIVITY is not counting, which is
        // exactly the reading a summary page is for, and it starts over the moment the rider
        // sets off again so that the next stop opens on page A rather than wherever the last
        // one happened to leave off.
        _pausedTicks = _engine.running ? 0 : _pausedTicks + 1;
        if (_fit == null) {
            return;
        }
        var turnEvent = (events >> 8) & 0x0F;
        var fit = _fit as FieldFit;
        fit.setRecord(_engine.detector.state, _engine.tickCount(),
            FieldFit.markerFor(turnEvent, _engine.turns.lastKind));
        fit.updateSession(_engine, FieldSettings.cfg);
    }

    // ---- drawing ----

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var bg = getBackgroundColor();
        dc.setColor(bg, bg);
        dc.clear();

        // getObscurityFlags() is documented as valid only inside onUpdate(), which is also
        // the only place the cell rectangle is known — so the geometry is rebuilt here every
        // frame rather than cached in initialize(). It costs one object and no measurement.
        var g = FieldLayout.place(w, h, _screenW, _screenH, getObscurityFlags(), _round);
        var cell = FieldLayout.fitCell(dc, w, h, _screenW, _screenH, g);
        var size = cell[0] as Number;
        var fonts = cell[1] as Array<Graphics.FontType>;
        var lean = cell[2] as Number;
        var caps = cell[3] as Array<Array<String> >;
        if (!unlocked()) {
            drawLocked(dc, w, h, bg, size, g);
            return;
        }
        if (size == FieldLayout.SIZE_FULL) {
            // Stopped or paused, and the cell is the whole glass: the rider is looking, so
            // give him the session rather than the second. Smaller cells keep their configured
            // metric — there is no room in a quadrant for a summary, and the number he chose
            // is the one he wants at a standstill too.
            if (!_engine.running) {
                var page = FieldLayout.summaryPage(_pausedTicks);
                var stack = FieldLayout.fitRendition(dc, w, h, page, g);
                if (stack != null) {
                    drawSummary(dc, w, h, bg, page, stack as Array, g);
                    return;
                }
            }
            drawMainPage(dc, w, h, bg, fonts, lean, g);
            return;
        }
        drawSlots(dc, w, h, bg, size, fonts, lean, caps, g);
    }

    const LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;

    // Foreground that survives both the light and the dark data-field theme.
    hidden function fg(bg as Graphics.ColorType) as Graphics.ColorType {
        return FieldMetrics.fg(bg);
    }

    // ---- the MAIN page (SIZE_FULL) ----
    //
    // The device app's Main page, on the one cell big enough to carry it. Five rows, in the
    // app's own order:
    //   0  foil % — the field's headline number, and the one the app draws as the arc around
    //      this very page. A data field cannot spend a ring on it, so it spends a row.
    //   1  the giant — live speed while the timer runs, the session's best 10 s when it does
    //      not, with the unit and the word that says which stacked beside the digits (the
    //      app's own inline-suffix form). A paused rider wants the session's best; a riding
    //      one wants the needle, and the caption means the page never has to be guessed at.
    //   2  the outcome dot ladder — one dot per counted turn in its verdict colour, oldest
    //      left. The counts under it say how many; the strip says how they ARRIVED, and three
    //      swims in a row is a different session from three swims in an hour.
    //   3  the same three counts as numbers, in the same three colours.
    //   4  the dry run: turns since he last went in, beside the session's longest.
    hidden function drawMainPage(dc as Dc, w as Number, h as Number, bg as Graphics.ColorType,
            fonts as Array<Graphics.FontType>, lean as Number,
            g as FieldLayout.Glass?) as Void {
        var heights = FieldLayout.heightsOf(dc, fonts);
        var caps = FieldLayout.CAPS[FieldLayout.SIZE_FULL];
        var cfg = FieldSettings.cfg;
        var t = _engine.turns;

        // row 0 — foil %
        var y = FieldLayout.stackY(h, heights, 0, lean);
        drawValueWithCap(dc, FieldLayout.rowWindow(w, y, heights[0], g), y, fonts[0],
            FieldMetrics.value(FieldMetrics.M_FOIL_PCT, _engine, cfg),
            FieldMetrics.color(FieldMetrics.M_FOIL_PCT, _engine, bg), caps[0], heights[0], bg);

        // row 1 — the giant
        var live = _engine.running;
        var mps = live ? _engine.speedMps : _engine.records.best10sMps;
        y = FieldLayout.stackY(h, heights, 1, lean);
        drawValueWithCap(dc, FieldLayout.rowWindow(w, y, heights[1], g), y, fonts[1],
            cfg.speedToDisplay(mps).format("%.1f"), fg(bg),
            [cfg.speedLabel(), live ? "speed" : "best 10s"] as Array<String>, heights[1], bg);

        // row 2 — the dot ladder
        y = FieldLayout.stackY(h, heights, 2, lean);
        drawDotRow(dc, FieldLayout.rowWindow(w, y, heights[2], g), y, heights[2], caps[2], bg);

        // row 3 — the counts, in the ladder's colours
        y = FieldLayout.stackY(h, heights, 3, lean);
        drawTallyRow(dc, FieldLayout.rowWindow(w, y, heights[3], g), y, fonts[3], heights[3],
            " · ", caps[3], bg);

        // row 4 — the dry run
        y = FieldLayout.stackY(h, heights, 4, lean);
        drawValueWithCap(dc, FieldLayout.rowWindow(w, y, heights[4], g), y, fonts[4],
            t.dryStreak.toString() + " / " + t.bestDryStreak.toString(),
            fg(bg), caps[4], heights[4], bg);
    }

    // ---- the summary pages (paused / stopped, full-screen only) ----
    //
    // The two halves of the session, alternating every FieldLayout.SUMMARY_TICKS seconds. Page
    // A is what the session WAS — foil share, foil time against moving time, flights, the
    // longest one, distance. Page B is how it was RIDDEN — the two speed records, the turn
    // count and its tack/jibe split, the outcome tally in its colours, and the dry run.
    //
    // Between them they are every number the field writes into the FIT, which is the point: a
    // rider who stops at the beach can read his session off the watch instead of waiting for
    // the phone. Each row carries its word, because a summary nobody can decode is a table of
    // numbers, and this is the screen a stranger is most likely to be looking at.
    hidden function drawSummary(dc as Dc, w as Number, h as Number, bg as Graphics.ColorType,
            page as Number, stack as Array, g as FieldLayout.Glass?) as Void {
        var fonts = stack[0] as Array<Graphics.FontType>;
        var lean = stack[1] as Number;
        var heights = FieldLayout.heightsOf(dc, fonts);
        var caps = FieldLayout.CAPS[page];
        var texts = summaryTexts(page);
        for (var i = 0; i < texts.size(); i++) {
            var y = FieldLayout.stackY(h, heights, i, lean);
            var win = FieldLayout.rowWindow(w, y, heights[i], g);
            // Page B's outcome row is the same three counts in the same three inks as the live
            // page's, drawn by the same function: one vocabulary, one place it is drawn.
            if (page == FieldLayout.REND_SUM_B && i == 2) {
                drawTallyRow(dc, win, y, fonts[i], heights[i], " · ", caps[i], bg);
                continue;
            }
            // Neutral ink throughout: a stopped session has no live state to tint, and the one
            // place colour still means something on these pages is the outcome row above.
            drawValueWithCap(dc, win, y, fonts[i], texts[i], fg(bg), caps[i], heights[i], bg);
        }
    }

    hidden function summaryTexts(page as Number) as Array<String> {
        var e = _engine;
        var cfg = FieldSettings.cfg;
        var d = e.detector;
        var t = e.turns;
        // Row order is not arbitrary: the WIDEST row of each page sits nearest the middle of
        // the glass, where the chord is widest, and the short ones take the top and bottom
        // arcs. Page B's pair of speed records is 11 characters and would have had to shrink
        // to FONT_XTINY at the top of a 454 px circle; three rows down it keeps its size.
        if (page == FieldLayout.REND_SUM_B) {
            return [t.turnCount.toString(),
                t.tackCount.toString() + "/" + t.jibeCount.toString(),
                FieldMetrics.outcomesText(t),      // drawn piecewise; measured as this string
                cfg.speedToDisplay(e.records.best2sMps).format("%.1f") + "/"
                    + cfg.speedToDisplay(e.records.best10sMps).format("%.1f"),
                t.dryStreak.toString() + " / "
                    + t.bestDryStreak.toString()] as Array<String>;
        }
        return [e.foilPct().format("%.0f") + "%",
            d.flightCount.toString(),
            FieldMetrics.fmtTime(d.foilTimeS) + " / " + FieldMetrics.fmtTime(e.timerS),
            FieldMetrics.fmtTime(d.longestS),
            (e.distM / 1000.0).format("%.1f") + " km"] as Array<String>;
    }

    // ---- the configurable cells (SIZE_SMALL, SIZE_WIDE) ----
    //
    // The rows the rider chose, plus the fixed bottom row that is the field's signature. The
    // fonts come from FieldLayout's worst-case table for that size — the very table fitCell()
    // used to decide this cell could carry it, and the very table FieldSettings rewrote from
    // these same slots — so what is drawn is what was measured.
    hidden function drawSlots(dc as Dc, w as Number, h as Number, bg as Graphics.ColorType,
            size as Number, fonts as Array<Graphics.FontType>, lean as Number,
            caps as Array<Array<String> >, g as FieldLayout.Glass?) as Void {
        var slots = FieldSettings.slotsFor(size);
        var heights = FieldLayout.heightsOf(dc, fonts);
        for (var i = 0; i < slots.size(); i++) {
            var y = FieldLayout.stackY(h, heights, i, lean);
            drawValueWithCap(dc, FieldLayout.rowWindow(w, y, heights[i], g), y, fonts[i],
                FieldMetrics.value(slots[i], _engine, FieldSettings.cfg),
                FieldMetrics.color(slots[i], _engine, bg), caps[i], heights[i], bg);
        }
    }

    // Invite build, no key yet. The request code is the only thing the tester has to
    // transcribe and mail back, so it is the row that must survive the smallest cell: in a
    // 3- or 4-field cell the word LOCKED is dropped and the code gets the whole box. The
    // rows go through the same fitStack() ladder as every other layout — a data field has no
    // idea how big its cell is, and a hard-coded font would clip on the 240 px fenix 7. The
    // `size` handed in is fitCell's, so a cell that had to step down to two rows for the live
    // display drops the word here too, and the code keeps the box to itself.
    hidden function drawLocked(dc as Dc, w as Number, h as Number, bg as Graphics.ColorType,
            size as Number, g as FieldLayout.Glass?) as Void {
        var texts = [] as Array<String>;
        var colors = [] as Array<Graphics.ColorType>;
        if (size != FieldLayout.SIZE_SMALL) {
            texts.add("LOCKED");
            colors.add(Graphics.COLOR_ORANGE);
        }
        texts.add(LockGate.requestCode());
        colors.add(fg(bg));
        // A key that was typed but did not open the gate must SAY so; silence would read as
        // "nothing happened" and the tester would keep retyping the same wrong key.
        if (LockGate.rejected()) {
            texts.add("KEY?");
            colors.add(Graphics.COLOR_RED);
        }
        // Every string here is its own worst case (the code is always 8 characters, the rest
        // are literals), so the fit needs no widest-case placeholders — and no captions: the
        // word LOCKED is the caption.
        var ladders = [] as Array;
        for (var i = 0; i < texts.size(); i++) {
            ladders.add(FieldLayout.TEXT_FONTS);
        }
        var caps = FieldLayout.noCaps(texts.size());
        var stack = FieldLayout.fitStack(dc, w, h, texts, ladders, caps, g, -1);
        var fonts = stack[0] as Array<Graphics.FontType>;
        var lean = stack[1] as Number;
        var heights = FieldLayout.heightsOf(dc, fonts);
        for (var i = 0; i < texts.size(); i++) {
            var y = FieldLayout.stackY(h, heights, i, lean);
            drawValueWithCap(dc, FieldLayout.rowWindow(w, y, heights[i], g), y, fonts[i],
                texts[i], colors[i], caps[i], heights[i], bg);
        }
    }

    // ---- the row primitives ----

    // The dot ladder. The dots that fit, newest last, each in its verdict colour — and when
    // there are more turns than the chord holds, the most recent ones, because "how has the
    // last while gone" is the question a strip answers and the tally under it answers the
    // other one.
    hidden function drawDotRow(dc as Dc, win as Array<Number>, y as Number, rowH as Number,
            cap as Array<String>, bg as Graphics.ColorType) as Void {
        var e = _engine;
        var capW = FieldLayout.capWidth(dc, cap);
        var r = FieldLayout.dotRadius(rowH, _screenW);
        var gap = FieldLayout.dotGap(_screenW);
        var shown = FieldLayout.dotsShown(e.outcomeCount, win[1] - capW, r, gap);
        var dotsW = shown > 0 ? shown * (2 * r + gap) - gap : 0;
        // Before the first turn the strip is empty and only the word is left; it is centred by
        // itself rather than pushed off to one side of nothing, which would read as a
        // half-drawn screen.
        var block = dotsW > 0 ? dotsW + capW : capW - FieldLayout.CAP_GAP;
        var x = win[0] - block / 2;
        for (var i = 0; i < shown; i++) {
            dc.setColor(FieldMetrics.outcomeColor(e.outcomes[e.outcomeCount - shown + i], bg),
                Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x + r + i * (2 * r + gap), y, r);
        }
        drawCap(dc, dotsW > 0 ? x + dotsW + FieldLayout.CAP_GAP : x, y, rowH, cap, bg);
    }

    // "35 · 8 · 8" with the three counts in the ladder's own inks — green flew, orange touched
    // down, red swam. Colour AND position carry the verdict, so the row reads before the
    // digits are in focus, and it is the same three inks the dots above it are drawn in.
    hidden function drawTallyRow(dc as Dc, win as Array<Number>, y as Number,
            font as Graphics.FontType, rowH as Number, sep as String, cap as Array<String>,
            bg as Graphics.ColorType) as Void {
        var t = _engine.turns;
        var parts = [t.flewCount.toString(), sep, t.touchdownCount.toString(), sep,
            t.fellCount.toString()] as Array<String>;
        var colors = [Graphics.COLOR_GREEN, fg(bg), Graphics.COLOR_ORANGE, fg(bg),
            Graphics.COLOR_RED] as Array<Graphics.ColorType>;
        var valW = 0;
        for (var i = 0; i < parts.size(); i++) {
            valW += dc.getTextWidthInPixels(parts[i], font);
        }
        var x = win[0] - (valW + FieldLayout.capWidth(dc, cap)) / 2;
        for (var i = 0; i < parts.size(); i++) {
            dc.setColor(colors[i], Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, font, parts[i], LV);
            x += dc.getTextWidthInPixels(parts[i], font);
        }
        drawCap(dc, x + FieldLayout.CAP_GAP, y, rowH, cap, bg);
    }

    // One row: the value and, where there is one, the small word beside it saying what it is.
    // The pair is centred on the row's WINDOW rather than on the cell, for the same reason
    // every other row is — on a corner cell the glass runs out on the inboard side first, so a
    // row glued to the middle of its own cell loses characters it could have kept by sliding a
    // few pixels towards the middle of the watch. Where the window is the whole cell — every
    // full-width cell, and every cell away from the rim — that centre IS w / 2.
    hidden function drawValueWithCap(dc as Dc, win as Array<Number>, y as Number,
            font as Graphics.FontType, text as String, color as Graphics.ColorType,
            cap as Array<String>, rowH as Number, bg as Graphics.ColorType) as Void {
        var valW = dc.getTextWidthInPixels(text, font);
        var x = win[0] - (valW + FieldLayout.capWidth(dc, cap)) / 2;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, text, LV);
        drawCap(dc, x + valW + FieldLayout.CAP_GAP, y, rowH, cap, bg);
    }

    // The caption block, drawn from its left edge. One line sits on the row's centre; two are
    // stacked around it, the unit above the word, which is the device app's Main-giant form.
    hidden function drawCap(dc as Dc, x as Number, y as Number, rowH as Number,
            cap as Array<String>, bg as Graphics.ColorType) as Void {
        var lines = FieldLayout.capLines(dc, cap, rowH);
        if (lines == 0) {
            return;
        }
        dc.setColor(fg(bg), Graphics.COLOR_TRANSPARENT);
        // A block cut from two lines to one keeps the LAST one: the word that names the number
        // is worth more than the unit beside it.
        var first = cap.size() - lines;
        for (var i = 0; i < lines; i++) {
            dc.drawText(x, FieldLayout.capLineY(dc, y, i, lines), FieldLayout.CAP_FONT,
                cap[first + i], LV);
        }
    }
}
