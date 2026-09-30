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
/// 2. **A drag that starts on a figure never turns the page.** The map pans, the chart and
///    the turn strips scrub, the replay slider slides; each marks itself
///    `.pagerExclusionZone()`, and the pager ignores any drag whose first touch
///    lands inside one. A rule about where the finger *started*, not a guess about what
///    it meant: a flat scrub on the chart is exactly the drag the pager used to steal.
/// 3. **The turn and flight-end sheets page with the session page's pager**
///    (`SessionPager`), not a page-style `TabView`. The `TabView` is a paging scroll view
///    around the page's vertical one, and a scroll view nested in a sideways one lets go of
///    any drag whose first points lean sideways — a thumb's do — so the page would not move
///    (Jan, 28 Sep 2026). The pager is a drag beside the scroll, turns only on a clearly
///    sideways one, and keeps out of the strips by rule 2.
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

    private var zones: [UUID: CGRect] = [:]

    func set(_ id: UUID, _ frame: CGRect?) { zones[id] = frame }

    func contains(_ point: CGPoint) -> Bool {
        zones.values.contains { $0.contains(point) }
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

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(PagerExclusions.space))
            } action: { frame in
                exclusions?.set(id, frame)
            }
            .onDisappear { exclusions?.set(id, nil) }
    }
}

extension View {
    /// A drag that starts here belongs to this view and never turns the session page — see
    /// `ScrubPan`, rule 2. Harmless outside a pager.
    func pagerExclusionZone() -> some View {
        modifier(PagerExclusionZone())
    }
}
