import Foundation

/// **Where the board was pointing, and how fast that was changing** — the second strip's
/// two series, on the same clock as the speed strip above it.
///
/// The speed strip answers "what did the turn cost". It cannot answer the question the turn
/// *detector* asks, which is entirely about heading: a sweep is kept when it clears
/// `turnMinAngle` and contains a sample at `turnPeakRate`, and it is trimmed at both ends to
/// where the rate falls under `turnContinueRate`. Three numbers decide where a jibe begins
/// and ends and none of them was ever drawn. This is that picture.
///
/// **Pure, and in the kit**, for the reason `TurnSlice` is: the unwrap and the TWA sign
/// convention are statements about the session that are invisible in a screenshot until a
/// jibe comes out drawn as a 350° cliff.
public struct SliceAngles: Sendable, Equatable {

    /// One vertex's angle, and the rate the board was turning at when it left.
    public struct Point: Sendable, Equatable {
        /// Seconds from the event's start.
        public var rt: Double
        /// The **unwrapped** angle: TWA where the wind is known, compass heading where it is
        /// not. Unwrapped means it may leave 0…360 or ±180 — see `deg`'s own note.
        public var deg: Double
        /// Signed rate of turn in °/s, from this vertex to the next; nil at the last vertex
        /// and wherever a bearing was missing on either side.
        public var rateDegS: Double?

        public init(rt: Double, deg: Double, rateDegS: Double?) {
            self.rt = rt
            self.deg = deg
            self.rateDegS = rateDegS
        }
    }

    public var points: [Point]
    /// True when `deg` is **true wind angle**: 0 = head to wind, ±180 = dead downwind. False
    /// when it is a compass heading, which is what a session with no usable wind gets.
    public var isTwa: Bool
    /// Signed peak rate over the whole window, for the axis and the spoken label.
    public var peakRateDegS: Double

    public init(points: [Point], isTwa: Bool, peakRateDegS: Double) {
        self.points = points
        self.isTwa = isTwa
        self.peakRateDegS = peakRateDegS
    }

    public var isEmpty: Bool { points.count < 2 }

    /// The angle axis's own domain: the drawn values with a little air, and never narrower
    /// than `minSpanDeg` — a rider who held a straight line through a course change would
    /// otherwise get two degrees of noise magnified into a mountain range.
    public static let minSpanDeg = 30.0

    public var degDomain: ClosedRange<Double> {
        let values = points.map(\.deg)
        guard let lo = values.min(), let hi = values.max() else { return -180...180 }
        let pad = max((hi - lo) * 0.12, (Self.minSpanDeg - (hi - lo)) / 2, 2)
        return (lo - pad)...(hi + pad)
    }

    /// The rate axis's domain, symmetric about zero so the dashed zero line sits in the
    /// middle and a turn to port reads as the mirror of the same turn to starboard.
    ///
    /// `atLeastDegS` is how the thresholds get in: the strip draws `turnPeakRate` and
    /// `turnContinueRate` as rules, and an axis that stopped below the peak rule would drop
    /// the very mark the strip exists for.
    public func rateDomain(atLeastDegS: Double) -> ClosedRange<Double> {
        let peak = points.compactMap(\.rateDegS).map(abs).max() ?? 0
        let top = max(peak * 1.15, atLeastDegS * 1.15, 10)
        return (-top)...top
    }

    // MARK: - Building

    /// Builds the series from a figure's **north-up** points.
    ///
    /// North up, always, even when the drawing is rotated: the wind-up rotation subtracts the
    /// wind from every heading, so on those points the heading already *is* the TWA and
    /// subtracting it again would double the angle. The strip is not a rotated picture, it is
    /// a plot of an angle, and there is exactly one right answer for it.
    ///
    /// **The unwrap.** Consecutive angles are moved by whole turns so each step is the
    /// shortest one — a jibe that runs 350°, 010°, 030° is drawn as 350, 370, 390 rather than
    /// as a cliff and a climb. It is anchored on the first vertex, so the numbers stay near
    /// the values a rider recognises for the first turn and only drift on a sweep that really
    /// did go round more than once.
    ///
    /// **The TWA sign.** `delta(from: wind, to: heading)`: 0 is pointing straight into the
    /// wind it comes from, ±180 is running dead downwind, and the sign says which side of the
    /// axis the board is on. A jibe therefore crosses ±180 and a tack crosses 0 — which is
    /// the same crossing `axisTs` marks, so the strip's `axis` rule lands on the axis line by
    /// construction rather than by agreement.
    public static func make(points input: [TurnSlice.Point],
                            windDirDeg: Double?) -> SliceAngles {
        let isTwa = windDirDeg != nil
        var raw: [(rt: Double, deg: Double)] = []
        raw.reserveCapacity(input.count)
        for point in input {
            guard let heading = point.headingDeg else { continue }
            let deg = windDirDeg.map { TurnSlice.delta(from: $0, to: heading) } ?? heading
            raw.append((rt: point.rt, deg: deg))
        }
        guard raw.count >= 2 else {
            return SliceAngles(points: raw.map { Point(rt: $0.rt, deg: $0.deg, rateDegS: nil) },
                               isTwa: isTwa, peakRateDegS: 0)
        }

        // Unwrap, then read the rate off the *unwrapped* series: after the unwrap a step is
        // already the shortest turn between two bearings, so the rate is a plain difference
        // and cannot disagree with the line it is drawn under.
        var unwrapped = [raw[0].deg]
        for index in 1..<raw.count {
            let previous = unwrapped[index - 1]
            unwrapped.append(previous + TurnSlice.delta(from: raw[index - 1].deg,
                                                        to: raw[index].deg))
        }

        var out: [Point] = []
        out.reserveCapacity(raw.count)
        var peak = 0.0
        for index in raw.indices {
            var rate: Double?
            if index + 1 < raw.count {
                let dt = raw[index + 1].rt - raw[index].rt
                if dt > 0.001 {
                    let value = (unwrapped[index + 1] - unwrapped[index]) / dt
                    rate = value
                    if abs(value) > abs(peak) { peak = value }
                }
            }
            out.append(Point(rt: raw[index].rt, deg: unwrapped[index], rateDegS: rate))
        }
        return SliceAngles(points: out, isTwa: isTwa, peakRateDegS: peak)
    }

    /// Where the drawn angle crosses the **axis** — the dashed rule the strip puts under the
    /// line. ±180 for a jibe's downwind axis and 0 for a tack's head-to-wind one, expressed
    /// in the unwrapped series' own numbers so the rule lands where the line actually is.
    ///
    /// nil on a heading series, which has no axis to cross: a compass bearing of 0 is north,
    /// not the wind, and drawing a rule there would invent a fact.
    public var axisCrossingDeg: Double? {
        guard isTwa, let first = points.first?.deg, let last = points.last?.deg else {
            return nil
        }
        // The nearest multiple of 180 the line actually spans — a jibe's is ±180, a tack's
        // is 0, and a sweep that crossed neither gets no rule at all.
        let lo = min(first, last)
        let hi = max(first, last)
        var best: Double?
        var k = (lo / 180).rounded(.down)
        while k * 180 <= hi + 0.001 {
            defer { k += 1 }
            let candidate = k * 180
            guard candidate >= lo - 0.001 else { continue }
            if best == nil || abs(candidate) < abs(best!) { best = candidate }
        }
        return best
    }
}
