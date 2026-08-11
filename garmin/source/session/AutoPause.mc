import Toybox.Lang;

// Auto-pause, as a pure state machine so it is unit-testable without a real session.
//
// Wingfoiling has long genuine stops (waiting for a gust, walking back upwind), so this is OFF
// by default and deliberately conservative: it needs the speed to stay under STOP_MPS for the
// whole delay before it pauses, and it only ever resumes a pause IT caused — a pause the rider
// pressed for stays put until the rider presses again (SessionController.togglePause() calls
// reset(), which is what clears the ownership flag).
class AutoPause {
    // enums (not const) so they are class-static: AutoPause.EV_PAUSE etc.
    enum {
        EV_NONE = 0,
        EV_PAUSE = 1,
        EV_RESUME = 2
    }

    // 1.0 m/s = 3.6 km/h: below this nobody is riding, and it is well under any drift a bad
    // fix produces. Not exposed in GCM — the delay is the knob worth having.
    const STOP_MPS = 1.0;

    var enabled as Boolean = false;
    var delayS as Number = 5;

    hidden var _slowS as Float = 0.0;
    hidden var _owned as Boolean = false;   // this pause is ours to undo

    function initialize() {
    }

    // Call once per position sample. `recording` = the session is running right now.
    function tick(dt as Float, speedMps as Float, recording as Boolean) as Number {
        if (!enabled) {
            _slowS = 0.0;
            _owned = false;
            return EV_NONE;
        }
        if (recording) {
            if (speedMps < STOP_MPS) {
                _slowS += dt;
                if (_slowS >= delayS) {
                    _slowS = 0.0;
                    _owned = true;
                    return EV_PAUSE;
                }
            } else {
                _slowS = 0.0;
            }
            return EV_NONE;
        }
        // paused: any real movement puts us back on the water
        if (_owned && speedMps >= STOP_MPS) {
            _owned = false;
            _slowS = 0.0;
            return EV_RESUME;
        }
        return EV_NONE;
    }

    // The rider took over (manual pause/resume) — forget everything we were tracking.
    function reset() as Void {
        _slowS = 0.0;
        _owned = false;
    }

    function ownsPause() as Boolean {
        return _owned;
    }
}
