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
        WatchUi.requestUpdate();
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
        controller.startGps();
        return [new StartView(), new StartDelegate()];
    }
}

function getApp() as WingfoilApp {
    return Application.getApp() as WingfoilApp;
}
