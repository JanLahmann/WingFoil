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
/// nowhere else. Deliberately constants rather than a fraction of the screen: a figure whose
/// height chased the container would resize as the page scrolls under a keyboard or a
/// callout appears.
private struct AdaptiveFigureHeight: ViewModifier {
    let regular: CGFloat
    let compact: CGFloat
    let wide: CGFloat?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Order matters. A Pro Max phone in landscape is horizontally *regular* and is still a
    /// phone in landscape, so the "no room" case is asked first and answers first.
    private var height: CGFloat {
        if verticalSizeClass == .compact { return compact }
        if SizeClass.isWideScreen(horizontalSizeClass, verticalSizeClass) {
            return wide ?? regular
        }
        return regular
    }

    func body(content: Content) -> some View {
        content.frame(height: height)
    }
}

extension View {

    /// `regular` on a portrait phone, `compact` on a phone in landscape, and `wide` — when a
    /// figure is given one — on an iPad-sized window.
    ///
    /// The third number exists because the iPad fixes the wrong half of the problem by
    /// itself: the column is capped at a readable measure (`ContentWidth`), so a figure that
    /// kept its phone height would sit at a phone's *width* too and gain nothing at all from
    /// 1 000 pt of glass. An iPad has vertical room a phone does not, and a map and a chart
    /// are the two things on the page that can spend it.
    func figureHeight(regular: CGFloat, compact: CGFloat, wide: CGFloat? = nil) -> some View {
        modifier(AdaptiveFigureHeight(regular: regular, compact: compact, wide: wide))
    }
}
