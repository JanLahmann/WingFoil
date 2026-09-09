import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
import Toybox.WatchUi;

// THE POST-SAVE MAP (device app 0.9.9, GitHub #4) — an experiment, off by default.
//
// The firmware's map view killed the app three ways during a *recording* session
// (docs/watch-ui-review.md §12.1), which is why the live page draws its own breadcrumb. What
// was never tried is the native map when the session is OVER: no sensors being written to, no
// FIT session open, no timer, no PageNav — just a track to show. This page is that trial.
//
// It is reached from the Summary's Track page with START, only when the rider has switched
// "Map after save" on in the settings and the watch has the view at all. If the firmware kills
// it, the session is already saved: the rider loses a map page he opened on purpose, and
// nothing else. That is the whole reason it lives on the summary stack and nowhere near a
// recording.
//
// Static, not live: the polylines are built once in onShow from the engine's breadcrumb
// (the same lat/lon/fly arrays TrackDraw draws), tinted per run of foil state exactly as the
// drawn track is, and the visible area is the track's own bounding box in preview mode —
// MapTrackView would otherwise centre on the CURRENT position, which ashore is the car park.
module SavedMap {
    // Whether the page can be offered: the setting, and a firmware that has the view.
    function available() as Boolean {
        if (!AppSettings.mapAfterSave) {
            return false;
        }
        return (WatchUi has :MapTrackView) && (WatchUi has :MapPolyline);
    }

    // A bounding box padded by 8 % of its larger side, never thinner than ~50 m, so a
    // session sailed up and down one line still gets a map with water either side of it.
    function padDeg(span as Float) as Float {
        var pad = span * 0.08;
        return pad < 0.00045 ? 0.00045 : pad;
    }
}

class SavedMapView extends WatchUi.MapTrackView {
    const TRACK_W = 3;

    function initialize() {
        MapTrackView.initialize();
    }

    function onShow() as Void {
        _build();
    }

    hidden function _build() as Void {
        var e = getApp().controller.engine;
        var n = e.trackN;
        var lat = e.trackLat;
        var lon = e.trackLon;
        var fly = e.trackFly;
        if (n < 2 || lat == null || lon == null || fly == null) {
            return;
        }
        clear();
        var minLat = lat[0]; var maxLat = lat[0];
        var minLon = lon[0]; var maxLon = lon[0];
        for (var k = 1; k < n; k++) {
            if (lat[k] < minLat) { minLat = lat[k]; }
            if (lat[k] > maxLat) { maxLat = lat[k]; }
            if (lon[k] < minLon) { minLon = lon[k]; }
            if (lon[k] > maxLon) { maxLon = lon[k]; }
        }
        var padLat = SavedMap.padDeg(maxLat - minLat);
        var padLon = SavedMap.padDeg(maxLon - minLon);
        setMapMode(WatchUi.MAP_MODE_PREVIEW);
        setMapVisibleArea(_loc(maxLat + padLat, minLon - padLon),
            _loc(minLat - padLat, maxLon + padLon));
        var minRun = TrackTint.minRunFor(fly, n);
        var i = 0;
        while (i < n) {
            var end = TrackTint.runEnd(fly, n, i, minRun);
            var poly = new WatchUi.MapPolyline();
            poly.setColor(fly[i] ? Ink.phaseFlying() : Ink.dim());
            poly.setWidth(TRACK_W);
            for (var k = i; k < end; k++) {
                poly.addLocation(_loc(lat[k], lon[k]));
            }
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

// BACK returns to the summary; everything else is the map's own (pan/zoom in browse mode is
// the firmware's business, and preview mode takes no input at all).
class SavedMapDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
