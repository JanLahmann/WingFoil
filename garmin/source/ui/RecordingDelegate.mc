import Toybox.Lang;
import Toybox.WatchUi;

// Button-first input while recording. Stray wet-touch taps are swallowed; page swipes are
// harmless and left enabled. Destructive actions live behind BACK -> menu.
class RecordingDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    hidden function view() as RecordingView? {
        var v = WatchUi.getCurrentView()[0];
        return v instanceof RecordingView ? v : null;
    }

    function onSelect() as Boolean {
        getApp().controller.togglePause();
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() as Boolean {
        var menu = new WatchUi.Menu2({:title => "Session"});
        menu.addItem(new WatchUi.MenuItem("Resume", null, :resume, null));
        menu.addItem(new WatchUi.MenuItem("Wind", AppSettings.windLabel(), :wind, null));
        menu.addItem(new WatchUi.MenuItem("Save", null, :save, null));
        menu.addItem(new WatchUi.MenuItem("Discard", null, :discard, null));
        WatchUi.pushView(menu, new StopMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }

    function onNextPage() as Boolean {
        var v = view();
        if (v != null) {
            v.nextPage(1);
        }
        return true;
    }

    function onPreviousPage() as Boolean {
        var v = view();
        if (v != null) {
            v.nextPage(-1);
        }
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        return true;   // swallow wet-touch taps
    }
}

class StopMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var c = getApp().controller;
        var id = item.getId();
        if (id == :save) {
            c.finishSave();
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            WatchUi.switchToView(new SummaryView(), new SummaryDelegate(),
                WatchUi.SLIDE_IMMEDIATE);
        } else if (id == :discard) {
            c.finishDiscard();
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            WatchUi.switchToView(new StartView(), new StartDelegate(),
                WatchUi.SLIDE_IMMEDIATE);
        } else if (id == :wind) {
            WatchUi.pushView(WindMenu.build(), new WindMenuDelegate(), WatchUi.SLIDE_UP);
        } else {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
    }
}

// Wind axis entry on the water: 16 compass points, gloves-friendly. The value the rider
// picks is the direction the wind blows FROM; it splits future turns into tacks and jibes
// and is written to session field 39 (docs/fit-schema.md). Turns already detected keep the
// classification they were given — the watch never re-runs the pass.
module WindMenu {
    function build() as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({:title => "Wind from"});
        menu.addItem(new WatchUi.MenuItem("Unset", null, -1, null));
        for (var i = 0; i < 16; i++) {
            var deg = i * 45 / 2;   // 22.5 deg steps, integer arithmetic
            menu.addItem(new WatchUi.MenuItem(AppSettings.COMPASS[i],
                deg.toString() + "°", deg, null));
        }
        return menu;
    }
}

class WindMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        AppSettings.storeWindDirection(id instanceof Lang.Number ? id as Number : -1);
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);   // wind menu
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);   // session menu -> back on the water
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
    }
}
