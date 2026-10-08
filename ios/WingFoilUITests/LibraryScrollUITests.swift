import XCTest

/// **The first scroll down the Sessions list is smooth** (Jan, 1 Oct 2026, dev 126:
/// "scrolling down on the sessions page is hakelig when scrolling for the first time").
///
/// A library of Jan's size — the fifteen fixtures, each copied six times
/// (`UI_FIXTURE_COPIES`), 105 rows — is scrolled top to bottom by the app itself
/// (`ScrollHitchMeter`, `UI_HITCH_METER`) on two launches:
///
/// - **fresh**: straight after a reset and an import, every row met for the first time
///   (nothing in memory, most outlines not yet built);
/// - **relaunch**: the same library on the next launch — on disk, not in memory — which is
///   the rider's first scroll of every day.
///
/// The number is Apple's hitch time ratio, ms of hitch per second of scrolling; Apple calls
/// under 5 good and over 10 critical on a device. A simulator runs a debug build on a Mac
/// shared with whatever else is building, so the ceiling is a regression guard, not a
/// promise about a phone (`ceiling`). Runs on `WingFoil Dev`:
///
///     xcodebuild test -project WingFoil.xcodeproj -scheme "WingFoil Dev" \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
///       -only-testing:WingFoilUITests/LibraryScrollUITests
final class LibraryScrollUITests: XCTestCase {

    /// ms of hitch per second of scrolling, the ceiling every run must stay under. A
    /// regression guard sized to the simulator, not Apple's 5 ms/s for a phone: a debug
    /// build on a shared Mac measured 850–980 before the fix (1 Oct 2026) and 60–110 after,
    /// so a row that goes back to costing what it did fails by a factor of three.
    static let ceiling = 250.0

    override func setUp() {
        continueAfterFailure = true
    }

    func testTheFirstScrollIsSmooth() {
        runPair(backdrop: false)
    }

    func testTheFirstScrollIsSmoothWithTheMapBackdrop() {
        runPair(backdrop: true)
    }

    private func runPair(backdrop: Bool) {
        let name = backdrop ? "backdrop" : "plain"
        let meter = ["UI_HITCH_METER": "1", "UI_HITCH_MIN_ROWS": "90", "UI_HITCH_DELAY": "5"]

        let app = XCUIApplication()
        app.launchArguments = ["-listMapBackdrop", backdrop ? "YES" : "NO"]
        app.launchEnvironment = meter.merging(["UI_RESET": "1", "UI_IMPORT_FIXTURES": "1",
                                               "UI_FIXTURE_COPIES": "6"]) { $1 }
        var done = doneExpectation()
        app.launch()
        let fresh = result(app, done, timeout: 900)
        app.terminate()

        app.launchEnvironment = meter
        done = doneExpectation()
        app.launch()
        let relaunch = result(app, done, timeout: 300)
        app.terminate()

        print("LIST HITCH \(name) fresh ratio=\(fresh.ratio) \(fresh.summary)")
        print("LIST HITCH \(name) relaunch ratio=\(relaunch.ratio) \(relaunch.summary)")
        XCTAssertLessThan(fresh.ratio, Self.ceiling, "\(name), fresh: \(fresh.summary)")
        XCTAssertLessThan(relaunch.ratio, Self.ceiling, "\(name), relaunch: \(relaunch.summary)")
    }

    /// Waits — without touching the app, whose main thread is what is being measured — for
    /// the meter's "done" (a Darwin notification), then reads its label once.
    private func result(_ app: XCUIApplication, _ done: XCTestExpectation,
                        timeout: TimeInterval) -> (summary: String, ratio: Double) {
        wait(for: [done], timeout: timeout)
        let label = app.staticTexts["scrollHitchMeter"]
        let summary = label.waitForExistence(timeout: 10) ? label.label : ""
        return (summary, Self.ratio(summary))
    }

    /// Armed before each launch, so a fast run cannot post before anyone listens.
    private func doneExpectation() -> XCTestExpectation {
        XCTDarwinNotificationExpectation(
            notificationName: "de.lahmann.wingfoil.uitest.hitchMeterDone")
    }

    /// `hitchMs / activeS` from "hitchMs=… activeS=… frames=… …".
    static func ratio(_ summary: String) -> Double {
        var fields: [String: Double] = [:]
        for part in summary.split(separator: " ") {
            let pair = part.split(separator: "=")
            if pair.count == 2, let value = Double(pair[1]) { fields[String(pair[0])] = value }
        }
        guard let ms = fields["hitchMs"], let s = fields["activeS"], s > 0 else {
            return .infinity
        }
        return ms / s
    }
}
