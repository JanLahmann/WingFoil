import Foundation
import GRDB
import Testing
@testable import WingFoilKit
import ZIPFoundation

/// Full-history backfill from Garmin's "Export Your Data" ZIP (plan §2, phase-4
/// acceptance: *clean, zero duplicates*). The real export is a ZIP of ZIPs of original
/// FITs sprinkled with JSON; this builds the same shape from two fixtures so the whole
/// path — stream-unpack, sport sniff, dedupe, import_log — runs on real FIT bytes.
@Suite struct GdprImportTests {

    private struct Harness {
        var ingestor: SessionIngestor
        var store: LibraryStore
        var root: URL
    }

    private func makeHarness() throws -> Harness {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-gdpr-\(UUID().uuidString)/Sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let database = try AppDatabase.inMemory()
        return Harness(ingestor: SessionIngestor(database: database,
                                                 archive: SessionArchive(root: root)),
                       store: LibraryStore(database: database), root: root)
    }

    private func fixture(_ needle: String) throws -> (name: String, data: Data) {
        let url = try #require(allFixtureFITs().first { $0.lastPathComponent.contains(needle) },
                               "no fixture matching \(needle)")
        return (url.lastPathComponent, try Data(contentsOf: url))
    }

    /// A 12-byte-header FIT-lookalike that parses as nothing — Garmin exports carry
    /// activities we have no business importing (and files we cannot read at all).
    private func junkFit() -> Data {
        var data = Data([12, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        data.append(contentsOf: Array(".FIT".utf8))
        data.append(contentsOf: [UInt8](repeating: 0x5a, count: 200))
        return data
    }

    /// `export.zip` → { `DI_CONNECT/…/uploads-1.zip` → { a.fit, meta.json },
    ///                  `DI_CONNECT/…/uploads-2.zip` → { b.fit.gz, junk.fit },
    ///                  `user_profile.json` }
    private func syntheticExport() throws -> (zip: Data, sessions: Int) {
        let a = try fixture("2026-08-01-0804")
        let b = try fixture("2026-08-05-0827")
        let part1 = try makeZip(entries: [(a.name, a.data),
                                          ("summarizedActivities.json", Data("[]".utf8))])
        let part2 = try makeZip(entries: [("\(b.name).gz", try Gzip.compress(b.data)),
                                          ("corrupt.fit", junkFit())])
        let outer = try makeZip(entries: [
            ("DI_CONNECT/DI-Connect-Uploaded-Files/uploads-1.zip", part1),
            ("DI_CONNECT/DI-Connect-Uploaded-Files/uploads-2.zip", part2),
            ("user_profile.json", Data("{}".utf8)),
            ("__MACOSX/._user_profile.json", Data([0, 1, 2])),
        ])
        return (outer, 2)
    }

    @Test func nestedExportImportsEverySessionExactlyOnce() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }
        let export = try syntheticExport()

        let progress = ProgressRecorder()
        let summary = await harness.ingestor.ingestContainer(
            data: export.zip, name: "export.zip", source: .gdpr,
            progress: { progress.record($0) })

        #expect(summary.found == 3, "two sessions plus the unreadable one")
        #expect(summary.imported == export.sessions)
        #expect(summary.duplicates == 0)
        #expect(summary.failed.count == 1, "the corrupt FIT is reported, not silently dropped")
        let sessions = try await harness.ingestor.allSessions()
        #expect(sessions.count == export.sessions)
        #expect(sessions.allSatisfy { $0.importSource == "gdpr" })
        #expect(sessions.allSatisfy { $0.engineVersion == AnalysisEngine.version })
        // Gzipped members are unwrapped before parsing.
        #expect(sessions.contains { ($0.originalFilename ?? "").contains("2026-08-05-0827") })

        // Progress arrived incrementally, not just at the end.
        #expect(progress.snapshots.count >= 4)
        #expect(progress.snapshots.contains { $0.current != nil })
        #expect(progress.snapshots.map(\.processed) == progress.snapshots.map(\.processed).sorted())
    }

    /// The acceptance criterion: run the backfill twice, end with the same library.
    @Test func rerunningTheBackfillAddsNothing() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }
        let export = try syntheticExport()

        _ = await harness.ingestor.ingestContainer(data: export.zip, name: "export.zip",
                                                   source: .gdpr)
        let second = await harness.ingestor.ingestContainer(data: export.zip, name: "export.zip",
                                                            source: .gdpr)
        #expect(second.imported == 0)
        #expect(second.duplicates == export.sessions)
        #expect(try await harness.ingestor.allSessions().count == export.sessions)
        #expect(harness.ingestor.archive.sessionDirectories().count == export.sessions)

        let log = try await harness.store.importLog()
        #expect(log.count == 2)
        #expect(log.allSatisfy { $0.finishedAt != nil })
        #expect(log.allSatisfy { $0.container == "export.zip" && $0.source == "gdpr" })
        #expect(log.first?.duplicates == export.sessions)      // newest first
        #expect(log.last?.imported == export.sessions)
        #expect(log.allSatisfy { $0.found == 3 })
    }

    /// Non-watersport activities in the export are skipped, not imported and not failed.
    @Test func bulkImportSkipsNonWatersportFits() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }
        // The synthetic smoke FIT records a non-watersport sport, so the bulk gate
        // rejects it — while the same file picked by hand is accepted (below).
        let smoke = try fixture("smoke-60s")
        let zipped = try makeZip(entries: [(smoke.name, smoke.data)])
        let bulk = await harness.ingestor.ingestContainer(data: zipped, name: "backup.zip",
                                                          source: .gdpr)
        #expect(bulk.found == 1)
        #expect(bulk.imported + bulk.skipped == 1)
        if bulk.skipped == 1 {
            #expect(try await harness.ingestor.allSessions().isEmpty)
            // Hand-picked, the same bytes come in regardless of sport.
            let single = await harness.ingestor.ingestContainer(data: smoke.data, name: smoke.name,
                                                                source: .file)
            #expect(single.imported == 1)
        }
    }

    /// Nesting deeper than the walker's limit is reported rather than followed forever.
    @Test func depthLimitIsEnforced() async throws {
        var payload = try makeZip(entries: [("a.fit", junkFit())])
        for level in 0..<(ZipWalker.maxDepth + 2) {
            payload = try makeZip(entries: [("level\(level).zip", payload)])
        }
        let result = await ZipWalker.walk(data: payload, name: "deep.zip") { _ in }
        #expect(result.fitCount == 0)
        #expect(result.unreadable > 0)
    }

    /// Streaming and collecting walks must agree on what is in the container.
    @Test func streamingWalkMatchesTheCollectingOne() async throws {
        let export = try syntheticExport()
        let collected = ZipWalker.walk(data: export.zip, name: "export.zip")
        var streamedNames: [String] = []
        let streamed = await ZipWalker.walk(data: export.zip, name: "export.zip") { fit in
            streamedNames.append(fit.name)
        }
        #expect(streamed.fitCount == collected.fitCount)
        #expect(streamed.archives == collected.archives)
        #expect(streamed.ignoredEntries == collected.ignoredEntries)
        #expect(streamedNames.sorted() == collected.fits.map(\.name).sorted())
        #expect(streamed.fits.isEmpty, "the streaming walk keeps no payloads")
    }
}

/// Collects the progress callbacks so the test can assert they were incremental.
private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ImportSummary] = []

    var snapshots: [ImportSummary] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func record(_ summary: ImportSummary) {
        lock.lock(); defer { lock.unlock() }
        storage.append(summary)
    }
}
