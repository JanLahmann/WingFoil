import Foundation

/// One calm sentence about one turn — what a friend on the beach would say after watching it.
///
/// The voice is `ReplayCommentary`'s, and the rules that keep it are the same three: it states
/// what happened, it uses the numbers already on screen rather than inventing a second
/// measurement, and it never blames. No exclamation marks, no "you should have", no adjectives
/// the data cannot support. A rider who swam out of a jibe knows he swam; the line's job is to
/// say *where* the speed went, which is the part he could not see.
///
/// **Table-driven on purpose.** The branches are a ladder of specificity, first match wins, and
/// the ladder itself is the thing worth testing — a rule accidentally shadowed by the one above
/// it is invisible until a rider reads "the speed went before the downwind point" under a jibe
/// he fell out of. `rule(turn:slice:)` returns the rung so a test can assert the ladder without
/// asserting prose, and `line` is the wording laid over it.
///
/// Definitions: docs/presentation.md, "Turn detail".
public enum TurnCoach {

    /// The rungs, most specific first. `line` walks them in this order.
    public enum Rule: String, Sendable, Equatable, CaseIterable {
        /// Ended in the water with the speed still there — the case engine 0.12.0 stopped
        /// calling clean, and the reason this rung exists: it is the one turn where the
        /// score and the outcome say opposite things, and the sentence has to say both.
        case fellInFast
        /// Ended in the water.
        case fellIn
        /// The barometer saw the wrist go under, on a turn that did not end in a fall.
        case wristUnder
        /// He pumped the foil back up out of it.
        case pumpedOut
        /// Touchdown, low point after the halfway mark — lost on the exit.
        case touchdownOnExit
        /// Touchdown, low point before it — lost going in.
        case touchdownComingIn
        /// Flew all the way through and barely slowed — a **clean** jibe on the 0.12.0
        /// rule, which the ladder gets for free: every rung above this one has already
        /// taken the turns that did not fly through.
        case cleanAndFast
        /// Flew all the way through, and it cost a lot of speed.
        case cleanButSlow
        /// The speed bottomed out before the turn was halfway round.
        case slowedEarly
        /// It bottomed out at or after halfway — lost on the way out.
        case slowedLate
        /// Nothing above applied, or the window has no usable geometry.
        case plain
    }

    /// Above this share of entry speed a turn is not just clean, it is quick.
    public static let fastScore = 0.85
    /// Below this a turn that flew all the way through still cost most of its speed.
    public static let slowScore = 0.7

    /// Which rung the turn lands on.
    ///
    /// The outcome is asked first and the score second, which is what keeps `cleanAndFast`
    /// honest: by the time the ladder reaches it every fall and every touchdown has already
    /// been taken, so the rung is `flewThrough` by construction and never calls a swim
    /// clean. `fellInFast` is the same rule read from the other end — a turn whose score
    /// held all the way round and whose foil went in the recovery tail.
    public static func rule(turn: TurnRecord, slice: TurnSlice) -> Rule {
        let outcome = TurnOutcomeKind(turn.outcome)
        let fast = turn.success && turn.score >= fastScore
        if outcome == .fellIn { return fast ? .fellInFast : .fellIn }
        if turn.submerged { return .wristUnder }
        if turn.pumped { return .pumpedOut }
        if outcome == .touchdown {
            return lateMinimum(slice) == true ? .touchdownOnExit : .touchdownComingIn
        }
        if fast { return .cleanAndFast }
        if outcome == .flewThrough && turn.score < slowScore { return .cleanButSlow }
        switch lateMinimum(slice) {
        case .some(true): return .slowedLate
        case .some(false): return .slowedEarly
        case .none: return .plain
        }
    }

    /// The sentence.
    ///
    /// `pumpStrokes` is the one number the ladder takes from outside the turn record
    /// (`TurnAnalytics.pumpStrokes`), and only the `pumpedOut` rung uses it. It is optional
    /// because the analysis may not know — and a sentence must never print a count that is
    /// really an absence. It is also on the page: the "pumped out" chip carries the same
    /// words, which is what keeps the rule "never a number the page is not already showing".
    public static func line(turn: TurnRecord, slice: TurnSlice,
                            pumpStrokes: Int? = nil) -> String {
        let mid = midPointWord(turn.type)
        switch rule(turn: turn, slice: slice) {
        case .fellInFast:
            return "The speed was there right round — \(pct(turn.score)) of your entry held "
                + "— and it still ended in the water."
        case .fellIn:
            return "This one ended in the water — \(kn(turn.entryKn)) coming in, "
                + "\(kn(turn.minKn)) at the low point."
        case .wristUnder:
            return "The barometer saw your wrist go under here, so the foil was gone for a "
                + "moment — \(kn(turn.entryKn)) in, \(kn(turn.minKn)) at the low point."
        case .pumpedOut:
            let strokes = pumpStrokes.map { "\(TurnAnalytics.strokesText($0))" }
            switch (strokes, turn.offFoilS > 0) {
            case (let strokes?, true):
                return "You pumped this one back out — \(strokes), and "
                    + "\(seconds(turn.offFoilS)) off the foil before it flew again."
            case (let strokes?, false):
                return "You pumped this one back out in \(strokes), and it was flying "
                    + "again straight away."
            case (nil, true):
                return "You pumped this one back out — \(seconds(turn.offFoilS)) off the "
                    + "foil before it flew again."
            case (nil, false):
                return "You pumped this one back out, and it was flying again straight away."
            }
        case .touchdownOnExit:
            return "The foil touched down on the way out — you held \(kn(turn.entryKn)) into "
                + "the \(mid) and lost it after."
        case .touchdownComingIn:
            return "The foil touched down before the \(mid) — the speed was already at "
                + "\(kn(turn.minKn)) going in."
        case .cleanAndFast:
            return "Clean, and you barely slowed — \(pct(turn.score)) of your entry speed "
                + "held all the way round."
        case .cleanButSlow:
            return "You flew all the way through, and it cost you — \(kn(turn.entryKn)) in, "
                + "\(kn(turn.minKn)) at the low point."
        case .slowedEarly:
            return "The speed went before the \(mid) — \(kn(slice.speed.minKn)) with the turn "
                + "still to come."
        case .slowedLate:
            return "You carried it into the \(mid) and the speed went on the way out — "
                + "down to \(kn(slice.speed.minKn))."
        case .plain:
            return "\(kn(turn.entryKn)) in, \(kn(turn.minKn)) at the low point, "
                + "\(pct(turn.score)) of your entry speed held."
        }
    }

    // MARK: - The one geometric question the ladder asks

    /// Did the speed bottom out at or after the turn's halfway point? nil when the window has
    /// too few usable bearings to say where halfway was — in which case no rule that depends
    /// on it may fire.
    private static func lateMinimum(_ slice: TurnSlice) -> Bool? {
        guard let mid = slice.midRotationRt else { return nil }
        return slice.speed.minRt >= mid
    }

    /// What a rider calls the middle of this turn. A jibe passes through dead downwind, a tack
    /// through head-to-wind, and a sweep the wind axis could not name passes through neither —
    /// so it gets the plain words rather than a guess.
    static func midPointWord(_ type: String) -> String {
        switch type {
        case "jibe": return "downwind point"
        case "tack": return "head-to-wind"
        default: return "middle of the turn"
        }
    }

    // MARK: - Numbers
    //
    // Nothing here invents a format: knots print the way the turn list's `detail` line prints
    // them and the score prints the way its `scoreText` does, so a sentence six points under
    // the numbers row cannot round differently from it.

    static func kn(_ value: Double) -> String { String(format: "%.1f kn", value) }

    static func pct(_ score: Double) -> String { "\(TurnAnalytics.scoreText(score)) %" }

    static func seconds(_ value: Double) -> String { String(format: "%.0f s", value) }
}
