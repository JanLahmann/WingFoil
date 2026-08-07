import Foundation
import GRDB
import Testing
@testable import WingFoilKit
import ZIPFoundation

/// Phase-4 library depth: the dedupe key under jitter, spot auto-clustering, the
/// `record_effort` PB history, and the gear rollups the Gear screen shows.
@Suite struct LibraryTests {

    private struct Harness {
        var ingestor: SessionIngestor
        var store: LibraryStore
        var root: URL
    }

    private func makeHarness() throws -> Harness {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-library-\(UUID().uuidString)/Sessions",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let database = try AppDatabase.inMemory()
        return Harness(ingestor: SessionIngestor(database: database,
                                                 archive: SessionArchive(root: root)),
                       store: LibraryStore(database: database), root: root)
    }

    private func fixture(_ needle: String) throws -> (Data, String) {
        let url = try #require(allFixtureFITs().first { $0.lastPathComponent.contains(needle) },
                               "no fixture matching \(needle)")
        return (try Data(contentsOf: url), url.lastPathComponent)
    }

    // MARK: - Dedupe

    /// Plan §3.3: start within ±60 s **and** duration within ±60 s. The same recording
    /// reaches the library as icu-downloaded bytes, as a GDPR ZIP member and over AirDrop,
    /// and the three disagree by a few seconds of rounding — but never by two minutes.
    @Test func dedupeKeyAbsorbsJitterAndStopsAtTheTolerance() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }
        let (data, name) = try fixture("2026-08-05-0827")

        guard case .imported(let first) = try await harness.ingestor.ingest(
            fitData: data, filename: name, source: .icu, icuActivityId: "i1") else {
            Issue.record("expected a fresh import"); return
        }

        // Byte-identical re-download of the same activity.
        guard case .duplicate = try await harness.ingestor.ingest(
            fitData: data, filename: name, source: .icu, icuActivityId: "i1") else {
            Issue.record("identical bytes must dedupe"); return
        }

        // Now pretend the stored copy arrived from a source that rounded differently:
        // 45 s later, 40 s shorter. Still the same session.
        try await shift(harness, id: first.id, seconds: 45, durationDelta: -40)
        guard case .duplicate(let merged) = try await harness.ingestor.ingest(
            fitData: data, filename: name, source: .gdpr) else {
            Issue.record("jitter inside ±60 s must dedupe"); return
        }
        #expect(merged.importSource == "gdpr+icu")
        #expect(try await harness.ingestor.allSessions().count == 1)

        // Two minutes out is a different session, and the library says so.
        try await shift(harness, id: first.id, seconds: 120, durationDelta: 0)
        guard case .imported = try await harness.ingestor.ingest(
            fitData: data, filename: name, source: .gdpr) else {
            Issue.record("beyond the tolerance it is a new session"); return
        }
        #expect(try await harness.ingestor.allSessions().count == 2)
    }

    /// Rewrites the stored dedupe key of one session (the archived FIT stays untouched).
    private func shift(_ harness: Harness, id: String, seconds: TimeInterval,
                       durationDelta: Double) async throws {
        try await harness.ingestor.database.writer.write { db in
            guard let row = try SessionRow.fetchOne(db, key: id) else { return }
            var updated = row
            updated.startDate = row.startDate.addingTimeInterval(seconds)
            updated.durationS = row.durationS + durationDelta
            try updated.update(db)
        }
    }

    /// The GDPR bulk path must not re-import what intervals.icu already downloaded.
    @Test func gdprContainerOfAKnownSessionImportsNothing() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }
        let (data, name) = try fixture("2026-08-05-0827")
        _ = try await harness.ingestor.ingest(fitData: data, filename: name, source: .icu,
                                              icuActivityId: "i7")

        let zipped = try makeZip(entries: [(name, data)])
        let summary = await harness.ingestor.ingestContainer(data: zipped, name: "export.zip",
                                                             source: .gdpr)
        #expect(summary.found == 1)
        #expect(summary.imported == 0)
        #expect(summary.duplicates == 1)
        #expect(try await harness.ingestor.allSessions().count == 1)
    }

    // MARK: - Spots

    @Test func clustererSeparatesPlacesAndMergesOneBeach() {
        // Two rig-up spots 40 m apart on the same beach, and a lake 300 km away.
        let fixes = [
            SpotClusterer.Fix(sessionId: "a", lat: 45.8760, lon: 10.8720),
            SpotClusterer.Fix(sessionId: "b", lat: 45.8763, lon: 10.8724),
            SpotClusterer.Fix(sessionId: "c", lat: 48.9800, lon: 8.3200),
            SpotClusterer.Fix(sessionId: "d", lat: 45.8758, lon: 10.8717),
        ]
        let clusters = SpotClusterer.cluster(fixes)
        #expect(clusters.count == 2)
        #expect(clusters[0].sessionIds.sorted() == ["a", "b", "d"])
        #expect(clusters[1].sessionIds == ["c"])
        // Centroid stays on the beach it describes.
        #expect(SpotClusterer.distance(lat1: clusters[0].lat, lon1: clusters[0].lon,
                                       lat2: 45.8760, lon2: 10.8720) < 50)
        // A radius below the beach's own spread splits it again.
        #expect(SpotClusterer.cluster(fixes, radiusM: 20).count > 2)
    }

    @Test func realFixturesClusterIntoGardaAndRheinstetten() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }
        for needle in ["2026-06-13-1558", "2026-08-05-0827", "2026-08-01-0804"] {
            let (data, name) = try fixture(needle)
            _ = try await harness.ingestor.ingest(fitData: data, filename: name, source: .file)
        }
        let spots = try await harness.store.spots()
        #expect(spots.count == 2, "Rheinstetten and Nago-Torbole are different places")
        #expect(spots.map(\.sessions).sorted() == [1, 2])
        // Offline fallback naming: no geocoder, so placeholders — and they are unique.
        #expect(Set(spots.map(\.spot.name)).count == 2)
        #expect(spots.allSatisfy { $0.spot.autoNamed })

        // A rename sticks, and survives a re-cluster.
        let garda = try #require(spots.max { $0.sessions < $1.sessions })
        try await harness.store.renameSpot(id: garda.id, to: "Torbole")
        try await harness.store.recluster()
        let after = try await harness.store.spots()
        #expect(after.count == 2)
        #expect(after.contains { $0.spot.name == "Torbole" && !$0.spot.autoNamed })
        #expect(after.first { $0.spot.name == "Torbole" }?.sessions == garda.sessions)

        // Filtering the library by spot returns exactly that spot's sessions.
        let filtered = try await harness.store.sessions(LibraryFilter(spotId: garda.id))
        #expect(filtered.count == garda.sessions)
    }

    /// A spot never comes from nowhere: an auto name only fills in when the resolver
    /// answers, and a resolver that fails (offline) leaves the placeholder alone.
    @Test func autoNamingIsBestEffort() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }
        let (data, name) = try fixture("2026-08-05-0827")
        _ = try await harness.ingestor.ingest(fitData: data, filename: name, source: .file)

        try await harness.store.nameAutoSpots { _, _ in nil }          // offline
        #expect(try await harness.store.spots().first?.spot.name.hasPrefix("Spot") == true)

        try await harness.store.nameAutoSpots { _, _ in "Nago-Torbole" }
        let named = try #require(try await harness.store.spots().first)
        #expect(named.spot.name == "Nago-Torbole")
        #expect(named.spot.autoNamed, "still machine-made: a rename is what clears the flag")
    }

    // MARK: - Records / PB history

    @Test func recordEffortsCarryThePbHistory() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }
        var expected2s: [Double] = []
        for needle in ["2026-08-01-0804", "2026-08-05-0827", "2026-06-13-1558"] {
            let (data, name) = try fixture(needle)
            guard case .imported(let row) = try await harness.ingestor.ingest(
                fitData: data, filename: name, source: .file) else { continue }
            if let best = row.best2sKn { expected2s.append(best) }
        }
        try #require(expected2s.count == 3)

        let records = try await harness.store.records()
        let best2s = try #require(records.first { $0.kind == .best2s })
        #expect(abs(best2s.valueKn - expected2s.max()!) < 0.001)
        #expect(best2s.history.count == 3)
        // History is chronological, and the PB step curve is strictly increasing.
        #expect(best2s.history.map(\.achievedAt) == best2s.history.map(\.achievedAt).sorted())
        let pbs = best2s.personalBests.map(\.valueKn)
        #expect(pbs.first == best2s.history.first?.valueKn)
        #expect(pbs.last == best2s.valueKn)
        #expect(zip(pbs, pbs.dropFirst()).allSatisfy { $0 < $1 })
        // Provenance survives, so a record row can jump to the effort on the map.
        #expect(best2s.window != nil)
        #expect(best2s.certified, "native Doppler FITs are class (b)")

        // Every kind present is genuinely achieved — an unreachable window has no row
        // rather than a flattering 0.0 kn.
        #expect(records.allSatisfy { $0.valueKn >= 0.05 })
        #expect(!records.contains { $0.kind == .bestHour }, "no fixture is an hour long")

        // Filtering by a spot narrows the all-time best to that spot's sessions.
        let spots = try await harness.store.spots()
        let single = try #require(spots.min { $0.sessions < $1.sessions })
        let atSpot = try await harness.store.records(LibraryFilter(spotId: single.id))
        #expect(atSpot.first { $0.kind == .best2s }?.history.count == 1)
        #expect((atSpot.first { $0.kind == .best2s }?.valueKn ?? 0) <= best2s.valueKn)
    }

    @Test func reanalysisRewritesEffortsInsteadOfAppending() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }
        let (data, name) = try fixture("2026-08-05-0827")
        guard case .imported(let row) = try await harness.ingestor.ingest(
            fitData: data, filename: name, source: .file) else { return }
        let before = try await harness.store.records()

        harness.ingestor.dropAllAnalyses()
        _ = try await harness.ingestor.reanalyze(row)

        let after = try await harness.store.records()
        #expect(after.count == before.count)
        #expect(after.allSatisfy { $0.history.count == 1 })
    }

    // MARK: - Gear

    @Test func gearCombosDefaultToTheLastUsedAndRollUp() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }

        let wing = GearRow(name: "Duotone Unit 5 m", kind: .wing)
        let board = GearRow(name: "Armstrong DW 75 l", kind: .board)
        let foil = GearRow(name: "Armstrong HA 925", kind: .foil)
        let smallWing = GearRow(name: "Duotone Unit 4 m", kind: .wing)
        for item in [wing, board, foil, smallWing] { try await harness.store.saveGear(item) }
        #expect(try await harness.store.gear(kind: .wing).count == 2)

        // First session: nothing used yet, so nothing is assumed.
        let (dataA, nameA) = try fixture("2026-08-01-0804")
        guard case .imported(let first) = try await harness.ingestor.ingest(
            fitData: dataA, filename: nameA, source: .file) else { return }
        #expect(try await harness.store.gearOfSession(first.id).isEmpty)

        try await harness.store.assignGear(sessionId: first.id, kind: .wing, gearId: wing.id)
        try await harness.store.assignGear(sessionId: first.id, kind: .board, gearId: board.id)
        try await harness.store.assignGear(sessionId: first.id, kind: .foil, gearId: foil.id)

        // Second session inherits the combo …
        let (dataB, nameB) = try fixture("2026-08-05-0827")
        guard case .imported(let second) = try await harness.ingestor.ingest(
            fitData: dataB, filename: nameB, source: .file) else { return }
        let inherited = try await harness.store.gearOfSession(second.id)
        #expect(inherited[.wing]?.id == wing.id)
        #expect(inherited[.foil]?.id == foil.id)

        // … and swapping one slot replaces it rather than adding a second wing.
        try await harness.store.assignGear(sessionId: second.id, kind: .wing, gearId: smallWing.id)
        let swapped = try await harness.store.gearOfSession(second.id)
        #expect(swapped[.wing]?.id == smallWing.id)
        #expect(swapped.count == 3)

        let aggregates = try await harness.store.gearAggregates()
        let boardStats = try #require(aggregates.first { $0.gear.id == board.id })
        #expect(boardStats.sessions == 2)
        #expect(boardStats.hours > 0)
        #expect(boardStats.foilPct != nil)
        #expect(aggregates.first { $0.gear.id == wing.id }?.sessions == 1)
        #expect(aggregates.first { $0.gear.id == smallWing.id }?.sessions == 1)

        // Per-gear filtering reaches the records and the trend the same way.
        let onSmallWing = try await harness.store.records(LibraryFilter(gearId: smallWing.id))
        #expect(onSmallWing.first { $0.kind == .best2s }?.history.count == 1)
        #expect(try await harness.store.trend(LibraryFilter(gearId: board.id)).count == 2)
    }

    // MARK: - Trends

    @Test func weekBucketsZeroFillTheGaps() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }
        for needle in ["2026-06-13-1558", "2026-08-05-0827"] {
            let (data, name) = try fixture(needle)
            _ = try await harness.ingestor.ingest(fitData: data, filename: name, source: .file)
        }
        let rows = try await harness.store.sessions()
        let last = try #require(rows.last?.startDate)
        let weeks = LibraryStore.weeks(rows, since: nil, until: last)
        #expect(weeks.count > 5, "mid-June to early August is more than five weeks")
        #expect(weeks.filter { $0.count > 0 }.count == 2)
        #expect(weeks.contains { $0.count == 0 }, "quiet weeks are part of the trend")
        #expect(weeks.map(\.weekStart) == weeks.map(\.weekStart).sorted())

        let points = try await harness.store.trend()
        #expect(points.count == 2)
        #expect(points.allSatisfy { $0.foilPct != nil })
        // No accelerometer in a native Windsurf FIT: pumps stay unknown, never 0.
        #expect(points.allSatisfy { $0.avgPumpsToTakeoff == nil })
    }
}

/// Store-mode ZIP builder shared by the library and GDPR import tests.
func makeZip(entries: [(String, Data)]) throws -> Data {
    let archive = try Archive(data: Data(), accessMode: .create, pathEncoding: nil)
    for (name, payload) in entries {
        try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(payload.count),
                             compressionMethod: .deflate) { position, size in
            payload.subdata(in: Int(position)..<(Int(position) + size))
        }
    }
    return archive.data ?? Data()
}
