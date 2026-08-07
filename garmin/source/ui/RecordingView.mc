import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// The on-water screens. Page 0 = Speed/Flight, page 1 = Session, page 2 = Records,
// page 3 = Clock. Button-cycled. Fonts are deliberately large: spray + chop make
// small text unreadable on the water.
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

    // Page 1: giant speed, foil-state ring, current flight timer, HR
    hidden function drawSpeedPage(dc as Dc, c as SessionController) as Void {
        var e = c.engine;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;

        // state ring: green flying, dark gray off-foil
        var flying = e.detector.state == FlightDetector.STATE_ON;
        dc.setPenWidth(10);
        dc.setColor(flying ? Graphics.COLOR_GREEN : Graphics.COLOR_DK_GRAY,
            Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, cx - 7);
        dc.setPenWidth(1);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 85, Graphics.FONT_NUMBER_THAI_HOT,
            AppSettings.speedToDisplay(e.speedMps).format("%.1f"),
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 22, Graphics.FONT_SMALL, AppSettings.speedLabel(),
            Graphics.TEXT_JUSTIFY_CENTER);

        // current flight timer (only while flying)
        if (flying) {
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 55, Graphics.FONT_MEDIUM,
                fmtTime(e.detector.currentFlightS), Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 55, Graphics.FONT_MEDIUM, "--:--",
                Graphics.TEXT_JUSTIFY_CENTER);
        }

        var hr = e.hr;
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, dc.getHeight() - 55, Graphics.FONT_SMALL,
            hr != null ? hr.toString() + " bpm" : "-- bpm", Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Page 2: foil %, flights, foil time, longest, distance, elapsed
    hidden function drawSessionPage(dc as Dc, c as SessionController) as Void {
        var e = c.engine;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;

        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 100, Graphics.FONT_NUMBER_HOT,
            e.foilPct().format("%.0f") + "%", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 35, Graphics.FONT_XTINY, "on foil", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        drawRow(dc, cx, cy - 10, "flights", e.detector.flightCount.toString());
        drawRow(dc, cx, cy + 28, "foil", fmtTime(e.detector.foilTimeS));
        drawRow(dc, cx, cy + 66, "longest", fmtTime(e.detector.longestS));
        drawRow(dc, cx, cy + 104, "dist",
            (e.distM / 1000.0).format("%.1f") + " km");
    }

    // Page 3: live speed records, one giant number per row
    hidden function drawRecordsPage(dc as Dc, c as SessionController) as Void {
        var r = c.engine.records;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 130, Graphics.FONT_SMALL, "best 2s", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 100, Graphics.FONT_NUMBER_HOT,
            AppSettings.speedToDisplay(r.best2sMps).format("%.1f"),
            Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 10, Graphics.FONT_SMALL, "best 10s", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 40, Graphics.FONT_NUMBER_HOT,
            AppSettings.speedToDisplay(r.best10sMps).format("%.1f"),
            Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, dc.getHeight() - 40, Graphics.FONT_SMALL, AppSettings.speedLabel(),
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Page 4: giant time of day (+ elapsed and battery, small)
    hidden function drawClockPage(dc as Dc, c as SessionController) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var ct = System.getClockTime();
        var hour = ct.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 70, Graphics.FONT_NUMBER_THAI_HOT,
            hour.format("%d") + ":" + ct.min.format("%02d"),
            Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        drawRow(dc, cx, cy + 60, "timer", fmtTime(c.engine.timerS));
        drawRow(dc, cx, cy + 98, "batt",
            System.getSystemStats().battery.format("%.0f") + "%");
    }

    hidden function drawRow(dc as Dc, cx as Number, y as Number, label as String,
            value as String) as Void {
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 10, y, Graphics.FONT_MEDIUM, label, Graphics.TEXT_JUSTIFY_RIGHT);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 10, y, Graphics.FONT_MEDIUM, value, Graphics.TEXT_JUSTIFY_LEFT);
    }

    static function fmtTime(seconds as Float) as String {
        var s = seconds.toNumber();
        return (s / 60).format("%d") + ":" + (s % 60).format("%02d");
    }
}
