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
/// against it. Python is the reference (docs/presentation/trends-periods.md, "Periods").
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
            /// T2, the rate denominator. Optional because `a6` has none — a row saved
            /// before digest schema 9 / GRDB v13, which is what pins the fallback.
            let timerTimeS: Double?
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
            /// The two engine rates beside CPH (digest schema 11 / GRDB v17). Optional
            /// because `a6` carries neither — the row the v17 sweep has not reached, which
            /// is what pins the gap in the JPH and TPH lines.
            let jibesPerHour: Double?
            let turnsPerHour: Double?
            /// `c` is the recording that could not certify a speed; it is what pins the
            /// mark on the best-2 s series.
            let sourceClass: String
            /// The period card's story (layout B v2): the tacks, the ladder over every
            /// counted turn and the flew streak. `a6` has no ladder and no streak.
            let tacks: Int
            let outcomes: PeriodCard.Outcomes?
            let longestFlewStreak: Int?
        }
        /// The per-session trend series the analyzer makes of the same ten afternoons.
        struct Trends: Decodable {
            struct Chart: Decodable {
                struct Line: Decodable {
                    struct Point: Decodable {
                        let i: Int
                        let id: String
                        let v: Double?
                        /// Only the speed chart's points carry one.
                        let certified: Bool?
                    }
                    let key: String
                    let label: String
                    let points: [Point]
                }
                let key: String
                let label: String
                let unit: String
                let uncertified: Bool
                let lines: [Line]
            }
            let charts: [Chart]
        }
        struct Rules: Decodable {
            let tripGapDays: Int
            let tripMinSessions: Int
            let tripRadiusM: Double
            let seasonStartMonth: Int
            let minJibesForRate: Int
            let blockOrder: [String]
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
            let mapGround: Bool
            let block: [PeriodBlock.Entry]
            let card: PeriodCard
            let start: String?
            let end: String?
        }
        let rules: Rules
        let sessions: [Session]
        let trends: Trends
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
                                     durationS: session.durationS,
                                     sourceClass: session.sourceClass)
                row.startUtcOffsetS = session.utcOffsetS
                row.startUtcOffsetSource = UtcOffsetSource.activity.rawValue
                row.startLat = session.lat
                row.startLon = session.lon
                row.spotId = spotIds[session.spot]
                row.rateDurationS = session.rateDurationS
                row.timerTimeS = session.timerTimeS
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
                row.engineJibesPerHour = session.jibesPerHour
                row.engineTurnsPerHour = session.turnsPerHour
                row.tacks = session.tacks
                row.turnsFlewThrough = session.outcomes?.flewThrough
                row.turnsTouchdown = session.outcomes?.touchdown
                row.turnsFellIn = session.outcomes?.fellIn
                row.longestFlewStreak = session.longestFlewStreak
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
        #expect(got.mapGround == want.mapGround, "\(label): mapGround")
        #expect(got.block == want.block, "\(label): block")
        #expect(got.card == want.card, "\(label): card")
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

    /// Every displayed duration is T1; every rate denominator is timer time.
    ///
    /// The block prints both, from the same rows, and they are not the same clock: "hours on
    /// the water" sums `rateSeconds` (the engine's cleaned elapsed span) while CPH and WPH
    /// divide by `timerSeconds` (the session minus its pauses) — the denominator the engine
    /// gives the session's own rates since 0.13.0, so a period holding one afternoon reports
    /// that afternoon's CPH rather than a deflated second opinion about it.
    @Test func aPeriodDividesByTheEnginesOwnSpan() {
        var row = SessionRow(id: "one", startDate: Date(timeIntervalSince1970: 1_785_000_000),
                             durationS: 5400, sourceClass: "b")
        row.startUtcOffsetS = 0
        row.rateDurationS = 3600
        row.timerTimeS = 1800
        row.jibes = 8
        row.jibesSuccessful = 5
        row.wetExits = 3
        let with = Dictionary(uniqueKeysWithValues:
            PeriodBlock.entries(LibraryStore.facts([row])).map { ($0.key, $0.value) })
        #expect(with[PeriodBlock.Key.hours] == "1.0 h")   // the shown duration is T1
        #expect(with[PeriodBlock.Key.cph] == "10.0")      // 5 clean in half an hour of timer
        #expect(with[PeriodBlock.Key.cph] != "5.0")       // …not 5 over the elapsed hour
        #expect(with[PeriodBlock.Key.wph] == "6.0")       // the same divisor, 3 swims

        // A row the v13 sweep has not refilled falls back to the elapsed span — the closest
        // clock it stores, and the number this layer divided by before the column existed.
        row.timerTimeS = nil
        let pre13 = Dictionary(uniqueKeysWithValues:
            PeriodBlock.entries(LibraryStore.facts([row])).map { ($0.key, $0.value) })
        #expect(pre13[PeriodBlock.Key.cph] == "5.0")

        // And one the v12 sweep never reached has only the raw sample span to fall back to.
        row.rateDurationS = nil
        let without = Dictionary(uniqueKeysWithValues:
            PeriodBlock.entries(LibraryStore.facts([row])).map { ($0.key, $0.value) })
        #expect(without[PeriodBlock.Key.cph] == "3.3")
    }

    // MARK: - The period card

    /// The card's numbers **are** the block — same entries, same order, same strings — and
    /// its story (layout B v2) prints nothing the block and `Period.card` do not carry. The
    /// same contract `verify_presentation.py` 5d holds the browser's period card to.
    @Test func thePeriodCardIsTheBlockAndTellsItsStory() async throws {
        let fixture = try Self.loadFixture()
        let set = try await Self.library(fixture).periods()
        let periods = set.trips + set.months + set.seasons
        #expect(!periods.isEmpty)

        for period in periods {
            let card = ShareCardStats.make(period: period)
            #expect(card.stats.map(\.key) == period.block.map(\.key))
            #expect(card.stats.map(\.label) == period.block.map(\.label))
            #expect(card.stats.map(\.value) == period.block.map(\.value))
            // The heading and the span are the period's own; the card re-derives neither.
            #expect(card.title == period.title)
            #expect(card.dateLine == period.dateLine)
            // A period spans several recordings, so the speed disclaimer — a claim about one
            // recording's speed channel — has nothing to attach to.
            #expect(card.disclaimer == nil)

            let story = try #require(card.story, "\(period.key): a period card tells a story")
            #expect(story.dateLine == period.dateLine)
            #expect(story.speedNote == nil)
            #expect(!story.heroOptions.contains(.tacks))
            #expect(story.heroOptions.contains(.sessions))
            let values = Set(period.block.map(\.value))
            for cell in story.ribbon where cell.key != "jph" && cell.key != "tph" {
                #expect(values.contains(cell.value), "\(period.key): \(cell.key) is the block's")
            }
            if let o = period.card.outcomes {
                #expect(story.bars.map(\.total) == [o.total])
                #expect(story.bars.first?.kind == period.card.dryKind)
            } else {
                #expect(story.bars.isEmpty)
            }
        }
    }

    /// The hero falls back clean → top speed → sessions, and with 0 clean jibes the clean
    /// number and clean jibes / h are left out (Jan, 26 Sep 2026).
    @Test func thePeriodHeroFallsBackAndZeroCleanIsNeverPrinted() {
        func period(clean: String?, best2s: String?, card: PeriodCard) -> Period {
            var block = [PeriodBlock.Entry(key: "sessions", label: "sessions", value: "3"),
                         PeriodBlock.Entry(key: "hours", label: "hours on the water",
                                           value: "4.5 h"),
                         PeriodBlock.Entry(key: "distance", label: "distance", value: "40.0 km")]
            if let clean {
                block.append(.init(key: "cleanJibes", label: "clean jibes", value: clean))
                block.append(.init(key: "cph", label: "CPH · clean jibes per hour", value: "0.0"))
            }
            if let best2s { block.append(.init(key: "best2s", label: "best 2 s", value: best2s)) }
            block.append(.init(key: "spots", label: "spots visited", value: "1"))
            return Period(kind: .trip, key: "trip:x", title: "Garda", spot: "Garda",
                          dateLine: "1 – 3 August 2026", spanShort: "1 – 3 Aug",
                          startDate: "2026-08-01", endDate: "2026-08-03",
                          sessionIds: ["a", "b", "c"], sessions: 3, mapGround: true,
                          block: block, card: card)
        }
        let ladder = PeriodCard(outcomes: .init(flewThrough: 10, touchdown: 5, fellIn: 5),
                                jibes: 20, tacks: 0, dryKind: "jibes", dryRate: "3.3",
                                flewStreak: 4, dryStreak: 9, falls: 6)
        let zero = Story.make(period: period(clean: "0", best2s: "15.50 kn", card: ladder),
                              hero: .clean)
        #expect(zero.heroOptions == [.max2s, .sessions])
        #expect(zero.hero?.kind == .max2s)
        #expect(zero.hero?.value == "15.50")
        #expect(!zero.ribbon.contains { $0.key == "cph" })
        #expect(zero.bars.first?.right == "of 20 jibes")
        #expect(zero.bars.first?.star == false)
        #expect(zero.ribbon.map(\.key) == ["jph", "sessions", "hours", "distance"])
        #expect(zero.ribbon.map(\.label)
                == ["dry jibes / h", "sessions", "time on the water", "distance"])

        let noSpeed = Story.make(period: period(clean: "0", best2s: nil, card: ladder),
                                 hero: .clean)
        #expect(noSpeed.hero?.kind == .sessions)
        #expect(noSpeed.hero?.unit == "sessions")
        #expect(noSpeed.hero?.sub == "at one spot")
        #expect(!noSpeed.ribbon.contains { $0.key == "sessions" })

        let clean = Story.make(period: period(clean: "7", best2s: "15.50 kn", card: ladder),
                               hero: .clean)
        #expect(clean.hero?.value == "7")
        #expect(clean.hero?.sub == "of 20 jibes")
        #expect(clean.bars.first?.right == nil)
        #expect(clean.ribbon.first?.key == "cph")
        #expect(clean.streak.map(\.text).joined() == "best streak 4 flew · 9 dry")
        #expect(clean.falls.map(\.text).joined() == "fell in 6 times")
    }

    /// **The period card's story is the shared fixture**: for every period the analyzer makes
    /// of the ten afternoons and every hero, the kit's story is the browser's, word for word.
    /// `fixtures/cards/period-stories.expected.json` is dumped by web/tools/card_parity.mjs
    /// and held by verify_presentation.py §5d; this holds `Story.make(period:)` to it.
    @Test func thePeriodStoryIsTheSharedFixture() async throws {
        let url = testFixturesDir.appendingPathComponent("cards/period-stories.expected.json")
        let fixture = try #require(try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)) as? [String: [String: Any]])
        let loaded = try Self.loadFixture()
        let store = try await Self.library(loaded)
        let set = try await store.periods()
        var periods = set.trips + set.months + set.seasons
        for range in loaded.custom {
            periods.append(try await store.periodBlock(from: range.start, to: range.end))
        }
        var checked = 0
        for period in periods {
            let want = try #require(fixture[period.key], "\(period.key): not in the fixture")
            for hero in [ShareCardStats.Hero.clean, .max2s, .sessions] {
                let got = DocumentRendererTests.json(Story.make(period: period, hero: hero))
                let expected = try #require(want[hero.rawValue] as? [String: Any])
                #expect(NSDictionary(dictionary: got).isEqual(to: expected),
                        "\(period.key)/\(hero.rawValue): the kit's story is not the fixture's\n\(got)")
                checked += 1
            }
        }
        #expect(checked == 3 * fixture.count)
    }

    private typealias Story = ShareCardStats.Story

    /// The map ground is offered exactly where a period **has** one: every afternoon inside a
    /// single 3 km cluster, and every one of them placed by a fix.
    ///
    /// The fixture pins the four period kinds against the analyzer's own answer (`expect`
    /// above); this says the rule out loud on the three cases that decide it, because the
    /// failure mode is a switch that appears on a month split between two lakes and draws a
    /// card of the motorway between them.
    @Test func theGroundIsOfferedOnlyWhereAPeriodHasOne() async throws {
        let fixture = try Self.loadFixture()
        let set = try await Self.library(fixture).periods()
        let byKey = Dictionary(uniqueKeysWithValues:
            (set.trips + set.months + set.seasons).map { ($0.key, $0) })

        // A trip is one place by construction, and every afternoon of it is anchored.
        #expect(byKey["trip:a1"]?.mapGround == true)
        // August holds Torbole *and* Malcesine, 12 km apart: two clusters, no single ground.
        #expect(byKey["2026-08"]?.mapGround == false)
        // May 2027 is the one afternoon with no fix — placed by the name of its file, which
        // is enough to file it under a spot and not enough to point a camera at one.
        #expect(byKey["2027-05"]?.sessionIds == ["a6"])
        #expect(byKey["2027-05"]?.mapGround == false)
        // …and the sanity check that it is the *anchor* doing that and not the count: the
        // other one-session months are all offered a ground.
        #expect(byKey["2026-09"]?.mapGround == true)
    }

    /// A title the rider typed wins over the period's own; an empty one leaves it derived.
    @Test func thePeriodCardTakesTheRidersOwnWords() async throws {
        let fixture = try Self.loadFixture()
        let period = try #require(try await Self.library(fixture).periods().trips.first)
        #expect(ShareCardStats.make(period: period, title: "").title == period.title)
        let named = ShareCardStats.make(period: period, title: "Garda, finally",
                                        note: "first week on the new foil")
        #expect(named.title == "Garda, finally")
        #expect(named.note == "first week on the new foil")
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
