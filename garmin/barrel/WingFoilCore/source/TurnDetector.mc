import Toybox.Lang;
import Toybox.Math;

module WingFoilCore {

// Live turn detection + outcome classification (docs/algorithms.md "Turn detection &
// classification" / "Turn outcome"). Watch approximation of lab/src/wingfoil_lab/turns.py:
// one forward pass, bounded work per tick, zero allocation after initialize().
//
// Detection: unwrapped COG is kept in a small ring together with cumulative distance. Each
// tick the ring is scanned backwards for the widest start sample within MAX_DURATION_S whose
// net COG change clears MIN_ANGLE_DEG, whose sweep contains a PEAK_RATE_DEG_S step, and whose
// geometry clears the spatial gate (arc >= MIN_ARC_M, arc/|net rad| >= MIN_RADIUS_M). Geometry
// is only read above COG_SPEED_FLOOR (below it COG is position noise, not a heading) and only
// while flying or within CONTEXT_AFTER_S of a flight.
//
// The trigger opens a SWEEP phase that follows the rotation while it keeps turning
// (CONTINUE_RATE_DEG_S, capped at MAX_DURATION_S from the sweep start), so tack/jibe
// classification sees the whole sweep rather than its first 60 deg. The sweep end confirms the
// turn (EVENT_TURN) and opens the recovery-gated outcome window: it stays open until the rider
// is demonstrably flying again (RECOVER_PCT of entry speed, floored at foilEntry, held
// RECOVER_HOLD_S), capped at LOOKAHEAD_S past the sweep. Evidence collected across the whole
// window: lost-the-foil (speed <= foilExit or submerged), longest stop spell below
// STOP_FLOOR_MPS, barometric submersion. Verdict: submerged or stop > FALL_STOP_S => fell in;
// else any loss => touchdown; else flew through.
//
// The score%/success pair is a *separate*, narrower measurement (turns.py `_build_turn`):
// the speed minimum over the sweep plus MIN_SPEED_LAG_S only. success = score >= SUCCESS_PCT
// AND that minimum stayed above foilExit. A turn can therefore be successful and still be
// classified a touchdown, when the foil was lost later in the recovery-gated window.
class TurnDetector {
    // enums (not const) so they are class-static: TurnDetector.EVENT_TURN etc.
    enum {
        EVENT_NONE = 0,
        EVENT_TURN = 1,        // sweep confirmed, kind known -> controller writes turn_marker
        EVENT_FLEW = 2,        // outcome resolved: flew through
        EVENT_TOUCHDOWN = 3,
        EVENT_FELL = 4
    }
    enum {
        KIND_NONE = 0,
        KIND_TACK = 1,         // matches turn_marker FIT enum (1 = tack)
        KIND_JIBE = 2,
        KIND_TURN = 3,         // wind axis unknown -> generic turn, still counted
        KIND_REJECT = 4        // bear-away / round-up: a course change, not a maneuver
    }
    enum {
        OUTCOME_NONE = 0,
        OUTCOME_FLEW = 1,
        OUTCOME_TOUCHDOWN = 2,
        OUTCOME_FELL = 3
    }
    enum {
        ST_IDLE = 0,
        ST_SWEEP = 1,
        ST_OUTCOME = 2
    }

    // docs/algorithms.md defaults (not user-tunable on the watch)
    const MIN_ANGLE_DEG = 60.0;
    const MAX_DURATION_S = 8.0;
    const PEAK_RATE_DEG_S = 25.0;
    const CONTINUE_RATE_DEG_S = 5.0;
    const COG_SPEED_FLOOR = 2.0;
    const MIN_ARC_M = 12.0;
    const MIN_RADIUS_M = 6.0;
    const CONTEXT_AFTER_S = 3.0;
    const ENTRY_WINDOW_S = 3.0;
    const MIN_SPEED_LAG_S = 2.0;
    const STOP_FLOOR_MPS = 1.0;
    const TOUCHDOWN_MAX_STOP_S = 3.0;
    const FALL_STOP_S = 5.0;
    const LOOKAHEAD_S = 12.0;
    const RECOVER_PCT = 0.70;
    const RECOVER_HOLD_S = 2.0;
    const SUCCESS_PCT = 70;
    const DEG2RAD = 0.017453292;
    const NO_CROSS = 1.0e9;     // "the sweep never passes this axis end"

    // 8 s sweep cap + 3 s entry window + margin, at 1 Hz
    const HIST = 14;

    var state as Number = ST_IDLE;

    // session counters (read by the Turns page, FIT session fields, summary)
    var turnCount as Number = 0;          // tacks + jibes + generic turns (bear-aways excluded)
    var tackCount as Number = 0;
    var jibeCount as Number = 0;
    var rejectedCount as Number = 0;      // bear-aways / round-ups
    var flewCount as Number = 0;
    var touchdownCount as Number = 0;
    var fellCount as Number = 0;
    var successCount as Number = 0;
    var lastKind as Number = KIND_NONE;
    var lastOutcome as Number = OUTCOME_NONE;
    var lastScorePct as Number = 0;
    var bestScorePct as Number = 0;
    var borderlineCount as Number = 0;

    // per-lap (SessionController resets these at every lap boundary)
    var lapTurnCount as Number = 0;
    var lapBestScorePct as Number = 0;

    hidden var _tArr as Array<Float>;
    hidden var _uArr as Array<Float>;
    hidden var _dArr as Array<Float>;
    hidden var _vArr as Array<Float>;
    hidden var _idx as Number = 0;        // newest slot
    hidden var _count as Number = 0;

    hidden var _clockS as Float = 0.0;    // recorded seconds since detector start
    hidden var _distM as Float = 0.0;     // cumulative distance
    hidden var _lastFlyingS as Float = -1000.0;
    hidden var _lastSpeed as Float = 0.0;

    hidden var _haveCog as Boolean = false;
    hidden var _rawCog as Float = 0.0;    // last raw bearing, for unwrapping
    hidden var _u as Float = 0.0;         // unwrapped bearing

    // current candidate / window
    hidden var _startT as Float = 0.0;
    hidden var _startU as Float = 0.0;
    hidden var _endT as Float = 0.0;
    hidden var _endU as Float = 0.0;
    hidden var _entrySpeed as Float = 0.0;
    hidden var _minSpeed as Float = 0.0;
    hidden var _stopRun as Float = 0.0;
    hidden var _stopMax as Float = 0.0;
    hidden var _lostFoil as Boolean = false;
    hidden var _wet as Boolean = false;
    hidden var _recoverHeld as Float = 0.0;

    // Thresholds live in an injected Config (see FlightDetector) — read live every tick, so
    // a wind axis set mid-session classifies every turn detected from then on.
    hidden var _cfg as Config;

    function initialize(cfg as Config) {
        _cfg = cfg;
        _tArr = new Array<Float>[HIST];
        _uArr = new Array<Float>[HIST];
        _dArr = new Array<Float>[HIST];
        _vArr = new Array<Float>[HIST];
        for (var i = 0; i < HIST; i++) {
            _tArr[i] = 0.0;
            _uArr[i] = 0.0;
            _dArr[i] = 0.0;
            _vArr[i] = 0.0;
        }
    }

    // One 1 Hz sample. cogDeg null (or GPS unusable) = no geometry this tick; the outcome
    // window keeps running on speed alone, which is exactly when a fall is being measured.
    function tick(dt as Float, cogDeg as Float?, speedMps as Float, distDelta as Float,
            flying as Boolean, submerged as Boolean) as Number {
        _clockS += dt;
        _distM += distDelta;
        if (flying) {
            _lastFlyingS = _clockS;
        }

        var u = _unwrap(cogDeg, speedMps);
        var event = EVENT_NONE;
        if (state == ST_IDLE) {
            if (u != null) {
                event = _scan(u as Float, speedMps, flying);
            }
        } else if (state == ST_SWEEP) {
            event = _sweep(dt, u, speedMps, submerged);
        } else {
            event = _outcomeTick(dt, speedMps, submerged);
        }
        _lastSpeed = speedMps;
        return event;
    }

    // GPS gap / pause: heading continuity and the detection window are both broken.
    function onGap() as Void {
        _haveCog = false;
        if (state == ST_IDLE) {
            _count = 0;
        }
    }

    function resetLap() as Void {
        lapTurnCount = 0;
        lapBestScorePct = 0;
    }

    function successPct() as Number {
        return turnCount > 0 ? (successCount * 100 / turnCount) : 0;
    }

    // ---- geometry ----

    // Unwrapped bearing in degrees, or null when COG is not readable. Below COG_SPEED_FLOOR
    // the COG is position noise (COAPS caveat): a capsize would otherwise read as a spin.
    hidden function _unwrap(cogDeg as Float?, speedMps as Float) as Float? {
        if (cogDeg == null || speedMps < COG_SPEED_FLOOR) {
            _haveCog = false;
            if (state == ST_IDLE) {
                _count = 0;
            }
            return null;
        }
        var c = cogDeg as Float;
        if (!_haveCog) {
            _haveCog = true;
            _rawCog = c;
            _u = c;
            if (state == ST_IDLE) {
                _count = 0;
            }
            return _u;
        }
        _u += _wrap180(c - _rawCog);
        _rawCog = c;
        return _u;
    }

    hidden function _push(u as Float, speedMps as Float) as Void {
        _idx = (_idx + 1) % HIST;
        _tArr[_idx] = _clockS;
        _uArr[_idx] = u;
        _dArr[_idx] = _distM;
        _vArr[_idx] = speedMps;
        if (_count < HIST) {
            _count++;
        }
    }

    // Backwards scan of the ring: widest qualifying sweep ending at this sample.
    hidden function _scan(u as Float, speedMps as Float, flying as Boolean) as Number {
        _push(u, speedMps);
        if (!flying && _clockS - _lastFlyingS > CONTEXT_AFTER_S) {
            return EVENT_NONE;      // turns while swimming don't count (turnContext)
        }
        var bestNet = 0.0;
        var bestSlot = -1;
        var maxRate = 0.0;
        var k = _idx;
        for (var back = 1; back < _count; back++) {
            var prev = (k - 1 + HIST) % HIST;
            var step = _tArr[k] - _tArr[prev];
            var r = step > 0.0 ? ((_uArr[k] - _uArr[prev]) / step).abs() : 0.0;
            // edge trim (turnContinueRate): the candidate is the actually-turning part only.
            // Without it a straight run after a pivot inflates the arc and walks the
            // spatial gate open — the wallow case.
            if (r < CONTINUE_RATE_DEG_S) {
                break;
            }
            if (r > maxRate) {
                maxRate = r;
            }
            k = prev;
            if (_clockS - _tArr[k] > MAX_DURATION_S) {
                break;
            }
            if (maxRate < PEAK_RATE_DEG_S) {
                continue;
            }
            var net = (u - _uArr[k]).abs();
            if (net < MIN_ANGLE_DEG || net <= bestNet) {
                continue;
            }
            var arc = _distM - _dArr[k];
            if (arc < MIN_ARC_M || arc / (net * DEG2RAD) < MIN_RADIUS_M) {
                continue;       // spatial gate: a heading flip on the spot is not a maneuver
            }
            bestNet = net;
            bestSlot = k;
        }
        if (bestSlot < 0) {
            return EVENT_NONE;
        }
        _openSweep(bestSlot, u, speedMps);
        return EVENT_NONE;      // confirmed when the sweep ends
    }

    hidden function _openSweep(slot as Number, u as Float, speedMps as Float) as Void {
        _startT = _tArr[slot];
        _startU = _uArr[slot];
        _endT = _clockS;
        _endU = u;

        // entry speed: max over the ENTRY_WINDOW_S before the sweep start
        _entrySpeed = _vArr[slot];
        var k = slot;
        for (var back = 0; back < _count; back++) {
            k = (k - 1 + HIST) % HIST;
            if (_startT - _tArr[k] > ENTRY_WINDOW_S) {
                break;
            }
            if (_vArr[k] > _entrySpeed) {
                _entrySpeed = _vArr[k];
            }
        }
        // minimum so far: the samples already swept
        _minSpeed = speedMps;
        k = _idx;
        while (k != slot) {
            if (_vArr[k] < _minSpeed) {
                _minSpeed = _vArr[k];
            }
            k = (k - 1 + HIST) % HIST;
        }

        _stopRun = 0.0;
        _stopMax = 0.0;
        _lostFoil = false;
        _wet = false;
        _recoverHeld = 0.0;
        _count = 0;
        state = ST_SWEEP;
    }

    // Follow the rotation while it is still turning, so classification sees the whole sweep.
    hidden function _sweep(dt as Float, u as Float?, speedMps as Float,
            submerged as Boolean) as Number {
        _track(dt, speedMps, submerged);
        if (u != null) {
            var step = _clockS - _endT;
            var rate = step > 0.0 ? ((u as Float) - _endU) / step : 0.0;
            if (rate.abs() >= CONTINUE_RATE_DEG_S && _clockS - _startT <= MAX_DURATION_S) {
                _endU = u as Float;
                _endT = _clockS;
                return EVENT_NONE;
            }
        }
        var kind = _classify(_startU, _endU);
        if (kind == KIND_REJECT) {
            rejectedCount++;        // bear-away / round-up: real course change, not a maneuver
            state = ST_IDLE;
            _count = 0;
            return EVENT_NONE;
        }
        lastKind = kind;
        turnCount++;
        lapTurnCount++;
        if (kind == KIND_TACK) {
            tackCount++;
        } else if (kind == KIND_JIBE) {
            jibeCount++;
        }
        state = ST_OUTCOME;
        return EVENT_TURN;
    }

    hidden function _outcomeTick(dt as Float, speedMps as Float,
            submerged as Boolean) as Number {
        _track(dt, speedMps, submerged);
        var thr = RECOVER_PCT * _entrySpeed;
        if (thr < _cfg.foilEntryMps) {
            thr = _cfg.foilEntryMps;     // nothing below foil entry is flying
        }
        if (speedMps >= thr) {
            _recoverHeld += dt;
        } else {
            _recoverHeld = 0.0;
        }
        if (_recoverHeld < RECOVER_HOLD_S && _clockS < _endT + LOOKAHEAD_S) {
            return EVENT_NONE;
        }
        return _resolve();
    }

    // Evidence collection, shared by the sweep and the outcome window.
    //
    // Two separate measurements live here and must not be confused (they were, once):
    //   _minSpeed  -- the SCORE channel, minimum over the sweep plus MIN_SPEED_LAG_S only,
    //                 exactly the [start_t, end_t + minSpeedLag] window turns.py._build_turn
    //                 scores. It, and nothing else, decides success.
    //   _lostFoil / _wet / _stopMax -- OUTCOME evidence, collected across the whole
    //                 recovery-gated window (up to end + LOOKAHEAD_S). A touchdown five
    //                 seconds after a cleanly-carried jibe is that jibe's outcome, but it is
    //                 not part of the speed it was scored on.
    hidden function _track(dt as Float, speedMps as Float, submerged as Boolean) as Void {
        if (submerged) {
            _wet = true;
        }
        if (state != ST_OUTCOME || _clockS <= _endT + MIN_SPEED_LAG_S) {
            if (speedMps < _minSpeed) {
                _minSpeed = speedMps;
            }
        }
        if (speedMps <= _cfg.foilExitMps || submerged) {
            _lostFoil = true;
        }
        // both-ends-qualify convention, same clock flight segmentation uses
        if (speedMps < STOP_FLOOR_MPS && _lastSpeed < STOP_FLOOR_MPS) {
            _stopRun += dt;
            if (_stopRun > _stopMax) {
                _stopMax = _stopRun;
            }
        } else {
            _stopRun = 0.0;
        }
    }

    hidden function _resolve() as Number {
        var outcome = OUTCOME_FLEW;
        if (_wet || _stopMax > FALL_STOP_S) {
            outcome = OUTCOME_FELL;
            fellCount++;
        } else if (_lostFoil) {
            outcome = OUTCOME_TOUCHDOWN;
            touchdownCount++;
            if (_stopMax > TOUCHDOWN_MAX_STOP_S) {
                borderlineCount++;
            }
        } else {
            flewCount++;
        }
        var pct = 0;
        if (_entrySpeed > 0.0) {
            pct = (_minSpeed / _entrySpeed * 100.0).toNumber();
            if (pct > 100) {
                pct = 100;
            } else if (pct < 0) {
                pct = 0;
            }
        }
        lastOutcome = outcome;
        lastScorePct = pct;
        if (pct > bestScorePct) {
            bestScorePct = pct;
        }
        if (pct > lapBestScorePct) {
            lapBestScorePct = pct;
        }
        // success is the score pair (turns.py._build_turn), independent of the outcome:
        // score >= turnSuccessPct AND the foil still carried across the scored window.
        if (pct >= SUCCESS_PCT && _minSpeed > _cfg.foilExitMps) {
            successCount++;
        }
        state = ST_IDLE;
        _count = 0;
        if (outcome == OUTCOME_FELL) {
            return EVENT_FELL;
        }
        return outcome == OUTCOME_TOUCHDOWN ? EVENT_TOUCHDOWN : EVENT_FLEW;
    }

    // ---- classification ----

    // Tack when the TWA sweep crosses head-to-wind, jibe when it crosses dead downwind,
    // rejected when it crosses neither (bear-away / round-up). No wind axis => generic turn.
    hidden function _classify(uIn as Float, uOut as Float) as Number {
        var wind = _cfg.windDirection;
        if (wind < 0) {
            return KIND_TURN;
        }
        var twaIn = _wrap180(uIn - wind);
        var twaOut = twaIn + (uOut - uIn);
        var lo = twaIn < twaOut ? twaIn : twaOut;
        var hi = twaIn < twaOut ? twaOut : twaIn;
        var mid = 0.5 * (lo + hi);
        var head = _crossing(lo, hi, 0.0, mid);
        var down = _crossing(lo, hi, 180.0, mid);
        if (head == NO_CROSS && down == NO_CROSS) {
            return KIND_REJECT;
        }
        if (down == NO_CROSS) {
            return KIND_TACK;
        }
        if (head == NO_CROSS) {
            return KIND_JIBE;
        }
        return (head - mid).abs() <= (down - mid).abs() ? KIND_TACK : KIND_JIBE;
    }

    // The value offset + 360k inside [lo, hi] closest to mid, or NO_CROSS when the sweep
    // never passes that axis end.
    hidden function _crossing(lo as Float, hi as Float, offset as Float,
            mid as Float) as Float {
        var k0 = Math.floor((lo - offset) / 360.0);
        var best = NO_CROSS;
        for (var i = 0; i < 3; i++) {
            var v = offset + 360.0 * (k0 + i);
            if (v >= lo && v <= hi
                && (best == NO_CROSS || (v - mid).abs() < (best - mid).abs())) {
                best = v;
            }
        }
        return best;
    }

    hidden function _wrap180(deg as Float) as Float {
        var d = deg;
        while (d > 180.0) {
            d -= 360.0;
        }
        while (d < -180.0) {
            d += 360.0;
        }
        return d;
    }
}

}
