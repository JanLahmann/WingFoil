import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import WingFoilCore;

// Live pump-stroke and takeoff-attempt detection from the wrist accelerometer.
// Watch twin of lab/src/wingfoil_lab/pump.py + takeoff.py (docs/algorithms.md "Pumping
// (accelerometer)" and "Pump / takeoff detection" -> "Watch approximation"). Every threshold
// below is the tuned lab default; nothing is re-tuned here.
//
// Chain, per 25 Hz sample, O(1) and allocation-free:
//   |a| (orientation-free -- the wrist rotates through every jibe)
//     -> slow EMA level removed (gap holding; the band-pass kills DC on its own)
//     -> 51-tap Hamming-windowed sinc band-pass 0.5-2.5 Hz (pumpFilterSpan 2 s x 25 Hz)
//     -> local maximum above pumpStrokeAmp, pumpRefractory dead time  = one STROKE
//     -> strokes <= pumpStrokeMaxInterval apart = a BURST; >= pumpMinStrokes = pumping
//     -> qualifying bursts less than takeoffAttemptWindow apart, measured from the last
//        stroke of the effort to the FIRST stroke of the next burst, = one ATTEMPT (one
//        effort) -- the lab's `_group` rule, live
//
// This class lives in the device app, NOT in the WingFoilCore barrel: every Toybox.Sensor
// entry point crashes a data field (docs/fit-schema.md class d), so the barrel -- shared with
// garmin/field/ -- must never reference one.
//
// It is a LIVE approximation of the lab, which sees the whole session at once. The
// deviations are listed in docs/algorithms.md "Watch approximation"; the load-bearing ones:
//   * the filter is causal, so a stroke is reported ~GROUP_DELAY_MS after it happened. Stroke
//     TIMES are corrected for that delay, so windows measured against GPS events are right;
//     only the vibe is late.
//   * an attempt is opened only while OFF foil (pumpArmed), and a burst that starts while
//     flying is in-flight pumping, counted separately and never a takeoff attempt.
//   * turn ownership is "a turn window was open at some point during the effort" rather than
//     the lab's "the episode lies inside the window".
class PumpDetector {
    // enums (not const) so they are class-static: PumpDetector.EVENT_TAKEOFF
    enum {
        EVENT_NONE = 0,
        EVENT_TAKEOFF = 1       // a pumped attempt just produced a confirmed flight
    }

    // ---- docs/algorithms.md "Pumping (accelerometer)" (lab-tuned, not user-settable) ----
    const GRID_HZ = 25;                 // pumpResampleHz
    const STEP_MS = 40;                 // 1000 / GRID_HZ
    const N_TAPS = 51;                  // pumpFilterSpan 2 s x 25 Hz, forced odd
    const GROUP_DELAY_MS = 1000;        // (N_TAPS - 1) / 2 samples: linear phase
    const BAND_LO_HZ = 0.5;             // pumpBandLo
    const BAND_HI_HZ = 2.5;             // pumpBandHi
    const STROKE_AMP_G = 0.25;          // pumpStrokeAmp
    const REFRACTORY_MS = 400;          // pumpRefractory
    const BURST_GAP_MS = 1500;          // pumpStrokeMaxInterval
    const MIN_STROKES = 4;              // pumpMinStrokes
    // The session total's two extra gates (engine 0.8.0, docs/algorithms.md "The session
    // total"). No unit conversion is involved: _y1 is the output of the SAME 51-tap
    // Hamming sinc band-pass the lab uses, over |a| already normalised to g by _scale, so
    // the watch's band-passed peak IS the lab's `PumpTrack.band` value and pumpBurstPeakG
    // crosses over as 0.8 unchanged. (The milli-g sniff happens before the filter, and the
    // taps are identical, so there is no gain difference to correct for either.)
    const BURST_PEAK_G = 0.8;           // pumpBurstPeakG -- PROVISIONAL, see the docs
    const MIN_SPEED_KMH = 3.0;          // pumpMinSpeedKmh: below this it is a swim stroke
    // ---- docs/algorithms.md "Takeoff analysis" ----
    const ATTEMPT_WINDOW_MS = 10000;    // takeoffAttemptWindow (also attemptFailSilence)
    // An effort may not be declared failed while a burst that BEGAN inside the window is
    // still too young to have reached MIN_STROKES: (MIN_STROKES - 1) * BURST_GAP_MS = 4500 ms
    // is the longest a legal qualifying burst can take to form, GROUP_DELAY_MS is how late
    // the filter reports its strokes, and one 1 Hz tick is the batch the last of them arrives
    // in. Without this grace the 10 s silence expires between a joining burst's first and
    // fourth stroke and one long bout is counted as several attempts (docs/algorithms.md
    // "Watch approximation" row 5a).
    const ATTEMPT_JOIN_GRACE_MS = 6500;
    const FREE_TAKEOFF = 3;             // freeTakeoff: fewer strokes = the wind did the work
    // ---- live display ----
    const CADENCE_WINDOW_MS = 10000;    // pump_cadence is measured over the last 10 s
    const CAD_RING = 32;                // >= 2.5 strokes/s x 10 s, with room to spare
    const LEVEL_ALPHA = 0.002;          // ~20 s: tracks gravity/posture, never a pump stroke
    const MILLI_G_FLOOR = 20.0;         // |a| this large can only be milli-g, not g

    // ---- session counters (read by PageModel, FitFields, SummaryView) ----
    // The session total (FIT session 38): only the strokes of a burst that qualified —
    // >= MIN_STROKES long, peaking at BURST_PEAK_G, with the board moving. A burst is
    // credited the moment it first qualifies (its earlier strokes included, retroactively),
    // and every later stroke of it as it arrives, so a completed burst contributes exactly
    // what the lab's `_session_strokes` gives it.
    var strokes as Number = 0;
    var peaks as Number = 0;            // every picked peak: the pre-0.8.0 number, diagnostic
    var inFlightStrokes as Number = 0;  // strokes inside a flight: holding/extending a glide
    var successes as Number = 0;        // = confirmed flights (FIT session 36), as the lab
    var failed as Number = 0;           // efforts that produced no flight
    var recoveryEpisodes as Number = 0; // pumping back up after a turn: the turn's business
    var lastPumpsToTakeoff as Number = -1;   // -1 = no takeoff yet; 0 = free takeoff
    var pumpsSum as Number = 0;         // over ALL takeoffs, free ones included (lab semantics)
    var cadence as Number = 0;          // strokes/min over CADENCE_WINDOW_MS (FIT record 2)
    var minGapMs as Number = 0;         // smallest gap between strokes seen (refractory proof)
    var refractoryDrops as Number = 0;  // peaks the dead time swallowed (diagnostic)
    var available as Boolean = false;   // a sensor listener is actually feeding us

    hidden var _cfg as Config;

    // filter state
    hidden var _taps as Array<Float>;
    hidden var _hist as Array<Float>;
    hidden var _pos as Number = 0;
    hidden var _warm as Number = 0;         // samples since the last reset
    hidden var _level as Float = 1.0;
    hidden var _haveLevel as Boolean = false;
    hidden var _scale as Float = 0.0;       // 0 = not sniffed yet; 1.0 = g, 0.001 = milli-g
    hidden var _y0 as Float = 0.0;          // filtered n-2
    hidden var _y1 as Float = 0.0;          // filtered n-1 (the candidate peak)
    hidden var _y2 as Float = 0.0;          // filtered n
    hidden var _outMs as Number = 0;        // time the newest filter OUTPUT refers to

    // resampling (only used when the sensor runs faster than the grid)
    hidden var _decim as Number = 1;
    hidden var _accum as Float = 0.0;
    hidden var _accumN as Number = 0;
    hidden var _lastBatchMs as Number = 0;

    // stroke / burst / attempt state
    hidden var _lastStrokeMs as Number = 0;
    hidden var _burstN as Number = 0;
    hidden var _burstStartMs as Number = 0;
    hidden var _burstPrevMs as Number = 0;
    hidden var _burstOwned as Boolean = false;   // this burst's strokes feed the open attempt
    hidden var _burstPeakG as Float = 0.0;       // tallest band-passed peak in this burst
    hidden var _burstMoving as Number = 0;       // its strokes taken above MIN_SPEED_KMH
    hidden var _burstCounted as Boolean = false; // it has already reached the session total
    hidden var _atOpen as Boolean = false;
    hidden var _atStartMs as Number = 0;
    hidden var _atLastMs as Number = 0;
    hidden var _atStrokes as Number = 0;         // strokes of the effort's LEAD burst =
                                                 //   pumps-to-takeoff if it gets up
    hidden var _atRecovery as Boolean = false;

    // flight/turn context, sampled at 1 Hz from MetricsEngine
    hidden var _flying as Boolean = false;
    hidden var _turnOpen as Boolean = false;
    hidden var _onFoilMs as Number = 0;
    // Speed at the last 1 Hz tick. Strokes arrive between ticks, so the session total's
    // speed gate is read at up to 1 s of age — the live approximation of the lab, which
    // interpolates the Doppler channel at the stroke's own instant. A GPS gap leaves the
    // last known speed standing: the rider does not stop because the fix did.
    hidden var _speedMps as Float = 0.0;

    // cadence ring
    hidden var _cad as Array<Number>;
    hidden var _cadPos as Number = 0;

    function initialize(cfg as Config) {
        _cfg = cfg;
        _taps = new [N_TAPS] as Array<Float>;
        _hist = new [N_TAPS] as Array<Float>;
        _cad = new [CAD_RING] as Array<Number>;
        _buildTaps();
        for (var i = 0; i < N_TAPS; i++) {
            _hist[i] = 0.0;
        }
        for (var i = 0; i < CAD_RING; i++) {
            _cad[i] = 0;
        }
    }

    // Hamming-windowed sinc band-pass = difference of two low-passes, exactly
    // lab/src/wingfoil_lab/pump.py `_bandpass_taps`. Built once; ~51 Floats.
    hidden function _buildTaps() as Void {
        var mid = (N_TAPS - 1) / 2.0;
        var fLo = 2.0 * BAND_LO_HZ / GRID_HZ;
        var fHi = 2.0 * BAND_HI_HZ / GRID_HZ;
        for (var i = 0; i < N_TAPS; i++) {
            var k = i - mid;
            var w = 0.54 - 0.46 * Math.cos(2.0 * Math.PI * i / (N_TAPS - 1));
            _taps[i] = (_lowPass(fHi, k) - _lowPass(fLo, k)) * w;
        }
    }

    // f * sinc(f * k) with numpy's normalized sinc, f = 2 * fc / fs.
    hidden function _lowPass(f as Float, k as Float) as Float {
        if (k == 0.0) {
            return f;
        }
        var x = Math.PI * f * k;
        return f * Math.sin(x) / x;
    }

    // ---- lifecycle ----

    // The controller calls this once the sensor listener is actually registered.
    // rateHz is what was requested; anything faster than the grid is box-averaged down,
    // anything slower leaves the detector unavailable (the band would be wrong).
    function start(rateHz as Number) as Void {
        _decim = 1;
        if (rateHz >= 2 * GRID_HZ) {
            _decim = (rateHz + GRID_HZ / 2) / GRID_HZ;
        }
        available = rateHz >= GRID_HZ;
        resetFilter();
    }

    function stop() as Void {
        available = false;
        resetFilter();
    }

    // A discontinuity in the accel stream: the FIR must not ring on it, so its history is
    // dropped and no stroke is emitted until it has refilled (docs/algorithms.md: a
    // SensorLogging gap contributes no strokes rather than a burst of edge artifacts).
    function resetFilter() as Void {
        _warm = 0;
        _pos = 0;
        _accum = 0.0;
        _accumN = 0;
        _y0 = 0.0;
        _y1 = 0.0;
        _y2 = 0.0;
        _burstN = 0;
        _burstOwned = false;
        _burstPeakG = 0.0;
        _burstMoving = 0;
        _burstCounted = false;
        for (var i = 0; i < N_TAPS; i++) {
            _hist[i] = 0.0;
        }
    }

    // GPS gap / pause: the flight state is frozen, so an open effort can no longer be judged.
    // The lab calls that outcome `unknown` and excludes it from every tally — so do we.
    function onGap() as Void {
        _atOpen = false;
        _atRecovery = false;
        // the record is still being written through a GPS gap, so pump_cadence must keep
        // ageing out rather than freezing at its last value
        _updateCadence(System.getTimer());
        resetFilter();
    }

    // ---- input ----

    // One SensorData batch: x/y/z arrays from Toybox.Sensor.AccelerometerData, newest sample
    // at nowMs. Units are sniffed once (Garmin ships milli-g under a "g" label).
    function onAccelBatch(x as Array<Number>?, y as Array<Number>?, z as Array<Number>?,
            nowMs as Number) as Void {
        if (!available || x == null || y == null || z == null) {
            return;
        }
        var n = x.size();
        if (n == 0 || y.size() < n || z.size() < n) {
            return;
        }
        // A stalled listener leaves a hole in the grid: restart the filter rather than
        // splicing two unrelated stretches of wrist motion together.
        var span = n * 1000 / (GRID_HZ * _decim);
        if (_lastBatchMs != 0 && (nowMs - _lastBatchMs - span).abs() > span / 2 + 200) {
            resetFilter();
        }
        _lastBatchMs = nowMs;
        var rateHz = GRID_HZ * _decim;
        for (var i = 0; i < n; i++) {
            var ax = x[i].toFloat();
            var ay = y[i].toFloat();
            var az = z[i].toFloat();
            var mag = Math.sqrt(ax * ax + ay * ay + az * az);
            // Garmin writes milli-g under a "g" label (docs/algorithms.md), so the scale is
            // sniffed from the resting magnitude exactly as the lab parser does — but only
            // off a sample that carries real signal, never off a sensor still warming up.
            if (_scale == 0.0 && mag > 0.2) {
                _scale = mag > MILLI_G_FLOOR ? 0.001 : 1.0;
            }
            if (_scale == 0.0) {
                continue;
            }
            _accum += mag * _scale;
            _accumN++;
            if (_accumN >= _decim) {
                // time of THIS grid sample: the batch ends at nowMs
                var tMs = nowMs - (n - 1 - i) * 1000 / rateHz;
                _pushGrid(_accum / _accumN, tMs);
                _accum = 0.0;
                _accumN = 0;
            }
        }
    }

    // Magnitudes already on the 25 Hz grid, in g. The unit tests' entry point, and the shape
    // the lab's `pump_track_from_arrays` takes.
    function pushMagBatch(mag as Array<Float>, nowMs as Number) as Void {
        var n = mag.size();
        for (var i = 0; i < n; i++) {
            _pushGrid(mag[i], nowMs - (n - 1 - i) * STEP_MS);
        }
    }

    // ---- the per-sample chain (O(1), no allocation) ----

    hidden function _pushGrid(magG as Float, tMs as Number) as Void {
        if (!_haveLevel) {
            _haveLevel = true;
            _level = magG;
        } else {
            _level += LEVEL_ALPHA * (magG - _level);
        }
        _hist[_pos] = magG - _level;

        var acc = 0.0;
        var j = _pos + 1;
        for (var k = 0; k < N_TAPS; k++) {
            if (j >= N_TAPS) {
                j = 0;
            }
            acc += _taps[k] * _hist[j];
            j++;
        }
        _pos++;
        if (_pos >= N_TAPS) {
            _pos = 0;
        }

        _y0 = _y1;
        _y1 = _y2;
        _y2 = acc;
        // The filter is linear phase: this output describes the sample GROUP_DELAY_MS ago.
        _outMs = tMs - GROUP_DELAY_MS;

        if (_warm < N_TAPS + 2) {
            _warm++;
            return;
        }
        // local maximum, strictly above the previous sample and at least the next
        // (lab `_pick_peaks`), above the amplitude gate, outside the refractory dead time
        if (_y1 > STROKE_AMP_G && _y1 > _y0 && _y1 >= _y2) {
            var strokeMs = _outMs - STEP_MS;
            if (_lastStrokeMs == 0 || strokeMs - _lastStrokeMs >= REFRACTORY_MS) {
                _onStroke(strokeMs, _y1);
            } else {
                refractoryDrops++;      // a human cannot pump faster than the band allows
            }
        }
    }

    hidden function _onStroke(tMs as Number, ampG as Float) as Void {
        if (_lastStrokeMs != 0) {
            var gap = tMs - _lastStrokeMs;
            if (minGapMs == 0 || gap < minGapMs) {
                minGapMs = gap;
            }
        }
        _lastStrokeMs = tMs;
        peaks++;
        if (_flying) {
            inFlightStrokes++;
        }
        _cad[_cadPos] = tMs;
        _cadPos++;
        if (_cadPos >= CAD_RING) {
            _cadPos = 0;
        }

        // burst bookkeeping: strokes no more than pumpStrokeMaxInterval apart are one burst
        if (_burstN > 0 && tMs - _burstPrevMs <= BURST_GAP_MS) {
            _burstN++;
        } else {
            _burstN = 1;
            _burstStartMs = tMs;
            _burstOwned = false;
            _burstPeakG = 0.0;
            _burstMoving = 0;
            _burstCounted = false;
        }
        _burstPrevMs = tMs;
        if (ampG > _burstPeakG) {
            _burstPeakG = ampG;
        }
        var moving = _speedMps * 3.6 >= MIN_SPEED_KMH;
        if (moving) {
            _burstMoving++;
        }
        // The session total (docs/algorithms.md "The session total"). A burst is credited
        // once, retroactively, on the stroke that first makes it qualify -- which may be a
        // late one, since the amplitude test is on the burst's MAXIMUM -- and per stroke
        // after that.
        if (_burstCounted) {
            if (moving) {
                strokes++;
            }
        } else if (_burstN >= MIN_STROKES && _burstPeakG >= BURST_PEAK_G) {
            strokes += _burstMoving;
            _burstCounted = true;
        }

        if (_burstN < MIN_STROKES) {
            return;
        }
        if (_burstN == MIN_STROKES) {
            // The burst qualifies as pumping only now, but the silence that separates two
            // efforts is measured to its FIRST stroke, exactly as the lab's `_group` does
            // (`first - out[-1].end_t < attempt_window_s`). Measuring it to this fourth
            // stroke instead shortens the merge window by however long the burst took to
            // form — up to 4.5 s — and splits one bout into several attempts.
            if (_atOpen && _burstStartMs - _atLastMs < ATTEMPT_WINDOW_MS) {
                // Same effort, a new burst inside it. `_atStrokes` tracks the LEAD burst,
                // not the whole effort: the lab's `pumps_to_takeoff` counts the strokes of
                // the run (speed rise ∪ lead burst), so an effort spanning half a minute of
                // thrashing must not report all of it as the cost of the takeoff.
                _atStrokes = MIN_STROKES;
                _burstOwned = true;
            } else if (!_flying) {
                _atOpen = true;
                _atStartMs = _burstStartMs;
                _atStrokes = MIN_STROKES;
                _atRecovery = _turnOpen;
                _burstOwned = true;
            }
            // else: it started while flying — in-flight pumping, never a takeoff attempt
        } else if (_burstOwned && _atOpen) {
            _atStrokes++;
        }
        if (_burstOwned && _atOpen) {
            _atLastMs = tMs;
            if (_turnOpen) {
                _atRecovery = true;
            }
        }
    }

    // ---- 1 Hz context tick, driven by MetricsEngine ----

    // flying: FlightDetector is ON_FOIL · turnOpen: a TurnDetector sweep/outcome window is
    // running · flightEvent: this tick's FlightDetector event · speedMps: this sample's
    // speed, which the session total's `pumpMinSpeedKmh` gate is read from.
    // Returns EVENT_TAKEOFF when a pumped effort just produced a confirmed flight.
    function tick(nowMs as Number, flying as Boolean, turnOpen as Boolean,
            flightEvent as Number, speedMps as Float) as Number {
        _turnOpen = turnOpen;
        _speedMps = speedMps;
        if (flying && !_flying) {
            // FlightDetector backdates ON_FOIL by the entry hold; so do we, so the 10 s
            // window is measured from the same instant the lab measures it from.
            _onFoilMs = nowMs - _cfg.entryHoldS * 1000;
        }
        _flying = flying;
        _updateCadence(nowMs);

        var event = EVENT_NONE;
        if (flightEvent == FlightDetector.EVENT_START) {
            event = _onFlightConfirmed();
        }
        _expire(nowMs);
        return event;
    }

    // Every confirmed flight is a takeoff success (lab: `takeoff_successes` = flights), and
    // the effort that produced it — if there was one inside takeoffAttemptWindow — is its
    // takeoff run. No effort ⇒ 0 pumps ⇒ a free takeoff: the wind did the work.
    // `_atStrokes` is the effort's LEAD burst, the watch's stand-in for the lab's run.
    hidden function _onFlightConfirmed() as Number {
        successes++;
        var pumped = _atOpen && _onFoilMs >= _atStartMs
            && _onFoilMs - _atLastMs <= ATTEMPT_WINDOW_MS;
        var pumps = pumped ? _atStrokes : 0;
        lastPumpsToTakeoff = pumps;
        pumpsSum += pumps;
        if (pumped) {
            _atOpen = false;
            _atRecovery = false;
            _burstOwned = false;
            return EVENT_TAKEOFF;
        }
        return EVENT_NONE;
    }

    // An effort ends when the rider stops trying: takeoffAttemptWindow of silence. If he is
    // ON foil at that moment the flight may still be confirmed (minFlight is up to 5 s late),
    // so the effort is held open until it is confirmed or the flight collapses — and if a
    // fresh burst has already started inside the window, until that burst has had
    // ATTEMPT_JOIN_GRACE_MS to reach pumpMinStrokes and join.
    hidden function _expire(nowMs as Number) as Void {
        if (!_atOpen || nowMs - _atLastMs <= ATTEMPT_WINDOW_MS) {
            return;
        }
        if (_flying && _onFoilMs - _atLastMs <= ATTEMPT_WINDOW_MS) {
            return;     // pending: ON_FOIL happened inside the window, wait for minFlight
        }
        if (_burstN > 0 && !_burstOwned && _burstStartMs - _atLastMs < ATTEMPT_WINDOW_MS
                && nowMs - _burstStartMs <= ATTEMPT_JOIN_GRACE_MS) {
            return;     // a burst opened inside the window and may still reach MIN_STROKES
        }
        if (_atRecovery) {
            recoveryEpisodes++;     // the turn already scored this as a touchdown
        } else {
            failed++;
        }
        _atOpen = false;
        _atRecovery = false;
        _burstOwned = false;
    }

    hidden function _updateCadence(nowMs as Number) as Void {
        var n = 0;
        for (var i = 0; i < CAD_RING; i++) {
            var t = _cad[i];
            if (t != 0 && nowMs - t <= CADENCE_WINDOW_MS) {
                n++;
            }
        }
        cadence = n * 60000 / CADENCE_WINDOW_MS;
    }

    // ---- derived values (FIT + UI) ----

    // FIT session 35: successes + failed efforts, exactly the lab's `takeoff_attempts`.
    function attempts() as Number {
        return successes + failed;
    }

    // FIT session 37: average pumps to takeoff x 10 (87 = 8.7 strokes), over ALL takeoffs
    // including the free ones — the lab's `avg_pumps_to_takeoff`.
    function avgPumpsX10() as Number {
        if (successes <= 0) {
            return 0;
        }
        var v = pumpsSum * 10 / successes;
        return v > 254 ? 254 : v;
    }

    function successPct() as Number {
        var a = attempts();
        return a > 0 ? successes * 100 / a : 0;
    }

    // True while an effort is open: the rider is pumping and has not got up yet.
    function attemptOpen() as Boolean {
        return _atOpen;
    }
}
