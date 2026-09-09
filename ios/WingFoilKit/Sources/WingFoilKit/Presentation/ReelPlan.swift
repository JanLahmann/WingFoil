import Foundation

/// One thing worth interrupting a fifteen-second video for.
///
/// A reel's moments are deliberately *not* `ReplayBeat`s and *not* `ReplayMilestone`s, even
/// though all three are lists of instants derived from one analysis. A beat is "where can I
/// scrub to" and a milestone is "what would a friend say out loud"; a moment is **"where
/// does the clock have to slow down, and what pops on screen when it does"**. The three
/// lists differ in exactly the place that matters here: a reel slows for *every* counted
/// jibe, because the breadcrumb drawing itself through a jibe at 200× is a smear and at 20×
/// is a maneuver, and that is a statement about drawing rather than about narration.
public struct ReelMoment: Sendable, Equatable, Identifiable {

    public enum Kind: Sendable, Equatable {
        /// The start of the longest flight — the takeoff a rider remembers.
        case takeoff
        /// A counted jibe, with the verdict it ended on and whether it was *clean*.
        case jibe(TurnOutcomeKind, clean: Bool)
        /// A speed record's window, by the engine's own window key ("best2s", …).
        case record(String)
        /// One "wrist under" episode.
        case submersion

        /// **Whether the clock slows here.** Takeoffs, jibes and records do; a submersion
        /// does not.
        ///
        /// A submersion is evidence rather than an event — it is a pressure step the
        /// barometer saw, it already belongs to a turn or a flight end most of the time
        /// (`SubmersionRecord.turnIndex`), and slowing for it would slow twice for one
        /// moment. It still gets a callout: the diamond is the mark every map in the app
        /// draws, and a reel that silently dropped it would be the one surface that does
        /// not (docs/presentation.md, "Wrist under").
        public var slowsTheClock: Bool {
            switch self {
            case .takeoff, .jibe, .record: true
            case .submersion: false
            }
        }
    }

    /// Stable across rebuilds of the same analysis.
    public let id: String
    /// Session-clock seconds — the same clock the playhead, the chart and the map dot ride.
    public let t: Double
    public let kind: Kind
    /// The whole callout, ready to draw: "jibe · flew through", "best 2 s 14.9 kn".
    ///
    /// Lowercase, because it is a label over a moving picture and not a sentence, and it
    /// borrows its verdict word from `TurnOutcomeKind.label` and its record spelling from
    /// `RecordKind.windowLabel` so the reel cannot invent a second vocabulary
    /// (docs/presentation.md, "Label table").
    public let headline: String

    public init(id: String, t: Double, kind: Kind, headline: String) {
        self.id = id
        self.t = t
        self.kind = kind
        self.headline = headline
    }
}

/// The cut: which moments a session video stops for, and the clock it is drawn on.
///
/// **Pure, in the kit, and tested**, for the same reason `ReplayPacing` is: "the whole track
/// draws over twenty seconds, but a jibe takes a second and a half of them" is a statement
/// about a session, and it is invisible in a rendered frame until a rider notices his best
/// jibe went past in two frames.
///
/// # The warp
///
/// A reel is a **density**, not a rate. Over the session's span the plan lays down an
/// attention density `d(t)`: 1 everywhere, rising to `boost` in a raised-cosine bump of
/// half-width `halfWidthS` around every moment that `slowsTheClock`. Reel time is that
/// density's integral, normalised to the length of the map section:
///
/// ```
/// reelTime(t) = mapS · ∫ₐᵗ d / ∫ₐᵇ d
/// ```
///
/// Every property the renderer needs falls out of that shape rather than being enforced:
/// the map is monotone in the session (d > 0), it starts at 0 and ends at `mapS` exactly
/// (the normalisation), the whole track therefore draws (nothing is skipped), and time near
/// a moment is stretched by exactly `boost` relative to the gaps.
///
/// **Why not `ReplayDriver`.** The cinema replay's warp is the same idea in the opposite
/// direction — a rate field ticked forward by `advance(_:byWallSeconds:)` — and it is right
/// for a live view, which only ever asks "where am I one frame later". An offscreen renderer
/// asks the other question: "given frame 317 of 600, where in the session am I", and the
/// driver has no inverse to answer it. Ticking `advance` 600 times would answer it by
/// accident and make every frame depend on the 316 before it, which is exactly the thing
/// that makes a render impossible to test one frame at a time. So: a table, and a bisection.
///
/// # The shrink
///
/// `halfWidthS` is not a constant, because forty jibes at three seconds each is two minutes
/// of premium in a twenty-second cut, and the bumps would merge into one flat, slow reel
/// that never gets anywhere. It halves — at most `shrinkSteps` times, from `S / 8` — until
/// the *extra* density mass is at most `highlightShare` of the whole, which is to say until
/// the moments own at most that fraction of the cut. Same move, and the same reason, as
/// `ReplayPacing.budget`.
public struct ReelPlan: Sendable, Equatable {

    // MARK: - The cut's length

    /// The lengths the export sheet offers. Twenty by default: fifteen is too short to
    /// hold an afternoon's shape and thirty is longer than a scroll past on a feed.
    public enum Length: Int, CaseIterable, Sendable, Identifiable, Codable {
        case s15 = 15
        case s20 = 20
        case s30 = 30

        public static let standard = Length.s20
        public var id: Int { rawValue }
        public var seconds: Double { Double(rawValue) }
        public var label: String { "\(rawValue) s" }
    }

    // MARK: - Constants

    /// Frames per second. Thirty, not sixty: the thing being animated is a breadcrumb
    /// growing over a still photograph, and doubling the frames doubles the render for a
    /// motion nobody can see.
    public static let fps = 30

    /// The end card's share of the cut. Three seconds is about as long as a reader spends
    /// on a still frame before scrolling, and it is the same card the share card is.
    public static let endCardS: Double = 3

    /// How long a callout stays up, in **reel** seconds. Long enough to read three words.
    public static let calloutS: Double = 1.5

    /// How much slower the clock runs at the centre of a moment than in the gaps.
    static let boost: Double = 5

    /// The largest share of the map section the moments may own between them.
    static let highlightShare: Double = 0.6

    /// Halvings the shrink is allowed. Twelve takes `S / 8` below a second on any session.
    static let shrinkSteps = 12

    /// The shortest a bump may get. Below this the warp is nearly linear, which is the
    /// right answer for a session where a hundred jibes make nothing special.
    static let minHalfWidthS: Double = 0.75

    /// Buckets in the cumulative table. A power of two, and fixed, so the same analysis
    /// gives the same table on every machine.
    static let samples = 1024

    // MARK: - Stored

    /// The session clock the reel is cut from.
    public let span: ClosedRange<Double>
    public let length: Length
    /// Every moment, in time order — callouts and warp anchors alike.
    public let moments: [ReelMoment]
    /// The bump half-width the shrink settled on, in session seconds.
    public let halfWidthS: Double

    /// `cumulative[i]` is `∫ d` from the span's start to bucket boundary `i`, normalised so
    /// the last entry is 1. `samples + 1` entries; monotone non-decreasing by construction.
    private let cumulative: [Double]

    // MARK: - Derived lengths

    /// Seconds of animated map — the whole cut minus the end card.
    public var mapS: Double { max(length.seconds - Self.endCardS, 1) }
    /// The whole cut.
    public var totalS: Double { length.seconds }
    /// Frames the renderer writes. The end card is frames too: it is a video, and a viewer
    /// scrubbing back into it must find something there.
    public var frameCount: Int { Int((totalS * Double(Self.fps)).rounded()) }

    // MARK: - Building

    /// The plan for one analysis.
    ///
    /// `span` is the recording's own scrubbable range (`SessionDetail.timeRange`) and is
    /// optional for the same reason `ReplayCommentary.make`'s is: the engine's clean clock
    /// starts at zero, so `0 ... durationS` is the right answer when the caller has nothing
    /// better — but a caller holding a timeline should pass it, because a moment outside the
    /// span is a moment the reel can never reach.
    public static func make(_ analysis: SessionAnalysis,
                            span: ClosedRange<Double>? = nil,
                            length: Length = .standard) -> ReelPlan {
        let clock = span ?? 0 ... max(analysis.summary.durationS, 0)
        let moments = self.moments(analysis, span: clock)
        return ReelPlan(span: clock, length: length, moments: moments)
    }

    /// Designated. Solves the shrink and builds the table; callers normally use `make`.
    public init(span: ClosedRange<Double>, length: Length = .standard,
                moments: [ReelMoment] = []) {
        self.span = span
        self.length = length
        self.moments = moments.sorted { $0.t == $1.t ? $0.id < $1.id : $0.t < $1.t }

        let spanS = max(span.upperBound - span.lowerBound, 0)
        // Anchors live on offsets from the span's start, because the table does; shifting
        // them once here is what stops the shrink and the table measuring different lists.
        let anchors = self.moments.filter(\.kind.slowsTheClock).map { $0.t - span.lowerBound }
        let width = Self.shrink(anchors: anchors, spanS: spanS)
        self.halfWidthS = width
        self.cumulative = Self.table(anchors: anchors, spanS: spanS, halfWidthS: width)
    }

    // MARK: - The clock

    /// Where in the session reel-second `r` is looking.
    ///
    /// Clamped at both ends, and **the end card holds on the last frame of the session**:
    /// past `mapS` this keeps returning the span's upper bound, so a renderer that asks for
    /// a position during the end card gets the finished track rather than a wrapped one.
    public func sessionTime(atReelTime r: Double) -> Double {
        let spanS = span.upperBound - span.lowerBound
        guard spanS > 0 else { return span.lowerBound }
        let clamped = min(max(r, 0), mapS)
        return span.lowerBound + spanS * Self.invert(clamped / mapS, in: cumulative)
    }

    /// The inverse: where session-second `t` lands in the cut. `mapS` for anything at or
    /// past the end of the session, 0 for anything before its start.
    public func reelTime(ofSessionTime t: Double) -> Double {
        let spanS = span.upperBound - span.lowerBound
        guard spanS > 0 else { return 0 }
        let u = min(max((t - span.lowerBound) / spanS, 0), 1)
        return mapS * Self.sample(u, in: cumulative)
    }

    /// How many session seconds pass per reel second at `r` — 1× at the plan's own average,
    /// low at a moment, high in a gap. The number the dev overlay would print, and the one
    /// the tests hold the warp's *shape* by.
    public func compression(atReelTime r: Double) -> Double {
        let step = 1.0 / Double(Self.fps)
        let before = sessionTime(atReelTime: max(r - step / 2, 0))
        let after = sessionTime(atReelTime: min(r + step / 2, mapS))
        return (after - before) / step
    }

    /// Is reel-second `r` on the end card?
    public func isEndCard(atReelTime r: Double) -> Bool { r >= mapS }

    /// How far into the end card `r` is, 0…1 — what a fade reads.
    public func endCardProgress(atReelTime r: Double) -> Double {
        guard Self.endCardS > 0 else { return 1 }
        return min(max((r - mapS) / Self.endCardS, 0), 1)
    }

    // MARK: - Callouts

    /// The moment whose callout is on screen at reel-second `r`, and how far through its
    /// `calloutS` it is (0…1) so the renderer can pop and fade it.
    ///
    /// **One callout at a time.** Two labels stacked over a moving map is two things to read
    /// and no time to read either, so the *latest* moment whose window is open wins — the
    /// newest news, which is what a viewer is looking for anyway. The window opens at the
    /// moment's own instant rather than before it: a callout that appears before the thing
    /// it names is a spoiler.
    public func callout(atReelTime r: Double) -> (moment: ReelMoment, progress: Double)? {
        guard !moments.isEmpty, !isEndCard(atReelTime: r) else { return nil }
        var best: (ReelMoment, Double)?
        for moment in moments {
            let opened = reelTime(ofSessionTime: moment.t)
            guard r >= opened, r < opened + Self.calloutS else { continue }
            best = (moment, (r - opened) / Self.calloutS)
        }
        return best
    }

    // MARK: - The running tally

    /// The counted jibes that have happened by session-second `t`, split the way the
    /// key-metrics block splits them.
    ///
    /// *Dry* is flew-through plus touchdown — the jibes he came out of still sailing — which
    /// is the same set `SessionSummarizer` counts for JPH, so the strip's "5 flew · 11 dry"
    /// and the end card's rates can never be about different turns
    /// (docs/presentation.md, "Rates are additive").
    public struct Tally: Sendable, Equatable {
        public var flew = 0
        public var touchdown = 0
        public var fell = 0
        public var clean = 0
        public init() {}
        public var counted: Int { flew + touchdown + fell }
        public var dry: Int { flew + touchdown }
    }

    public func tally(throughSessionTime t: Double) -> Tally {
        var out = Tally()
        for moment in moments {
            guard moment.t <= t, case .jibe(let outcome, let clean) = moment.kind else {
                continue
            }
            switch outcome {
            case .flewThrough: out.flew += 1
            case .touchdown: out.touchdown += 1
            case .fellIn: out.fell += 1
            }
            if clean { out.clean += 1 }
        }
        return out
    }

    // MARK: - Equatable
    //
    // The table is a function of the other three and is 8 KB of doubles; comparing it would
    // make every equality check a memcmp of derived data that can only ever agree.

    public static func == (lhs: ReelPlan, rhs: ReelPlan) -> Bool {
        lhs.span == rhs.span && lhs.length == rhs.length && lhs.moments == rhs.moments
    }

    // MARK: - Moments, from one analysis

    static func moments(_ analysis: SessionAnalysis,
                        span: ClosedRange<Double>) -> [ReelMoment] {
        var out: [ReelMoment] = []

        // The longest flight by *time*, which is the one a rider remembers, and its start —
        // the takeoff, not the flight. Ties go to the earlier flight so the choice never
        // depends on array order (`ReplayBeats.make` picks it the same way, deliberately).
        if let longest = analysis.flights.enumerated().max(by: {
            let (a, b) = ($0.element, $1.element)
            let (da, db) = (a.endTs - a.startTs, b.endTs - b.startTs)
            return da == db ? a.startTs > b.startTs : da < db
        }), longest.element.endTs > longest.element.startTs {
            out.append(ReelMoment(id: "takeoff", t: longest.element.startTs,
                                  kind: .takeoff, headline: "takeoff"))
        }

        // Counted jibes only. A bear-away or a round-up is a course change with no verdict
        // in it, and a reel that slowed down for one would be slowing down for nothing.
        for (index, turn) in analysis.turns.enumerated()
        where turn.counted && turn.type == "jibe" {
            let outcome = TurnOutcomeKind(turn.outcome)
            // The star's own line. A clean jibe answers to one chip on every map
            // (`TurnOutcomeKind.layer(clean:)`) and it gets one line here for the same
            // reason: it is the strict verdict, not a decorated flew-through.
            let headline = turn.clean
                ? "clean jibe"
                : "jibe · \(outcome.label)"
            out.append(ReelMoment(id: "jibe-\(index)", t: turn.ts,
                                  kind: .jibe(outcome, clean: turn.clean),
                                  headline: headline))
        }

        // The speed set the key-metrics block prints, and only where the engine gave the
        // record a window: a record with a value but no provenance cannot be put on a clock.
        for kind in [RecordKind.best2s, .best5x10s, .alpha500] {
            guard let window = analysis.records.windows[kind.rawValue],
                  let value = kind.value(in: analysis.records), value > 0 else { continue }
            out.append(ReelMoment(id: "record-\(kind.rawValue)", t: window.startTs,
                                  kind: .record(kind.rawValue),
                                  headline: "best \(kind.windowLabel) \(KeyMetrics.knots(value))"))
        }

        for (index, episode) in analysis.submersions.enumerated() {
            out.append(ReelMoment(id: "wet-\(index)", t: episode.ts,
                                  kind: .submersion, headline: "wrist under"))
        }

        // Everything outside the span goes: a moment the playhead can never reach is a
        // callout that never fires and a bump the warp spends its budget on.
        return out
            .filter { span.contains($0.t) }
            .sorted { $0.t == $1.t ? $0.id < $1.id : $0.t < $1.t }
    }

    // MARK: - The density, the shrink and the table

    /// `d(t) - 1` at session offset `u` (seconds from the span's start), before the boost.
    /// Overlapping bumps take the deepest rather than summing — two jibes four seconds
    /// apart are one slow passage, not a passage twice as slow.
    static func bump(_ u: Double, anchors: [Double], halfWidthS: Double) -> Double {
        guard halfWidthS > 0, !anchors.isEmpty else { return 0 }
        var deepest = 0.0
        for anchor in anchors {
            let distance = abs(u - anchor)
            guard distance < halfWidthS else { continue }
            deepest = max(deepest, 0.5 * (1 + cos(.pi * distance / halfWidthS)))
            if deepest >= 1 { break }
        }
        return deepest
    }

    /// The half-width that keeps the moments inside their share of the cut.
    static func shrink(anchors: [Double], spanS: Double) -> Double {
        guard spanS > 0, !anchors.isEmpty else { return 0 }
        // The premium the moments may cost, as a multiple of the session's own length:
        // extra / (spanS + extra) ≤ highlightShare.
        let allowance = highlightShare / (1 - highlightShare) * spanS
        var width = spanS / 8
        for _ in 0..<shrinkSteps {
            if width <= minHalfWidthS { break }
            if (boost - 1) * mass(anchors: anchors, spanS: spanS, halfWidthS: width)
                <= allowance {
                break
            }
            width /= 2
        }
        return max(width, min(minHalfWidthS, spanS))
    }

    /// `∫ bump` over the span, by the same midpoint rule the table uses, so the shrink's
    /// arithmetic and the table's cannot disagree.
    static func mass(anchors: [Double], spanS: Double, halfWidthS: Double) -> Double {
        let step = spanS / Double(samples)
        var total = 0.0
        for index in 0..<samples {
            total += bump((Double(index) + 0.5) * step, anchors: anchors,
                          halfWidthS: halfWidthS) * step
        }
        return total
    }

    /// The normalised cumulative density, `samples + 1` long, first entry 0 and last 1.
    /// `anchors` are offsets from the span's start, as `init` shifted them.
    static func table(anchors: [Double], spanS: Double, halfWidthS: Double) -> [Double] {
        guard spanS > 0 else { return [0, 1] }
        let step = spanS / Double(samples)
        var out = [Double](repeating: 0, count: samples + 1)
        var running = 0.0
        for index in 0..<samples {
            let mid = (Double(index) + 0.5) * step
            running += (1 + (boost - 1) * bump(mid, anchors: anchors,
                                               halfWidthS: halfWidthS)) * step
            out[index + 1] = running
        }
        guard running > 0 else { return out }
        for index in out.indices { out[index] /= running }
        return out
    }

    /// The table at fraction `u` of the span, linearly between buckets.
    static func sample(_ u: Double, in table: [Double]) -> Double {
        guard table.count > 1 else { return u }
        let scaled = min(max(u, 0), 1) * Double(table.count - 1)
        let low = min(Int(scaled), table.count - 2)
        let frac = scaled - Double(low)
        return table[low] + (table[low + 1] - table[low]) * frac
    }

    /// The table's inverse at reel fraction `y`, by bisection then linear interpolation.
    /// Monotone data, so the bisection cannot pick the wrong bracket.
    static func invert(_ y: Double, in table: [Double]) -> Double {
        guard table.count > 1 else { return y }
        let target = min(max(y, 0), 1)
        var low = 0, high = table.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if table[mid] <= target { low = mid } else { high = mid }
        }
        let width = table[high] - table[low]
        let frac = width > 0 ? (target - table[low]) / width : 0
        return (Double(low) + frac) / Double(table.count - 1)
    }
}

