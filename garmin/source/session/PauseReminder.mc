import Toybox.Lang;

// The reminder that a pressed pause is still on (rider review W1, 9 Oct 2026).
//
// "I bumped START with the wing handle. The rest of the session has no turns." START is one
// press, a wing handle can make it, and until this round the pause made no sound at all: the
// banner said PAUSED to a rider who was not looking, and the rest of the session recorded
// nothing. Jan kept the one-press pause and made it loud instead — a buzz on pause, a buzz on
// resume, and THIS: the pause buzz again every two minutes for as long as the pause lasts.
//
// Only a pause the RIDER pressed is reminded of. An auto-pause ends itself the moment the
// board moves again (AutoPause only resumes what it paused), so it cannot be ridden through,
// and a rider who waits ten minutes for a gust with auto-pause on should not be buzzed five
// times on the beach for it.
//
// A pure clock, so the suite can drive twenty minutes in a loop: SessionController starts it
// at the pause, stops it at the resume, and asks `due` once per position sample — no fix, no
// question, the same "the callback is the clock" rule AutoPause runs on.
class PauseReminder {
    const EVERY_MS = 120000;

    hidden var _lastMs as Number = 0;
    hidden var _on as Boolean = false;

    function initialize() {
    }

    function start(nowMs as Number) as Void {
        _lastMs = nowMs;
        _on = true;
    }

    function stop() as Void {
        _on = false;
    }

    function running() as Boolean {
        return _on;
    }

    // True once per EVERY_MS of pause. The next window runs from NOW, not from the last
    // boundary: after a gap with no samples (a watch that slept, a sim that skipped) the
    // reminder buzzes once and resumes its rhythm, rather than catching up three buzzes in
    // three seconds. A clock that ran backwards (getTimer's wrap) restarts the window.
    function due(nowMs as Number) as Boolean {
        if (!_on) {
            return false;
        }
        var gap = nowMs - _lastMs;
        if (gap < 0) {
            _lastMs = nowMs;
            return false;
        }
        if (gap >= EVERY_MS) {
            _lastMs = nowMs;
            return true;
        }
        return false;
    }
}
