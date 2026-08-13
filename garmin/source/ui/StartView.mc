import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Timer;
import Toybox.WatchUi;

// File scope so the static layout helpers (shared with the layout test) can reach them —
// class consts are instance-scoped in Monkey C.
const START_TITLE = "WingFoil";
const START_HINT = "START to record";
// Nominal fonts as TEXT_FONTS indices: FONT_MEDIUM for the title, FONT_SMALL for the two
// text rows. fitFont() shrinks from there when the chord at that depth is narrower.
const START_TITLE_FONT = 1;
const START_BODY_FONT = 2;

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

    // ---- Layout ----
    // The four rows used to sit at fixed offsets from the centre (-80 / -20 / +5 / +55 px,
    // 30 px dot pitch, 8 px dots). Those numbers were authored on a 454 px AMOLED, where they
    // read tight, and they are simply wrong on the fenix 7 family: a 240 px glass renders the
    // same block 1.9x too tall, so the title clips off the top and the hint off the bottom.
    // The rows are now a stack centred on the screen and measured in the device's own font
    // metrics, exactly like the recording pages.

    // Radius of one GPS-quality dot: 8 px on a 454 px glass, never below 3 px.
    static function dotRadius(dc as Dc) as Number {
        var r = dc.getWidth() / 56;
        return r < 3 ? 3 : r;
    }

    // Centre-to-centre pitch of the dot row, held at the authored 30 px : 8 px ratio.
    static function dotStep(r as Number) as Number {
        return r * 15 / 4;
    }

    // Ink centre of row `row` — 0 title, 1 dot row, 2 GPS state, 3 hint — for a stack
    // centred on `cy`. The gap between rows is half a body line, so the whole page breathes
    // with the font the device actually has.
    static function rowY(cy as Number, hTitle as Number, hDots as Number, hBody as Number,
            row as Number) as Number {
        var gap = hBody / 2;
        var y = cy - (hTitle + hDots + 2 * hBody + 3 * gap) / 2;   // top edge of the stack
        if (row <= 0) { return y + hTitle / 2; }
        y += hTitle + gap;
        if (row == 1) { return y + hDots / 2; }
        y += hDots + gap;
        if (row == 2) { return y + hBody / 2; }
        y += hBody + gap;
        return y + hBody / 2;
    }

    function onUpdate(dc as Dc) as Void {
        var app = getApp();
        var q = app.controller.engine.gpsQuality;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = RecordingView.fitRadius(dc);
        var CV = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        var r = dotRadius(dc);
        var titleFont = TEXT_FONTS[START_TITLE_FONT];
        var bodyFont = TEXT_FONTS[START_BODY_FONT];
        var hTitle = dc.getFontHeight(titleFont);
        var hBody = dc.getFontHeight(bodyFont);
        var hDots = 2 * r;
        var yTitle = rowY(cy, hTitle, hDots, hBody, 0);
        var yDots = rowY(cy, hTitle, hDots, hBody, 1);
        var yState = rowY(cy, hTitle, hDots, hBody, 2);
        var yHint = rowY(cy, hTitle, hDots, hBody, 3);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, yTitle,
            RecordingView.fitFont(dc, TEXT_FONTS, START_TITLE_FONT, START_TITLE,
                RecordingView.rowBudget(radius, yTitle - cy,
                    RecordingView.inkH(dc, titleFont))),
            START_TITLE, CV);

        // GPS quality: 4 dots, filled up to current quality
        var gpsReady = q >= Position.QUALITY_USABLE;
        var step = dotStep(r);
        for (var i = 0; i < 4; i++) {
            var x = cx - (3 * step) / 2 + i * step;
            if (i < q) {
                dc.setColor(gpsReady ? Graphics.COLOR_GREEN : Graphics.COLOR_YELLOW,
                    Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, yDots, r);
            } else {
                dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.drawCircle(x, yDots, r);
            }
        }

        var state = gpsReady ? "GPS ready" : "GPS...";
        dc.setColor(gpsReady ? Graphics.COLOR_GREEN : Graphics.COLOR_LT_GRAY,
            Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, yState,
            RecordingView.fitFont(dc, TEXT_FONTS, START_BODY_FONT, state,
                RecordingView.rowBudget(radius, yState - cy,
                    RecordingView.inkH(dc, bodyFont))),
            state, CV);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, yHint,
            RecordingView.fitFont(dc, TEXT_FONTS, START_BODY_FONT, START_HINT,
                RecordingView.rowBudget(radius, yHint - cy,
                    RecordingView.inkH(dc, bodyFont))),
            START_HINT, CV);
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
