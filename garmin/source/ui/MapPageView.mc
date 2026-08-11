import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Timer;
import Toybox.WatchUi;

// Breadcrumb map page (PageModel.LAYOUT_MAP).
//
// The map API is Toybox.WatchUi.MapTrackView — a *View*, not something that can be painted
// inside RecordingView.onUpdate — which is why paging onto this page swaps the whole view
// (PageNav.step). MapTrackView keeps itself centred on the current position and draws the
// device's own navigation arrow; all we contribute is the session's track as a MapPolyline.
//
// Every fenix 8 variant in the manifest ships MapTrackView (verified against the SDK 9.2 doc's
// supported-device list), so this compiles unconditionally; PageModel.hasMap() still gates the
// page at runtime so a future product without maps degrades to "page not offered".
//
// The polyline is rebuilt on a 5 s timer, and only when the engine has actually appended a
// point — building ~128 Location objects is not something to do at 1 Hz, and nothing else on
// this page needs a faster refresh than the map's own redraw.
class MapPageView extends WatchUi.MapTrackView {
    const REFRESH_MS = 5000;

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
        if (lat == null || lon == null) {
            return;
        }
        var poly = new WatchUi.MapPolyline();
        poly.setColor(Graphics.COLOR_GREEN);
        poly.setWidth(3);
        for (var i = 0; i < n; i++) {
            poly.addLocation(new Position.Location({
                :latitude => lat[i],
                :longitude => lon[i],
                :format => :degrees
            }));
        }
        setPolyline(poly);
        WatchUi.requestUpdate();
    }
}
