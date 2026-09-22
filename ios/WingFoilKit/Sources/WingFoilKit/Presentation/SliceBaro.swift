import Foundation

/// **What the barometer saw** — the third strip's series, and the one place in the app where
/// the "wrist under" verdict is drawn as the measurement it is made of rather than as a chip.
///
/// The submersion mask is one rule (`Evidence.submergedTrace`): a sample counts as underwater
/// when the barometric altitude reads `turnBaroDrop` metres below the **local baseline** — the
/// line the altimeter had settled on just before. On the water the *absolute* altitude is
/// meaningless — it is a pressure reading, and the baseline is whatever the air, and the
/// watch, were doing at that moment — so the strip draws everything relative to that line,
/// which puts the threshold at a fixed −`dropM` and makes two maneuvers comparable.
public struct SliceBaro: Sendable, Equatable {

    public struct Point: Sendable, Equatable {
        public var rt: Double
        /// Metres relative to the local baseline: negative is "the wrist went down".
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

    /// `referenceM` is the local baseline at this event (`BaroReference.at`), `dropM` the engine's
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

/// The altitude a maneuver's submersions are measured **against**.
///
/// Since engine 0.22.0 that is not one number for the afternoon: the wrist-under test reads
/// a **local baseline** that walks with the altimeter and holds under a spike
/// (`Evidence.submergedTrace`, docs/algorithms/pumping.md "Turn outcome" step 2). So the strip asks
/// for the line in force at the moment it is drawing rather than for a median of the day —
/// which is what keeps the −`dropM` rule on the picture where the mask actually crossed it,
/// on a watch whose reference stepped 190 m between stretches as readily as on one whose
/// did not.
///
/// A forwarder, still: the engine spells the rule once, and a presentation copy that drifted
/// by a metre would draw the threshold in the wrong place on every strip in the app.
public struct BaroReference: Sendable, Equatable {
    /// Sample times of the cleaned track.
    public var t: [Double]
    /// The engine's own baseline at each of them; `nan` before the first finite altitude.
    public var baseline: [Double]

    public init(t: [Double], baseline: [Double]) {
        self.t = t
        self.baseline = baseline
    }

    /// The engine's baseline over a whole cleaned track, built once per session.
    public static func session(_ samples: [CleanSample], dropM: Double) -> BaroReference {
        let t = samples.map(\.t)
        let trace = Evidence.submergedTrace(samples.map(\.altM), t: t,
                                            gap: samples.map(\.gapBefore), dropM: dropM)
        return BaroReference(t: t, baseline: trace.baseline)
    }

    /// The line in force at `ts`: the last sample at or before it that has one.
    ///
    /// nil where the source has no altitude channel at all, which is what makes the
    /// barometer strip print its one-line empty state. A window that opens before the first
    /// finite altitude borrows the first line there is rather than going blank — the trace
    /// it is drawn beside starts there too.
    public func at(_ ts: Double) -> Double? {
        var best: Double?
        for i in t.indices {
            if t[i] > ts { break }
            if baseline[i].isFinite { best = baseline[i] }
        }
        return best ?? baseline.first { $0.isFinite }
    }
}
