import XCTest

/// **One finger on an inline map scrolls the page** (rule 4 in `ScrubPan`, Jan 30 Sep 2026:
/// "scroll up still struggles"). A swipe up that starts on the map must move the page — the
/// map's own frame climbs the screen — rather than pan the map in place. And the map says so:
/// after a one-finger drag on it the capsule "Use two fingers to move the map" is on it
/// (`MapFingerHint`).
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

    /// **The map says it wants two fingers** (Jan, 30 Sep 2026: "We need to inform the user
    /// that the map needs two fingers to operate"). A short, slow one-finger drag up on the
    /// Ride map — the drag of a rider trying to move it — scrolls the page a little and the
    /// hint is on the map, still on screen. A flick would throw the map off the top first.
    func testAOneFingerDragOnTheMapShowsTheTwoFingerHint() {
        let (app, map, _) = openMap(extra: [:])
        let start = map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let end = map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow,
                    thenHoldForDuration: 0.1)
        // One query for the id and the words: the hint is up for 1.5 s after the finger
        // lifts, and a snapshot of a map with its marks takes a good part of that.
        let hint = app.staticTexts.matching(NSPredicate(
            format: "identifier == 'mapFingerHint' AND label == %@",
            "Use two fingers to move the map")).firstMatch
        let shown = hint.waitForExistence(timeout: 1.5)
        if let path = ProcessInfo.processInfo.environment["MAP_HINT_SHOT"] {
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path))
        }
        XCTAssertTrue(shown, "no two-finger hint on the map")
    }

    /// **Back to the top** (Jan, 30 Sep 2026, on 119: "Turns page still did not scroll up").
    /// Scroll the Turns tab well down in the gutter, then drag DOWN from the middle of the
    /// screen — over the map or the list, wherever the thumb lands — and the page must come
    /// back until the turns heading is where it started. The filter rows are in the pinned
    /// bar and do not move, so the heading under them is what measures the scroll.
    func testTheTurnsTabScrollsBackToTheTop() {
        let (app, heading) = openTurns()
        let top0 = heading.frame.minY
        let win = app.windows.firstMatch
        for _ in 0..<6 {
            win.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.85))
                .press(forDuration: 0.05, thenDragTo:
                    win.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.2)))
        }
        Thread.sleep(forTimeInterval: 1)
        XCTAssertLessThan(heading.frame.minY, top0 - 400, "the gutter swipes did not scroll down")
        let down = heading.frame.minY
        for _ in 0..<8 where heading.frame.minY < top0 - 5 {
            win.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                .press(forDuration: 0.05, thenDragTo:
                    win.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
        }
        Thread.sleep(forTimeInterval: 1)
        XCTAssertGreaterThan(heading.frame.minY, down + 300,
                             "dragging down mid-screen did not bring the page back: \(down) → \(heading.frame.minY)")
    }

    /// **The thumb that scrolls is on the content, never on a segmented control** (Jan, 30
    /// Sep 2026, dev 120: "Scroll back up on turns section still does not work … up
    /// struggles at exactly this position"). The filter rows live in the pinned bar under the
    /// switcher now, so the position of Jan's screenshot — a quarter down the screen, just
    /// under the switcher — is the content below the bar. Park the Turns tab there, then drag
    /// DOWN from mid-screen, flicking and resting first, and the page must come back up each
    /// time. (A long drag may bring the turn cards back and unpin the bar; that is the section
    /// arriving, not the bar scrolling.) A tap on a segment still filters.
    func testADragDownUnderThePinnedFiltersScrollsThePage() {
        continueAfterFailure = true   // every start and every thumb reports, not the first
        let (app, heading) = openTurns()
        let type = app.descendants(matching: .any)["turnTypeFilter"].firstMatch
        let side = app.descendants(matching: .any)["turnSideFilter"].firstMatch
        let win = app.windows.firstMatch
        let height = win.frame.height
        // Where the thumb lands: mid-screen, left and centre, higher and lower.
        let starts: [(CGFloat, CGFloat)] = [(0.17, 0.4), (0.5, 0.4), (0.17, 0.55), (0.5, 0.55)]
        // A quick flick, and a thumb that rests before it moves — the second is what a
        // UIScrollView hands to a UIControl for good (`touchesShouldCancel(in:)`).
        let presses: [(TimeInterval, String)] = [(0.05, "quick"), (0.4, "resting")]
        // Where the bar sits once it is pinned: the first park, one screen into the list.
        park(heading, at: 0.28, in: win, height: height)
        let pinned = side.frame.maxY
        for (dx, dy) in starts {
          for (hold, how) in presses {
            let name = "(\(dx), \(dy)), \(how)"
            park(heading, at: 0.28, in: win, height: height)
            let before = heading.frame.minY
            let bar = side.frame.maxY
            XCTAssertEqual(bar, pinned, accuracy: 2, "\(name): the bar is not pinned")
            XCTAssertLessThan(bar, height * dy, "\(name): the filters are not above the thumb")
            win.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy))
                .press(forDuration: hold, thenDragTo:
                    win.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.9)),
                       withVelocity: .default, thenHoldForDuration: 0.1)
            Thread.sleep(forTimeInterval: 1)
            XCTAssertGreaterThan(heading.frame.minY, before + 80,
                                 "\(name): a drag down mid-screen did not scroll the page: "
                                 + "\(before) → \(heading.frame.minY)")
          }
        }
        // And a tap still picks a segment.
        let jibes = type.buttons["Jibes"]
        jibes.tap()
        XCTAssertTrue(jibes.isSelected, "a tap on Jibes did not select it")
    }

    /// **Segmented controls live in the pinned bar, and only on their tabs.** On Turns the bar
    /// is the switcher and the two filter rows, and it stays put while the list scrolls under
    /// it; on Ride it is the switcher alone. The bar's heights go to the log; with
    /// `SEG_SHOT_DIR` set (as `TEST_RUNNER_SEG_SHOT_DIR`) the two screens are saved there.
    func testTheFilterRowsArePinnedOnlyOnTheirTabs() {
        let (app, heading) = openTurns()
        let win = app.windows.firstMatch
        let height = win.frame.height
        let bar = app.descendants(matching: .any)["sessionPinnedBar"].firstMatch
        XCTAssertTrue(bar.exists, "no pinned bar")
        park(heading, at: 0.28, in: win, height: height)
        let pinned = bar.frame
        // On to the list: two more gutter drags, and the bar has not moved.
        for _ in 0..<2 {
            win.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.8))
                .press(forDuration: 0.05, thenDragTo:
                    win.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.35)))
        }
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(bar.frame.minY, pinned.minY, accuracy: 2, "the bar scrolled away")
        let turns = bar.frame.height
        shoot(app, "turns")

        bar.buttons["Ride"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(app.descendants(matching: .any)["turnTypeFilter"].exists,
                       "the turn filters are still up on Ride")
        let ride = bar.frame.height
        shoot(app, "ride")
        print("PINNED BAR HEIGHT turns=\(turns) ride=\(ride) width=\(bar.frame.width)")
        XCTAssertGreaterThan(turns, ride + 50, "the Turns bar does not carry its two rows")
    }

    /// Launches onto the latest session's Turns tab and waits for the heading of the turn
    /// list, with the page settled.
    private func openTurns() -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_IMPORT_FIXTURES": "1", "UI_OPEN_SESSION": "latest",
                                 "UI_OPEN_TURNS": "1"]
        app.launch()
        let type = app.descendants(matching: .any)["turnTypeFilter"].firstMatch
        XCTAssertTrue(type.waitForExistence(timeout: 300), "no turn-type filter")
        let heading = app.descendants(matching: .any)["turnsHeading"].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 30), "no turns heading")
        Thread.sleep(forTimeInterval: 5)
        return (app, heading)
    }

    private func shoot(_ app: XCUIApplication, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SEG_SHOT_DIR"] else { return }
        try? app.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    /// Scroll with gutter drags until `element` sits at `fraction` of the screen height.
    private func park(_ element: XCUIElement, at fraction: CGFloat, in win: XCUIElement,
                      height: CGFloat) {
        let target = height * fraction
        for _ in 0..<12 {
            let y = element.frame.minY
            if abs(y - target) < 60 { break }
            let span = min(max(abs(y - target), 80), height * 0.5) / height
            let from = y > target ? 0.8 : 0.3
            let to = y > target ? from - span : from + span
            win.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: from))
                .press(forDuration: 0.3, thenDragTo:
                    win.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: to)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
            Thread.sleep(forTimeInterval: 0.8)
        }
    }

    private func assertSwipeUpScrolls(extra: [String: String],
                                      file: StaticString = #filePath, line: UInt = #line) {
        let (_, map, before) = openMap(extra: extra, file: file, line: line)

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

    /// Launches onto the session, brings the map fully on screen and waits for the page to
    /// settle. The hint's counter is held at zero for the run by the argument domain,
    /// whatever earlier runs left in the app's defaults.
    private func openMap(extra: [String: String], file: StaticString = #filePath,
                         line: UInt = #line) -> (XCUIApplication, XCUIElement, CGRect) {
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_IMPORT_FIXTURES": "1", "UI_OPEN_SESSION": "latest"]
            .merging(extra) { $1 }
        app.launchArguments = ["-mapFingerHint.shown.v1", "0"]
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
        return (app, map, before)
    }
}
