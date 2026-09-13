import Toybox.Application.Storage;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// THE SPLASH (device app 0.9.10, Jan 13 Sep 2026: "adding our logo more visibly in the Garmin
// app as well … do both"). A page that is nothing but the mark and the wordmark, drawn by us on
// the app's own black — no native view, nothing that can die — for a second and a half, then
// the start page as before.
//
// SHOWN ONCE PER VERSION, not on every launch. The start page is where a rider goes to press
// START, often with cold hands; a logo that costs him a second every single time is a logo he
// learns to resent. The first launch after an install or an update is where the brand earns
// that second, and `Storage` remembers the version it was shown for. Any key skips it.
module BrandSplash {
    const HOLD_MS = 1500;
    const STORE_SEEN = "brandSeen";

    // Whether this launch gets the page: the stored version is not this one.
    function due() as Boolean {
        var seen = Storage.getValue(STORE_SEEN);
        return !(seen instanceof Lang.String) || !(seen as String).equals(FitSchema.APP_VERSION);
    }

    function markSeen() as Void {
        Storage.setValue(STORE_SEEN, FitSchema.APP_VERSION);
    }

    // Ink centre of the hero and of the wordmark under it, for a glass of half-height `cy`:
    // the lockup — hero, a gap of a third of the word's height, the word — sits centred.
    function heroY(cy as Number, heroH as Number, wordH as Number) as Number {
        return cy - (heroH + wordH / 3 + wordH) / 2 + heroH / 2;
    }

    function wordY(cy as Number, heroH as Number, wordH as Number) as Number {
        return heroY(cy, heroH, wordH) + heroH / 2 + wordH / 3 + wordH / 2;
    }
}

class BrandSplashView extends WatchUi.View {
    const CV = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

    hidden var _timer as Timer.Timer?;

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        BrandSplash.markSeen();
        _timer = new Timer.Timer();
        _timer.start(method(:onDone), BrandSplash.HOLD_MS, false);
    }

    function onHide() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
        Brand.releaseHero();
    }

    function onDone() as Void {
        BrandSplashDelegate.leave();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var heroH = Brand.heroH();
        var wordH = dc.getFontHeight(Graphics.FONT_LARGE);
        Brand.drawHero(dc, cx, BrandSplash.heroY(cy, heroH, wordH));
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, BrandSplash.wordY(cy, heroH, wordH), Graphics.FONT_LARGE, START_TITLE,
            CV);
    }
}

// Any key leaves early — the page is a courtesy, not a gate.
class BrandSplashDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    static function leave() as Void {
        WatchUi.switchToView(new StartView(), new StartDelegate(), WatchUi.SLIDE_IMMEDIATE);
    }

    function onSelect() as Boolean {
        leave();
        return true;
    }

    function onBack() as Boolean {
        leave();
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        leave();
        return true;
    }
}
