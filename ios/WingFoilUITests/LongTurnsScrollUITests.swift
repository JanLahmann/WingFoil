import XCTest

/// **Scrolling back up a long Turns tab** (Jan, 30 Sep 2026, dev 124 on an iPhone 17 Pro Max:
/// "scroll in 124 does not work" — a session of 79 turns, the page stalled on the way up
/// with the Turns section's heading just under the pinned switcher). The fixture session
/// with the most turns (`foilmotion`, 69) parked at that position; slow drags DOWN from
/// mid-screen, the thumb resting first, must each bring the page back.
///
/// Runs on the `WingFoil Dev` scheme like `MapScrollUITests`.
final class LongTurnsScrollUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    func testALongTurnsTabScrollsBackUpFromUnderTheSwitcher() {
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_IMPORT_FIXTURES": "1", "UI_OPEN_SESSION": "foilmotion",
                                 "UI_OPEN_TURNS": "1"]
        app.launch()
        // "All 69 turns", found by its words so the test needs nothing from the page.
        let heading = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH 'All ' AND label ENDSWITH ' turns'")).firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 400), "no turns heading")
        Thread.sleep(forTimeInterval: 5)
        let win = app.windows.firstMatch
        let height = win.frame.height

        // Jan's screenshot: the heading just under the pinned bar (the switcher, and on
        // this tab the two filter rows). Then the thumb on the map in the middle of the
        // screen, resting, and a slow pull down; and a quicker one. Each must move the page
        // — the resting ones stood still while MapKit's own one-finger press held the touch
        // (`MapFingerRecognizer.twoFingerPan`).
        let presses: [(TimeInterval, XCUIGestureVelocity, String)] = [
            (0.4, .slow, "resting, slow"), (0.4, .default, "resting"),
            (0.05, .slow, "quick, slow"), (0.05, .default, "quick"),
        ]
        for round in 0..<2 {
          for (hold, velocity, how) in presses {
            let name = "round \(round), \(how)"
            park(heading, at: 0.3, in: win, height: height)
            let before = heading.frame.minY
            XCTAssertLessThan(before, height * 0.4, "\(name): not parked (\(before))")
            // On the map (Jan's screenshot: the middle of the screen *is* the map).
            let map = app.maps.firstMatch
            XCTAssertTrue(map.exists && map.frame.minY < height * 0.7
                          && map.frame.maxY > height * 0.4, "\(name): the map is not mid-screen")
            map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
                .press(forDuration: hold, thenDragTo:
                    win.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)),
                       withVelocity: velocity, thenHoldForDuration: 0.2)
            Thread.sleep(forTimeInterval: 1)
            let after = heading.frame.minY
            XCTAssertGreaterThan(after, before + 120,
                                 "\(name): a drag down mid-screen did not scroll the page: "
                                 + "\(before) → \(after)")
          }
        }
    }

    /// **Jan's recording** (dev 124, 30 Sep 2026, a 67-turn session): the Turns tab from its
    /// top, down deep into the list, then back up — and the page stopped with the list's
    /// heading under the switcher, never showing "Turns & losses" again. Here: the same trip
    /// on the longest fixture, mid-screen drags on the way up, until the cards are back.
    func testALongTurnsListScrollsBackUpToTheCards() {
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_IMPORT_FIXTURES": "1", "UI_OPEN_SESSION": "foilmotion",
                                 "UI_OPEN_TURNS": "1"]
        app.launch()
        let cards = app.staticTexts["Turns & losses"].firstMatch
        XCTAssertTrue(cards.waitForExistence(timeout: 400), "no Turns & losses")
        Thread.sleep(forTimeInterval: 5)
        let win = app.windows.firstMatch
        let height = win.frame.height
        let top0 = cards.frame.minY
        // Down, deep into the list — about seven screens of it, in the gutter, each drag
        // held at its end so nothing coasts and every run goes the same distance.
        for _ in 0..<7 {
            win.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.85))
                .press(forDuration: 0.05, thenDragTo:
                    win.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.15)),
                       withVelocity: .default, thenHoldForDuration: 0.3)
        }
        Thread.sleep(forTimeInterval: 1.5)
        func y(_ e: XCUIElement) -> CGFloat { e.exists ? e.frame.minY : -.greatestFiniteMagnitude }
        let deep = y(cards)
        XCTAssertLessThan(deep, top0 - 1500, "did not get deep into the list: \(top0) → \(deep)")
        // Up again, mid-screen under the pinned bar, the way a thumb does it, until the cards'
        // title is on screen below the switcher: the same distance back, and some spare.
        var trail: [Int] = []
        for _ in 0..<16 where y(cards) < height * 0.25 {
            win.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                .press(forDuration: 0.05, thenDragTo:
                    win.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)),
                       withVelocity: .default, thenHoldForDuration: 0.3)
            Thread.sleep(forTimeInterval: 0.6)
            let now = y(cards)
            trail.append(now < -100_000 ? -99_999 : Int(now))
        }
        print("LONGTURNS deep trail \(trail)")
        XCTAssertGreaterThan(y(cards), height * 0.25,
                             "the page did not come back to the cards: \(trail)")
    }

    /// Scroll with gutter drags until `element` sits at `fraction` of the screen height.
    private func park(_ element: XCUIElement, at fraction: CGFloat, in win: XCUIElement,
                      height: CGFloat) {
        let target = height * fraction
        for _ in 0..<14 {
            let y = element.frame.minY
            if abs(y - target) < 40 { break }
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
}
