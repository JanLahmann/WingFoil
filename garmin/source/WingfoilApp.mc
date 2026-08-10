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
        AppSettings.load();
    }

    function onStop(state as Dictionary?) as Void {
        controller.emergencySave();
    }

    function onSettingsChanged() as Void {
        AppSettings.load();   // thresholds hot-reload; detectors read them each tick
        WatchUi.requestUpdate();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        controller.startGps();
        return [new StartView(), new StartDelegate()];
    }
}

function getApp() as WingfoilApp {
    return Application.getApp() as WingfoilApp;
}
