import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Timer;
import Toybox.WatchUi;

// Splitting the breadcrumb into runs of equal foil state.
//
// WatchUi.MapPolyline carries ONE colour for the whole line (setColor), and a polyline is a
// connected chain — so "green while flying, gray otherwise" cannot be two polylines with the
// points dealt out alternately: each would join its own points straight across the gaps where
// the other was. It has to be one polyline per contiguous RUN, added with setPolyline() (which
// the API documents as "add", with clear() removing all of them).
//
// The catch is arithmetic: 128 decimated points over a two-hour session land ~1 min apart, so
// a rider doing 1-2 min flights produces a run on nearly every point. This module bounds that
// by growing a minimum run length until the run count fits MAX_RUNS — short flickers get
// absorbed into the run around them, which is exactly the right lie to tell at one pixel per
// minute. Pure integer maths on the arrays that already exist: nothing here allocates, and it
// is unit-testable without a map.
module TrackTint {
    const MAX_RUNS = 32;

    // Number of runs `fly[0..n)` splits into when a run must be at least `minRun` points long.
    // A shorter stretch of the other state is swallowed by the run it interrupts.
    function runCount(fly as Array<Boolean>, n as Number, minRun as Number) as Number {
        var runs = 0;
        var i = 0;
        while (i < n) {
            i = runEnd(fly, n, i, minRun);
            runs++;
        }
        return runs;
    }

    // Index one past the run that starts at `from`. The run keeps extending while the state
    // matches, and also across any stretch of the other state shorter than `minRun`.
    function runEnd(fly as Array<Boolean>, n as Number, from as Number,
            minRun as Number) as Number {
        var state = fly[from];
        var i = from + 1;
        while (i < n) {
            if (fly[i] == state) {
                i++;
                continue;
            }
            // a differing stretch: measure it, and only break out if it is long enough to be
            // a run of its own
            var j = i;
            while (j < n && fly[j] != state) {
                j++;
            }
            if (j - i >= minRun || j >= n) {
                return i;
            }
            i = j;      // too short to matter: absorb it and carry on
        }
        return n;
    }

    // The smallest minimum-run length that keeps the whole track inside MAX_RUNS polylines.
    function minRunFor(fly as Array<Boolean>, n as Number) as Number {
        var minRun = 1;
        while (minRun < n && runCount(fly, n, minRun) > MAX_RUNS) {
            minRun++;
        }
        return minRun;
    }
}

// Breadcrumb map page (PageModel.LAYOUT_MAP).
//
// The map API is Toybox.WatchUi.MapTrackView — a *View*, not something that can be painted
// inside RecordingView.onUpdate — which is why paging onto this page swaps the whole view
// (PageNav.step). MapTrackView keeps itself centred on the current position and draws the
// device's own navigation arrow; all we contribute is the session's track, drawn in the phase
// teal where the rider was flying and the dim ink where he was not.
//
// Every fenix 8 variant in the manifest ships MapTrackView (verified against the SDK 9.2 doc's
// supported-device list), so this compiles unconditionally; PageModel.hasMap() still gates the
// page at runtime so a future product without maps degrades to "page not offered".
//
// The polylines are rebuilt on a 5 s timer, and only when the engine has actually appended a
// point — building ~128 Location objects is not something to do at 1 Hz, and nothing else on
// this page needs a faster refresh than the map's own redraw.
class MapPageView extends WatchUi.MapTrackView {
    const REFRESH_MS = 5000;
    const TRACK_W = 3;

    hidden var _timer as Timer.Timer?;
    hidden var _drawn as Number = -1;

    function initialize() {
        MapTrackView.initialize();
    }

    function onShow() as Void {
        _refresh();
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), REFRESH_MS, true);
    }

    function onHide() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    function onTick() as Void {
        _refresh();
    }

    hidden function _refresh() as Void {
        var e = getApp().controller.engine;
        var n = e.trackN;
        if (n < 2 || n == _drawn) {
            return;
        }
        _drawn = n;
        var lat = e.trackLat;
        var lon = e.trackLon;
        var fly = e.trackFly;
        if (lat == null || lon == null || fly == null) {
            return;
        }
        clear();
        var minRun = TrackTint.minRunFor(fly, n);
        var i = 0;
        while (i < n) {
            var end = TrackTint.runEnd(fly, n, i, minRun);
            var poly = new WatchUi.MapPolyline();
            // Phase teal / the dim ink, never green: the rider has been trained by the
            // outcome markers to read green as "that jibe worked", and a green track would
            // be saying it about a straight line (docs/presentation.md).
            poly.setColor(fly[i] ? Ink.phaseFlying() : Ink.dim());
            poly.setWidth(TRACK_W);
            for (var k = i; k < end; k++) {
                poly.addLocation(_loc(lat[k], lon[k]));
            }
            // the first point of the NEXT run belongs to this one too, or the trail would
            // show a hole at every state change
            if (end < n) {
                poly.addLocation(_loc(lat[end], lon[end]));
            }
            setPolyline(poly);
            i = end;
        }
        WatchUi.requestUpdate();
    }

    hidden function _loc(lat as Float, lon as Float) as Position.Location {
        return new Position.Location({
            :latitude => lat,
            :longitude => lon,
            :format => :degrees
        });
    }
}
