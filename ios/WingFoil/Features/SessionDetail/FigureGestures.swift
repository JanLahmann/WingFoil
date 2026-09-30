import MapKit
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import WingFoilKit

/// **Which finger belongs to which surface** — the three rules every figure inside a scroll
/// view or a pager keeps (Jan, 25 Sep 2026: "the gestures fight each other").
///
/// 1. **A sideways drag on a chart scrubs it; an up-or-down one scrolls the page.**
///    `ScrubPan` is a UIKit recogniser that every other pan on the way up — the page's
///    scroll view, the sheet's own dismiss — has to wait for, and that makes its call once
///    the finger has travelled far enough to show its direction (`DragClaim`, in the kit):
///    clearly flatter than tall is a scrub, the scrub's and nobody else's; anything else
///    fails it and the page scrolls. So the stack of strips on the turn page is no longer a
///    wall the page cannot be scrolled past. It had been SwiftUI `DragGesture`s, and a
///    SwiftUI drag cannot say "fail if vertical" before the scroll view has lost the touch
///    to it. And it had been a plain `UIPanGestureRecognizer` deciding at the platform's ten
///    points with a 45° line (25–28 Sep): a thumb leans sideways in its first few points,
///    so a scroll that began on a strip read as a scrub, the scrub kept the touch, and the
///    page stuck (Jan, 28 Sep 2026, on dev 114/116).
/// 2. **A drag that starts on a figure never turns the page.** The chart and the turn
///    strips scrub, the replay slider slides, a map moves under two fingers (rule 4); each marks itself
///    `.pagerExclusionZone()`, and the pager ignores any drag whose first touch
///    lands inside one. A rule about where the finger *started*, not a guess about what
///    it meant: a flat scrub on the chart is exactly the drag the pager used to steal.
/// 3. **The turn and flight-end sheets page with the session page's pager**
///    (`SessionPager`), not a page-style `TabView`. The `TabView` is a paging scroll view
///    around the page's vertical one, and a scroll view nested in a sideways one lets go of
///    any drag whose first points lean sideways — a thumb's do — so the page would not move
///    (Jan, 28 Sep 2026). The pager is a drag beside the scroll, turns only on a clearly
///    sideways one, and keeps out of the strips by rule 2.
/// 4. **On an inline map one finger is the page's, two are the map's** (Jan, 30 Sep 2026:
///    "scroll up still struggles"). The Ride, Turns and Flights maps fill a third of the
///    screen, and while the map owned every one-finger pan a scroll that started on it moved
///    the map instead. `PageMapFingers` raises the map's own pan to two fingers, so one finger
///    scrolls the page — or, flat enough, turns it — and two move and pinch the map; taps on
///    it and on its marks are untouched. The full-screen maps keep one-finger panning.
struct ScrubPan: UIGestureRecognizerRepresentable {
    /// The finger's position in the view's own space, on every move while it is scrubbing.
    var onChange: (CGPoint) -> Void
    var onEnd: () -> Void = {}

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> ScrubRecognizer {
        let recognizer = ScrubRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: ScrubRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChange(context.converter.location(in: .local))
        case .ended, .cancelled, .failed:
            onEnd()
        default:
            break
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Every other pan waits for this one to fail: the page's vertical scroll (which it
        /// does as soon as the finger shows it is going up or down) and a sheet's dismiss.
        @objc(gestureRecognizer:shouldBeRequiredToFailByGestureRecognizer:)
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer)
            -> Bool {
            otherGestureRecognizer is UIPanGestureRecognizer
        }

        /// The pinch on the session chart runs beside it; the one-finger rule and the
        /// chart's own `pinchBase` guard keep the two apart.
        @objc(gestureRecognizer:shouldRecognizeSimultaneouslyWithGestureRecognizer:)
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer)
            -> Bool {
            otherGestureRecognizer is UIPinchGestureRecognizer
        }
    }
}

/// One finger, held undecided until `DragClaim` makes the call on its travel since it
/// landed. Not a `UIPanGestureRecognizer`: a pan begins at its own ten points and asks its
/// delegate only once, yes or no — there is no "not yet" to say to it.
final class ScrubRecognizer: UIGestureRecognizer {
    private var finger: UITouch?
    private var landed: CGPoint = .zero

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if finger == nil, touches.count == 1, let touch = touches.first {
            finger = touch
            landed = touch.location(in: nil)
            return
        }
        // A second finger is a pinch's: before the call it is not a scrub at all, and
        // during one the scrub keeps following the first finger.
        if state == .possible {
            state = .failed
        } else {
            touches.forEach { ignore($0, for: event) }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let finger, touches.contains(finger) else { return }
        switch state {
        case .possible:
            let at = finger.location(in: nil)
            switch DragClaim.decide(dx: Double(at.x - landed.x), dy: Double(at.y - landed.y)) {
            case .undecided: break
            case .upDown: state = .failed
            case .sideways: state = .began
            }
        case .began, .changed:
            state = .changed
        default:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let finger, touches.contains(finger) else { return }
        state = scrubbing ? .ended : .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let finger, touches.contains(finger) else { return }
        state = scrubbing ? .cancelled : .failed
    }

    override func reset() {
        super.reset()
        finger = nil
    }

    private var scrubbing: Bool { state == .began || state == .changed }
}

// MARK: - Maps inside a scrolling page

/// How many fingers are on one inline map right now — what the pager asks before it keeps
/// its hands off it (rule 4: only a two-finger drag on the map is the map's).
/// Main-thread only, like `PagerExclusions`.
final class MapFingers: @unchecked Sendable {
    fileprivate(set) var down = 0
    var areTheMaps: Bool { down >= 2 }
    /// Called once per touch when one finger that landed on the map has gone up or down far
    /// enough for the page to scroll with it (`DragClaim.upDown`) — the drag a rider who
    /// meant to move the map just lost to the page. `MapFingerHint` listens.
    var onPageScroll: (@MainActor () -> Void)?
    /// Called once the touch is over (the recogniser resets), so the hint's clock starts when
    /// the rider can read it rather than while his thumb is still on it.
    var onLift: (@MainActor () -> Void)?
}

/// Rule 4 in `ScrubPan`: the map under this view pans with two fingers, so one finger goes to
/// the page's scroll view (and, flat enough, to the pager).
///
/// No private API and no guess about how SwiftUI's `Map` is built: on the first touch the
/// recogniser walks up from the view the finger landed on to the `MKMapView` that holds it,
/// and sets every enabled one-finger pan the map itself carries (not its marks') to need two.
/// Pinch, double-tap zoom and every tap are other recognisers and keep working. It never
/// recognises anything itself — it counts the fingers for the pager and fails when the last
/// one lifts.
struct PageMapFingers: UIGestureRecognizerRepresentable {
    let fingers: MapFingers

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> MapFingerRecognizer {
        let recognizer = MapFingerRecognizer(fingers: fingers)
        recognizer.delegate = context.coordinator
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        return recognizer
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Beside everything: it only watches.
        @objc(gestureRecognizer:shouldRecognizeSimultaneouslyWithGestureRecognizer:)
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer)
            -> Bool {
            true
        }
    }
}

final class MapFingerRecognizer: UIGestureRecognizer {
    private let fingers: MapFingers
    /// The map already set to two fingers, so a touch does not walk its subviews again.
    private weak var adopted: MKMapView?
    /// Where a lone finger landed, in the window — nil once a second one joins it, or once
    /// the scroll it started has been reported.
    private var landed: CGPoint?

    init(fingers: MapFingers) {
        self.fingers = fingers
        super.init(target: nil, action: nil)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        landed = fingers.down == 0 && touches.count == 1
            ? touches.first?.location(in: nil) : nil
        fingers.down += touches.count
        if let view = touches.first?.view, let map = Self.map(holding: view), map !== adopted {
            Self.twoFingerPan(on: map)
            adopted = map
        }
    }

    /// One finger, gone up or down the way the page scrolls: the page took this drag.
    /// A flat one turns the page instead, and a tap never travels far enough.
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard fingers.down == 1, let landed, let at = touches.first?.location(in: nil) else {
            return
        }
        guard DragClaim.decide(dx: Double(at.x - landed.x), dy: Double(at.y - landed.y))
                == .upDown else { return }
        self.landed = nil
        fingers.onPageScroll?()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        lift(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        lift(touches)
    }

    override func reset() {
        super.reset()
        fingers.down = 0
        landed = nil
        // However the touch ended, the hint's clock starts: it never stays up for good.
        fingers.onLift?()
    }

    private func lift(_ touches: Set<UITouch>) {
        fingers.down = max(0, fingers.down - touches.count)
        if fingers.down == 0 { state = .failed }
    }

    private static func map(holding view: UIView) -> MKMapView? {
        var at: UIView? = view
        while let candidate = at {
            if let map = candidate as? MKMapView { return map }
            at = candidate.superview
        }
        return nil
    }

    /// The map's own pans — on the map view and its drawing, never inside a mark's view.
    static func twoFingerPan(on map: MKMapView) {
        var stack: [UIView] = [map]
        while let view = stack.popLast() {
            for case let pan as UIPanGestureRecognizer in view.gestureRecognizers ?? []
            where pan.isEnabled && pan.minimumNumberOfTouches < 2 {
                pan.minimumNumberOfTouches = 2
            }
            stack += view.subviews.filter { !($0 is MKAnnotationView) }
        }
    }
}

extension View {
    /// Rule 4 in `ScrubPan`, for an inline map: one finger scrolls or turns the page, two
    /// move the map — and a drag with two on it never turns the page.
    func pageMap(_ fingers: MapFingers) -> some View {
        gesture(PageMapFingers(fingers: fingers))
            .overlay(alignment: .bottom) { MapFingerHint(fingers: fingers) }
            .pagerExclusionZone(while: { fingers.areTheMaps })
    }
}

/// **The map moves with two fingers — said on the map, the first few times it matters**
/// (Jan, 30 Sep 2026: "We need to inform the user that the map needs two fingers to
/// operate"). When one finger that started on an inline map scrolls the page, a capsule says
/// so until `holdSeconds` after the finger lifts. At most `limit` times per install, counted in
/// `AppStorage`; after that the help topic "Reading the map" is its home. Never under
/// VoiceOver, whose own gestures are not these. It takes no touches.
private struct MapFingerHint: View {
    let fingers: MapFingers

    static let limit = 3
    static let holdSeconds = 1.5

    @AppStorage("mapFingerHint.shown.v1") private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var visible = false
    @State private var hiding: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottom) {
            if visible {
                Text(Copy.twoFingerMap)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    // Above the Maps logo and its "Legal" link, which have to stay readable.
                    .padding(.horizontal, 12)
                    .padding(.bottom, 36)
                    .transition(.opacity)
                    .accessibilityIdentifier("mapFingerHint")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .onAppear {
            fingers.onPageScroll = { show() }
            fingers.onLift = { hideLater() }
        }
        .onDisappear {
            fingers.onPageScroll = nil
            fingers.onLift = nil
            hiding?.cancel()
            visible = false
        }
    }

    private func show() {
        guard !visible, !voiceOver, shown < Self.limit else { return }
        shown += 1
        hiding?.cancel()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { visible = true }
    }

    /// `holdSeconds` after the finger lifts, not after the hint came up: the drag that
    /// raised it may still be going on.
    private func hideLater() {
        guard visible else { return }
        hiding?.cancel()
        hiding = Task {
            try? await Task.sleep(for: .seconds(Self.holdSeconds))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.3)) { visible = false }
        }
    }
}

// MARK: - Where the session pager keeps its hands off

/// The rectangles, in the pager's coordinate space, that a page turn may not start in.
///
/// A plain reference, not observed: the figures write their frames here as the page scrolls
/// and nothing has to be redrawn for it — the pager only reads it when a drag begins.
/// Main-thread only, which is where SwiftUI calls both ends.
final class PagerExclusions: @unchecked Sendable {
    /// The pager's coordinate space, named so a figure deep inside the scroll view can
    /// report its frame in the same space the pager's drag reports its start in.
    static let space = "sessionPager"

    private var zones: [UUID: (frame: CGRect, active: () -> Bool)] = [:]

    func set(_ id: UUID, _ frame: CGRect?, while active: @escaping () -> Bool = { true }) {
        zones[id] = frame.map { ($0, active) }
    }

    func contains(_ point: CGPoint) -> Bool {
        zones.values.contains { $0.frame.contains(point) && $0.active() }
    }
}

extension EnvironmentValues {
    /// The pager this view is inside, if any. Nil everywhere else — a figure on a sheet or on
    /// the full-screen map has no pager to keep out of.
    @Entry var pagerExclusions: PagerExclusions?
}

private struct PagerExclusionZone: ViewModifier {
    @Environment(\.pagerExclusions) private var exclusions
    @State private var id = UUID()
    /// Asked when a drag starts inside the zone; the zone holds only while it says yes.
    let active: () -> Bool

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(PagerExclusions.space))
            } action: { frame in
                exclusions?.set(id, frame, while: active)
            }
            .onDisappear { exclusions?.set(id, nil) }
    }
}

extension View {
    /// A drag that starts here belongs to this view and never turns the session page — see
    /// `ScrubPan`, rule 2. Harmless outside a pager.
    func pagerExclusionZone() -> some View {
        modifier(PagerExclusionZone(active: { true }))
    }

    /// The same, but only for a drag that starts while `active` says yes — an inline map's,
    /// which is the map's only with two fingers on it (rule 4).
    func pagerExclusionZone(while active: @escaping () -> Bool) -> some View {
        modifier(PagerExclusionZone(active: active))
    }
}
