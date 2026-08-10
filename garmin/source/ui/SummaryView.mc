import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Post-save summary (CIQ sessions get no native one). Engine state survives the save.
class SummaryView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        var e = getApp().controller.engine;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var cx = dc.getWidth() / 2;
        var y = 40;

        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_MEDIUM, "Saved!", Graphics.TEXT_JUSTIFY_CENTER);
        y += 45;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        drawRow(dc, cx, y, "foil", e.foilPct().format("%.0f") + "%");
        y += 32;
        drawRow(dc, cx, y, "flights", e.detector.flightCount.toString());
        y += 32;
        drawRow(dc, cx, y, "longest", RecordingView.fmtTime(e.detector.longestS));
        y += 32;
        drawRow(dc, cx, y, "best 2s",
            AppSettings.speedToDisplay(e.records.best2sMps).format("%.1f")
            + " " + AppSettings.speedLabel());
        y += 32;
        drawRow(dc, cx, y, "dist", (e.distM / 1000.0).format("%.1f") + " km");

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, dc.getHeight() - 50, Graphics.FONT_XTINY, "press to exit",
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    hidden function drawRow(dc as Dc, cx as Number, y as Number, label as String,
            value as String) as Void {
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 10, y, Graphics.FONT_SMALL, label, Graphics.TEXT_JUSTIFY_RIGHT);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 10, y, Graphics.FONT_SMALL, value, Graphics.TEXT_JUSTIFY_LEFT);
    }
}

class SummaryDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        System.exit();
    }

    function onBack() as Boolean {
        System.exit();
    }
}
