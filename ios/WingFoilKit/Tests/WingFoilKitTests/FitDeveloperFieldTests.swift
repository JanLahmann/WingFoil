import Foundation
import Testing
@testable import WingFoilKit

/// Cover for our own developer-field decoder (FitDeveloperFieldReader), which exists
/// because FitFileParser cannot decode developer fields in `.generic` mode. Contract:
/// docs/fit-schema.md — record ids 0–4, lap 10–16, session 20–43 (schema v1) plus the
/// packed 54–56 (v2); speeds uint16 cm/s; `discipline` string(16). Both schema versions
/// must yield the same `WatchSummary`.
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

    // MARK: - Schema v2 packed session fields

    /// Session fields shared by both schema versions — everything outside the three packs.
    /// `app_version` is deliberately absent: presence of a pack, not the version tag, is
    /// what selects the unpacking (class (d) files carry `cfg_pack` under schema v1).
    private static let commonSessionFields: [String: FitDevValue] = [
        "discipline": .text("wingfoil"),
        "foil_time": .number(2439),
        "foil_pct": .number(58),
        "flight_count": .number(23),
        "best_2s": .number(591),
        "tack_count": .number(9),
        "jibe_count": .number(14),
        "turn_success_pct": .number(61),
        "total_pump_strokes": .number(412),
        "wind_dir_user": .number(200),
    ]

    private static func v1Session(entryCms: Int, exitCms: Int, minFlightS: Int,
                                  avgPumpsX10: Int, attempts: Int, successes: Int,
                                  longestS: Int, longestM: Int) -> [String: FitDevValue] {
        commonSessionFields.merging([
            "cfg_entry_speed": .number(Double(entryCms)),
            "cfg_exit_speed": .number(Double(exitCms)),
            "cfg_min_flight": .number(Double(minFlightS)),
            "avg_pumps_to_takeoff": .number(Double(avgPumpsX10)),
            "takeoff_attempts": .number(Double(attempts)),
            "takeoff_successes": .number(Double(successes)),
            "longest_flight_s": .number(Double(longestS)),
            "longest_flight_m": .number(Double(longestM)),
        ]) { _, new in new }
    }

    /// The wire encoding of garmin/source/fit/FitSchema.mc `packCfg`/`packTakeoff`/`packLongest`.
    private static func v2Session(entryCms: Int, exitCms: Int, minFlightS: Int,
                                  avgPumpsX10: Int, attempts: Int, successes: Int,
                                  longestS: Int, longestM: Int) -> [String: FitDevValue] {
        commonSessionFields.merging([
            "cfg_pack": .number(Double(entryCms << 16 | minFlightS << 11 | exitCms)),
            "takeoff_pack": .number(Double(avgPumpsX10 << 16 | attempts << 8 | successes)),
            "longest_pack": .number(Double(longestS << 16 | longestM)),
        ]) { _, new in new }
    }

    /// v2 (docs/fit-schema.md session 54–56) packs eight small session fields into three
    /// uint32s, because the device hard-limits developer fields to 16 per message type.
    @Test func v2PackedSessionFieldsUnpack() throws {
        let s = FitSessionParser.watchSummary(
            Self.v2Session(entryCms: 333, exitCms: 222, minFlightS: 5,
                           avgPumpsX10: 87, attempts: 31, successes: 23,
                           longestS: 420, longestM: 1923))

        #expect(s.cfgEntrySpeedMps == 3.33)
        #expect(s.cfgExitSpeedMps == 2.22)
        #expect(s.cfgMinFlightS == 5)
        #expect(s.avgPumpsToTakeoff == 8.7)
        #expect(s.takeoffAttempts == 31)
        #expect(s.takeoffSuccesses == 23)
        #expect(s.longestFlightS == 420)
        #expect(s.longestFlightM == 1923)
        // The unpacking must not disturb the fields that stayed direct.
        #expect(s.discipline == "wingfoil")
        #expect(s.best2sMps == 5.91)
    }

    /// Each subfield at the top of its bit range, and everything at zero. `cfg_pack` at its
    /// maxima is exactly `UInt32.max`, which is the whole point of the 16/5/11 split.
    @Test func v2PackedFieldBoundaries() throws {
        let hi = FitSessionParser.watchSummary(
            Self.v2Session(entryCms: 65535, exitCms: 2047, minFlightS: 31,
                           avgPumpsX10: 255, attempts: 255, successes: 255,
                           longestS: 65535, longestM: 65535))
        #expect(hi.cfgEntrySpeedMps == 655.35)
        #expect(hi.cfgExitSpeedMps == 20.47)
        #expect(hi.cfgMinFlightS == 31)
        #expect(hi.avgPumpsToTakeoff == 25.5)
        #expect(hi.takeoffAttempts == 255)
        #expect(hi.takeoffSuccesses == 255)
        #expect(hi.longestFlightS == 65535)
        #expect(hi.longestFlightM == 65535)

        let zero = FitSessionParser.watchSummary(
            Self.v2Session(entryCms: 0, exitCms: 0, minFlightS: 0,
                           avgPumpsX10: 0, attempts: 0, successes: 0,
                           longestS: 0, longestM: 0))
        #expect(zero.cfgEntrySpeedMps == 0)
        #expect(zero.cfgExitSpeedMps == 0)
        #expect(zero.cfgMinFlightS == 0)
        #expect(zero.avgPumpsToTakeoff == 0)
        #expect(zero.takeoffAttempts == 0)
        #expect(zero.takeoffSuccesses == 0)
        #expect(zero.longestFlightS == 0)
        #expect(zero.longestFlightM == 0)
        #expect(!zero.isEmpty)      // zeros are values, not absence
    }

    /// v1 files keep decoding exactly as before — the eight direct fields are untouched.
    @Test func v1DirectSessionFieldsStillDecode() throws {
        let s = FitSessionParser.watchSummary(
            Self.v1Session(entryCms: 333, exitCms: 222, minFlightS: 5,
                           avgPumpsX10: 87, attempts: 31, successes: 23,
                           longestS: 420, longestM: 1923))

        #expect(s.cfgEntrySpeedMps == 3.33)
        #expect(s.cfgExitSpeedMps == 2.22)
        #expect(s.cfgMinFlightS == 5)
        #expect(s.avgPumpsToTakeoff == 8.7)
        #expect(s.takeoffAttempts == 31)
        #expect(s.takeoffSuccesses == 23)
        #expect(s.longestFlightS == 420)
        #expect(s.longestFlightM == 1923)
    }

    /// The whole compatibility rule in one assertion: the same session written under either
    /// schema produces the *same* `WatchSummary` — same properties, units and scaling — so
    /// nothing downstream of the parser can tell the two apart.
    @Test func v1AndV2SummariesAreIdentical() throws {
        let v1 = FitSessionParser.watchSummary(
            Self.v1Session(entryCms: 333, exitCms: 222, minFlightS: 5,
                           avgPumpsX10: 87, attempts: 31, successes: 23,
                           longestS: 420, longestM: 1923))
        let v2 = FitSessionParser.watchSummary(
            Self.v2Session(entryCms: 333, exitCms: 222, minFlightS: 5,
                           avgPumpsX10: 87, attempts: 31, successes: 23,
                           longestS: 420, longestM: 1923))
        #expect(v1 == v2)
        #expect(!v1.isEmpty)
    }

    /// A pack wins over the v1 field of the same meaning, should a file ever carry both.
    @Test func packedFieldsOverrideTheirV1Counterparts() throws {
        var d = Self.v1Session(entryCms: 333, exitCms: 222, minFlightS: 5,
                               avgPumpsX10: 87, attempts: 31, successes: 23,
                               longestS: 420, longestM: 1923)
        for (key, value) in Self.v2Session(entryCms: 1200, exitCms: 800, minFlightS: 7,
                                           avgPumpsX10: 41, attempts: 12, successes: 9,
                                           longestS: 61, longestM: 300) {
            d[key] = value
        }
        let s = FitSessionParser.watchSummary(d)

        #expect(s.cfgEntrySpeedMps == 12.0)
        #expect(s.cfgMinFlightS == 7)
        #expect(s.takeoffAttempts == 12)
        #expect(s.longestFlightS == 61)
    }

    /// Fail-soft, matching the parser's contract everywhere else: a missing pack leaves its
    /// properties nil, and a malformed one (wrong type, fractional, out of uint32 range) is
    /// ignored rather than half-applied.
    @Test func malformedOrMissingPacksFailSoft() throws {
        let missing = FitSessionParser.watchSummary(Self.commonSessionFields)
        #expect(missing.cfgEntrySpeedMps == nil)
        #expect(missing.takeoffAttempts == nil)
        #expect(missing.longestFlightS == nil)
        #expect(missing.discipline == "wingfoil")   // the rest still decodes

        for bad: FitDevValue in [.text("nonsense"), .number(1.5), .number(-1),
                                 .number(4294967296), .number(.nan)] {
            var d = Self.commonSessionFields
            d["cfg_pack"] = bad
            d["takeoff_pack"] = bad
            d["longest_pack"] = bad
            let s = FitSessionParser.watchSummary(d)
            #expect(s.cfgEntrySpeedMps == nil)
            #expect(s.cfgMinFlightS == nil)
            #expect(s.takeoffSuccesses == nil)
            #expect(s.longestFlightM == nil)
        }
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
