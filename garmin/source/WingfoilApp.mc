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
        controller.engine.trackEnabled = PageModel.mapPage;
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
