import Toybox.Lang;

module WingFoilCore {

// Foil-flight hysteresis state machine (docs/algorithms.md "Flight detection").
// Speed >= entry sustained entryHold s => ON_FOIL (backdated to first qualifying sample);
// speed <= exit sustained exitHold s => OFF_FOIL (backdated); flights < minFlight discarded.
//
// Both-ends-qualify, exactly as lab/src/wingfoil_lab/flight.py `_flight_spans`: an interval
// counts toward a hold only when BOTH of its end samples qualify. The first qualifying
// sample opens the run with the accumulator at zero, so the hold measures the time from
// that sample -- the dt spanning the last NON-qualifying sample is never part of it. At
// 1 Hz that means entryHold + 1 qualifying samples to confirm, and the backdated flight
// time never includes an interval the rider was not flying.
// Lap semantics (W1): EVENT_START fires when a flight reaches minFlight (lap boundary is up to
// minFlight late — phone analysis is authoritative on exact flight edges).
class FlightDetector {
    // enums (not const) so they are class-static: FlightDetector.STATE_ON etc.
    enum {
        STATE_OFF = 0,
        STATE_ON = 2      // matches foil_state FIT enum (2 = flying)
    }
    enum {
        EVENT_NONE = 0,
        EVENT_START = 1,  // flight confirmed (>= minFlight) -> controller adds lap
        EVENT_END = 2     // confirmed flight ended -> controller adds lap
    }

    var state as Number = STATE_OFF;
    var flightCount as Number = 0;
    var foilTimeS as Float = 0.0;
    var longestS as Float = 0.0;
    var longestM as Float = 0.0;
    var currentFlightS as Float = 0.0;   // 0 when off foil
    var currentFlightM as Float = 0.0;

    hidden var _entryAccum as Float = 0.0;
    hidden var _entryRun as Boolean = false;    // the PREVIOUS sample cleared foilEntry
    hidden var _exitAccum as Float = 0.0;
    hidden var _exitRun as Boolean = false;     // the PREVIOUS sample was at/below foilExit
    hidden var _exitDistAccum as Float = 0.0;
    hidden var _confirmed as Boolean = false;   // current flight reached minFlight (lap emitted)

    // Thresholds live in an injected Config so the same detector serves the device app and
    // the data field; each supplies its own settings source. Read live every tick, so a
    // settings change during a session takes effect immediately (unchanged behaviour).
    hidden var _cfg as Config;

    function initialize(cfg as Config) {
        _cfg = cfg;
    }

    // dt in seconds, distDelta meters moved since last tick.
    function tick(dt as Float, speedMps as Float, distDelta as Float) as Number {
        if (state == STATE_OFF) {
            if (speedMps >= _cfg.foilEntryMps) {
                if (_entryRun) {
                    _entryAccum += dt;          // both ends of this interval qualify
                } else {
                    _entryRun = true;           // first qualifying sample: the run starts here
                    _entryAccum = 0.0;
                }
                if (_entryAccum >= _cfg.entryHoldS) {
                    state = STATE_ON;
                    _confirmed = false;
                    // backdate: the entry-hold window was already flying
                    currentFlightS = _entryAccum;
                    currentFlightM = 0.0;   // distance backdating not tracked; phone corrects
                    foilTimeS += _entryAccum;
                    _entryAccum = 0.0;
                    _entryRun = false;
                    _exitAccum = 0.0;
                    _exitRun = false;
                }
            } else {
                _entryAccum = 0.0;
                _entryRun = false;
            }
            return EVENT_NONE;
        }

        // STATE_ON
        foilTimeS += dt;
        currentFlightS += dt;
        currentFlightM += distDelta;
        var event = EVENT_NONE;

        // confirm only while cleanly flying (no exit run open), so EVENT_START can never
        // collide with EVENT_END in one tick and laps stay strictly alternating
        if (!_confirmed && !_exitRun && currentFlightS >= _cfg.minFlightS) {
            _confirmed = true;
            flightCount++;
            event = EVENT_START;
        }

        if (speedMps <= _cfg.foilExitMps) {
            if (_exitRun) {
                _exitAccum += dt;               // both ends of this interval qualify
                _exitDistAccum += distDelta;
            } else {
                _exitRun = true;                // first sub-exit sample: the end is backdated here
                _exitAccum = 0.0;
                _exitDistAccum = 0.0;
            }
            if (_exitAccum >= _cfg.exitHoldS) {
                // backdate the end to the first sub-exit sample
                foilTimeS -= _exitAccum;
                currentFlightS -= _exitAccum;
                currentFlightM -= _exitDistAccum;
                if (_confirmed) {
                    if (currentFlightS > longestS) {
                        longestS = currentFlightS;
                    }
                    if (currentFlightM > longestM) {
                        longestM = currentFlightM;
                    }
                    event = EVENT_END;
                } else {
                    // too short: never counted, remove its time entirely
                    foilTimeS -= currentFlightS;
                }
                state = STATE_OFF;
                currentFlightS = 0.0;
                currentFlightM = 0.0;
                _entryAccum = 0.0;
                _entryRun = false;      // this sample is sub-exit: it cannot open an entry run
                _exitAccum = 0.0;
                _exitRun = false;
                _exitDistAccum = 0.0;
            }
        } else {
            _exitAccum = 0.0;
            _exitRun = false;
            _exitDistAccum = 0.0;
        }
        return event;
    }
}

}
