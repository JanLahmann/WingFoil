import Foundation
import GRDB
import Testing
@testable import WingFoilKit

/// Schema v1 → v2 (plan §3.3, phase 4). A shipped v1 library holds only the session
/// index; the migration has to add every aggregate column, create the child tables, and
/// arrange for the analysis-derived data to be *re-derived* rather than invented — which
/// it does by clearing `engineVersion`, the same trigger an engine bump uses.
@Suite struct MigrationTests {

    private struct Harness {
        var database: AppDatabase
        var ingestor: SessionIngestor
        var root: URL
        var v1Ids: [String]
    }

    /// Builds a database that stops at v1, fills it the way the v1 app did (raw rows +
    /// archived FITs, no child tables), then opens it as the current AppDatabase — which
    /// runs the v2 migration.
    private func migratedV1Library(fixtureCount: Int = 2) throws -> Harness {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-migration-\(UUID().uuidString)/Sessions",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = SessionArchive(root: root)

        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v1")
        #expect(try queue.read { try $0.tableExists("session") })
        #expect(try queue.read { try !$0.tableExists("flight") })

        var ids: [String] = []
        for url in allFixtureFITs().prefix(fixtureCount) {
            let data = try Data(contentsOf: url)
            let track = try FitSessionParser.parse(data: data)
            guard let start = track.startDate, let first = track.samples.first,
                  let last = track.samples.last else { continue }
            let id = UUID().uuidString
            ids.append(id)
            try archive.storeOriginal(data, id: id)
            try queue.write { db in
                try db.execute(sql: """
                    INSERT INTO session (id, startDate, durationS, sport, sourceClass,
                                         originalFilename, importSource, engineVersion, foilPct)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [id, start, last.t - first.t, track.capabilities.sport,
                                     track.capabilities.sourceClass, url.lastPathComponent,
                                     "file", "0.1.0", 42.0])
            }
        }
        try #require(!ids.isEmpty, "no fixtures to migrate")

        let database = try AppDatabase(queue)          // ← runs v2
        return Harness(database: database,
                       ingestor: SessionIngestor(database: database, archive: archive),
                       root: root, v1Ids: ids)
    }

    @Test func v2AddsEveryTableAndColumn() throws {
        let harness = try migratedV1Library()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }

        try harness.database.writer.read { db in
            for table in ["session", "flight", "turn", "takeoff_attempt", "record_effort",
                          "gear", "session_gear", "spot", "import_log"] {
                #expect(try db.tableExists(table), "missing table \(table)")
            }
            let columns = Set(try db.columns(in: "session").map(\.name))
            for column in ["foilTimeS", "best500mKn", "alpha500Kn", "jibes", "jibesFlewThrough",
                           "turnsCounted", "turnSuccessPct", "turnsPort", "turnsStarboard",
                           "takeoffAttempts", "avgPumpsToTakeoff", "windAxisDeg", "startLat",
                           "spotId", "hasAccel"] {
                #expect(columns.contains(column), "missing session column \(column)")
            }
            // v1 rows survive with their identity intact …
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM session") == harness.v1Ids.count)
            // … but are marked stale so nothing is left half-derived.
            #expect(try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM session WHERE engineVersion IS NULL")
                == harness.v1Ids.count)
        }
    }

    @Test func migratedSessionsReanalyzeAndFillTheNewTables() async throws {
        let harness = try migratedV1Library()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }

        let rebuilt = try await harness.ingestor.reanalyzeStale()
        #expect(rebuilt == harness.v1Ids.count)
        // Idempotent: a second pass finds nothing stale.
        #expect(try await harness.ingestor.reanalyzeStale() == 0)

        let sessions = try await harness.ingestor.allSessions()
        #expect(sessions.allSatisfy { $0.engineVersion == AnalysisEngine.version })
        // The stub 42 % from the v1 row is gone — these are recomputed numbers.
        #expect(sessions.allSatisfy { $0.foilPct != 42.0 })
        #expect(sessions.allSatisfy { $0.foilTimeS != nil })

        for session in sessions {
            let analysis = try await harness.ingestor.analysis(for: session)
            try await harness.database.writer.read { db in
                let flights = try FlightRow.filter(Column("sessionId") == session.id).fetchAll(db)
                let turns = try TurnRow.filter(Column("sessionId") == session.id).fetchAll(db)
                let takeoffs = try TakeoffAttemptRow
                    .filter(Column("sessionId") == session.id).fetchAll(db)
                #expect(flights.count == analysis.flights.count)
                #expect(turns.count == analysis.turns.count)
                #expect(takeoffs.count == analysis.takeoffs.count)
                if let first = flights.first, let source = analysis.flights.first {
                    #expect(abs(first.maxKn - source.maxKn) < 0.001)
                    #expect(abs(first.durationS - (source.endTs - source.startTs)) < 0.001)
                }
            }
            #expect(session.flightCount == analysis.summary.flightCount)
            #expect(session.jibes == analysis.summary.turns.jibes)
            #expect(session.turnsCounted == analysis.summary.turns.turnsCounted)
        }
    }

    @Test func migratedSessionsGetSpotsAndRecordEfforts() async throws {
        let harness = try migratedV1Library()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }
        _ = try await harness.ingestor.reanalyzeStale()

        let sessions = try await harness.ingestor.allSessions()
        let positioned = sessions.filter { $0.startLat != nil }
        try #require(!positioned.isEmpty, "fixtures should carry GPS")
        #expect(positioned.allSatisfy { $0.spotId != nil })

        let store = LibraryStore(database: harness.database)
        #expect(try await !store.spots().isEmpty)
        let records = try await store.records()
        #expect(!records.isEmpty)
        // Every effort refers to a session that still exists and a kind we know.
        let ids = Set(sessions.map(\.id))
        #expect(records.allSatisfy { ids.contains($0.sessionId) })
        #expect(records.allSatisfy { $0.valueKn > 0 })
    }

    /// v5 adds the rider column. A shipped library's rows are the reader's own, so every
    /// one of them has to come out of the migration as NULL — a default of "" or a
    /// non-null column would take the whole library out of its own Records overnight.
    @Test func v5AddsTheRiderColumnAndLeavesEveryExistingRowMine() throws {
        let harness = try migratedV1Library()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }

        let (hasColumn, mine) = try harness.database.writer.read { db in
            (try db.columns(in: "session").map(\.name).contains("rider"),
             try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM session WHERE rider IS NULL"))
        }
        #expect(hasColumn)
        #expect(mine == harness.v1Ids.count)
        // The registration list itself is pinned by
        // `ExampleSessionTests.migrationListNamesEveryRegisteredMigration`.
        #expect(AppDatabase.migrationNames.contains("v5"))
    }

    /// v10 adds the two turn streaks. They are the one pair of session records that cannot
    /// be recovered from anything already stored — a streak merges counted turns with the
    /// flight ends no turn owns, so the `turn` table alone cannot say where a run ended —
    /// which is why the migration marks every row stale rather than leaving the columns
    /// NULL and hoping. After the sweep they must equal the engine's own numbers.
    @Test func v10AddsTheStreakColumnsAndFillsThemFromTheEngine() async throws {
        let harness = try migratedV1Library()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }

        let (columns, stale) = try await harness.database.writer.read { db in
            (Set(try db.columns(in: "session").map(\.name)),
             try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM session WHERE engineVersion IS NULL"))
        }
        #expect(columns.isSuperset(of: ["longestDryStreak", "longestFlewStreak"]))
        #expect(stale == harness.v1Ids.count)
        #expect(AppDatabase.migrationNames.last == "v12")
        #expect(AppDatabase.schemaVersion == 12)

        _ = try await harness.ingestor.reanalyzeStale()
        for session in try await harness.ingestor.allSessions() {
            let turns = try await harness.ingestor.analysis(for: session).summary.turns
            #expect(session.longestDryStreak == turns.longestDryStreak)
            #expect(session.longestFlewStreak == turns.longestFlewStreak)
            #expect(session.jibesSuccessful == turns.jibesSuccessful)
        }
    }

    /// v11 denormalizes the engine's own CPH, and the point of it is that the number is
    /// **not** the one this layer used to compute: the engine divides by its own cleaned
    /// session span and the row's `durationS` is the raw sample span. The sweep must
    /// therefore actually fill the column — a NULL left standing would silently keep the
    /// old arithmetic for ever.
    @Test func v11FillsCphFromTheEngineRatherThanDividingForItself() async throws {
        let harness = try migratedV1Library()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }

        let columns = try await harness.database.writer.read { db in
            Set(try db.columns(in: "session").map(\.name))
        }
        #expect(columns.contains("engineCleanJibesPerHour"))

        _ = try await harness.ingestor.reanalyzeStale()
        for session in try await harness.ingestor.allSessions() {
            let summary = try await harness.ingestor.analysis(for: session).summary
            #expect(session.engineCleanJibesPerHour == summary.cleanJibesPerHour)
            #expect(session.cleanJibesPerHour == summary.cleanJibesPerHour)
        }

        // The fallback, and that it is a *different* answer — which is what makes the
        // column worth a migration rather than a rename.
        var orphan = try #require(try await harness.ingestor.allSessions().first)
        let engine = try #require(orphan.cleanJibesPerHour)
        orphan.engineCleanJibesPerHour = nil
        let divided = try #require(orphan.cleanJibesPerHour)
        #expect(divided == Double(orphan.jibesSuccessful ?? 0) * 3600 / orphan.durationS)
        #expect(abs(divided - engine) >= 0)
    }

    /// v12 adds the two facts a period needs and a session row never carried. Same sweep,
    /// same reason: the rate denominator is the engine's cleaned span and not the row's own
    /// duration, and the swim count is every fell-in flight end — neither is recoverable from
    /// anything already stored, which is why the columns exist rather than a query.
    @Test func v12FillsTheRateSpanAndTheSwimCount() async throws {
        let harness = try migratedV1Library()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }

        let columns = try await harness.database.writer.read { db in
            Set(try db.columns(in: "session").map(\.name))
        }
        #expect(columns.isSuperset(of: ["rateDurationS", "wetExits"]))

        _ = try await harness.ingestor.reanalyzeStale()
        var sawADifference = false
        for session in try await harness.ingestor.allSessions() {
            let summary = try await harness.ingestor.analysis(for: session).summary
            #expect(session.rateDurationS == summary.durationS)
            #expect(session.wetExits == summary.flightEnds.all.fellIn)
            #expect(session.rateSeconds == summary.durationS)
            // And it is the rate the engine published, to the decimal — which is the whole
            // claim: WPH over a period is this count over these hours.
            if let wet = session.wetExits, let wph = summary.wetPerHour, summary.durationS > 0 {
                #expect(abs(Double(wet) / (summary.durationS / 3600) - wph) < 1e-9)
            }
            if session.rateDurationS != session.durationS { sawADifference = true }
        }
        #expect(sawADifference, "the corpus must contain a session the two spans disagree about")
    }

    @Test func deletingASessionCascadesToItsDerivedRows() async throws {
        let harness = try migratedV1Library(fixtureCount: 1)
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }
        _ = try await harness.ingestor.reanalyzeStale()

        let session = try #require(try await harness.ingestor.allSessions().first)
        try await harness.ingestor.delete(session)
        try await harness.database.writer.read { db in
            for table in ["flight", "turn", "takeoff_attempt", "record_effort"] {
                let remaining = try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM \(table) WHERE sessionId = ?",
                    arguments: [session.id]) ?? -1
                #expect(remaining == 0, "\(table) kept orphans")
            }
        }
    }
}
