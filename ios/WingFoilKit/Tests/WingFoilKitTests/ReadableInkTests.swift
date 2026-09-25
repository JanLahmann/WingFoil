import XCTest
@testable import WingFoilKit

/// Every readable ink against every ground, in both appearances — the 4.5 : 1 floor is a
/// property of the pair, so a nudge to either value that breaks it fails here.
final class ReadableInkTests: XCTestCase {

    func testContrastMatchesWcagReferencePoints() {
        XCTAssertEqual(ReadableInk.contrast(0x000000, 0xFFFFFF), 21, accuracy: 0.01)
        XCTAssertEqual(ReadableInk.contrast(0x777777, 0xFFFFFF), 4.48, accuracy: 0.01)
        XCTAssertEqual(ReadableInk.contrast(0x123456, 0x123456), 1, accuracy: 0.0001)
    }

    func testEveryInkMeetsAaOnEveryGround() {
        for ink in [ReadableInk.secondary, ReadableInk.link] {
            for ground in ReadableInk.lightGrounds {
                XCTAssertGreaterThanOrEqual(ReadableInk.contrast(ink.light, ground),
                                            ReadableInk.minimumContrast,
                                            String(format: "%06X on %06X", ink.light, ground))
            }
            for ground in ReadableInk.darkGrounds {
                XCTAssertGreaterThanOrEqual(ReadableInk.contrast(ink.dark, ground),
                                            ReadableInk.minimumContrast,
                                            String(format: "%06X on %06X", ink.dark, ground))
            }
        }
    }

    /// What this replaced, so the reason stays on record: the system tertiary label and the
    /// accent mint on a light list are both under the floor.
    func testWhatItReplacedWasUnderTheFloor() {
        // tertiaryLabel (60,60,67 at 30 %) flattened onto the grouped background.
        XCTAssertLessThan(ReadableInk.contrast(0xC5C5C9, 0xF2F2F7), ReadableInk.minimumContrast)
        XCTAssertLessThan(ReadableInk.contrast(0x2EE6A8, 0xFFFFFF), ReadableInk.minimumContrast)
    }
}
