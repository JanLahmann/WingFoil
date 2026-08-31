import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// Splitting the breadcrumb into runs of equal foil state.
//
// It was written for WatchUi.MapPolyline, which carries ONE colour for a whole connected line,
// and it survives the native map's removal (0.9.2) because the same problem exists when we draw
// the trail ourselves: a colour change is a `setColor` call, and a 128-point track whose state
// flickers point-to-point would make 128 of them per frame. This module bounds that by growing
// a minimum run length until the run count fits MAX_RUNS — short flickers get absorbed into the
// run around them, which is exactly the right lie to tell at one pixel per minute. Pure integer
// maths on the arrays that already exist: nothing here allocates, and it is unit-testable
// without a map.
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

    // The smallest minimum-run length that keeps the whole track inside MAX_RUNS runs.
    function minRunFor(fly as Array<Boolean>, n as Number) as Number {
        var minRun = 1;
        while (minRun < n && runCount(fly, n, minRun) > MAX_RUNS) {
            minRun++;
        }
        return minRun;
    }
}

// The breadcrumb as a SHAPE, drawn with Dc primitives — one renderer, two screens.
//
// WHY THIS EXISTS AT ALL. Until 0.9.2 the live map page was `WatchUi.MapTrackView`, the
// firmware's own native view. Three releases tried to make it work and the device said no
// three times: 0.8.x switched to it (`switchToView` over a native base view — a Type Error on
// the watch, fine in the simulator), 0.9.1 pushed it instead (`pushView`, the documented way)
// and the fenix 8 still killed the app the moment it came up during a recording session, with
// NOTHING in CIQ_LOG. A crash a rider can reproduce and a log cannot see is not a crash to keep
// chasing, so the native map is gone: the trail is now drawn like every other page, inside
// RecordingView.onUpdate, on every product whether or not it has a map.
//
// The post-save Track page has drawn its trail this way since 0.8.2 and never crashed anything,
// which is the other half of the argument. That renderer is this one — the two screens share it
// rather than owning two copies, because a live trail and a post-save trail that disagreed
// about which half of the session was flown would be the same bug twice.
//
// Bounding box, longitudes squeezed by cos(lat) so the track keeps its real proportions, then
// one aspect-preserving scale — a straight-line reach must land in a band, not be stretched to
// fill the box. North is up, always: a rotating map is a thing to read, and this is a thing to
// glance at.
module TrackDraw {

    // Full side of the square a track of radius `r` may use: the square inscribed in that
    // circle has side r*sqrt(2). Callers scale the track's longer axis to this and hang their
    // caption off `cy + box/2`, so this must be the WHOLE side — returning the half once drew
    // every track at half size with the caption floating mid-glass.
    function boxSide(r as Number) as Number {
        return r * 1414 / 1000;
    }

    // Degrees-to-pixels, aspect preserved: whichever axis is relatively longer sets the scale,
    // so a track that is 3 km by 200 m draws as a band. A degenerate (single-point) track gets
    // a finite scale rather than an infinity.
    function scale(box as Number, w as Float, h as Float) as Float {
        var sw = w > 0.0 ? box / w : 1.0e9;
        var sh = h > 0.0 ? box / h : 1.0e9;
        var s = sw < sh ? sw : sh;
        return s > 1.0e8 ? 1.0e8 : s;
    }

    // Draw `n` points into the square of side `box` centred on (cx, cy). `marker` puts a white
    // dot on the newest point — where the rider is NOW, which is the one thing a live trail has
    // to say and a post-save one does not. Returns false when there is no line to draw, so the
    // caller can say so in words instead.
    function draw(dc as Dc, lat as Array<Float>?, lon as Array<Float>?, fly as Array<Boolean>?,
            n as Number, cx as Number, cy as Number, box as Number,
            marker as Boolean) as Boolean {
        if (n < 2 || lat == null || lon == null || fly == null) {
            return false;
        }
        var latLo = lat[0];
        var latHi = lat[0];
        var lonLo = lon[0];
        var lonHi = lon[0];
        for (var i = 1; i < n; i++) {
            if (lat[i] < latLo) { latLo = lat[i]; }
            if (lat[i] > latHi) { latHi = lat[i]; }
            if (lon[i] < lonLo) { lonLo = lon[i]; }
            if (lon[i] > lonHi) { lonHi = lon[i]; }
        }
        var midLat = (latLo + latHi) / 2.0;
        var midLon = (lonLo + lonHi) / 2.0;
        var squeeze = Math.cos(midLat * 0.017453292);
        var s = scale(box, (lonHi - lonLo) * squeeze, latHi - latLo);

        // One setColor per RUN, not per segment: see TrackTint. The first point of the next run
        // belongs to this one too, or the trail shows a hole at every state change.
        dc.setPenWidth(3);
        var minRun = TrackTint.minRunFor(fly, n);
        var i = 0;
        while (i < n) {
            var end = TrackTint.runEnd(fly, n, i, minRun);
            // Phase teal / the dim ink, never green: the rider has been trained by the outcome
            // markers to read green as "that jibe worked", and a green track would be saying it
            // about a straight line (docs/presentation.md).
            dc.setColor(fly[i] ? Ink.phaseFlying() : Ink.dim(), Graphics.COLOR_TRANSPARENT);
            var px = cx + ((lon[i] - midLon) * squeeze * s).toNumber();
            // screen y grows downward, latitude grows northward
            var py = cy - ((lat[i] - midLat) * s).toNumber();
            var last = end < n ? end : n - 1;
            for (var k = i + 1; k <= last; k++) {
                var qx = cx + ((lon[k] - midLon) * squeeze * s).toNumber();
                var qy = cy - ((lat[k] - midLat) * s).toNumber();
                dc.drawLine(px, py, qx, qy);
                px = qx;
                py = qy;
            }
            i = end;
        }
        dc.setPenWidth(1);
        if (marker) {
            var r = markerRadius(dc);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx + ((lon[n - 1] - midLon) * squeeze * s).toNumber(),
                cy - ((lat[n - 1] - midLat) * s).toNumber(), r);
        }
        return true;
    }

    // The "you are here" dot. Scaled off the glass like every other bezel dimension, and never
    // smaller than 3 px, because a 1 px dot on a teal line is not a position.
    function markerRadius(dc as Dc) as Number {
        var r = dc.getWidth() / 60;
        return r < 3 ? 3 : r;
    }
}
