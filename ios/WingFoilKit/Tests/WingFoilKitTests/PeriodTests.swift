import Foundation
import GRDB
import Testing
@testable import WingFoilKit

/// Periods, held to the analyzer's own answer.
///
/// `fixtures/periods/periods.expected.json` carries ten synthetic afternoons **and** the
/// trips, months, seasons and custom ranges `web/lab_bundle/library.py` makes of them. This
/// suite builds the same library out of the `sessions` half and asserts the rest, entry for
/// entry, string for string.
///
/// It is a file rather than a second set of hand-written expectations on purpose. Two suites
/// that agree today are not two implementations that cannot drift: the block is fifteen
/// numbers in one order with one set of formatters, and the only way to keep that true across
/// a Python module and a Swift one is to make one of them the reference and check the other
/// against it. Python is the reference (docs/presentation.md, "Periods").
@Suite struct PeriodTests {

    // MARK: - The fixture

    struct Fixture: Decodable {
        struct Session: Decodable {
            let id: String
            let spot: String
            let startUtc: String
            let utcOffsetS: Int
            let lat: Double?
            let lon: Double?
            let rateDurationS: Double
            let durationS: Double
            let distanceKm: Double
            let foilTimeS: Double
            let foilPct: Double
            let flightCount: Int
            let longestFlightS: Double
            let jibes: Int
            let jibesSuccessful: Int
            let turnsCounted: Int
            let longestDryStreak: Int?
            let wetExits: Int?
            let best2sKn: Double
            let best10sKn: Double?
        }
        struct Rules: Decodable {
            let tripGapDays: Int
            let tripMinSessions: Int
            let tripRadiusM: Double
            let seasonStartMonth: Int
            let minJibesForRate: Int
            let blockOrder: [String]
            let leanKeys: [String]
        }
        struct Expected: Decodable {
            let kind: String
            let key: String
            let title: String
            let spot: String?
            let dateLine: String
            let spanShort: String
            let startDate: String?
            let endDate: String?
            let sessionIds: [String]
            let sessions: Int
            let block: [PeriodBlock.Entry]
            let start: String?
            let end: String?
        }
        let rules: Rules
        let sessions: [Session]
        let trips: [Expected]
        let months: [Expected]
        let seasons: [Expected]
        let custom: [Expected]
    }

    static func loadFixture() throws -> Fixture {
        let url = testFixturesDir
            .appendingPathComponent("periods")
            .appendingPathComponent("periods.expected.json")
        return try JSONDecoder().decode(Fixture.self, from: try Data(contentsOf: url))
    }

    /// The fixture's sessions as the rows the phone would hold.
    ///
    /// A row with no fix gets no `spotId` of its own; it is placed by the spot it is already
    /// assigned to, which is the phone's equivalent of the analyzer's filename-derived name —
    /// so it is given the same spot every other "Nago Torbole" afternoon has, exactly as
    /// `SpotClusterer.assign` would have left it.
    static func library(_ fixture: Fixture) async throws -> LibraryStore {
        let database = try AppDatabase.inMemory()
        var ids: [String: String] = [:]
        for session in fixture.sessions where ids[session.spot] == nil {
            ids[session.spot] = UUID().uuidString
        }
        let spotIds = ids
        try await database.writer.write { db in
            for (name, id) in spotIds.sorted(by: { $0.key < $1.key }) {
                let anchor = fixture.sessions.first { $0.spot == name && $0.lat != nil }
                try SpotRow(id: id, name: name, lat: anchor?.lat ?? 0, lon: anchor?.lon ?? 0,
                            radiusM: SpotClusterer.defaultRadiusM).insert(db)
            }
            for session in fixture.sessions {
                var row = SessionRow(id: session.id,
                                     startDate: try #require(iso(session.startUtc)),
                                     durationS: session.durationS, sourceClass: "b")
                row.startUtcOffsetS = session.utcOffsetS
                row.startUtcOffsetSource = UtcOffsetSource.activity.rawValue
                row.startLat = session.lat
                row.startLon = session.lon
                row.spotId = spotIds[session.spot]
                row.rateDurationS = session.rateDurationS
                row.distanceKm = session.distanceKm
                row.foilTimeS = session.foilTimeS
                row.foilPct = session.foilPct
                row.flightCount = session.flightCount
                row.longestFlightS = session.longestFlightS
                row.jibes = session.jibes
                row.jibesSuccessful = session.jibesSuccessful
                row.turnsCounted = session.turnsCounted
                row.longestDryStreak = session.longestDryStreak
                row.wetExits = session.wetExits
                row.best2sKn = session.best2sKn
                row.best10sKn = session.best10sKn
                try row.insert(db)
            }
        }
        return LibraryStore(database: database)
    }

    static func iso(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: text)
    }

    static func expect(_ got: Period, _ want: Fixture.Expected, _ label: String) {
        #expect(got.kind.rawValue == want.kind, "\(label): kind")
        #expect(got.key == want.key, "\(label): key")
        #expect(got.title == want.title, "\(label): title")
        #expect(got.spot == want.spot, "\(label): spot")
        #expect(got.dateLine == want.dateLine, "\(label): dateLine")
        #expect(got.spanShort == want.spanShort, "\(label): spanShort")
        #expect(got.startDate == want.startDate, "\(label): startDate")
        #expect(got.endDate == want.endDate, "\(label): endDate")
        #expect(got.sessionIds == want.sessionIds, "\(label): sessionIds")
        #expect(got.sessions == want.sessions, "\(label): session count")
        #expect(got.block == want.block, "\(label): block")
    }

    // MARK: - The contract

    /// The rules the two implementations share, as constants, before any of them is applied:
    /// a difference here is a difference in every period below, and this says which one.
    @Test func theRulesAreTheAnalyzersRules() throws {
        let rules = try Self.loadFixture().rules
        #expect(rules.tripGapDays == PeriodRules.tripGapDays)
        #expect(rules.tripMinSessions == PeriodRules.tripMinSessions)
        #expect(rules.tripRadiusM == PeriodRules.tripRadiusM)
        #expect(rules.seasonStartMonth == PeriodRules.seasonStartMonth)
        #expect(rules.minJibesForRate == SessionRecordKind.minJibesForRate)
        #expect(rules.blockOrder == PeriodBlock.order)
        #expect(rules.leanKeys == PeriodBlock.leanKeys)
    }

    @Test func tripsMatchTheAnalyzer() async throws {
        let fixture = try Self.loadFixture()
        let got = try await Self.library(fixture).periods().trips
        #expect(got.count == fixture.trips.count)
        for (period, want) in zip(got, fixture.trips) {
            Self.expect(period, want, "trip \(want.key)")
        }
        // The two facts the fixture is *designed* to force, said out loud so a regression
        // names itself: a three-day gap holds a trip together, and a four-day gap does not.
        #expect(got.contains { $0.sessionIds == ["a1", "a2", "a3"] })
        #expect(got.allSatisfy { !$0.sessionIds.contains("a4") })
    }

    @Test func monthsMatchTheAnalyzer() async throws {
        let fixture = try Self.loadFixture()
        let got = try await Self.library(fixture).periods().months
        #expect(got.count == fixture.months.count)
        for (period, want) in zip(got, fixture.months) {
            Self.expect(period, want, "month \(want.key)")
        }
        // 22:30 UTC on 31 August at +02:00 is a September afternoon where the rider stood.
        #expect(got.first { $0.key == "2026-09" }?.sessionIds == ["a5"])
        #expect(got.first { $0.key == "2026-08" }?.sessionIds.contains("a5") == false)
    }

    @Test func seasonsMatchTheAnalyzer() async throws {
        let fixture = try Self.loadFixture()
        let got = try await Self.library(fixture).periods().seasons
        #expect(got.count == fixture.seasons.count)
        for (period, want) in zip(got, fixture.seasons) {
            Self.expect(period, want, "season \(want.key)")
        }
        // The two spellings: a season that reached February has a second half to its name.
        #expect(got.map(\.title) == ["Season 2027", "Season 2026/27"])
    }

    @Test func customRangesMatchTheAnalyzer() async throws {
        let fixture = try Self.loadFixture()
        let store = try await Self.library(fixture)
        for want in fixture.custom {
            let got = try await store.periodBlock(from: want.start, to: want.end)
            Self.expect(got, want, "custom \(want.start ?? "…")→\(want.end ?? "…")")
        }
    }

    // MARK: - The block's own rules

    /// A period whose rows cannot supply a fact drops the entry rather than printing a zero.
    /// The fixture's last afternoon has no swims, no streak, no 10 s record and only three
    /// jibes, and the season built out of it alone must be four entries shorter.
    @Test func anUnanswerableFactIsDroppedAndNeverZeroed() async throws {
        let fixture = try Self.loadFixture()
        let sparse = try await Self.library(fixture).periods().seasons
            .first { $0.key == "2027" }
        let keys = Set((sparse?.block ?? []).map(\.key))
        #expect(!keys.contains(PeriodBlock.Key.wph))
        #expect(!keys.contains(PeriodBlock.Key.longestDryStreak))
        #expect(!keys.contains(PeriodBlock.Key.best10s))
        #expect(!keys.contains(PeriodBlock.Key.cleanJibeRate))
        #expect(keys.contains(PeriodBlock.Key.sessions))
        // A measured zero is still a value, and prints as one.
        var f = PeriodBlock.Facts()
        f.hours = 1
        f.wph = 0
        #expect(PeriodBlock.entries(f).first { $0.key == PeriodBlock.Key.wph }?.value == "0.0")
    }

    /// Rates over a period divide the period's own totals, never the mean of the sessions'.
    @Test func aRateOverAPeriodDividesSummedBySummed() async throws {
        let base = Date(timeIntervalSince1970: 1_785_000_000)
        func row(_ id: String, day: Double, seconds: Double, jibes: Int, clean: Int) -> SessionRow {
            var row = SessionRow(id: id, startDate: base.addingTimeInterval(day * 86_400),
                                 durationS: seconds, sourceClass: "b")
            row.startUtcOffsetS = 0
            row.rateDurationS = seconds
            row.jibes = jibes
            row.jibesSuccessful = clean
            return row
        }
        let rows = [row("short", day: 0, seconds: 600, jibes: 6, clean: 1),
                    row("long", day: 1, seconds: 10_800, jibes: 12, clean: 3)]
        let block = Dictionary(uniqueKeysWithValues:
            PeriodBlock.entries(LibraryStore.facts(rows)).map { ($0.key, $0.value) })
        #expect(block[PeriodBlock.Key.hours] == "3.2 h")
        #expect(block[PeriodBlock.Key.cleanJibes] == "4")
        #expect(block[PeriodBlock.Key.cph] == "1.3")        // 4 over 3 h 10 min
        #expect(block[PeriodBlock.Key.cph] != "3.5")        // …and not the mean of 6.0 and 1.0
    }

    /// The denominator is the engine's own cleaned span, so a period holding one afternoon
    /// reports that afternoon's CPH rather than a second opinion about it.
    @Test func aPeriodDividesByTheEnginesOwnSpan() {
        var row = SessionRow(id: "one", startDate: Date(timeIntervalSince1970: 1_785_000_000),
                             durationS: 5400, sourceClass: "b")
        row.startUtcOffsetS = 0
        row.rateDurationS = 3600
        row.jibes = 8
        row.jibesSuccessful = 5
        let with = Dictionary(uniqueKeysWithValues:
            PeriodBlock.entries(LibraryStore.facts([row])).map { ($0.key, $0.value) })
        #expect(with[PeriodBlock.Key.cph] == "5.0")

        // A row the v12 sweep has not refilled falls back to the raw span, which is what
        // this layer divided by before the column existed.
        row.rateDurationS = nil
        let without = Dictionary(uniqueKeysWithValues:
            PeriodBlock.entries(LibraryStore.facts([row])).map { ($0.key, $0.value) })
        #expect(without[PeriodBlock.Key.cph] == "3.3")
    }

    /// The filter every other aggregate screen honours narrows a holiday too — and the
    /// example session, a provisional row and a friend's afternoon are in nobody's trip.
    @Test func periodsHonourTheLibraryFilterAndItsExclusions() async throws {
        let database = try AppDatabase.inMemory()
        let base = Date(timeIntervalSince1970: 1_785_000_000)
        try await database.writer.write { db in
            for (index, id) in ["mine", "theirs", "demo"].enumerated() {
                var row = SessionRow(id: id,
                                     startDate: base.addingTimeInterval(Double(index) * 86_400),
                                     durationS: 3600, sourceClass: "b")
                row.startUtcOffsetS = 0
                row.rateDurationS = 3600
                row.startLat = 45.876
                row.startLon = 10.871
                row.rider = id == "theirs" ? "Max" : nil
                row.isExample = id == "demo"
                try row.insert(db)
            }
        }
        let set = try await LibraryStore(database: database).periods()
        #expect(set.trips.isEmpty, "one countable afternoon is not a holiday")
        #expect(set.months.first?.sessionIds == ["mine"])
    }
}
