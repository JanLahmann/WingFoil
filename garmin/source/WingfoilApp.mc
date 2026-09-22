import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class WingfoilApp extends Application.AppBase {
    var controller as SessionController;

    function initialize() {
        AppBase.initialize();
        // The words the glass draws, out of the resource table and into the globals the
        // pages use (docs/copy/watch.json, garmin/tools/make_strings.py). Once, here, before
        // any view exists: a menu is built by a delegate rather than by a page, so the app
        // is the one place upstream of every one of them.
        Words.load();
        controller = new SessionController();
    }

    function onStart(state as Dictionary?) as Void {
        // FIRST, before anything that can itself fail: a run that never reached onStop is
        // counted here and nowhere else (CrashBreadcrumb).
        CrashBreadcrumb.onStart();
        CrashBreadcrumb.report();
        _applySettings();
        // Phase-5 companion link. Registering costs nothing when no phone is paired, and the
        // retry is the whole point of the pending slot: the app opening is the first moment
        // after an offline save at which a card from a previous session can still get through.
        PhoneLink.register();
        PhoneLink.send();
        // Pages of a direct stream an earlier run could not deliver (dev build only).
        DirectSend.restore();
    }

    function onStop(state as Dictionary?) as Void {
        controller.emergencySave();
        DirectSend.persist();
        // LAST: the session and the pages are safe, so this run closed properly. Anything
        // that killed us before this line is what the next start counts.
        CrashBreadcrumb.onStop();
    }

    function onSettingsChanged() as Void {
        // The reset switch first: it rewrites the page properties, and the rebuild inside
        // _applySettings has to read the restored ones, not the ones the rider just left.
        if (AppSettings.consumeResetPages()) {
            PageModel.restoreDefaults();
        }
        _applySettings();     // thresholds hot-reload; detectors read them each tick
        // A GCM settings edit is proof a phone was talking to this watch a second ago, which
        // makes it the cheapest reliable "the link is up" signal a watch-app gets.
        PhoneLink.send();
        DirectSend.reopen();
        WatchUi.requestUpdate();
    }

    // Single entry point for everything GCM can change: detector thresholds, alert toggles,
    // and the data-screen model. Re-running PageModel.build() is what makes page edits live
    // without a restart; PageNav.index is re-wrapped in case the page set shrank under it.
    hidden function _applySettings() as Void {
        AppSettings.load();
        PageModel.build(null);
        PageNav.index = PageModel.wrap(PageNav.index);
        // The breadcrumb is now recorded ALWAYS, not only when a map page is configured.
        // The post-save summary draws the session's track as its last page, and that page is
        // the difference between a receipt and a review — it cannot be conditional on a
        // setting the rider has probably never opened. Cost: 128 x (4 + 4 + 1) bytes = 1.2 KB
        // against a 786 KB app budget.
        controller.engine.trackEnabled = true;
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        controller.startGps();
        // The GPS is already warming while the splash is up, so the second and a half it
        // holds costs the rider nothing on the way to a fix (BrandSplashView, 0.9.10).
        if (BrandSplash.due()) {
            return [new BrandSplashView(), new BrandSplashDelegate()];
        }
        return [new StartView(), new StartDelegate()];
    }
}

function getApp() as WingfoilApp {
    return Application.getApp() as WingfoilApp;
}
