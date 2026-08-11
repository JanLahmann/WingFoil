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
    }

    function onStop(state as Dictionary?) as Void {
        // Nothing to save: the FIT belongs to the native activity, which closes it itself.
    }

    function onSettingsChanged() as Void {
        // Thresholds hot-reload into the same Config object the detectors already hold.
        FieldSettings.load();
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
