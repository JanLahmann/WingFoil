import Foundation

/// **What the barometer saw** — the third strip's series, and the one place in the app where
/// the "wrist under" verdict is drawn as the measurement it is made of rather than as a chip.
///
/// The submersion mask is one line of arithmetic (`Evidence.submergedMask`): a sample counts
/// as underwater when the barometric altitude reads `turnBaroDrop` metres below the session
/// median. On the water the *absolute* altitude is meaningless — it is a pressure reading,
/// and the session median is whatever the air was doing that afternoon — so the strip draws
/// everything relative to that median, which puts the threshold at a fixed −`dropM` and makes
/// two sessions comparable.
public struct SliceBaro: Sendable, Equatable {

    public struct Point: Sendable, Equatable {
        public var rt: Double
        /// Metres relative to the session reference: negative is "the wrist went down".
        public var m: Double
        /// This sample is inside one of the analysis' submersion episodes.
        public var submerged: Bool

        public init(rt: Double, m: Double, submerged: Bool) {
            self.rt = rt
            self.m = m
            self.submerged = submerged
        }
    }

    public var points: [Point]
    /// The wrist-under line, in the same relative metres: `−dropM`, always, by construction.
    public var thresholdM: Double

    public init(points: [Point], thresholdM: Double) {
        self.points = points
        self.thresholdM = thresholdM
    }

    /// **The empty state's own question.** A session imported from a source with no
    /// barometer, or one whose window happens to carry no finite altitude, has nothing to
    /// draw — and the strip says so in one line rather than drawing a flat trace at zero,
    /// which would read as "the wrist stayed up" when the truth is "nobody was looking".
    public var hasBarometer: Bool { points.count >= 2 }

    /// The metre axis, floored at a span that keeps the threshold rule on screen. Without the
    /// floor a dry window — where the altitude wanders over half a metre — magnifies its own
    /// noise into a mountain and pushes the −25 m rule off the bottom of the plot, so the one
    /// mark the strip exists for is the one mark you cannot see.
    public var metreDomain: ClosedRange<Double> {
        let values = points.map(\.m)
        let lo = min(values.min() ?? 0, thresholdM * 1.2, -1)
        let hi = max(values.max() ?? 0, 1)
        return lo...(hi + max((hi - lo) * 0.08, 0.5))
    }

    /// The submerged samples as spans, so the strip shades them instead of dotting each one.
    /// Consecutive runs only — the merge rule that makes a dunk and the wave after it one
    /// event is the engine's (`Evidence.submersionMergeS`) and is already applied to the
    /// episodes this was built from.
    public var submergedSpans: [ClosedRange<Double>] {
        var out: [ClosedRange<Double>] = []
        var start: Double?
        var previous: Double?
        for point in points {
            if point.submerged {
                if start == nil { start = point.rt }
                previous = point.rt
            } else if let from = start, let to = previous {
                out.append(from...max(to, from))
                start = nil
                previous = nil
            }
        }
        if let from = start, let to = previous { out.append(from...max(to, from)) }
        return out
    }

    // MARK: - Building

    /// `referenceM` is the session median (`BaroReference.session`), `dropM` the engine's
    /// `turnBaroDrop` from this analysis' own config echo, and `submersions` the episode
    /// spans **on the event's own clock** — the caller has them from `analysis.submersions`
    /// and converts, because only the caller knows the event's `t = 0`.
    ///
    /// Reading the episodes rather than re-applying the threshold is deliberate. The mask
    /// the verdict was computed with is the engine's, and a strip that re-derived it here
    /// could mark a sample the analysis did not — one rounding apart from the stored
    /// document, and the picture would quietly disagree with the chip above it.
    public static func make(points input: [TurnSlice.Point], referenceM: Double?,
                            dropM: Double,
                            submersions: [ClosedRange<Double>] = []) -> SliceBaro {
        guard let reference = referenceM, reference.isFinite else {
            return SliceBaro(points: [], thresholdM: -abs(dropM))
        }
        let points = input.compactMap { point -> Point? in
            guard let alt = point.altM, alt.isFinite else { return nil }
            return Point(rt: point.rt, m: alt - reference,
                         submerged: submersions.contains { $0.contains(point.rt) })
        }
        return SliceBaro(points: points, thresholdM: -abs(dropM))
    }
}

/// The altitude every submersion is measured **against**.
///
/// One forwarder rather than a second median: the engine already spells this rule
/// (`Evidence.submergedReference` — the session median of the finite samples), the mask and
/// each episode's `dropM` are both read from it, and a presentation copy that drifted by a
/// metre would draw the threshold rule in the wrong place on every strip in the app.
public enum BaroReference {
    /// nil where the source has no altitude channel at all, which is what makes the
    /// barometer strip print its one-line empty state.
    public static func session(_ altM: [Double?]) -> Double? {
        Evidence.submergedReference(altM)
    }
}
