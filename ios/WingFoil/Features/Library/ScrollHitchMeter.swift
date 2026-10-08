#if DEBUG && targetEnvironment(simulator)
import QuartzCore
import SwiftUI
import UIKit

/// **The list's own scroll benchmark** — the number `LibraryScrollUITests` asserts on.
///
/// `UI_HITCH_METER=1` on a simulator debug build (docs/testing.md): once the library has
/// loaded and settled, the app scrolls its own Sessions list from the top to the bottom at a
/// steady finger's pace, one display-link frame at a time, and counts every frame that
/// arrived later than one refresh interval after the last — and by how much. The total is
/// Apple's **hitch time ratio**, ms of hitch per second of scrolling (under 5 is good, over
/// 10 critical), and it goes to an invisible label once the bottom is reached.
///
/// The app drives the scroll rather than the test because an XCUITest swipe snapshots the
/// accessibility tree between gestures, on the main thread, and a meter running then counts
/// the test's own stalls as the list's (the first attempt measured 700 ms/s that way).
@MainActor
@Observable
final class ScrollHitchMeter: NSObject {
    static let isWanted = ProcessInfo.processInfo.environment["UI_HITCH_METER"] == "1"

    /// Points per second: a brisk thumb, ~6 rows a second at the default text size.
    static let speed: CGFloat = 1_800

    /// "hitchMs=… activeS=… frames=… hitches=… worstMs=… done=0|1", read by the UI test.
    private(set) var summary = "idle"

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private weak var scroll: UIScrollView?
    @ObservationIgnored private var last: CFTimeInterval = 0
    @ObservationIgnored private var hitchS: Double = 0
    @ObservationIgnored private var worstS: Double = 0
    @ObservationIgnored private var activeS: Double = 0
    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var hitches = 0
    @ObservationIgnored private var started = false

    /// Scrolls the list once, top to bottom. Idempotent: one run per launch.
    func run() {
        guard !started, let scroll = Self.listScrollView() else { return }
        started = true
        self.scroll = scroll
        scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top),
                                animated: false)
        summary = "running"
        // For a profiler on the host: `tmp/hitch-start` in the app's container marks the
        // first frame of the scroll, `tmp/hitch-result` holds the summary at the end.
        try? FileManager.default.removeItem(at: URL.temporaryDirectory.appending(path: "hitch-result"))
        try? Data().write(to: URL.temporaryDirectory.appending(path: "hitch-start"))
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let scroll else { finish(); return }
        defer { last = link.timestamp }
        guard last > 0 else { return }
        let delta = link.timestamp - last
        let expected = max(link.duration, 1.0 / 120)
        activeS += delta
        frames += 1
        if delta > expected * 1.5 {
            hitchS += delta - expected
            worstS = max(worstS, delta - expected)
            hitches += 1
        }
        let bottom = scroll.contentSize.height + scroll.adjustedContentInset.bottom
            - scroll.bounds.height
        // A fixed step per frame, as a finger moves the list: a late frame is a late frame,
        // not a jump of two screens that the next frame then has to lay out.
        let next = min(scroll.contentOffset.y + Self.speed * expected, bottom)
        scroll.contentOffset.y = next
        if next >= bottom - 0.5 { finish() }
    }

    private func finish() {
        link?.invalidate()
        link = nil
        summary = String(format: "hitchMs=%.1f activeS=%.3f frames=%d hitches=%d worstMs=%.1f done=1",
                         hitchS * 1000, activeS, frames, hitches, worstS * 1000)
        try? Data(summary.utf8).write(to: URL.temporaryDirectory.appending(path: "hitch-result"))
        // The test waits on this rather than polling the label: every look at the label is
        // an accessibility snapshot on the main thread being measured.
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(Self.doneNotification as CFString),
                                             nil, nil, true)
    }

    /// Posted when the scroll reaches the bottom (`XCTDarwinNotificationExpectation`).
    static let doneNotification = "de.lahmann.wingfoil.uitest.hitchMeterDone"

    /// The Sessions list: the tallest scroll view in the key window.
    private static func listScrollView() -> UIScrollView? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var best: UIScrollView?
        func walk(_ view: UIView) {
            if let scroll = view as? UIScrollView, !scroll.isHidden,
               scroll.contentSize.height > (best?.contentSize.height ?? 0) {
                best = scroll
            }
            view.subviews.forEach(walk)
        }
        window.map(walk)
        return best
    }
}

/// The meter's label: its own view, so a new summary redraws one invisible text and not
/// the list.
struct ScrollHitchMeterLabel: View {
    let meter: ScrollHitchMeter

    var body: some View {
        Text(meter.summary)
            .font(.system(size: 2))
            .opacity(0.02)
            .frame(width: 4, height: 4)
            .allowsHitTesting(false)
            .accessibilityIdentifier("scrollHitchMeter")
            .accessibilityLabel(meter.summary)
    }
}
#endif
