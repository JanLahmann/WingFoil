import Foundation

/// One turn, cut out of the session and put in its own little frame — the geometry the turn
/// detail sheet draws, and nothing else.
///
/// **Why the turn gets a frame of its own.** The session map answers "where did I ride"; a
/// single jibe is 30 m of water inside 2 km of it, and at session scale it is four pixels.
/// Reading one turn means throwing the session away and drawing the turn: local metres around
/// its own entry point, its own time zero, and — where the wind is known — its own *rotation*,
/// so the picture is oriented the way the rider was thinking rather than the way the compass
/// was pointing.
///
/// **Pure, and in the kit, for the reason `TurnAnalytics` is.** The projection, the heading
/// derivation, the wind-up rotation and the choice of comparison turn are all statements about
/// the session that are invisible in a screenshot until a jibe is drawn backwards. They belong
/// where a test can hold them.
///
/// **It derives, it never re-decides.** `TurnRecord.entryKn`, `minKn`, `score`, `outcome` and
/// the rest are the engine's and stay the engine's — the numbers row prints those. What the
/// slice measures from the samples is only what the engine does not carry: where the track
/// went, which way it was pointing, and where on *this* window the speed bottomed out, so the
/// strip can put a mark there. Definitions: docs/presentation.md, "Turn detail".
public struct TurnSlice: Sendable, Equatable {

    // MARK: - Input

    /// One positioned sample, reduced to the four fields a turn needs. Deliberately not
    /// `RecordSample`: a slice is built from a window a few dozen seconds wide, and the caller
    /// has already decided which samples are positioned.
    public struct Sample: Sendable, Equatable {
        public var t: Double
        public var lat: Double
        public var lon: Double
        public var kn: Double

        public init(t: Double, lat: Double, lon: Double, kn: Double) {
            self.t = t
            self.lat = lat
            self.lon = lon
            self.kn = kn
        }
    }

    // MARK: - Output

    /// One vertex of the drawn turn, in metres around the turn's entry point.
    ///
    /// `x` is metres **east**, `y` metres **north** — the engine's own local frame and the one
    /// `TrackThumbnail.Bounds` carries, so a renderer flips `y` once and nothing else has to
    /// think about it.
    public struct Point: Sendable, Equatable {
        public var x: Double
        public var y: Double
        /// Seconds from the turn's start (`turn.ts`). Negative in the lead-in pad.
        public var rt: Double
        public var kn: Double
        /// Course over ground in degrees (0 = north, clockwise), from this vertex to the next.
        ///
        /// nil where the step was shorter than `minStepM`: at 1 Hz a rider who has stopped
        /// produces a metre of GPS noise per sample, and the bearing of a metre of noise is a
        /// random number. A tick drawn along it would spin.
        public var headingDeg: Double?
        /// Inside `turn.ts ... turn.endTs` — the part drawn thick and coloured.
        public var inTurn: Bool

        public init(x: Double, y: Double, rt: Double, kn: Double,
                    headingDeg: Double? = nil, inTurn: Bool) {
            self.x = x
            self.y = y
            self.rt = rt
            self.kn = kn
            self.headingDeg = headingDeg
            self.inTurn = inTurn
        }
    }

    /// A metre rectangle, in the same east/north frame as `Point`.
    public struct Bounds: Sendable, Equatable {
        public var minX: Double
        public var minY: Double
        public var maxX: Double
        public var maxY: Double

        public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
            self.minX = minX
            self.minY = minY
            self.maxX = maxX
            self.maxY = maxY
        }

        public var width: Double { maxX - minX }
        public var height: Double { maxY - minY }
        public var centerX: Double { (minX + maxX) / 2 }
        public var centerY: Double { (minY + maxY) / 2 }
        /// The side of the square that contains it — what a renderer scales by, so the drawing
        /// keeps its aspect ratio.
        public var spanM: Double { max(width, height, TurnSlice.minSpanM) }

        public func union(_ other: Bounds) -> Bounds {
            Bounds(minX: min(minX, other.minX), minY: min(minY, other.minY),
                   maxX: max(maxX, other.maxX), maxY: max(maxY, other.maxY))
        }

        /// The framing rule: grow by `padFraction` of the larger side on every edge, and never
        /// come out narrower than `minSpanM`.
        ///
        /// A fraction of the *larger* side rather than of each side on its own, so a turn
        /// sailed along one line does not get a fat margin across its width and a thin one
        /// along its length. The floor is what keeps a two-metre pivot from being magnified
        /// into a picture of GPS noise.
        public func padded(fraction: Double = TurnSlice.padFraction) -> Bounds {
            let pad = max(width, height, TurnSlice.minSpanM) * fraction
            return Bounds(minX: minX - pad, minY: minY - pad,
                          maxX: maxX + pad, maxY: maxY + pad)
        }

        static func around(_ points: [Point]) -> Bounds? {
            guard let first = points.first else { return nil }
            var out = Bounds(minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
            for point in points.dropFirst() {
                out.minX = min(out.minX, point.x)
                out.minY = min(out.minY, point.y)
                out.maxX = max(out.maxX, point.x)
                out.maxY = max(out.maxY, point.y)
            }
            return out
        }
    }

    /// The three speeds the strip marks, measured **on this window** rather than taken from
    /// the engine.
    ///
    /// They are not the same numbers as `TurnRecord.entryKn` / `minKn` and they must not
    /// pretend to be: the engine scores a turn on a smoothed maneuver channel over its own
    /// outcome window, and this is the recorded speed at three instants of a padded slice.
    /// The numbers row prints the engine's (they are the verdict); the strip's rule marks sit
    /// on the trace the strip is drawing, which is this one. Anything else puts a label at
    /// 11.4 kn on a line that is at 10.9 there.
    public struct SpeedMarks: Sendable, Equatable {
        /// The engine's entry speed — the **maximum** over the `entrySpeedWindowS` before
        /// the sweep starts, not the sample at `turn.ts`.
        public var entryKn: Double
        /// Where that maximum was read, in seconds from `turn.ts` (≤ 0): the sample inside
        /// the entry window whose speed is nearest `entryKn`. Until 6 Sep 2026 the "in"
        /// mark sat at 0 and floated above the line whenever the rider had already begun
        /// to slow before the heading started to move — which is most jibes.
        public var entryRt: Double = 0
        /// First moment after the sweep at which the speed is back to `recoverPct` of the
        /// entry speed — the engine's own "flying again" threshold — in seconds from
        /// `turn.ts`; nil when it never got there inside the drawn window. The sweep ends
        /// when the *heading* stops changing, which is often a second or two before the
        /// speed comes back, and the strip shades the two spans differently so the band's
        /// early end reads as what it is.
        public var recoverRt: Double? = nil
        /// The lowest speed inside the turn, and when it happened (seconds from `turn.ts`).
        public var minKn: Double
        public var minRt: Double
        /// Speed at `turn.endTs`.
        public var exitKn: Double
        /// `turn.endTs - turn.ts` — where the shaded in-turn band ends.
        public var exitRt: Double

        public init(entryKn: Double, minKn: Double, minRt: Double,
                    exitKn: Double, exitRt: Double) {
            self.entryKn = entryKn
            self.minKn = minKn
            self.minRt = minRt
            self.exitKn = exitKn
            self.exitRt = exitRt
        }
    }

    // MARK: - Constants

    /// A step shorter than this has no usable bearing — see `Point.headingDeg`.
    public static let minStepM = 0.5
    /// Framing margin, as a fraction of the drawn turn's larger side.
    public static let padFraction = 0.14
    /// No frame is ever narrower than this. A turn is tens of metres of water; a frame of
    /// five would be a picture of the receiver's own scatter.
    public static let minSpanM = 20.0
    /// Default lead-in / run-out either side of the turn, in seconds.
    public static let defaultPadS = 8.0

    // MARK: - Stored

    /// The turn this slice is of — carried so a view has one value to pass around.
    public let turn: TurnRecord
    /// Every vertex of the padded window, **north up**, in time order.
    public let points: [Point]
    /// The same vertices rotated so the wind blows from the top of the frame. nil when the
    /// session has no usable wind direction, which is exactly when the orientation control's
    /// second option is disabled.
    public let windUpPoints: [Point]?
    /// The wind direction the rotation used — degrees the wind blows **from**.
    public let windDirDeg: Double?
    /// Padded frames for the two orientations. `windUpBounds` is nil with `windUpPoints`.
    public let bounds: Bounds?
    public let windUpBounds: Bounds?
    public let speed: SpeedMarks
    /// Seconds from `turn.ts` at which the turn has swept **half** its total heading change —
    /// the downwind point of a jibe, head-to-wind on a tack.
    ///
    /// Measured as cumulative absolute heading change rather than from `turn.netDeg`, because
    /// the question the coach asks is "had he got round yet", and a sweep that overshoots and
    /// comes back has swept more than its net. nil when the window has too few usable bearings
    /// to say.
    public let midRotationRt: Double?
    /// Seconds of lead-in and run-out this slice was cut with.
    public let padS: Double

    /// Enough vertices to draw a line. A slice of a turn the GPS had no fix through still
    /// carries its numbers — the sheet is mostly numbers — and simply draws no map.
    public var hasGeometry: Bool { points.count >= 2 }

    /// `turn.endTs - turn.ts`, the shaded band's width.
    public var durationS: Double { max(turn.endTs - turn.ts, 0) }

    /// The strip's x domain: the whole padded window.
    public var timeDomain: ClosedRange<Double> { -padS ... max(durationS + padS, -padS + 1) }

    public func points(windUp: Bool) -> [Point] {
        windUp ? (windUpPoints ?? points) : points
    }

    public func bounds(windUp: Bool) -> Bounds? {
        windUp ? (windUpBounds ?? bounds) : bounds
    }

    // MARK: - Building

    /// Cuts `turn` out of `samples`.
    ///
    /// `samples` must be in time order and carry positions; the caller filters (see
    /// `SessionDetail.turnSamples`). The window is `[ts - padS, endTs + padS]`, which is what
    /// makes the picture readable: a jibe drawn from its first frame to its last is an arc
    /// with no approach and no exit, and the whole question the rider is asking is what the
    /// speed did on either side of it.
    ///
    /// The projection is equirectangular around the turn's **entry point** — not the window's
    /// centroid — so the entry sits at the origin. That is what lets a ghost turn be laid over
    /// this one by doing nothing at all: both are already anchored at their own entries.
    public static func make(samples: [Sample], turn: TurnRecord, windDirDeg: Double?,
                            padS: Double = defaultPadS) -> TurnSlice {
        let pad = max(padS, 0)
        let from = turn.ts - pad
        let to = turn.endTs + pad
        let window = samples.filter { $0.t >= from && $0.t <= to }

        // The anchor: the positioned sample nearest the turn's start. Without one there is no
        // frame to project into, and the slice degrades to numbers only.
        guard let anchor = nearest(window, t: turn.ts) ?? nearest(samples, t: turn.ts) else {
            return TurnSlice(turn: turn, points: [], windUpPoints: nil,
                             windDirDeg: windDirDeg, bounds: nil, windUpBounds: nil,
                             speed: marks(window, turn: turn), midRotationRt: nil, padS: pad)
        }
        let cosLat = cos(anchor.lat * .pi / 180)

        var points: [Point] = []
        points.reserveCapacity(window.count)
        for sample in window {
            points.append(Point(x: (sample.lon - anchor.lon) * cosLat * 111_320,
                                y: (sample.lat - anchor.lat) * 110_540,
                                rt: sample.t - turn.ts,
                                kn: sample.kn,
                                inTurn: sample.t >= turn.ts && sample.t <= turn.endTs))
        }
        applyHeadings(&points)

        let up = windDirDeg.map { rotated(points, windFromDeg: $0) }
        return TurnSlice(turn: turn,
                         points: points,
                         windUpPoints: up,
                         windDirDeg: windDirDeg,
                         bounds: Bounds.around(points)?.padded(),
                         windUpBounds: up.flatMap(Bounds.around)?.padded(),
                         speed: marks(window, turn: turn),
                         midRotationRt: midRotation(points),
                         padS: pad)
    }

    /// The bearing from each vertex to the next, written onto the vertex it leaves.
    ///
    /// The last vertex inherits the one before it rather than being left nil: it is the end of
    /// the run-out, and a tick that vanished at the edge of the frame would read as a gap in
    /// the recording.
    private static func applyHeadings(_ points: inout [Point]) {
        guard points.count >= 2 else { return }
        for index in 0..<(points.count - 1) {
            let dx = points[index + 1].x - points[index].x
            let dy = points[index + 1].y - points[index].y
            guard (dx * dx + dy * dy).squareRoot() >= minStepM else { continue }
            points[index].headingDeg = normalize(atan2(dx, dy) * 180 / .pi)
        }
        points[points.count - 1].headingDeg = points[points.count - 2].headingDeg
    }

    /// Rotates the frame so the direction the wind blows **from** points at the top.
    ///
    /// `windFromDeg` is a compass bearing, so the "from" direction is the unit vector
    /// `(sin W, cos W)`; the rotation below is the one that takes it to `(0, 1)`. A rider
    /// running downwind therefore travels toward the bottom of the frame, which is the whole
    /// point: on a wind-up jibe the track comes down the page, sweeps across, and goes back
    /// up, and the rider recognises the shape.
    ///
    /// Headings rotate with the points (`heading - W`), so a tick's arrow stays an arrow.
    public static func rotated(_ points: [Point], windFromDeg: Double) -> [Point] {
        let radians = windFromDeg * .pi / 180
        let (sinW, cosW) = (sin(radians), cos(radians))
        return points.map { point in
            var out = point
            out.x = point.x * cosW - point.y * sinW
            out.y = point.x * sinW + point.y * cosW
            out.headingDeg = point.headingDeg.map { normalize($0 - windFromDeg) }
            return out
        }
    }

    /// Speed at the entry, at the low point and at the exit — **the engine's own three
    /// numbers**, at the engine's own times.
    ///
    /// They used to be read off the window's samples, and the footnote promised they would
    /// differ from the numbers row "by a tenth". On Jan's phone they differed by 1.5 kn
    /// (6 Sep 2026): the strip was drawing the FIT's Doppler speed while the verdict was
    /// scored on the maneuver channel (`CleanSample.hybridMps`, position-derived because
    /// device Doppler is smoothed through a turn). One page, one channel: the caller now
    /// feeds the slice the maneuver channel (`SessionDetail.buildTurnSamples`), and the
    /// marks are `entryKn` / `minKn` at `minTs` / `exitKn` straight from the record, so
    /// they sit on the drawn line by construction and print the same digits as the row.
    private static func marks(_ window: [Sample], turn: TurnRecord) -> SpeedMarks {
        let duration = max(turn.endTs - turn.ts, 0)
        let minRt = min(max(turn.minTs - turn.ts, 0), duration)
        let config = TurnConfig()
        // The entry speed is the engine's maximum over the window *before* the sweep; put
        // the mark where that maximum sits on the drawn line.
        let entryWindow = window.filter {
            $0.t >= turn.ts - config.entrySpeedWindowS && $0.t <= turn.ts
        }
        let entryAt = entryWindow.min { abs($0.kn - turn.entryKn) < abs($1.kn - turn.entryKn) }
        // Recovery: the first sample after the sweep back at the engine's own threshold.
        let threshold = config.recoverPct / 100 * turn.entryKn
        let recoverAt = window.first { $0.t > turn.endTs && $0.kn >= threshold }
        var marks = SpeedMarks(entryKn: turn.entryKn,
                               minKn: turn.minKn,
                               minRt: minRt,
                               exitKn: turn.exitKn,
                               exitRt: duration)
        marks.entryRt = entryAt.map { $0.t - turn.ts } ?? 0
        marks.recoverRt = recoverAt.map { $0.t - turn.ts }
        return marks
    }

    /// Where the turn is halfway round, by cumulative heading change — see `midRotationRt`.
    private static func midRotation(_ points: [Point]) -> Double? {
        let arc = points.filter { $0.inTurn && $0.headingDeg != nil }
        guard arc.count >= 3 else { return nil }
        var steps: [(rt: Double, swept: Double)] = []
        var total = 0.0
        for index in 1..<arc.count {
            guard let previous = arc[index - 1].headingDeg,
                  let current = arc[index].headingDeg else { continue }
            total += abs(delta(from: previous, to: current))
            steps.append((rt: arc[index].rt, swept: total))
        }
        guard total > 0 else { return nil }
        return steps.first { $0.swept >= total / 2 }?.rt ?? steps.last?.rt
    }

    // MARK: - Ghost

    /// The session's best clean jibe of the same rotation — the dashed outline the sheet lays
    /// under the drawn turn.
    ///
    /// **The rule, and why each half of it.** Same session, because a comparison against an
    /// afternoon in different wind is not a comparison. Same `direction`, because a jibe spun
    /// to starboard and one spun to port are mirror images and laying one on the other would
    /// say the rider went the wrong way round. **Clean** (engine 0.12.0), because the model
    /// has to be a turn that worked — which since 0.12.0 means it flew through *and* held its
    /// speed, where before it only had to fly through. Highest `score`, because among the
    /// ones that worked that is the one he carried most speed through — the shape worth
    /// copying. And never the turn itself,
    /// which would draw a dashed line exactly under the solid one and read as a rendering bug.
    ///
    /// nil when the session has no other such jibe, which is common and not an error: the
    /// toggle simply says there is nothing to compare with.
    public static func ghost(for turn: TurnRecord, in turns: [TurnRecord],
                             samples: [Sample], windDirDeg: Double?,
                             padS: Double = defaultPadS) -> TurnSlice? {
        guard let best = bestClean(for: turn, in: turns) else { return nil }
        return make(samples: samples, turn: best, windDirDeg: windDirDeg, padS: padS)
    }

    /// The comparison turn itself, exposed for the tests and for a caller that wants to name
    /// it ("compared with your 14:31 jibe"). Ties go to the earlier turn, so the choice is a
    /// function of the session rather than of array order.
    public static func bestClean(for turn: TurnRecord, in turns: [TurnRecord]) -> TurnRecord? {
        turns
            .filter {
                $0.ts != turn.ts
                    && $0.clean
                    && $0.direction == turn.direction
            }
            .max { first, second in
                first.score == second.score ? first.ts > second.ts : first.score < second.score
            }
    }

    // MARK: - Helpers

    /// 0…360.
    public static func normalize(_ degrees: Double) -> Double {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// Signed shortest turn from one bearing to another, −180…180.
    public static func delta(from: Double, to: Double) -> Double {
        var d = (to - from).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    /// The sample closest in time to `t` (binary search over a sorted array).
    static func nearest(_ samples: [Sample], t: Double) -> Sample? {
        guard !samples.isEmpty else { return nil }
        var lo = 0, hi = samples.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if samples[mid].t <= t { lo = mid } else { hi = mid }
        }
        return abs(samples[lo].t - t) <= abs(samples[hi].t - t) ? samples[lo] : samples[hi]
    }

    /// The vertex nearest a relative time — what the strip's scrub drives the map's playhead
    /// dot through.
    public func point(atRelative rt: Double, windUp: Bool) -> Point? {
        let all = points(windUp: windUp)
        guard !all.isEmpty else { return nil }
        var best = all[0]
        var bestDelta = Double.infinity
        for point in all {
            let d = abs(point.rt - rt)
            if d < bestDelta {
                bestDelta = d
                best = point
            }
        }
        return best
    }

    /// A scale bar the frame has room for: 10 m, 25 m or 50 m, whichever is the largest that
    /// fits comfortably inside the drawn width — and 10 m as the floor, so there is always a
    /// bar rather than a frame with no scale on it at all.
    public static func scaleBarM(forSpanM span: Double) -> Double {
        for candidate in [50.0, 25.0, 10.0] where candidate <= span * 0.45 { return candidate }
        return 10
    }
}
