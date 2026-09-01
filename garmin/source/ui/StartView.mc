import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Timer;
import Toybox.WatchUi;

// File scope so the static layout helpers (shared with the layout test) can reach them —
// class consts are instance-scoped in Monkey C.
const START_TITLE = "CleanJibe";
const START_HINT = "START to record";
// Nominal fonts as TEXT_FONTS indices: FONT_MEDIUM for the title and — since 0.9.2 — for the
// GPS STATE row, FONT_SMALL for the wind and hint rows. fitFont() shrinks any of them when the
// chord at that depth is narrower, which is what still fits the long wind reminder on a 240 px
// glass.
//
// The state row was FONT_SMALL, one rung under the app's own name, on a screen whose only
// question is "can I press start yet?" — the answer to it was smaller than the label on the
// question. It is now the title's equal, and it is paid for out of the row GAPS (a third of a
// body line rather than a half): the block still leaves 39 % of a 454 px glass empty, and the
// wind row keeps FONT_SMALL on the narrowest glass in the manifest, which is the row that
// measures closest to its chord.
const START_TITLE_FONT = 1;
const START_STATE_FONT = 1;
const START_BODY_FONT = 2;

// The wind row. Without a wind axis the turn classifier calls every sweep a generic turn, so
// the Turns page loses the tack/jibe split AND the port/starboard entry split, and the FIT
// omits both counts (docs/fit-schema.md) — an omission the rider can only fix BEFORE he is
// on the water, which is why the reminder lives on this screen and says HOW.
//
// "hold MENU" is the literal binding: StartDelegate.onMenu() pushes the same WindMenu the
// session menu opens, and MENU on every fenix in the manifest is a long press of the UP
// button. Naming a button the rider cannot find would be worse than no reminder at all.
const START_WIND_UNSET = "set wind - hold MENU";
const START_WIND_PREFIX = "wind ";

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
        // The mark is decoration on a page nobody is looking at once the session starts, and
        // the session is the long-running thing. Give the bytes back with the timer.
        Brand.release();
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
    //
    // The four GPS-quality dots are GONE. They cost a whole row to say what the word beside
    // them already said — the row's only content was "how many are unfilled", which the state
    // word now carries in four steps of its own (searching / weak / ready / good) plus its
    // colour. The row they freed went to the wind reminder, which is information the screen
    // did not have at all.

    // Ink centre of row `row` — 0 title, 1 GPS state, 2 wind, 3 hint — for a stack centred
    // on `cy`. The gap between rows is a third of a body line, so the whole page breathes with
    // the font the device actually has. `hState` is its own band since 0.9.2: the row that
    // answers the screen's only question is a rung bigger than the two under it.
    static function rowY(cy as Number, hTitle as Number, hState as Number, hBody as Number,
            row as Number) as Number {
        var gap = hBody / 3;
        var y = cy - (hTitle + hState + 2 * hBody + 3 * gap) / 2;  // top edge of the stack
        if (row <= 0) { return y + hTitle / 2; }
        y += hTitle + gap + hState / 2;
        if (row == 1) { return y; }
        y += hState / 2 + gap + hBody / 2;
        return row == 2 ? y : y + hBody + gap;
    }

    // Ink centre of the brand mark, which rides in the air ABOVE the stack rather than inside
    // it (0.9.5). That is a deliberate choice and not laziness about the arithmetic: the stack
    // is required to leave a quarter of the glass empty — "this is a four-line page, not a
    // data screen", asserted — and on the narrowest glass in the manifest it is already within
    // 27 px of that limit, so a mark given a row of its own would have had to be 18 px tall to
    // be legal and would have pushed the page past the rule it exists under at any size worth
    // drawing. The air above the title is 44 px on a 240 px fenix 7S and 88 px on a 454 px
    // fenix 8, it was empty, and it is where a logo belongs anyway.
    //
    // It is hung off the TITLE, one stack gap above it, so the mark and the wordmark read as
    // one lockup and the gap between them is smaller than the gap to the GPS row — the same
    // hBody/3 the rows use, so this too breathes with the font the device actually has.
    static function markY(cy as Number, hTitle as Number, hState as Number, hBody as Number,
            markH as Number) as Number {
        return rowY(cy, hTitle, hState, hBody, 0) - hTitle / 2 - hBody / 3 - markH / 2;
    }

    // The GPS row: one line whose WORD and COLOUR together carry what the four dots used to.
    // Position.QUALITY_* is an ordered scale, so the four rungs map one-to-one.
    static function gpsText(q as Number) as String {
        if (q >= Position.QUALITY_GOOD) { return "GPS good"; }
        if (q >= Position.QUALITY_USABLE) { return "GPS ready"; }
        if (q >= Position.QUALITY_POOR) { return "GPS weak"; }
        return "GPS ...";
    }

    static function gpsColor(q as Number) as Number {
        if (q >= Position.QUALITY_USABLE) { return Graphics.COLOR_GREEN; }
        // White, not the dim ink: "GPS ..." is the state the rider is WAITING on, and a grey
        // word on a black screen at 30 % brightness is a word he cannot read (0.9.2).
        return q >= Position.QUALITY_POOR ? Graphics.COLOR_YELLOW : Graphics.COLOR_WHITE;
    }

    // The wind row: the axis when there is one, and how to set one when there is not.
    //
    // An axis the WATCH estimated reads "wind ~200° SSW" — the tilde is the whole difference
    // between a number the rider gave and one the app inferred, and it is carried once, on the
    // bearing, rather than twice (`windMark` rather than `windLabel`, which folds it into the
    // compass point for the call sites that print only that).
    static function windText() as String {
        var deg = AppSettings.cfg.windDirection;
        return deg < 0
            ? START_WIND_UNSET
            : START_WIND_PREFIX + AppSettings.cfg.windMark() + deg.toString() + "° "
                + AppSettings.cfg.compassLabel();
    }

    function onUpdate(dc as Dc) as Void {
        var app = getApp();
        var q = app.controller.engine.gpsQuality;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = RecordingView.fitRadius(dc, false, false);

        var hTitle = dc.getFontHeight(TEXT_FONTS[START_TITLE_FONT]);
        var hState = dc.getFontHeight(TEXT_FONTS[START_STATE_FONT]);
        var hBody = dc.getFontHeight(TEXT_FONTS[START_BODY_FONT]);

        // The mark above the wordmark. Skipped rather than clipped when the air will not hold
        // it, exactly as a row drops content rather than shrinking past the floor.
        var yMark = markY(cy, hTitle, hState, hBody, Brand.h());
        if (Brand.fits(dc, radius, 0, yMark - cy)) {
            Brand.draw(dc, cx, yMark);
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        drawRow(dc, cx, cy, radius, rowY(cy, hTitle, hState, hBody, 0), START_TITLE_FONT,
            START_TITLE);

        // GPS quality: one line, four rungs, colour and word saying the same thing twice.
        dc.setColor(gpsColor(q), Graphics.COLOR_TRANSPARENT);
        drawRow(dc, cx, cy, radius, rowY(cy, hTitle, hState, hBody, 1), START_STATE_FONT,
            gpsText(q));

        // The wind axis, or how to set one. Amber when unset: it is not an error — the app
        // records perfectly well without it — but it is the one thing that cannot be fixed
        // afterwards, so it should catch the eye before START does.
        var wind = windText();
        dc.setColor(AppSettings.cfg.windDirection < 0
            ? Graphics.COLOR_YELLOW : Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        drawRow(dc, cx, cy, radius, rowY(cy, hTitle, hState, hBody, 2), START_BODY_FONT, wind);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        drawRow(dc, cx, cy, radius, rowY(cy, hTitle, hState, hBody, 3), START_BODY_FONT,
            START_HINT);
    }

    // One centred row, at the largest font from `from` that the chord at its depth holds.
    hidden function drawRow(dc as Dc, cx as Number, cy as Number, radius as Number,
            y as Number, from as Number, text as String) as Void {
        dc.drawText(cx, y, RecordingView.fitFont(dc, TEXT_FONTS, from, text,
            RecordingView.rowBudget(radius, y - cy,
                RecordingView.inkH(dc, TEXT_FONTS[from]))),
            text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
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

    // MENU (a long press of UP on every fenix in the manifest) opens the wind axis — the
    // same WindMenu the session menu opens, so there is one place the axis is set and one
    // string on the start screen naming the button that opens it. Before this the axis could
    // only be set from inside a running session, i.e. after the first turns had already been
    // classified as generic ones.
    //
    // ONE pop, not the session menu's two: StartView is the bottom of the stack here, and
    // popping past it would exit the app on a wind pick.
    function onMenu() as Boolean {
        WatchUi.pushView(WindMenu.build(), new WindMenuDelegate(1), WatchUi.SLIDE_UP);
        return true;
    }

    function onBack() as Boolean {
        System.exit();
    }
}
