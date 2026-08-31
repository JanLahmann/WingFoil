import Toybox.Lang;
import Toybox.WatchUi;

// Where in the page cycle we are. A module rather than view state because the index has to
// outlive any view swap — the menu, the summary and a settings reload all reach for it.
//
// IT USED TO BE MUCH MORE THAN THIS. The map page was `WatchUi.MapTrackView`, the firmware's
// own View, which cannot be painted inside our onUpdate — so paging onto it swapped views, and
// this module carried the whole push/pop state machine that went with it (`mapShown`,
// `_pushMap`, `dropMap`, `onPauseToggled`, and a `nextIndex` that skipped the map while paused
// because a native view can show no PAUSED banner). 0.9.0 switched to it and the watch threw a
// Type Error; 0.9.1 pushed it, the documented way, and the fenix 8 killed the app anyway with
// nothing in CIQ_LOG. 0.9.2 draws the trail itself (TrackDraw), so LAYOUT_MAP is an ordinary
// layout, paging is an index and a repaint, and every one of those special cases is gone —
// including the paused skip, since the page now carries the banner like any other.
module PageNav {
    var index as Number = 0;

    function reset() as Void {
        index = 0;
    }

    // Put the recording UI on screen. One view, whatever the page.
    function show() as Void {
        WatchUi.switchToView(new RecordingView(), new RecordingDelegate(),
            WatchUi.SLIDE_IMMEDIATE);
    }

    // Step `dir` pages and repaint. Every layout is drawn by RecordingView, so there is
    // nothing else to do.
    function step(dir as Number) as Void {
        index = PageModel.wrap(index + dir);
        WatchUi.requestUpdate();
    }
}

// Button-first input while recording. Stray wet-touch taps are swallowed; page swipes are
// harmless and left enabled. Destructive actions live behind BACK -> menu.
// Paging lives in PageNav, not in the view.
class RecordingDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        getApp().controller.togglePause();   // manual pause also cancels auto-pause ownership
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
        PageNav.step(1);
        return true;
    }

    function onPreviousPage() as Boolean {
        PageNav.step(-1);
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
            // The summary's page LIST depends on what the session produced (no turns, no
            // turns page), so it is built once here, after the save, from the engine state
            // that finishSave deliberately leaves intact.
            SummaryNav.build(c);
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            WatchUi.switchToView(new SummaryView(), new SummaryDelegate(),
                WatchUi.SLIDE_IMMEDIATE);
        } else if (id == :discard) {
            c.finishDiscard();
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            WatchUi.switchToView(new StartView(), new StartDelegate(),
                WatchUi.SLIDE_IMMEDIATE);
        } else if (id == :wind) {
            // two pops on the way out: the wind menu, then this session menu, so a wind pick
            // puts the rider straight back on the water rather than one menu up from it
            WatchUi.pushView(WindMenu.build(), new WindMenuDelegate(2), WatchUi.SLIDE_UP);
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

// `pops` is how many views to unwind after a pick, and it is not cosmetic: the session menu
// pushes this on top of ITSELF (2 = wind menu + session menu, landing back on the water),
// while the start screen pushes it straight onto StartView (1 = the wind menu alone). Popping
// two from the start screen would pop StartView, which is the bottom of that stack — i.e.
// choosing a wind direction before the session would exit the app.
class WindMenuDelegate extends WatchUi.Menu2InputDelegate {

    hidden var _pops as Number;

    function initialize(pops as Number) {
        Menu2InputDelegate.initialize();
        _pops = pops;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        AppSettings.storeWindDirection(id instanceof Lang.Number ? id as Number : -1);
        for (var i = 0; i < _pops; i++) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
    }
}
