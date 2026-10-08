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
// the majority (docs/algorithms/wind.md "Default turn type"). A second copy of this arithmetic
// would let the prior vote on a different classification than the session reports.
//
// `uIn`/`uOut` are UNWRAPPED bearings: uOut may legitimately sit 200 deg from uIn.
// Engine 0.13.0 (Jan, 7 Sep 2026): a course change may be 35° or 60°, but a tack or a jibe
// needs a real sweep. Below this net angle a sweep is filed as a course change — uncounted,
// with or without a wind axis — never a tack, a jibe or a generic turn. Corpus effect: 5 of
// 773 jibes reclassify; the course-change markers stay. Module-level because `classifySweep`
// is shared with the auto-wind prior and the turn-log rebuild, and lives outside the class.
const CLASSIFY_MIN_ANGLE_DEG = 90.0;

function classifySweep(uIn as Float, uOut as Float, windDeg as Number) as Number {
    // The classification floor comes first, ahead of the wind check: a 70° sweep is a course
    // change whether or not anyone knows where the wind is.
    if ((uOut - uIn).abs() < CLASSIFY_MIN_ANGLE_DEG) {
        return TurnDetector.KIND_REJECT;
    }
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

// THE TURN'S OWN NAME (engine 0.27.0, R4; watch 0.9.21). The same rule as `classifySweep`
// except for a sweep that crosses BOTH axes: it is named by the one it reached FIRST in its
// own sense of rotation, the phone's `classify_sweep(..., first_crossing=True)`. A jibe the
// rider carries on round through the wind as he crashes went through downwind first, and the
// middle of the sweep can sit nearer the tack. `classifySweep` keeps the middle reading,
// because AutoWind's prior asks a different question with it and moving it would move a wind.
// The first crossing is `abortCrossedKind`'s arithmetic, which already answered it for the
// aborted turn.
function classifyTurn(uIn as Float, uOut as Float, windDeg as Number) as Number {
    if ((uOut - uIn).abs() < CLASSIFY_MIN_ANGLE_DEG) {
        return TurnDetector.KIND_REJECT;
    }
    if (windDeg < 0) {
        return TurnDetector.KIND_TURN;
    }
    var k = abortCrossedKind(uIn, uOut, windDeg);
    return k == TurnDetector.KIND_NONE ? TurnDetector.KIND_REJECT : k;
}

// R5's question (engine 0.27.0, `_join_split`): does the heading change from `uA` to `uB`, the
// gap between two sweeps, pass either end of the wind axis?
function joinCrosses(uA as Float, uB as Float, windDeg as Number) as Boolean {
    if (windDeg < 0) {
        return false;
    }
    var a = wrapDeg180(uA - windDeg.toFloat());
    var b = a + (uB - uA);
    var lo = a < b ? a : b;
    var hi = a < b ? b : a;
    return Math.ceil(lo / 180.0).toNumber() * 180.0 <= hi;
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

// ---- THE ABORTED TURN'S NAME, AND ITS TWO WIND QUESTIONS (watch 0.9.20) ----
//
// Module scope for the reason `classifySweep` is: the detector asks them when the turn
// happens and `rebuildWindSplit` asks them again under every new axis, and the two must never
// drift. The thresholds are the phone's `turnAbortAxisDeg` (R2) and `turnAbortLuffDeg` (R3).
const ABORT_AXIS_DEG = 30.0;
const ABORT_LUFF_DEG = 20.0;

function posMod360(x as Float) as Float {
    return x - 360.0 * Math.floor(x / 360.0);
}

// The axis the sweep crossed FIRST in its own sense of rotation (engine 0.27.0's
// `first_crossing`), or KIND_NONE when it crossed neither. No classification floor: an
// aborted turn's angle says when the rider fell, not what he meant.
function abortCrossedKind(uIn as Float, uOut as Float, windDeg as Number) as Number {
    if (windDeg < 0) {
        return TurnDetector.KIND_NONE;
    }
    var twaIn = wrapDeg180(uIn - windDeg.toFloat());
    var twaOut = twaIn + (uOut - uIn);
    var m = 0;
    if (twaOut >= twaIn) {
        m = Math.ceil(twaIn / 180.0).toNumber();
        if (m * 180.0 > twaOut) {
            return TurnDetector.KIND_NONE;
        }
    } else {
        m = Math.floor(twaIn / 180.0).toNumber();
        if (m * 180.0 < twaOut) {
            return TurnDetector.KIND_NONE;
        }
    }
    return m % 2 == 0 ? TurnDetector.KIND_TACK : TurnDetector.KIND_JIBE;
}

// An aborted turn is named by the axis it crossed, or else by the axis its rotation was
// closing on (`_classify_aborted`): a rider luffing up from a broad reach who goes in short
// of the wind was tacking. No axis, no name: a generic turn.
function abortKind(uIn as Float, uOut as Float, windDeg as Number) as Number {
    if (windDeg < 0) {
        return TurnDetector.KIND_TURN;
    }
    var crossed = abortCrossedKind(uIn, uOut, windDeg);
    if (crossed != TurnDetector.KIND_NONE) {
        return crossed;
    }
    var twaEnd = wrapDeg180(uIn - windDeg.toFloat()) + (uOut - uIn);
    var sense = uOut >= uIn ? 1.0 : -1.0;
    var toHead = posMod360((0.0 - twaEnd) * sense);
    var toDown = posMod360((180.0 - twaEnd) * sense);
    return toHead <= toDown ? TurnDetector.KIND_TACK : TurnDetector.KIND_JIBE;
}

// R2 and R3 (engine 0.27.0, `_abort_reached_axis`). Only an aborted sweep that crossed
// nothing, named for the side the rider did NOT declare, is asked: did he FLY to within
// ABORT_AXIS_DEG of that axis, and gain ABORT_LUFF_DEG of heading toward it at speed? `lo`
// and `hi` are the flown heading range and `gain` the heading gained at speed, both relative
// to the entry heading, so the question can be asked again under any later axis.
function abortPasses(kind as Number, uIn as Float, uOut as Float, windDeg as Number,
        turnType as Number, flown as Boolean, lo as Float, hi as Float,
        gain as Float) as Boolean {
    if (kind != TurnDetector.KIND_TACK && kind != TurnDetector.KIND_JIBE) {
        return true;
    }
    if (abortCrossedKind(uIn, uOut, windDeg) != TurnDetector.KIND_NONE) {
        return true;
    }
    var gated = turnType == TURN_TYPE_BALANCED
        || (turnType == TURN_TYPE_TACKS ? kind == TurnDetector.KIND_JIBE
                                        : kind == TurnDetector.KIND_TACK);
    if (!gated) {
        return true;
    }
    if (!flown) {
        return false;
    }
    var offset = kind == TurnDetector.KIND_TACK ? 0.0 : 180.0;
    var twaIn = wrapDeg180(uIn - windDeg.toFloat());
    var a = twaIn + lo;
    var b = twaIn + hi;
    var closest = 0.0;
    if (sweepCrossing(a, b, offset, 0.5 * (a + b)) == SWEEP_NO_CROSS) {
        var da = wrapDeg180(a - offset).abs();
        var db = wrapDeg180(b - offset).abs();
        closest = da < db ? da : db;
    }
    if (closest > ABORT_AXIS_DEG) {
        return false;
    }
    return gain >= ABORT_LUFF_DEG;
}

// Live turn detection + outcome classification (docs/algorithms/turns.md "Turn detection &
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
// RECOVER_HOLD_S), capped at LOOKAHEAD_NOT_RECOVERED_S past the sweep (0.9.19: the phone's
// 30 s tail for a rider who never gets going again — see the constant). Evidence is collected
// across the whole window: lost-the-foil (speed <= foilExit or submerged), stop spell below
// STOP_FLOOR_MPS, barometric submersion. Verdict: submerged or stop > FALL_STOP_S => fell in;
// else any loss => touchdown; else flew through.
//
// WHEN the verdict lands is its own rule (Jan, 22 September 2026). A fall is monotonic — once
// the stop spell passes FALL_STOP_S nothing later can make it anything else — so the window
// ends on that tick instead of running out the tail, and the buzz and the Turns page arrive
// while the rider is still in the water. The phone, reading the same FIT afterwards, reaches
// the same verdict off the same fact; only the wrist has a moment to be late for.
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
        EVENT_FELL = 4,
        // The quiet tail decided (device app 0.9.9, engine 0.17.0): `lastCleanJibe` says
        // which way. Fired up to CLEAN_QUIET_S after the sweep, after EVENT_FLEW has
        // already been returned for the same turn — the outcome is final at EVENT_FLEW, the
        // star is not. Consumers that log or mark *outcomes* must ignore it.
        EVENT_CLEAN_SETTLED = 5
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
    const MIN_ANGLE_DEG = 60.0;     // the CANDIDATE floor; see CLASSIFY_MIN_ANGLE_DEG below
    const MAX_DURATION_S = 8.0;     // measured 7 Sep 2026: 12 s bought 6 jibes and cost 26 clean ones on the corpus, so it stays
    const PEAK_RATE_DEG_S = 18.0;   // engine 0.14.0 (was 25): a carved jibe at 11 kn on 25 m turns at a steady ~13–22°/s and never spikes to 25
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
    // `turnOutcomeLookahead`. Since 0.9.19 NOTHING READS IT: the window is capped by the
    // not-recovered value below, and the phone's other two uses of the 12 s number —
    // `axisAfterDeg` and the not-recovered flag itself — are one the watch does not publish
    // and one it does not need (on the wrist "he has not recovered" is just "the window is
    // still open"). Kept because it is the phone's parameter and because setting the cap
    // below equal to it is the documented way to switch the whole rule off.
    const LOOKAHEAD_S = 12.0;
    // A FALL THE TURN CAUSED IS THE TURN'S FALL (engine 0.24.0, ADR-032; watch 0.9.19).
    // `LOOKAHEAD_S` is sized for a foil that STALLS: bleed off from foiling speed and you are
    // at a standstill inside 12 s. A learner who mushes slowly out of a jibe is still making
    // way at 12 s and coasts to a stop a little after it — on the corpus the median is exactly
    // 12 s, at the cap — so the turn read `touchdown` and the stop it ended in was booked all
    // over again by the flight-end channel. While the rider has NOT RECOVERED the window
    // follows him this far instead. Recovery still closes it wherever it happens, so this only
    // ever lengthens a window that had nothing to close it; set it equal to `LOOKAHEAD_S` and
    // the detector is 0.9.18's exactly.
    const LOOKAHEAD_NOT_RECOVERED_S = 30.0;
    const RECOVER_PCT = 0.70;
    const RECOVER_HOLD_S = 2.0;
    const SUCCESS_PCT = 70;
    // THE QUIET TAIL (engine 0.17.0, Jan 7 Sep 2026: "no touch down or fall within 10 s
    // afterwards" for a clean jibe). The outcome window closes at recovery, often 3–5 s past
    // the sweep, so a touchdown at +7 s was invisible to the star. A clean candidate is now
    // held for CLEAN_QUIET_S after the sweep end and withdrawn if the foil is lost for
    // QUIET_OFF_FOIL_S or the wrist goes under; the outcome itself is not touched.
    const CLEAN_QUIET_S = 10.0;
    const QUIET_OFF_FOIL_S = 1.0;
    const DEG2RAD = 0.017453292;

    // How long an unowned flight end is judged for, before its evidence is called. The turn
    // window's own cap, reused deliberately: one physical question ("did he stop, and for how
    // long") deserves one set of numbers however the loss started. Since 0.9.19 that is the
    // NOT-RECOVERED cap, because the phone's `flightend.py` reads the very same
    // `evidence.outcome_tail` the turns do — a rider who ventilates on a straight reach and
    // coasts to a stop at 20 s is a swim on both sides now, not a glide-out on the wrist.
    const FLIGHT_END_WINDOW_S = LOOKAHEAD_NOT_RECOVERED_S;

    // ---- THE ABORTED TURN (engine 0.21.0 / 0.27.0, ADR-028 and ADR-037; watch 0.9.20) ----
    //
    // Jan, 20 Sep 2026: "an attempted turn that ends in the water is a turn that fell in." The
    // main scan wants MIN_ANGLE_DEG inside MAX_DURATION_S, and a rider who goes in halfway
    // round never gets there: the COG is read only above COG_SPEED_FLOOR, so the sailing run
    // ENDS AT THE FALL and what is left of the maneuver is the part he rode. Every one of Jan's
    // five wingfoil tack attempts was such a turn, and until 0.9.20 the wrist saw none of
    // them. So, the tick a sailing run ends below the COG floor with the detector idle, the
    // ring is read backwards from its last heading, exactly as `_abort_candidates` does on the
    // phone: the widest net change within MAX_DURATION_S, with the main scan's peak-rate,
    // carve and on-foil gates and only the angle lowered to ABORT_MIN_ANGLE_DEG. The
    // candidate is judged by the ordinary outcome window and COUNTED ONLY IF IT FELL IN
    // (`_merge_aborted`); a candidate that recovered or merely touched down is dropped and the
    // loss is the straight-line one it would have been. Never successful, never clean.
    const ABORT_MIN_ANGLE_DEG = 45.0;   // turnAbortMinAngle
    // R2 (turnAbortAxisDeg, ABORT_AXIS_DEG at module scope): an aborted sweep that crossed NO
    // axis and is named by the axis it was closing on must have been FLOWN to within 30 deg
    // of it. R3 (turnAbortLuffDeg / turnAbortLuffSpeedPct): ...and gained 20 deg of heading
    // toward it while still at this share of the entry speed. A tack starts with a luff on the foil;
    // a crash that rounds up loses the speed first. R2 and R3 gate only the side the rider did
    // NOT declare (`defaultTurnType`): a jibes rider's aborted tacks, a tacks rider's jibes.
    const ABORT_LUFF_SPEED_PCT = 0.80;
    // R1 (turnAbortAfterTurnS): an aborted candidate turning the same way as the previous
    // counted turn, starting before that turn's end + max(its outcome window, this), is the
    // tail of that turn and is dropped.
    const ABORT_AFTER_TURN_S = 3.0;
    // What a rebuild needs to re-judge an aborted turn under a NEW axis (R2 and R3 are
    // questions about the wind): the flown heading range and the gain at speed, both relative
    // to the entry heading. One record per aborted turn, 7 bytes, beside the turn log.
    const ABORT_MAX = 32;
    const ABORT_STRIDE = 7;

    // R5 (turnJoinGapS, engine 0.27.0; watch 0.9.21): two same-direction sweeps of one sailing
    // run at most this far apart, with the wind axis crossed in the gap between the first's
    // last heading and the second's first, are one rotation. The second is extended back to
    // where the first ended and named with it. Nothing else is joined.
    const JOIN_GAP_S = 2.0;
    // A join is a question about the wind, so a rebuild asks it again under every new axis:
    // one record per turn that had a same-direction sweep that close before it, 4 bytes.
    const JOIN_MAX = 16;
    const JOIN_STRIDE = 4;

    // 8 s sweep cap + 3 s entry window + margin, at 1 Hz
    const HIST = 14;
    // The speed history the score, the entry speed and the recovery search read (0.9.21): every
    // tick, whatever the state machine is doing, so a sweep joined back across the gap (R5)
    // still finds the speeds it now starts at. 8 s sweep + 2 s gap + 3 s entry + margin.
    const SPEED_HIST = 16;

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
    // after (docs/presentation/clean-jibe.md "Clean jibe", docs/algorithms/turns.md "Glossary"). Kept as its own
    // counter rather than derived, because success and kind are decided at different moments —
    // kind when the sweep closes, success when the outcome window resolves — and the only place
    // both are known is `_resolve()`.
    var cleanJibeCount as Number = 0;
    // FLEW-THROUGH, PER KIND (device app 0.9.17, the Tacks & jibes page). `flewCount` counts
    // every counted turn he kept the foil through; these two split that number the way
    // `tackCount` / `jibeCount` split `turnCount`, so the page can say "12 jibes, flew 9"
    // without the rider doing the arithmetic. Two counters and not a derivation, for the same
    // reason `cleanJibeCount` is one: the KIND is fixed when the sweep closes and the OUTCOME
    // when the window resolves, and `_resolve()` is the only place that knows both.
    //
    // REBUILT WHENEVER THE AXIS CHANGES (0.9.18). These are counted live as turns resolve and
    // then thrown away and recomputed from the turn log by `rebuildWindSplit`, so a turn the
    // rider rode before the estimator spoke is named the same as one he rode after. Until
    // 0.9.18 a one-shot backfill added to `tackCount` / `jibeCount` alone and left these
    // behind, and a pre-lock jibe was a jibe with no rung.
    var tackFlewCount as Number = 0;
    var jibeFlewCount as Number = 0;
    // THE OTHER TWO RUNGS, PER KIND (device app 0.9.18). 0.9.17 split only the ladder's TOP
    // rung by kind, which was enough for a page that said "jibes, flew 38" and not enough for
    // one that draws the whole ladder per kind — and drawing the whole ladder per kind is what
    // the Tacks & jibes page does since this round (Jan's layout review, 21 Sep 2026: one wide
    // row per kind, the same colour language the Turns page uses).
    //
    // Counted exactly where `touchdownCount` and `fellCount` are, off the same `lastKind`, for
    // the reason the flew pair is: kind is fixed when the sweep closes, outcome when the
    // window resolves, and `_resolve()` is the only place that knows both.
    //
    // THE INVARIANT, and since 0.9.18 it is an equality rather than a bound. With a wind axis
    // set,
    //   jibeFlewCount + jibeTouchCount + jibeFellCount == jibeCount
    //   tackFlewCount + tackTouchCount + tackFellCount == tackCount
    // at all times — because all eight numbers are rebuilt together from the turn log every
    // time the axis changes (`rebuildWindSplit`). 0.9.17 could only promise it for turns typed
    // after the lock; the rows on the Tacks & jibes page add up now.
    var tackTouchCount as Number = 0;
    var tackFellCount as Number = 0;
    var jibeTouchCount as Number = 0;
    var jibeFellCount as Number = 0;
    // Was the turn that just resolved a clean jibe? Published beside `lastOutcome` so a caller
    // that already reacts to a resolved turn can tell the two apart without a second event
    // nibble; false again on the next turn that is not one.
    var lastCleanJibe as Boolean = false;
    // A clean candidate waiting out its quiet tail. While true, `lastCleanJibe` is not yet
    // this turn's answer and the clean-jibe buzz must wait for EVENT_CLEAN_SETTLED.
    var cleanPending as Boolean = false;
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

    // Turn streaks (docs/algorithms/pumping.md "Turn streaks"). A tally says how the session went;
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
    // Rejected sweeps — bear-aways and round-ups — still increment nothing. A fall after one
    // arrives as an unowned flight end and breaks the run through exactly the path above, and
    // since 0.9.21 so does one that starts INSIDE it: the end's verdict waits for the sweep,
    // and only a counted turn owns it (`_claimEnd` / `_ownEnd` / `_releaseEnd`, ADR-035). Counting a course change as a maneuver would make a streak depend on how
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

    // The rider's declared habit (AppSettings.windDefaultTurnType), set live by MetricsEngine
    // the way AutoWind's is: it decides which side of an aborted turn R2 and R3 gate.
    var defaultTurnType as Number = TURN_TYPE_JIBES;
    // Aborted turns counted (all of them fell in by definition). Inside `turnCount` and
    // `fellCount`; published on its own for the tests and the summary.
    var abortedCount as Number = 0;

    hidden var _tArr as Array<Float>;
    hidden var _uArr as Array<Float>;
    hidden var _dArr as Array<Float>;
    hidden var _vArr as Array<Float>;
    // Was the board flying at each ring sample? R2 asks for the closest FLOWN heading.
    hidden var _fArr as Array<Boolean>;

    // The open aborted candidate, and the previous counted turn R1 compares it with.
    hidden var _aborted as Boolean = false;
    hidden var _abortKind as Number = KIND_NONE;
    hidden var _abortLo as Float = 0.0;     // flown heading range, relative to the entry
    hidden var _abortHi as Float = 0.0;
    hidden var _abortFlown as Boolean = false;
    hidden var _abortGain as Float = 0.0;   // heading gained in the sweep's sense at speed
    hidden var _prevEndT as Float = -1000.0;
    hidden var _prevDir as Number = 0;
    hidden var _prevWinS as Float = 0.0;
    // The recording ended in the water (engine 0.28.0, turnRecordingEndS): set by `finish`.
    hidden var _endFell as Boolean = false;
    hidden var _abortLog as ByteArray;
    hidden var _abortN as Number = 0;
    // R5's memory: the last sweep that closed, while its sailing run lasts.
    hidden var _joinOk as Boolean = false;
    hidden var _joinT as Float = 0.0;
    hidden var _joinU as Float = 0.0;
    hidden var _joinDir as Number = 0;
    // The open sweep: its own start (`_startU` is the joined one), the clock its duration cap
    // runs from, and whether it had a sweep close enough before it to be joined (and the
    // heading change across that gap) so the log can ask again under a later axis.
    hidden var _ownStartU as Float = 0.0;
    hidden var _capT as Float = 0.0;
    hidden var _gapOk as Boolean = false;
    hidden var _gapDeg as Float = 0.0;
    hidden var _joinLog as ByteArray;
    hidden var _joinN as Number = 0;
    // the always-on speed history
    hidden var _sT as Array<Float>;
    hidden var _sV as Array<Float>;
    hidden var _sIdx as Number = 0;
    hidden var _sCount as Number = 0;
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
    hidden var _minT as Float = 0.0;      // the clock of the speed minimum: recovery is searched after it
    hidden var _stopRun as Float = 0.0;
    hidden var _stopMax as Float = 0.0;
    hidden var _lostFoil as Boolean = false;
    hidden var _wet as Boolean = false;
    hidden var _recoverHeld as Float = 0.0;
    // THE RECOVERY SEARCH (0.9.21, the phone's `recovery_end`). Recovery is searched from the
    // speed MINIMUM, not from the sweep end, and held with the both-ends convention: a sample
    // at the threshold whose predecessor was too. Where it is found is where the phone stops
    // judging, so the evidence at that moment is kept: the minimum is not final until
    // MIN_SPEED_LAG_S past the sweep, and a later one moves the search on.
    hidden var _recLast as Boolean = false;
    hidden var _recovered as Boolean = false;
    hidden var _recLost as Boolean = false;
    hidden var _recWet as Boolean = false;
    hidden var _recStopMax as Float = 0.0;
    // the quiet tail: when it ends, and the off-foil spell inside it (both-ends convention)
    hidden var _cleanPendingUntil as Float = 0.0;
    hidden var _quietOffRun as Float = 0.0;
    hidden var _quietWasOff as Boolean = false;

    // ---- THE TURN LOG (device app 0.9.18) ----
    //
    // One record per counted turn: enough geometry to re-type it against a wind axis, plus
    // the verdict it earned. It is what makes `rebuildWindSplit` exact — every per-kind
    // counter is thrown away and recomputed from these records whenever the axis changes, so
    // a kind's three rungs sum to that kind's count at all times with a wind set, and a turn
    // the rider rode before the estimator spoke is typed the same as one he rode after.
    //
    // It replaces the one-shot `backfillWindSplit` and the sweep log that fed it. That pass
    // ran ONCE, at the first auto lock, and it only ever ADDED to `tackCount` / `jibeCount`:
    // the outcome rungs and the clean count were left behind, because the sweep log is
    // written when a sweep CLOSES and at that moment the outcome window has not resolved.
    // This log is written when the outcome resolves, which is the moment both halves exist.
    //
    // A BYTE ARRAY, four bytes a turn, because this is the one structure on the watch whose
    // size is a session's length rather than a constant:
    //
    //   b0   entry bearing, low 8 bits            (0..359 needs nine)
    //   b1   bit 0    entry bearing, bit 8
    //        bits 1-2 outcome (OUTCOME_FLEW / TOUCHDOWN / FELL)
    //        bit 3    CLEAN-ELIGIBLE: the score cleared the bar, the foil held across the
    //                 scored window, and the quiet tail ran out without a loss
    //   b2-3 net rotation, signed, +32768 and big-endian. It may exceed +-180 and the sign
    //        is the sweep's direction, which is what types it
    //
    // Clean-eligible rather than "clean" is the whole reason the rebuild can fix the count:
    // whether a turn is a CLEAN JIBE depends on the kind, and the kind is what is being
    // re-decided. A successful fly-through that was a generic turn at the time becomes a
    // clean jibe the moment an axis says it was a jibe — which is exactly the under-read
    // docs/algorithms.md used to carry as a divergence.
    //
    // THE CAP is TURN_LOG_MAX turns, 2 KB. A turn every thirty seconds for four hours is 480,
    // so a real session does not reach it. Beyond it the OLDEST record is dropped, and before
    // it goes it is typed against the axis in force at that moment and folded into a frozen
    // base (`_baseTack` and the rest) that every rebuild starts from. That keeps the invariant
    // exact even past the cap: what a rebuild cannot do for a dropped turn is re-type it
    // against an axis the rider changes LATER, and a turn 512 maneuvers ago was ridden hours
    // after the estimator locked, so there is nothing left to correct.
    const TURN_LOG_MAX = 512;
    const TURN_LOG_STRIDE = 4;
    hidden var _log as ByteArray;
    hidden var _logN as Number = 0;       // records held, oldest first
    // The frozen contribution of records the cap has dropped. Eleven counters, the same
    // eleven `rebuildWindSplit` recomputes; all zero on a session that never fills the log.
    hidden var _baseTack as Number = 0;
    hidden var _baseJibe as Number = 0;
    hidden var _baseTackFlew as Number = 0;
    hidden var _baseTackTouch as Number = 0;
    hidden var _baseTackFell as Number = 0;
    hidden var _baseJibeFlew as Number = 0;
    hidden var _baseJibeTouch as Number = 0;
    hidden var _baseJibeFell as Number = 0;
    hidden var _baseClean as Number = 0;
    hidden var _basePort as Number = 0;
    hidden var _baseStbd as Number = 0;

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
    // An end that a sweep or an aborted candidate may yet own (0.9.21). Only a COUNTED turn
    // owns a flight end (ADR-035): one inside a sweep that turns out a bear-away, or an
    // aborted candidate that is dropped, is the straight-line end it would have been. So it is
    // judged as usual while the question is open, and its verdict waits (`_endDue`) for the
    // answer: kept when the turn is not counted, thrown away when it is.
    hidden var _endProvisional as Boolean = false;
    hidden var _endDue as Boolean = false;

    // Thresholds live in an injected Config (see FlightDetector) — read live every tick, so
    // a wind axis set mid-session classifies every turn detected from then on.
    hidden var _cfg as Config;

    function initialize(cfg as Config) {
        _cfg = cfg;
        _tArr = new Array<Float>[HIST];
        _uArr = new Array<Float>[HIST];
        _dArr = new Array<Float>[HIST];
        _vArr = new Array<Float>[HIST];
        _fArr = new Array<Boolean>[HIST];
        for (var i = 0; i < HIST; i++) {
            _tArr[i] = 0.0;
            _uArr[i] = 0.0;
            _dArr[i] = 0.0;
            _vArr[i] = 0.0;
            _fArr[i] = false;
        }
        _abortLog = new [ABORT_MAX * ABORT_STRIDE]b;
        _joinLog = new [JOIN_MAX * JOIN_STRIDE]b;
        _sT = new Array<Float>[SPEED_HIST];
        _sV = new Array<Float>[SPEED_HIST];
        for (var i = 0; i < SPEED_HIST; i++) {
            _sT[i] = 0.0;
            _sV[i] = 0.0;
        }
        // 2 KB, allocated once. A ByteArray and not an Array<Number>: this is the only
        // structure here whose size is a session's length, and four Numbers a turn would be
        // four times the bytes and a boxed read on every rebuild.
        _log = new [TURN_LOG_MAX * TURN_LOG_STRIDE]b;
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
        _sIdx = (_sIdx + 1) % SPEED_HIST;
        _sT[_sIdx] = _clockS;
        _sV[_sIdx] = speedMps;
        if (_sCount < SPEED_HIST) {
            _sCount++;
        }
        // Before the state machine, and on every tick whatever state it is in: the edge this
        // watches for is the one the state machine does not see.
        _flightEndTick(dt, speedMps, flying, submerged);
        // Likewise the quiet tail: it outlives the outcome window and runs whatever the
        // state machine is doing, including the next sweep.
        var settled = _quietTick(dt, speedMps, flying, submerged);

        // THE ABORTED TURN: the sailing run ends here, below the COG floor, with nothing being
        // judged. Before `_unwrap` forgets the ring, ask whether it was still turning.
        if (state == ST_IDLE && _haveCog && _count >= 2 && speedMps < COG_SPEED_FLOOR) {
            // On success the state is ST_OUTCOME and `_outcomeTick` below collects this
            // tick's evidence, so nothing is tracked twice.
            _abortScan(flying);
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
        if (event == EVENT_NONE && settled) {
            event = EVENT_CLEAN_SETTLED;
        }
        return event;
    }

    // The quiet tail, one sample at a time. Off the foil here is what the phone's flying mask
    // says: not in a flight, or below foilExit, or under water. A spell of QUIET_OFF_FOIL_S
    // (both-ends convention, so two consecutive off-foil samples at 1 Hz) or any submerged
    // sample withdraws the candidate; the clock running out grants it. Returns true on the
    // tick the answer is known.
    hidden function _quietTick(dt as Float, speedMps as Float, flying as Boolean,
            submerged as Boolean) as Boolean {
        if (!cleanPending) {
            return false;
        }
        var offFoil = !flying || submerged || speedMps <= _cfg.foilExitMps;
        if (offFoil && _quietWasOff) {
            _quietOffRun += dt;
        } else {
            _quietOffRun = 0.0;
        }
        _quietWasOff = offFoil;
        if (submerged || _quietOffRun >= QUIET_OFF_FOIL_S) {
            cleanPending = false;
            lastCleanJibe = false;
            return true;
        }
        if (_clockS >= _cleanPendingUntil) {
            cleanPending = false;
            // The tail ran out clean: the turn is clean-ELIGIBLE whatever it was named, and a
            // clean JIBE only if the axis in force calls it one. The two halves are separate
            // since 0.9.18 so that a later axis can still award the star (rebuildWindSplit).
            _markCleanEligible();
            if (lastKind == KIND_JIBE) {
                lastCleanJibe = true;
                cleanJibeCount++;
            }
            return true;
        }
        return false;
    }

    // Set the clean-eligible bit on the newest log record. The quiet tail always ends before
    // the next turn resolves — it is CLEAN_QUIET_S from the sweep end and a second sweep
    // cannot even open until the outcome window closes — so "newest" is this turn's.
    hidden function _markCleanEligible() as Void {
        if (_logN <= 0) {
            return;
        }
        var at = (_logN - 1) * TURN_LOG_STRIDE + 1;
        _log[at] = _log[at] | 0x08;
    }

    // GPS gap / pause: heading continuity and the detection window are both broken.
    function onGap() as Void {
        _haveCog = false;
        _joinOk = false;
        _sCount = 0;            // the phone's arrays end at a gap too
        if (state == ST_IDLE) {
            _count = 0;
        }
        // a hold never bridges a hole
        if (!_recovered) {
            _recoverHeld = 0.0;
            _recLast = false;
        }
        // An unjudgeable end is dropped, not called a fall: a GPS gap is missing evidence,
        // and "he might have swum" must never break a run the rider actually kept.
        _endOpen = false;
        _endProvisional = false;
        _endDue = false;
        // Same for the quiet tail: the phone's window stops at a gap and calls what it saw,
        // and what it saw was nothing against the star. Settled on the next tick.
        if (cleanPending) {
            _cleanPendingUntil = _clockS;
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
            _joinOk = false;    // R5 joins two sweeps of one sailing run only
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

    hidden function _push(u as Float, speedMps as Float, flying as Boolean) as Void {
        _idx = (_idx + 1) % HIST;
        _tArr[_idx] = _clockS;
        _uArr[_idx] = u;
        _dArr[_idx] = _distM;
        _vArr[_idx] = speedMps;
        _fArr[_idx] = flying;
        if (_count < HIST) {
            _count++;
        }
    }

    // Backwards scan of the ring: widest qualifying sweep ending at this sample.
    hidden function _scan(u as Float, speedMps as Float, flying as Boolean) as Number {
        _push(u, speedMps, flying);
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
        _ownStartU = _startU;
        _capT = _startT;
        _endT = _clockS;
        _endU = u;

        // R5: a sweep that closed at most JOIN_GAP_S before this one started, turning the
        // same way in the same sailing run. When the axis was crossed in the gap, neither
        // sweep saw it: this one starts again where the other ended.
        _gapOk = false;
        _gapDeg = 0.0;
        var dir = u >= _startU ? 1 : -1;
        if (_joinOk && _joinDir == dir && _startT > _joinT
                && _startT - _joinT <= JOIN_GAP_S) {
            _gapOk = true;
            _gapDeg = _startU - _joinU;
            if (joinCrosses(_joinU, _startU, _cfg.windDirection)) {
                _startT = _joinT;
                _startU = _joinU;
            }
        }

        _resetEvidence();
        // Entry speed: max over the ENTRY_WINDOW_S before the start. The minimum: over the
        // sweep so far, the start included, its EARLIEST sample on a tie (`np.argmin`), since
        // recovery is searched after it. Both off the speed history, which reaches back past
        // a join.
        _entrySpeed = 0.0;
        _minSpeed = speedMps + 1.0;     // this sample is in the history: the loop finds it
        _minT = _clockS;
        var oldest = (_sIdx - _sCount + 1 + SPEED_HIST) % SPEED_HIST;
        var k = oldest;
        for (var n = 0; n < _sCount; n++) {
            var t = _sT[k];
            if (t >= _startT - ENTRY_WINDOW_S && t <= _startT && _sV[k] > _entrySpeed) {
                _entrySpeed = _sV[k];
            }
            if (t >= _startT && _sV[k] < _minSpeed) {
                _minSpeed = _sV[k];
                _minT = t;
            }
            k = (k + 1) % SPEED_HIST;
        }
        _replayRecovery(_clockS);

        _count = 0;
        state = ST_SWEEP;
        _claimEnd();
    }

    // The recovery search over the samples already behind us, from the speed minimum up to
    // and including `untilT`, so a turn opened late finds a recovery the phone would have.
    hidden function _replayRecovery(untilT as Float) as Void {
        var k = (_sIdx - _sCount + 1 + SPEED_HIST) % SPEED_HIST;
        var prevT = -1.0;
        for (var n = 0; n < _sCount; n++) {
            var t = _sT[k];
            if (t > _minT && t <= untilT) {
                _recoverStep(prevT >= 0.0 ? t - prevT : 0.0, _sV[k], false);
            }
            prevT = t;
            k = (k + 1) % SPEED_HIST;
        }
    }

    // One sample of the recovery search. `newMin` is a sample that just became the speed
    // minimum: the search starts again after it, whatever it had found.
    hidden function _recoverStep(dt as Float, speedMps as Float, newMin as Boolean) as Void {
        if (newMin) {
            _recovered = false;
            _recoverHeld = 0.0;
            _recLast = false;
            return;
        }
        if (_recovered) {
            return;
        }
        var thr = RECOVER_PCT * _entrySpeed;
        if (thr < _cfg.foilEntryMps) {
            thr = _cfg.foilEntryMps;     // nothing below foil entry is flying
        }
        if (speedMps < thr) {
            _recoverHeld = 0.0;
            _recLast = false;
            return;
        }
        _recoverHeld = _recLast ? _recoverHeld + dt : 0.0;
        _recLast = true;
        if (_recoverHeld >= RECOVER_HOLD_S) {
            _recovered = true;
            _recLost = _lostFoil;
            _recWet = _wet;
            _recStopMax = _stopMax;
        }
    }

    // A turn has opened: a flight end that began at or after its start is the turn's to own,
    // if it is counted. Until it is known, the end keeps collecting and its verdict waits.
    hidden function _claimEnd() as Void {
        if (_endOpen && _endStartS >= _startT) {
            _endProvisional = true;
        }
    }

    // The turn was counted: the end is its own, and the straight-line channel forgets it.
    hidden function _ownEnd() as Void {
        if (_endProvisional) {
            _endOpen = false;
            _endProvisional = false;
            _endDue = false;
        }
    }

    // The turn was not counted: the end is a straight-line one after all, judged now if its
    // evidence was already in.
    hidden function _releaseEnd() as Void {
        if (!_endProvisional) {
            return;
        }
        _endProvisional = false;
        if (_endDue) {
            _endDue = false;
            _closeFlightEnd();
        }
    }

    hidden function _resetEvidence() as Void {
        _stopRun = 0.0;
        _stopMax = 0.0;
        _lostFoil = false;
        _wet = false;
        _recoverHeld = 0.0;
        _recLast = false;
        _recovered = false;
        _endFell = false;
    }

    // ---- the aborted turn ----

    // Read the ring backwards from its LAST heading (the newest slot: the run ends on this
    // tick, below the COG floor, so nothing newer will come). Opens an outcome window on a
    // candidate and returns true; the window's verdict decides whether it counts.
    hidden function _abortScan(flyingNow as Boolean) as Boolean {
        var j = _idx;
        var tj = _tArr[j];
        var uj = _uArr[j];
        var i = -1;
        var best = 0.0;
        var k = j;
        for (var back = 1; back < _count; back++) {
            k = (k - 1 + HIST) % HIST;
            if (tj - _tArr[k] > MAX_DURATION_S) {
                break;
            }
            var n = (uj - _uArr[k]).abs();
            if (n > best) {
                best = n;
                i = k;
            }
        }
        if (i < 0 || best < ABORT_MIN_ANGLE_DEG) {
            return false;
        }
        // the main scan's gates, unchanged: a peak-rate step, the carve, and the foil
        var peak = 0.0;
        var onFoil = _fArr[i];
        k = j;
        while (k != i) {
            var p = (k - 1 + HIST) % HIST;
            var step = _tArr[k] - _tArr[p];
            if (step > 0.0) {
                var r = ((_uArr[k] - _uArr[p]) / step).abs();
                if (r > peak) {
                    peak = r;
                }
            }
            if (_fArr[k]) {
                onFoil = true;
            }
            k = p;
        }
        if (peak < PEAK_RATE_DEG_S) {
            return false;
        }
        if (!onFoil && _tArr[i] - _lastFlyingS > CONTEXT_AFTER_S) {
            return false;
        }
        var arc = _dArr[j] - _dArr[i];
        if (arc < MIN_ARC_M || arc / (best * DEG2RAD) < MIN_RADIUS_M) {
            return false;
        }
        var ui = _uArr[i];
        var dir = uj >= ui ? 1 : -1;
        // R1: the tail of the turn before, turning the same way
        var tail = _prevWinS > ABORT_AFTER_TURN_S ? _prevWinS : ABORT_AFTER_TURN_S;
        if (_prevDir == dir && _tArr[i] <= _prevEndT + tail) {
            return false;
        }
        // entry speed, the same max-over-the-entry-window `_openSweep` takes
        var entry = _vArr[i];
        var older = _count - 1 - ((j - i + HIST) % HIST);    // valid slots before the entry
        k = i;
        for (var back = 0; back < older; back++) {
            k = (k - 1 + HIST) % HIST;
            if (_tArr[i] - _tArr[k] > ENTRY_WINDOW_S) {
                break;
            }
            if (_vArr[k] > entry) {
                entry = _vArr[k];
            }
        }
        // R2/R3 evidence, forward from the entry: the flown heading range and the gain at
        // speed. A heading is FLOWN when the board flew at it and at the next sample.
        var lo = 0.0;
        var hi = 0.0;
        var flown = false;
        var gain = 0.0;
        var minV = _vArr[i];
        var minT = _tArr[i];
        var floor = ABORT_LUFF_SPEED_PCT * entry;
        k = i;
        while (true) {
            var rel = _uArr[k] - ui;
            if (_vArr[k] < minV) {
                minV = _vArr[k];
                minT = _tArr[k];
            }
            if (_vArr[k] >= floor && dir * rel > gain) {
                gain = dir * rel;
            }
            var nextFlying = k == j ? flyingNow : _fArr[(k + 1) % HIST];
            if (_fArr[k] && nextFlying) {
                if (!flown || rel < lo) { lo = rel; }
                if (!flown || rel > hi) { hi = rel; }
                flown = true;
            }
            if (k == j) {
                break;
            }
            k = (k + 1) % HIST;
        }
        var wind = _cfg.windDirection;
        var kind = abortKind(ui, uj, wind);
        if (!abortPasses(kind, ui, uj, wind, defaultTurnType, flown, lo, hi, gain)) {
            return false;   // the course change stays on the map; the fall is a straight one
        }
        _startT = _tArr[i];
        _startU = ui;
        _endT = tj;
        _endU = uj;
        _entrySpeed = entry;
        _minSpeed = minV;
        _minT = minT;
        _gapOk = false;
        _resetEvidence();
        // this tick is tracked by `_outcomeTick` below, so the replay stops at the last one
        _replayRecovery(tj);
        _aborted = true;
        _abortKind = kind;
        _abortLo = lo;
        _abortHi = hi;
        _abortFlown = flown;
        _abortGain = gain;
        _count = 0;
        state = ST_OUTCOME;
        _claimEnd();            // the turn owns this loss if it counts, and only then
        return true;
    }

    // An aborted candidate's verdict. Counted only as a fall; anything else is dropped and
    // the loss is the straight-line end it would otherwise have been.
    hidden function _resolveAborted() as Number {
        _aborted = false;
        state = ST_IDLE;
        _count = 0;
        if (!(_wet || _stopMax > FALL_STOP_S || _endFell)) {
            _releaseEnd();          // the loss is a straight-line one, judged as such
            return EVENT_NONE;
        }
        _ownEnd();
        var kind = _abortKind;
        lastKind = kind;
        turnCount++;
        lapTurnCount++;
        abortedCount++;
        fellCount++;
        if (kind == KIND_TACK) {
            tackCount++;
            tackFellCount++;
        } else if (kind == KIND_JIBE) {
            jibeCount++;
            jibeFellCount++;
        }
        countEntrySide(_startU);
        dryStreak = 0;
        flewStreak = 0;
        var pct = 0;
        if (_entrySpeed > 0.0) {
            pct = (_minSpeed / _entrySpeed * 100.0).toNumber();
            if (pct > 100) { pct = 100; } else if (pct < 0) { pct = 0; }
        }
        lastOutcome = OUTCOME_FELL;
        lastScorePct = pct;     // reported, never a best: an aborted turn is never successful
        lastCleanJibe = false;
        _logTurn(_startU, _endU - _startU, OUTCOME_FELL, false, true);
        _abortLogAdd(_logN - 1, _abortFlown, _abortLo, _abortHi, _abortGain);
        _notePrev();
        return EVENT_FELL;
    }

    // R1's memory: the counted turn just resolved.
    hidden function _notePrev() as Void {
        _prevEndT = _endT;
        _prevDir = _endU >= _startU ? 1 : -1;
        _prevWinS = _clockS - _endT;
    }

    // THE RECORDING ENDS IN THE WATER (engine 0.28.0, `turnRecordingEndS`; watch 0.9.20).
    // Called once by SessionController before the FIT session fields are written. A turn
    // window still open — the rider came off the foil, never recovered, and is below the stop
    // floor as the activity stops — is a fall: the file ends with him in the water. The 10 Aug
    // 2025 tack read `touchdown` on the phone until 0.28.0 for exactly this reason. Returns the
    // event so a caller can log it; nothing buzzes at save.
    function finish() as Number {
        if (state != ST_OUTCOME) {
            return EVENT_NONE;
        }
        if (!_recovered && _lostFoil && _lastSpeed < STOP_FLOOR_MPS) {
            _endFell = true;
        }
        return _resolve();
    }

    // Follow the rotation while it is still turning, so classification sees the whole sweep.
    hidden function _sweep(dt as Float, u as Float?, speedMps as Float,
            submerged as Boolean) as Number {
        _track(dt, speedMps, submerged);
        if (u != null) {
            var step = _clockS - _endT;
            var rate = step > 0.0 ? ((u as Float) - _endU) / step : 0.0;
            // the cap runs from the sweep's own start: a join (R5) adds the gap, not a limit
            if (rate.abs() >= CONTINUE_RATE_DEG_S && _clockS - _capT <= MAX_DURATION_S) {
                _endU = u as Float;
                _endT = _clockS;
                return EVENT_NONE;
            }
        }
        // Published before the verdict, so the geometry is fresh whatever the verdict is. The
        // sweep's OWN geometry: it is what AutoWind learns from (the phone's wind never sees a
        // join) and what the log keeps, with the gap beside it (`_joinLogAdd`).
        lastEntryU = _ownStartU;
        lastNetDeg = _endU - _ownStartU;
        // R5's memory, for a sweep that starts within JOIN_GAP_S of this one's end
        _joinOk = _haveCog;     // a sweep the sailing run ended has nothing to join
        _joinT = _endT;
        _joinU = _endU;
        _joinDir = _endU >= _ownStartU ? 1 : -1;
        var kind = _classify(_startU, _endU);
        if (kind == KIND_REJECT) {
            rejectedCount++;        // bear-away / round-up: real course change, not a maneuver
            state = ST_IDLE;
            _count = 0;
            _releaseEnd();          // a fall inside it is a straight-line one (ADR-035)
            return EVENT_NONE;
        }
        _ownEnd();
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
        // RECOVERY closes the window, judged on the evidence at the sample it was found
        // (0.9.21). It may have been found inside the sweep, after an early minimum, which is
        // where the phone stops judging too; it is only final once the minimum is, at
        // MIN_SPEED_LAG_S past the sweep.
        if (_recovered && _clockS >= _endT + MIN_SPEED_LAG_S) {
            return _resolve();
        }
        // THE VERDICT LANDS AT THE STOP (Jan, 22 September 2026). The 30 s tail is there so a
        // slow mush-out is still the turn's fall; it is NOT a delay the rider should feel. Once
        // the stop spell has passed FALL_STOP_S the answer is already `fell in` and no further
        // evidence can move it — `_resolve` reads the same `_stopMax` on its top rung, and
        // `_stopMax` only ever grows. So the fall is called here, on that tick, and the buzz
        // and the Turns page land while the rider is still in the water rather than half a
        // minute later. A fall never un-falls, which is what makes ending the window early the
        // same verdict and not a guess at one.
        //
        // The score is untouched: it closes at `_endT + MIN_SPEED_LAG_S` (2 s), and a stop
        // spell cannot exceed 5 s before `_endT + 6 s` — the sweep itself is above
        // COG_SPEED_FLOOR throughout, so `_stopMax` is 0 when the window opens.
        if (_stopMax > FALL_STOP_S && !_recovered) {
            return _resolve();
        }
        // The cap is the NOT-RECOVERED one (0.9.19): only a rider who never gets going again
        // is followed this far, which is the whole of ADR-032.
        if (_clockS < _endT + LOOKAHEAD_NOT_RECOVERED_S) {
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
    //                 recovery-gated window (up to end + LOOKAHEAD_NOT_RECOVERED_S). A
    //                 touchdown five seconds after a cleanly-carried jibe is that jibe's
    //                 outcome, but it is not part of the speed it was scored on.
    hidden function _track(dt as Float, speedMps as Float, submerged as Boolean) as Void {
        if (submerged) {
            _wet = true;
        }
        var newMin = false;
        if (state != ST_OUTCOME || _clockS <= _endT + MIN_SPEED_LAG_S) {
            if (speedMps < _minSpeed) {
                _minSpeed = speedMps;
                _minT = _clockS;
                newMin = true;
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
        // after this sample's evidence: the phone's window includes the recovery sample
        _recoverStep(dt, speedMps, newMin);
    }

    // The straight-line half of the streak rule (docs/algorithms/pumping.md "Turn streaks", watch
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
        // Opened while idle, and also inside a sweep or an aborted candidate, which may turn
        // out not to be a counted turn (0.9.21); a counted turn's open window owns it outright.
        if (_wasFlying && !flying && !_endOpen && (state != ST_OUTCOME || _aborted)) {
            _endOpen = true;
            _endProvisional = state != ST_IDLE;
            _endDue = false;
            _endStartS = _clockS;
            _endWet = false;
            _endStopRun = 0.0;
            _endStopMax = 0.0;
            _endTouched = false;
        }
        _wasFlying = flying;
        if (!_endOpen || _endDue) {
            return;
        }
        if (submerged) {
            _endWet = true;
        }
        if (speedMps < STOP_FLOOR_MPS) {
            // THE EARLY TOUCH (engine 0.25.0, ADR-035; watch 0.9.20): a landing counts only
            // within `turnOutcomeLookahead` of the exit. A slog that brushes the floor 20 s
            // later is a glide-out on the phone, and now on the wrist too.
            if (_clockS - _endStartS <= LOOKAHEAD_S) {
                _endTouched = true;
            }
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
        // Closed by recovery (he is flying again), by the evidence already proving a swim, or
        // by the window running out. Either way the evidence is called with what there is,
        // exactly as the turn window does — including the early close: `_closeFlightEnd`'s top
        // rung is this same `_endStopMax > FALL_STOP_S`, and it only ever grows, so calling it
        // on the tick the stop gets there is the same answer sooner. The streak on the main
        // screen therefore breaks while the rider is in the water, in step with the wrist's
        // verdict on a turn's fall.
        if (flying || _endStopMax > FALL_STOP_S
                || _clockS - _endStartS >= FLIGHT_END_WINDOW_S) {
            if (_endProvisional) {
                _endDue = true;     // the evidence is in; whose it is, is not yet
            } else {
                _closeFlightEnd();
            }
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
        // judged on the evidence at the recovery, where the phone's window ends
        if (_recovered) {
            _lostFoil = _recLost;
            _wet = _recWet;
            _stopMax = _recStopMax;
        }
        if (_aborted) {
            return _resolveAborted();
        }
        var outcome = OUTCOME_FLEW;
        if (_wet || _stopMax > FALL_STOP_S || _endFell) {
            outcome = OUTCOME_FELL;
            fellCount++;
            // the same split the flew branch takes, off the same `lastKind` (0.9.18)
            if (lastKind == KIND_TACK) {
                tackFellCount++;
            } else if (lastKind == KIND_JIBE) {
                jibeFellCount++;
            }
            dryStreak = 0;          // he swam: both runs end here
            flewStreak = 0;
        } else if (_lostFoil) {
            outcome = OUTCOME_TOUCHDOWN;
            touchdownCount++;
            if (lastKind == KIND_TACK) {
                tackTouchCount++;
            } else if (lastKind == KIND_JIBE) {
                jibeTouchCount++;
            }
            if (_stopMax > TOUCHDOWN_MAX_STOP_S) {
                borderlineCount++;
            }
            dryStreak++;            // dry survives a touchdown; flew does not
            flewStreak = 0;
        } else {
            flewCount++;
            // the same verdict, split by what the sweep was named: no allocation, no second
            // pass, and `lastKind` is still this turn's (the watch does not detect during an
            // outcome window)
            if (lastKind == KIND_TACK) {
                tackFlewCount++;
            } else if (lastKind == KIND_JIBE) {
                jibeFlewCount++;
            }
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
        // The turn goes into the log HERE, before the quiet tail has answered, because this
        // is where its geometry and its outcome are both known. `_logTurn` writes the
        // clean-eligible bit as false and `_quietTick` sets it when the tail runs out — the
        // record is the newest one until the next turn resolves, and the watch does not
        // detect during an outcome window, so "the newest record" is unambiguous.
        _logTurn(lastEntryU, lastNetDeg, outcome, false, false);
        if (_gapOk) {
            _joinLogAdd(_logN - 1, _gapDeg);
        }
        _notePrev();
        if (pct >= SUCCESS_PCT && _minSpeed > _cfg.foilExitMps) {
            successCount++;
            // ...and a successful turn that also FLEW THROUGH is clean-eligible (engine
            // 0.12.0, Jan 5 Sep 2026: a jibe he fell out of is not clean, whatever the sweep
            // scored). The KIND is deliberately not part of that test any more: eligibility
            // is a fact about the riding and the kind is a fact about the wind, and since
            // 0.9.18 the wind can arrive later and re-type the turn. `cleanJibeCount` still
            // only ever counts JIBES — `rebuildWindSplit` applies the kind — and the buzz
            // below still fires for jibes alone.
            if (outcome == OUTCOME_FLEW) {
                // ...pending the quiet tail (0.9.9): the star is granted at
                // end + CLEAN_QUIET_S unless the foil is lost before then. A window that
                // already ran that long without a loss has answered the question.
                cleanPending = true;
                _cleanPendingUntil = _endT + CLEAN_QUIET_S;
                _quietOffRun = 0.0;
                _quietWasOff = false;
                if (_clockS >= _cleanPendingUntil) {
                    cleanPending = false;
                    _markCleanEligible();
                    if (lastKind == KIND_JIBE) {
                        lastCleanJibe = true;
                        cleanJibeCount++;
                    }
                }
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
        return classifyTurn(uIn, uOut, _cfg.windDirection);
    }

    // ---- the turn log: write, read, and the rebuild it exists for (0.9.18) ----

    // Append one resolved turn. Called from `_resolve`, where the geometry and the verdict
    // are both known for the first time. `clean` is CLEAN-ELIGIBLE and not "this was a clean
    // jibe": see the log's header for why the kind is deliberately not baked in.
    hidden function _logTurn(entryU as Float, netDeg as Float, outcome as Number,
            clean as Boolean, aborted as Boolean) as Void {
        if (_logN >= TURN_LOG_MAX) {
            _dropOldest();
        }
        // The entry bearing arrives UNWRAPPED — it is the detector's running heading and may
        // be any multiple of 360 away from a compass bearing — and what the log stores is the
        // compass one. `classifySweep` reads the pair as (in, in + net), so folding the entry
        // and keeping the net signed loses nothing it uses.
        var entry = wrapDeg180(entryU).toNumber();
        if (entry < 0) { entry += 360; }
        if (entry < 0) { entry = 0; } else if (entry > 359) { entry = 359; }
        var net = netDeg.toNumber();
        if (net < -32768) { net = -32768; } else if (net > 32767) { net = 32767; }
        var enc = net + 32768;
        var at = _logN * TURN_LOG_STRIDE;
        _log[at] = entry & 0xFF;
        _log[at + 1] = ((entry >> 8) & 0x01) | ((outcome & 0x03) << 1) | (clean ? 0x08 : 0)
            | (aborted ? 0x10 : 0);
        _log[at + 2] = (enc >> 8) & 0xFF;
        _log[at + 3] = enc & 0xFF;
        _logN++;
    }

    // The cap. Type the oldest record against the axis in force NOW, fold it into the frozen
    // base, and shuffle the rest down. A memmove of at most 2 KB, once every 512 turns.
    hidden function _dropOldest() as Void {
        _foldIntoBase(0, _cfg.windDirection);
        for (var i = TURN_LOG_STRIDE; i < TURN_LOG_MAX * TURN_LOG_STRIDE; i++) {
            _log[i - TURN_LOG_STRIDE] = _log[i];
        }
        _logN = TURN_LOG_MAX - 1;
        // the aborted records point at log indices: record 0 is gone, the rest move down
        var w = 0;
        for (var r = 0; r < _abortN; r++) {
            var idx = _abortIdx(r);
            if (idx == 0) {
                continue;
            }
            for (var b = 0; b < ABORT_STRIDE; b++) {
                _abortLog[w * ABORT_STRIDE + b] = _abortLog[r * ABORT_STRIDE + b];
            }
            _abortLog[w * ABORT_STRIDE] = ((idx - 1) >> 8) & 0xFF;
            _abortLog[w * ABORT_STRIDE + 1] = (idx - 1) & 0xFF;
            w++;
        }
        _abortN = w;
        w = 0;
        for (var r = 0; r < _joinN; r++) {
            var idx = _joinIdx(r);
            if (idx == 0) {
                continue;
            }
            for (var b = 0; b < JOIN_STRIDE; b++) {
                _joinLog[w * JOIN_STRIDE + b] = _joinLog[r * JOIN_STRIDE + b];
            }
            _joinLog[w * JOIN_STRIDE] = ((idx - 1) >> 8) & 0xFF;
            _joinLog[w * JOIN_STRIDE + 1] = (idx - 1) & 0xFF;
            w++;
        }
        _joinN = w;
    }

    // ---- the join records (watch 0.9.21) ----
    //
    //   b0-1 log index, big-endian
    //   b2-3 the heading change across the gap before the sweep, whole degrees, +32768
    //
    // Written for every logged turn whose sweep had a same-direction sweep close within
    // JOIN_GAP_S before it in the same sailing run, joined or not: whether the gap crossed the
    // axis depends on the axis. Appended in log order, so the index only grows. The cap drops
    // the oldest; its turn is then named by its own sweep.
    hidden function _joinLogAdd(logIdx as Number, gap as Float) as Void {
        if (_joinN >= JOIN_MAX) {
            for (var i = JOIN_STRIDE; i < JOIN_MAX * JOIN_STRIDE; i++) {
                _joinLog[i - JOIN_STRIDE] = _joinLog[i];
            }
            _joinN = JOIN_MAX - 1;
        }
        var at = _joinN * JOIN_STRIDE;
        var g = _clamp16(gap) + 32768;
        _joinLog[at] = (logIdx >> 8) & 0xFF;
        _joinLog[at + 1] = logIdx & 0xFF;
        _joinLog[at + 2] = (g >> 8) & 0xFF;
        _joinLog[at + 3] = g & 0xFF;
        _joinN++;
    }

    hidden function _joinIdx(r as Number) as Number {
        var at = r * JOIN_STRIDE;
        return (_joinLog[at] << 8) | _joinLog[at + 1];
    }

    // How far record `i`'s start moves back under `wind` (R5): the gap's heading change when
    // the gap crossed this axis, else 0.
    hidden function _joinGapAt(i as Number, wind as Number) as Float {
        if (wind < 0) {
            return 0.0;
        }
        for (var r = 0; r < _joinN; r++) {
            var idx = _joinIdx(r);
            if (idx > i) {
                break;
            }
            if (idx < i) {
                continue;
            }
            var at = r * JOIN_STRIDE;
            var gap = (((_joinLog[at + 2] << 8) | _joinLog[at + 3]) - 32768).toFloat();
            var uIn = logEntryDeg(i);
            return joinCrosses(uIn - gap, uIn, wind) ? gap : 0.0;
        }
        return 0.0;
    }

    // ---- the aborted records (watch 0.9.20) ----
    //
    //   b0-1 log index, big-endian
    //   b2-3 flown range low, degrees relative to the entry, +32768
    //   b4-5 flown range high, the same
    //   b6   bit 7 = a heading was flown at all; bits 0-6 = gain at speed, 0..127 degrees
    //
    // The cap drops the OLDEST aborted record; its turn then keeps the name its sweep gives
    // under any axis, unasked — after 32 aborted turns in one session that is the least of
    // anyone's worries.
    hidden function _abortLogAdd(logIdx as Number, flown as Boolean, lo as Float, hi as Float,
            gain as Float) as Void {
        if (_abortN >= ABORT_MAX) {
            for (var i = ABORT_STRIDE; i < ABORT_MAX * ABORT_STRIDE; i++) {
                _abortLog[i - ABORT_STRIDE] = _abortLog[i];
            }
            _abortN = ABORT_MAX - 1;
        }
        var at = _abortN * ABORT_STRIDE;
        var l = _clamp16(lo) + 32768;
        var h = _clamp16(hi) + 32768;
        var g = gain.toNumber();
        if (g < 0) { g = 0; } else if (g > 127) { g = 127; }
        _abortLog[at] = (logIdx >> 8) & 0xFF;
        _abortLog[at + 1] = logIdx & 0xFF;
        _abortLog[at + 2] = (l >> 8) & 0xFF;
        _abortLog[at + 3] = l & 0xFF;
        _abortLog[at + 4] = (h >> 8) & 0xFF;
        _abortLog[at + 5] = h & 0xFF;
        _abortLog[at + 6] = (flown ? 0x80 : 0) | g;
        _abortN++;
    }

    hidden function _clamp16(v as Float) as Number {
        var n = v.toNumber();
        if (n < -32768) { return -32768; }
        if (n > 32767) { return 32767; }
        return n;
    }

    hidden function _abortIdx(r as Number) as Number {
        var at = r * ABORT_STRIDE;
        return (_abortLog[at] << 8) | _abortLog[at + 1];
    }

    function logAborted(i as Number) as Boolean {
        return (_log[i * TURN_LOG_STRIDE + 1] & 0x10) != 0;
    }

    // Record `i`'s kind under `wind`: the ordinary classifier for a finished sweep; for an
    // aborted one its own name, gated by R2/R3 against THIS axis (KIND_REJECT when it fails —
    // a course change under this axis, which stays a generic turn in `turnCount`).
    hidden function _kindAt(i as Number, wind as Number) as Number {
        var uIn = logEntryDeg(i);
        var uOut = uIn + logNetDeg(i);
        if (!logAborted(i)) {
            return classifyTurn(uIn - _joinGapAt(i, wind), uOut, wind);
        }
        var kind = abortKind(uIn, uOut, wind);
        for (var r = 0; r < _abortN; r++) {
            if (_abortIdx(r) != i) {
                continue;
            }
            var at = r * ABORT_STRIDE;
            var lo = (((_abortLog[at + 2] << 8) | _abortLog[at + 3]) - 32768).toFloat();
            var hi = (((_abortLog[at + 4] << 8) | _abortLog[at + 5]) - 32768).toFloat();
            var flown = (_abortLog[at + 6] & 0x80) != 0;
            var gain = (_abortLog[at + 6] & 0x7F).toFloat();
            if (!abortPasses(kind, uIn, uOut, wind, defaultTurnType, flown, lo, hi, gain)) {
                return KIND_REJECT;
            }
            break;
        }
        return kind;
    }

    // Record `i`'s entry bearing, as the float `classifySweep` wants.
    function logEntryDeg(i as Number) as Float {
        var at = i * TURN_LOG_STRIDE;
        return (_log[at] | ((_log[at + 1] & 0x01) << 8)).toFloat();
    }

    // Record `i`'s signed net rotation.
    function logNetDeg(i as Number) as Float {
        var at = i * TURN_LOG_STRIDE;
        return ((_log[at + 2] << 8 | _log[at + 3]) - 32768).toFloat();
    }

    function logOutcome(i as Number) as Number {
        return (_log[i * TURN_LOG_STRIDE + 1] >> 1) & 0x03;
    }

    function logCleanEligible(i as Number) as Boolean {
        return (_log[i * TURN_LOG_STRIDE + 1] & 0x08) != 0;
    }

    // How many turns the log actually holds, and whether the cap has ever bitten. Both are
    // read by the layout suite and by nothing in the app.
    function logCount() as Number { return _logN; }
    function logDropped() as Boolean { return _baseTack + _baseJibe > 0; }

    // Add record `i`'s contribution to the frozen base, typed against `wind`.
    hidden function _foldIntoBase(i as Number, wind as Number) as Void {
        var uIn = logEntryDeg(i) - _joinGapAt(i, wind);
        var kind = _kindAt(i, wind);
        var o = logOutcome(i);
        if (kind == KIND_TACK) {
            _baseTack++;
            if (o == OUTCOME_FLEW) { _baseTackFlew++; }
            else if (o == OUTCOME_TOUCHDOWN) { _baseTackTouch++; }
            else if (o == OUTCOME_FELL) { _baseTackFell++; }
        } else if (kind == KIND_JIBE) {
            _baseJibe++;
            if (o == OUTCOME_FLEW) { _baseJibeFlew++; }
            else if (o == OUTCOME_TOUCHDOWN) { _baseJibeTouch++; }
            else if (o == OUTCOME_FELL) { _baseJibeFell++; }
            if (logCleanEligible(i) && o == OUTCOME_FLEW) { _baseClean++; }
        }
        if (kind == KIND_TACK || kind == KIND_JIBE) {
            var twa = _wrap180(uIn - wind.toFloat());
            if (twa > 0.0) { _basePort++; } else if (twa < 0.0) { _baseStbd++; }
        }
    }

    // ---- REBUILD (0.9.18, replacing `backfillWindSplit`) ----
    //
    // Throw every per-kind counter away and recompute it from the log against the axis in
    // force now. Called whenever that axis CHANGES — the auto-wind lock, an update to it, or
    // the rider setting or clearing a bearing by hand — so the Tacks & jibes page says the
    // same thing about a session however late the wind arrived.
    //
    // What it does NOT touch, and the list is the same one `backfillWindSplit` kept: the
    // `turnCount`, the session-wide outcome tally, the streaks, the scores. Those were real
    // observations made at the time and they are not re-judged; only the NAME of each turn
    // and everything that hangs off the name is recomputed. So `tackCount + jibeCount <=
    // turnCount` still holds, with the difference being the sweeps that are course changes
    // under this axis.
    //
    // The invariant it buys, and the reason it exists: with a wind axis set,
    //   jibeFlewCount + jibeTouchCount + jibeFellCount == jibeCount
    //   tackFlewCount + tackTouchCount + tackFellCount == tackCount
    // exactly — not "for turns typed after the lock", which is what 0.9.17 could promise.
    //
    // Cost: one pass over at most 512 records, on an event that happens a handful of times a
    // session. No allocation.
    function rebuildWindSplit() as Void {
        var wind = _cfg.windDirection;
        tackCount = _baseTack;
        jibeCount = _baseJibe;
        tackFlewCount = _baseTackFlew;
        tackTouchCount = _baseTackTouch;
        tackFellCount = _baseTackFell;
        jibeFlewCount = _baseJibeFlew;
        jibeTouchCount = _baseJibeTouch;
        jibeFellCount = _baseJibeFell;
        cleanJibeCount = _baseClean;
        portEntryCount = _basePort;
        starboardEntryCount = _baseStbd;
        for (var i = 0; i < _logN; i++) {
            var uIn = logEntryDeg(i) - _joinGapAt(i, wind);
            var kind = _kindAt(i, wind);
            if (kind != KIND_TACK && kind != KIND_JIBE) {
                continue;       // a course change under this axis: it stays a generic turn
            }
            var o = logOutcome(i);
            if (kind == KIND_TACK) {
                tackCount++;
                if (o == OUTCOME_FLEW) { tackFlewCount++; }
                else if (o == OUTCOME_TOUCHDOWN) { tackTouchCount++; }
                else if (o == OUTCOME_FELL) { tackFellCount++; }
            } else {
                jibeCount++;
                if (o == OUTCOME_FLEW) { jibeFlewCount++; }
                else if (o == OUTCOME_TOUCHDOWN) { jibeTouchCount++; }
                else if (o == OUTCOME_FELL) { jibeFellCount++; }
                // A clean jibe is a clean-eligible FLY-THROUGH that this axis calls a jibe.
                // The eligibility was decided when the turn resolved; the kind is decided
                // here, which is the half that can change.
                if (logCleanEligible(i) && o == OUTCOME_FLEW) { cleanJibeCount++; }
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
