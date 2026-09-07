import Foundation

/// **The drawing's whole input, and nothing else.**
///
/// A turn and a straight-line flight end are different events with different verdicts, but
/// the picture a rider wants of them is the same picture: a track in local metres, north up
/// or wind up, ticked by the second, with a ring where the speed bottomed out and a dot
/// inked by how it ended. Until this type existed only `TurnSlice` could be drawn, and the
/// flight-end page would have meant a second four-hundred-line `Canvas` that drifted from
/// the first the day either was touched.
///
/// So the geometry moved here and both slices expose one (`TurnSlice.figure`,
/// `FlightEndSlice.figure`). The renderer takes a figure and knows nothing about which kind
/// of event it came from — which is also what keeps the two pages honestly identical rather
/// than accidentally similar.
///
/// **What it deliberately does not carry.** No score, no chips, no coach line, no window
/// bands: those differ between the two events and belong to their own slices. A figure is
/// the *shape*, plus the four marks that are drawn on the shape.
public struct ManeuverFigure: Sendable, Equatable {

    /// Every vertex of the padded window, **north up**, in time order.
    public var points: [TurnSlice.Point]
    /// The same vertices rotated so the wind blows from the top; nil without a usable wind.
    public var windUpPoints: [TurnSlice.Point]?
    public var bounds: TurnSlice.Bounds?
    public var windUpBounds: TurnSlice.Bounds?
    /// Degrees the wind blows **from**, or nil — the gate on wind up and on TWA everywhere.
    public var windDirDeg: Double?

    /// The speed ramp's anchor: the entry speed the line is coloured against.
    public var entryKn: Double
    /// Where the hollow ring goes — the low point — in seconds from `t = 0`. nil ⇒ no ring.
    public var lowRt: Double?
    /// Where the filled outcome dot goes. On a turn that is the end of the sweep; on a
    /// flight end it is the end itself, which is `0`.
    public var endRt: Double?
    /// The engine's outcome word, which inks the dot. Never re-derived here.
    public var outcome: String
    /// The wind-axis crossing, in seconds from `t = 0`; nil where none was recorded — and
    /// always nil on a flight end, which is not a maneuver and crosses nothing.
    public var axisRt: Double?

    /// The drawn window, on the event's own clock.
    public var timeDomain: ClosedRange<Double>
    /// The length of the thing itself: the sweep on a turn, `0` on a flight end.
    public var durationS: Double
    /// "Jibe", "Flight end" — what the spoken label calls it.
    public var title: String

    public init(points: [TurnSlice.Point], windUpPoints: [TurnSlice.Point]?,
                bounds: TurnSlice.Bounds?, windUpBounds: TurnSlice.Bounds?,
                windDirDeg: Double?, entryKn: Double, lowRt: Double?, endRt: Double?,
                outcome: String, axisRt: Double?, timeDomain: ClosedRange<Double>,
                durationS: Double, title: String) {
        self.points = points
        self.windUpPoints = windUpPoints
        self.bounds = bounds
        self.windUpBounds = windUpBounds
        self.windDirDeg = windDirDeg
        self.entryKn = entryKn
        self.lowRt = lowRt
        self.endRt = endRt
        self.outcome = outcome
        self.axisRt = axisRt
        self.timeDomain = timeDomain
        self.durationS = durationS
        self.title = title
    }

    /// Enough vertices to draw a line. A window the GPS had no fix through still carries its
    /// numbers — both pages are mostly numbers — and simply draws no map.
    public var hasGeometry: Bool { points.count >= 2 }

    public func points(windUp: Bool) -> [TurnSlice.Point] {
        windUp ? (windUpPoints ?? points) : points
    }

    public func bounds(windUp: Bool) -> TurnSlice.Bounds? {
        windUp ? (windUpBounds ?? bounds) : bounds
    }

    /// The vertex nearest a relative time — what the strip's scrub drives the playhead dot
    /// through.
    public func point(atRelative rt: Double, windUp: Bool) -> TurnSlice.Point? {
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

    /// **The vertex nearest a point on the water** — what a tap on the drawing picks.
    ///
    /// Nearest *vertex*, not nearest point on the polyline: the callout names one recorded
    /// sample and reads its speed and its heading, and interpolating a position between two
    /// samples would put a real-looking time on a reading nobody took. `x` and `y` are metres
    /// in the same frame the caller drew — so a caller working in the wind-up frame must ask
    /// with `windUp: true`, or it will pick the vertex the rotation happens to have left
    /// there.
    ///
    /// `withinM` is the tap tolerance in metres, and it is the caller's because the caller
    /// knows the scale: at 40 m across a phone-width canvas, a fingertip is about 6 m of
    /// water. nil when nothing is close enough, which is what makes a tap on empty water
    /// dismiss the callout rather than snap to the far end of the track.
    public func point(nearX x: Double, y: Double, windUp: Bool,
                      withinM: Double = .infinity) -> TurnSlice.Point? {
        var best: TurnSlice.Point?
        var bestSq = withinM * withinM
        for point in points(windUp: windUp) {
            let dx = point.x - x
            let dy = point.y - y
            let sq = dx * dx + dy * dy
            if sq <= bestSq {
                bestSq = sq
                best = point
            }
        }
        return best
    }

    /// **The label ticks along the path**: the whole seconds a "5", a "10" should be printed
    /// at, and the vertex each one belongs to.
    ///
    /// Every `everyS` seconds of the event's own clock, negative side included — the lead-in
    /// is where a jibe's approach is, and a rider counting down to the turn wants `−5` as
    /// much as `+5`. Zero is skipped: the sweep's start is already the origin of every other
    /// mark on the page, and a "0" beside it would be the fourth thing saying so.
    ///
    /// The vertex is the nearest one in time rather than an interpolation, for the same
    /// reason `point(nearX:y:)` is: the label sits on a sample that exists.
    public func pathLabels(everyS: Double = 5, windUp: Bool) -> [(rt: Double, at: TurnSlice.Point)] {
        guard everyS > 0, hasGeometry else { return [] }
        let all = points(windUp: windUp)
        guard let first = all.first?.rt, let last = all.last?.rt, last > first else { return [] }
        var out: [(rt: Double, at: TurnSlice.Point)] = []
        var rt = (first / everyS).rounded(.up) * everyS
        while rt <= last {
            defer { rt += everyS }
            guard abs(rt) > 0.001 else { continue }
            guard let at = point(atRelative: rt, windUp: windUp),
                  abs(at.rt - rt) <= everyS / 2 else { continue }
            out.append((rt: rt, at: at))
        }
        return out
    }
}
