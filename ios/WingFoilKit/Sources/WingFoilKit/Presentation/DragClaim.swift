import Foundation

/// **Which way a finger on a strip is going** — sideways (a scrub) or up and down (the
/// page's scroll).
///
/// A thumb that scrolls a page does not start straight: its first few points often lean
/// sideways before it settles into the up-or-down it meant (Jan, 28 Sep 2026: "scrolling
/// gets stuck when going to detailed turn analysis and then trying to scroll up again").
/// The strips' scrub decided at the platform's ten points of travel on a 45° line, so such
/// a thumb was taken for a scrub, which kept the whole touch, and the page did not move at
/// all. (The other half of that report was the sheets' paging `TabView`, which is now the
/// session page's pager and decides by `SessionPaging.isHorizontal`.) So the call waits
/// for `decideAfter` points of travel, where a thumb has shown its direction, and sideways
/// has to be clearly flatter than tall (`flatness`). A drag that is neither is the page's:
/// scrolling is what a finger on these pages usually means.
///
/// Nothing here knows about a gesture recogniser; it takes the travel since touch-down and
/// answers, so the rule is pinned by a test rather than by a thumb on a phone.
public enum DragClaim: String, Sendable, Equatable, CaseIterable {
    /// Not far enough yet to tell. Whatever waits on the call keeps waiting.
    case undecided
    /// A scrub along the strip.
    case sideways
    /// The page's scroll.
    case upDown

    /// Points of travel before the call is made.
    public static let decideAfter: Double = 20
    /// How much flatter than tall a drag has to be to go sideways (about 34° from the
    /// horizontal).
    public static let flatness: Double = 1.5

    /// The claim for a finger that has moved `dx` across and `dy` down since it landed.
    public static func decide(dx: Double, dy: Double) -> DragClaim {
        guard hypot(dx, dy) >= decideAfter else { return .undecided }
        return abs(dx) >= abs(dy) * flatness ? .sideways : .upDown
    }
}
