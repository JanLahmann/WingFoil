import Toybox.Activity;
import Toybox.Lang;
import Toybox.Position;
import WingFoilCore;

// The data field's 1 Hz computation core — the Activity.Info twin of the device app's
// MetricsEngine. Same detectors (from the barrel), same gates, different input plumbing:
// a data field has no Position events and no ActivityRecording, it gets one Activity.Info
// per second in compute() and nothing else.
//
// What a fenix 8 data field can actually read (verified in
// ~/Library/Application Support/Garmin/ConnectIQ/Devices/fenix847mm/fenix847mm.api.debug.xml):
//   currentSpeed (m/s, GNSS Doppler under the Windsurf profile) · track (radians, direction
//   of travel = the COG the TurnDetector needs) · currentLocationAccuracy (Position.QUALITY_*)
//   · elapsedDistance (m) · timerTime (ms) · timerState · rawAmbientPressure /
//   ambientPressure (Pa, the submersion evidence) · altitude · currentHeartRate.
// What it must NOT touch: every Sensor.* entry point (registerSensorDataListener,
// enableSensorEvents, getInfo, ...) is documented "Will cause an app crash if called from a
// data field app" — hence no accelerometer, no pump metrics. See docs/fit-schema.md.
class FieldEngine {
    // Same submersion model as MetricsEngine (docs/algorithms.md "Turn outcome"): ~300 Pa
    // above a slow baseline is a wrist under water, and the baseline refuses to adapt while
    // a spike is in progress so a long swim cannot re-baseline itself dry.
    const SUBMERSION_PA = 300.0;
    const BARO_EMA = 0.02;
    const RAD2DEG = 57.29578;

    var detector as FlightDetector;
    var turns as TurnDetector;
    var records as SpeedRecords;

    // Live state the view renders
    var speedMps as Float = 0.0;
    var gpsQuality as Number = 0;
    var distM as Float = 0.0;
    var timerS as Float = 0.0;
    var submerged as Boolean = false;
    var running as Boolean = false;     // activity timer is on

    hidden var _cfg as WingFoilCore.Config;
    hidden var _lastTimerMs as Number = -1;
    hidden var _lastDist as Float = 0.0;
    hidden var _tickCount as Number = 0;
    hidden var _baseline as Float = 0.0;
    hidden var _haveBaseline as Boolean = false;

    function initialize(cfg as WingFoilCore.Config) {
        _cfg = cfg;
        detector = new FlightDetector(cfg);
        turns = new TurnDetector(cfg);
        records = new SpeedRecords();
    }

    // A fresh activity (onTimerReset): drop every counter, keep the config.
    function reset() as Void {
        detector = new FlightDetector(_cfg);
        turns = new TurnDetector(_cfg);
        records = new SpeedRecords();
        speedMps = 0.0;
        gpsQuality = 0;
        distM = 0.0;
        timerS = 0.0;
        submerged = false;
        _lastTimerMs = -1;
        _lastDist = 0.0;
        _tickCount = 0;
        _haveBaseline = false;
    }

    // One compute() call. Returns the same packed event word MetricsEngine returns:
    // flightEvent | pbEvents << 4 | turnEvent << 8.
    //
    // dt comes from timerTime, not the system clock: it is the activity's own clock, it
    // stops when the rider pauses, and it makes the whole tick path drivable from a test.
    function onCompute(info as Activity.Info) as Number {
        var st = info.timerState;
        running = (st != null) && (st == Activity.TIMER_STATE_ON);

        var tms = info.timerTime;
        var dt = 1.0;
        if (tms != null) {
            var ms = tms as Number;
            if (_lastTimerMs >= 0) {
                dt = (ms - _lastTimerMs) / 1000.0;
            }
            _lastTimerMs = ms;
            timerS = ms / 1000.0;
        }
        if (!running) {
            return 0;           // paused/stopped: hold every counter where it is
        }
        if (dt < 0.2) {
            return 0;           // sub-second re-compute: nothing to integrate
        }
        if (dt > 3.0) {
            dt = 3.0;           // a gap in compute() must not inflate foil time
        }

        var sp = info.currentSpeed;
        var speed = sp != null ? sp as Float : 0.0;

        var distDelta = speed * dt;
        var ed = info.elapsedDistance;
        if (ed != null) {
            var d = ed as Float;
            if (d >= _lastDist) {
                distDelta = d - _lastDist;
            }
            _lastDist = d;
            distM = d;
        }

        var quality = info.currentLocationAccuracy;
        var q = quality != null ? quality as Number : 0;

        return feed(dt, speed, _cogDeg(info), distDelta, q, _pressure(info));
    }

    // The whole per-tick contract, with every Activity.Info lookup already done: unit tests
    // drive this directly with synthetic 1 Hz arrays.
    function feed(dt as Float, speed as Float, cogDeg as Float?, distDelta as Float,
            quality as Number, pressurePa as Float?) as Number {
        speedMps = speed;
        gpsQuality = quality;
        _updateSubmersion(pressurePa);
        _tickCount++;

        if (quality < Position.QUALITY_USABLE) {
            // don't feed garbage into detectors/records; windows must restart cleanly
            records.onGap();
            turns.onGap();
            return 0;
        }

        var flightEvent = detector.tick(dt, speed, distDelta);
        var pbEvents = records.tick(speed);
        var turnEvent = turns.tick(dt, cogDeg, speed, distDelta,
            detector.state == FlightDetector.STATE_ON, submerged);
        return flightEvent | (pbEvents << 4) | (turnEvent << 8);
    }

    function tickCount() as Number {
        return _tickCount;
    }

    function foilPct() as Float {
        return timerS > 0 ? detector.foilTimeS / timerS * 100.0 : 0.0;
    }

    function flying() as Boolean {
        return detector.state == FlightDetector.STATE_ON;
    }

    // Direction of travel in degrees, or null when the fix carries none. Activity.Info.track
    // is radians ("the direction of travel based on GPS movement") — the same quantity
    // Position.Info.heading gives the device app.
    hidden function _cogDeg(info as Activity.Info) as Float? {
        if (!(info has :track) || info.track == null) {
            return null;
        }
        var deg = (info.track as Float) * RAD2DEG;
        while (deg < 0.0) {
            deg += 360.0;
        }
        while (deg >= 360.0) {
            deg -= 360.0;
        }
        return deg;
    }

    hidden function _pressure(info as Activity.Info) as Float? {
        if (info has :rawAmbientPressure && info.rawAmbientPressure != null) {
            return (info.rawAmbientPressure as Numeric).toFloat();
        }
        if (info has :ambientPressure && info.ambientPressure != null) {
            return (info.ambientPressure as Numeric).toFloat();
        }
        return null;
    }

    // Positive-only evidence: a device or a sim run without the channel simply loses it.
    hidden function _updateSubmersion(pa as Float?) as Void {
        submerged = false;
        if (pa == null) {
            return;
        }
        var p = pa as Float;
        if (!_haveBaseline) {
            _haveBaseline = true;
            _baseline = p;
            return;
        }
        var rise = p - _baseline;
        if (rise > SUBMERSION_PA) {
            submerged = true;
            return;
        }
        _baseline += BARO_EMA * rise;
    }
}
