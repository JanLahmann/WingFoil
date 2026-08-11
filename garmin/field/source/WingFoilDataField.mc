import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import WingFoilCore;

// The on-water face of the data field. Three layouts, chosen from the cell the system gives
// us (FieldLayout.classify), all built from the same numbers:
//
//   SMALL (3-4 field cell)  foil %            + flights · flight timer
//   WIDE  (2 field cell)    foil %            + flights · flight timer + outcome · tally
//   FULL  (1 field page)    speed, foil %, flights + flight timer, last turn outcome word
//                           and score, tack/jibe split and flew·touch·swim tally
//
// The last turn's outcome is a colour-coded word — FLEW green, TOUCH orange, SWIM red — the
// same vocabulary as the device app's Turns page, because it is the one thing you want to
// read at a glance while sailing away from the maneuver you just made.
class WingFoilDataField extends WatchUi.DataField {
    hidden var _engine as FieldEngine;
    hidden var _fit as FieldFit?;
    hidden var _screenW as Number = 0;
    hidden var _screenH as Number = 0;

    function initialize() {
        DataField.initialize();
        _engine = new FieldEngine(FieldSettings.cfg);
        var s = System.getDeviceSettings();
        _screenW = s.screenWidth;
        _screenH = s.screenHeight;
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

    // ---- 1 Hz compute ----

    function compute(info as Activity.Info) as Void {
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

        var size = FieldLayout.classify(w, h, _screenW, _screenH);
        var round = FieldLayout.isRoundFull(w, h, _screenW, _screenH);
        if (size == FieldLayout.SIZE_FULL) {
            drawFull(dc, w, h, bg, round);
        } else if (size == FieldLayout.SIZE_WIDE) {
            drawWide(dc, w, h, bg);
        } else {
            drawSmall(dc, w, h, bg);
        }
    }

    const CV = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

    // Foreground that survives both the light and the dark data-field theme.
    hidden function fg(bg as Graphics.ColorType) as Graphics.ColorType {
        return bg == Graphics.COLOR_BLACK ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
    }

    // 3- and 4-field cells: the two numbers that decide whether the session is going well.
    hidden function drawSmall(dc as Dc, w as Number, h as Number,
            bg as Graphics.ColorType) as Void {
        var texts = [pctText(), flightText()] as Array<String>;
        var fonts = FieldLayout.fitRows(dc, w, h, ["100%", "99 · 88:88"] as Array<String>,
            [FieldLayout.NUM_FONTS, FieldLayout.TEXT_FONTS] as Array, false);
        var heights = FieldLayout.heightsOf(dc, fonts);
        drawRow(dc, w, h, heights, fonts, 0, texts[0], stateColor(bg));
        drawRow(dc, w, h, heights, fonts, 1, texts[1], fg(bg));
    }

    // 2-field cell: room for the turn line as well.
    hidden function drawWide(dc as Dc, w as Number, h as Number,
            bg as Graphics.ColorType) as Void {
        var widest = ["100%", "99 · 88:88", "TOUCH 100% · 99/99"] as Array<String>;
        var fonts = FieldLayout.fitRows(dc, w, h, widest,
            [FieldLayout.NUM_FONTS, FieldLayout.TEXT_FONTS,
             FieldLayout.TEXT_FONTS] as Array, false);
        var heights = FieldLayout.heightsOf(dc, fonts);
        drawRow(dc, w, h, heights, fonts, 0, pctText(), stateColor(bg));
        drawRow(dc, w, h, heights, fonts, 1, flightText(), fg(bg));
        drawRow(dc, w, h, heights, fonts, 2, turnLine(), outcomeColor(bg));
    }

    // 1-field page: everything, biggest first.
    hidden function drawFull(dc as Dc, w as Number, h as Number, bg as Graphics.ColorType,
            round as Boolean) as Void {
        var widest = ["88.8 km/h", "100%", "99 · 88:88", "TOUCH 100%",
            "99/99 · 99·99·99"] as Array<String>;
        var fonts = FieldLayout.fitRows(dc, w, h, widest,
            [FieldLayout.TEXT_FONTS, FieldLayout.NUM_FONTS, FieldLayout.TEXT_FONTS,
             FieldLayout.TEXT_FONTS, FieldLayout.TEXT_FONTS] as Array, round);
        var heights = FieldLayout.heightsOf(dc, fonts);
        drawRow(dc, w, h, heights, fonts, 0, speedText(), fg(bg));
        drawRow(dc, w, h, heights, fonts, 1, pctText(), stateColor(bg));
        drawRow(dc, w, h, heights, fonts, 2, flightText(), fg(bg));
        drawRow(dc, w, h, heights, fonts, 3, outcomeText(), outcomeColor(bg));
        drawRow(dc, w, h, heights, fonts, 4, tallyText(), fg(bg));
    }

    hidden function drawRow(dc as Dc, w as Number, h as Number, heights as Array<Number>,
            fonts as Array<Graphics.FontType>, row as Number, text as String,
            color as Graphics.ColorType) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, FieldLayout.stackY(h, heights, row), fonts[row], text, CV);
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
