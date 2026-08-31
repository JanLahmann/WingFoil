import Foundation

/// A session reduced to what a list row can draw: a tiny aspect-correct outline of the
/// track (split into flying and off-foil runs), the handful of moments worth marking on it,
/// and a speed sparkline.
///
/// Building one means re-parsing the archived FIT, which is far too expensive to do while
/// a list scrolls — so this is a cache format, written next to the session's archive and
/// read back as a few kilobytes of JSON. It is versioned: a change to the geometry bumps
/// `currentVersion` and every stale thumbnail is silently rebuilt.
public struct TrackThumbnail: Codable, Sendable, Equatable {

    /// Rebuild everything cached before this. Bump on any change to the geometry below.
    ///
    /// v2 adds `marks`. A v1 blob has no such key and fails to decode outright, which
    /// reaches the same place the version check does — `thumbnail(for:)` returns nil and
    /// the thumbnail is rebuilt — but the bump is what *documents* it.
    public static let currentVersion = 2

    /// A track vertex in a unit box: x/y in 0…1, y already pointing **down** so the value
    /// can be multiplied straight into a view rectangle. Aspect ratio is preserved (the
    /// shorter axis is centred), so a long reach does not get stretched into a blob.
    public struct Point: Codable, Sendable, Equatable {
        public var x: Double
        public var y: Double
        /// The rider was on the foil arriving at this vertex.
        public var flying: Bool

        public init(x: Double, y: Double, flying: Bool) {
            self.x = x
            self.y = y
            self.flying = flying
        }
    }

    /// A moment worth a dot on the outline, in the same unit box as `Point`.
    ///
    /// Three semantics and no more (docs/presentation.md): where the maneuvers went, and
    /// where the wrist went under. A thumbnail is not a map — there is no room here for
    /// takeoffs, pumping spans, chevrons or record windows, and a card carrying all eleven
    /// map layers at 1080 px would be confetti. What survives the shrink is the verdict
    /// ladder plus the swim evidence, because those are the two things the card's own
    /// numbers (the tally, and WPH) are about.
    public struct Mark: Codable, Sendable, Equatable {

        /// Deliberately the ladder's three rungs plus the one effort-layer event that is
        /// not a verdict. Raw values match `MapLayer` where they overlap, so a reader of
        /// the JSON does not have to hold two vocabularies.
        public enum Kind: String, Codable, Sendable, CaseIterable {
            /// carried the maneuver on the foil
            case flewThrough
            /// lost it briefly
            case touchdown
            /// swam out of it
            case fellIn
            /// the barometer saw the wrist go under — evidence, not a verdict
            case splash
        }

        public var x: Double
        public var y: Double
        public var kind: Kind

        public init(x: Double, y: Double, kind: Kind) {
            self.x = x
            self.y = y
            self.kind = kind
        }
    }

    /// One moment on the session clock, before it has been given a position. What callers
    /// hand `make` — they know *when* something happened; only the thumbnail knows where
    /// that lands in its own box.
    public struct Event: Sendable, Equatable {
        public var t: Double
        public var kind: Mark.Kind

        public init(t: Double, kind: Mark.Kind) {
            self.t = t
            self.kind = kind
        }
    }

    public var version: Int
    public var points: [Point]
    /// Maneuver outcomes and splashes, in time order. Empty on a thumbnail built without
    /// an analysis, which is a fact about the source rather than a claim that nothing
    /// happened — the list row does not draw them anyway.
    public var marks: [Mark]
    /// Speed over time, normalized to 0…1 of `maxKn`, evenly spaced across the session.
    public var speed: [Double]
    public var maxKn: Double

    public init(version: Int = TrackThumbnail.currentVersion, points: [Point],
                marks: [Mark] = [], speed: [Double], maxKn: Double) {
        self.version = version
        self.points = points
        self.marks = marks
        self.speed = speed
        self.maxKn = maxKn
    }

    public var isEmpty: Bool { points.count < 2 && speed.isEmpty }
    public var isStale: Bool { version != Self.currentVersion }

    /// The sub-rectangle of the unit box the drawn session actually occupies — the
    /// polyline **and** its marks.
    ///
    /// The projection preserves aspect by centring the shorter axis in a *square*, so a
    /// session sailed up and down one reach fills the full width and about a third of the
    /// height — and a renderer that inscribes the whole unit square into its view then
    /// wastes the view's width as well, twice over. This is what lets a drawing layer fit
    /// the track itself instead of the box it was normalized into
    /// (`TrackOutlineView.fillsBox`). nil when there is nothing to fit.
    ///
    /// The marks count because a mark is placed from the sample nearest its instant, which
    /// the thinning may have dropped from the polyline — so a turn at the far end of a reach
    /// can sit a hair outside the vertices, and a fit that ignored it would clip the dot
    /// against the edge of an exported image.
    public var contentBox: (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        guard let first = points.first else { return nil }
        var box = (minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
        func absorb(_ x: Double, _ y: Double) {
            box.minX = min(box.minX, x)
            box.minY = min(box.minY, y)
            box.maxX = max(box.maxX, x)
            box.maxY = max(box.maxY, y)
        }
        for point in points.dropFirst() { absorb(point.x, point.y) }
        for mark in marks { absorb(mark.x, mark.y) }
        return box
    }

    /// Contiguous runs of vertices sharing a phase, so a drawing layer can stroke each run
    /// once instead of one segment at a time. Consecutive runs share a vertex, so the
    /// polyline has no visual gap where the phase changes.
    public var runs: [(flying: Bool, points: [Point])] {
        guard points.count >= 2 else { return [] }
        var out: [(flying: Bool, points: [Point])] = []
        var current: [Point] = [points[0]]
        var flying = points[1].flying
        for point in points.dropFirst() {
            if point.flying != flying {
                current.append(point)
                if current.count >= 2 { out.append((flying, current)) }
                current = [point]
                flying = point.flying
            } else {
                current.append(point)
            }
        }
        if current.count >= 2 { out.append((flying, current)) }
        return out
    }

    // MARK: - Building

    /// Track vertices kept: enough for a recognisable outline at thumbnail size, few
    /// enough that a hundred cached sessions stay well under a megabyte.
    public static let maxPoints = 180
    /// Sparkline buckets. Bucketed by **max**, so a peak survives the thinning — a
    /// sparkline that averages the session away is worse than no sparkline.
    public static let sparklineBuckets = 48

    /// Builds a thumbnail from a parsed track, the flights the engine found, and the
    /// moments worth marking on it (`events(_:)`).
    ///
    /// Every half degrades independently: a session with no positions still gets its
    /// sparkline, a session with no speed channel still gets its outline, and a session
    /// with no analysis yet gets both and no marks.
    public static func make(track: RawTrack, flights: [FlightRecord],
                            events: [Event] = []) -> TrackThumbnail {
        let sorted = flights.sorted { $0.startTs < $1.startTs }
        let isFlying = flyingLookup(sorted)
        let positioned = track.samples.filter { $0.lat != nil && $0.lon != nil }
        let kept = thin(positioned, isFlying: isFlying)
        let projection = Projection(kept.map { (lat: $0.lat, lon: $0.lon) })
        let (speed, maxKn) = sparkline(track.samples)
        return TrackThumbnail(points: outline(coordinates: kept),
                              marks: marks(events, on: positioned, in: projection),
                              speed: speed, maxKn: maxKn)
    }

    /// The moments a thumbnail marks, straight off the shared presentation rules: every
    /// *counted* turn on the verdict ladder, plus the submersion evidence on both of its
    /// channels. An uncounted turn is a bear-away or a round-up — a course change, never a
    /// verdict — and gets no dot, exactly as on the map.
    public static func events(_ analysis: SessionAnalysis) -> [Event] {
        var out: [Event] = []
        for turn in analysis.turns where turn.counted {
            let kind: Mark.Kind
            switch PresentationRules.layer(for: turn) {
            case .fellIn: kind = .fellIn
            case .touchdown: kind = .touchdown
            default: kind = .flewThrough
            }
            out.append(Event(t: turn.ts, kind: kind))
        }
        for turn in PresentationRules.splashTurns(analysis) {
            out.append(Event(t: turn.ts, kind: .splash))
        }
        for end in PresentationRules.splashEnds(analysis) {
            out.append(Event(t: end.ts, kind: .splash))
        }
        return out.sorted { $0.t < $1.t }
    }

    /// Binary search over the (sorted, non-overlapping) flights.
    static func flyingLookup(_ flights: [FlightRecord]) -> (Double) -> Bool {
        { t in
            var lo = 0, hi = flights.count - 1
            while lo <= hi {
                let mid = (lo + hi) / 2
                if t < flights[mid].startTs { hi = mid - 1 }
                else if t > flights[mid].endTs { lo = mid + 1 }
                else { return true }
            }
            return false
        }
    }

    /// Drops the polyline to `maxPoints`, keeping every phase change and the last vertex.
    static func thin(_ positioned: [RecordSample],
                     isFlying: (Double) -> Bool) -> [(lat: Double, lon: Double, flying: Bool)] {
        guard positioned.count >= 2 else { return [] }

        // Ceiling division: `count / maxPoints` would round *down* and keep up to twice
        // the budget (400 samples ÷ 180 = stride 2 ⇒ 200 vertices).
        let stride = max(1, (positioned.count + maxPoints - 1) / maxPoints)
        var kept: [(lat: Double, lon: Double, flying: Bool)] = []
        kept.reserveCapacity(min(positioned.count, maxPoints) + 2)
        for (index, sample) in positioned.enumerated() {
            let flying = isFlying(sample.t)
            let phaseChange = kept.last.map { $0.flying != flying } ?? true
            guard index % stride == 0 || index == positioned.count - 1 || phaseChange else {
                continue
            }
            kept.append((sample.lat!, sample.lon!, flying))
        }
        return kept
    }

    /// The equirectangular projection the outline is normalized through, as a value.
    ///
    /// It is a *type* rather than four lines inside `outline` because a mark has to land in
    /// the same unit box as the vertex it sits on. Re-deriving the centroid and the span
    /// from a different set of coordinates — the events rather than the track, say — would
    /// put every dot somewhere plausible and wrong, which is the kind of bug a card ships
    /// with because nobody can check a jibe's position by eye.
    public struct Projection: Sendable, Equatable {
        let lon0: Double
        let cosLat0: Double
        let lat0: Double
        let minX: Double
        let minY: Double
        let span: Double
        let offsetX: Double
        let offsetY: Double

        /// nil for fewer than two coordinates — there is no box to normalize into.
        public init?(_ coordinates: [(lat: Double, lon: Double)]) {
            guard coordinates.count >= 2 else { return nil }

            // Same equirectangular projection the analysis engine uses (CleanTrack), around
            // the track centroid — at session scale it is exact enough that the outline is
            // indistinguishable from the map's.
            let centreLat = coordinates.reduce(0.0) { $0 + $1.lat } / Double(coordinates.count)
            let centreLon = coordinates.reduce(0.0) { $0 + $1.lon } / Double(coordinates.count)
            let cosCentre = cos(centreLat * .pi / 180)
            lat0 = centreLat
            lon0 = centreLon
            cosLat0 = cosCentre
            let raw = coordinates.map { point in
                (x: (point.lon - centreLon) * cosCentre * 111_320,
                 y: (point.lat - centreLat) * 110_540)
            }
            let maxX = raw.map(\.x).max()!, maxY = raw.map(\.y).max()!
            minX = raw.map(\.x).min()!
            minY = raw.map(\.y).min()!
            // One scale for both axes keeps the shape honest; the shorter axis is centred.
            // A degenerate track (a straight line, or a rider who never moved) would divide
            // by zero, so the span has a floor.
            span = max(maxX - minX, maxY - minY, 1)
            offsetX = (span - (maxX - minX)) / 2
            offsetY = (span - (maxY - minY)) / 2
        }

        /// One coordinate in the unit box. Not clamped: a mark whose nearest positioned
        /// sample sits outside the thinned polyline's own extent would be moved by a clamp,
        /// and a dot in the wrong place is worse than a dot a hair outside the frame.
        public func place(lat: Double, lon: Double) -> (x: Double, y: Double) {
            let x = (lon - lon0) * cosLat0 * 111_320
            let y = (lat - lat0) * 110_540
            return (x: (x - minX + offsetX) / span,
                    // Screen y grows downward, the projection's grows north.
                    y: 1 - (y - minY + offsetY) / span)
        }
    }

    /// Projects and normalizes an already-thinned polyline.
    ///
    /// Exposed because the share card draws the *same* outline from geometry the detail
    /// screen already has in memory — there must be exactly one definition of what a
    /// CleanJibe track outline looks like, or the card and the list row would disagree
    /// about the same session.
    public static func outline(
        coordinates: [(lat: Double, lon: Double, flying: Bool)]) -> [Point] {
        guard let projection = Projection(coordinates.map { (lat: $0.lat, lon: $0.lon) })
        else { return [] }
        return coordinates.map { point in
            let placed = projection.place(lat: point.lat, lon: point.lon)
            return Point(x: placed.x, y: placed.y, flying: point.flying)
        }
    }

    /// Gives a list of moments their positions, through the outline's own projection.
    ///
    /// An event whose instant has no positioned sample anywhere near it is dropped rather
    /// than nailed to the nearest fix the recording happens to have: a card is looked at,
    /// not queried, so a dot in the wrong bay cannot be corrected by tapping it.
    public static func marks(_ events: [Event], on positioned: [RecordSample],
                             in projection: Projection?) -> [Mark] {
        guard let projection, !positioned.isEmpty else { return [] }
        return events.compactMap { event in
            guard let sample = nearest(positioned, t: event.t),
                  let lat = sample.lat, let lon = sample.lon,
                  abs(sample.t - event.t) <= maxMarkGapS else { return nil }
            let placed = projection.place(lat: lat, lon: lon)
            return Mark(x: placed.x, y: placed.y, kind: event.kind)
        }
    }

    /// Positions from further than this off the event's own instant are not that event's.
    /// Half a minute of drifting with the GPS off is a different place on the water.
    static let maxMarkGapS: Double = 30

    /// The positioned sample closest in time to `t` (binary search over a sorted array).
    static func nearest(_ samples: [RecordSample], t: Double) -> RecordSample? {
        guard !samples.isEmpty else { return nil }
        var lo = 0, hi = samples.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if samples[mid].t <= t { lo = mid } else { hi = mid }
        }
        return abs(samples[lo].t - t) <= abs(samples[hi].t - t) ? samples[lo] : samples[hi]
    }

    static func sparkline(_ samples: [RecordSample]) -> (values: [Double], maxKn: Double) {
        let usable = samples.filter { $0.speedMps != nil }
        guard let first = usable.first, let last = usable.last, last.t > first.t else {
            return ([], 0)
        }
        let span = last.t - first.t
        let buckets = min(sparklineBuckets, max(1, usable.count))
        let width = span / Double(buckets)
        guard width > 0 else { return ([], 0) }

        var peaks = [Double](repeating: 0, count: buckets)
        for sample in usable {
            let index = min(buckets - 1, Int((sample.t - first.t) / width))
            peaks[index] = max(peaks[index], (sample.speedMps ?? 0) * Units.mpsToKn)
        }
        let maxKn = peaks.max() ?? 0
        guard maxKn > 0 else { return (peaks.map { _ in 0 }, 0) }
        return (peaks.map { $0 / maxKn }, maxKn)
    }
}

// MARK: - Cache

extension SessionArchive {

    public func thumbnailURL(for id: String) -> URL {
        directory(for: id).appendingPathComponent("thumbnail.json")
    }

    /// The cached thumbnail, or nil when absent, unreadable or built by an older version.
    public func thumbnail(for id: String) -> TrackThumbnail? {
        guard let data = try? Data(contentsOf: thumbnailURL(for: id)),
              let decoded = try? JSONDecoder().decode(TrackThumbnail.self, from: data),
              !decoded.isStale else { return nil }
        return decoded
    }

    public func writeThumbnail(_ thumbnail: TrackThumbnail, id: String) throws {
        try FileManager.default.createDirectory(at: directory(for: id),
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(thumbnail).write(to: thumbnailURL(for: id), options: .atomic)
    }

    public func dropThumbnail(for id: String) {
        try? FileManager.default.removeItem(at: thumbnailURL(for: id))
    }
}
