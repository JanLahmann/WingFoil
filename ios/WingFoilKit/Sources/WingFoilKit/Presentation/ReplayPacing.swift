import Foundation

/// Turning "I want a ten-second clip" into a rate and an ease.
///
/// **Why the picker was inverted.** The setup sheet used to offer 10× / 30× / 60× and print
/// the length each of them came out at. But a rate is not what anybody is choosing: a rider
/// picks a speed by reading the seconds underneath it, and the *same* speed means a 23-second
/// clip on one afternoon and a four-minute one on the next. The length is the decision; the
/// rate is arithmetic. So the sheet asks for the length and this works out the rest.
///
/// **Why it is a solve and not a division.** `rate = span / target` is only right when the
/// replay runs at a constant rate, and it does not: `ReplayDriver.Ease` dips to a quarter
/// speed around every commentary milestone, and the dips are measured in **wall** seconds,
/// so each one costs roughly a fixed second of clip whatever the rate is. On the 30 Aug
/// Torbole fixture that is about thirteen seconds of slow motion across twelve milestones —
/// more than a ten-second clip has to spend. Dividing would label a 30-second clip "10 s",
/// which is exactly the lie the inversion was supposed to remove.
///
/// So there are three moves, in this order:
///
/// 1. **Budget the milestones.** A clip of a given length has room for a given number of
///    things to be said (`ReplayCommentary.budget`), and a long session squeezed into ten
///    seconds has far more than that. The overflow is *selected away* rather than played
///    faster — see step 2 for why the alternative used to be a lie.
/// 2. **Budget the ease.** The dips may take at most `easeShare` of the clip. Over budget,
///    the half-width shrinks in proportion — the slow motion is still there, still on the
///    same milestones, just briefer. A ten-second clip cannot afford twelve one-second
///    ritardandos, and the honest response is shorter dips rather than a longer clip.
/// 3. **Solve for the rate**, by bisection on the driver's own `runWallS`. It is monotone
///    decreasing in the rate, so the search cannot go wrong, and using the driver's own
///    integral rather than a model of it means the quoted length and the clip that comes out
///    are the same number by construction.
///
/// **Why there is no ceiling on the rate.** There used to be one — 250×, on the theory that
/// past it the 20 Hz playhead moves so far per frame that the dot stops reading as a boat.
/// What it actually produced was the bug it was meant to prevent: a two-hour afternoon asked
/// for ten seconds saturated the cap, ran for twenty-nine, and arrived as a forty-second video
/// with the sheet relabelling the estimate rather than honouring the choice. The chosen length
/// is the promise, so the rate is whatever the span needs. The thing the cap was really
/// worried about — a clip too dense to read — is step 1's job, and step 1 can do it without
/// breaking the number on the button.
public enum ReplayPacing {

    /// What the sheet hands the cinema view: a rate, the ease that rate was solved with, and
    /// the milestones both were solved *for*.
    ///
    /// The three travel together because they are one decision. The pruned list is the script
    /// the clip actually has — the captions the viewer reads and the instants the run slows
    /// through are the same array, which is the property `ReplayDriverTests` pins and the one
    /// a clip whose slow motion happened somewhere other than its captions would have lost.
    public struct Plan: Sendable, Equatable {
        public var rate: Double
        public var ease: ReplayDriver.Ease
        /// The script this plan was solved against, already cut to the target's budget. **The**
        /// list: captions and dips both, never one of each.
        public var milestones: [ReplayMilestone]

        public init(rate: Double, ease: ReplayDriver.Ease,
                    milestones: [ReplayMilestone] = []) {
            self.rate = rate
            self.ease = ease
            self.milestones = milestones
        }
    }

    /// Real time. Slower than this is not a replay, and a target longer than the session
    /// itself simply gets the session.
    public static let minRate: Double = 1

    /// The largest share of a clip the slow-motion dips may eat.
    ///
    /// A third, because that is about where the ease stops being punctuation and starts being
    /// the clip: below it the run is recognisably at the speed the rider picked with slower
    /// moments in it, above it the whole thing is slow motion and the nominal rate is a
    /// number that describes nothing. On the Torbole fixture the standard 0.6 s half-width
    /// costs ~13 s, so it is untouched at a 60 s target, halved at 25 s and cut to under a
    /// third at 10 s.
    public static let easeShare = 0.35

    /// The rate and ease that make the replay run for `targetWallS` wall seconds.
    ///
    /// `targetWallS` is the **replay's** length, not the clip's: the title card, the closing
    /// card and every photo pause are `ReplayStoryboard`'s to add on top, and they are added
    /// out loud ("about 17 s of video — 10 s of replay, plus the title and the closing card").
    /// Splitting it that way is what keeps the sheet's sentence true when the rider adds a
    /// photo, which changes the clip's length and must not change the replay's.
    public static func plan(span: ClosedRange<Double>, targetWallS: Double,
                            milestones: [ReplayMilestone] = [],
                            ease: ReplayDriver.Ease = .cinema) -> Plan {
        // Step 1, and it comes first because the other two are functions of what survives it:
        // dropping eight of twelve lines takes eight dips out of the ease budget, which lets
        // the four that are left keep a readable width.
        let script = ReplayCommentary.pruned(milestones, forTargetWallS: targetWallS)
        let easeAt = script.map(\.t)

        let spanS = max(span.upperBound - span.lowerBound, 0)
        // A recording with no duration has no replay to pace, and a nonsensical target is not
        // worth a search. Either way the driver's own clamping does the rest.
        guard spanS > 0, targetWallS > 0 else {
            return Plan(rate: minRate, ease: ease, milestones: script)
        }

        // Steps 2 and 3 are interleaved rather than sequential, because each moves the other:
        // shorter dips let the rate come down, and a different rate changes what the dips
        // cost. Four passes is far more than the fixed point needs — it converges from above
        // and monotonically (see `budget`) — and it costs four integrals of a 4096-sample sum.
        var budgeted = ease
        var rate = max(spanS / targetWallS, minRate)
        for _ in 0..<4 {
            guard let tighter = budget(budgeted, span: span, targetWallS: targetWallS,
                                       easeAt: easeAt, spanS: spanS, rate: rate)
            else { break }
            budgeted = tighter
            rate = solve(span: span, targetWallS: targetWallS, easeAt: easeAt, ease: budgeted)
        }
        rate = solve(span: span, targetWallS: targetWallS, easeAt: easeAt, ease: budgeted)
        return Plan(rate: rate, ease: budgeted, milestones: script)
    }

    /// Step 2: shrink the dips until they fit their share of the clip. Returns nil once they
    /// already do, which is what ends the loop above.
    ///
    /// With the milestone budget in front of it this rarely has much left to do — four dips in
    /// ten seconds are close to their allowance already — which is the point: the width it
    /// arrives at is a width that can still be watched.
    ///
    /// The overhead is measured rather than modelled — one `runWallS`, minus what the same run
    /// would take with no ease at all — because overlapping dips take the deepest rather than
    /// compounding (`ReplayDriver.pace`), and a closed form for that would have to know how a
    /// particular afternoon's milestones fall against each other.
    ///
    /// A proportional cut *under*-corrects, which is exactly why this is iterated: narrower
    /// dips overlap each other less, so each one keeps more of its own cost and halving the
    /// width takes rather less than half the time out. Repeating is therefore a monotone
    /// descent onto the budget rather than an oscillation around it.
    private static func budget(_ ease: ReplayDriver.Ease, span: ClosedRange<Double>,
                               targetWallS: Double, easeAt: [Double],
                               spanS: Double, rate: Double) -> ReplayDriver.Ease? {
        guard !easeAt.isEmpty, ease.halfWidthWallS > 0, ease.floor < 1 else { return nil }
        let overhead = ReplayDriver(span: span, rate: rate, easeAt: easeAt, ease: ease).runWallS
            - spanS / rate
        let allowance = easeShare * targetWallS
        guard overhead > allowance, overhead > 0 else { return nil }
        return ReplayDriver.Ease(floor: ease.floor,
                                 halfWidthWallS: ease.halfWidthWallS * allowance / overhead)
    }

    /// Step 3: bisect the rate. `runWallS` falls monotonically as the rate rises, so forty
    /// halvings settle it to well under a millisecond of clip.
    ///
    /// **The bracket is derived rather than declared.** The pace never falls below
    /// `ease.floor`, so the run can never take longer than `spanS / (rate × floor)` — which
    /// makes `spanS / (target × floor)` a rate that is provably fast enough, whatever the
    /// session and however much of it is slow motion. That is the upper end of the search, and
    /// it is why there is no ceiling to saturate against: the bracket adapts to the afternoon
    /// instead of the afternoon being trimmed to fit the bracket.
    ///
    /// The one remaining saturation is a real answer rather than a failure: a target longer
    /// than the session at real time gets `minRate`, because you cannot stretch four minutes
    /// into ten by playing them back faster.
    private static func solve(span: ClosedRange<Double>, targetWallS: Double,
                              easeAt: [Double], ease: ReplayDriver.Ease) -> Double {
        func runWallS(_ rate: Double) -> Double {
            ReplayDriver(span: span, rate: rate, easeAt: easeAt, ease: ease).runWallS
        }
        guard runWallS(minRate) > targetWallS else { return minRate }
        let spanS = max(span.upperBound - span.lowerBound, 0)
        let enough = max(spanS / (targetWallS * max(ease.floor, 0.01)), minRate)
        guard runWallS(enough) < targetWallS else { return enough }
        var slow = minRate, fast = enough
        for _ in 0..<40 {
            let middle = (slow + fast) / 2
            if runWallS(middle) > targetWallS { slow = middle } else { fast = middle }
        }
        return (slow + fast) / 2
    }
}
