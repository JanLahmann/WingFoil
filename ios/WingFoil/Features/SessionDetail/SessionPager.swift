import SwiftUI
import WingFoilKit

/// **The session page's sideways turn** — one afternoon on screen, the older one waiting on
/// its left and the newer one on its right (`SessionPaging`).
///
/// Why it is a view of its own (Jan, 25 Sep 2026: "hakelig"): the drag's offset used to be
/// state on `SessionDetailView`, so every frame of a swipe re-ran that view's whole body —
/// the map, the chart, the tab — to move a picture sideways. Here the offset is this view's
/// state and the page is a value it was handed, so a frame of the drag redraws one offset.
///
/// And why it slides **to** a neighbour rather than swapping under a transition: the page
/// follows the finger one to one with the neighbour drawn beside it, the way a paged scroll
/// view does, and a release finishes the slide from wherever the finger let go at the speed
/// it was going. Only when the incoming page is fully in place is the session on screen
/// changed — the neighbour's stand-in (`preview`) and the real page are drawn at the same
/// place, so the swap is not a movement at all. The neighbour is a stand-in because a real
/// page is an analysis to load; the stand-in is the header the real page starts with.
///
/// Three things never turn the page: a drag that starts on a map, a chart or the replay
/// slider (`pagerExclusionZone`), a drag steeper than `SessionPaging.isHorizontal`, and a
/// drag during a turn already running.
struct SessionPager<Page: View, Preview: View>: View {
    /// The neighbours in time, nil at the ends of the list.
    let older: String?
    let newer: String?
    /// Set by the header's ‹ ›: the pager runs the same slide a flick does and clears it.
    @Binding var request: SessionPaging.Step?
    /// Called once the incoming page is in place, with the session now on screen.
    let onTurn: (String) -> Void
    let page: Page
    let preview: (String) -> Preview

    @State private var offset: CGFloat = 0
    @State private var width: CGFloat = 0
    /// Whether the drag in progress is the pager's. Decided once per drag, at
    /// `decideAfter` points of travel, and kept: a drag that began as a scroll stays one.
    @State private var claimed: Bool?
    /// The drag's translation at the moment it was claimed, so the page starts moving from
    /// where it rests rather than jumping by the decision distance.
    @State private var origin: CGFloat = 0
    @State private var turning = false
    @State private var exclusions = PagerExclusions()

    /// A hairline of background between the two pages while they slide.
    private let gap: CGFloat = 12
    private let decideAfter: CGFloat = 14

    private func target(_ step: SessionPaging.Step) -> String? {
        switch step {
        case .older: older
        case .newer: newer
        case .stay: nil
        }
    }

    var body: some View {
        ZStack {
            page
                .offset(x: offset)
            // The neighbour under the finger: on the left while the page is pulled right,
            // on the right while it is pulled left.
            if offset != 0 {
                let showing: SessionPaging.Step = offset > 0 ? .older : .newer
                if let id = target(showing) {
                    preview(id)
                        .offset(x: offset + CGFloat(SessionPaging.side(of: showing))
                                * (width + gap))
                        .allowsHitTesting(false)
                        .id(id)
                }
            }
        }
        .environment(\.pagerExclusions, exclusions)
        .coordinateSpace(.named(PagerExclusions.space))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // The sliding pages stop at the screen's edges rather than drawing over the bars.
        .clipped()
        // `simultaneousGesture`, so the vertical scroll keeps every touch it had; the claim
        // decides once, early, whether this drag is a page turn at all.
        .simultaneousGesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .named(PagerExclusions.space))
                .onChanged(changed)
                .onEnded(ended))
        .onChange(of: request) {
            guard let step = request else { return }
            request = nil
            slide(step, velocity: 0)
        }
    }

    private func changed(_ value: DragGesture.Value) {
        let dx = value.translation.width
        let dy = value.translation.height
        if claimed == nil {
            if turning || exclusions.contains(value.startLocation) {
                claimed = false
            } else if hypot(dx, dy) >= decideAfter {
                claimed = SessionPaging.isHorizontal(dx: Double(dx), dy: Double(dy))
                origin = dx
            }
        }
        guard claimed == true else { return }
        let travel = Double(dx - origin)
        let heading = SessionPaging.heading(dx: travel)
        offset = CGFloat(SessionPaging.follow(dx: travel, hasTarget: target(heading) != nil))
    }

    private func ended(_ value: DragGesture.Value) {
        defer { claimed = nil }
        guard claimed == true else { return }
        let travel = Double(value.translation.width - origin)
        // The drag was claimed as sideways at its start, so a finger that drifted down on
        // the way is still a page turn: `dy` has already been judged.
        let step = SessionPaging.step(
            dx: travel, dy: 0,
            predictedDx: Double(value.predictedEndTranslation.width - origin))
        slide(step, velocity: value.velocity.width)
    }

    /// Finishes a turn — or springs back, for `stay` and at the ends of the list.
    private func slide(_ step: SessionPaging.Step, velocity: CGFloat) {
        guard let id = target(step), width > 0, !turning else {
            withAnimation(.snappy(duration: 0.25)) { offset = 0 }
            return
        }
        let destination = -CGFloat(SessionPaging.side(of: step)) * (width + gap)
        let remaining = destination - offset
        // The spring starts at the finger's speed, as a fraction of the distance left, so
        // a thrown page keeps going instead of stopping and starting again.
        let initial = remaining == 0 ? 0 : min(max(velocity / remaining, 0), 12)
        turning = true
        withAnimation(.interpolatingSpring(mass: 1, stiffness: 260, damping: 34,
                                           initialVelocity: initial),
                      completionCriteria: .logicallyComplete) {
            offset = destination
        } completion: {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                onTurn(id)
                offset = 0
                turning = false
            }
        }
    }
}
