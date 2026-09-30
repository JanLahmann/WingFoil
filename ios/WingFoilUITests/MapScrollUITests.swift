import XCTest

/// **One finger on an inline map scrolls the page** (rule 4 in `ScrubPan`, Jan 30 Sep 2026:
/// "scroll up still struggles"). A swipe up that starts on the map must move the page — the
/// map's own frame climbs the screen — rather than pan the map in place.
///
/// Runs on the `WingFoil Dev` scheme with the staging hooks as launch environment:
///
///     xcodebuild test -project WingFoil.xcodeproj -scheme "WingFoil Dev" \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:WingFoilUITests
final class MapScrollUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSwipeUpOnTheRideMapScrollsThePage() {
        assertSwipeUpScrolls(extra: [:])
    }

    func testSwipeUpOnTheTurnsMapScrollsThePage() {
        assertSwipeUpScrolls(extra: ["UI_OPEN_TURNS": "1"])
    }

    /// **Back to the top** (Jan, 30 Sep 2026, on 119: "Turns page still did not scroll up").
    /// Scroll the Turns tab well down in the gutter, then drag DOWN from the middle of the
    /// screen — over the map, the list or the filter rows, wherever the thumb lands — and the
    /// page must come back until the turn-type segments are on screen again.
    func testTheTurnsTabScrollsBackToTheTop() {
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_IMPORT_FIXTURES": "1", "UI_OPEN_SESSION": "latest",
                                 "UI_OPEN_TURNS": "1"]
        app.launch()
        let segments = app.segmentedControls.element(boundBy: 1)
        XCTAssertTrue(segments.waitForExistence(timeout: 300), "no filter segments")
        Thread.sleep(forTimeInterval: 5)
        let top0 = segments.frame.minY
        let win = app.windows.firstMatch
        for _ in 0..<6 {
            win.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.85))
                .press(forDuration: 0.05, thenDragTo:
                    win.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.2)))
        }
        Thread.sleep(forTimeInterval: 1)
        XCTAssertLessThan(segments.frame.minY, top0 - 400, "the gutter swipes did not scroll down")
        let down = segments.frame.minY
        for _ in 0..<8 where segments.frame.minY < top0 - 5 {
            win.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                .press(forDuration: 0.05, thenDragTo:
                    win.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
        }
        Thread.sleep(forTimeInterval: 1)
        XCTAssertGreaterThan(segments.frame.minY, down + 300,
                             "dragging down mid-screen did not bring the page back: \(down) → \(segments.frame.minY)")
    }

    private func assertSwipeUpScrolls(extra: [String: String],
                                      file: StaticString = #filePath, line: UInt = #line) {
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_IMPORT_FIXTURES": "1", "UI_OPEN_SESSION": "latest"]
            .merging(extra) { $1 }
        app.launch()

        // The import and the first analysis take over a minute on a cold simulator.
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 300), "no map on the session page",
                      file: file, line: line)
        // Bring the map fully on screen first (the Turns map sits under the turn cards),
        // swiping in the left gutter rather than on the map.
        let window = app.windows.firstMatch.frame
        for _ in 0..<8 where map.frame.maxY > window.maxY - 120 {
            let top = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.8))
            let up = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.45))
            top.press(forDuration: 0.05, thenDragTo: up)
        }
        // Let the page settle (the analysis finishing can reflow what is above the map).
        var before = map.frame
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 1)
            if map.frame == before { break }
            before = map.frame
        }
        XCTAssertGreaterThan(before.height, 100, file: file, line: line)

        // One finger, from the map's lower part upwards, ending on the map too.
        let start = map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        let end = map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .default,
                    thenHoldForDuration: 0.2)
        Thread.sleep(forTimeInterval: 1)

        let after = map.frame
        XCTAssertLessThan(after.minY, before.minY - 60,
                          "the page did not scroll: the map stayed at \(before.minY), now \(after.minY)",
                          file: file, line: line)
    }
}
