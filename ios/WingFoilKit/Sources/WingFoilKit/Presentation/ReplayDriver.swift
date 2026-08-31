import Foundation

/// Drives a replay that plays *itself*: wall-clock ticks in, playhead position out.
///
/// The scrubber's own playback is three lines inside a `.task` — a fixed step per tick and a
/// clamp at the end — and that was fine while a hand was on the slider. The cinema replay is
/// different in the one way that matters: it is the **renderer** for a clip somebody else
/// will watch, so the pace it runs at is part of the thing being published. "The clip ran
/// past the jibe before the caption could be read" is a defect nobody can see in a
/// screenshot and nobody can fix after the fact, so the pacing lives here — next to
/// `ReplayBeats` and `ReplayCommentary`, pure, a function of (span, rate, milestone times)
/// only, and pinned by a test against the Torbole fixture.
///
/// Nothing in here knows about views, timers or ReplayKit. The caller ticks it; where the
/// ticks come from is the caller's problem.
public struct ReplayDriver: Sendable, Equatable {

    /// The cinematic slow-down: how far the run eases off around a milestone, and how wide
    /// the ease is.
    ///
    /// **Why it exists.** At 30× a jibe is a third of a second and the caption naming it is
    /// up for two and a half — the words arrive, the thing they are about is already gone.
    /// Easing to a quarter speed for a beat on either side of the milestone puts the two
    /// back on the same screen, and it is the one piece of grammar every sports highlight
    /// reel shares.
    public struct Ease: Sendable, Equatable {

        /// Slowest fraction of the nominal rate, reached exactly on the milestone. A quarter:
        /// at 30× that is 7.5× — still a replay, still recognisably a jibe.
        public var floor: Double

        /// Half-width of the dip, in **wall** seconds at the nominal rate.
        ///
        /// Wall rather than session seconds, which is the only unit that means the same
        /// thing at all three speeds: two session-seconds around a milestone is a third of a
        /// wall second at 60× (invisible) and a fifth of a second at 10× (also invisible).
        /// Six tenths of a second on each side is six tenths of a second at every rate, and
        /// the driver converts it to session seconds with the rate it was built for.
        ///
        /// Six tenths and not a full second because the dips are what the clip's length is
        /// really made of: on the 30 Aug Torbole fixture (645 s, twelve milestones) 0.6
        /// turns a nominal 21.5 s run at 30× into 34 s, and 1.0 would make it 42 — at which
        /// point the rate a rider picked is no longer the number they were choosing by.
        public var halfWidthWallS: Double

        public init(floor: Double = 0.25, halfWidthWallS: Double = 0.6) {
            self.floor = min(max(floor, 0.01), 1)
            self.halfWidthWallS = max(halfWidthWallS, 0)
        }

        /// What the cinema view uses.
        public static let cinema = Ease()

        /// No slow-down at all — constant rate, the scrubber's behaviour. Also what a caller
        /// gets by passing no milestones.
        public static let none = Ease(floor: 1, halfWidthWallS: 0)
    }

    /// The session clock the playhead rides on, exactly as the scrubber's slider uses it.
    public let span: ClosedRange<Double>
    /// Session seconds per wall second, before the ease: 10, 30 or 60.
    public let rate: Double
    /// Instants the run eases through, sorted. In practice `milestones.map(\.t)` — the
    /// commentary's own script, so the slow-down and the captions cannot drift apart.
    public let easeAt: [Double]
    public let ease: Ease

    public init(span: ClosedRange<Double>, rate: Double,
                easeAt: [Double] = [], ease: Ease = .cinema) {
        self.span = span
        // A non-positive rate is a stopped replay, which is a state the view expresses by
        // not ticking rather than by asking the driver to divide by zero.
        self.rate = max(rate, 0.001)
        self.easeAt = easeAt.sorted()
        self.ease = ease
    }

    /// Where a run begins. The cinema replay always starts at the session's first sample —
    /// a clip that opens halfway through is not a session replay.
    public var start: Double { span.lowerBound }

    /// Session seconds in the whole run. Zero on a recording with no duration.
    public var sessionSpanS: Double { max(span.upperBound - span.lowerBound, 0) }

    /// Half-width of one ease, in session seconds.
    private var easeHalfWidthS: Double { ease.halfWidthWallS * rate }

    // MARK: - The pace curve

    /// How fast the run is moving at `t`, as a fraction of the nominal rate — 1 on open
    /// water, `ease.floor` exactly on a milestone.
    ///
    /// One raised-cosine dip per milestone, centred **on** it: the run decelerates into the
    /// jibe and accelerates out of it, which is what slow motion looks like and is also the
    /// only shape with no corner in it. A rectangular slow patch reads as a dropped frame,
    /// and a linear ramp kinks visibly at both ends of the dip.
    ///
    /// Overlapping dips take the **deepest** rather than multiplying: a cluster of
    /// milestones fifteen seconds apart — which is most of a good session — is one slow
    /// passage at a quarter speed, not a crawl at a sixty-fourth.
    public func pace(at t: Double) -> Double {
        let halfWidth = easeHalfWidthS
        guard !easeAt.isEmpty, halfWidth > 0, ease.floor < 1 else { return 1 }
        var deepest = 0.0
        for milestone in easeAt {
            let distance = abs(t - milestone)
            guard distance < halfWidth else { continue }
            deepest = max(deepest, 0.5 * (1 + cos(.pi * distance / halfWidth)))
            if deepest >= 1 { break }
        }
        return 1 - (1 - ease.floor) * deepest
    }

    /// Session seconds per wall second at `t`, ease included.
    public func rate(at t: Double) -> Double { rate * pace(at: t) }

    // MARK: - Ticking

    /// The playhead one tick later, clamped into the span at both ends.
    ///
    /// A **midpoint** step rather than the obvious `t + rate(at: t) * dt`: sampling the ease
    /// only at the step's leading edge lags the curve by half a tick, and half a tick at 60×
    /// is a second and a half of session — enough to put the slowest instant of the dip past
    /// the jibe it is meant to be slowing for. With no ease the two are identical, so the
    /// constant-rate arithmetic stays exactly `span / rate`.
    public func advance(_ t: Double, byWallSeconds dt: Double) -> Double {
        guard dt > 0 else { return clamp(t) }
        let from = clamp(t)
        let midpoint = from + rate(at: from) * dt / 2
        return clamp(from + rate(at: midpoint) * dt)
    }

    /// Whether the run is over — the caller's cue to stop the recorder and offer the clip.
    ///
    /// A tolerance rather than `>=`, because `advance` clamps *to* `span.upperBound` and a
    /// caller that compared exactly would need the same float to come back twice.
    public func hasFinished(_ t: Double, tolerance: Double = 0.001) -> Bool {
        t >= span.upperBound - tolerance
    }

    /// 0…1, for the progress hairline along the bottom of the frame.
    public func progress(at t: Double) -> Double {
        guard sessionSpanS > 0 else { return 1 }
        return min(max((t - span.lowerBound) / sessionSpanS, 0), 1)
    }

    private func clamp(_ t: Double) -> Double {
        min(max(t, span.lowerBound), span.upperBound)
    }

    // MARK: - How long the clip will be

    /// Wall seconds the whole run takes, ease included — the number the rate picker offers
    /// before anything is recorded ("30× · about 35 s"), and the one a rider is really
    /// choosing between when they pick a speed.
    ///
    /// Integrated rather than simulated: the answer must not depend on the view's tick rate,
    /// and `∫ ds / rate(s)` over the span is the same quantity the ticking converges to. The
    /// midpoint rule over a fixed sample count is exact for the constant-rate case (every
    /// sample returns the same pace), so `645 s at 30×` is 21.5 s on the nose whatever N is.
    public var runWallS: Double {
        guard sessionSpanS > 0 else { return 0 }
        let samples = 4096
        let step = sessionSpanS / Double(samples)
        var total = 0.0
        for index in 0..<samples {
            let midpoint = span.lowerBound + (Double(index) + 0.5) * step
            total += step / rate(at: midpoint)
        }
        return total
    }
}
