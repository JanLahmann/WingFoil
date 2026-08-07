import Foundation
import Testing
@testable import WingFoilKit

/// Cover for our own developer-field decoder (FitDeveloperFieldReader), which exists
/// because FitFileParser cannot decode developer fields in `.generic` mode. Contract:
/// docs/fit-schema.md — record ids 0–4, lap 10–16, session 20–43; speeds uint16 cm/s;
/// `discipline` string(16).
@Suite struct FitDeveloperFieldTests {

    private var ciqFixture: URL {
        testFixturesDir.appendingPathComponent(
            "sessions/ciq/2026-08-07-0754_nago-torbole-windsurfen_ciq.fit")
    }

    /// The watch's own session summary. These are the *watch's* numbers, deliberately not
    /// the phone's — they differ slightly (the watch computes on raw 1 Hz samples with no
    /// cleaning), and having both is exactly what the divergence check needs. The phone's
    /// authoritative values live in the golden: foil 2442 s, longest 421 s, best2s 11.36 kn.
    @Test func ciqSessionDevFieldsDecode() throws {
        guard FileManager.default.fileExists(atPath: ciqFixture.path) else { return }
        let track = try FitSessionParser.parse(url: ciqFixture)
        let watch = track.watchSummary

        #expect(watch.discipline == "wingfoil")
        #expect(watch.foilPct == 58)
        #expect(watch.flightCount == 23)
        #expect(watch.foilTimeS == 2439)
        #expect(watch.longestFlightS == 420)
        #expect(watch.longestFlightM == 1923)
        // uint16 cm/s on the wire → m/s in the model.
        #expect(watch.best2sMps == 5.91)
        #expect(watch.best10sMps == 5.50)
        let best2sKn = try #require(watch.best2sMps) * Units.mpsToKn
        #expect(abs(best2sKn - 11.488) < 0.005)
        // Within the golden's ±0.05 kn of the phone's own figure — the two engines agree.
        #expect(abs(best2sKn - 11.363) < 0.2)
        // cfg_* echoes: the thresholds the watch actually ran with (docs/algorithms.md).
        #expect(abs(try #require(watch.cfgEntrySpeedMps) * Units.mpsToKmh - 12.0) < 0.05)
        #expect(abs(try #require(watch.cfgExitSpeedMps) * Units.mpsToKmh - 8.0) < 0.05)
        #expect(watch.cfgMinFlightS == 5)
        #expect(watch.appVersion == 257)       // 0x0101: app minor 1, schema 1
        #expect(watch.schemaVersion == 1)      // docs/fit-schema.md SCHEMA_VERSION
    }

    /// Record-level developer fields, and the classification they drive.
    @Test func ciqRecordDevFieldsMarkSourceClassA() throws {
        guard FileManager.default.fileExists(atPath: ciqFixture.path) else { return }
        let track = try FitSessionParser.parse(url: ciqFixture)

        #expect(track.capabilities.hasDevFields)
        #expect(track.capabilities.sourceClass == "a")
        #expect(track.capabilities.discipline == "wingfoil")

        let states = track.samples.compactMap(\.foilState)
        #expect(states.count == track.samples.count, "foil_state missing on some records")
        #expect(Set(states).isSubset(of: [0, 1, 2]), "foil_state outside its enum: \(Set(states))")
        #expect(Set(states).contains(2), "no flying samples — decoder is producing constants")

        // `tick` is a rolling counter that must actually roll. Note it tops out at 254,
        // not 255: 0xFF is FIT's uint8 "invalid" sentinel, so the 15 records the watch
        // stamped 255 decode as absent — same as in the lab (fitdecode drops invalids).
        let ticks = track.samples.compactMap(\.tick)
        #expect(Set(ticks).count == 255, "tick is not rolling: \(Set(ticks).count) values")
        #expect(ticks.min() == 0 && ticks.max() == 254)
        #expect(track.samples.count - ticks.count < 25, "too many ticks lost to the sentinel")

        // The watch's own foil time must agree with what its per-record states imply —
        // that is what makes the dev stream usable as a cross-check on our segmenter.
        // Tolerance is docs/testing.md's ±2 % for foil time.
        let flyingSeconds = Double(states.filter { $0 == 2 }.count)
        let watchFoilTime = try #require(track.watchSummary.foilTimeS)
        #expect(abs(flyingSeconds - watchFoilTime) <= 0.02 * watchFoilTime,
                "records imply \(flyingSeconds) s of foiling, session says \(watchFoilTime)")
    }

    /// Nothing that lacks our developer fields may be misclassified as class (a).
    @Test func nonCiqFixturesStayClassB() throws {
        for url in allFixtureFITs() where !url.path.contains("/ciq/") {
            let track = try FitSessionParser.parse(url: url)
            #expect(!track.capabilities.hasDevFields,
                    "\(url.lastPathComponent): unexpected dev fields")
            #expect(track.watchSummary.isEmpty,
                    "\(url.lastPathComponent): unexpected watch summary")
            #expect(track.capabilities.discipline == nil,
                    "\(url.lastPathComponent): unexpected discipline")
        }
    }

    /// The classification the developer fields unlock has to survive into the library:
    /// `sourceClass` and the authoritative `discipline` tag are already indexed columns,
    /// they were simply never populated while the developer fields were unreadable.
    @Test func ingestCarriesClassAndDisciplineToTheDatabase() async throws {
        guard FileManager.default.fileExists(atPath: ciqFixture.path) else { return }
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-dev-\(UUID().uuidString)/Sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let ingestor = SessionIngestor(database: try AppDatabase.inMemory(),
                                       archive: SessionArchive(root: root))

        let data = try Data(contentsOf: ciqFixture)
        // Bulk-import gate: sport is windsurfing(43), so the discipline tag is what
        // distinguishes this from Jan's real windsurf sessions (docs/fit-schema.md).
        guard case let .imported(row) = try await ingestor.ingest(
            fitData: data, filename: ciqFixture.lastPathComponent, source: .file,
            requireWatersport: true) else {
            Issue.record("expected a fresh import")
            return
        }
        #expect(row.sourceClass == "a")
        #expect(row.discipline == "wingfoil")
        #expect(row.sport == "windsurfing")

        let stored = try #require(try await ingestor.session(id: row.id))
        #expect(stored.sourceClass == "a")
        #expect(stored.discipline == "wingfoil")
        // The watch summary stays recoverable from the archived original — no schema change.
        #expect(try ingestor.rawTrack(for: stored).watchSummary.discipline == "wingfoil")
    }

    /// The join between FitFileParser's messages and our own decode is positional, so a
    /// drift would silently attach values to the wrong samples. Verify it holds by
    /// checking the decoded counts against the message counts.
    @Test func developerFieldCountsMatchMessageCounts() throws {
        guard FileManager.default.fileExists(atPath: ciqFixture.path) else { return }
        let sanitized = FitStreamSanitizer.sanitize(try Data(contentsOf: ciqFixture))
        let dev = FitDeveloperFieldReader.read(sanitized.data)
        #expect(dev.fields(forMessageType: 20).count == 4154)   // record
        #expect(dev.fields(forMessageType: 19).count == 47)     // lap
        #expect(dev.fields(forMessageType: 18).count == 1)      // session
        #expect(!dev.isEmpty)
    }
}
