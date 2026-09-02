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

    /// `spots()` is one `GROUP BY` pass instead of a `SessionRow` fetch per spot. It must
    /// return exactly what the per-row computation returned: same order, same counts, same
    /// last visit — including a spot nobody has sailed yet and sessions with no spot at all.
    @Test func spotAggregatesMatchThePerRowComputation() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }
        let database = harness.store.database
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let places = [SpotRow(id: "garda", name: "Torbole", lat: 45.876, lon: 10.872),
                      SpotRow(id: "rhein", name: "Rheinstetten", lat: 48.98, lon: 8.32),
                      SpotRow(id: "empty", name: "Never sailed", lat: 0, lon: 0)]
        // Deliberately not in chronological order: MAX() must not depend on insert order.
        let sessions: [(id: String, spot: String?, day: Double)] = [
            ("s1", "garda", 3), ("s2", "rhein", 1), ("s3", "garda", 9),
            ("s4", "garda", 5), ("s5", nil, 7),
        ]
        try await database.writer.write { db in
            for spot in places { try spot.insert(db) }
            for s in sessions {
                var row = SessionRow(id: s.id, startDate: base.addingTimeInterval(s.day * 86_400),
                                     durationS: 3600, sourceClass: "test")
                row.spotId = s.spot
                try row.insert(db)
            }
        }

        // The implementation this replaced, verbatim.
        let reference: [SpotAggregate] = try await database.writer.read { db in
            try SpotRow.order(Column("name")).fetchAll(db).map { spot in
                let rows = try SessionRow.filter(Column("spotId") == spot.id)
                    .order(Column("startDate")).fetchAll(db)
                return SpotAggregate(spot: spot, sessions: rows.count,
                                     lastVisit: rows.last?.startDate)
            }
        }
        let actual = try await harness.store.spots()
        #expect(actual == reference)

        // And the values themselves, so a shared bug in both paths cannot hide.
        #expect(actual.map(\.id) == ["empty", "rhein", "garda"])       // ordered by name
        #expect(actual.map(\.sessions) == [0, 1, 3])
        #expect(actual.map(\.lastVisit) == [nil, base.addingTimeInterval(86_400),
                                            base.addingTimeInterval(9 * 86_400)])
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

    // MARK: - Rider attribution

    /// The whole point of the `rider` column: a friend's session is in the library, opens
    /// in full, and moves *nothing*.
    ///
    /// Asserted by importing the same fixture twice — once as the reader's own, once
    /// credited to a friend, two hours apart so the dedupe key does not merge them. The
    /// two sessions are then identical in every number, which is the sharpest possible
    /// form of the test: any aggregate that counts the friend's copy would visibly double,
    /// and any that does not is provably filtering on attribution rather than on luck.
    @Test func aFriendsSessionIsKeptOutOfEveryAggregate() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }
        let (data, name) = try fixture("2026-08-05-0827")

        guard case .imported(let mine) = try await harness.ingestor.ingest(
            fitData: data, filename: name, source: .file) else {
            Issue.record("expected a fresh import"); return
        }
        // Two hours out of the way first, so the second import of the same bytes is a
        // different session rather than a dedupe hit — and only *then* photograph the
        // aggregates, since a record carries the session's wall-clock time.
        try await shift(harness, id: mine.id, seconds: 7200, durationDelta: 0)
        let before = try await harness.store.records()
        let beforeTrend = try await harness.store.trend()

        guard case .imported(let theirs) = try await harness.ingestor.ingest(
            fitData: data, filename: name, source: .file, rider: "  Marco  ") else {
            Issue.record("a friend's session is still a session"); return
        }
        // Stored trimmed, so the badge and the "known riders" list cannot end up with two
        // spellings of one friend.
        #expect(theirs.rider == "Marco")
        #expect(mine.rider == nil)

        // It is in the library, in full — the detail screen reads this list.
        #expect(try await harness.ingestor.allSessions().count == 2)
        #expect(try await harness.ingestor.session(id: theirs.id)?.rider == "Marco")
        // …and offered back as a name for the next file from the same friend.
        #expect(try await harness.store.riders() == ["Marco"])

        // But every aggregate is exactly where it was before he arrived.
        #expect(try await harness.store.sessions().map(\.id) == [mine.id])
        #expect(try await harness.store.records() == before)
        #expect(try await harness.store.trend() == beforeTrend)
        #expect(try await harness.store.weeks().map(\.count).reduce(0, +) == 1)

        // Including the gear rollups, which have their own SQL.
        let wing = GearRow(name: "Duotone 5.0", kind: .wing)
        try await harness.store.saveGear(wing)
        for id in [mine.id, theirs.id] {
            try await harness.store.assignGear(sessionId: id, kind: .wing, gearId: wing.id)
        }
        let rollup = try #require(try await harness.store.gearAggregates().first)
        #expect(rollup.sessions == 1, "a friend's session must not pad the gear totals")
    }

    /// The prompt's text field can be left blank after tapping "a friend's". An empty
    /// string in the column would be the worst of both worlds — excluded from every
    /// aggregate, badged with nothing — so it degrades to "mine".
    @Test func aBlankRiderNameMeansMine() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent()) }
        let (data, name) = try fixture("2026-08-05-0827")

        guard case .imported(let row) = try await harness.ingestor.ingest(
            fitData: data, filename: name, source: .file, rider: "   ") else {
            Issue.record("expected a fresh import"); return
        }
        #expect(row.rider == nil)
        #expect(try await harness.store.sessions().count == 1)
        #expect(SessionIngestor.riderName(nil) == nil)
        #expect(SessionIngestor.riderName("") == nil)
        #expect(SessionIngestor.riderName(" Jo ") == "Jo")
    }

    // MARK: - Session records (the non-speed table)

    /// Synthetic rows rather than fixtures, because what is under test here is the *rule*
    /// and not the corpus: no arrangement of real FITs can be made to hold a four-jibe
    /// afternoon and a nine-jibe one whose clean rates tie on purpose.
    private static let recordsBase = Date(timeIntervalSince1970: 1_785_000_000)

    private func sessionRow(_ id: String, day: Double, durationS: Double = 3600,
                            _ build: (inout SessionRow) -> Void = { _ in }) -> SessionRow {
        var row = SessionRow(id: id,
                             startDate: Self.recordsBase.addingTimeInterval(day * 86_400),
                             durationS: durationS, sourceClass: "test")
        build(&row)
        return row
    }

    private func store(_ rows: [SessionRow]) async throws -> LibraryStore {
        let database = try AppDatabase.inMemory()
        try await database.writer.write { db in for row in rows { try row.insert(db) } }
        return LibraryStore(database: database)
    }

    /// The catalogue is a contract with the analyzer's `SESSION_RECORD_KINDS`: same ten
    /// kinds, same order, so a rider reading both sees one set of personal bests.
    @Test func sessionRecordsAreTheTenKindsInCatalogueOrder() async throws {
        #expect(SessionRecordKind.allCases.map(\.rawValue) ==
                ["longestFlight", "mostFlights", "bestFoilPct", "mostCleanJibes", "bestCph",
                 "bestCleanJibeRate", "longestDryStreak", "longestFlewStreak",
                 "longestSession", "mostDistance"])

        let full = sessionRow("full", day: 1) {
            $0.longestFlightS = 120; $0.longestFlightM = 640; $0.flightCount = 9
            $0.foilPct = 55; $0.jibes = 8; $0.jibesSuccessful = 5
            $0.longestDryStreak = 6; $0.longestFlewStreak = 3; $0.distanceKm = 12
        }
        let records = try await store([full]).sessionRecords()
        #expect(records.map(\.kind) == SessionRecordKind.allCases)
        #expect(records.allSatisfy { $0.sessionId == "full" })
        // The longest-flight row carries the one fact its duration cannot.
        #expect(records.first { $0.kind == .longestFlight }?.distanceM == 640)
        #expect(records.filter { $0.distanceM != nil }.count == 1)
    }

    @Test func eachSessionRecordIsTheMaximumOverTheLibrary() async throws {
        let older = sessionRow("older", day: 1) {
            $0.longestFlightS = 120; $0.flightCount = 9; $0.foilPct = 55
            $0.jibes = 8; $0.jibesSuccessful = 5
            $0.longestDryStreak = 6; $0.longestFlewStreak = 3; $0.distanceKm = 12
        }
        let newer = sessionRow("newer", day: 8, durationS: 7200) {
            $0.longestFlightS = 90; $0.flightCount = 4; $0.foilPct = 40
            $0.jibes = 20; $0.jibesSuccessful = 8
            $0.longestDryStreak = 9; $0.longestFlewStreak = 1; $0.distanceKm = 30
        }
        let by = Dictionary(uniqueKeysWithValues:
            try await store([newer, older]).sessionRecords().map { ($0.kind, $0) })

        #expect(by[.longestFlight]?.sessionId == "older")
        #expect(by[.mostFlights]?.value == 9)
        #expect(by[.bestFoilPct]?.value == 55)
        #expect(by[.mostCleanJibes]?.sessionId == "newer")
        // Five clean jibes in one hour beats eight in two.
        #expect(by[.bestCph]?.sessionId == "older")
        #expect(by[.bestCph]?.value == 5)
        #expect(by[.bestCleanJibeRate]?.value == 62.5)
        #expect(by[.longestDryStreak]?.sessionId == "newer")
        #expect(by[.longestFlewStreak]?.sessionId == "older")
        #expect(by[.longestSession]?.value == 7200)
        #expect(by[.mostDistance]?.value == 30)
    }

    /// The record was set then, not re-set later — the same tie rule the speed table has
    /// always followed, and the reason `sessionRecords` compares with a strict `>`.
    @Test func aTiedSessionRecordGoesToTheEarliestSession() async throws {
        let rows = ["first": 1.0, "second": 8.0, "third": 15.0].map { id, day in
            sessionRow(id, day: day) { $0.jibes = 10; $0.jibesSuccessful = 5 }
        }
        for order in [rows, Array(rows.reversed()),
                      Array(rows.dropFirst()) + Array(rows.prefix(1))] {
            let by = Dictionary(uniqueKeysWithValues:
                try await store(order).sessionRecords().map { ($0.kind, $0) })
            #expect(by[.longestSession]?.sessionId == "first")
            #expect(by[.mostCleanJibes]?.sessionId == "first")
            #expect(by[.bestCleanJibeRate]?.sessionId == "first")
        }
        // …and a later session that genuinely beats it does take the record.
        let beaten = try await store(rows + [sessionRow("beat", day: 20, durationS: 3600.1)])
            .sessionRecords()
        #expect(beaten.first { $0.kind == .longestSession }?.sessionId == "beat")
    }

    /// Four out of four is a good afternoon; it is not a rate. The floor is
    /// `SessionRecordKind.minJibesForRate`, and the same number is printed in the caption
    /// so the rule the number obeys is the rule the reader is told.
    @Test func theCleanJibeRateNeedsFiveJibes() async throws {
        let floor = SessionRecordKind.minJibesForRate
        for (jibes, clean, expected) in [(0, 0, nil), (1, 1, nil), (floor - 1, floor - 1, nil),
                                         (floor, 4, 80.0), (floor, floor, 100.0),
                                         (20, 3, 15.0)] as [(Int, Int, Double?)] {
            let row = sessionRow("s", day: 1) { $0.jibes = jibes; $0.jibesSuccessful = clean }
            let rate = try await store([row]).sessionRecords()
                .first { $0.kind == .bestCleanJibeRate }?.value
            #expect(rate == expected, "\(clean)/\(jibes)")
        }
        // A perfect thin session does not merely lose the record — it is not in the running.
        let perfect = sessionRow("perfect", day: 1) { $0.jibes = 3; $0.jibesSuccessful = 3 }
        let honest = sessionRow("honest", day: 8) { $0.jibes = 10; $0.jibesSuccessful = 4 }
        let best = try await store([perfect, honest]).sessionRecords()
            .first { $0.kind == .bestCleanJibeRate }
        #expect(best?.sessionId == "honest")
        #expect(best?.value == 40)
        #expect(SessionRecordKind.bestCleanJibeRate.caption
                == "Sessions with at least \(floor) jibes.")
    }

    /// Absent is never zero. A row the v10 migration has not re-derived yet has no streaks
    /// and no clean-jibe count; reading those as 0 would put a fabricated number in the
    /// running for an all-time best, and a kind nobody has set is dropped rather than shown.
    @Test func aRowWithNoCountsSetsNoSessionRecordForThem() async throws {
        let stale = sessionRow("stale", day: 1) { $0.distanceKm = 12 }
        let kinds = Set(try await store([stale]).sessionRecords().map(\.kind))
        #expect(kinds.isDisjoint(with: [.mostCleanJibes, .bestCph, .bestCleanJibeRate,
                                        .longestDryStreak, .longestFlewStreak]))
        #expect(kinds.contains(.mostDistance))
        #expect(kinds.contains(.longestSession), "the session still lasted an hour")

        // A genuine zero is dropped too — "0 flights" is not a record anybody holds.
        let flat = sessionRow("flat", day: 1) {
            $0.flightCount = 0; $0.distanceKm = 0; $0.jibes = 9; $0.jibesSuccessful = 0
        }
        let flatKinds = Set(try await store([flat]).sessionRecords().map(\.kind))
        #expect(flatKinds.isDisjoint(with: [.mostFlights, .mostDistance, .mostCleanJibes]))
    }

    /// The second table goes through `LibraryStore.clause` like the first one, so the
    /// example session, a provisional row and a friend's afternoon move nothing here either.
    @Test func sessionRecordsHonourTheSameExclusionsAndFilters() async throws {
        let mine = sessionRow("mine", day: 1) {
            $0.distanceKm = 10; $0.spotId = "garda"; $0.foilPct = 60; $0.flightCount = 5
        }
        let friend = sessionRow("friend", day: 2, durationS: 99_999) {
            $0.distanceKm = 99; $0.rider = "Marco"
        }
        let demo = sessionRow("demo", day: 3, durationS: 88_888) {
            $0.distanceKm = 88; $0.isExample = true
        }
        let watch = sessionRow("watch", day: 4, durationS: 77_777) {
            $0.distanceKm = 77; $0.isProvisional = true
        }
        let elsewhere = sessionRow("elsewhere", day: 5, durationS: 5000) {
            $0.distanceKm = 20; $0.spotId = "rhein"; $0.foilPct = 40; $0.flightCount = 2
        }
        let library = try await store([mine, friend, demo, watch, elsewhere])
        let all = try await library.sessionRecords()
        #expect(Set(all.map(\.sessionId)) == ["mine", "elsewhere"])
        #expect(all.first { $0.kind == .mostDistance }?.value == 20)

        let atGarda = try await library.sessionRecords(LibraryFilter(spotId: "garda"))
        #expect(atGarda.allSatisfy { $0.sessionId == "mine" })
        #expect(atGarda.first { $0.kind == .mostDistance }?.value == 10)

        let recent = try await library.sessionRecords(
            LibraryFilter(since: Self.recordsBase.addingTimeInterval(3 * 86_400)))
        #expect(recent.allSatisfy { $0.sessionId == "elsewhere" })
    }

    /// The week rule is ISO-8601, Monday start: a Saturday and the Monday after it are two
    /// different weeks, and the Sunday between them belongs to the *earlier* one. A
    /// Sunday-first calendar gets that last one backwards and every bar still looks
    /// plausible, which is why it is pinned here rather than left to the chart.
    @Test func weeksStartOnTheIsoMonday() async throws {
        let calendar = LibraryStore.isoCalendar
        func noon(_ month: Int, _ day: Int) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: 2026, month: month,
                                                            day: day, hour: 12)))
        }
        let saturday = try noon(8, 1), sunday = try noon(8, 2), monday = try noon(8, 3)
        let rows = [SessionRow(id: "sat", startDate: saturday, durationS: 3600,
                               sourceClass: "test"),
                    SessionRow(id: "sun", startDate: sunday, durationS: 3600,
                               sourceClass: "test"),
                    SessionRow(id: "mon", startDate: monday, durationS: 7200,
                               sourceClass: "test")]
        let weeks = LibraryStore.weeks(rows, since: nil, until: monday)

        #expect(weeks.count == 2, "27 Jul and 3 Aug, and nothing in between")
        #expect(weeks.map(\.count) == [2, 1], "the Sunday joins the Saturday's week")
        #expect(weeks.map(\.hours) == [2, 2])
        let starts = weeks.map { calendar.component(.weekday, from: $0.weekStart) }
        #expect(starts.allSatisfy { $0 == 2 }, "every bucket opens on a Monday")
        #expect(weeks[1].weekStart == calendar.startOfDay(for: monday))
        #expect(weeks[0].weekStart == calendar.date(byAdding: .day, value: -7,
                                                    to: weeks[1].weekStart))
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
