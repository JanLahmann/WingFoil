import Toybox.Lang;

// Foil-flight hysteresis state machine (docs/algorithms.md "Flight detection").
// Speed >= entry sustained entryHold s => ON_FOIL (backdated to first qualifying sample);
// speed <= exit sustained exitHold s => OFF_FOIL (backdated); flights < minFlight discarded.
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
    hidden var _exitAccum as Float = 0.0;
    hidden var _exitDistAccum as Float = 0.0;
    hidden var _confirmed as Boolean = false;   // current flight reached minFlight (lap emitted)

    // dt in seconds, distDelta meters moved since last tick.
    function tick(dt as Float, speedMps as Float, distDelta as Float) as Number {
        if (state == STATE_OFF) {
            if (speedMps >= AppSettings.foilEntryMps) {
                _entryAccum += dt;
                if (_entryAccum >= AppSettings.entryHoldS) {
                    state = STATE_ON;
                    _confirmed = false;
                    // backdate: the entry-hold window was already flying
                    currentFlightS = _entryAccum;
                    currentFlightM = 0.0;   // distance backdating not tracked; phone corrects
                    foilTimeS += _entryAccum;
                    _entryAccum = 0.0;
                    _exitAccum = 0.0;
                }
            } else {
                _entryAccum = 0.0;
            }
            return EVENT_NONE;
        }

        // STATE_ON
        foilTimeS += dt;
        currentFlightS += dt;
        currentFlightM += distDelta;
        var event = EVENT_NONE;

        // confirm only while cleanly flying (_exitAccum == 0), so EVENT_START can never
        // collide with EVENT_END in one tick and laps stay strictly alternating
        if (!_confirmed && _exitAccum == 0.0 && currentFlightS >= AppSettings.minFlightS) {
            _confirmed = true;
            flightCount++;
            event = EVENT_START;
        }

        if (speedMps <= AppSettings.foilExitMps) {
            _exitAccum += dt;
            _exitDistAccum += distDelta;
            if (_exitAccum >= AppSettings.exitHoldS) {
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
                _exitAccum = 0.0;
                _exitDistAccum = 0.0;
            }
        } else {
            _exitAccum = 0.0;
            _exitDistAccum = 0.0;
        }
        return event;
    }
}
