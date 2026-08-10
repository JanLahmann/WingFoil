import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Turns-page metrics, file scope so the static width helpers (shared with the layout
// test) can reach them — class consts are instance-scoped in Monkey C.
const TURNS_SPLIT_GAP = 16;
const TURNS_WORD_GAP = 12;
const TURNS_TALLY_SEP = " · ";

// The on-water screens. Page 0 = Speed/Flight, page 1 = Session, page 2 = Records,
// page 3 = Turns, page 4 = Clock. Button-cycled. Fonts are deliberately large: spray + chop
// make small text unreadable on the water. All vertical positions are stacked from
// dc.getFontHeight() so blocks can never overlap, on any fenix 8 variant.
class RecordingView extends WatchUi.View {
    var pageIndex as Number = 0;
    const PAGE_COUNT = 5;

    function initialize() {
        View.initialize();
    }

    function nextPage(dir as Number) as Void {
        pageIndex = (pageIndex + dir + PAGE_COUNT) % PAGE_COUNT;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        var c = getApp().controller;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (pageIndex == 0) {
            drawSpeedPage(dc, c);
        } else if (pageIndex == 1) {
            drawSessionPage(dc, c);
        } else if (pageIndex == 2) {
            drawRecordsPage(dc, c);
        } else if (pageIndex == 3) {
            drawTurnsPage(dc, c);
        } else {
            drawClockPage(dc, c);
        }
        if (c.state == SessionController.STATE_PAUSED) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(dc.getWidth() / 2, 18, Graphics.FONT_SMALL, "PAUSED",
                Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    const CV = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

    // Page 1: giant speed, foil-state ring, current flight timer, HR
    hidden function drawSpeedPage(dc as Dc, c as SessionController) as Void {
        var e = c.engine;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var hN = dc.getFontHeight(Graphics.FONT_NUMBER_THAI_HOT);
        var hS = dc.getFontHeight(Graphics.FONT_SMALL);
        var hM = dc.getFontHeight(Graphics.FONT_MEDIUM);

        // state ring: green flying, dark gray off-foil
        var flying = e.detector.state == FlightDetector.STATE_ON;
        dc.setPenWidth(10);
        dc.setColor(flying ? Graphics.COLOR_GREEN : Graphics.COLOR_DK_GRAY,
            Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, cx - 7);
        dc.setPenWidth(1);

        // speed number + unit + flight timer, stacked around the vertical center
        var ySpeed = cy - (hS + hM) / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, ySpeed, Graphics.FONT_NUMBER_THAI_HOT,
            AppSettings.speedToDisplay(e.speedMps).format("%.1f"), CV);
        var yUnit = ySpeed + (hN + hS) / 2;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, yUnit, Graphics.FONT_SMALL, AppSettings.speedLabel(), CV);
        var yTimer = yUnit + (hS + hM) / 2;
        if (flying) {
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, yTimer, Graphics.FONT_MEDIUM,
                fmtTime(e.detector.currentFlightS), CV);
        } else {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, yTimer, Graphics.FONT_MEDIUM, "--:--", CV);
        }

        var hr = e.hr;
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, yTimer + (hM + hS) / 2, Graphics.FONT_SMALL,
            hr != null ? hr.toString() + " bpm" : "-- bpm", CV);
    }

    // Page 2: foil %, then flights / foil time / longest / dist
    hidden function drawSessionPage(dc as Dc, c as SessionController) as Void {
        var e = c.engine;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var hHot = dc.getFontHeight(Graphics.FONT_NUMBER_HOT);
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var hM = dc.getFontHeight(Graphics.FONT_MEDIUM);
        var rowH = hM;

        // biased 8 px up: the bottom row sits where the circle narrows
        var y = cy - 8 - (hHot + hT + 4 * rowH) / 2 + hHot / 2;
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_NUMBER_HOT,
            e.foilPct().format("%.0f") + "%", CV);
        y += (hHot + hT) / 2;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_XTINY, "on foil", CV);

        // widest rows first: the circle narrows toward the bottom
        y += (hT + rowH) / 2;
        drawRowF(dc, cx, y, "foil", fmtTime(e.detector.foilTimeS), Graphics.FONT_SMALL);
        y += rowH;
        drawRowF(dc, cx, y, "longest", fmtTime(e.detector.longestS), Graphics.FONT_SMALL);
        y += rowH;
        drawRowF(dc, cx, y, "dist", (e.distM / 1000.0).format("%.1f") + " km",
            Graphics.FONT_SMALL);
        y += rowH;
        drawRowF(dc, cx, y, "flights", e.detector.flightCount.toString(), Graphics.FONT_SMALL);
    }

    // Page 3: live speed records, one giant number per block
    hidden function drawRecordsPage(dc as Dc, c as SessionController) as Void {
        var r = c.engine.records;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var hHot = dc.getFontHeight(Graphics.FONT_NUMBER_HOT);
        var hS = dc.getFontHeight(Graphics.FONT_SMALL);
        var unit = " " + AppSettings.speedLabel();

        // biased 16 px down: the top label otherwise clips the circle edge;
        // unit only on the lower label to keep the top one narrow
        var y = cy + 16 - (2 * hHot + 2 * hS) / 2 + hS / 2;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_SMALL, "best 2s", CV);
        y += (hS + hHot) / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_NUMBER_HOT,
            AppSettings.speedToDisplay(r.best2sMps).format("%.1f"), CV);
        y += (hHot + hS) / 2;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_SMALL, "best 10s" + unit, CV);
        y += (hS + hHot) / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_NUMBER_HOT,
            AppSettings.speedToDisplay(r.best10sMps).format("%.1f"), CV);
    }

    // Page 4: turns — big count (tacks/jibes once a wind axis is set, total otherwise),
    // the last turn's outcome as a colour-coded word, its score, and the outcome tally.
    hidden function drawTurnsPage(dc as Dc, c as SessionController) as Void {
        var t = c.engine.turns;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var hHot = dc.getFontHeight(Graphics.FONT_NUMBER_HOT);
        var hL = dc.getFontHeight(Graphics.FONT_LARGE);
        var hS = dc.getFontHeight(Graphics.FONT_SMALL);
        var windSet = AppSettings.windDirection >= 0;

        var y = turnsRowY(cy, hT, hHot, hL, hS, 0);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_XTINY,
            windSet ? "tack / jibe  " + AppSettings.windLabel() : "turns", CV);

        // widest block on the vertical centre line, where the round display is widest
        y = turnsRowY(cy, hT, hHot, hL, hS, 1);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (windSet) {
            drawSplitCount(dc, cx, y, t.tackCount.toString(), t.jibeCount.toString());
        } else {
            dc.drawText(cx, y, Graphics.FONT_NUMBER_HOT, t.turnCount.toString(), CV);
        }

        // last outcome: the word in its colour, then the score, centred as one phrase.
        // Anchoring each half at the centre line instead puts "TOUCH 100%" 412 px wide on
        // a 384 px chord at that depth — the round glass eats both ends.
        y = turnsRowY(cy, hT, hHot, hL, hS, 2);
        var word = "--";
        var col = Graphics.COLOR_DK_GRAY;
        if (t.lastOutcome == TurnDetector.OUTCOME_FLEW) {
            word = "FLEW";
            col = Graphics.COLOR_GREEN;
        } else if (t.lastOutcome == TurnDetector.OUTCOME_TOUCHDOWN) {
            word = "TOUCH";
            col = Graphics.COLOR_ORANGE;
        } else if (t.lastOutcome == TurnDetector.OUTCOME_FELL) {
            word = "SWIM";
            col = Graphics.COLOR_RED;
        }
        var score = t.lastOutcome == TurnDetector.OUTCOME_NONE
            ? "--" : t.lastScorePct.toString() + "%";
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var x = cx - outcomeWidth(dc, word, score) / 2;
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_LARGE, word, LV);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + dc.getTextWidthInPixels(word, Graphics.FONT_LARGE) + TURNS_WORD_GAP,
            y, Graphics.FONT_LARGE, score, LV);

        // tally: flew · touchdown · swim, in the same colours as the words above
        drawTally(dc, cx, turnsRowY(cy, hT, hHot, hL, hS, 3), t);
    }

    // Row centre for the Turns page: 0 = header, 1 = counts, 2 = outcome, 3 = tally.
    // Stacked from font heights only, so the rows can never overlap on any variant.
    // Shared with the layout test, which asserts every row still clears the circle.
    static function turnsRowY(cy as Number, hT as Number, hHot as Number, hL as Number,
            hS as Number, row as Number) as Number {
        var y = cy - (hT + hHot + hL + hS) / 2 + hT / 2;
        if (row == 0) {
            return y;
        }
        y += (hT + hHot) / 2;
        if (row == 1) {
            return y;
        }
        y += (hHot + hL) / 2;
        return row == 2 ? y : y + (hL + hS) / 2;
    }

    // Total width of the "<word> <score>" block.
    static function outcomeWidth(dc as Dc, word as String, score as String) as Number {
        return dc.getTextWidthInPixels(word, Graphics.FONT_LARGE) + TURNS_WORD_GAP
            + dc.getTextWidthInPixels(score, Graphics.FONT_LARGE);
    }

    // Total width of the "<n> / <n>" block. Shared with the layout test, which asserts the
    // block still fits the circle at its row.
    static function splitCountWidth(dc as Dc, left as String, right as String) as Number {
        return dc.getTextWidthInPixels(left, Graphics.FONT_NUMBER_HOT)
            + dc.getTextWidthInPixels(right, Graphics.FONT_NUMBER_HOT)
            + dc.getTextWidthInPixels("/", Graphics.FONT_MEDIUM) + 2 * TURNS_SPLIT_GAP;
    }

    static function tallyWidth(dc as Dc, a as String, b as String, c as String) as Number {
        var f = Graphics.FONT_SMALL;
        return dc.getTextWidthInPixels(a, f) + dc.getTextWidthInPixels(b, f)
            + dc.getTextWidthInPixels(c, f) + 2 * dc.getTextWidthInPixels(TURNS_TALLY_SEP, f);
    }

    // Two giant counts with a separator, centred as one block.
    hidden function drawSplitCount(dc as Dc, cx as Number, y as Number, left as String,
            right as String) as Void {
        var f = Graphics.FONT_NUMBER_HOT;
        var wl = dc.getTextWidthInPixels(left, f);
        var ws = dc.getTextWidthInPixels("/", Graphics.FONT_MEDIUM);
        var x = cx - splitCountWidth(dc, left, right) / 2;
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.drawText(x, y, f, left, LV);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + wl + TURNS_SPLIT_GAP, y, Graphics.FONT_MEDIUM, "/", LV);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + wl + ws + 2 * TURNS_SPLIT_GAP, y, f, right, LV);
    }

    // "flew · touch · swim" counts, colour-coded, centred as one block.
    hidden function drawTally(dc as Dc, cx as Number, y as Number,
            t as TurnDetector) as Void {
        var f = Graphics.FONT_SMALL;
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var a = t.flewCount.toString();
        var b = t.touchdownCount.toString();
        var s = t.fellCount.toString();
        var wSep = dc.getTextWidthInPixels(TURNS_TALLY_SEP, f);
        var wa = dc.getTextWidthInPixels(a, f);
        var wb = dc.getTextWidthInPixels(b, f);
        var x = cx - tallyWidth(dc, a, b, s) / 2;
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, f, a, LV);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + wa, y, f, TURNS_TALLY_SEP, LV);
        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + wa + wSep, y, f, b, LV);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + wa + wSep + wb, y, f, TURNS_TALLY_SEP, LV);
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + wa + wb + 2 * wSep, y, f, s, LV);
    }

    // Page 5: giant time of day (+ timer and battery)
    hidden function drawClockPage(dc as Dc, c as SessionController) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var hN = dc.getFontHeight(Graphics.FONT_NUMBER_THAI_HOT);
        var hM = dc.getFontHeight(Graphics.FONT_MEDIUM);
        var rowH = hM + 4;
        var ct = System.getClockTime();
        var hour = ct.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }

        var y = cy - (hN + 2 * rowH) / 2 + hN / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_NUMBER_THAI_HOT,
            hour.format("%d") + ":" + ct.min.format("%02d"), CV);

        y += (hN + rowH) / 2;
        drawRow(dc, cx, y, "timer", fmtTime(c.engine.timerS));
        y += rowH;
        drawRow(dc, cx, y, "batt",
            System.getSystemStats().battery.format("%.0f") + "%");
    }

    hidden function drawRow(dc as Dc, cx as Number, y as Number, label as String,
            value as String) as Void {
        drawRowF(dc, cx, y, label, value, Graphics.FONT_MEDIUM);
    }

    hidden function drawRowF(dc as Dc, cx as Number, y as Number, label as String,
            value as String, labelFont as Graphics.FontType) as Void {
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 10, y, labelFont, label,
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 10, y, Graphics.FONT_MEDIUM, value,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    static function fmtTime(seconds as Float) as String {
        var s = seconds.toNumber();
        return (s / 60).format("%d") + ":" + (s % 60).format("%02d");
    }
}
