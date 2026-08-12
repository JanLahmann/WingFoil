import Foundation
import GRDB
import Testing
@testable import WingFoilKit

/// The bundled example session (task #30): the scrub, the `isExample` flag, and the
/// promise the flag makes — that a borrowed session never shows up in a number claiming to
/// be about the rider.
///
/// The scrub half reads the **bundle**, not the file in the repo, because what matters is
/// what actually ships. `lab/tools/scrub_fit.py` proves the analysis is unchanged; this
/// suite proves the identifiers are gone from the bytes Xcode installed.
@Suite struct ExampleSessionTests {

    private struct Harness {
        var ingestor: SessionIngestor
        var store: LibraryStore
        var root: URL
    }

    private func makeHarness() throws -> Harness {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-example-\(UUID().uuidString)/Sessions",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let database = try AppDatabase.inMemory()
        return Harness(ingestor: SessionIngestor(database: database,
                                                 archive: SessionArchive(root: root)),
                       store: LibraryStore(database: database), root: root)
    }

    private func cleanup(_ harness: Harness) {
        try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent())
    }

    // MARK: - The bundled bytes

    @Test func exampleIsBundledAndReadable() throws {
        let data = try ExampleSession.data()
        #expect(data.count > 100_000, "the bundled example is suspiciously small")
        // A FIT file announces itself in bytes 8..11 — a resource that was mangled by the
        // build (text encoding, line endings) fails here rather than at run time.
        #expect(Array(data[8..<12]) == Array("\u{2E}FIT".utf8))
    }

    /// The whole point of `scrub_fit.py`. Asserted on the *shipped* bytes: no serial
    /// number, no rider name, no paired-accessory name, anywhere in the file.
    @Test func bundledExampleCarriesNoIdentifiers() throws {
        let data = try ExampleSession.data()

        // 1. Nothing that parses as a serial number survives.
        let track = try FitSessionParser.parse(data: data)
        #expect(track.capabilities.sourceClass == "a", "the example must stay class (a)")

        // 2. No identifying string anywhere in the raw bytes. The rider's own name and the
        //    paired accessory's name were both in the original; the watch serial number is
        //    a uint32 and is checked in both byte orders.
        for needle in ["Lahmann", "Jan-Rainer", "AirPods", "JRL"] {
            #expect(data.range(of: Data(needle.utf8)) == nil,
                    "the bundled example still contains \"\(needle)\"")
        }
        let serial: UInt32 = 3_489_711_811
        let little = withUnsafeBytes(of: serial.littleEndian) { Data($0) }
        let big = withUnsafeBytes(of: serial.bigEndian) { Data($0) }
        #expect(data.range(of: little) == nil, "the watch serial number survives (LE)")
        #expect(data.range(of: big) == nil, "the watch serial number survives (BE)")
    }

    /// The scrub is only worth anything if the session still *shows* something. These are
    /// the numbers the help topic and the setup card promise a first-time reader.
    @Test func exampleStillAnalysesToARealSession() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }

        guard case .imported(let row) = try await harness.ingestor.importExample() else {
            Issue.record("the example did not import")
            return
        }
        #expect(row.durationS > 3_000)                       // ~69 minutes
        #expect((row.distanceKm ?? 0) > 10)
        #expect((row.flightCount ?? 0) >= 20)
        #expect((row.jibes ?? 0) >= 25)
        #expect((row.best2sKn ?? 0) > 10)
        #expect(row.hasAccel == true)                        // pump counts survive
        #expect(row.hasHR == true)                           // Jan consented to the HR stream
        #expect((row.totalPumpStrokes ?? 0) > 500)
        #expect(row.windDirDeg != nil)
        #expect(row.startLat != nil && row.startLon != nil)   // Lake Garda track intact

        // Child tables filled the same way any import fills them.
        let counts = try await harness.ingestor.database.writer.read { db in
            (flights: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM flight") ?? 0,
             turns: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM turn") ?? 0,
             efforts: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM record_effort") ?? 0)
        }
        #expect(counts.flights >= 20)
        #expect(counts.turns >= 25)
        #expect(counts.efforts > 0)
    }

    // MARK: - The flag

    @Test func importingTheExampleSetsTheFlagAndTheSource() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }

        guard case .imported(let row) = try await harness.ingestor.importExample() else {
            Issue.record("the example did not import")
            return
        }
        #expect(row.isExample)
        #expect(row.importSource == ImportSource.example.rawValue)
        #expect(row.originalFilename == ExampleSession.filename)

        // The flag round-trips through SQLite, not just through the in-memory struct.
        let stored = try #require(try await harness.ingestor.session(id: row.id))
        #expect(stored.isExample)

        // It is in the library like anything else …
        #expect(try await harness.ingestor.allSessions().count == 1)
        // … and deletable like anything else.
        try await harness.ingestor.delete(stored)
        #expect(try await harness.ingestor.allSessions().isEmpty)
    }

    /// The promise the badge makes. Records, Trends and the week histogram all funnel
    /// through `LibraryStore.clause`, so one example in an otherwise empty library must
    /// leave every one of them empty.
    @Test func theExampleIsInvisibleToRecordsAndTrends() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }

        guard case .imported = try await harness.ingestor.importExample() else {
            Issue.record("the example did not import")
            return
        }
        // It produced record efforts — they exist in the table …
        let effortRows = try await harness.ingestor.database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM record_effort") ?? 0
        }
        #expect(effortRows > 0)
        // … but no screen that speaks for the rider can see them.
        #expect(try await harness.store.records().isEmpty)
        #expect(try await harness.store.trend().isEmpty)
        #expect(try await harness.store.sessions().isEmpty)
        #expect(try await harness.store.weeks().isEmpty)

        // Gear rollups too: an example was not ridden on the rider's kit, so it is not
        // given the default combo and not counted if one is attached anyway.
        let gear = GearRow(name: "Test wing", kind: .wing)
        try await harness.store.saveGear(gear)
        let row = try #require(try await harness.ingestor.allSessions().first)
        try await harness.store.assignGear(sessionId: row.id, kind: .wing, gearId: gear.id)
        let aggregate = try #require(try await harness.store.gearAggregates().first)
        #expect(aggregate.sessions == 0)
    }

    /// A real session in the same library is completely unaffected — the filter keys on
    /// the flag, not on "the newest row" or on the source class.
    @Test func realSessionsStillReachRecordsAlongsideTheExample() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }

        let url = try #require(allFixtureFITs().first { $0.lastPathComponent.contains("2026-08-05") },
                               "no non-example fixture to pair with")
        let data = try Data(contentsOf: url)
        guard case .imported = try await harness.ingestor.ingest(
            fitData: data, filename: url.lastPathComponent, source: .file) else {
            Issue.record("the real fixture did not import")
            return
        }
        _ = try await harness.ingestor.importExample()

        #expect(try await harness.ingestor.allSessions().count == 2)
        #expect(try await harness.store.sessions().count == 1)
        #expect(try await harness.store.trend().count == 1)
        #expect(try await harness.store.records().isEmpty == false)
        for record in try await harness.store.records() {
            let owner = try #require(try await harness.ingestor.session(id: record.sessionId))
            #expect(!owner.isExample, "an example effort reached the records screen")
        }
    }

    // MARK: - Dedupe

    /// The interaction that needed a decision: the example *is* a real recording, so the
    /// rider who made it will one day import it for real and land on the ±60 s dedupe key.
    ///
    /// Decision: the real import wins. The row is promoted (flag cleared, sources merged)
    /// and rejoins Records and Trends, rather than the rider's own session being
    /// permanently excluded because a demo happened to get there first.
    @Test func aRealImportOfTheSameSessionPromotesTheExample() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }

        guard case .imported(let example) = try await harness.ingestor.importExample() else {
            Issue.record("the example did not import")
            return
        }
        #expect(example.isExample)
        #expect(try await harness.store.records().isEmpty)

        // The unscrubbed original: same start, same duration — the dedupe key matches.
        let original = try #require(
            allFixtureFITs().first { $0.lastPathComponent.contains("2026-08-07-0754") },
            "the example's source fixture is missing from the corpus")
        let outcome = try await harness.ingestor.ingest(
            fitData: try Data(contentsOf: original),
            filename: original.lastPathComponent, source: .icu, icuActivityId: "i42")
        guard case .duplicate(let merged) = outcome else {
            Issue.record("the real import did not dedupe against the example")
            return
        }
        #expect(!merged.isExample, "the rider's own session is still flagged as an example")
        #expect(merged.importSource == "example+icu")
        #expect(merged.icuActivityId == "i42")
        #expect(try await harness.ingestor.allSessions().count == 1)
        // Promoted rows count immediately: the efforts were already derived.
        #expect(try await harness.store.records().isEmpty == false)
        #expect(try await harness.store.sessions().count == 1)
    }

    /// The other direction must not fire: tapping "load the example" when the rider
    /// already owns that ride leaves their session alone and adds nothing.
    @Test func loadingTheExampleNeverDemotesARealSession() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }

        let original = try #require(
            allFixtureFITs().first { $0.lastPathComponent.contains("2026-08-07-0754") })
        guard case .imported(let real) = try await harness.ingestor.ingest(
            fitData: try Data(contentsOf: original),
            filename: original.lastPathComponent, source: .icu, icuActivityId: "i42") else {
            Issue.record("the real fixture did not import")
            return
        }
        #expect(!real.isExample)

        guard case .duplicate(let after) = try await harness.ingestor.importExample() else {
            Issue.record("the example did not dedupe against the rider's own import")
            return
        }
        #expect(!after.isExample)
        #expect(try await harness.ingestor.allSessions().count == 1)
        #expect(try await harness.store.records().isEmpty == false)
    }

    // MARK: - Schema

    @Test func v3AddsTheFlagAndDefaultsExistingRowsToFalse() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v2")
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO session (id, startDate, durationS, sourceClass)
                VALUES ('legacy', ?, 1200, 'a')
                """, arguments: [Date(timeIntervalSince1970: 1_770_000_000)])
        }
        let beforeColumns = try queue.read { db in Set(try db.columns(in: "session").map(\.name)) }
        #expect(!beforeColumns.contains("isExample"))

        _ = try AppDatabase(queue)                          // ← runs v3
        let afterColumns = try queue.read { db in Set(try db.columns(in: "session").map(\.name)) }
        #expect(afterColumns.contains("isExample"))

        let migrated = try #require(try queue.read { db in
            try SessionRow.fetchOne(db, key: "legacy")
        })
        #expect(!migrated.isExample, "a pre-v3 session must not become an example")
    }

    @Test func migrationListNamesEveryRegisteredMigration() throws {
        #expect(AppDatabase.migrationNames == ["v1", "v2", "v3"])
        let queue = try DatabaseQueue()
        _ = try AppDatabase(queue)
        let applied = try queue.read { db in try AppDatabase.migrator.appliedMigrations(db) }
        #expect(applied == AppDatabase.migrationNames)
    }

    // MARK: - What the UI promises

    @Test func exampleCopyIsWrittenAndPointsAtTheRealFile() {
        #expect(ExampleSession.filename.hasSuffix("_example.fit"))
        // SessionDisplay.title reads the middle `_`-separated component, so the library row
        // is only readable if the filename keeps that shape.
        #expect(ExampleSession.filename.split(separator: "_").count == 3)
        #expect(ExampleSession.blurb.count > 60)
        #expect(!ExampleSession.place.isEmpty)

        let topic = HelpCatalog.topic(.exampleSession)
        #expect(topic.section == .setup)
        #expect(topic.action == .loadExampleSession)
        #expect(topic.body.count >= 3)
        let prose = topic.body.joined(separator: " ")
        // The three facts a reader needs: it is real, it is not theirs, and it is scrubbed.
        #expect(prose.contains("EXAMPLE"))
        #expect(prose.lowercased().contains("records"))
        #expect(prose.lowercased().contains("serial"))
        #expect(HelpCatalog.search("example").contains { $0.id == .exampleSession })
    }
}
