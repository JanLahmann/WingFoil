import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Timer;
import Toybox.WatchUi;

// Pre-session screen: GPS acquisition status, START to begin.
class StartView extends WatchUi.View {
    hidden var _timer as Timer.Timer?;

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), 1000, true);
    }

    function onHide() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    function onTick() as Void {
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        var app = getApp();
        var q = app.controller.engine.gpsQuality;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 80, Graphics.FONT_MEDIUM, "WingFoil", Graphics.TEXT_JUSTIFY_CENTER);

        // GPS quality: 4 dots, filled up to current quality
        var gpsReady = q >= Position.QUALITY_USABLE;
        for (var i = 0; i < 4; i++) {
            var x = cx - 45 + i * 30;
            if (i < q) {
                dc.setColor(gpsReady ? Graphics.COLOR_GREEN : Graphics.COLOR_YELLOW,
                    Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, cy - 20, 8);
            } else {
                dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.drawCircle(x, cy - 20, 8);
            }
        }
        dc.setColor(gpsReady ? Graphics.COLOR_GREEN : Graphics.COLOR_LT_GRAY,
            Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 5, Graphics.FONT_SMALL, gpsReady ? "GPS ready" : "GPS...",
            Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 55, Graphics.FONT_SMALL, "START to record",
            Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class StartDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        var app = getApp();
        if (app.controller.startSession()) {
            PageNav.reset();
            PageNav.show();
        }
        return true;
    }

    function onBack() as Boolean {
        System.exit();
    }
}
