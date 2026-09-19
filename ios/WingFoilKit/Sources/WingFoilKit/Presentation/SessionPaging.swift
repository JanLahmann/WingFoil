import Foundation

/// **Turning the page between two sessions** — which way a flick goes, and how far the page
/// follows the finger while it is on the glass.
///
/// The rule is the platform's, not ours: the finger drags the *content*. A drag to the left
/// pulls the current page off to the left and brings in the one after it in the list; a drag
/// to the right walks back to the one before it. The same mapping a paged scroll view, a
/// photo library and a tab strip all have, and the reason it lives here as a value rather
/// than as a ternary inside a gesture closure is that a sign is exactly the kind of thing
/// that is read right and written backwards (Jan, Beta 75).
///
/// Nothing here knows what a session is. It takes a translation and answers with a step, so
/// the direction can be pinned by a test instead of by a flick on a phone.
public enum SessionPaging {

    /// Which way the page turns. `stay` is a drag that was not a page turn — a scroll, a map
    /// pan, or a flick too short to mean it.
    public enum Step: String, Sendable, Equatable, CaseIterable {
        /// The item before this one in the list's order. Reached by dragging **right**.
        case previous
        /// The item after this one in the list's order. Reached by dragging **left**.
        case next
        case stay
    }

    /// How far a drag has to travel sideways before it counts as a page turn.
    public static let commitDx: Double = 100
    /// A flick can be shorter than `commitDx` when it is thrown: iOS reads a fast, short
    /// swipe as a page turn, and a rider who flicks twice as fast covers half the distance.
    public static let flickDx: Double = 180
    /// How far it may wander up or down and still be a page turn.
    public static let maxDy: Double = 48
    /// How much flatter than tall a drag has to be. The inline map pans horizontally too,
    /// so the predicate is strict on purpose: below this the drag belongs to the map.
    public static let flatness: Double = 2.5
    /// How far the page follows the finger before it stops following it.
    public static let followLimit: Double = 130

    /// Whether a drag is sideways enough to be about the page rather than about the map or
    /// the scroll under it.
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
        // The content follows the finger: dragging left brings in what comes next.
        return dx < 0 ? .next : .previous
    }

    /// How far the page is drawn from its resting place mid-drag.
    ///
    /// It follows the finger one to one until `followLimit`, then gives less and less, so a
    /// long drag still shows the page moving without walking it off the screen. With nothing
    /// to turn to it barely moves at all — the same dead end a list bounces against.
    public static func follow(dx: Double, hasTarget: Bool) -> Double {
        guard hasTarget else { return rubberBand(dx, limit: followLimit / 5) }
        return rubberBand(dx, limit: followLimit)
    }

    /// `dx` bent towards `limit`: linear near zero, asymptotic past it.
    static func rubberBand(_ dx: Double, limit: Double) -> Double {
        guard limit > 0 else { return 0 }
        let sign: Double = dx < 0 ? -1 : 1
        let x = abs(dx)
        return sign * limit * (x / (x + limit))
    }
}
