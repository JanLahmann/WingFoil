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

        let existing = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM spot") ?? 0
        let spot = SpotRow(name: "Spot \(existing + 1)", lat: lat, lon: lon, radiusM: radiusM)
        try spot.insert(db)
        try db.execute(sql: "UPDATE session SET spotId = ? WHERE id = ?",
                       arguments: [spot.id, sessionId])
        return spot.id
    }

    /// Rebuilds every spot from scratch. Used after a radius change and by the v1→v2
    /// backfill, where sessions predate the whole concept. Rider-given names are
    /// preserved by re-matching the old spot nearest to each new centroid.
    public static func recluster(db: Database, radiusM: Double = defaultRadiusM) throws {
        let fixes = try Row.fetchAll(db, sql: """
            SELECT id, startLat, startLon FROM session
            WHERE startLat IS NOT NULL AND startLon IS NOT NULL
            ORDER BY startDate
            """).map { Fix(sessionId: $0["id"], lat: $0["startLat"], lon: $0["startLon"]) }

        let named = try SpotRow.fetchAll(db).filter { !$0.autoNamed }
        let clusters = cluster(fixes, radiusM: radiusM)

        try db.execute(sql: "UPDATE session SET spotId = NULL")
        try db.execute(sql: "DELETE FROM spot")

        for (index, cluster) in clusters.enumerated() {
            let inherited = named.min { a, b in
                distance(lat1: cluster.lat, lon1: cluster.lon, lat2: a.lat, lon2: a.lon)
                    < distance(lat1: cluster.lat, lon1: cluster.lon, lat2: b.lat, lon2: b.lon)
            }.flatMap { candidate -> SpotRow? in
                distance(lat1: cluster.lat, lon1: cluster.lon,
                         lat2: candidate.lat, lon2: candidate.lon) <= radiusM ? candidate : nil
            }
            var spot = SpotRow(id: inherited?.id ?? UUID().uuidString,
                               name: inherited?.name ?? "Spot \(index + 1)",
                               lat: cluster.lat, lon: cluster.lon, radiusM: radiusM,
                               autoNamed: inherited == nil,
                               createdAt: inherited?.createdAt ?? Date())
            spot.radiusM = radiusM
            try spot.insert(db)
            for sessionId in cluster.sessionIds {
                try db.execute(sql: "UPDATE session SET spotId = ? WHERE id = ?",
                               arguments: [spot.id, sessionId])
            }
        }
    }
}
