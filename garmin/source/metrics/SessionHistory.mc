import Toybox.Lang;
import WingFoilCore;

// Backing data for the Timeline page: the whole session's story in a fixed footprint.
//
// Two pre-allocated Number arrays (never grown, never re-allocated after construction) hold
// one slot per SLOT_S seconds: the fraction of that slot spent flying (0-100) and the fastest
// speed seen in it (cm/s, so it stays an integer). When the arrays fill, the series is
// DOWNSAMPLED IN PLACE — pairs merge, slot period doubles — rather than wrapped: the point of
// the page is the arc of the whole session, so losing resolution beats losing the first hour.
// 256 slots x 30 s = 2:08 h before the first halving, 4:16 h after, and so on.
//
// The turn log is the outcome sequence the page draws as dots. It is capped and drops the
// OLDEST entry on overflow (most recent turns are the ones worth reading on the water).
//
// Cost per 1 Hz tick: three adds and a compare, no allocation. The halving is O(n) but happens
// at most ~once per hour.
class SessionHistory {
    const SLOT_MAX = 256;
    const SLOT_BASE_S = 30;
    const TURN_MAX = 64;

    var foilPct as Array<Number>;        // 0-100 per slot
    var maxCms as Array<Number>;         // fastest speed in the slot, cm/s
    var slotCount as Number = 0;         // committed slots
    var slotS as Number = 30;            // current slot period; doubles on each halving
    var turns as Array<Number>;          // TurnDetector.OUTCOME_* per turn, oldest first
    var turnCount as Number = 0;

    hidden var _accS as Float = 0.0;     // seconds accumulated into the open slot
    hidden var _foilS as Float = 0.0;    // of which flying
    hidden var _peakCms as Number = 0;

    function initialize() {
        foilPct = new [SLOT_MAX] as Array<Number>;
        maxCms = new [SLOT_MAX] as Array<Number>;
        turns = new [TURN_MAX] as Array<Number>;
        for (var i = 0; i < SLOT_MAX; i++) {
            foilPct[i] = 0;
            maxCms[i] = 0;
        }
        for (var i = 0; i < TURN_MAX; i++) {
            turns[i] = 0;
        }
        slotS = SLOT_BASE_S;
    }

    // One sample. `flying` is FlightDetector.STATE_ON.
    function tick(dt as Float, flying as Boolean, speedMps as Float) as Void {
        _accS += dt;
        if (flying) {
            _foilS += dt;
        }
        var cms = (speedMps * 100.0).toNumber();
        if (cms > _peakCms) {
            _peakCms = cms;
        }
        if (_accS >= slotS) {
            _commit();
        }
    }

    hidden function _commit() as Void {
        if (slotCount >= SLOT_MAX) {
            _halve();
        }
        var pct = _accS > 0 ? (_foilS / _accS * 100.0).toNumber() : 0;
        foilPct[slotCount] = pct > 100 ? 100 : pct;
        maxCms[slotCount] = _peakCms;
        slotCount++;
        _accS = 0.0;
        _foilS = 0.0;
        _peakCms = 0;
    }

    // Merge slot pairs: foil fraction averages, speed keeps the peak. Period doubles.
    hidden function _halve() as Void {
        var j = 0;
        for (var i = 0; i < slotCount; i += 2) {
            var b = i + 1 < slotCount ? i + 1 : i;
            foilPct[j] = (foilPct[i] + foilPct[b]) / 2;
            maxCms[j] = maxCms[i] > maxCms[b] ? maxCms[i] : maxCms[b];
            j++;
        }
        slotCount = j;
        slotS *= 2;
    }

    // Append a resolved turn outcome; oldest falls off the front when the log is full.
    function logTurn(outcome as Number) as Void {
        if (turnCount >= TURN_MAX) {
            for (var i = 1; i < TURN_MAX; i++) {
                turns[i - 1] = turns[i];
            }
            turnCount = TURN_MAX - 1;
        }
        turns[turnCount] = outcome;
        turnCount++;
    }

    // Fastest slot in the series, cm/s — the sparkline's scale.
    function peakCms() as Number {
        var m = 0;
        for (var i = 0; i < slotCount; i++) {
            if (maxCms[i] > m) {
                m = maxCms[i];
            }
        }
        return m;
    }
}
