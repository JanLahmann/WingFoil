import Toybox.Lang;

// Whether the watch has stopped counting because the GPS went (rider review W13, 9 Oct 2026).
//
// "The watch counted 12 turns, the phone 19, and nothing told me the GPS dropped." Below
// Position.QUALITY_USABLE the engine feeds nothing to the detectors (MetricsEngine.tick's gap
// branch): no flight, no turn, no record — and the glass went on looking exactly as it did.
// From this round the state ring says so: after GRACE_MS without a usable fix it turns grey and
// breaks into segments, and the first usable fix makes it whole again.
//
// Five seconds, not one: a single poor fix under a wave or behind the sail is normal and the
// detectors ride it out; a ring that flickered on every one would teach the rider to ignore
// it. Recovery is immediate, because "counting again" is good news and costs nothing to show.
//
// Time since the last usable fix, not a count of bad ones: a receiver that stops calling back
// altogether is the worst loss of all, and a counter would never see it. Pure, so the suite
// can drive it; SessionController arms it at the session start and feeds it every sample.
class GpsLoss {
    const GRACE_MS = 5000;

    hidden var _lastGoodMs as Number = 0;
    hidden var _armed as Boolean = false;

    function initialize() {
    }

    // The session started: the window runs from here, so a session begun without a fix
    // greys after five seconds like any other loss.
    function arm(nowMs as Number) as Void {
        _lastGoodMs = nowMs;
        _armed = true;
    }

    function disarm() as Void {
        _armed = false;
    }

    function onFix(nowMs as Number, usable as Boolean) as Void {
        if (usable) {
            _lastGoodMs = nowMs;
        }
    }

    function lost(nowMs as Number) as Boolean {
        return _armed && nowMs - _lastGoodMs >= GRACE_MS;
    }
}
