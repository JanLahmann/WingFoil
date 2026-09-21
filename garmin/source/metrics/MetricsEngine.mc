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
    // The settle release (0.9.17). A held baseline is the right answer to a dunk and the
    // wrong one to a watch whose pressure channel RE-ANCHORS after the dunk: on a fenix 5X
    // Plus (tester, 20 Sep 2026) the level after a fall never came back, so the rise stayed
    // over SUBMERSION_PA and `submerged` latched true for the rest of the session — every
    // later turn "fell in". A dunk is a spike; a level is not a dunk. So when the rise has
    // been over SUBMERSION_PA for BARO_SETTLE_S ticks AND every sample in that window sits
    // within +/-BARO_SETTLE_PA of this one, the new level is accepted as ambient:
    // `_baseline = pa`, this sample dry. 20 ticks = the phone's BARO_SETTLE_S (20 s at 1 Hz);
    // 60 Pa = the phone's 5 m at the same ~12 Pa/m this file converts turnBaroDrop with.
    // The cost is honest and is the phone's too: a swim that holds one depth to within 5 m
    // for 20 s reads dry from its 20th second. A wrist in moving water does not.
    const BARO_SETTLE_S = 20;
    const BARO_SETTLE_PA = 60.0;
    const RAD2DEG = 57.29578;

    // Breadcrumb for the optional map page: lat/lon in degrees, Float (~1 m on a wingfoil
    // spot — plenty for a track line). Only filled when a map page is configured, because
    // 2 x 128 Floats is memory the other five pages have no use for.
    const TRACK_MAX = 128;
    const TRACK_BASE_STRIDE = 5;        // one point every ~5 s at 1 Hz
    const TRACK_STRIDE_MAX = 1 << 20;   // see _trackTick: a doubling stride must have a roof

    var detector as FlightDetector;
    var turns as TurnDetector;
    var records as SpeedRecords;
    var history as SessionHistory;
    // The live wind-axis estimator (docs/algorithms.md "Watch approximation: auto wind"). It
    // is in the barrel because it is pure computation over COG and speed, but it is DRIVEN
    // from here, after the detectors, so that a direction adopted this second classifies the
    // turns of the next one and never re-judges the one just resolved.
    var autoWind as AutoWind;
    // The one-shot backfill is exactly that: it may fire once, at the first lock, and this is
    // the flag that says so (docs/fit-schema.md, TurnDetector.backfillWindSplit).
    var autoWindBackfilled as Boolean = false;
    // App-only: the pump/takeoff detector reads the accelerometer, which a data field may not
    // touch, so it lives here rather than in the WingFoilCore barrel (docs/fit-schema.md
    // class d). SessionController owns the sensor listener and feeds it batches.
    var pump as PumpDetector;
    // The HR price of the last takeoff. Rides with the pump detector because it is anchored on
    // the effort the pump detector opens: no accelerometer (rawAccelLogging off) means no
    // efforts, which means this simply never produces a number — which is the honest answer.
    var hrCost as HrCostTracker;

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

    // TEST SEAM. `tick` measures dt from System.getTimer(), which nothing outside the
    // firmware can move — so a fuzz loop that calls tick() twenty thousand times in a row
    // sees dt ≈ 0 every time, returns at the first guard and exercises nothing. Set this and
    // the engine reads its clock from here instead: that is how the crash-hunt suite drives
    // six hours at 1 Hz, a 30 s gap, a clock that runs backwards and the getTimer wrap
    // (docs/testing.md, "The watch's crash hunt"). Null on every watch, always.
    var clockMsOverride as Number? = null;

    hidden var _lastMs as Number = 0;
    // Distance comes through the barrel's teleport guard, never straight off elapsedDistance.
    hidden var _odo as Odometer = new Odometer();
    hidden var _tickCount as Number = 0;
    hidden var _baseline as Float = 0.0;
    hidden var _haveBaseline as Boolean = false;
    // The settle window: the last BARO_SETTLE_S pressure samples, a ring written once per
    // tick and read for its spread only while a spike is open. Allocated once (20 Floats),
    // never per tick; `_settleN` is how much of it is real, `_wetRun` the length of the run of
    // consecutive over-threshold ticks the window has to agree with.
    hidden var _settleRing as Array<Float>;
    hidden var _settlePos as Number = 0;
    hidden var _settleN as Number = 0;
    hidden var _wetRun as Number = 0;

    // Detectors come from the WingFoilCore barrel and read their thresholds from the
    // Config this app fills from GCM properties (AppSettings.load()).
    function initialize() {
        detector = new FlightDetector(AppSettings.cfg);
        turns = new TurnDetector(AppSettings.cfg);
        records = new SpeedRecords();
        history = new SessionHistory();
        pump = new PumpDetector(AppSettings.cfg);
        _settleRing = new [BARO_SETTLE_S] as Array<Float>;
        for (var i = 0; i < BARO_SETTLE_S; i++) {
            _settleRing[i] = 0.0;
        }
        hrCost = new HrCostTracker();
        autoWind = new AutoWind();
    }

    // Returns detector event (FlightDetector.EVENT_*) | pbEvents<<4 | turnEvent<<8
    // | pumpEvent<<12 | autoWindEvent<<16.
    function tick(info as Position.Info) as Number {
        var o = clockMsOverride;
        var now = o != null ? o as Number : System.getTimer();
        var dt = _lastMs > 0 ? (now - _lastMs) / 1000.0 : 1.0;
        _lastMs = now;
        // Negative dt is not impossible: System.getTimer() wraps (~24.8 days of uptime), and
        // the sample after the wrap is two billion milliseconds "earlier". `dt < 0.2` already
        // drops it — this comment is here so nobody re-derives dt as an absolute value and
        // books 24 days of flight time into one tick.
        if (dt < 0.2) {
            return 0;
        }
        if (dt > 3.0) {
            dt = 3.0;
        }

        // accuracy is a Position.Quality enum, but nothing guarantees the fix carries one of
        // its five values — an unusable constant is the safe reading of anything else.
        var acc = info.accuracy;
        gpsQuality = acc instanceof Lang.Number ? acc as Number : 0;
        var sp = info.speed;
        speedMps = 0.0;
        if (sp instanceof Lang.Float) {
            speedMps = sp as Float;
        } else if (sp instanceof Lang.Number) {
            speedMps = (sp as Number).toFloat();
        }
        // An impossible speed is garbage, whatever the fix claims about its quality, and it
        // must not reach the records (which latch) or the distance (which integrates).
        var sane = WingFoilCore.speedPlausible(speedMps);
        if (!sane) {
            speedMps = 0.0;
        }

        var actInfo = Activity.getActivityInfo();
        var distDelta = speedMps * dt;
        if (actInfo != null) {
            if (actInfo.timerTime != null) {
                timerS = actInfo.timerTime / 1000.0;
            }
            if (actInfo.elapsedDistance != null) {
                distDelta = _odo.step(actInfo.elapsedDistance as Float, distDelta, dt);
            }
            hr = actInfo.currentHeartRate;
        }
        distM += distDelta;
        _updateSubmersion(actInfo);

        _tickCount++;

        if (!sane || gpsQuality < Position.QUALITY_USABLE) {
            // don't feed garbage into detectors/records; windows must restart cleanly
            records.onGap();
            turns.onGap();
            // an open pumping effort can no longer be judged: the lab calls that `unknown`
            // and drops it from every tally rather than calling it a failure
            pump.onGap();
            return 0;
        }

        var cog = _cogDeg(info);
        var flightEvent = detector.tick(dt, speedMps, distDelta);
        var pbEvents = records.tick(speedMps);
        var turnEvent = turns.tick(dt, cog, speedMps, distDelta,
            detector.state == FlightDetector.STATE_ON, submerged);

        // Pumping is judged against the flight and turn state of this same sample: a burst
        // that starts while flying is in-flight pumping, one inside a turn window is the
        // rider recovering from that turn, and neither is a takeoff attempt.
        var pumpEvent = pump.tick(now, detector.state == FlightDetector.STATE_ON,
            turns.state != TurnDetector.ST_IDLE, flightEvent, speedMps);
        // Priced against the effort the detector just reported, on this same heart rate: the
        // window opens when he starts pumping and stays open 30 s, takeoff or not.
        hrCost.tick(dt, hr, pump.attemptOpen(), pumpEvent == PumpDetector.EVENT_TAKEOFF);

        history.tick(dt, detector.state == FlightDetector.STATE_ON, speedMps);
        if (turnEvent >= TurnDetector.EVENT_FLEW && turnEvent <= TurnDetector.EVENT_FELL) {
            history.logTurn(turns.lastOutcome);
        }
        var windEvent = _autoWindTick(dt, cog, turnEvent);
        if (trackEnabled) {
            _trackTick(info, detector.state == FlightDetector.STATE_ON);
        }
        return flightEvent | (pbEvents << 4) | (turnEvent << 8) | (pumpEvent << 12)
            | (windEvent << 16);
    }

    // The auto-wind half of a tick, after the detectors so that an axis adopted now takes
    // effect from the NEXT sample: the sweep that just resolved was named with the wind that
    // was in force while it happened, which is the watch's whole rule about turn labels.
    //
    // The single exception is the FIRST lock, and it is deliberate: the sweeps the estimator
    // learned the axis from are the session's own first turns, and leaving them generic would
    // mean the Turns page starts counting tacks and jibes from zero at minute two of an hour's
    // riding. `backfillWindSplit` replays the logged sweeps once — counts only, no outcome and
    // no score is re-judged — and `autoWindBackfilled` makes sure "once" means once.
    hidden function _autoWindTick(dt as Float, cog as Float?, turnEvent as Number) as Number {
        if (!AppSettings.autoWind) {
            return 0;
        }
        // Read live rather than cached at construction, for the same reason the detectors read
        // their Config live: this object is built in `WingfoilApp.initialize()`, which runs
        // BEFORE the first `AppSettings.load()`, and a GCM edit mid-session must take effect
        // without a restart.
        autoWind.defaultTurnType = AppSettings.windDefaultTurnType;
        if (turnEvent == TurnDetector.EVENT_TURN) {
            autoWind.logSweep(turns.lastEntryU, turns.lastNetDeg);
        }
        var ev = autoWind.tick(dt, cog, speedMps,
            detector.state == FlightDetector.STATE_ON);
        if (ev == AutoWind.EV_NONE) {
            return ev;
        }
        AppSettings.applyAutoWind(autoWind.dirDeg);
        // Both the backfill and the vibe are about the axis the rider is actually being shown.
        // With a manual bearing in force the estimate changes nothing on screen and nothing in
        // the classifier — and backfilling against the MANUAL axis would count every logged
        // sweep a second time, since those turns were already split as they happened.
        if (!AppSettings.cfg.windIsAuto()) {
            return AutoWind.EV_NONE;
        }
        if (ev == AutoWind.EV_LOCK && !autoWindBackfilled) {
            autoWindBackfilled = true;
            turns.backfillWindSplit(autoWind.sweepEntries(), autoWind.sweepNets(),
                autoWind.sweepCount);
        }
        return ev;
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
            // Capped, because a Number that doubles for long enough goes NEGATIVE, and a
            // negative stride makes `_trackSkip < _trackStride` false forever — every fix
            // appended, the buffer halved every 128 s, for the rest of the session. Six hours
            // reaches 320; the cap is unreachable on a battery but it is not a comment.
            if (_trackStride < TRACK_STRIDE_MAX) {
                _trackStride *= 2;
            }
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
        if (!(h instanceof Lang.Float) && !(h instanceof Lang.Number)) {
            return null;    // no heading on this fix — and null is not the only way to say so
        }
        // heading is radians in [-PI, PI]; the detector unwraps, so any 0-360 mapping works.
        //
        // THE WRAP IS ARITHMETIC, NOT A LOOP. It used to be two `while`s, which is fine for
        // the ±PI the API promises and a freeze for anything else: a fix carrying 1e9 rad
        // spins 2.7 million times inside a 1 Hz callback and the watchdog kills the app with
        // nothing in the log. A modulo costs the same at ±PI and is bounded at every input.
        var rad = h instanceof Lang.Float ? (h as Float) : (h as Number).toFloat();
        var deg = rad * RAD2DEG;
        deg -= Math.floor(deg / 360.0) * 360.0;     // Monkey C has no `%` for Floats
        // The subtraction is exact at the ±PI the API promises and cancels badly at 1e9 rad,
        // where a 32-bit Float has no digits left to spare — so the range is asserted rather
        // than assumed. North is the honest reading of a bearing that arrived as noise.
        if (deg < 0.0 || deg >= 360.0) {
            deg = 0.0;
        }
        return deg;
    }

    // Barometric submersion evidence for TurnDetector. The baseline tracks the ambient
    // pressure slowly and deliberately refuses to adapt while a spike is in progress, so a
    // dunk cannot re-baseline itself into looking dry — until it stops being a spike and
    // becomes a level, which is the settle release above. Null-safe: devices/sim runs
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
        submersionSample((p as Numeric).toFloat());
    }

    // The rule itself, one pressure sample in and `submerged` out. Split from the reader
    // above because the simulator hands a test no Activity.Info and the suite has to be able
    // to drive a trace (docs/testing.md, the watch's unit suite) — the same seam shape as
    // `clockMsOverride`. Bounded work, no allocation: one ring write and, only while a spike
    // is open, one pass over BARO_SETTLE_S Floats.
    function submersionSample(pa as Float) as Void {
        submerged = false;
        if (!_haveBaseline) {
            _haveBaseline = true;
            _baseline = pa;
        }
        _settleRing[_settlePos] = pa;
        _settlePos++;
        if (_settlePos >= BARO_SETTLE_S) {
            _settlePos = 0;
        }
        if (_settleN < BARO_SETTLE_S) {
            _settleN++;
        }

        var rise = pa - _baseline;
        if (rise > SUBMERSION_PA) {
            _wetRun++;
            // The settle release: BARO_SETTLE_S consecutive over-threshold ticks whose whole
            // window sits within +/-BARO_SETTLE_PA of this sample is a new ambient level, not
            // a wrist under water. Accept it and read this sample dry.
            if (_wetRun >= BARO_SETTLE_S && _settleN >= BARO_SETTLE_S && _settleLevel(pa)) {
                _baseline = pa;
                _wetRun = 0;
                return;
            }
            submerged = true;
            return;
        }
        _wetRun = 0;
        _baseline += BARO_EMA * rise;
    }

    // Did the last BARO_SETTLE_S samples all stay within +/-BARO_SETTLE_PA of `pa`? A scan
    // rather than a maintained min/max: BARO_SETTLE_S is 20, the loop runs only on a tick
    // that is already over the threshold, and a rolling extremum would cost a second ring.
    hidden function _settleLevel(pa as Float) as Boolean {
        for (var i = 0; i < BARO_SETTLE_S; i++) {
            var d = _settleRing[i] - pa;
            if (d > BARO_SETTLE_PA || d < -BARO_SETTLE_PA) {
                return false;
            }
        }
        return true;
    }

    // A pause is a hole in the pressure stream, not quiet water: the rider can walk the watch
    // up the beach, into a car, up a hill, and the level it comes back to has nothing to do
    // with the one it left. SessionController calls this on every resume (manual and auto) so
    // the first sample after the hole re-anchors the baseline instead of reading as a dunk.
    function restartBaseline() as Void {
        _haveBaseline = false;
        _settleN = 0;
        _settlePos = 0;
        _wetRun = 0;
        submerged = false;
    }

    function tickCount() as Number {
        return _tickCount;
    }

    function foilPct() as Float {
        return timerS > 0 ? detector.foilTimeS / timerS * 100.0 : 0.0;
    }

    // The same question asked of the odometer instead of the clock: what share of the ground
    // covered was covered flying. It is NOT a restatement of foilPct — flying is the fast half
    // of a session, so the distance share always runs ahead of the time share, and the gap
    // between the two is exactly how much faster. Negative only if a teleport guard ever
    // clawed back more than it gave; callers guard on distM instead of on this.
    function foilDistPct() as Float {
        return distM > 0 ? detector.foilDistM / distM * 100.0 : 0.0;
    }
}
