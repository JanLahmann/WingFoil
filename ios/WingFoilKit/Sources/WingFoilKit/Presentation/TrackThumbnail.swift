import Foundation

/// A session reduced to what a list row can draw: a tiny aspect-correct outline of the
/// track (split into flying and off-foil runs) and a speed sparkline.
///
/// Building one means re-parsing the archived FIT, which is far too expensive to do while
/// a list scrolls — so this is a cache format, written next to the session's archive and
/// read back as a few kilobytes of JSON. It is versioned: a change to the geometry bumps
/// `currentVersion` and every stale thumbnail is silently rebuilt.
public struct TrackThumbnail: Codable, Sendable, Equatable {

    /// Rebuild everything cached before this. Bump on any change to the geometry below.
    public static let currentVersion = 1

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

    public var version: Int
    public var points: [Point]
    /// Speed over time, normalized to 0…1 of `maxKn`, evenly spaced across the session.
    public var speed: [Double]
    public var maxKn: Double

    public init(version: Int = TrackThumbnail.currentVersion, points: [Point],
                speed: [Double], maxKn: Double) {
        self.version = version
        self.points = points
        self.speed = speed
        self.maxKn = maxKn
    }

    public var isEmpty: Bool { points.count < 2 && speed.isEmpty }
    public var isStale: Bool { version != Self.currentVersion }

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

    /// Builds a thumbnail from a parsed track and the flights the engine found.
    ///
    /// Both halves degrade independently: a session with no positions still gets its
    /// sparkline, and a session with no speed channel still gets its outline.
    public static func make(track: RawTrack, flights: [FlightRecord]) -> TrackThumbnail {
        let sorted = flights.sorted { $0.startTs < $1.startTs }
        let isFlying = flyingLookup(sorted)
        let points = outline(track.samples, isFlying: isFlying)
        let (speed, maxKn) = sparkline(track.samples)
        return TrackThumbnail(points: points, speed: speed, maxKn: maxKn)
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

    static func outline(_ samples: [RecordSample],
                        isFlying: (Double) -> Bool) -> [Point] {
        let positioned = samples.filter { $0.lat != nil && $0.lon != nil }
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
        return outline(coordinates: kept)
    }

    /// Projects and normalizes an already-thinned polyline.
    ///
    /// Exposed because the share card draws the *same* outline from geometry the detail
    /// screen already has in memory — there must be exactly one definition of what a
    /// WingFoil track outline looks like, or the card and the list row would disagree
    /// about the same session.
    public static func outline(
        coordinates: [(lat: Double, lon: Double, flying: Bool)]) -> [Point] {
        guard coordinates.count >= 2 else { return [] }

        // Same equirectangular projection the analysis engine uses (CleanTrack), around
        // the track centroid — at session scale it is exact enough that the outline is
        // indistinguishable from the map's.
        let lat0 = coordinates.reduce(0.0) { $0 + $1.lat } / Double(coordinates.count)
        let lon0 = coordinates.reduce(0.0) { $0 + $1.lon } / Double(coordinates.count)
        let cosLat0 = cos(lat0 * .pi / 180)
        let raw = coordinates.map { point in
            (x: (point.lon - lon0) * cosLat0 * 111_320,
             y: (point.lat - lat0) * 110_540,
             flying: point.flying)
        }

        let minX = raw.map(\.x).min()!, maxX = raw.map(\.x).max()!
        let minY = raw.map(\.y).min()!, maxY = raw.map(\.y).max()!
        // One scale for both axes keeps the shape honest; the shorter axis is centred.
        // A degenerate track (a straight line, or a rider who never moved) would divide
        // by zero, so the span has a floor.
        let span = max(maxX - minX, maxY - minY, 1)
        let offsetX = (span - (maxX - minX)) / 2
        let offsetY = (span - (maxY - minY)) / 2
        return raw.map { point in
            Point(x: (point.x - minX + offsetX) / span,
                  // Screen y grows downward, the projection's grows north.
                  y: 1 - (point.y - minY + offsetY) / span,
                  flying: point.flying)
        }
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
