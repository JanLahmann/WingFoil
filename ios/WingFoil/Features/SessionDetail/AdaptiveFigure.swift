import SwiftUI

/// Height for a figure — the inline map, the speed chart, the turns map — that has to work
/// in both orientations.
///
/// The app declares landscape (`Info.plist`, `UISupportedInterfaceOrientations`) because a
/// track and a speed chart are both wider than they are tall and a phone turned sideways is
/// the better screen for them. But a phone in landscape is about 390 pt tall *including*
/// the nav bar, and the figures were sized for a 850 pt portrait page: a 260 pt map plus a
/// 190 pt chart is more than the whole screen, so the "one instrument" the map/chart tab is
/// built around could never be seen at once — which is the one thing landscape was supposed
/// to fix.
///
/// `verticalSizeClass == .compact` is exactly "a phone in landscape" (an iPad stays
/// `.regular` in both orientations, and it has the room), so the figures shrink there and
/// nowhere else. Deliberately two constants rather than a fraction of the screen: a figure
/// whose height chased the container would resize as the page scrolls under a keyboard or
/// a callout appears.
private struct AdaptiveFigureHeight: ViewModifier {
    let regular: CGFloat
    let compact: CGFloat

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    func body(content: Content) -> some View {
        content.frame(height: verticalSizeClass == .compact ? compact : regular)
    }
}

extension View {

    /// `regular` on a portrait phone and on any iPad, `compact` on a phone in landscape.
    func figureHeight(regular: CGFloat, compact: CGFloat) -> some View {
        modifier(AdaptiveFigureHeight(regular: regular, compact: compact))
    }
}
