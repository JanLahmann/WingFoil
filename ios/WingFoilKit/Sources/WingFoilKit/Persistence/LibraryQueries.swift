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
    /// The UTC offset of the session the record was set in (`SessionRow.startUtcOffsetS`),
    /// so the row dates the effort on the day the *rider* had. Carried here rather than
    /// looked up by the view: a PB row names a day, and a day is a question only the
    /// session's own zone can answer — an evening session either side of midnight is filed
    /// under the wrong date by any other clock.
    public var utcOffsetS: Int?

    public var id: String { kind.rawValue }

    /// The zone the effort's date is drawn in. `.current` when the session could not say —
    /// the same fallback `SessionRow.displayZone` makes, for the same reason.
    public var displayZone: TimeZone {
        utcOffsetS.flatMap { TimeZone(secondsFromGMT: $0) } ?? .current
    }

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

/// One session record's all-time best under the current filter.
///
/// Deliberately thinner than `RecordBest`: there is no effort history to draw a step curve
/// from (the number lives on the session row, not in `record_effort`) and no certification
/// to badge, because a session record makes no claim about a speed channel.
public struct SessionRecordBest: Sendable, Identifiable, Equatable {
    public var kind: SessionRecordKind
    public var value: Double
    public var sessionId: String
    public var achievedAt: Date
    /// The offset of the session the record was set in, so the row dates it on the day the
    /// *rider* had — same reason `RecordBest` carries one.
    public var utcOffsetS: Int?
    /// The winning session's longest-flight distance, on the `.longestFlight` row and
    /// nowhere else: six minutes downwind and six minutes of pumping in a lull are not the
    /// same flight, and the duration alone cannot tell them apart.
    public var distanceM: Double?

    public var id: String { kind.rawValue }

    public var displayZone: TimeZone {
        utcOffsetS.flatMap { TimeZone(secondsFromGMT: $0) } ?? .current
    }
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
    /// The flew-through share over every counted turn — what the "Flew-through rate" chart
    /// plots on both platforms. `turnSuccessPct` beside it is the engine's score verdict:
    /// carried on the point because the row has it, and drawn by nothing, because it is not
    /// one of the rider's two tiers (7 Sep 2026).
    public var flewThroughPct: Double?
    public var turnSuccessPct: Double?
    /// Clean jibes in the session and the same count per hour of it — the two series the
    /// Trends screen adds beside the rates. nil, never 0, on a row that has no count.
    public var cleanJibes: Int?
    public var cleanJibesPerHour: Double?
    /// **Rates are additive.** JPH says he got away with the jibes, TPH says how busy the
    /// afternoon was, CPH says he rode them — three questions, three lines on the Trends
    /// page, in that order. The engine's own fields (schema v17); nil, never 0, on a row the
    /// v17 sweep has not reached (docs/algorithms.md "Session rates").
    public var jibesPerHour: Double?
    public var turnsPerHour: Double?
    public var avgPumpsToTakeoff: Double?
    public var portSharePct: Double?
    public var best2sKn: Double?
    /// Could this recording certify a speed? A class-(c) session differentiated its speed
    /// from positions, which reads high, so its `best2sKn` is drawn *marked* — the same rule
    /// the Records table applies to an all-time best, and the analyzer's `library._stamp`
    /// to a trend point (docs/algorithms.md, "Source classes").
    public var certified: Bool = true
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
        // The engine's own cleaned span — the clock every trend hour and every displayed
        // session duration divides by (docs/presentation.md, "One clock").
        durationS = row.rateSeconds
        foilPct = row.foilPct
        longestFlightS = row.longestFlightS
        flightCount = row.flightCount
        distanceKm = row.distanceKm
        jibeFlewThroughPct = row.jibeFlewThroughPct
        flewThroughPct = row.flewThroughPct
        turnSuccessPct = (row.turnsCounted ?? 0) > 0 ? row.turnSuccessPct : nil
        cleanJibes = row.jibesSuccessful
        cleanJibesPerHour = row.cleanJibesPerHour
        jibesPerHour = row.jibesPerHour
        turnsPerHour = row.turnsPerHour
        avgPumpsToTakeoff = row.avgPumpsToTakeoff
        portSharePct = row.portSharePct
        best2sKn = row.best2sKn
        certified = row.sourceClass != "c"
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
    ///
    /// A recording that is **not a session** (`isSession = 0`, engine 0.19.0,
    /// docs/algorithms.md "Not a session") is the fourth, and the newest: the thirty seconds
    /// a rider records on the beach and stops again. Thirteen of them turned up in Jan's
    /// library on 13–14 September 2026 — 0:00–0:24 min, 0.0 km, no foil time — and every one
    /// of them counted in the totals and pulled the Trends "on foil" line to zero on its way
    /// past. Like the other three this is an exclusion from *numbers* only: the row stays in
    /// the list, quietly tagged, and its page still opens.
    static func clause(_ filter: LibraryFilter, alias: String) -> (join: String, where: String,
                                                                   args: StatementArguments) {
        var conditions: [String] = ["\(alias).isExample = 0", "\(alias).isProvisional = 0",
                                    "\(alias).isSession = 1", "\(alias).rider IS NULL"]
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
    ///
    /// **The verified/unverified decision is taken here, at query time** (Settings → Speed
    /// records, 22 September 2026). The `record_effort` table keeps every effort whatever
    /// the setting says; `SpeedRecordRule.eligible` decides, per kind, which of them the
    /// rider's policy lets stand, and it runs *before* the maximum is taken — that is the
    /// whole of "a verified record wins whenever one exists". A kind whose only efforts are
    /// unverified drops out of the result under `onlyVerified`, exactly like a kind nobody
    /// has ever set.
    public func records(_ filter: LibraryFilter = LibraryFilter(),
                        policy: SpeedRecordPolicy = .preferVerified) async throws
        -> [RecordBest] {
        try await database.writer.read { db in
            let (join, whereSQL, args) = Self.clause(filter, alias: "s")
            let efforts = try RecordEffortRow.fetchAll(db, sql: """
                SELECT e.* FROM record_effort e JOIN session s ON s.id = e.sessionId\(join)\(whereSQL)
                ORDER BY e.achievedAt
                """, arguments: args)
            var byKind: [String: [RecordEffortRow]] = [:]
            for effort in efforts { byKind[effort.kind, default: []].append(effort) }
            // One extra read rather than a wider effort row: the offset belongs to the
            // session, and denormalizing it onto every effort would be a second copy of a
            // fact that already has a home.
            var offsets: [String: Int] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT id, startUtcOffsetS FROM session WHERE startUtcOffsetS IS NOT NULL
                """) {
                offsets[row["id"]] = row["startUtcOffsetS"]
            }

            return RecordKind.allCases.compactMap { kind -> RecordBest? in
                guard let all = byKind[kind.rawValue], !all.isEmpty else { return nil }
                // One call per kind, because `preferVerified` is a statement about a kind:
                // best 2 s may be filled by an unverified effort on a library that holds a
                // verified 500 m and no verified 2 s.
                let history = SpeedRecordRule.eligible(all, policy: policy) {
                    $0.sourceClass != "c"
                }
                guard !history.isEmpty,
                      let best = history.max(by: { $0.valueKn < $1.valueKn }) else { return nil }
                let window = best.windowStartTs.map {
                    RecordWindow(startTs: $0, durS: best.windowDurS ?? 0)
                }
                return RecordBest(kind: kind, valueKn: best.valueKn, sessionId: best.sessionId,
                                  achievedAt: best.achievedAt, sourceClass: best.sourceClass,
                                  window: window, history: history,
                                  utcOffsetS: offsets[best.sessionId])
            }
        }
    }

    /// The all-time best per session-record kind under the same filter the speed records
    /// use, in catalogue order. A kind nobody has a positive value for is absent rather
    /// than shown as a dash — the same rule `records(_:)` follows, and the same rule the
    /// analyzer's `library._session_records` follows.
    ///
    /// **Ties go to the earliest session**, because the record was set then and not re-set
    /// later. `sessions(_:)` orders by `startDate`, so a strict `>` is the whole of it.
    public func sessionRecords(_ filter: LibraryFilter = LibraryFilter()) async throws
        -> [SessionRecordBest] {
        try await database.writer.read { db in
            let rows = try Self.sessions(filter, db: db)          // oldest first
            return SessionRecordKind.allCases.compactMap { kind in
                var best: (Double, SessionRow)?
                for row in rows {
                    guard let value = kind.value(in: row), value > 0 else { continue }
                    if best == nil || value > best!.0 { best = (value, row) }
                }
                guard let (value, row) = best else { return nil }
                return SessionRecordBest(
                    kind: kind, value: value, sessionId: row.id, achievedAt: row.startDate,
                    utcOffsetS: row.startUtcOffsetS,
                    distanceM: kind == .longestFlight ? row.longestFlightM : nil)
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

    /// **JPH per session**, keyed by session id — dry jibes per hour of timer time.
    ///
    /// It is a query rather than a column because the session index denormalizes CPH and
    /// not JPH (schema v11 added one rate, not four). The numerator is the engine's own
    /// rule read back off the `turn` table — counted jibes he did **not** swim out of,
    /// `SessionSummarizer.dryJibeTimes` — and the denominator is `timerSeconds`, the one
    /// clock a rate may divide by since engine 0.13.0 (docs/algorithms.md, "Session
    /// rates"). So the number here is the number on the session page, not a second
    /// arithmetic that happens to be close.
    ///
    /// A session with a timer and genuinely no dry jibe reports a measured 0, exactly as
    /// the engine does; a session with no timer to divide by is absent, never 0.
    public func jibeRates(_ filter: LibraryFilter = LibraryFilter()) async throws
        -> [String: Double] {
        try await database.writer.read { db in
            let counts = try Self.dryJibeCounts(filter, db: db)
            var out: [String: Double] = [:]
            for row in try Self.sessions(filter, db: db) where row.timerSeconds > 0 {
                out[row.id] = Double(counts[row.id] ?? 0) * 3600 / row.timerSeconds
            }
            return out
        }
    }

    /// Counted jibes that did not end in the water, per session — the JPH numerator.
    /// Uncounted turns (bear-aways, round-ups) are excluded in the SQL, the same rule every
    /// other turn number in the app follows.
    static func dryJibeCounts(_ filter: LibraryFilter, db: Database) throws -> [String: Int] {
        let (join, whereSQL, args) = clause(filter, alias: "s")
        // `clause` always emits a WHERE (the example/provisional exclusions are
        // unconditional), so appending conditions is safe.
        let rows = try Row.fetchAll(db, sql: """
            SELECT t.sessionId AS sessionId, COUNT(*) AS n
            FROM turn t JOIN session s ON s.id = t.sessionId\(join)\(whereSQL)
              AND t.counted = 1 AND t.type = 'jibe' AND t.outcome <> 'fell_in'
            GROUP BY t.sessionId
            """, arguments: args)
        var out: [String: Int] = [:]
        for row in rows { out[row["sessionId"]] = row["n"] }
        return out
    }

    /// Sessions per week over the filtered range, zero-filled between the first and the
    /// last session (or from `filter.since`, so an empty recent month reads as empty).
    public func weeks(_ filter: LibraryFilter = LibraryFilter(),
                      until: Date = Date()) async throws -> [WeekBucket] {
        let rows = try await sessions(filter)
        return Self.weeks(rows, since: filter.since, until: until)
    }

    /// The week rule, in one place: **ISO-8601 weeks, Monday start, in the reader's own
    /// local time**. The analyzer says the same thing in `library._week_start`.
    ///
    /// `firstWeekday` and `minimumDaysInFirstWeek` are set rather than inherited even
    /// though the ISO-8601 identifier implies both: a calendar that picks up a locale's
    /// Sunday-first habit would bucket a Sunday session into the week *after* the one the
    /// rider rode it in, and the failure is invisible — every bar still has a plausible
    /// height. It is also what the chart's own binning is handed, so the bar and the bucket
    /// cannot drift apart.
    public static var isoCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        calendar.firstWeekday = 2                    // Monday
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func weeks(_ rows: [SessionRow], since: Date?, until: Date) -> [WeekBucket] {
        guard let first = rows.first?.startDate ?? since else { return [] }
        let calendar = isoCalendar
        func startOfWeek(_ date: Date) -> Date {
            calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        }
        var buckets: [Date: WeekBucket] = [:]
        for row in rows {
            let key = startOfWeek(row.startDate)
            var bucket = buckets[key] ?? WeekBucket(weekStart: key, count: 0, hours: 0)
            bucket.count += 1
            bucket.hours += row.rateSeconds / 3600
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
                      AND s.isSession = 1 AND s.rider IS NULL
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
            if let pct = row.foilPct, row.rateSeconds > 0 {
                foilNumerator += pct * row.rateSeconds
                foilDenominator += row.rateSeconds
            }
            jibes += row.jibes ?? 0
            jibesFlew += row.jibesFlewThrough ?? 0
        }
        return GearAggregate(
            gear: gear,
            sessions: rows.count,
            hours: rows.reduce(0) { $0 + $1.rateSeconds } / 3600,
            distanceKm: rows.reduce(0) { $0 + ($1.distanceKm ?? 0) },
            foilPct: foilDenominator > 0 ? foilNumerator / foilDenominator : nil,
            best2sKn: rows.compactMap(\.best2sKn).max(),
            jibeFlewThroughPct: jibes > 0 ? Double(jibesFlew) / Double(jibes) * 100 : nil,
            lastUsed: rows.last?.startDate)
    }

    /// The combo the rider used most recently — the default for a freshly imported session.
    ///
    /// "Most recently" over the sessions he actually rode: the example, a friend's afternoon
    /// and a thirty-second beach recording are none of them evidence of what is rigged on the
    /// van roof today, and the last of the three is exactly the kind of row that lands newest.
    public func lastUsedGear() async throws -> [GearKind: GearRow] {
        try await database.writer.read { db in
            var out: [GearKind: GearRow] = [:]
            for kind in GearKind.allCases {
                out[kind] = try GearRow.fetchOne(db, sql: """
                    SELECT g.* FROM gear g JOIN session_gear sg ON sg.gearId = g.id
                    JOIN session s ON s.id = sg.sessionId
                    WHERE sg.kind = ? AND g.active = 1
                      AND s.isExample = 0 AND s.isSession = 1 AND s.rider IS NULL
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
    ///
    /// Counted over the sessions the rider actually rode — the same four exclusions
    /// `clause` applies, spelled here because this query is a `GROUP BY` over the raw table
    /// rather than a filtered fetch. "Torbole · 3" must mean three afternoons, not two
    /// afternoons and the thirty seconds he recorded in the car park.
    public func spots() async throws -> [SpotAggregate] {
        try await database.writer.read { db in
            var counts: [String: Int] = [:]
            var lastVisits: [String: Date] = [:]
            let rows = try Row.fetchAll(db, sql: """
                SELECT spotId, COUNT(*) AS sessions, MAX(startDate) AS lastVisit
                FROM session WHERE spotId IS NOT NULL
                  AND isExample = 0 AND isProvisional = 0 AND isSession = 1
                  AND rider IS NULL
                GROUP BY spotId
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

    /// How many spots are still wearing a `"Spot N"` placeholder — the work a naming pass
    /// has left to do, and the only thing that makes "Look up names again" worth offering.
    public func unnamedSpotCount() async throws -> Int {
        try await database.writer.read { db in
            try SpotRow.fetchAll(db)
                .filter { $0.autoNamed && SpotClusterer.isPlaceholderName($0.name) }
                .count
        }
    }

    /// Names every spot still wearing a placeholder, from a reverse-geocoding closure.
    /// Returns how many are **still** unnamed afterwards, so the caller can decide whether
    /// a retry is worth scheduling. Anything the closure cannot resolve (offline, no
    /// result) keeps its `"Spot N"` and is asked again on the next pass.
    ///
    /// The candidate set is `autoNamed && isPlaceholderName`, not `autoNamed` alone. A
    /// looked-up name stays `autoNamed` — the flag distinguishes "the rider renamed this"
    /// from "we did", and it has to, or a rename could not survive the next pass — so
    /// asking on `autoNamed` alone re-geocoded every spot in the library at every launch:
    /// a network round trip, and one coordinate leaving the phone, for an answer already on
    /// the screen (docs/presentation.md, "What leaves the phone").
    @discardableResult
    public func nameAutoSpots(
        using locality: @Sendable (Double, Double) async -> String?) async throws -> Int {
        let pending = try await database.writer.read { db in
            try SpotRow.fetchAll(db)
                .filter { $0.autoNamed && SpotClusterer.isPlaceholderName($0.name) }
        }
        var unresolved = 0
        for spot in pending {
            guard let name = await locality(spot.lat, spot.lon), !name.isEmpty else {
                unresolved += 1
                continue
            }
            try await database.writer.write { db in
                // Still auto-named: a later rename wins over this, a re-cluster carries it.
                try db.execute(sql: "UPDATE spot SET name = ? WHERE id = ? AND autoNamed = 1",
                               arguments: [name, spot.id])
            }
        }
        return unresolved
    }

    public func recluster(radiusM: Double = SpotClusterer.defaultRadiusM) async throws {
        try await database.writer.write { db in
            try SpotClusterer.recluster(db: db, radiusM: radiusM)
        }
    }

    /// Deletes every spot no session points at — see `SpotClusterer.pruneEmptySpots`.
    @discardableResult
    public func pruneEmptySpots() async throws -> Int {
        try await database.writer.write { db in
            try SpotClusterer.pruneEmptySpots(db: db)
        }
    }

    // MARK: - Naming a session

    /// Renames one session, or gives it its derived name back.
    ///
    /// Nil (and blank, and whitespace) all write NULL, which is what makes "he cleared it"
    /// and "he never named it" one state: the row falls back to `SessionDisplay.title` and
    /// every surface follows, because every surface asks the same function
    /// (`SessionNaming.title`).
    ///
    /// Normalized on the way in rather than on the way out — `SessionNaming.customTitle` caps
    /// and trims — so the stored value is the value, and a reader never has to wonder whether
    /// what it fetched has been through the rules yet.
    public func renameSession(id: String, to title: String?) async throws {
        let stored = SessionNaming.customTitle(title)
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE session SET customTitle = ? WHERE id = ?",
                           arguments: [stored, id])
        }
    }

    /// Sets (or clears) the one-line caption the card and the clip's opening frame carry.
    ///
    /// Same shape and same rules as `renameSession`, and capped at `SessionNaming.noteLimit`
    /// here as well as in the field the rider types into: a card is a PNG, so the length at
    /// which a caption stops fitting is a fact about the content, not about the text field.
    public func setShareNote(id: String, to note: String?) async throws {
        let stored = SessionNaming.note(note)
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE session SET shareNote = ? WHERE id = ?",
                           arguments: [stored, id])
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

    // MARK: - Deleted sessions

    /// Every tombstone, newest deletion first — what the sync consults and what the Settings
    /// escape hatch counts.
    ///
    /// Read whole rather than queried per activity: a rider's tombstone list is a handful of
    /// rows, and one read per sync is cheaper than one query per listed activity as well as
    /// being the only shape a *pure* matcher (`SessionTombstones.blocks`) can be handed.
    public func tombstones() async throws -> [SessionTombstoneRow] {
        try await database.writer.read { db in
            try SessionTombstoneRow.order(Column("deletedAt").desc).fetchAll(db)
        }
    }

    public func tombstoneCount() async throws -> Int {
        try await database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM deleted_session") ?? 0
        }
    }

    /// Forgets that these sessions were ever deleted, which is the whole of "re-add": the
    /// next sync then sees them as activities it has never met and imports them normally.
    ///
    /// Deliberately not an import of its own. The FIT is gone — the archive directory went
    /// with the row — so the only place the session can come back *from* is intervals.icu,
    /// and going through the ordinary sync means a re-added session is analysed by the same
    /// code, logged the same way and deduped against the same key as any other.
    public func forgetTombstones(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        _ = try await database.writer.write { db in
            try SessionTombstoneRow.deleteAll(db, keys: ids)
        }
    }

    public func forgetAllTombstones() async throws {
        _ = try await database.writer.write { db in
            try SessionTombstoneRow.deleteAll(db)
        }
    }

    // MARK: - Import history

    public func importLog(limit: Int = 20) async throws -> [ImportLogRow] {
        try await database.writer.read { db in
            try ImportLogRow.order(Column("startedAt").desc).limit(limit).fetchAll(db)
        }
    }
}
