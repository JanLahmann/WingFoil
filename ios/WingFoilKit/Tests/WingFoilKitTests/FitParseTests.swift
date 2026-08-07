import Foundation
import GRDB
import Testing
@testable import WingFoilKit

/// Repo-local fixtures (works when tests run from the checkout; CI keeps the same layout).
private let fixturesDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // strip FitParseTests.swift -> WingFoilKitTests/
    .deletingLastPathComponent()   // -> Tests/
    .deletingLastPathComponent()   // -> WingFoilKit/
    .deletingLastPathComponent()   // -> ios/
    .deletingLastPathComponent()   // -> repo root
    .appendingPathComponent("fixtures")

@Suite struct FitParseTests {

    @Test func syntheticFixtureMatchesPython() throws {
        // Same file the lab parses (fixtures/synthetic/smoke-60s.fit): 60 samples @ 1 Hz,
        // sport windsurfing, top speed 22 km/h. Cross-implementation phase-0 acceptance.
        let url = fixturesDir.appendingPathComponent("synthetic/smoke-60s.fit")
        try #require(FileManager.default.fileExists(atPath: url.path),
                     "run lab tests first to generate the synthetic fixture")
        let track = try FitSessionParser.parse(url: url)

        #expect(track.samples.count == 60)
        #expect(track.capabilities.hasSpeed)
        #expect(track.capabilities.hasPosition)
        #expect(track.capabilities.hasHR)
        #expect(track.capabilities.sourceClass == "b")
        #expect(abs(track.capabilities.sampleRateHz - 1.0) < 0.01)

        let maxKn = track.samples.compactMap(\.speedMps).max()! * Units.mpsToKn
        #expect(abs(maxKn - 22.0 / 3.6 * Units.mpsToKn) < 0.05)
        #expect((track.capabilities.sport ?? "").lowercased().contains("windsurf")
                || track.capabilities.sport == "43")
    }

    @Test func realFixturesParseWhenPresent() throws {
        let sessions = fixturesDir.appendingPathComponent("sessions")
        let fits = (FileManager.default.enumerator(at: sessions, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "fit" }) ?? []
        guard !fits.isEmpty else { return }  // nothing downloaded yet — nothing to verify
        for url in fits {
            let track = try FitSessionParser.parse(url: url)
            #expect(!track.samples.isEmpty, "\(url.lastPathComponent): no records")
            #expect(track.capabilities.hasPosition, "\(url.lastPathComponent): no GPS")
        }
    }

    @Test func databaseMigratesAndStoresSession() throws {
        let db = try AppDatabase.inMemory()
        var row = SessionRow(startDate: .now, durationS: 3600, sourceClass: "b")
        row.discipline = "wingfoil"
        try db.writer.write { try row.insert($0) }
        let count = try db.writer.read {
            try SessionRow.filter(Column("discipline") == "wingfoil").fetchCount($0)
        }
        #expect(count == 1)
    }
}
