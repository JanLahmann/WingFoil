import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// The best-2s personal-best celebration.
//
// A PB is the one thing on the water worth interrupting the rider for, and the existing double
// buzz (AlertManager.speedPb) is easy to miss with a wetsuit hood on. This adds the visual half:
// the whole screen strobes green for ~700 ms with the new number on it, then the page comes
// back exactly as it was.
//
// Timing is frame-driven, not sample-driven: the position callback only fires at 1 Hz, so a
// flash that lived on requestUpdate() alone would be one static frame. A single repeating
// Timer, allocated ONCE for the life of the app and re-armed rather than re-created, walks
// FRAMES frames of FRAME_MS and then clears itself. `active()` is a Number compare, so the
// steady-state cost on every other redraw is nothing and no tick allocates.
//
// State lives in a module, not in RecordingView: paging on and off the map swaps the whole
// View (see PageNav), and a celebration must not die because the rider happened to be scrolling.
module PbFlash {
    const FRAME_MS = 100;
    const FRAMES = 7;              // 7 x 100 ms = 700 ms

    var frame as Number = -1;      // -1 = idle
    var best2sMps as Float = 0.0;
    var _timer as PbFlashTimer? = null;

    // New best 2 s average. Re-firing during a flash simply restarts it.
    function fire(mps as Float) as Void {
        best2sMps = mps;
        frame = 0;
        if (_timer == null) {
            _timer = new PbFlashTimer();
        }
        (_timer as PbFlashTimer).arm(FRAME_MS);
        WatchUi.requestUpdate();
    }

    function active() as Boolean {
        return frame >= 0;
    }

    // One frame older. Auto-clears at FRAMES so a flash can never get stuck on screen.
    function tick() as Void {
        if (frame < 0) {
            return;
        }
        frame++;
        if (frame >= FRAMES) {
            stop();
        }
        WatchUi.requestUpdate();
    }

    // Idempotent: safe from onHide, from the save/discard path and from the timer itself.
    function stop() as Void {
        frame = -1;
        if (_timer != null) {
            (_timer as PbFlashTimer).disarm();
        }
    }

    // Alternating shades are what makes it read as a PULSE rather than a still green card.
    function color() as Number {
        return frame % 2 == 0 ? Graphics.COLOR_GREEN : Graphics.COLOR_DK_GREEN;
    }
}

// Owns the one Timer. A class, not a bare module method reference, because `method(:sym)`
// binds to `self` and a module is not a reliable `self` for a Timer callback.
class PbFlashTimer {
    hidden var _t as Timer.Timer;

    function initialize() {
        _t = new Timer.Timer();
    }

    function arm(ms as Number) as Void {
        _t.stop();
        _t.start(method(:onFrame), ms, true);
    }

    function disarm() as Void {
        _t.stop();
    }

    function onFrame() as Void {
        PbFlash.tick();
    }
}
