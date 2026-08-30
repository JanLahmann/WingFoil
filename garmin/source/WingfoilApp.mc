import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class WingfoilApp extends Application.AppBase {
    var controller as SessionController;

    function initialize() {
        AppBase.initialize();
        controller = new SessionController();
    }

    function onStart(state as Dictionary?) as Void {
        _applySettings();
        // Phase-5 companion link. Registering costs nothing when no phone is paired, and the
        // retry is the whole point of the pending slot: the app opening is the first moment
        // after an offline save at which a card from a previous session can still get through.
        PhoneLink.register();
        PhoneLink.send();
    }

    function onStop(state as Dictionary?) as Void {
        controller.emergencySave();
    }

    function onSettingsChanged() as Void {
        _applySettings();     // thresholds hot-reload; detectors read them each tick
        // The unlock key arrives through exactly this callback: the tester types it in
        // Garmin Connect while staring at the lock screen, so re-validating here is what
        // makes the app open without a restart. No-op in every build but the invite one.
        if (LockGate.enabled() && !LockGate.isUnlocked() && LockGate.refresh()) {
            unlockedNow();
            return;
        }
        // A GCM settings edit is proof a phone was talking to this watch a second ago, which
        // makes it the cheapest reliable "the link is up" signal a watch-app gets.
        PhoneLink.send();
        WatchUi.requestUpdate();
    }

    // Leave the lock screen for the real start screen, once. Safe to call when already
    // unlocked or when the gate was never on — it only ever runs after refresh() said yes.
    function unlockedNow() as Void {
        controller.startGps();
        WatchUi.switchToView(new StartView(), new StartDelegate(), WatchUi.SLIDE_IMMEDIATE);
    }

    // Single entry point for everything GCM can change: detector thresholds, alert toggles,
    // and the data-screen model. Re-running PageModel.build() is what makes page edits live
    // without a restart; PageNav.index is re-wrapped in case the page set shrank under it.
    hidden function _applySettings() as Void {
        AppSettings.load();
        PageModel.build(null);
        PageNav.index = PageModel.wrap(PageNav.index);
        // A settings edit can remove the page the pushed map view is standing on; pop it
        // rather than leave a view no index refers to. (Pushing the map from here is not
        // done: if the edit made the current page a map, the next page press picks it up.)
        if (PageNav.mapShown
                && PageModel.layoutAt(PageNav.index) != PageModel.LAYOUT_MAP) {
            PageNav.dropMap();
            WatchUi.requestUpdate();
        }
        // The breadcrumb is now recorded ALWAYS, not only when a map page is configured.
        // The post-save summary draws the session's track as its last page, and that page is
        // the difference between a receipt and a review — it cannot be conditional on a
        // setting the rider has probably never opened. Cost: 128 x (4 + 4 + 1) bytes = 1.2 KB
        // against a 786 KB app budget.
        controller.engine.trackEnabled = true;
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        // Invite build only (docs/decisions.md ADR-012): a public store listing that stays
        // locked until an individual key is entered. Zero pepper = public/beta build = this
        // is a single array scan and nothing else. GPS deliberately stays off while locked.
        if (LockGate.enabled() && !LockGate.refresh()) {
            return [new LockView(), new LockDelegate()];
        }
        controller.startGps();
        return [new StartView(), new StartDelegate()];
    }
}

function getApp() as WingfoilApp {
    return Application.getApp() as WingfoilApp;
}
