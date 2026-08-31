import Foundation
import GRDB

/// What the Records/Trends/Gear screens are currently looking at. Every filter is
/// optional and they compose (`nil` = no restriction).
public struct LibraryFilter: Sendable, Equatable {
    public var spotId: String?
    public var gearId: String?
    /// Inclusive lower bound on `session.startDate`.
    public var since: Date?

    public init(spotId: String? = nil, gearId: String? = nil, since: Date? = nil) {
        self.spotId = spotId
        self.gearId = gearId
        self.since = since
    }

    public var isEmpty: Bool { spotId == nil && gearId == nil && since == nil }
}

/// One record kind's all-time best under the current filter, with the full effort series
/// behind it. `history` is ascending in time and holds *every* session's effort, so the
/// sparkline shows the shape of the progression, not just the PBs.
public struct RecordBest: Sendable, Identifiable, Equatable {
    public var kind: RecordKind
    public var valueKn: Double
    public var sessionId: String
    public var achievedAt: Date
    public var sourceClass: String
    public var window: RecordWindow?
    public var history: [RecordEffortRow]

    public var id: String { kind.rawValue }

    /// The efforts that were a personal best *when they happened* — the step curve.
    public var personalBests: [RecordEffortRow] {
        var best = -Double.infinity
        return history.filter {
            guard $0.valueKn > best else { return false }
            best = $0.valueKn
            return true
        }
    }

    /// The PB before this one, for the "+0.4 kn" delta.
    public var previousBest: Double? {
        let pbs = personalBests
        guard pbs.count >= 2 else { return nil }
        return pbs[pbs.count - 2].valueKn
    }

    /// A record only class (a)/(b) sources can certify; class (c) is GPX-grade.
    public var certified: Bool { sourceClass != "c" }
}

/// One session as the Trends charts see it. Every optional stays optional: a session
/// without an accelerometer has *unknown* pumps-to-takeoff, which must not plot as 0.
public struct TrendPoint: Sendable, Identifiable, Equatable {
    public var sessionId: String
    public var date: Date
    public var durationS: Double
    public var foilPct: Double?
    public var longestFlightS: Double?
    public var flightCount: Int?
    public var distanceKm: Double?
    public var jibeFlewThroughPct: Double?
    public var turnSuccessPct: Double?
    public var avgPumpsToTakeoff: Double?
    public var portSharePct: Double?
    public var best2sKn: Double?
    /// Turn outcomes split by the tack the turn was *entered* on. Zero-valued (and so
    /// nil-reporting) when the session has no per-turn rows — an old row imported before
    /// the child tables existed, or a session with no counted turns at all.
    public var turnSides = TurnSideSplit()

    public var id: String { sessionId }

    /// Port entry success, nil when he never entered a turn on port that session.
    public var portFlewThroughPct: Double? { turnSides.portSuccessPct }
    public var starboardFlewThroughPct: Double? { turnSides.starboardSuccessPct }

    public init(_ row: SessionRow, turnSides: TurnSideSplit = TurnSideSplit()) {
        sessionId = row.id
        date = row.startDate
        durationS = row.durationS
        foilPct = row.foilPct
        longestFlightS = row.longestFlightS
        flightCount = row.flightCount
        distanceKm = row.distanceKm
        jibeFlewThroughPct = row.jibeFlewThroughPct
        turnSuccessPct = (row.turnsCounted ?? 0) > 0 ? row.turnSuccessPct : nil
        avgPumpsToTakeoff = row.avgPumpsToTakeoff
        portSharePct = row.portSharePct
        best2sKn = row.best2sKn
        self.turnSides = turnSides
    }
}

/// Sessions per ISO week, gaps included (a week with no session plots as 0 — that *is*
/// the information).
public struct WeekBucket: Sendable, Identifiable, Equatable {
    public var weekStart: Date
    public var count: Int
    public var hours: Double

    public var id: Date { weekStart }
}

/// Per-gear rollup for the Gear screen.
public struct GearAggregate: Sendable, Identifiable, Equatable {
    public var gear: GearRow
    public var sessions: Int
    public var hours: Double
    public var distanceKm: Double
    public var foilPct: Double?
    public var best2sKn: Double?
    public var jibeFlewThroughPct: Double?
    public var lastUsed: Date?

    public var id: String { gear.id }
}

public struct SpotAggregate: Sendable, Identifiable, Equatable {
    public var spot: SpotRow
    public var sessions: Int
    public var lastVisit: Date?

    public var id: String { spot.id }
}

/// Every read the aggregate screens need. Kept as one type so the SQL that implements
/// the filters lives in exactly one place.
public struct LibraryStore: Sendable {

    public let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    // MARK: - Filtered session set

    /// `WHERE` fragment + arguments shared by every filtered query. `alias` is the
    /// session table's alias in the caller's statement.
    ///
    /// The example session is excluded unconditionally, in this one place, because it is
    /// the one place every aggregate goes through: Records, Trends, the week histogram.
    /// A borrowed session must never appear in a number that claims to be about the rider,
    /// and "remember to filter it" in six call sites is not a plan.
    ///
    /// A provisional session — the watch's BLE card, its FIT not synced yet — is excluded
    /// for a different reason and by the same mechanism: its numbers are the *watch's*
    /// arithmetic, not this engine's, and a trend line that mixes the two is a line about
    /// nothing. It has no `record_effort` rows either, so it could never hold a record.
    /// The exclusion is temporary by construction: when the FIT lands, `SessionIngestor`
    /// fills the same row with real analysis and clears the flag.
    ///
    /// A session credited to a friend (`rider IS NOT NULL`) is excluded for the plainest
    /// reason of the three: it is not the reader's session. Since the app answers for
    /// `.fit` files, a friend's recording is one tap on a chat attachment away from the
    /// library, and a personal best is a claim about a person — the third condition here
    /// is what keeps it one.
    static func clause(_ filter: LibraryFilter, alias: String) -> (join: String, where: String,
                                                                   args: StatementArguments) {
        var conditions: [String] = ["\(alias).isExample = 0", "\(alias).isProvisional = 0",
                                    "\(alias).rider IS NULL"]
        var args = StatementArguments()
        var join = ""
        if let gearId = filter.gearId {
            join = " JOIN session_gear sg ON sg.sessionId = \(alias).id AND sg.gearId = ?"
            args += [gearId]
        }
        if let spotId = filter.spotId {
            conditions.append("\(alias).spotId = ?")
            args += [spotId]
        }
        if let since = filter.since {
            conditions.append("\(alias).startDate >= ?")
            args += [since]
        }
        let whereSQL = conditions.isEmpty ? "" : " WHERE " + conditions.joined(separator: " AND ")
        return (join, whereSQL, args)
    }

    public func sessions(_ filter: LibraryFilter = LibraryFilter()) async throws -> [SessionRow] {
        try await database.writer.read { db in try Self.sessions(filter, db: db) }
    }

    static func sessions(_ filter: LibraryFilter, db: Database) throws -> [SessionRow] {
        let (join, whereSQL, args) = clause(filter, alias: "s")
        return try SessionRow.fetchAll(db, sql: "SELECT s.* FROM session s\(join)\(whereSQL) "
                                       + "ORDER BY s.startDate", arguments: args)
    }

    // MARK: - Records

    /// All-time bests per kind under the filter, strongest kinds first in catalogue order.
    /// A kind with no qualifying effort anywhere is simply absent from the result.
    public func records(_ filter: LibraryFilter = LibraryFilter()) async throws -> [RecordBest] {
        try await database.writer.read { db in
            let (join, whereSQL, args) = Self.clause(filter, alias: "s")
            let efforts = try RecordEffortRow.fetchAll(db, sql: """
                SELECT e.* FROM record_effort e JOIN session s ON s.id = e.sessionId\(join)\(whereSQL)
                ORDER BY e.achievedAt
                """, arguments: args)
            var byKind: [String: [RecordEffortRow]] = [:]
            for effort in efforts { byKind[effort.kind, default: []].append(effort) }

            return RecordKind.allCases.compactMap { kind -> RecordBest? in
                guard let history = byKind[kind.rawValue], !history.isEmpty,
                      let best = history.max(by: { $0.valueKn < $1.valueKn }) else { return nil }
                let window = best.windowStartTs.map {
                    RecordWindow(startTs: $0, durS: best.windowDurS ?? 0)
                }
                return RecordBest(kind: kind, valueKn: best.valueKn, sessionId: best.sessionId,
                                  achievedAt: best.achievedAt, sourceClass: best.sourceClass,
                                  window: window, history: history)
            }
        }
    }

    // MARK: - Trends

    public func trend(_ filter: LibraryFilter = LibraryFilter()) async throws -> [TrendPoint] {
        try await database.writer.read { db in
            let splits = try Self.turnSideSplits(filter, db: db)
            return try Self.sessions(filter, db: db).map {
                TrendPoint($0, turnSides: splits[$0.id] ?? TurnSideSplit())
            }
        }
    }

    /// Per-session turn outcomes by entry tack, for the port/starboard success series.
    ///
    /// It has to come from the `turn` child table: the denormalized session columns count
    /// port and starboard turns but not how each side *ended*, and the engine's
    /// `TurnSummary` does not carry per-side outcomes either (adding them would move a
    /// golden). Uncounted turns — bear-aways and round-ups — are excluded in the SQL, the
    /// same rule every other turn number in the app follows.
    static func turnSideSplits(_ filter: LibraryFilter,
                               db: Database) throws -> [String: TurnSideSplit] {
        let (join, whereSQL, args) = clause(filter, alias: "s")
        // `clause` always emits a WHERE (the example/provisional exclusions are
        // unconditional), so appending a condition is safe.
        let rows = try Row.fetchAll(db, sql: """
            SELECT t.sessionId AS sessionId, t.side AS side, t.outcome AS outcome
            FROM turn t JOIN session s ON s.id = t.sessionId\(join)\(whereSQL)
              AND t.counted = 1
            """, arguments: args)
        var out: [String: TurnSideSplit] = [:]
        for row in rows {
            let sessionId: String = row["sessionId"]
            let side: String = row["side"]
            let outcome: String = row["outcome"]
            var split = out[sessionId] ?? TurnSideSplit()
            split.add(side: side, flewThrough: TurnOutcomeKind(outcome) == .flewThrough)
            out[sessionId] = split
        }
        return out
    }

    /// Sessions per week over the filtered range, zero-filled between the first and the
    /// last session (or from `filter.since`, so an empty recent month reads as empty).
    public func weeks(_ filter: LibraryFilter = LibraryFilter(),
                      until: Date = Date()) async throws -> [WeekBucket] {
        let rows = try await sessions(filter)
        return Self.weeks(rows, since: filter.since, until: until)
    }

    static func weeks(_ rows: [SessionRow], since: Date?, until: Date) -> [WeekBucket] {
        guard let first = rows.first?.startDate ?? since else { return [] }
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        func startOfWeek(_ date: Date) -> Date {
            calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        }
        var buckets: [Date: WeekBucket] = [:]
        for row in rows {
            let key = startOfWeek(row.startDate)
            var bucket = buckets[key] ?? WeekBucket(weekStart: key, count: 0, hours: 0)
            bucket.count += 1
            bucket.hours += row.durationS / 3600
            buckets[key] = bucket
        }
        var out: [WeekBucket] = []
        var cursor = startOfWeek(min(first, since ?? first))
        let end = startOfWeek(max(until, rows.last?.startDate ?? until))
        // Guard against a pathological range blowing the chart up.
        while cursor <= end, out.count < 520 {
            out.append(buckets[cursor] ?? WeekBucket(weekStart: cursor, count: 0, hours: 0))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }
        return out
    }

    // MARK: - Gear

    public func gear(kind: GearKind? = nil, includeRetired: Bool = false) async throws -> [GearRow] {
        try await database.writer.read { db in
            var request = GearRow.all()
            if let kind { request = request.filter(Column("kind") == kind.rawValue) }
            if !includeRetired { request = request.filter(Column("active") == true) }
            return try request.order(Column("kind"), Column("name")).fetchAll(db)
        }
    }

    public func gearAggregates() async throws -> [GearAggregate] {
        try await database.writer.read { db in
            let gear = try GearRow.order(Column("kind"), Column("name")).fetchAll(db)
            return try gear.map { item in
                let rows = try SessionRow.fetchAll(db, sql: """
                    SELECT s.* FROM session s JOIN session_gear sg ON sg.sessionId = s.id
                    WHERE sg.gearId = ? AND s.isExample = 0 AND s.isProvisional = 0
                      AND s.rider IS NULL
                    ORDER BY s.startDate
                    """, arguments: [item.id])
                return Self.aggregate(item, rows: rows)
            }
        }
    }

    static func aggregate(_ gear: GearRow, rows: [SessionRow]) -> GearAggregate {
        // Foil % is weighted by session duration: a 10-minute session should not swing
        // the number as hard as a two-hour one.
        var foilNumerator = 0.0, foilDenominator = 0.0
        var jibes = 0, jibesFlew = 0
        for row in rows {
            if let pct = row.foilPct, row.durationS > 0 {
                foilNumerator += pct * row.durationS
                foilDenominator += row.durationS
            }
            jibes += row.jibes ?? 0
            jibesFlew += row.jibesFlewThrough ?? 0
        }
        return GearAggregate(
            gear: gear,
            sessions: rows.count,
            hours: rows.reduce(0) { $0 + $1.durationS } / 3600,
            distanceKm: rows.reduce(0) { $0 + ($1.distanceKm ?? 0) },
            foilPct: foilDenominator > 0 ? foilNumerator / foilDenominator : nil,
            best2sKn: rows.compactMap(\.best2sKn).max(),
            jibeFlewThroughPct: jibes > 0 ? Double(jibesFlew) / Double(jibes) * 100 : nil,
            lastUsed: rows.last?.startDate)
    }

    /// The combo the rider used most recently — the default for a freshly imported session.
    public func lastUsedGear() async throws -> [GearKind: GearRow] {
        try await database.writer.read { db in
            var out: [GearKind: GearRow] = [:]
            for kind in GearKind.allCases {
                out[kind] = try GearRow.fetchOne(db, sql: """
                    SELECT g.* FROM gear g JOIN session_gear sg ON sg.gearId = g.id
                    JOIN session s ON s.id = sg.sessionId
                    WHERE sg.kind = ? AND g.active = 1
                    ORDER BY s.startDate DESC LIMIT 1
                    """, arguments: [kind.rawValue])
            }
            return out
        }
    }

    public func gearOfSession(_ sessionId: String) async throws -> [GearKind: GearRow] {
        try await database.writer.read { db in
            var out: [GearKind: GearRow] = [:]
            let rows = try GearRow.fetchAll(db, sql: """
                SELECT g.* FROM gear g JOIN session_gear sg ON sg.gearId = g.id
                WHERE sg.sessionId = ?
                """, arguments: [sessionId])
            for row in rows { if let kind = row.gearKind { out[kind] = row } }
            return out
        }
    }

    // MARK: - Gear mutations

    @discardableResult
    public func saveGear(_ gear: GearRow) async throws -> GearRow {
        try await database.writer.write { db in try gear.save(db) }
        return gear
    }

    public func deleteGear(id: String) async throws {
        _ = try await database.writer.write { db in try GearRow.deleteOne(db, key: id) }
    }

    /// Assigns (or, with `gearId == nil`, clears) one slot of a session's combo.
    public func assignGear(sessionId: String, kind: GearKind, gearId: String?) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM session_gear WHERE sessionId = ? AND kind = ?",
                           arguments: [sessionId, kind.rawValue])
            if let gearId {
                try SessionGearRow(sessionId: sessionId, gearId: gearId, kind: kind).insert(db)
            }
        }
    }

    /// Applies the most recent combo to a session that has none yet — the "default =
    /// last used" rule, applied on import and re-applied when the rider adds gear later.
    @discardableResult
    public func applyDefaultGear(sessionId: String) async throws -> Int {
        let last = try await lastUsedGear()
        guard !last.isEmpty else { return 0 }
        return try await database.writer.write { db in
            let existing = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM session_gear WHERE sessionId = ?",
                arguments: [sessionId]) ?? 0
            guard existing == 0 else { return 0 }
            for (kind, gear) in last {
                try SessionGearRow(sessionId: sessionId, gearId: gear.id, kind: kind).insert(db)
            }
            return last.count
        }
    }

    // MARK: - Spots

    /// Every spot with its session count and last visit. One `GROUP BY` pass over the
    /// sessions rather than a full `SessionRow` fetch per spot — only the two aggregates
    /// are ever read. `startDate` is stored as a sortable datetime, so `MAX` is the
    /// chronological last visit; a spot with no sessions still appears, with 0 / nil.
    public func spots() async throws -> [SpotAggregate] {
        try await database.writer.read { db in
            var counts: [String: Int] = [:]
            var lastVisits: [String: Date] = [:]
            let rows = try Row.fetchAll(db, sql: """
                SELECT spotId, COUNT(*) AS sessions, MAX(startDate) AS lastVisit
                FROM session WHERE spotId IS NOT NULL GROUP BY spotId
                """)
            for row in rows {
                guard let id: String = row["spotId"] else { continue }
                counts[id] = row["sessions"]
                lastVisits[id] = row["lastVisit"]
            }
            return try SpotRow.order(Column("name")).fetchAll(db).map { spot in
                SpotAggregate(spot: spot, sessions: counts[spot.id] ?? 0,
                              lastVisit: lastVisits[spot.id])
            }
        }
    }

    public func renameSpot(id: String, to name: String) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE spot SET name = ?, autoNamed = 0 WHERE id = ?",
                           arguments: [name, id])
        }
    }

    /// Names auto-named spots from a reverse-geocoding closure. Anything the closure
    /// cannot resolve (offline, no result) keeps its "Spot N" placeholder.
    public func nameAutoSpots(
        using locality: @Sendable (Double, Double) async -> String?) async throws {
        let pending = try await database.writer.read { db in
            try SpotRow.filter(Column("autoNamed") == true).fetchAll(db)
        }
        for spot in pending {
            guard let name = await locality(spot.lat, spot.lon), !name.isEmpty else { continue }
            try await database.writer.write { db in
                // Still auto-named: a later re-cluster may replace it, a rename won't.
                try db.execute(sql: "UPDATE spot SET name = ? WHERE id = ? AND autoNamed = 1",
                               arguments: [name, spot.id])
            }
        }
    }

    public func recluster(radiusM: Double = SpotClusterer.defaultRadiusM) async throws {
        try await database.writer.write { db in
            try SpotClusterer.recluster(db: db, radiusM: radiusM)
        }
    }

    // MARK: - Riders

    /// The friends whose sessions are already in the library, alphabetically.
    ///
    /// The distinct values of the column *are* the address book — a rider imports two or
    /// three friends' files, and a table plus a picker plus a merge story for a name typed
    /// two ways would be more machinery than the fact deserves. The import prompt offers
    /// these so the second file from the same friend is one tap and lands on the same
    /// spelling as the first.
    public func riders() async throws -> [String] {
        try await database.writer.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT rider FROM session
                WHERE rider IS NOT NULL AND TRIM(rider) <> '' ORDER BY rider COLLATE NOCASE
                """)
        }
    }

    // MARK: - Import history

    public func importLog(limit: Int = 20) async throws -> [ImportLogRow] {
        try await database.writer.read { db in
            try ImportLogRow.order(Column("startedAt").desc).limit(limit).fetchAll(db)
        }
    }
}
