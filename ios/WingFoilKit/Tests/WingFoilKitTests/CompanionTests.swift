import Foundation
import GRDB
import Testing
@testable import WingFoilKit

/// Phase 5, the phone half: decoding the watch's BLE card and reconciling it with the FIT
/// that follows. Everything here is the part that can actually be wrong — the radio hop
/// itself needs a paired watch and Garmin Connect Mobile, and is not testable in a package.
@Suite struct CompanionTests {

    // MARK: - Payloads

    /// A card exactly as `PhoneLink.summary()` builds it: every key present, every value a
    /// plain integer, speeds in cm/s, wind in whole degrees.
    static func payload(start: Int = 1_754_570_000, duration: Int = 3_600) -> [String: Any] {
        [
            "v": 1,
            "st": start,
            "du": duration,
            "ft": 1_800,
            "fp": 50,
            "fc": 24,
            "ls": 210,
            "lm": 1_450,
            "ds": 18_400,
            "b2": 1_234,          // 12.34 m/s
            "bt": 1_100,
            "tn": 30,
            "tk": 12,
            "jb": 16,
            "of": 21,
            "ot": 6,
            "ox": 3,
            "ka": 40,
            "ks": 31,
            "wd": 225,
            "av": 258,            // APP_MINOR 1 * 256 + FIT schema 2
        ]
    }

    @Test func decodesACompleteCard() throws {
        let card = try CompanionSummary(payload: Self.payload())

        #expect(card.startDate == Date(timeIntervalSince1970: 1_754_570_000))
        #expect(card.durationS == 3_600)
        #expect(card.foilTimeS == 1_800)
        #expect(card.foilPct == 50)
        #expect(card.flightCount == 24)
        #expect(card.longestFlightS == 210)
        #expect(card.longestFlightM == 1_450)
        #expect(card.distanceM == 18_400)
        // cm/s → m/s → knots, the one unit conversion on this path.
        #expect(abs(card.best2sKn - 12.34 * Units.mpsToKn) < 0.0001)
        #expect(abs(card.best10sKn - 11.0 * Units.mpsToKn) < 0.0001)
        #expect(card.turnCount == 30)
        #expect(card.tacks == 12)
        #expect(card.jibes == 16)
        #expect(card.flewThrough == 21)
        #expect(card.touchdowns == 6)
        #expect(card.fellIn == 3)
        #expect(card.takeoffAttempts == 40)
        #expect(card.takeoffSuccesses == 31)
        #expect(card.windDirDeg == 225)
        #expect(card.appVersion == 258)
        #expect(card.dedupeKey.durationS == 3_600)
    }

    /// The link hands the payload over as an unordered ObjC dictionary of NSNumbers, and
    /// key order is not observable on either side — so the version has to be found by key.
    @Test func decodesAnUnorderedBridgedDictionary() throws {
        var bridged: [AnyHashable: Any] = [:]
        for (key, value) in Self.payload() {
            bridged[key] = NSNumber(value: (value as? Int) ?? 0)
        }
        let card = try CompanionSummary(payload: bridged as Any)
        #expect(card.flightCount == 24)
        #expect(card.durationS == 3_600)
    }

    @Test func rejectsAnUnknownSchemaVersion() {
        var future = Self.payload()
        future["v"] = 2
        #expect(throws: CompanionDecodeError.unsupportedSchemaVersion(2)) {
            try CompanionSummary(payload: future)
        }
        var ancient = Self.payload()
        ancient["v"] = 0
        #expect(throws: CompanionDecodeError.unsupportedSchemaVersion(0)) {
            try CompanionSummary(payload: ancient)
        }
    }

    @Test func rejectsAMissingOrUnreadableSchemaVersion() {
        var missing = Self.payload()
        missing["v"] = nil
        #expect(throws: CompanionDecodeError.missingSchemaVersion) {
            try CompanionSummary(payload: missing)
        }
        var text = Self.payload()
        text["v"] = "1"
        #expect(throws: CompanionDecodeError.notAnInteger(key: "v")) {
            try CompanionSummary(payload: text)
        }
    }

    @Test func rejectsAnythingThatIsNotADictionary() {
        for payload: Any? in [nil, "hello" as Any, 42 as Any, [1, 2, 3] as Any] {
            #expect(throws: CompanionDecodeError.notADictionary) {
                try CompanionSummary(payload: payload)
            }
        }
    }

    /// A truncated dictionary is the shape a half-written Storage slot or a mismatched
    /// watch build produces: right version, missing keys. It must be refused whole rather
    /// than defaulted to zero, or the library gets a session with no flights and no speed.
    @Test func rejectsATruncatedDictionary() {
        for dropped in ["st", "du", "fc", "b2", "wd", "av"] {
            var truncated = Self.payload()
            truncated[dropped] = nil
            #expect(throws: CompanionDecodeError.missingKey(dropped)) {
                try CompanionSummary(payload: truncated)
            }
        }
        // The extreme case: version and nothing else.
        #expect(throws: CompanionDecodeError.missingKey("st")) {
            try CompanionSummary(payload: ["v": 1])
        }
    }

    @Test func rejectsOutOfRangeValues() {
        func expectRefused(_ key: String, _ value: Int) {
            var broken = Self.payload()
            broken[key] = value
            #expect(throws: CompanionDecodeError.outOfRange(key: key, value: value)) {
                try CompanionSummary(payload: broken)
            }
        }
        expectRefused("st", 0)                    // a watch that never got a clock fix
        expectRefused("st", 4_200_000_000)        // year 2103
        expectRefused("du", 0)                    // not a session
        expectRefused("du", 90_000)               // 25 hours
        expectRefused("fp", 101)
        expectRefused("fp", -1)
        expectRefused("b2", 99_999)               // ~1 900 knots
        expectRefused("ds", -5)
        expectRefused("wd", 360)
        expectRefused("wd", -2)
        expectRefused("fc", -1)
    }

    /// -1 is the watch's "the rider never set a wind direction" (`WingFoilCore.Config`),
    /// and it has to survive as nil rather than as a bearing of minus one degree.
    @Test func unsetWindArrivesAsNil() throws {
        var unset = Self.payload()
        unset["wd"] = -1
        #expect(try CompanionSummary(payload: unset).windDirDeg == nil)
        var north = Self.payload()
        north["wd"] = 0
        #expect(try CompanionSummary(payload: north).windDirDeg == 0)
    }

    /// Bridged booleans read as 0/1 through `NSNumber`, and a flag that quietly became a
    /// flight count is exactly the kind of wrong number this decoder exists to refuse.
    @Test func rejectsNonIntegerValues() throws {
        var boolean = Self.payload()
        boolean["fc"] = true
        #expect(throws: CompanionDecodeError.notAnInteger(key: "fc")) {
            try CompanionSummary(payload: boolean)
        }
        var fractional = Self.payload()
        fractional["ft"] = 12.5
        #expect(throws: CompanionDecodeError.notAnInteger(key: "ft")) {
            try CompanionSummary(payload: fractional)
        }
        // An integral double still reads: a JSON round-trip in the middle is not a lie.
        var whole = Self.payload()
        whole["ft"] = 1_800.0
        #expect(try CompanionSummary(payload: whole).foilTimeS == 1_800)
    }

    // MARK: - Reconciliation

    private struct Harness {
        var ingestor: SessionIngestor
        var root: URL
        var fit: Data
        var name: String
        /// A card whose dedupe key matches the fixture FIT, offset by `skewS` seconds to
        /// prove the ±60 s tolerance is the rule doing the matching.
        func card(skewS: Int = 0) throws -> CompanionSummary {
            let track = try FitSessionParser.parse(data: fit)
            let start = try #require(track.startDate)
            let first = try #require(track.samples.first)
            let last = try #require(track.samples.last)
            var payload = CompanionTests.payload(
                start: Int(start.timeIntervalSince1970) + skewS,
                duration: Int((last.t - first.t).rounded()) + skewS)
            payload["fc"] = 24 + abs(skewS)       // so a refresh is observable
            return try CompanionSummary(payload: payload)
        }
    }

    private func makeHarness() throws -> Harness {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-companion-\(UUID().uuidString)/Sessions",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = try #require(allFixtureFITs().first, "no fixture FITs available")
        return Harness(ingestor: SessionIngestor(database: try AppDatabase.inMemory(),
                                                 archive: SessionArchive(root: root)),
                       root: root, fit: try Data(contentsOf: url), name: url.lastPathComponent)
    }

    /// The phone was in the car: the card arrives and there is no FIT for hours. That is a
    /// real session the rider did, and it has to be in the library, marked for what it is.
    @Test func cardAloneBecomesOneProvisionalSession() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }

        let card = try harness.card()
        guard case .provisional(let row) = try await harness.ingestor.ingest(card: card) else {
            Issue.record("expected a provisional row")
            return
        }
        #expect(row.isProvisional)
        #expect(row.importSource == "watch")
        #expect(row.discipline == "wingfoil")
        #expect(row.foilPct == card.foilPct)
        #expect(row.flightCount == card.flightCount)
        #expect(row.distanceKm == card.distanceM / 1000)
        // Nothing the card cannot know is invented: nil means "not analysed yet", not 0.
        #expect(row.engineVersion == nil)
        #expect(row.best500mKn == nil)
        #expect(row.avgPumpsToTakeoff == nil)
        #expect(try await harness.ingestor.allSessions().count == 1)

        // It shows in the library but never in a number that claims to describe the rider.
        let library = harness.ingestor.library
        #expect(try await library.sessions().isEmpty)
        #expect(try await library.records().isEmpty)

        // Nothing to re-derive: a card carries no track, so it must not make every launch
        // announce a re-analysis for ever.
        #expect(try await harness.ingestor.reanalyzeStale() == 0)
    }

    /// The ordinary path: card first (seconds after Save), FIT hours later. ONE session.
    @Test func cardThenFitIsOneSessionWithRealAnalysis() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }

        guard case .provisional(let provisional) =
                try await harness.ingestor.ingest(card: try harness.card(skewS: 12)) else {
            Issue.record("expected a provisional row")
            return
        }

        guard case .imported(let real) = try await harness.ingestor.ingest(
            fitData: harness.fit, filename: harness.name, source: .icu,
            icuActivityId: "i4242") else {
            Issue.record("the FIT must import, not dedupe away against its own card")
            return
        }

        // The SAME row, upgraded in place — not a second one beside it.
        #expect(real.id == provisional.id)
        #expect(try await harness.ingestor.allSessions().count == 1)
        #expect(!real.isProvisional)
        #expect(real.engineVersion == AnalysisEngine.version)
        #expect(real.originalFilename == harness.name)
        #expect(real.icuActivityId == "i4242")
        // The BLE hop stays visible in the provenance.
        #expect(real.importSource == "icu+watch")
        // The watch's arithmetic is gone; these are the engine's numbers now.
        let analysis = try await harness.ingestor.analysis(for: real)
        #expect(real.flightCount == analysis.summary.flightCount)
        #expect(real.foilPct == analysis.summary.foilPct)

        // And the session rejoins everything a provisional row was kept out of.
        let library = harness.ingestor.library
        #expect(try await library.sessions().count == 1)
        try await harness.ingestor.database.writer.read { db in
            let children = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM flight WHERE sessionId = ?",
                                            arguments: [real.id]) ?? 0
            #expect(children == analysis.flights.count)
        }
    }

    /// The other order — the rider synced Garmin Connect before opening this app, or the
    /// watch resent its pending slot the next morning. Still one session, and the FIT wins.
    @Test func fitThenCardIsOneSessionAndTheFitWins() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }

        guard case .imported(let real) = try await harness.ingestor.ingest(
            fitData: harness.fit, filename: harness.name, source: .icu) else {
            Issue.record("expected a fresh import")
            return
        }
        let engineFlights = real.flightCount

        guard case .alreadyAnalysed(let noted) =
                try await harness.ingestor.ingest(card: try harness.card(skewS: -30)) else {
            Issue.record("a card for an analysed session must not create a row")
            return
        }
        #expect(noted.id == real.id)
        #expect(try await harness.ingestor.allSessions().count == 1)
        #expect(!noted.isProvisional)
        #expect(noted.importSource == "icu+watch")
        // Twenty integers did not overwrite a full analysis.
        #expect(noted.flightCount == engineFlights)
        #expect(noted.engineVersion == AnalysisEngine.version)
    }

    /// The watch keeps one newest-wins pending slot and resends it on the connected edge,
    /// so the same session can arrive as a card twice. Still one row.
    @Test func aSecondCardRefreshesTheProvisionalRow() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }

        guard case .provisional(let first) =
                try await harness.ingestor.ingest(card: try harness.card()) else { return }
        guard case .refreshed(let second) =
                try await harness.ingestor.ingest(card: try harness.card(skewS: 20)) else {
            Issue.record("a repeat card must refresh, not duplicate")
            return
        }
        #expect(second.id == first.id)
        #expect(second.isProvisional)
        #expect(second.flightCount == 44)                 // 24 + skew, the newer numbers
        #expect(try await harness.ingestor.allSessions().count == 1)
    }

    /// Two genuinely different sessions on the same day must not collapse into one — the
    /// tolerance is ±60 s, and a card two hours away is a different afternoon.
    @Test func aCardFarFromAnySessionMakesItsOwnRow() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }

        _ = try await harness.ingestor.ingest(fitData: harness.fit, filename: harness.name,
                                              source: .file)
        guard case .provisional = try await harness.ingestor.ingest(
            card: try harness.card(skewS: 7_200)) else {
            Issue.record("a card 2 h away is another session")
            return
        }
        #expect(try await harness.ingestor.allSessions().count == 2)
    }

    // MARK: - Schema

    @Test func v4AddsTheProvisionalFlagToAV3Library() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v3")
        let before = try queue.read { db in try db.columns(in: "session").map(\.name) }
        #expect(!before.contains("isProvisional"))

        _ = try AppDatabase(queue)                      // ← runs v4
        let after = try queue.read { db in try db.columns(in: "session").map(\.name) }
        #expect(after.contains("isProvisional"))
        #expect(AppDatabase.migrationNames.last == "v4")
    }

    // MARK: - The link seam

    @Test func fakeLinkCarriesWindAndRefusesNonsense() async throws {
        let link = FakeCompanionLink()
        #expect(await link.state.canSend)
        try await link.sendWind(degreesFrom: 225)
        try await link.sendWind(degreesFrom: CompanionWind.clear)
        await #expect(throws: CompanionLinkError.invalidWind(360)) {
            try await link.sendWind(degreesFrom: 360)
        }
        // A bearing that is not one is refused before the radio is touched at all.
        #expect(await link.sentWind == [225, -1])

        await link.set(state: .appNotRunning(name: "fenix 8"))
        #expect(await !link.state.canSend)
        await #expect(throws: CompanionLinkError.notReady(.appNotRunning(name: "fenix 8"))) {
            try await link.sendWind(degreesFrom: 90)
        }
    }

    @Test func fakeLinkDeliversCardsInOrder() async throws {
        let link = FakeCompanionLink()
        let one = try CompanionSummary(payload: Self.payload(start: 1_754_570_000))
        let two = try CompanionSummary(payload: Self.payload(start: 1_754_580_000))
        await link.deliver(one)
        await link.deliver(two)
        await link.finish()

        var received: [CompanionSummary] = []
        for await card in await link.summaries() { received.append(card) }
        #expect(received == [one, two])
    }
}
