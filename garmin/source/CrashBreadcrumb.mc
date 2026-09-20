import Toybox.Application.Storage;
import Toybox.Lang;

// THE WATCH HAS NO CRASH REPORTING. An unhandled exception drops the rider to the watch face
// and writes GARMIN/APPS/LOGS/CIQ_LOG.YML on the device — a file nobody sends us, on a watch
// that is usually on a beach. The iPhone app has MetricKit and a "Recent crashes" block in
// its feedback mail (docs/testing.md, `CrashDiagnosticsTests`); the watch had nothing, so a
// tester's "it quit on me" was the whole report and we could not even tell it apart from a
// battery that ran out.
//
// This is the smallest thing that answers "did it quit, and where". Three Storage keys:
//
//   runOpen    set on onStart, cleared on onStop. Present at the next onStart = the previous
//              run never reached onStop, which is exactly what a crash (or a firmware kill)
//              looks like from inside.
//   crashCount how many times that has happened, ever, on this watch.
//   lastView   the screen the app was on when it went. Written by the views themselves, ONE
//              setValue per view switch (see `view` below) — never per frame, because a
//              Storage write every 30 ms is its own bug.
//
// It cannot see WHY, and it is honest about that: a battery pulled mid-session counts as a
// crash here. What it buys is a number a tester can read off the card and a page name that
// says which screen to look at first.
module CrashBreadcrumb {

    const STORE_OPEN = "runOpen";
    const STORE_COUNT = "crashCount";
    const STORE_VIEW = "lastView";

    // The view names, one word each. They ride to the phone and onto the probe page, so they
    // are short on purpose and never translated.
    const V_START = "start";
    const V_RECORDING = "recording";
    const V_SUMMARY = "summary";
    const V_MENU = "menu";
    const V_PROBE = "probe";

    // Nothing sane reaches this. It is a cap on a stored number so a corrupted count cannot
    // become a five-digit string on a 240 px page or a card key the phone squints at.
    const COUNT_MAX = 999;

    // Read once at onStart and then held: how many runs before this one never closed, and the
    // view the last of them was on. `crashes` is what PhoneLink.summary carries.
    var crashes as Number = 0;
    var lastView as String = "";

    // The value already in STORE_VIEW, so a rider paging through six screens costs six
    // compares and no writes at all. Module scope, not `hidden`: Monkey C allows `hidden`
    // only on class members.
    var _written as String = "";

    // Called first thing in WingfoilApp.onStart. Counts an unclosed previous run, then marks
    // this one open.
    function onStart() as Void {
        crashes = _count();
        lastView = _view();
        if (_isOpen()) {
            crashes += 1;
            if (crashes > COUNT_MAX) {
                crashes = COUNT_MAX;
            }
            _putNumber(STORE_COUNT, crashes);
        }
        _putNumber(STORE_OPEN, 1);
        _written = "";
    }

    // Called from WingfoilApp.onStop — the app is closing the way it should.
    function onStop() as Void {
        try {
            Storage.deleteValue(STORE_OPEN);
        } catch (e) {
        }
    }

    // A view became current. Deduped: only a CHANGE of screen is written.
    function view(name as String) as Void {
        if (_written.equals(name)) {
            return;
        }
        _written = name;
        _putString(STORE_VIEW, name);
    }

    // "crashes 2 (last: recording)", or null when this watch has never lost a run. The dev
    // build writes it onto the probe's Results page at start (WingfoilApp.onStart); the beta
    // and the release carry the number on the card and nothing on screen.
    function line() as String? {
        if (crashes <= 0) {
            return null;
        }
        return "crashes " + crashes.toString()
            + (lastView.equals("") ? "" : " (last: " + lastView + ")");
    }

    // The tester has read it; start again from zero. Not wired to any menu yet — it exists so
    // a reset is one call and not a story about deleting keys by hand.
    function reset() as Void {
        crashes = 0;
        lastView = "";
        try {
            Storage.deleteValue(STORE_COUNT);
            Storage.deleteValue(STORE_VIEW);
        } catch (e) {
        }
    }

    // ---- the store, never believed ----
    // Every read is type-checked and every write is wrapped. These keys outlive the build
    // that wrote them, and a `crashCount` that came back as a String would otherwise take the
    // app down on the one line that exists to prove it did not.

    function _count() as Number {
        var v = _get(STORE_COUNT);
        if (!(v instanceof Lang.Number)) {
            return 0;
        }
        var n = v as Number;
        if (n < 0) {
            return 0;
        }
        return n > COUNT_MAX ? COUNT_MAX : n;
    }

    function _view() as String {
        var v = _get(STORE_VIEW);
        return v instanceof Lang.String ? v as String : "";
    }

    function _isOpen() as Boolean {
        return _get(STORE_OPEN) != null;
    }

    function _get(key as String) as Object? {
        try {
            return Storage.getValue(key);
        } catch (e) {
            return null;
        }
    }

    function _putNumber(key as String, v as Number) as Void {
        try {
            Storage.setValue(key, v);
        } catch (e) {
        }
    }

    function _putString(key as String, v as String) as Void {
        try {
            Storage.setValue(key, v);
        } catch (e) {
        }
    }

    // The probe's Results page is the dev build's log; outside it there is no page to write
    // to and this compiles to nothing.
    (:dev)
    function report() as Void {
        var l = line();
        if (l != null) {
            LinkProbe.append(l as String);
        }
    }

    (:notdev)
    function report() as Void {
    }
}
