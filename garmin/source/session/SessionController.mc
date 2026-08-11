import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Lang;
import Toybox.Position;
import Toybox.SensorLogging;
import Toybox.WatchUi;
import WingFoilCore;

// Owns the ActivityRecording.Session, GPS wiring, laps, and save/discard flow.
// State machine: IDLE -> RECORDING <-> PAUSED -> SAVED (docs/plan.md §3.2).
class SessionController {
    enum {
        STATE_IDLE = 0,
        STATE_RECORDING = 1,
        STATE_PAUSED = 2,
        STATE_SAVED = 3
    }

    var state as Number = STATE_IDLE;
    var engine as MetricsEngine;

    hidden var _session as ActivityRecording.Session?;
    hidden var _fit as FitFields?;
    hidden var _logger;
    hidden var _prevLongest as Float = 0.0;

    function initialize() {
        engine = new MetricsEngine();
    }

    // ---- GPS ----

    function startGps() as Void {
        var opts = {:acquisitionType => Position.LOCATION_CONTINUOUS};
        if (Position has :hasConfigurationSupport) {
            var cfgs = [] as Array;
            if (Position has :CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1_L5) {
                cfgs.add(Position.CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1_L5);
            }
            if (Position has :CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1) {
                cfgs.add(Position.CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1);
            }
            if (Position has :CONFIGURATION_GPS) {
                cfgs.add(Position.CONFIGURATION_GPS);
            }
            for (var i = 0; i < cfgs.size(); i++) {
                if (Position.hasConfigurationSupport(cfgs[i])) {
                    opts[:configuration] = cfgs[i];
                    break;
                }
            }
        }
        try {
            Position.enableLocationEvents(opts, method(:onPosition));
        } catch (e) {
            // legacy signature fallback
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        }
    }

    function stopGps() as Void {
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
    }

    function onPosition(info as Position.Info) as Void {
        if (state == STATE_RECORDING) {
            var events = engine.tick(info);
            var flightEvent = events & 0x0F;
            var pbEvents = (events >> 4) & 0x0F;
            var turnEvent = (events >> 8) & 0x0F;

            if (flightEvent == FlightDetector.EVENT_START
                || flightEvent == FlightDetector.EVENT_END) {
                if (_session != null) {
                    // lap dev fields take the values held when the lap closes
                    if (_fit != null) {
                        _fit.setLap(engine.turns);
                    }
                    _session.addLap();
                }
                engine.turns.resetLap();
                if (flightEvent == FlightDetector.EVENT_END
                    && engine.detector.longestS > _prevLongest) {
                    _prevLongest = engine.detector.longestS;
                    AlertManager.longestFlight();
                }
            }
            if (pbEvents != 0 && engine.speedMps >= AppSettings.cfg.foilEntryMps) {
                AlertManager.speedPb();
            }
            if (turnEvent >= TurnDetector.EVENT_FLEW) {
                AlertManager.turnOutcome(engine.turns.lastOutcome);
            }
            if (_fit != null) {
                _fit.setRecord(engine.detector.state, engine.tickCount(),
                    FitFields.markerFor(turnEvent, engine.turns.lastKind));
                _fit.updateSession(engine.detector, engine.records, engine.timerS,
                    engine.turns);
            }
        } else {
            // pre-session: surface quality/speed on the start screen
            engine.gpsQuality = info.accuracy != null ? info.accuracy as Number : 0;
            engine.speedMps = info.speed != null ? info.speed as Float : 0.0;
        }
        WatchUi.requestUpdate();
    }

    // ---- session lifecycle ----

    function startSession() as Boolean {
        if (_session != null) {
            return false;
        }
        var opts = {
            :name => "Wingfoil",
            :sport => _sport(),
            :subSport => Activity.SUB_SPORT_GENERIC
        };
        if (AppSettings.accelLogging && (Toybox has :SensorLogging)) {
            try {
                _logger = new SensorLogging.SensorLogger({
                    :accelerometer => {:enabled => true}
                });
                opts[:sensorLogger] = _logger;
            } catch (e) {
                _logger = null;
            }
        }
        _session = ActivityRecording.createSession(opts);
        _fit = new FitFields(_session);
        _session.start();
        state = STATE_RECORDING;
        return true;
    }

    hidden function _sport() as Activity.Sport {
        if (AppSettings.sportChoice == 1 && (Activity has :SPORT_KITESURFING)) {
            return Activity.SPORT_KITESURFING;
        }
        if (AppSettings.sportChoice != 2 && (Activity has :SPORT_WINDSURFING)) {
            return Activity.SPORT_WINDSURFING;
        }
        return Activity.SPORT_GENERIC;
    }

    function togglePause() as Void {
        if (_session == null) {
            return;
        }
        if (state == STATE_RECORDING) {
            _session.stop();
            state = STATE_PAUSED;
        } else if (state == STATE_PAUSED) {
            _session.start();
            state = STATE_RECORDING;
        }
    }

    function finishSave() as Boolean {
        if (_session == null) {
            return false;
        }
        if (state == STATE_RECORDING) {
            _session.stop();
        }
        if (_fit != null) {
            _fit.updateSession(engine.detector, engine.records, engine.timerS, engine.turns);
        }
        var ok = _session.save();
        state = STATE_SAVED;
        _session = null;
        stopGps();
        return ok;
    }

    function finishDiscard() as Void {
        if (_session != null) {
            if (state == STATE_RECORDING) {
                _session.stop();
            }
            _session.discard();
            _session = null;
        }
        state = STATE_IDLE;
    }

    function isRecordingOrPaused() as Boolean {
        return state == STATE_RECORDING || state == STATE_PAUSED;
    }

    // App is being killed mid-session: never lose water time.
    function emergencySave() as Void {
        if (_session != null && isRecordingOrPaused()) {
            finishSave();
        }
    }
}
