import Toybox.Lang;

// Live jump COUNT from the wrist accelerometer — beta and dev (0.9.24).
// Watch twin of lab/src/wingfoil_lab/jump.py `detect_jumps_from_arrays`, engine 0.29.0
// (docs/algorithms/jumps.md, and its "Watch approximation"). Every threshold below is the
// lab default; nothing is re-tuned here. No HEIGHT: the integrated estimate needs the whole
// support profile and still reads low (Freddy, 15 Oct 2026), so the phone says it and the
// watch only counts.
//
// Fed from PumpDetector._pushGrid, the one place every 25 Hz grid magnitude passes, so it
// reads exactly the numbers the pump chain reads. MetricsEngine creates it where the `jumpCount`
// property is on (`_makeJumps`): the beta and the dev build. The release has no such
// property, so it carries the class and never runs it.
//
// Per grid sample, O(1), no allocation:
//   |a| -> 3-sample running median (jumpSmooth 0.06 s at 25 Hz, the lab's width)
//       -> below jumpAirborneMaxG = airborne; one excursion of <= jumpBridge at <=
//          jumpBridgeMaxG does not end the window
//       -> window edges at the interpolated threshold crossings
//       -> jumpMinAirtime..jumpMaxAirtime, pop >= jumpTakeoffMinG in the jumpSpikeWindow
//          before, impact >= jumpImpactMinG in the jumpSpikeWindow after
//       -> the three context gates from the 1 Hz tick: on the foil at the takeoff, at least
//          jumpMinSpeedKmh in the jumpSpeedWindow before it, no turn sweep over the window
//       -> jumpRefractory after an accepted jump
//
// Deviations from the lab (docs/algorithms/jumps.md "Watch approximation"):
//   * a jump is decided jumpSpikeWindow after the landing (the impact search), so the
//     count and its buzz land ~1 s late;
//   * the context is the 1 Hz tick's, so the speed, foil and sweep reads are +-1 s fuzzy;
//     the sweep gate asks for a ST_SWEEP tick from 1 s before the takeoff to 0.5 s after
//     the landing;
//   * a low-g window that starts while the previous one waits for its impact is dropped.
class JumpDetector {
    const LOW_G = 0.75;               // jumpAirborneMaxG
    const BRIDGE_MS = 100;            // jumpBridge
    const BRIDGE_MAX_G = 0.95;        // jumpBridgeMaxG
    const MIN_AIR_MS = 400;           // jumpMinAirtime
    const MAX_AIR_MS = 4000;          // jumpMaxAirtime
    const POP_G = 1.8;                // jumpTakeoffMinG
    const IMPACT_G = 2.5;             // jumpImpactMinG
    const SPIKE_MS = 1000;            // jumpSpikeWindow
    const REFRACTORY_MS = 2000;       // jumpRefractory
    const MIN_SPEED_MPS = 5.0;        // jumpMinSpeedKmh 18 km/h
    const SPEED_MS = 3000;            // jumpSpeedWindow
    const SWEEP_LEAD_MS = 1000;       // the tick fuzz on the sweep gate, before the takeoff
    const SWEEP_TAIL_MS = 500;        // ... and after the landing
    const RING = 28;                  // > jumpSpikeWindow at 25 Hz, the pop's look-back
    const SPEEDS = 6;                 // > jumpSpeedWindow at 1 Hz

    enum {
        ST_IDLE = 0,
        ST_RUN = 1,
        ST_WAIT = 2
    }

    var count as Number = 0;

    hidden var _state as Number = ST_IDLE;
    // the median's two previous raw samples, and the newest one's time
    hidden var _m1 as Float = 0.0;
    hidden var _m2 as Float = 0.0;
    hidden var _t1 as Number = 0;
    hidden var _n as Number = 0;
    // the last smoothed sample, for the takeoff crossing
    hidden var _prevSm as Float = 1.0;
    hidden var _prevT as Number = 0;
    // raw look-back for the pop
    hidden var _ringM as Array<Float>;
    hidden var _ringT as Array<Number>;
    hidden var _ringPos as Number = 0;
    // the window being measured
    hidden var _t0 as Float = 0.0;
    hidden var _tEnd as Float = 0.0;
    hidden var _pop as Float = 0.0;
    hidden var _impact as Float = 0.0;
    hidden var _lowT as Number = 0;
    hidden var _lowSm as Float = 0.0;
    hidden var _highN as Number = 0;
    hidden var _highT as Number = 0;
    hidden var _highSm as Float = 0.0;
    hidden var _highMax as Float = 0.0;
    hidden var _highRaw as Float = 0.0;
    hidden var _onFoil as Boolean = false;
    hidden var _fast as Boolean = false;
    hidden var _sweepHit as Boolean = false;
    hidden var _lastEnd as Float = -100000.0;
    // the 1 Hz context
    hidden var _flying as Boolean = false;
    hidden var _lastSweepMs as Number = -100000;
    hidden var _spdV as Array<Float>;
    hidden var _spdT as Array<Number>;
    hidden var _spdPos as Number = 0;

    function initialize() {
        _ringM = new [RING] as Array<Float>;
        _ringT = new [RING] as Array<Number>;
        _spdV = new [SPEEDS] as Array<Float>;
        _spdT = new [SPEEDS] as Array<Number>;
        reset();
    }

    // A hole in the stream (pause, GPS gap, a stalled listener): the window in progress is
    // dropped, exactly as the lab's `jumpMaxGap` voids one. The count stays.
    function reset() as Void {
        _state = ST_IDLE;
        _n = 0;
        _prevSm = 1.0;
        for (var i = 0; i < RING; i++) {
            _ringM[i] = 0.0;
            _ringT[i] = -100000;
        }
        for (var j = 0; j < SPEEDS; j++) {
            _spdV[j] = 0.0;
            _spdT[j] = -100000;
        }
    }

    // The 1 Hz context: foil state, whether a turn is sweeping, this fix's speed.
    function tick(nowMs as Number, flying as Boolean, sweeping as Boolean,
            speedMps as Float) as Void {
        _flying = flying;
        _spdV[_spdPos] = speedMps;
        _spdT[_spdPos] = nowMs;
        _spdPos = (_spdPos + 1) % SPEEDS;
        if (sweeping) {
            _lastSweepMs = nowMs;
            if (_state == ST_RUN || (_state == ST_WAIT && nowMs <= _tEnd + SWEEP_TAIL_MS)) {
                _sweepHit = true;
            }
        }
    }

    // One grid magnitude in g at tMs. The median is centred, so each sample is judged one
    // sample late, with its own time.
    function push(m as Float, tMs as Number) as Void {
        if (_n >= 2) {
            _step(_med3(_m2, _m1, m), _m1, _t1);
        }
        _m2 = _m1;
        _m1 = m;
        _t1 = tMs;
        if (_n < 2) {
            _n++;
        }
    }

    hidden function _step(sm as Float, raw as Float, t as Number) as Void {
        if (_state == ST_WAIT) {
            if (t <= _tEnd + SPIKE_MS) {
                if (raw > _impact) {
                    _impact = raw;
                }
            } else {
                _decide();
                _state = ST_IDLE;
            }
        }
        if (_state == ST_IDLE) {
            if (sm < LOW_G) {
                _open(sm, t);
            }
        } else if (_state == ST_RUN) {
            if (sm < LOW_G) {
                if (_highN > 0) {
                    if (t - _lowT <= BRIDGE_MS && _highMax <= BRIDGE_MAX_G) {
                        _highN = 0;                 // bridged: one window
                    } else {
                        _close();
                        if (_state == ST_IDLE) {
                            _open(sm, t);
                        }
                    }
                }
                if (_state == ST_RUN) {
                    _lowT = t;
                    _lowSm = sm;
                }
            } else {
                if (_highN == 0) {
                    _highT = t;
                    _highSm = sm;
                    _highMax = sm;
                    _highRaw = raw;
                } else {
                    if (sm > _highMax) {
                        _highMax = sm;
                    }
                    if (raw > _highRaw) {
                        _highRaw = raw;
                    }
                }
                _highN++;
                if (t - _lowT > BRIDGE_MS) {
                    _close();
                }
            }
        }
        _ringM[_ringPos] = raw;
        _ringT[_ringPos] = t;
        _ringPos = (_ringPos + 1) % RING;
        _prevSm = sm;
        _prevT = t;
    }

    // A low sample after a supported one: the takeoff. The pop is looked for in the raw
    // samples of the spike window before the crossing, and the context is read now.
    hidden function _open(sm as Float, t as Number) as Void {
        _t0 = _crossing(_prevT, _prevSm, t, sm);
        _pop = 0.0;
        for (var i = 0; i < RING; i++) {
            var rt = _ringT[i];
            if (rt >= _t0 - SPIKE_MS && rt <= _t0 && _ringM[i] > _pop) {
                _pop = _ringM[i];
            }
        }
        _onFoil = _flying;
        var peak = 0.0;
        for (var j = 0; j < SPEEDS; j++) {
            var st = _spdT[j];
            if (st >= _t0 - SPEED_MS && st <= _t0 + SWEEP_TAIL_MS && _spdV[j] > peak) {
                peak = _spdV[j];
            }
        }
        _fast = peak >= MIN_SPEED_MPS;
        _sweepHit = _lastSweepMs >= _t0 - SWEEP_LEAD_MS;
        _lowT = t;
        _lowSm = sm;
        _highN = 0;
        _state = ST_RUN;
    }

    // The window ended at the last low sample: the landing crossing, then the impact wait,
    // which starts with the supported samples already seen after it.
    hidden function _close() as Void {
        _tEnd = _crossing(_lowT, _lowSm, _highT, _highSm);
        var air = _tEnd - _t0;
        if (air < MIN_AIR_MS || air > MAX_AIR_MS) {
            _state = ST_IDLE;
            return;
        }
        _impact = _highRaw;
        _state = ST_WAIT;
    }

    hidden function _decide() as Void {
        if (_pop >= POP_G && _impact >= IMPACT_G && _onFoil && _fast && !_sweepHit
                && _t0 - _lastEnd >= REFRACTORY_MS) {
            count++;
            _lastEnd = _tEnd;
        }
    }

    // The lab's `_crossing`: where the line between two samples meets jumpAirborneMaxG.
    hidden function _crossing(tA as Number, yA as Float, tB as Number, yB as Float) as Float {
        if (yA == yB) {
            return tB.toFloat();
        }
        var f = (yA - LOW_G) / (yA - yB);
        if (f < 0.0) {
            f = 0.0;
        } else if (f > 1.0) {
            f = 1.0;
        }
        return tA + f * (tB - tA);
    }

    hidden function _med3(a as Float, b as Float, c as Float) as Float {
        if (a > b) {
            var s = a;
            a = b;
            b = s;
        }
        if (b > c) {
            b = c;
        }
        return a > b ? a : b;
    }
}
