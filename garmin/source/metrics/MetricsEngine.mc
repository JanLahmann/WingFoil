import Toybox.Activity;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;

// 1 Hz computation core, driven by position events while recording.
// Pure compute: returns events; SessionController owns laps/alerts/FIT session writes.
class MetricsEngine {
    var detector as FlightDetector;
    var records as SpeedRecords;

    // Live state the views render
    var speedMps as Float = 0.0;
    var hr as Number?;
    var gpsQuality as Number = 0;
    var distM as Float = 0.0;
    var timerS as Float = 0.0;

    hidden var _lastMs as Number = 0;
    hidden var _lastDist as Float = 0.0;
    hidden var _tickCount as Number = 0;

    function initialize() {
        detector = new FlightDetector();
        records = new SpeedRecords();
    }

    // Returns detector event (FlightDetector.EVENT_*) | pbEvents<<4 packed.
    function tick(info as Position.Info) as Number {
        var now = System.getTimer();
        var dt = _lastMs > 0 ? (now - _lastMs) / 1000.0 : 1.0;
        _lastMs = now;
        if (dt < 0.2) {
            return 0;
        }
        if (dt > 3.0) {
            dt = 3.0;
        }

        gpsQuality = info.accuracy != null ? info.accuracy as Number : 0;
        var sp = info.speed;
        speedMps = sp != null ? sp : 0.0;

        var actInfo = Activity.getActivityInfo();
        var distDelta = speedMps * dt;
        if (actInfo != null) {
            if (actInfo.timerTime != null) {
                timerS = actInfo.timerTime / 1000.0;
            }
            if (actInfo.elapsedDistance != null) {
                var d = actInfo.elapsedDistance as Float;
                if (d >= _lastDist) {
                    distDelta = d - _lastDist;
                }
                _lastDist = d;
                distM = d;
            }
            hr = actInfo.currentHeartRate;
        }

        _tickCount++;

        if (gpsQuality < Position.QUALITY_USABLE) {
            // don't feed garbage into detectors/records; windows must restart cleanly
            records.onGap();
            return 0;
        }

        var flightEvent = detector.tick(dt, speedMps, distDelta);
        var pbEvents = records.tick(speedMps);
        return flightEvent | (pbEvents << 4);
    }

    function tickCount() as Number {
        return _tickCount;
    }

    function foilPct() as Float {
        return timerS > 0 ? detector.foilTimeS / timerS * 100.0 : 0.0;
    }
}
