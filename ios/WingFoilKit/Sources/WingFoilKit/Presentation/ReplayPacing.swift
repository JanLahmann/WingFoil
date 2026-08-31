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
/// So there are two moves, in this order:
///
/// 1. **Budget the ease.** The dips may take at most `easeShare` of the clip. Over budget,
///    the half-width shrinks in proportion — the slow motion is still there, still on the
///    same milestones, just briefer. A ten-second clip cannot afford twelve one-second
///    ritardandos, and the honest response is shorter dips rather than a longer clip.
/// 2. **Solve for the rate**, by bisection on the driver's own `runWallS`. It is monotone
///    decreasing in the rate, so the search cannot go wrong, and using the driver's own
///    integral rather than a model of it means the quoted length and the clip that comes out
///    are the same number by construction.
public enum ReplayPacing {

    /// What the sheet hands the cinema view: a rate, and the ease that rate was solved with.
    public struct Plan: Sendable, Equatable {
        public var rate: Double
        public var ease: ReplayDriver.Ease

        public init(rate: Double, ease: ReplayDriver.Ease) {
            self.rate = rate
            self.ease = ease
        }
    }

    /// The fastest the replay is allowed to run, whatever length was asked for.
    ///
    /// The cinema view ticks the playhead 20 times a second, so at rate R the dot moves R/20
    /// session-seconds per frame — and *that*, not the rate, is what decides whether the
    /// replay reads as a boat travelling or as a slideshow of positions.
    ///
    /// **What was actually looked at** (docs/testing.md, `UI_REPLAY_LENGTH`): the 30 Aug
    /// Torbole fixture at a 10 s target, which solves to 99×, in the Simulator. Five session
    /// seconds a frame, roughly fifty metres at planing speed: the dot is plainly moving and
    /// the track draws smoothly behind it. 250× is two and a half times that — twelve and a
    /// half seconds and a couple of hundred metres a frame — which is the point at which a
    /// jibe becomes a single displaced dot rather than a turn. It is a ceiling with headroom
    /// over what was observed to work, not a measured failure point; if a rider ever reports a
    /// four-hour clip stuttering, this is the number to lower.
    ///
    /// It only ever binds on a very long session with a very short target — a four-hour
    /// afternoon squeezed into ten seconds would want 1400×. The clip is then longer than the
    /// label, which the sheet says out loud rather than hiding, because the alternative is a
    /// clip in which nothing recognisable happens.
    public static let maxRate: Double = 250

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
                            easeAt: [Double] = [],
                            ease: ReplayDriver.Ease = .cinema) -> Plan {
        let spanS = max(span.upperBound - span.lowerBound, 0)
        // A recording with no duration has no replay to pace, and a nonsensical target is not
        // worth a search. Either way the driver's own clamping does the rest.
        guard spanS > 0, targetWallS > 0 else { return Plan(rate: minRate, ease: ease) }

        // The two steps are interleaved rather than sequential, because each moves the other:
        // shorter dips let the rate come down, and a different rate changes what the dips
        // cost. Four passes is far more than the fixed point needs — it converges from above
        // and monotonically (see `budget`) — and it costs four integrals of a 4096-sample sum.
        var budgeted = ease
        var rate = min(max(spanS / targetWallS, minRate), maxRate)
        for _ in 0..<4 {
            guard let tighter = budget(budgeted, span: span, targetWallS: targetWallS,
                                       easeAt: easeAt, spanS: spanS, rate: rate)
            else { break }
            budgeted = tighter
            rate = solve(span: span, targetWallS: targetWallS, easeAt: easeAt, ease: budgeted)
        }
        rate = solve(span: span, targetWallS: targetWallS, easeAt: easeAt, ease: budgeted)
        return Plan(rate: rate, ease: budgeted)
    }

    /// Step 1: shrink the dips until they fit their share of the clip. Returns nil once they
    /// already do, which is what ends the loop above.
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

    /// Step 2: bisect the rate. `runWallS` falls monotonically as the rate rises, so forty
    /// halvings of [1, 250] settle it to well under a millisecond of clip.
    ///
    /// Both saturations are real answers, not failures. A target longer than the session at
    /// real time gets `minRate` — you cannot stretch four minutes into ten by playing it back
    /// faster. A target that would need more than `maxRate` gets the cap, and a clip longer
    /// than it asked for, which the sheet quotes honestly.
    private static func solve(span: ClosedRange<Double>, targetWallS: Double,
                              easeAt: [Double], ease: ReplayDriver.Ease) -> Double {
        func runWallS(_ rate: Double) -> Double {
            ReplayDriver(span: span, rate: rate, easeAt: easeAt, ease: ease).runWallS
        }
        guard runWallS(minRate) > targetWallS else { return minRate }
        guard runWallS(maxRate) < targetWallS else { return maxRate }
        var slow = minRate, fast = maxRate
        for _ in 0..<40 {
            let middle = (slow + fast) / 2
            if runWallS(middle) > targetWallS { slow = middle } else { fast = middle }
        }
        return (slow + fast) / 2
    }
}
