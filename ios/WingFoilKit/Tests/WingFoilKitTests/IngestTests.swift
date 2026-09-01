import Foundation
import GRDB
import Testing
@testable import WingFoilKit

/// The library-side pipeline: FIT bytes → analysis → archive + `session` row, with the
/// ±60 s/±60 s dedupe key from plan §3.3 and lazy re-analysis on a stale cache.
@Suite struct IngestTests {

    private func makeIngestor() throws -> (SessionIngestor, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-tests-\(UUID().uuidString)/Sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (SessionIngestor(database: try AppDatabase.inMemory(),
                                archive: SessionArchive(root: root)), root)
    }

    private func fixtureData() throws -> (Data, String) {
        let url = try #require(allFixtureFITs().first, "no fixture FITs available")
        return (try Data(contentsOf: url), url.lastPathComponent)
    }

    /// Compare through the persisted representation: `GP3SRecords.totalDistanceM` is a
    /// derived convenience that the golden schema (and therefore `analysis.json`) omits.
    private func encoded(_ analysis: SessionAnalysis) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(analysis)
    }

    @Test func ingestArchivesAndIndexesASession() async throws {
        let (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let (data, name) = try fixtureData()

        guard case .imported(let row) = try await ingestor.ingest(
            fitData: data, filename: name, source: .file) else {
            Issue.record("expected a fresh import")
            return
        }

        // Immutable archive: original bytes untouched, analysis cached alongside.
        let archive = ingestor.archive
        #expect(try archive.originalData(for: row.id) == data)
        #expect(FileManager.default.fileExists(atPath: archive.analysisURL(for: row.id).path))

        let analysis = try #require(archive.analysis(for: row.id))
        let expected = SessionSummarizer.analyze(try FitSessionParser.parse(data: data))
        #expect(try encoded(analysis) == encoded(expected))

        // Denormalized summary columns mirror the analysis.
        #expect(row.engineVersion == AnalysisEngine.version)
        #expect(row.flightCount == expected.summary.flightCount)
        #expect(row.foilPct == expected.summary.foilPct)
        #expect(row.distanceKm == expected.summary.distanceKm)
        #expect(row.best2sKn == expected.records.best2sKn)
        #expect(row.originalFilename == name)
        #expect(row.importSource == "file")
        #expect(row.durationS > 0)
        #expect(try await ingestor.allSessions().count == 1)
    }

    @Test func sameSessionFromASecondSourceIsADuplicate() async throws {
        let (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let (data, name) = try fixtureData()

        _ = try await ingestor.ingest(fitData: data, filename: name, source: .file)
        let second = try await ingestor.ingest(fitData: data, filename: name, source: .icu,
                                               icuActivityId: "i9999")
        guard case .duplicate(let row) = second else {
            Issue.record("expected the second ingest to dedupe")
            return
        }
        // Skipped, but the note records that intervals.icu has it too.
        #expect(row.importSource == "file+icu")
        #expect(row.icuActivityId == "i9999")
        #expect(try await ingestor.allSessions().count == 1)
        #expect(try await ingestor.icuActivityIds() == ["i9999"])
        #expect(ingestor.archive.sessionDirectories().count == 1)
    }

    @Test func differentSessionsCoexist() async throws {
        let fits = allFixtureFITs()
        try #require(fits.count >= 2, "need two fixtures")
        let (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        for url in fits.prefix(2) {
            _ = try await ingestor.ingest(fitData: try Data(contentsOf: url),
                                          filename: url.lastPathComponent, source: .file)
        }
        let sessions = try await ingestor.allSessions()
        #expect(sessions.count == 2)
        // Library order is newest first.
        #expect(sessions[0].startDate >= sessions[1].startDate)
    }

    @Test func staleAnalysisIsRecomputedLazily() async throws {
        let (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let (data, name) = try fixtureData()
        guard case .imported(let row) = try await ingestor.ingest(
            fitData: data, filename: name, source: .file) else { return }

        ingestor.dropAllAnalyses()
        #expect(ingestor.archive.analysis(for: row.id) == nil)

        let recomputed = try await ingestor.analysis(for: row)
        #expect(recomputed.engineVersion == AnalysisEngine.version)
        let cached = try #require(ingestor.archive.analysis(for: row.id))   // cache rewritten
        #expect(try encoded(cached) == encoded(recomputed))
        #expect(ingestor.archive.diskUsageBytes() > Int64(data.count))
    }

    @Test func bulkImportGatesOnSport() async throws {
        let (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        // Jan's native Windsurf recordings qualify for bulk import; a Ride would not.
        var windsurf = SourceCapabilities()
        windsurf.sport = "windsurfing"
        #expect(SessionIngestor.isWatersport(windsurf))

        var ciqWalk = SourceCapabilities()          // FoilMotion & co. record as Walk …
        ciqWalk.sport = "walking"
        #expect(!SessionIngestor.isWatersport(ciqWalk))
        ciqWalk.discipline = "wingfoil"             // … but our discipline tag rescues them
        #expect(SessionIngestor.isWatersport(ciqWalk))

        var cycling = SourceCapabilities()
        cycling.sport = "cycling"
        #expect(!SessionIngestor.isWatersport(cycling))

        // A hand-picked single FIT is always accepted, whatever its sport says.
        let (data, name) = try fixtureData()
        let summary = await ingestor.ingestContainer(data: data, name: name, source: .file)
        #expect(summary.imported == 1)
        #expect(summary.failed.isEmpty)
    }

    @Test func deleteRemovesRowAndArchive() async throws {
        let (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let (data, name) = try fixtureData()
        guard case .imported(let row) = try await ingestor.ingest(
            fitData: data, filename: name, source: .file) else { return }

        try await ingestor.delete(row)
        #expect(try await ingestor.allSessions().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: ingestor.archive.directory(for: row.id).path))
    }

    // MARK: - GPX (engine 0.9.0, input class c)

    /// A GPX walks the same path a FIT does — and comes out labelled for what it is.
    ///
    /// The end-to-end claim of engine 0.9.0, asserted where it can actually be broken: the
    /// row carries `sourceClass` "c", so every consumer that reads that column reaches the
    /// uncertified treatment without being told about GPX at all.
    @Test func aGpxIngestsAsAClassCSession() async throws {
        let (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let url = try #require(findFixtureTrack(stem: "2026-08-30-1407_nago-torbole"),
                               "no GPX fixture available")
        let data = try Data(contentsOf: url)

        guard case .imported(let row) = try await ingestor.ingest(
            fitData: data, filename: url.lastPathComponent, source: .file) else {
            Issue.record("expected a fresh import")
            return
        }

        #expect(row.sourceClass == "c")
        #expect(row.engineVersion == AnalysisEngine.version)
        #expect(row.flightCount == 2)
        #expect(row.durationS > 0)
        #expect((row.best2sKn ?? 0) > 0)
        // No accelerometer, so no pump answer at all — never a zero, which would read as
        // "he got up without pumping".
        #expect(row.totalPumpStrokes == nil || row.totalPumpStrokes == 0)

        // The archive keeps the recording under its own extension: these bytes get handed
        // back out, and a GPX filed as `original.fit` is a lie that reaches a mailbox.
        let archive = ingestor.archive
        #expect(archive.originalURL(for: row.id).lastPathComponent == "original.gpx")
        #expect(try archive.originalData(for: row.id) == data)
        #expect(archive.originalFormat(for: row.id) == .gpx)
        // …and re-reading it produces the same track, so lazy re-analysis works from disk.
        let reread = try archive.rawTrack(for: row.id)
        #expect(reread.capabilities.sourceClass == "c")
        #expect(reread.samples.count == 640)
    }

    /// The uncertified treatment, end to end from the ingested row.
    ///
    /// A share card is the one surface that leaves the app, so it is the one that must
    /// carry the disclaimer; `certified` is what keeps a class-(c) effort out of the
    /// personal-best celebration. Both read the same column the ingest just wrote.
    @Test func aGpxSessionsRecordsAreTreatedAsUncertified() async throws {
        let (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let url = try #require(findFixtureTrack(stem: "2026-08-30-1407_nago-torbole"))
        guard case .imported(let row) = try await ingestor.ingest(
            fitData: try Data(contentsOf: url), filename: url.lastPathComponent,
            source: .file) else { return }

        let card = ShareCardStats.make(row: row, title: "Nago-Torbole",
                                       timeZone: row.displayZone)
        #expect(card.disclaimer == "Speeds from a degraded source — uncertified")

        let best = try await LibraryStore(database: ingestor.database).records()
        #expect(!best.isEmpty)
        #expect(best.allSatisfy { $0.sourceClass == "c" })
        #expect(best.allSatisfy { !$0.certified })
        // A class-(c) effort is never celebrated as a personal best, even against a
        // snapshot it beats outright — a degraded source can read high, and confetti is
        // exactly the wrong answer to a bad speed sample.
        let previous = PersonalBestSnapshot(bestByKind: ["best2s": 1.0, "best10s": 1.0])
        #expect(PersonalBestDetector.improvements(previous: previous, current: best).isEmpty)
    }
}
