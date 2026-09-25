import Foundation

/// **Turning the page between two sessions** — which way a flick goes, which session is on
/// which side, and how far the page follows the finger while it is on the glass.
///
/// **Time runs left to right** (Jan, 25 Sep 2026): the older afternoon is on the left of the
/// one on screen and the newer one on its right, whatever order the list happens to be
/// grouped in. The finger drags the *content*, the platform's rule, so a drag to the left
/// pulls the page off to the left and brings in the one waiting on its right — the newer one
/// — and a drag to the right walks back in time. The `‹ ›` pair in the header sits on the
/// same sides: ‹ is older, › is newer. The mapping lives here as a value rather than as a
/// ternary inside a gesture closure because a sign is exactly the kind of thing that is read
/// right and written backwards (Jan, Beta 75).
///
/// Nothing here knows what a session is. It takes a translation and answers with a step, and
/// a list of start times and answers with neighbours, so the direction can be pinned by a
/// test instead of by a flick on a phone.
public enum SessionPaging {

    /// Which way the page turns. `stay` is a drag that was not a page turn — a scroll, a map
    /// pan, or a flick too short to mean it.
    public enum Step: String, Sendable, Equatable, CaseIterable {
        /// The session before this one in time, waiting on the **left**. Reached by
        /// dragging **right**, or by ‹.
        case older
        /// The session after this one in time, waiting on the **right**. Reached by
        /// dragging **left**, or by ›.
        case newer
        case stay
    }

    /// How far a drag has to travel sideways before it counts as a page turn.
    public static let commitDx: Double = 100
    /// A flick can be shorter than `commitDx` when it is thrown: iOS reads a fast, short
    /// swipe as a page turn, and a rider who flicks twice as fast covers half the distance.
    public static let flickDx: Double = 180
    /// How far it may wander up or down and still be a page turn.
    public static let maxDy: Double = 48
    /// How much flatter than tall a drag has to be. The page scrolls vertically under the
    /// same finger, so the predicate is strict on purpose: below this the drag belongs to
    /// the scroll. (The map, the speed chart and the scrubber do not need it: a drag that
    /// *starts* on one of them never turns the page at all.)
    public static let flatness: Double = 2.5
    /// How far the page moves at the ends of the list, where there is nothing to turn to:
    /// the same dead end a list bounces against.
    public static let deadEndLimit: Double = 26

    /// Whether a drag is sideways enough to be about the page rather than about the scroll
    /// under it.
    public static func isHorizontal(dx: Double, dy: Double) -> Bool {
        abs(dy) <= maxDy && abs(dx) > abs(dy) * flatness
    }

    /// The step a finished drag asks for.
    ///
    /// - Parameters:
    ///   - dx: how far the finger travelled sideways. Negative is leftwards.
    ///   - dy: and vertically.
    ///   - predictedDx: where the drag would coast to at its release speed. Defaults to
    ///     `dx`, so a caller without a velocity gets the distance rule alone.
    public static func step(dx: Double, dy: Double, predictedDx: Double? = nil) -> Step {
        guard isHorizontal(dx: dx, dy: dy) else { return .stay }
        let thrown = abs(predictedDx ?? dx) >= flickDx && (predictedDx ?? dx) * dx > 0
        guard abs(dx) >= commitDx || thrown else { return .stay }
        // The content follows the finger: dragging left brings in what waits on the right,
        // and the right is where the newer session is.
        return dx < 0 ? .newer : .older
    }

    /// Which side a step's page waits on: −1 left, +1 right, 0 for `stay`. The pager draws
    /// the incoming page at `side × width` and slides it to zero.
    public static func side(of step: Step) -> Double {
        switch step {
        case .older: -1
        case .newer: 1
        case .stay: 0
        }
    }

    /// The step a drag this far is heading for, for choosing which neighbour to draw
    /// under the finger: leftwards shows the newer page, rightwards the older one.
    public static func heading(dx: Double) -> Step {
        dx < 0 ? .newer : dx > 0 ? .older : .stay
    }

    /// How far the page is drawn from its resting place mid-drag.
    ///
    /// **One to one**, with the neighbour drawn beside it, the way a paged scroll view
    /// follows a finger: the page used to be rubber-banded from the first point, so it lagged
    /// the finger by half a page and then sprang, which is what read as "hakelig" (Jan,
    /// 25 Sep 2026). Only with nothing to turn to does it resist, and then hard.
    public static func follow(dx: Double, hasTarget: Bool) -> Double {
        guard hasTarget else { return rubberBand(dx, limit: deadEndLimit) }
        return dx
    }

    /// `dx` bent towards `limit`: linear near zero, asymptotic past it.
    static func rubberBand(_ dx: Double, limit: Double) -> Double {
        guard limit > 0 else { return 0 }
        let sign: Double = dx < 0 ? -1 : 1
        let x = abs(dx)
        return sign * limit * (x / (x + limit))
    }

    // MARK: - Neighbours

    /// The ids in time order, oldest first — the order the pages lie in from left to right.
    /// Ties keep the order they came in, so two sessions with one start time do not swap
    /// places between two reads.
    public static func timeline<ID>(_ items: [(id: ID, start: Date)]) -> [ID] {
        items.enumerated()
            .sorted { lhs, rhs in
                lhs.element.start == rhs.element.start ? lhs.offset < rhs.offset
                                                       : lhs.element.start < rhs.element.start
            }
            .map(\.element.id)
    }

    /// The session on either side of `id` in a timeline (oldest first). Nil at the ends,
    /// and both nil for an id the timeline does not hold.
    public static func neighbours<ID: Equatable>(of id: ID, in timeline: [ID])
        -> (older: ID?, newer: ID?) {
        guard let at = timeline.firstIndex(of: id) else { return (nil, nil) }
        return (at > 0 ? timeline[at - 1] : nil,
                at + 1 < timeline.count ? timeline[at + 1] : nil)
    }
}
