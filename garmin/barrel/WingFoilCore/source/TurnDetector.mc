import Toybox.Lang;
import Toybox.Math;

module WingFoilCore {

// "this sweep never passes that axis end" — module scope so `classifySweep` and the class
// that delegates to it read the same sentinel.
const SWEEP_NO_CROSS = 1.0e9;

// Signed angle difference folded into (-180, 180]. Module scope: three different consumers
// (turn classification, the auto-wind histogram, the tests) need the same fold.
function wrapDeg180(deg as Float) as Float {
    var d = deg;
    while (d > 180.0) {
        d -= 360.0;
    }
    while (d < -180.0) {
        d += 360.0;
    }
    return d;
}

// Tack when the TWA sweep crosses head-to-wind, jibe when it crosses dead downwind, rejected
// when it crosses neither (bear-away / round-up); KIND_TURN when there is no axis.
//
// THE one rule, at module scope, because two callers need it and they must never drift:
// `TurnDetector._classify` names the turn the rider just made, and `AutoWind` names the same
// sweep under BOTH ends of a candidate axis to see which end makes the rider's declared habit
// the majority (docs/algorithms.md "Default turn type"). A second copy of this arithmetic
// would let the prior vote on a different classification than the session reports.
//
// `uIn`/`uOut` are UNWRAPPED bearings: uOut may legitimately sit 200 deg from uIn.
function classifySweep(uIn as Float, uOut as Float, windDeg as Number) as Number {
    if (windDeg < 0) {
        return TurnDetector.KIND_TURN;
    }
    var twaIn = wrapDeg180(uIn - windDeg.toFloat());
    var twaOut = twaIn + (uOut - uIn);
    var lo = twaIn < twaOut ? twaIn : twaOut;
    var hi = twaIn < twaOut ? twaOut : twaIn;
    var mid = 0.5 * (lo + hi);
    var head = sweepCrossing(lo, hi, 0.0, mid);
    var down = sweepCrossing(lo, hi, 180.0, mid);
    if (head == SWEEP_NO_CROSS && down == SWEEP_NO_CROSS) {
        return TurnDetector.KIND_REJECT;
    }
    if (down == SWEEP_NO_CROSS) {
        return TurnDetector.KIND_TACK;
    }
    if (head == SWEEP_NO_CROSS) {
        return TurnDetector.KIND_JIBE;
    }
    return (head - mid).abs() <= (down - mid).abs()
        ? TurnDetector.KIND_TACK : TurnDetector.KIND_JIBE;
}

// The value offset + 360k inside [lo, hi] closest to mid, or SWEEP_NO_CROSS when the sweep
// never passes that axis end.
function sweepCrossing(lo as Float, hi as Float, offset as Float, mid as Float) as Float {
    var k0 = Math.floor((lo - offset) / 360.0);
    var best = SWEEP_NO_CROSS;
    for (var i = 0; i < 3; i++) {
        var v = offset + 360.0 * (k0 + i);
        if (v >= lo && v <= hi
            && (best == SWEEP_NO_CROSS || (v - mid).abs() < (best - mid).abs())) {
            best = v;
        }
    }
    return best;
}

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

    // How long an unowned flight end is judged for, before its evidence is called. The turn
    // window's own cap, reused deliberately: one physical question ("did he stop, and for how
    // long") deserves one set of numbers however the loss started.
    const FLIGHT_END_WINDOW_S = LOOKAHEAD_S;

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
    // CLEAN JIBES (device app 0.9.5). `successCount` counts every successful turn; this counts
    // the ones that were also classified as JIBES, which is the metric the product is named
    // after (docs/presentation.md "Clean jibe", docs/algorithms.md "Glossary"). Kept as its own
    // counter rather than derived, because success and kind are decided at different moments —
    // kind when the sweep closes, success when the outcome window resolves — and the only place
    // both are known is `_resolve()`.
    var cleanJibeCount as Number = 0;
    // Was the turn that just resolved a clean jibe? Published beside `lastOutcome` so a caller
    // that already reacts to a resolved turn can tell the two apart without a second event
    // nibble; false again on the next turn that is not one.
    var lastCleanJibe as Boolean = false;
    var lastKind as Number = KIND_NONE;
    // The geometry of the sweep just confirmed, published at EVENT_TURN: the UNWRAPPED entry
    // bearing and the net rotation (signed, and free to exceed 180 deg). It is what a sweep is
    // as evidence about the wind — AutoWind logs the pair and re-names it under both ends of a
    // candidate axis — and it is the only thing about a resolved turn that outlives it.
    var lastEntryU as Float = 0.0;
    var lastNetDeg as Float = 0.0;
    var lastOutcome as Number = OUTCOME_NONE;
    var lastScorePct as Number = 0;
    var bestScorePct as Number = 0;
    var borderlineCount as Number = 0;

    // Turn streaks (docs/algorithms.md "Turn streaks"). A tally says how the session went;
    // a streak says how it FELT — nine fly-throughs scattered one at a time between swims are
    // not the same session as nine in a row, and the counts alone cannot tell them apart.
    //
    //   dry   how many COUNTED TURNS since he last went in. Extended by flew_through and by
    //         touchdown (borderline included) — a touchdown pumped straight back out does not
    //         end it, because he never swam. Reset by a fall.
    //   flew  the strict run: reset by any touchdown or fall, so bestFlewStreak <=
    //         bestDryStreak always holds.
    //
    // WHAT COUNTS AS A FALL IS NOT ONLY A TURN. A streak claims "he has not been in the water
    // since", and a rider who ventilates the foil on a straight reach and swims has been in
    // the water — so a **flight end** that no turn is judging is classified with the same
    // wet/stopped evidence the turn outcomes use, and breaks the runs on the same terms. Only
    // counted turns ever INCREMENT; straight-line ends can only break. That asymmetry is the
    // whole rule: what the number counts is maneuvers, what ends it is swims.
    //
    // Rejected sweeps — bear-aways and round-ups — still increment nothing, and they need no
    // special case for the falls either: a rejected sweep leaves the state machine idle, so a
    // fall after one arrives as an unowned flight end and breaks the run through exactly the
    // path above. Counting a course change as a maneuver would make a streak depend on how
    // far the rider bore away between two jibes, which is not what the number claims.
    var dryStreak as Number = 0;          // current run, live on the main screen
    var bestDryStreak as Number = 0;      // session best of the same
    var flewStreak as Number = 0;
    var bestFlewStreak as Number = 0;

    // Which tack the rider was ON when he entered the maneuver: port when the wind was
    // crossing his port side (true wind angle > 0), starboard when it was crossing his
    // starboard side. Counted for every COUNTED turn, and only while a wind axis is set —
    // without one there is no side to be on, and both stay 0.
    //
    // It is the asymmetry number: a rider whose jibes work one way round and not the other
    // sees it here and nowhere else, and every counter above averages it away. Derived from
    // the SAME `_wrap180(entry heading - wind)` the tack/jibe classifier already computes, so
    // the two can never disagree about which side of the wind a turn started on.
    var portEntryCount as Number = 0;
    var starboardEntryCount as Number = 0;

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

    // Unowned flight ends — the straight-line half of the streak rule. Same evidence as
    // `_track` collects for a turn, kept separately because the two windows can overlap in
    // time and must never share a stop spell.
    hidden var _wasFlying as Boolean = false;
    hidden var _endOpen as Boolean = false;
    hidden var _endStartS as Float = 0.0;
    hidden var _endWet as Boolean = false;
    hidden var _endStopRun as Float = 0.0;
    hidden var _endStopMax as Float = 0.0;
    hidden var _endTouched as Boolean = false;

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
        // Before the state machine, and on every tick whatever state it is in: the edge this
        // watches for is the one the state machine does not see.
        _flightEndTick(dt, speedMps, flying, submerged);

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
        // An unjudgeable end is dropped, not called a fall: a GPS gap is missing evidence,
        // and "he might have swum" must never break a run the rider actually kept.
        _endOpen = false;
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
        // Published before the verdict, so the geometry is fresh whatever the verdict is.
        lastEntryU = _startU;
        lastNetDeg = _endU - _startU;
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
        countEntrySide(_startU);
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

    // The straight-line half of the streak rule (docs/algorithms.md "Turn streaks", watch
    // approximation). A flight that ends while NO turn is being judged is a loss nothing else
    // explains — a ventilated foil, a dying gust, a caught tip — and if the rider swam, the
    // dry run is over whether or not a maneuver was involved.
    //
    // Ownership is `state == ST_IDLE`, which is the honest live approximation of the engine's
    // `ownedByTurn`: a sweep or an outcome window that is still open IS the turn judging this
    // end, and it will reach its own verdict a few seconds later through `_resolve`. Opening a
    // second window for the same loss would count it twice.
    //
    // It classifies and does nothing else: no counters, no events, no FIT markers. Flight-end
    // tallies are FlightDetector's business; this exists only so a streak cannot claim the
    // rider stayed dry through a swim it never looked at.
    hidden function _flightEndTick(dt as Float, speedMps as Float, flying as Boolean,
            submerged as Boolean) as Void {
        if (_wasFlying && !flying && !_endOpen && state == ST_IDLE) {
            _endOpen = true;
            _endStartS = _clockS;
            _endWet = false;
            _endStopRun = 0.0;
            _endStopMax = 0.0;
            _endTouched = false;
        }
        _wasFlying = flying;
        if (!_endOpen) {
            return;
        }
        if (submerged) {
            _endWet = true;
        }
        if (speedMps < STOP_FLOOR_MPS) {
            _endTouched = true;
            // both-ends-qualify, the same clock flight segmentation and `_track` use
            if (_lastSpeed < STOP_FLOOR_MPS) {
                _endStopRun += dt;
                if (_endStopRun > _endStopMax) {
                    _endStopMax = _endStopRun;
                }
            }
        } else {
            _endStopRun = 0.0;
        }
        // Closed by recovery (he is flying again) or by the window running out. Either way the
        // evidence is called with what there is, exactly as the turn window does.
        if (flying || _clockS - _endStartS >= FLIGHT_END_WINDOW_S) {
            _closeFlightEnd();
        }
    }

    // Same ladder as a turn outcome, minus the leaf a flight end cannot have: it is already
    // off the foil, so there is no "flew through".
    hidden function _closeFlightEnd() as Void {
        _endOpen = false;
        if (_endWet || _endStopMax > FALL_STOP_S) {
            dryStreak = 0;          // he swam
            flewStreak = 0;
        } else if (_endTouched) {
            flewStreak = 0;         // touched down: dry survives, the strict run does not
        }
        // else: a glide-out. He came off the foil and kept making way — nothing broke.
    }

    hidden function _resolve() as Number {
        var outcome = OUTCOME_FLEW;
        if (_wet || _stopMax > FALL_STOP_S) {
            outcome = OUTCOME_FELL;
            fellCount++;
            dryStreak = 0;          // he swam: both runs end here
            flewStreak = 0;
        } else if (_lostFoil) {
            outcome = OUTCOME_TOUCHDOWN;
            touchdownCount++;
            if (_stopMax > TOUCHDOWN_MAX_STOP_S) {
                borderlineCount++;
            }
            dryStreak++;            // dry survives a touchdown; flew does not
            flewStreak = 0;
        } else {
            flewCount++;
            dryStreak++;
            flewStreak++;
        }
        if (dryStreak > bestDryStreak) {
            bestDryStreak = dryStreak;
        }
        if (flewStreak > bestFlewStreak) {
            bestFlewStreak = flewStreak;
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
        lastCleanJibe = false;
        if (pct >= SUCCESS_PCT && _minSpeed > _cfg.foilExitMps) {
            successCount++;
            // ...and a successful turn that was named a JIBE is a clean jibe. `lastKind` is
            // still this turn's: the watch does not re-detect during an outcome window, so
            // nothing can have overwritten it between the sweep closing and here.
            if (lastKind == KIND_JIBE) {
                cleanJibeCount++;
                lastCleanJibe = true;
            }
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
    // The arithmetic lives at module scope (`classifySweep`) because AutoWind's default-turn-
    // type prior has to name the same sweeps under the other axis end; one rule, two callers.
    hidden function _classify(uIn as Float, uOut as Float) as Number {
        return classifySweep(uIn, uOut, _cfg.windDirection);
    }

    // The ONE-SHOT BACKFILL (docs/algorithms.md "Watch approximation: auto wind").
    //
    // The watch never re-runs classification: a turn is named with the wind in effect when it
    // happened, and a manual axis set at minute forty leaves the first forty minutes generic.
    // Auto wind is the single deliberate exception, and only at its FIRST lock: the estimator
    // needs ~500 m of flying before it can speak, and without this pass the session's tack /
    // jibe / port / starboard counts would start from zero at that moment even though the
    // rider's first reaches are exactly the evidence the axis was estimated FROM. It runs once
    // per session (SessionController holds the flag) over the sweep log AutoWind kept.
    //
    // Deliberately narrow — it only ADDS the splits the counters were missing:
    //   * `turnCount`, the outcome tallies, the streaks and the scores are untouched. Those
    //     were real observations made at the time and are not re-judged.
    //   * a logged sweep that comes out KIND_REJECT under the new axis (a bear-away) stays
    //     counted as the generic turn it was. Retracting it would move turnCount, successPct
    //     and every streak that spanned it, i.e. re-judge outcomes on hindsight evidence.
    //   * `cleanJibeCount` is NOT backfilled. The sweep log carries geometry only (entry
    //     bearing and net rotation, all AutoWind needs to re-name an axis), and it is written
    //     when the sweep CLOSES — before the outcome window has resolved, so at that moment
    //     nothing in it knows whether the turn was carried. Backfilling the split therefore
    //     turns pre-lock turns into jibes without turning any of them into clean jibes, and
    //     the watch's CPH under-reads for the first few minutes of an auto-wind session.
    //     Documented in docs/algorithms.md's watch-divergence list rather than fixed with a
    //     third parallel array: it is a handful of turns at the very start of a session, and
    //     it errs the way every other watch divergence errs — conservative.
    // So after the backfill `tackCount + jibeCount <= turnCount`, with the difference being
    // the sweeps that turned out to be course changes.
    function backfillWindSplit(entryDeg as Array<Number>, netDeg as Array<Number>,
            n as Number) as Void {
        var wind = _cfg.windDirection;
        if (wind < 0) {
            return;
        }
        for (var i = 0; i < n; i++) {
            var uIn = entryDeg[i].toFloat();
            var kind = classifySweep(uIn, uIn + netDeg[i].toFloat(), wind);
            if (kind == KIND_TACK) {
                tackCount++;
            } else if (kind == KIND_JIBE) {
                jibeCount++;
            } else {
                continue;           // a bear-away under this axis: it stays a generic turn
            }
            countEntrySide(uIn);
        }
    }

    // Which side the wind was crossing at the ENTRY heading, counted once per counted turn.
    // TWA > 0 means the heading sits clockwise of the wind's own bearing, i.e. the wind
    // arrives over the port side: port tack. Exactly 0 (dead head-to-wind on entry) is not a
    // side and is not counted — it is also not a state a foiler holds.
    // Public so the layout tests and the FIT layer can reason about the same rule.
    function countEntrySide(entryU as Float) as Void {
        var wind = _cfg.windDirection;
        if (wind < 0) {
            return;             // no axis: there is no side, and 0/0 is the honest answer
        }
        var twa = _wrap180(entryU - wind.toFloat());
        if (twa > 0.0) {
            portEntryCount++;
        } else if (twa < 0.0) {
            starboardEntryCount++;
        }
    }

    hidden function _wrap180(deg as Float) as Float {
        return wrapDeg180(deg);
    }
}

}
