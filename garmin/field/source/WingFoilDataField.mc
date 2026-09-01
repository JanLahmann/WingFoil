import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import WingFoilCore;

// The on-water face of the data field. Three layouts, chosen from the cell the system gives
// us (FieldLayout.fitCell — how much room it has AND how much of that room is glass), all
// built from the same numbers:
//
//   SMALL (3-4 field cell)  foil %            + flights · flight timer
//   WIDE  (2 field cell)    foil %            + flights · flight timer + outcome · tally
//   FULL  (1 field page)    speed, foil %, flights + flight timer, last turn outcome word
//                           and score, tack/jibe split and flew·touch·swim tally
//
// The last turn's outcome is a colour-coded word — FLEW green, TOUCH orange, SWIM red — the
// same vocabulary as the device app's Turns page, because it is the one thing you want to
// read at a glance while sailing away from the maneuver you just made.
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
        if (!unlocked()) {
            drawLocked(dc, w, h, bg, size, g);
            return;
        }
        drawStack(dc, w, h, rowTexts(size), rowColors(size, bg),
            cell[1] as Array<Graphics.FontType>, cell[2] as Number, g);
    }

    const CV = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

    // Foreground that survives both the light and the dark data-field theme.
    hidden function fg(bg as Graphics.ColorType) as Graphics.ColorType {
        return bg == Graphics.COLOR_BLACK ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
    }

    // SMALL (3-4 field cell) is the two numbers that decide whether the session is going well;
    // WIDE (2-field cell) adds the turn line; FULL (1-field page) is everything, biggest first.
    // The rows of one of those three, in order: the strings to draw, and the colour each one
    // carries. The fonts come from FieldLayout's worst-case table for that layout — the very
    // table fitCell() used to decide this cell could carry it — so what is drawn is what was
    // measured.
    hidden function rowTexts(size as Number) as Array<String> {
        if (size == FieldLayout.SIZE_FULL) {
            return [speedText(), pctText(), flightText(), outcomeText(),
                tallyText()] as Array<String>;
        }
        if (size == FieldLayout.SIZE_WIDE) {
            return [pctText(), flightText(), turnLine()] as Array<String>;
        }
        return [pctText(), flightText()] as Array<String>;
    }

    hidden function rowColors(size as Number, bg as Graphics.ColorType)
            as Array<Graphics.ColorType> {
        if (size == FieldLayout.SIZE_FULL) {
            return [fg(bg), stateColor(bg), fg(bg), outcomeColor(bg),
                fg(bg)] as Array<Graphics.ColorType>;
        }
        if (size == FieldLayout.SIZE_WIDE) {
            return [stateColor(bg), fg(bg), outcomeColor(bg)] as Array<Graphics.ColorType>;
        }
        return [stateColor(bg), fg(bg)] as Array<Graphics.ColorType>;
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
        // are literals), so the fit needs no widest-case placeholders.
        var ladders = [] as Array;
        for (var i = 0; i < texts.size(); i++) {
            ladders.add(FieldLayout.TEXT_FONTS);
        }
        var stack = FieldLayout.fitStack(dc, w, h, texts, ladders, g);
        drawStack(dc, w, h, texts, colors, stack[0] as Array<Graphics.FontType>,
            stack[1] as Number, g);
    }

    // Draw a fitted stack. Each row is centred on its own window rather than on the cell: on a
    // corner cell the glass runs out on the inboard side first, so a row that stayed glued to
    // the middle of its cell would lose characters it could have kept by sliding a few pixels
    // towards the middle of the watch. Where the window is the whole cell — every full-width
    // cell, and every cell away from the rim — that centre IS w / 2.
    hidden function drawStack(dc as Dc, w as Number, h as Number, texts as Array<String>,
            colors as Array<Graphics.ColorType>, fonts as Array<Graphics.FontType>,
            lean as Number, g as FieldLayout.Glass?) as Void {
        var heights = FieldLayout.heightsOf(dc, fonts);
        for (var i = 0; i < texts.size(); i++) {
            var y = FieldLayout.stackY(h, heights, i, lean);
            var window = FieldLayout.rowWindow(w, y, heights[i], g);
            dc.setColor(colors[i], Graphics.COLOR_TRANSPARENT);
            dc.drawText(window[0], y, fonts[i], texts[i], CV);
        }
    }

    // ---- the numbers ----

    hidden function pctText() as String {
        return _engine.foilPct().format("%.0f") + "%";
    }

    // flights so far, and the flight you are in right now (or --:-- off the foil)
    hidden function flightText() as String {
        var d = _engine.detector;
        var t = _engine.flying() ? fmtTime(d.currentFlightS) : "--:--";
        return d.flightCount.toString() + " · " + t;
    }

    hidden function speedText() as String {
        var cfg = FieldSettings.cfg;
        return cfg.speedToDisplay(_engine.speedMps).format("%.1f") + " " + cfg.speedLabel();
    }

    // Last turn: the outcome word plus the score that turn carried.
    hidden function outcomeText() as String {
        var t = _engine.turns;
        if (t.lastOutcome == TurnDetector.OUTCOME_NONE) {
            return t.turnCount > 0 ? "TURN" : "--";
        }
        return outcomeWord() + " " + t.lastScorePct.toString() + "%";
    }

    hidden function outcomeWord() as String {
        var o = _engine.turns.lastOutcome;
        if (o == TurnDetector.OUTCOME_FLEW) {
            return "FLEW";
        }
        if (o == TurnDetector.OUTCOME_TOUCHDOWN) {
            return "TOUCH";
        }
        return o == TurnDetector.OUTCOME_FELL ? "SWIM" : "--";
    }

    // tacks/jibes, then the flew · touchdown · swim tally
    hidden function tallyText() as String {
        var t = _engine.turns;
        return t.tackCount.toString() + "/" + t.jibeCount.toString() + " · "
            + t.flewCount.toString() + "·" + t.touchdownCount.toString() + "·"
            + t.fellCount.toString();
    }

    hidden function turnLine() as String {
        var t = _engine.turns;
        return outcomeText() + " · " + t.tackCount.toString() + "/"
            + t.jibeCount.toString();
    }

    hidden function stateColor(bg as Graphics.ColorType) as Graphics.ColorType {
        return _engine.flying() ? Graphics.COLOR_GREEN : fg(bg);
    }

    hidden function outcomeColor(bg as Graphics.ColorType) as Graphics.ColorType {
        var o = _engine.turns.lastOutcome;
        if (o == TurnDetector.OUTCOME_FLEW) {
            return Graphics.COLOR_GREEN;
        }
        if (o == TurnDetector.OUTCOME_TOUCHDOWN) {
            return Graphics.COLOR_ORANGE;
        }
        return o == TurnDetector.OUTCOME_FELL ? Graphics.COLOR_RED : fg(bg);
    }

    static function fmtTime(seconds as Float) as String {
        var s = seconds.toNumber();
        return (s / 60).format("%d") + ":" + (s % 60).format("%02d");
    }
}
