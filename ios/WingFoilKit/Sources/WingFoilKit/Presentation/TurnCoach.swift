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
/// Definitions: docs/presentation/turn-detail.md, "Turn detail".
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
        /// Flew through and held its speed, and the ten seconds after it were not quiet: a
        /// touchdown or a fall the flight-end channel saw (engine 0.17.0).
        case quietFlightEnd
        /// The same tail, with the foil lost for a second or more — too short to end a
        /// flight, long enough that the jibe is not one he rode away from.
        case quietOffFoil
        /// The same tail, with the barometer seeing the wrist go under in it.
        case quietSubmerged
        /// Carried and flown through, and it did not come far enough past the wind axis
        /// (`turnAxisAfterDeg`, off by default).
        case axisAfter
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
    ///
    /// The four `cleanBlockedBy` rungs (engine 0.17.0) sit immediately above `cleanAndFast`
    /// for the same reason: a jibe the quiet tail refused *did* fly through and *did* hold
    /// its speed, so every rung below would call it clean and say so out loud.
    public static func rule(turn: TurnRecord, slice: TurnSlice) -> Rule {
        let outcome = TurnOutcomeKind(turn.outcome)
        let fast = turn.success && turn.score >= fastScore
        if outcome == .fellIn { return fast ? .fellInFast : .fellIn }
        if turn.submerged { return .wristUnder }
        if turn.pumped { return .pumpedOut }
        if outcome == .touchdown {
            return lateMinimum(slice) == true ? .touchdownOnExit : .touchdownComingIn
        }
        // Above `cleanAndFast` on purpose: a jibe the quiet tail or the axis gate refused
        // flew through and held its speed, so every rung below this one would call it clean.
        switch turn.cleanBlockedBy {
        case CleanBlock.quietFlightEnd.rawValue: return .quietFlightEnd
        case CleanBlock.quietOffFoil.rawValue: return .quietOffFoil
        case CleanBlock.quietSubmerged.rawValue: return .quietSubmerged
        case CleanBlock.axisAfter.rawValue: return .axisAfter
        default: break
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
    ///
    /// **The tip** (27 Sep 2026, Jan: "coach the next attempt"). Every line a turn that was
    /// not clean gets ends with one plain thing to try next time (`tip(turn:slice:quietS:)`),
    /// read off the same facts the sentence already used. `quietS` is the analysis'
    /// `turnCleanQuietS`, the one number the quiet-tail tip names, and the footnote under
    /// the page prints the same one.
    public static func line(turn: TurnRecord, slice: TurnSlice,
                            pumpStrokes: Int? = nil, quietS: Double? = nil) -> String {
        let said = observation(turn: turn, slice: slice, pumpStrokes: pumpStrokes)
        guard let tip = tip(turn: turn, slice: slice, quietS: quietS) else { return said }
        return said + " " + tip
    }

    /// **The wording, as templates** (28 September 2026): the browser's turn page reads the
    /// same table out of `docs/copy/app-words.json` (`turnCoach`), so the two shells cannot
    /// word one rung two ways. `{score}`, `{entry}`, `{low}`, `{mid}`, `{strokes}` and
    /// `{seconds}` are filled by `observation` below with the page's own formats.
    public static let lines: [String: String] = [
        "fellInFast": "You held {score} of your entry speed right round. "
            + "It still ended in the water.",
        "fellIn": "This one ended in the water. {entry} coming in, {low} at the low point.",
        "wristUnder": "The barometer saw your wrist go under here. "
            + "The foil was gone for a moment. {entry} in, {low} at the low point.",
        "pumpedOut": "You pumped this one back out.",
        "pumpedOutIn": "You pumped this one back out in {strokes}.",
        "offFoilThenFlew": "{seconds} off the foil before it flew again.",
        "flewStraightAway": "It was flying again straight away.",
        "touchdownOnExit": "The foil touched down on the way out. "
            + "You held {entry} into the {mid} and lost it after.",
        "touchdownComingIn": "The foil touched down before the {mid}. "
            + "The speed was already at {low} going in.",
        "quietFlightEnd": "You rode the turn itself and held {score} of your entry speed. "
            + "The foil went a few seconds later, so this one is not clean.",
        "quietOffFoil": "You rode the turn, then the foil dropped again on the way out. "
            + "This one does not count as clean.",
        "quietSubmerged": "You held {score} of your entry speed through the turn. "
            + "The barometer then saw your wrist go under. This one is not clean.",
        "axisAfter": "You held {score} of your entry speed. "
            + "The board did not come far enough past the wind axis. This one is not clean.",
        "cleanAndFast": "Clean, and you barely slowed. "
            + "You held {score} of your entry speed all the way round.",
        "flewAndFast": "You flew through and barely slowed. "
            + "You held {score} of your entry speed all the way round.",
        "cleanButSlow": "You flew all the way through, and it cost you speed. "
            + "{entry} in, {low} at the low point.",
        "slowedEarly": "The speed went before the {mid}. "
            + "You were down to {low} with the turn still to come.",
        "slowedLate": "You held it into the {mid}. The speed went on the way out, down to {low}.",
        "plain": "{entry} in, {low} at the low point. You held {score} of your entry speed.",
        "midJibe": "downwind point",
        "midTack": "head-to-wind",
        "midOther": "middle of the turn",
    ]

    /// The tips' wording, the same way (`turnCoachTips` in the export).
    public static let tipLines: [String: String] = [
        "comeInFasterJibe": "Next time, come in faster, or keep the wing powered through "
            + "the downwind point.",
        "comeInFaster": "Next time, come in with more speed.",
        "powerUpOnExit": "Next time, power the wing up as soon as you are on the new tack.",
        "steadyExit": "Next time, stay low and steady on the way out.",
        "rideItOut": "Next time, stay on the foil for {hold} after the turn, "
            + "and it counts as clean.",
        "rideItOutHold": "a few seconds",
        "carryFurther": "Next time, carry the turn further past the wind axis before you "
            + "settle.",
    ]

    private static func say(_ key: String, _ args: [String: String] = [:]) -> String {
        AppShellCopy.fill(lines[key] ?? key, args)
    }

    /// What happened, without the tip.
    static func observation(turn: TurnRecord, slice: TurnSlice,
                            pumpStrokes: Int?) -> String {
        let args = ["score": pct(turn.score), "entry": kn(turn.entryKn),
                    "low": kn(turn.minKn), "mid": midPointWord(turn.type)]
        switch rule(turn: turn, slice: slice) {
        case .fellInFast:
            // The score and the outcome say opposite things, so the sentence says both.
            return say("fellInFast", args)
        case .fellIn:
            return say("fellIn", args)
        case .wristUnder:
            return say("wristUnder", args)
        case .pumpedOut:
            let opener = pumpStrokes.map {
                say("pumpedOutIn", ["strokes": TurnAnalytics.strokesText($0)])
            } ?? say("pumpedOut")
            let after = turn.offFoilS > 0
                ? say("offFoilThenFlew", ["seconds": seconds(turn.offFoilS)])
                : say("flewStraightAway")
            return opener + " " + after
        case .touchdownOnExit:
            return say("touchdownOnExit", args)
        case .touchdownComingIn:
            return say("touchdownComingIn", args)
        case .quietFlightEnd:
            // The turn itself was clean. The ten seconds after it were not (engine 0.17.0).
            return say("quietFlightEnd", args)
        case .quietOffFoil:
            // The foil was lost for a second or more in the tail: too short to end a flight,
            // long enough that the jibe is not one he rode away from.
            return say("quietOffFoil", args)
        case .quietSubmerged:
            return say("quietSubmerged", args)
        case .axisAfter:
            return say("axisAfter", args)
        case .cleanAndFast:
            // "Clean" only where the engine said clean: a tack has no clean reading, and
            // under the hero word "Flew through" the old line contradicted it (27 Sep 2026).
            return say(turn.clean ? "cleanAndFast" : "flewAndFast", args)
        case .cleanButSlow:
            return say("cleanButSlow", args)
        case .slowedEarly:
            return say("slowedEarly", args.merging(["low": kn(slice.speed.minKn)]) { $1 })
        case .slowedLate:
            return say("slowedLate", args.merging(["low": kn(slice.speed.minKn)]) { $1 })
        case .plain:
            return say("plain", args)
        }
    }

    // MARK: - The tip

    /// **What to try next time**, as a table. Five tips, and each one is keyed to a fact
    /// the coach line has already stated, so a tip can never claim more than the data does:
    ///
    /// | tip | when | the fact behind it |
    /// |---|---|---|
    /// | `comeInFaster` | the speed was gone before the mid-point | `lateMinimum == false` |
    /// | `powerUpOnExit` | the speed went on the way out | `lateMinimum == true` |
    /// | `steadyExit` | the speed held right round and it still ended in the water | `fellInFast` |
    /// | `rideItOut` | the turn was clean and the seconds after it were not | the quiet tail |
    /// | `carryFurther` | the board did not come far enough past the wind axis | `axisAfter` |
    ///
    /// No tip on a clean jibe, on `cleanAndFast` and on `plain`, and none where the tip needs
    /// the halfway point and the window has no geometry to find it: "come in faster" under a
    /// turn whose low point cannot be placed would be a guess.
    public enum Tip: String, Sendable, Equatable, CaseIterable {
        case comeInFaster
        case powerUpOnExit
        case steadyExit
        case rideItOut
        case carryFurther
    }

    /// Which tip the turn gets, or nil.
    public static func tipKind(turn: TurnRecord, slice: TurnSlice) -> Tip? {
        if turn.clean { return nil }
        // Where the speed went, for the rungs whose sentence says so or could.
        func byWhere() -> Tip? {
            switch lateMinimum(slice) {
            case .some(true): return .powerUpOnExit
            case .some(false): return .comeInFaster
            case .none: return nil
            }
        }
        switch rule(turn: turn, slice: slice) {
        case .fellInFast: return .steadyExit
        case .fellIn, .wristUnder, .pumpedOut, .cleanButSlow: return byWhere()
        case .touchdownOnExit, .slowedLate: return .powerUpOnExit
        case .touchdownComingIn, .slowedEarly: return .comeInFaster
        case .quietFlightEnd, .quietOffFoil, .quietSubmerged: return .rideItOut
        case .axisAfter: return .carryFurther
        case .cleanAndFast, .plain: return nil
        }
    }

    /// The tip's sentence. One sentence, second person, "next time" in front so it reads as
    /// an offer rather than a correction (docs/voice.md, register 1).
    public static func tip(turn: TurnRecord, slice: TurnSlice,
                           quietS: Double? = nil) -> String? {
        tipKind(turn: turn, slice: slice).map { tipText($0, type: turn.type, quietS: quietS) }
    }

    /// The table's wording. `type` picks the jibe's words where the tip is about the wing
    /// through dead downwind, which is a jibe's move and not a tack's.
    public static func tipText(_ tip: Tip, type: String, quietS: Double? = nil) -> String {
        func line(_ key: String) -> String { tipLines[key] ?? key }
        switch tip {
        case .comeInFaster:
            return line(type == "jibe" ? "comeInFasterJibe" : "comeInFaster")
        case .powerUpOnExit:
            return line("powerUpOnExit")
        case .steadyExit:
            return line("steadyExit")
        case .rideItOut:
            let hold = quietS.flatMap { $0 > 0 ? String(Int($0)) + " s" : nil }
                ?? line("rideItOutHold")
            return AppShellCopy.fill(line("rideItOut"), ["hold": hold])
        case .carryFurther:
            return line("carryFurther")
        }
    }

    // MARK: - The verdict

    /// **The verdict, as the page's hero** (27 Sep 2026): the one word a rider asks about a
    /// turn, large under its drawing. "Clean" where the engine said clean, else the outcome
    /// word with a capital, so the hero and the Turns list's outcome word are one word.
    public static func verdictWord(_ turn: TurnRecord) -> String {
        if turn.clean { return "Clean" }
        let label = TurnOutcomeKind(turn.outcome).label
        return label.prefix(1).uppercased() + label.dropFirst()
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
        case "jibe": return lines["midJibe"] ?? ""
        case "tack": return lines["midTack"] ?? ""
        default: return lines["midOther"] ?? ""
        }
    }

    // MARK: - Numbers
    //
    // Nothing here invents a format: knots print the way the turn list's `detail` line prints
    // them and the score prints the way its `scoreText` does, so a sentence six points under
    // the numbers row cannot round differently from it.

    static func kn(_ value: Double) -> String { Speed.format(value, digits: 1) }

    static func pct(_ score: Double) -> String { "\(TurnAnalytics.scoreText(score)) %" }

    static func seconds(_ value: Double) -> String { String(format: "%.0f s", value) }
}
