import XCTest
@testable import WingFoilKit

/// Every number VoiceOver reads is read with its word, in the rider's vocabulary.
final class SpokenFiguresTests: XCTestCase {

    func testTallyReadsEachNumberWithItsWord() {
        XCTAssertEqual(SpokenFigures.tally(flewThrough: 42, touchdown: 3, fellIn: 5),
                       "42 flew through, 3 touchdowns, 5 fell in")
        XCTAssertEqual(SpokenFigures.tally(flewThrough: 1, touchdown: 1, fellIn: 0),
                       "1 flew through, 1 touchdown, 0 fell in")
    }

    func testTallyNeverUsesEngineWords() {
        let spoken = SpokenFigures.tally(flewThrough: 2, touchdown: 2, fellIn: 2).lowercased()
        for word in ["success", "carried", "falls", "swim"] {
            XCTAssertFalse(spoken.contains(word), word)
        }
    }

    func testTurnPin() {
        XCTAssertEqual(SpokenFigures.turnPin(type: "Jibe", clock: "14:03",
                                             outcome: .flewThrough, clean: true),
                       "Jibe at 14:03, flew through, clean")
        XCTAssertEqual(SpokenFigures.turnPin(type: "Tack", clock: "0:42",
                                             outcome: .fellIn, clean: false),
                       "Tack at 0:42, fell in")
    }

    func testSeriesSummary() {
        let fmt: (Double) -> String = { String(format: "%.0f %%", $0) }
        XCTAssertEqual(SpokenFigures.series(title: "On foil", values: [40, 72, 64], format: fmt),
                       "On foil, 3 sessions, latest 64 %, lowest 40 %, highest 72 %")
        XCTAssertEqual(SpokenFigures.series(title: "On foil", values: [55], format: fmt),
                       "On foil, 1 session, latest 55 %")
        XCTAssertEqual(SpokenFigures.series(title: "On foil", values: [], format: fmt),
                       "On foil, no sessions in this range")
    }
}
