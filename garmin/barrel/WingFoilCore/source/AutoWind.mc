import Toybox.Lang;
import Toybox.Math;

module WingFoilCore {

// `default_turn_type` vocabulary — the watch mirror of lab/src/wingfoil_lab/wind.py's
// JIBES / TACKS / BALANCED, in the order the GCM list setting uses.
enum {
    TURN_TYPE_JIBES = 0,        // the default: a wingfoiler jibes far more than he tacks
    TURN_TYPE_TACKS = 1,
    TURN_TYPE_BALANCED = 2      // prior off: the no-go cone decides alone
}

// LIVE WIND-AXIS ESTIMATION ON THE WATCH — the approximation of
// lab/src/wingfoil_lab/wind.py (docs/algorithms.md "Wind axis estimation" and "Watch
// approximation: auto wind").
//
// The engine sees a whole session at once, holds every foiling sample, and answers once. The
// watch has to answer while the rider is still on the water, in O(1) per tick and with every
// array allocated at construction. What it does with that budget is the SAME chain:
//
//   1. accumulate a distance-weighted circular histogram of course over ground, 36 bins of
//      10 deg, only while the FlightDetector says ON and the Doppler speed clears
//      MIN_SPEED_MPS (below that COG is position noise, not a heading — the COAPS caveat the
//      engine's `min_speed_mps` exists for). Weight = speed x dt, i.e. the distance flown in
//      that tick, which is what the engine weights its samples by too.
//   2. every EVAL_PERIOD_S, once MIN_DISTANCE_M of flying has accumulated: smooth the
//      histogram with a +-SMOOTH_HALF_BINS circular box (= the engine's 20 deg), take the two
//      dominant lobes, refine each as the mass-weighted circular mean of its +-LOBE_HALF_BINS
//      window, and call the bisector the axis.
//   3. resolve the 180 deg ambiguity by NO-GO-CONE ASYMMETRY: of the two axis ends, the one
//      whose +-CONE_HALF_DEG cone holds (almost) no distance is where the wind blows from.
//   4. where that margin is weak, let the rider's declared DEFAULT TURN TYPE break the tie,
//      on exactly the engine's blend (`e = eCone + w * mTurn`), voting on the sweep log below.
//   5. adopt the answer when `axisConfidence x certainty >= MIN_CONFIDENCE`.
//
// THE THREE PLACES IT DELIBERATELY DIFFERS FROM THE ENGINE, all forced by the platform:
//
//   a. It has bins, not samples. Lobe refinement and cone mass are computed over BIN CENTRES,
//      so both carry up to +-5 deg of quantization the engine does not. Measured cost on the
//      two ciq fixtures: under 2 deg (the residual is dominated by (c), not by this).
//   b. It is INCREMENTAL and one-way. A sample joins the histogram and never leaves, so the
//      estimate is the whole session so far — there is no sliding window and no way to forget
//      a wind shift. That is the honest trade: a foiling session is an hour or two at one
//      spot, and a histogram that forgets would also forget the upwind work the cone call
//      needs. A real shift shows up as the estimate walking, and HYSTERESIS_DEG bounds how
//      far it may walk before the display follows.
//   c. Once adopted, the direction only moves on a re-evaluation at least HYSTERESIS_DEG
//      away. The estimate keeps converging underneath (on 2026-08-07 it walks 23 -> 35 deg
//      over the session) but the adopted value stays put, because a wind readout that creeps
//      by two degrees a minute is worse than one that is a few degrees off. So the adopted
//      value may lag the converged estimate by up to HYSTERESIS_DEG BY CONSTRUCTION, which is
//      exactly why the acceptance band against the engine is +-20 deg and not +-5.
//
// And one addition the engine has no need for: the lock is CONFIRMED. Two consecutive
// qualifying evaluations must agree within CONFIRM_DEG before the first direction is adopted.
// The engine can afford to answer once from complete evidence; the watch's first answer costs
// a vibe, the whole session's tack/jibe split (the one-shot backfill in
// `TurnDetector.backfillWindSplit`) and every turn named from then on — so it does not commit
// on one minute of it. Cost: one extra EVAL_PERIOD_S before the first lock.
class AutoWind {
    // Events, returned by `tick` (class-static, like TurnDetector's).
    enum {
        EV_NONE = 0,
        EV_LOCK = 1,        // first adoption this session: vibe + the one-shot backfill
        EV_UPDATE = 2       // the axis moved >= HYSTERESIS_DEG (or flipped)
    }

    // ---- histogram (engine: bin_deg 10, smooth_deg 20, lobe_half_width_deg 25) ----
    const BINS = 36;
    const BIN_DEG = 10.0;
    const SMOOTH_HALF_BINS = 2;         // +-2 bins = +-20 deg
    const LOBE_HALF_BINS = 2;           // +-2 bins = +-25 deg of window, engine's lobe width

    // ---- gates (engine: min_speed_mps 2, min_distance_m 500) ----
    const MIN_SPEED_MPS = 2.0;
    // 500 m of FLYING distance is the engine's own floor, kept rather than re-tuned so the
    // watch and the phone refuse on the same evidence. At a wingfoil's 8 m/s it is a bit over
    // a minute in the air and typically two or three reaches — the least that can show two
    // lobes at all. Below it there is no estimate, not a weak one.
    const MIN_DISTANCE_M = 500.0;
    const EVAL_PERIOD_S = 60.0;

    // ---- axis gates (engine `_dominant_lobes` / `_axis_confidence`) ----
    const MIN_LOBE_SEP_DEG = 60.0;      // closer than this and the two modes are one lobe
    const MAX_LOBE_SEP_DEG = 179.0;     // exactly opposed lobes: the bisector is degenerate
    const SEP_FULL_DEG = 20.0;          // separation factor saturates min_sep + 20
    const MASS_FLOOR = 0.2;             // mass factor: 0.2 -> 0, 0.6 -> 1
    const MASS_SPAN = 0.4;
    const BALANCE_FULL = 0.5;           // balance factor: weaker/stronger, 0.5 -> 1

    // ---- the 180 deg call (engine `_resolve_180` + the prior) ----
    const CONE_HALF_DEG = 45.0;
    const MIN_CONE_MASS = 0.01;         // both cones emptier than this: direction unresolved
    const FULL_MARGIN = 0.4;            // cone asymmetry at/above which the call is certain
    const TURN_PRIOR_WEIGHT = 0.5;      // cap on the declared habit's signed contribution

    // ---- adoption ----
    const MIN_CONFIDENCE = 0.5;         // engine `min_confidence`: below it turns stay generic
    const CONFIRM_DEG = 20.0;           // watch-only: two evaluations must agree to lock
    const HYSTERESIS_DEG = 15.0;        // adopted direction moves only this far or further

    // The sweep log the default-turn-type prior votes on, and the one-shot backfill replays.
    // Capped exactly like SessionHistory's turn log and with the same rule: the OLDEST entry
    // falls off, because a full log means a long session and the recent turns are the ones the
    // current axis has to explain.
    const SWEEP_MAX = 64;

    // ---- live state ----
    var dirDeg as Number = -1;          // adopted estimate, wind FROM, -1 = nothing adopted
    var confidence as Float = 0.0;      // axisConfidence x certainty of the adopted call
    var distanceM as Float = 0.0;       // flying distance in the histogram
    var evalCount as Number = 0;        // evaluations that got past the distance floor
    var sweepCount as Number = 0;
    // The rider's declared habit, mirrored from the GCM setting (or set by a test).
    var defaultTurnType as Number = TURN_TYPE_JIBES;

    // Diagnostics from the last evaluation — read by the tests and worth a log line.
    var lastAxisConf as Float = 0.0;
    var lastMargin as Float = 0.0;
    var lastSepDeg as Float = 0.0;
    var lastPriorFlipped as Boolean = false;
    var lastPriorVotes as Number = 0;

    hidden var _hist as Array<Float>;
    hidden var _smooth as Array<Float>;
    hidden var _sweepIn as Array<Number>;    // unwrapped entry bearing, 0-359
    hidden var _sweepNet as Array<Number>;   // signed net rotation, may exceed +-180
    hidden var _sinceEvalS as Float = 0.0;
    hidden var _pendingDeg as Float = -1.0;  // candidate awaiting its second agreeing vote

    function initialize() {
        _hist = new Array<Float>[BINS];
        _smooth = new Array<Float>[BINS];
        for (var i = 0; i < BINS; i++) {
            _hist[i] = 0.0;
            _smooth[i] = 0.0;
        }
        _sweepIn = new Array<Number>[SWEEP_MAX];
        _sweepNet = new Array<Number>[SWEEP_MAX];
        for (var i = 0; i < SWEEP_MAX; i++) {
            _sweepIn[i] = 0;
            _sweepNet[i] = 0;
        }
    }

    // One 1 Hz sample. `cogDeg` null (or below the speed floor, or not flying) contributes no
    // geometry; the evaluation clock runs regardless, because it measures wall time and not
    // evidence. Returns EV_NONE / EV_LOCK / EV_UPDATE.
    function tick(dt as Float, cogDeg as Float?, speedMps as Float,
            flying as Boolean) as Number {
        if (flying && cogDeg != null && speedMps >= MIN_SPEED_MPS) {
            var c = cogDeg as Float;
            var i = (Math.floor(_norm360(c) / BIN_DEG).toNumber()) % BINS;
            var w = speedMps * dt;
            _hist[i] += w;
            distanceM += w;
        }
        _sinceEvalS += dt;
        if (_sinceEvalS < EVAL_PERIOD_S) {
            return EV_NONE;
        }
        _sinceEvalS = 0.0;
        return evaluate();
    }

    // A confirmed sweep, logged for the prior and the one-shot backfill. `entryU` and `netDeg`
    // are TurnDetector's `lastEntryU` / `lastNetDeg`: the unwrapped entry bearing and the
    // signed rotation, which is what a sweep is as evidence about the wind.
    function logSweep(entryU as Float, netDeg as Float) as Void {
        if (sweepCount >= SWEEP_MAX) {
            for (var i = 1; i < SWEEP_MAX; i++) {
                _sweepIn[i - 1] = _sweepIn[i];
                _sweepNet[i - 1] = _sweepNet[i];
            }
            sweepCount = SWEEP_MAX - 1;
        }
        _sweepIn[sweepCount] = _norm360(entryU).toNumber();
        _sweepNet[sweepCount] = netDeg.toNumber();
        sweepCount++;
    }

    // The sweep log, for `TurnDetector.backfillWindSplit`. Handed out rather than copied:
    // the backfill reads it once and the arrays are fixed for the life of the session.
    function sweepEntries() as Array<Number> { return _sweepIn; }
    function sweepNets() as Array<Number> { return _sweepNet; }

    // ---- evaluation ----

    // One pass over the histogram. Returns EV_LOCK / EV_UPDATE when the adopted direction
    // changed, EV_NONE otherwise. Public so a test can drive it without waiting 60 ticks.
    function evaluate() as Number {
        if (distanceM < MIN_DISTANCE_M) {
            return EV_NONE;
        }
        evalCount++;
        _smoothHistogram();

        var first = _peakBin(-1);
        if (first < 0) {
            return _unconfirmed();
        }
        var second = _peakBin(first);
        if (second < 0) {
            return _unconfirmed();
        }

        var lobe0 = _refineLobe(first);
        var lobe1 = _refineLobe(second);
        var mass0 = _lobeMass(first) / distanceM;
        var mass1 = _lobeMass(second) / distanceM;
        var sep = wrapDeg180(lobe1 - lobe0).abs();
        lastSepDeg = sep;
        if (sep > MAX_LOBE_SEP_DEG) {
            return _unconfirmed();      // pure beam-reach out-and-back: no bisector can help
        }

        var bisector = _bisect(lobe0, lobe1);
        var axisConf = _axisConfidence(mass0, mass1, sep);
        lastAxisConf = axisConf;

        // The no-go-cone call, then the rider's habit where it is weak.
        var coneDir = _coneDirection(bisector);
        var eCone = FULL_MARGIN > 0.0 ? _clip01(lastMargin / FULL_MARGIN) : 1.0;
        var certainty = eCone;
        var dir = coneDir;
        lastPriorFlipped = false;
        lastPriorVotes = 0;
        if (defaultTurnType != TURN_TYPE_BALANCED && eCone < 1.0) {
            var blended = _turnTypePrior(coneDir, eCone);
            certainty = blended;
            if (lastPriorFlipped) {
                dir = _norm360(coneDir + 180.0);
            }
        }

        var conf = axisConf * certainty;
        if (conf < MIN_CONFIDENCE) {
            return _unconfirmed();
        }
        return _adopt(dir, conf);
    }

    // A qualifying evaluation that failed a gate also clears the pending candidate: the two
    // votes a lock needs must be CONSECUTIVE, or "confirmed" would only mean "twice, ever".
    hidden function _unconfirmed() as Number {
        _pendingDeg = -1.0;
        return EV_NONE;
    }

    // Adoption, with the confirmation on the way in and the hysteresis afterwards.
    hidden function _adopt(dir as Float, conf as Float) as Number {
        if (dirDeg < 0) {
            if (_pendingDeg < 0.0 || wrapDeg180(dir - _pendingDeg).abs() > CONFIRM_DEG) {
                _pendingDeg = dir;      // first vote: wait one more evaluation
                return EV_NONE;
            }
            dirDeg = _norm360(dir).toNumber() % 360;
            confidence = conf;
            _pendingDeg = -1.0;
            return EV_LOCK;
        }
        if (wrapDeg180(dir - dirDeg.toFloat()).abs() < HYSTERESIS_DEG) {
            return EV_NONE;             // the estimate moved, the readout does not
        }
        dirDeg = _norm360(dir).toNumber() % 360;
        confidence = conf;
        return EV_UPDATE;
    }

    // Circular box smoothing, +-SMOOTH_HALF_BINS. Into the pre-allocated scratch, never a
    // fresh array: this runs once a minute for the life of the session.
    hidden function _smoothHistogram() as Void {
        var n = 2 * SMOOTH_HALF_BINS + 1;
        for (var i = 0; i < BINS; i++) {
            var acc = 0.0;
            for (var k = -SMOOTH_HALF_BINS; k <= SMOOTH_HALF_BINS; k++) {
                acc += _hist[(i + k + BINS) % BINS];
            }
            _smooth[i] = acc / n;
        }
    }

    // The fullest smoothed bin, or the fullest at least MIN_LOBE_SEP_DEG from `awayFrom`
    // (-1 = no constraint). -1 when there is no such bin with any mass in it.
    hidden function _peakBin(awayFrom as Number) as Number {
        var best = -1;
        var bestV = 0.0;
        var ref = awayFrom < 0 ? 0.0 : _binCenter(awayFrom);
        for (var i = 0; i < BINS; i++) {
            if (awayFrom >= 0
                && wrapDeg180(_binCenter(i) - ref).abs() < MIN_LOBE_SEP_DEG) {
                continue;
            }
            if (_smooth[i] > bestV) {
                bestV = _smooth[i];
                best = i;
            }
        }
        return best;
    }

    // Mass-weighted circular mean of the RAW bins inside the lobe window — the watch's
    // bin-resolution stand-in for the engine's weighted circular mean over the samples in a
    // +-25 deg window. The peak bin is found on the smoothed histogram, the lobe is placed on
    // the unsmoothed one, exactly as the engine orders those two steps.
    hidden function _refineLobe(idx as Number) as Float {
        var sx = 0.0;
        var sy = 0.0;
        for (var k = -LOBE_HALF_BINS; k <= LOBE_HALF_BINS; k++) {
            var j = (idx + k + BINS) % BINS;
            var r = _binCenter(j) * 0.017453292;
            sx += _hist[j] * Math.cos(r);
            sy += _hist[j] * Math.sin(r);
        }
        if (sx == 0.0 && sy == 0.0) {
            return _binCenter(idx);
        }
        return _norm360(Math.atan2(sy, sx) * 57.29578);
    }

    hidden function _lobeMass(idx as Number) as Float {
        var m = 0.0;
        for (var k = -LOBE_HALF_BINS; k <= LOBE_HALF_BINS; k++) {
            m += _hist[(idx + k + BINS) % BINS];
        }
        return m;
    }

    // The axis line: the circular mean of the two lobes, i.e. their bisector.
    hidden function _bisect(a as Float, b as Float) as Float {
        var ra = a * 0.017453292;
        var rb = b * 0.017453292;
        return _norm360(Math.atan2(Math.sin(ra) + Math.sin(rb),
            Math.cos(ra) + Math.cos(rb)) * 57.29578);
    }

    // Product of three [0,1] factors, the engine's `_axis_confidence` verbatim:
    //   mass    share of flying distance inside the two lobe windows (0.2 -> 0, 0.6 -> 1)
    //   balance weaker lobe over stronger (0 -> 0, 0.5 -> 1); one-sided sessions score low
    //   sep     distinctness of the two modes (60 deg -> 0, 80 deg -> 1)
    hidden function _axisConfidence(m0 as Float, m1 as Float, sep as Float) as Float {
        var lo = m0 < m1 ? m0 : m1;
        var hi = m0 < m1 ? m1 : m0;
        var balance = hi > 0.0 ? lo / hi : 0.0;
        return _clip01((m0 + m1 - MASS_FLOOR) / MASS_SPAN)
            * _clip01(balance / BALANCE_FULL)
            * _clip01((sep - MIN_LOBE_SEP_DEG) / SEP_FULL_DEG);
    }

    // The no-go zone: a rider can hold any downwind course but none within ~45 deg of the
    // wind, so of the two axis ends the emptier cone is the one the wind blows FROM. Leaves
    // the relative asymmetry in `lastMargin` (0 = both cones equally full, or both empty,
    // which makes the direction a coin flip and the axis line still usable).
    hidden function _coneDirection(bisector as Float) as Float {
        var ma = 0.0;
        var mb = 0.0;
        for (var i = 0; i < BINS; i++) {
            var c = _binCenter(i);
            if (wrapDeg180(c - bisector).abs() <= CONE_HALF_DEG) {
                ma += _hist[i];
            } else if (wrapDeg180(c - bisector - 180.0).abs() <= CONE_HALF_DEG) {
                mb += _hist[i];
            }
        }
        ma /= distanceM;
        mb /= distanceM;
        if (ma + mb < MIN_CONE_MASS) {
            lastMargin = 0.0;
            return _norm360(bisector);
        }
        lastMargin = (ma - mb).abs() / (ma + mb);
        return _norm360(ma < mb ? bisector : bisector + 180.0);
    }

    // The default-turn-type prior (docs/algorithms.md "Default turn type"), the engine's
    // `_blend` verbatim on the watch's own sweep log.
    //
    // Flipping the wind 180 deg swaps every jibe and tack, so the rider's declared habit is
    // evidence about ORIENTATION and nothing else. Only sweeps that come out tack-or-jibe
    // under BOTH ends vote — a bear-away is not evidence about the wind, and a sweep that is a
    // maneuver under one end only would let the prior pick its own electorate.
    //
    //   mTurn = (nDefault - nOther) / votes, signed towards the cone's own pick
    //   e     = eCone + TURN_PRIOR_WEIGHT * mTurn ; the cone's end while e >= 0
    // Returns the certainty (clip01(|e|)) and sets `lastPriorFlipped` / `lastPriorVotes`.
    hidden function _turnTypePrior(coneDir as Float, eCone as Float) as Float {
        var wanted = defaultTurnType == TURN_TYPE_JIBES
            ? TurnDetector.KIND_JIBE : TurnDetector.KIND_TACK;
        var here = _norm360(coneDir).toNumber() % 360;
        var there = _norm360(coneDir + 180.0).toNumber() % 360;
        var nDefault = 0;
        var nOther = 0;
        for (var i = 0; i < sweepCount; i++) {
            var uIn = _sweepIn[i].toFloat();
            var uOut = uIn + _sweepNet[i].toFloat();
            var kHere = classifySweep(uIn, uOut, here);
            var kThere = classifySweep(uIn, uOut, there);
            if ((kHere != TurnDetector.KIND_TACK && kHere != TurnDetector.KIND_JIBE)
                || (kThere != TurnDetector.KIND_TACK && kThere != TurnDetector.KIND_JIBE)) {
                continue;
            }
            if (kHere == wanted) {
                nDefault++;
            } else {
                nOther++;
            }
        }
        lastPriorVotes = nDefault + nOther;
        if (lastPriorVotes == 0) {
            return eCone;               // no electorate: the cone acts alone, to the bit
        }
        var mTurn = (nDefault - nOther).toFloat() / lastPriorVotes.toFloat();
        var e = eCone + TURN_PRIOR_WEIGHT * mTurn;
        lastPriorFlipped = e < 0.0;
        return _clip01(e.abs());
    }

    // ---- small maths ----

    hidden function _binCenter(i as Number) as Float {
        return (i + 0.5) * BIN_DEG;
    }

    hidden function _norm360(deg as Float) as Float {
        var d = deg;
        while (d < 0.0) {
            d += 360.0;
        }
        while (d >= 360.0) {
            d -= 360.0;
        }
        return d;
    }

    hidden function _clip01(v as Float) as Float {
        return v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);
    }
}

}
