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

    /// The newest twelve, still oldest first — a season's collage is its latest afternoons in
    /// the order they were ridden.
    @Test func aLongPeriodKeepsItsNewestTwelveInOrder() {
        let ids = (1...40).map { "s\($0)" }
        let picked = TrackCollage.pick(ids)
        #expect(picked.count == TrackCollage.limit)
        #expect(picked.first == "s29")
        #expect(picked.last == "s40")
        #expect(TrackCollage.pick(["a", "b"]) == ["a", "b"])
        #expect(TrackCollage.cells(count: 0, in: TrackStack.Box(x: 0, y: 0, w: 10, h: 10))
                    .isEmpty)
    }
}
