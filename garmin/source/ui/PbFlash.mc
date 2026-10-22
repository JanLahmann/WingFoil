import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// The best-2s personal-best celebration.
//
// A PB is the one thing on the water worth interrupting the rider for, and the existing double
// buzz (AlertManager.speedPb) is easy to miss with a wetsuit hood on. This adds the visual half:
// the whole screen strobes orange for 700 ms with the new number on it, then HOLDS that number
// steadily until HOLD_MS (3 s) have passed, then the page comes back exactly as it was.
//
// Why strobe-then-hold (Jan, 22 Oct 2026, from a tester: "display 2 sec speed record in big
// numbers for some seconds"): the strobe is what catches the eye at the moment of the buzz, and
// a number on a strobing ground is the hardest thing on the glass to read. A rider who looks
// down a second or two after the buzz — which is when he looks, once he has the board settled —
// gets a still card he can read in one glance. A strobe for the full 3 s would be both
// tiring and less legible; a hold with no strobe at all would lose the "something happened".
//
// A turn verdict (EventFlash) paints over this while it runs — the verdict is the newer fact.
// The PB clock keeps running underneath, so when the 1.5 s verdict ends the hold shows for
// whatever is left of its 3 s, or not at all; it never restarts, so a PB cannot reappear
// seconds later and read as a second one.
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
    const STROBE_FRAMES = 7;       // 7 x 100 ms = 700 ms of strobe ...
    const HOLD_MS = 3000;          // ... inside 3 s on screen in all (Jan, 22 Oct 2026)
    const FRAMES = HOLD_MS / FRAME_MS;

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
    // During the hold nothing changes on screen, so only the strobe frames and the end ask
    // for a repaint (the 1 Hz position callback repaints the page anyway).
    function tick() as Void {
        if (frame < 0) {
            return;
        }
        frame++;
        if (frame >= FRAMES) {
            stop();
        } else if (frame > STROBE_FRAMES) {
            return;
        }
        WatchUi.requestUpdate();
    }

    function strobing() as Boolean {
        return frame >= 0 && frame < STROBE_FRAMES;
    }

    // Idempotent: safe from onHide, from the save/discard path and from the timer itself.
    function stop() as Void {
        frame = -1;
        if (_timer != null) {
            (_timer as PbFlashTimer).disarm();
        }
    }

    // Alternating shades are what makes it read as a PULSE rather than a still card; after
    // STROBE_FRAMES the full shade holds still.
    //
    // The ink is the EFFORT window orange, not green: a personal best is something the rider
    // did, not a verdict on a maneuver, and green on this app is the outcome ladder's "flew
    // through" (docs/presentation.md). The dim frame is that same token at half brightness —
    // a derivation of one value, not a second value: shifting every channel down one bit
    // keeps the hue exactly and cannot drift from the token it came from.
    function color() as Number {
        var c = Ink.effortWindow();
        return (!strobing() || frame % 2 == 0) ? c : (c >> 1) & 0x7F7F7F;
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
