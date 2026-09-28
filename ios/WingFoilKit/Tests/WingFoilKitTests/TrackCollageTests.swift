import Foundation
import Testing
@testable import WingFoilKit

/// The period card's collage: every session's own small track in a grid, the same grid on
/// both platforms. `fixtures/periods/outlines.expected.json` (`collage`) is written by
/// `web/tools/make_presentation_goldens.py`; `verify_presentation.py` §5e holds
/// `collageCells` in web/js/sharecard.js to the same file.
@Suite struct TrackCollageTests {

    struct Fixture: Decodable {
        struct Collage: Decodable {
            struct Rule: Decodable {
                let limit: Int
                let gap: Double
            }
            struct Case: Decodable {
                let name: String
                let count: Int
                let box: TrackStackTests.Fixture.Box
                let cells: [[Double]]
            }
            let rule: Rule
            let cases: [Case]
        }
        let collage: Collage
    }

    static func load() throws -> Fixture.Collage {
        let url = testFixturesDir
            .appendingPathComponent("periods")
            .appendingPathComponent("outlines.expected.json")
        return try JSONDecoder().decode(Fixture.self, from: try Data(contentsOf: url)).collage
    }

    @Test func theRulesAreTheFixturesRules() throws {
        let rule = try Self.load().rule
        #expect(rule.limit == TrackCollage.limit)
        #expect(rule.gap == TrackCollage.gap)
    }

    @Test func everyCellIsWhereTheFixtureSays() throws {
        let collage = try Self.load()
        #expect(!collage.cases.isEmpty)
        for want in collage.cases {
            let box = TrackStack.Box(x: want.box.x, y: want.box.y, w: want.box.w, h: want.box.h)
            let got = TrackCollage.cells(count: want.count, in: box).map {
                [$0.x, $0.y, $0.w, $0.h].map(TrackStackTests.round6)
            }
            #expect(got == want.cells.map { $0.map(TrackStackTests.round6) }, "\(want.name)")
        }
    }

    /// A trivial ranking (fixed clean count, no best 2 s) that reduces `pick` to "the
    /// newest twelve" — the fixture-free cases exercise the tie-break chain on its own.
    private struct Session {
        let id: String
        let clean: Int
        let best2s: Double?
        let start: Date
    }

    private static func pick(_ sessions: [Session]) -> [String] {
        TrackCollage.pick(sessions, clean: \.clean, best2s: \.best2s, start: \.start)
            .map(\.id)
    }

    /// Every session tied on the ladder: the newest twelve win, still oldest first — a
    /// season's collage stays chronological even once the frames were chosen for merit.
    @Test func aLongPeriodKeepsItsNewestTwelveInOrder() {
        let sessions = (1...40).map {
            Session(id: "s\($0)", clean: 0, best2s: nil,
                    start: Date(timeIntervalSince1970: Double($0)))
        }
        let picked = Self.pick(sessions)
        #expect(picked.count == TrackCollage.limit)
        #expect(picked.first == "s29")
        #expect(picked.last == "s40")

        let two = [Session(id: "a", clean: 0, best2s: nil, start: Date(timeIntervalSince1970: 1)),
                   Session(id: "b", clean: 0, best2s: nil, start: Date(timeIntervalSince1970: 2))]
        #expect(Self.pick(two) == ["a", "b"])
        #expect(TrackCollage.cells(count: 0, in: TrackStack.Box(x: 0, y: 0, w: 10, h: 10))
                    .isEmpty)
    }

    /// The most clean jibes wins, whatever the date — the whole point of "best", not
    /// "latest".
    @Test func moreCleanJibesOutranksNewer() {
        let sessions = [
            Session(id: "a", clean: 10, best2s: nil, start: Date(timeIntervalSince1970: 1)),
            Session(id: "b", clean: 3, best2s: nil, start: Date(timeIntervalSince1970: 2)),
        ]
        #expect(TrackCollage.best(sessions, clean: \.clean, best2s: \.best2s,
                                  start: \.start)?.id == "a")
    }

    /// A tie in clean jibes goes to the higher best 2 s; a session with none ranks below
    /// one that has it, whatever the count.
    @Test func tiedCleanJibesGoToTheHigherBest2s() {
        let sessions = [
            Session(id: "a", clean: 5, best2s: 12.0, start: Date(timeIntervalSince1970: 1)),
            Session(id: "b", clean: 5, best2s: 18.0, start: Date(timeIntervalSince1970: 2)),
            Session(id: "c", clean: 5, best2s: nil, start: Date(timeIntervalSince1970: 3)),
        ]
        let best = TrackCollage.best(sessions, clean: \.clean, best2s: \.best2s, start: \.start)
        #expect(best?.id == "b")
    }

    /// A session with no ladder at all — no clean jibes and no best 2 s — ranks last.
    @Test func aSessionWithNoLadderRanksLast() {
        let sessions = [
            Session(id: "a", clean: 0, best2s: nil, start: Date(timeIntervalSince1970: 99)),
            Session(id: "b", clean: 1, best2s: nil, start: Date(timeIntervalSince1970: 1)),
        ]
        #expect(TrackCollage.best(sessions, clean: \.clean, best2s: \.best2s,
                                  start: \.start)?.id == "b")
    }

    /// `pick` keeps the best `limit`, still returned oldest first.
    @Test func pickKeepsTheBestInDateOrder() {
        var sessions = (1...20).map {
            Session(id: "s\($0)", clean: 1, best2s: nil,
                    start: Date(timeIntervalSince1970: Double($0)))
        }
        // The two weakest by date (oldest) are made the two strongest by clean jibes, so a
        // pure "newest limit" pick would drop them and a ranked pick keeps them, still at
        // the front — in date order.
        sessions[0] = Session(id: "s1", clean: 99, best2s: nil,
                              start: Date(timeIntervalSince1970: 1))
        sessions[1] = Session(id: "s2", clean: 50, best2s: nil,
                              start: Date(timeIntervalSince1970: 2))
        let picked = Self.pick(sessions)
        #expect(picked.count == TrackCollage.limit)
        #expect(picked.first == "s1")
        #expect(picked[1] == "s2")
        #expect(picked == picked.sorted { Int($0.dropFirst())! < Int($1.dropFirst())! })
    }
}
