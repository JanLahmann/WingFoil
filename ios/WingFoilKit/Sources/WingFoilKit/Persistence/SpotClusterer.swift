import Foundation
import GRDB

/// Groups sessions into places by their start coordinate.
///
/// Deliberately the simplest thing that survives real data: single-link greedy assignment
/// with a fixed radius. A rig-up beach is tens of metres across and the next spot is
/// kilometres away, so there is no cluster-count parameter to get wrong — Jan's corpus
/// splits cleanly into Nago-Torbole and Rheinstetten at any radius between ~100 m and
/// ~10 km. The centroid is refined incrementally as sessions join, which keeps the
/// result independent of import order for well-separated spots.
public enum SpotClusterer {

    /// Cluster radius, plan §3.3 ("~500 m").
    public static let defaultRadiusM: Double = 500
    static let earthRadiusM: Double = 6_371_000

    // MARK: - Placeholder names

    /// The name a brand-new spot wears until something better arrives — `"Spot 3"`.
    ///
    /// It exists in one place, with `isPlaceholderName` beside it, because three separate
    /// decisions turn on "is this still a placeholder?": whether the reverse geocoder is
    /// asked about this spot at all, whether "Look up names again" is worth offering, and
    /// whether a re-cluster may carry the name across to a new centroid. Spelling the
    /// pattern three times is how a geocoded spot ends up asked again every launch.
    public static func placeholderName(_ number: Int) -> String { "Spot \(number)" }

    /// Is this name one nobody chose — the mint-fresh `"Spot N"` and nothing else?
    ///
    /// A geocoded name ("Nago-Torbole") is **not** a placeholder even though the spot is
    /// still `autoNamed`: `autoNamed` means "the rider has not renamed it", which is a
    /// different fact and the one a rename has to be able to win against.
    public static func isPlaceholderName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("Spot ") else { return false }
        let tail = trimmed.dropFirst("Spot ".count)
        return !tail.isEmpty && tail.allSatisfy(\.isNumber)
    }

    /// The next free placeholder number: one past the highest already in the table, never
    /// `COUNT(*) + 1`.
    ///
    /// `COUNT(*) + 1` mints a second "Spot 2" in a library where a spot was renamed and
    /// another removed, and two spots with one name is a row a rider cannot tell apart from
    /// itself. Renamed and geocoded spots are simply not in the running.
    static func nextPlaceholderNumber(_ spots: [SpotRow]) -> Int {
        let used = spots.compactMap { spot -> Int? in
            guard isPlaceholderName(spot.name) else { return nil }
            return Int(spot.name.trimmingCharacters(in: .whitespaces).dropFirst("Spot ".count))
        }
        return (used.max() ?? spots.count) + 1
    }

    /// Great-circle distance in metres.
    public static func distance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let φ1 = lat1 * .pi / 180, φ2 = lat2 * .pi / 180
        let dφ = (lat2 - lat1) * .pi / 180
        let dλ = (lon2 - lon1) * .pi / 180
        let a = sin(dφ / 2) * sin(dφ / 2) + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
        return 2 * earthRadiusM * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }

    /// A session's location as the clusterer sees it.
    public struct Fix: Sendable, Equatable {
        public var sessionId: String
        public var lat: Double
        public var lon: Double

        public init(sessionId: String, lat: Double, lon: Double) {
            self.sessionId = sessionId
            self.lat = lat
            self.lon = lon
        }
    }

    public struct Cluster: Sendable, Equatable {
        public var lat: Double
        public var lon: Double
        public var sessionIds: [String]

        public init(lat: Double, lon: Double, sessionIds: [String]) {
            self.lat = lat
            self.lon = lon
            self.sessionIds = sessionIds
        }
    }

    /// Pure clustering, used by the batch re-cluster and by the tests. Fixes join the
    /// nearest cluster whose centroid is within `radiusM`, otherwise they seed a new one.
    public static func cluster(_ fixes: [Fix], radiusM: Double = defaultRadiusM) -> [Cluster] {
        var clusters: [Cluster] = []
        for fix in fixes {
            var bestIndex: Int?
            var bestDistance = Double.infinity
            for (index, cluster) in clusters.enumerated() {
                let d = distance(lat1: fix.lat, lon1: fix.lon, lat2: cluster.lat, lon2: cluster.lon)
                if d <= radiusM && d < bestDistance {
                    bestDistance = d
                    bestIndex = index
                }
            }
            if let bestIndex {
                var cluster = clusters[bestIndex]
                let n = Double(cluster.sessionIds.count)
                cluster.lat = (cluster.lat * n + fix.lat) / (n + 1)
                cluster.lon = (cluster.lon * n + fix.lon) / (n + 1)
                cluster.sessionIds.append(fix.sessionId)
                clusters[bestIndex] = cluster
            } else {
                clusters.append(Cluster(lat: fix.lat, lon: fix.lon, sessionIds: [fix.sessionId]))
            }
        }
        return clusters
    }

    // MARK: - Database side

    /// Assigns one session to an existing spot or creates a new one, nudging the spot's
    /// centroid towards the new fix. Returns the spot id, or nil when the session has no
    /// usable start coordinate (a FIT that never got a GPS lock).
    @discardableResult
    public static func assign(sessionId: String, lat: Double, lon: Double, db: Database,
                              radiusM: Double = defaultRadiusM) throws -> String? {
        let spots = try SpotRow.fetchAll(db)
        var best: (spot: SpotRow, distance: Double)?
        for spot in spots {
            let d = distance(lat1: lat, lon1: lon, lat2: spot.lat, lon2: spot.lon)
            if d <= spot.radiusM, d < (best?.distance ?? .infinity) { best = (spot, d) }
        }

        if var spot = best?.spot {
            let n = Double(try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM session WHERE spotId = ?", arguments: [spot.id]) ?? 0)
            spot.lat = (spot.lat * n + lat) / (n + 1)
            spot.lon = (spot.lon * n + lon) / (n + 1)
            try spot.update(db)
            try db.execute(sql: "UPDATE session SET spotId = ? WHERE id = ?",
                           arguments: [spot.id, sessionId])
            return spot.id
        }

        let spot = SpotRow(name: placeholderName(Self.nextPlaceholderNumber(spots)),
                           lat: lat, lon: lon, radiusM: radiusM)
        try spot.insert(db)
        try db.execute(sql: "UPDATE session SET spotId = ? WHERE id = ?",
                       arguments: [spot.id, sessionId])
        return spot.id
    }

    /// Deletes every spot no session points at. Returns how many went.
    ///
    /// A spot exists because a session was recorded there; when the last of those sessions
    /// is deleted the place stops being one the rider has been, and a row reading "Spot 2 ·
    /// 0 · Never sailed" is a phantom of a session he removed on purpose. `session.spotId`
    /// carries no foreign key (it is a plain column, so a spot can be re-clustered without
    /// touching the sessions), which is exactly why the cascade has to be written down here
    /// rather than left to SQLite.
    ///
    /// Called on the two occasions a spot can be orphaned — when a session is deleted, and
    /// at the end of a re-cluster — each time inside the same write, so "a spot with no
    /// sessions" is a state the library passes through and never rests in. (An import cannot
    /// orphan one: `assign` attaches the session to the spot in the same breath as creating
    /// it.) Migration v16 runs it once more, to clear the phantoms libraries built before
    /// any of this existed.
    @discardableResult
    public static func pruneEmptySpots(db: Database) throws -> Int {
        try db.execute(sql: """
            DELETE FROM spot
             WHERE id NOT IN (SELECT spotId FROM session WHERE spotId IS NOT NULL)
            """)
        return db.changesCount
    }

    /// Rebuilds every spot from scratch. Used after a radius change and by the v1→v2
    /// backfill, where sessions predate the whole concept. **Every name somebody chose or
    /// looked up** is preserved by re-matching the old spot nearest to each new centroid.
    ///
    /// "Somebody chose or looked up" is `!isPlaceholderName`, not `!autoNamed`. A geocoded
    /// name stays `autoNamed` — the flag means "the rider has not renamed this", and it has
    /// to, or a rename could not win against a later lookup — so inheriting on `!autoNamed`
    /// threw away every looked-up name on every re-cluster and put "Spot 1 … Spot 7" back on
    /// the screen. What is genuinely disposable is the placeholder, and only that.
    ///
    /// Spots the rebuild does not re-create simply cease to exist: the table is emptied and
    /// refilled from the sessions, so **after a re-cluster no spot has zero sessions** — and
    /// the prune at the end says so for the degenerate case where a cluster ends up empty.
    public static func recluster(db: Database, radiusM: Double = defaultRadiusM) throws {
        let fixes = try Row.fetchAll(db, sql: """
            SELECT id, startLat, startLon FROM session
            WHERE startLat IS NOT NULL AND startLon IS NOT NULL
            ORDER BY startDate
            """).map { Fix(sessionId: $0["id"], lat: $0["startLat"], lon: $0["startLon"]) }

        let named = try SpotRow.fetchAll(db).filter { !isPlaceholderName($0.name) }
        let clusters = cluster(fixes, radiusM: radiusM)

        try db.execute(sql: "UPDATE session SET spotId = NULL")
        try db.execute(sql: "DELETE FROM spot")

        // A named spot may be the nearest one to two new centroids at once (a radius the
        // rider widened, two beaches that merged). It can only be inherited by one of them,
        // or the second `insert` collides on the primary key and the whole re-cluster
        // throws — so a claimed id is out of the running for the rest of the pass, and the
        // second cluster takes a placeholder and gets looked up like any new place.
        var claimed = Set<String>()
        for (index, cluster) in clusters.enumerated() {
            let inherited = named
                .filter { !claimed.contains($0.id) }
                .min { a, b in
                    distance(lat1: cluster.lat, lon1: cluster.lon, lat2: a.lat, lon2: a.lon)
                        < distance(lat1: cluster.lat, lon1: cluster.lon, lat2: b.lat, lon2: b.lon)
                }.flatMap { candidate -> SpotRow? in
                    distance(lat1: cluster.lat, lon1: cluster.lon,
                             lat2: candidate.lat, lon2: candidate.lon) <= radiusM ? candidate : nil
                }
            if let inherited { claimed.insert(inherited.id) }
            var spot = SpotRow(id: inherited?.id ?? UUID().uuidString,
                               name: inherited?.name ?? placeholderName(index + 1),
                               lat: cluster.lat, lon: cluster.lon, radiusM: radiusM,
                               // The inherited spot's own flag, not "did we inherit": a
                               // looked-up name is still auto-named, and carrying it across
                               // must not promote it to a name the rider typed.
                               autoNamed: inherited?.autoNamed ?? true,
                               createdAt: inherited?.createdAt ?? Date())
            spot.radiusM = radiusM
            try spot.insert(db)
            for sessionId in cluster.sessionIds {
                try db.execute(sql: "UPDATE session SET spotId = ? WHERE id = ?",
                               arguments: [spot.id, sessionId])
            }
        }
        try pruneEmptySpots(db: db)
    }
}
