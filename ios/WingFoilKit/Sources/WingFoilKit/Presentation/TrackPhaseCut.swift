import Foundation

/// The track split into runs of one phase each, cut at the engine's exact flight
/// boundaries (docs/presentation.md, "Phase tints").
///
/// The obvious spelling — walk the samples, ask "is this fix inside a flight?", start a new
/// run whenever the answer changes — is wrong on a coarse source, and wrong in the direction
/// that flatters the rider. The 2026-08-06 "Wingfoiling"-app session records at 2 s with a
/// 5 s p95, and 24 of its 54 flight boundaries have an off-foil span of 5–7 s containing no
/// positioned sample at all: the fix before the landing is inside flight *n*, the fix after
/// the next takeoff is inside flight *n+1*, the answer never changes, and two flights tint
/// as one continuous flight with a takeoff arrow apparently mid-flight. It is not a rare
/// shape either — every 0.5 Hz native fixture in the corpus has it, up to 74 boundaries in
/// one session.
///
/// So the cut is made at the boundary *time*, not at a sample: the coordinate is
/// interpolated between the two positioned samples that straddle it, which puts the cut
/// point exactly on the line the map already draws between those two fixes. The colour
/// changes; the geometry does not. Consecutive runs share that vertex, so the drawn track
/// has no hole at a phase change, and an off-foil span with nothing recorded inside it still
/// renders as a short grey stub.
public enum TrackPhaseCut {

    /// One positioned sample: a session time and where the rider was.
    ///
    /// `segment` is the recording-continuity id — a change between neighbours is a gap the
    /// line breaks at. A source that carries no gap information passes the same id
    /// throughout, which is the same as saying "one unbroken recording".
    public struct Point: Sendable, Equatable {
        public var t: Double
        public var lat: Double
        public var lon: Double
        public var segment: Int

        public init(t: Double, lat: Double, lon: Double, segment: Int = 0) {
            self.t = t
            self.lat = lat
            self.lon = lon
            self.segment = segment
        }
    }

    /// A flight, as the engine reported it: `[start, end]` on the session clock.
    public struct Span: Sendable, Equatable {
        public var start: Double
        public var end: Double

        public init(start: Double, end: Double) {
            self.start = start
            self.end = end
        }
    }

    /// A stretch of track drawn with one phase tint.
    public struct Run: Sendable, Equatable {
        public var flying: Bool
        public var points: [Point]

        public init(flying: Bool, points: [Point]) {
            self.flying = flying
            self.points = points
        }
    }

    /// The runs to draw, in time order.
    ///
    /// - Parameters:
    ///   - points: positioned samples, ascending in `t`.
    ///   - flights: the engine's flight spans, ascending and non-overlapping.
    ///   - keepEvery: decimation stride for the *interior* of a run. Boundary cuts are never
    ///     decimated away — the whole point of them is that they land where no sample does —
    ///     and the interpolation always uses the two true neighbours, so thinning the drawn
    ///     line cannot move a cut.
    public static func runs(_ points: [Point], flights: [Span],
                            keepEvery stride: Int = 1) -> [Run] {
        guard !points.isEmpty else { return [] }
        let step = max(1, stride)
        let cuts = boundaries(flights)

        var out: [Run] = []
        var current: [Point] = []
        var flying = isFlying(points[0].t, flights)
        var next = 0                                    // the next unconsumed cut

        func flush() {
            if current.count >= 2 { out.append(Run(flying: flying, points: current)) }
            current.removeAll(keepingCapacity: true)
        }

        // Cuts before the first fix change nothing that can be drawn, but they do decide
        // which phase the first run starts in.
        while next < cuts.count, cuts[next].t <= points[0].t {
            flying = cuts[next].flyingAfter
            next += 1
        }
        current.append(points[0])

        for index in 1..<points.count {
            let previous = points[index - 1], sample = points[index]
            // Every boundary the recording stepped over between these two fixes, in order:
            // a flight shorter than one sample interval contributes both of its own.
            var cutHere = false
            while next < cuts.count, cuts[next].t <= sample.t {
                let cut = cuts[next]
                current.append(interpolate(previous, sample, at: cut.t))
                flush()
                flying = cut.flyingAfter
                current.append(interpolate(previous, sample, at: cut.t))
                next += 1
                cutHere = true
            }
            // A recording gap breaks the line — except across a cut, where these two fixes
            // are the only evidence there is of where the phase changed, and a hole would
            // read as the flight simply carrying on.
            if !cutHere, sample.segment != previous.segment {
                flush()
                current.append(sample)
                continue
            }
            // A boundary that landed exactly *on* this fix has already contributed it (as
            // the shared vertex), so adding it again would be a duplicate point.
            guard current.last?.t != sample.t else { continue }
            if index % step == 0 || index == points.count - 1 || cutHere {
                current.append(sample)
            }
        }
        flush()
        return out
    }

    /// Whether a time is inside any flight. Binary search: the flights are ascending.
    public static func isFlying(_ t: Double, _ flights: [Span]) -> Bool {
        var lo = 0, hi = flights.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if t < flights[mid].start { hi = mid - 1 }
            else if t > flights[mid].end { lo = mid + 1 }
            else { return true }
        }
        return false
    }

    // MARK: - Internals

    /// One phase change: when it happens, and what the track is doing just after it.
    struct Cut: Equatable {
        var t: Double
        var flyingAfter: Bool
    }

    /// The flight edges as cuts, in time order. A flight's `start` turns the tint on and its
    /// `end` turns it off; a zero-length flight contributes both, in that order, and draws a
    /// (degenerate but honest) two-point run.
    static func boundaries(_ flights: [Span]) -> [Cut] {
        var out: [Cut] = []
        out.reserveCapacity(flights.count * 2)
        for flight in flights.sorted(by: { $0.start < $1.start }) {
            out.append(Cut(t: flight.start, flyingAfter: true))
            out.append(Cut(t: flight.end, flyingAfter: false))
        }
        return out
    }

    /// The coordinate at `t`, linearly between two fixes. Pure geometry over the line the
    /// map already draws between them — never reported as a measurement.
    static func interpolate(_ a: Point, _ b: Point, at t: Double) -> Point {
        let span = b.t - a.t
        guard span > 0 else { return Point(t: t, lat: b.lat, lon: b.lon, segment: b.segment) }
        let f = min(max((t - a.t) / span, 0), 1)
        return Point(t: t, lat: a.lat + (b.lat - a.lat) * f, lon: a.lon + (b.lon - a.lon) * f,
                     segment: b.segment)
    }
}
