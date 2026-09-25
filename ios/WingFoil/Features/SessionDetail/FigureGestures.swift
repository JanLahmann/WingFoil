import SwiftUI
import UIKit

/// **Which finger belongs to which surface** — the two rules every figure inside a scroll
/// view or a pager keeps (Jan, 25 Sep 2026: "the gestures fight each other").
///
/// 1. **A sideways drag on a chart scrubs it; an up-or-down one scrolls the page.**
///    `ScrubPan` is a UIKit pan that begins only when the finger moved more across than
///    down, and that every other pan on the way up — the page's scroll view, the turn
///    sheet's paging, the sheet's own dismiss — has to wait for. So a vertical finger on a
///    strip fails it at once and the page scrolls, and a sideways one is the scrub's and
///    nobody else's: the turn page no longer swipes to the next turn under a scrub, and
///    the stack of strips on the turn page is no longer a wall the page cannot be scrolled
///    past. It had been SwiftUI `DragGesture`s, and a SwiftUI drag cannot say "fail if
///    vertical" before the scroll view has lost the touch to it.
/// 2. **A drag that starts on a figure never turns the session page.** The map pans, the
///    chart scrubs and zooms, the replay slider slides; each marks itself
///    `.pagerExclusionZone()`, and the session pager ignores any drag whose first touch
///    lands inside one. A rule about where the finger *started*, not a guess about what
///    it meant: a flat scrub on the chart is exactly the drag the pager used to steal.
struct ScrubPan: UIGestureRecognizerRepresentable {
    /// The finger's position in the view's own space, on every move while it is scrubbing.
    var onChange: (CGPoint) -> Void
    var onEnd: () -> Void = {}

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        // One finger: two are the pinch's, and a pinch's centroid would fling the playhead.
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer,
                                         context: Context) {
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
        /// Sideways or not, read off the first few points of travel (and the speed, for a
        /// finger that was already moving when the recogniser asked).
        @objc(gestureRecognizerShouldBegin:)
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let travel = pan.translation(in: pan.view)
            if travel.x != 0 || travel.y != 0 { return abs(travel.x) > abs(travel.y) }
            let speed = pan.velocity(in: pan.view)
            return abs(speed.x) > abs(speed.y)
        }

        /// Every other pan waits for this one to fail: the page's vertical scroll (which it
        /// does at once for a vertical finger), a paging `TabView`, a sheet's dismiss.
        @objc(gestureRecognizer:shouldBeRequiredToFailByGestureRecognizer:)
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer)
            -> Bool {
            otherGestureRecognizer is UIPanGestureRecognizer
        }

        /// The pinch on the session chart runs beside it; the pan's one-finger limit and the
        /// chart's own `pinchBase` guard keep the two apart.
        @objc(gestureRecognizer:shouldRecognizeSimultaneouslyWithGestureRecognizer:)
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer)
            -> Bool {
            otherGestureRecognizer is UIPinchGestureRecognizer
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
