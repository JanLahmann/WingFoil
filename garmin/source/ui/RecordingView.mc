import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// The on-water screens. Page 0 = Speed/Flight, page 1 = Session, page 2 = Records,
// page 3 = Clock. Button-cycled. Fonts are deliberately large: spray + chop make
// small text unreadable on the water. All vertical positions are stacked from
// dc.getFontHeight() so blocks can never overlap, on any fenix 8 variant.
class RecordingView extends WatchUi.View {
    var pageIndex as Number = 0;
    const PAGE_COUNT = 4;

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

    // Page 4: giant time of day (+ timer and battery)
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
