import Toybox.Activity;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import WingFoilCore;

// 1 Hz computation core, driven by position events while recording.
// Pure compute: returns events; SessionController owns laps/alerts/FIT session writes.
class MetricsEngine {
    // Wrist under water: ambient pressure jumps far beyond anything weather does.
    // docs/algorithms.md states turnBaroDrop as 25 m of *apparent altitude*; near sea level
    // that is ~12 Pa/m x 25 m = 300 Pa (3 hPa) of pressure rise. The baro domain is the one
    // the watch actually has, so the threshold is converted once, here.
    const SUBMERSION_PA = 300.0;
    const BARO_EMA = 0.02;              // ~50 s baseline: follows weather, never a dunk
    const RAD2DEG = 57.29578;

    // Breadcrumb for the optional map page: lat/lon in degrees, Float (~1 m on a wingfoil
    // spot — plenty for a track line). Only filled when a map page is configured, because
    // 2 x 128 Floats is memory the other five pages have no use for.
    const TRACK_MAX = 128;
    const TRACK_BASE_STRIDE = 5;        // one point every ~5 s at 1 Hz

    var detector as FlightDetector;
    var turns as TurnDetector;
    var records as SpeedRecords;
    var history as SessionHistory;
    // App-only: the pump/takeoff detector reads the accelerometer, which a data field may not
    // touch, so it lives here rather than in the WingFoilCore barrel (docs/fit-schema.md
    // class d). SessionController owns the sensor listener and feeds it batches.
    var pump as PumpDetector;

    var trackEnabled as Boolean = false;
    var trackLat as Array<Float>?;
    var trackLon as Array<Float>?;
    // Foil state at each breadcrumb point, so the map page can tint the trail. One Boolean per
    // point rides along with the two Floats it belongs to and is decimated with them.
    var trackFly as Array<Boolean>?;
    var trackN as Number = 0;
    hidden var _trackStride as Number = TRACK_BASE_STRIDE;
    hidden var _trackSkip as Number = 0;

    // Live state the views render
    var speedMps as Float = 0.0;
    var hr as Number?;
    var gpsQuality as Number = 0;
    var distM as Float = 0.0;
    var timerS as Float = 0.0;
    var submerged as Boolean = false;

    hidden var _lastMs as Number = 0;
    hidden var _lastDist as Float = 0.0;
    hidden var _tickCount as Number = 0;
    hidden var _baseline as Float = 0.0;
    hidden var _haveBaseline as Boolean = false;

    // Detectors come from the WingFoilCore barrel and read their thresholds from the
    // Config this app fills from GCM properties (AppSettings.load()).
    function initialize() {
        detector = new FlightDetector(AppSettings.cfg);
        turns = new TurnDetector(AppSettings.cfg);
        records = new SpeedRecords();
        history = new SessionHistory();
        pump = new PumpDetector(AppSettings.cfg);
    }

    // Returns detector event (FlightDetector.EVENT_*) | pbEvents<<4 | turnEvent<<8
    // | pumpEvent<<12.
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
        _updateSubmersion(actInfo);

        _tickCount++;

        if (gpsQuality < Position.QUALITY_USABLE) {
            // don't feed garbage into detectors/records; windows must restart cleanly
            records.onGap();
            turns.onGap();
            // an open pumping effort can no longer be judged: the lab calls that `unknown`
            // and drops it from every tally rather than calling it a failure
            pump.onGap();
            return 0;
        }

        var flightEvent = detector.tick(dt, speedMps, distDelta);
        var pbEvents = records.tick(speedMps);
        var turnEvent = turns.tick(dt, _cogDeg(info), speedMps, distDelta,
            detector.state == FlightDetector.STATE_ON, submerged);

        // Pumping is judged against the flight and turn state of this same sample: a burst
        // that starts while flying is in-flight pumping, one inside a turn window is the
        // rider recovering from that turn, and neither is a takeoff attempt.
        var pumpEvent = pump.tick(now, detector.state == FlightDetector.STATE_ON,
            turns.state != TurnDetector.ST_IDLE, flightEvent);

        history.tick(dt, detector.state == FlightDetector.STATE_ON, speedMps);
        if (turnEvent >= TurnDetector.EVENT_FLEW) {
            history.logTurn(turns.lastOutcome);
        }
        if (trackEnabled) {
            _trackTick(info, detector.state == FlightDetector.STATE_ON);
        }
        return flightEvent | (pbEvents << 4) | (turnEvent << 8) | (pumpEvent << 12);
    }

    // Appends a decimated breadcrumb point. When the buffer fills, every other point is
    // dropped and the stride doubles, so the whole session stays on the map at half the
    // resolution rather than the start scrolling off it.
    hidden function _trackTick(info as Position.Info, flying as Boolean) as Void {
        _trackSkip++;
        if (_trackSkip < _trackStride) {
            return;
        }
        _trackSkip = 0;
        var loc = info.position;
        if (loc == null) {
            return;
        }
        var lat = trackLat;
        var lon = trackLon;
        var fly = trackFly;
        if (lat == null || lon == null || fly == null) {
            lat = new [TRACK_MAX] as Array<Float>;
            lon = new [TRACK_MAX] as Array<Float>;
            fly = new [TRACK_MAX] as Array<Boolean>;
            trackLat = lat;
            trackLon = lon;
            trackFly = fly;
        }
        if (trackN >= TRACK_MAX) {
            var j = 0;
            for (var i = 0; i < trackN; i += 2) {
                lat[j] = lat[i];
                lon[j] = lon[i];
                fly[j] = fly[i];
                j++;
            }
            trackN = j;
            _trackStride *= 2;
        }
        var d = (loc as Position.Location).toDegrees();
        lat[trackN] = d[0].toFloat();
        lon[trackN] = d[1].toFloat();
        fly[trackN] = flying;
        trackN++;
    }

    // Course over ground in degrees, or null when the fix carries no heading.
    hidden function _cogDeg(info as Position.Info) as Float? {
        var h = info.heading;
        if (h == null) {
            return null;
        }
        // heading is radians in [-PI, PI]; the detector unwraps, so any 0-360 mapping works
        var deg = (h as Float) * RAD2DEG;
        while (deg < 0.0) {
            deg += 360.0;
        }
        while (deg >= 360.0) {
            deg -= 360.0;
        }
        return deg;
    }

    // Barometric submersion evidence for TurnDetector. The baseline tracks the ambient
    // pressure slowly and deliberately refuses to adapt while a spike is in progress, so a
    // 30 s swim cannot re-baseline itself into looking dry. Null-safe: devices/sim runs
    // without the channel simply lose this evidence (positive-only, its silence means
    // nothing — docs/algorithms.md "Turn outcome" step 2).
    hidden function _updateSubmersion(actInfo as Activity.Info?) as Void {
        submerged = false;
        if (actInfo == null) {
            return;
        }
        var p = null;
        if (actInfo has :rawAmbientPressure && actInfo.rawAmbientPressure != null) {
            p = actInfo.rawAmbientPressure;
        } else if (actInfo has :ambientPressure && actInfo.ambientPressure != null) {
            p = actInfo.ambientPressure;
        }
        if (p == null) {
            return;
        }
        var pa = (p as Numeric).toFloat();
        if (!_haveBaseline) {
            _haveBaseline = true;
            _baseline = pa;
            return;
        }
        var rise = pa - _baseline;
        if (rise > SUBMERSION_PA) {
            submerged = true;
            return;
        }
        _baseline += BARO_EMA * rise;
    }

    function tickCount() as Number {
        return _tickCount;
    }

    function foilPct() as Float {
        return timerS > 0 ? detector.foilTimeS / timerS * 100.0 : 0.0;
    }
}
