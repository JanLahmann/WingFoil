import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Entry point of the WingFoil Field data field. A data field app owns exactly one view and
// no input: the native activity drives everything, we only get compute()/onUpdate().
class WingFoilFieldApp extends Application.AppBase {
    hidden var _field as WingFoilDataField?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        FieldSettings.load();
        // Invite build only (docs/decisions.md ADR-012). With the zero pepper this is one
        // array scan that reports unlocked and never runs again; with a real pepper it is
        // what re-reads the unlock this watch already earned, so a tester who unlocked last
        // week does not see the lock again at the top of every session.
        LockGate.refresh();
    }

    function onStop(state as Dictionary?) as Void {
        // Nothing to save: the FIT belongs to the native activity, which closes it itself.
    }

    function onSettingsChanged() as Void {
        // Thresholds hot-reload into the same Config object the detectors already hold.
        FieldSettings.load();
        // The unlock key arrives through exactly this callback: the tester types it into
        // Garmin Connect mid-activity while the cell shows the request code, and re-validating
        // here is what makes the field start computing without ending the activity.
        LockGate.refresh();
        WatchUi.requestUpdate();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        _field = new WingFoilDataField();
        return [_field] as [Views];
    }
}

function getFieldApp() as WingFoilFieldApp {
    return Application.getApp() as WingFoilFieldApp;
}
