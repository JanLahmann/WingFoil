import SwiftUI

/// How wide a column of the app's own content is allowed to get.
///
/// On a phone this question never comes up: the screen is 390–440 pt across and every card,
/// paragraph and picker is as wide as it gets. An iPad is 1 024–1 366 pt across and the
/// same column stretched over all of it stops being a column — a footnote runs twenty-five
/// words to the line, a four-word segmented control floats in the middle of a metre of bar,
/// and the "Foil" card grid (`GridItem(.adaptive(minimum: 150))`) lays eight tiles across a
/// row that holds four facts.
///
/// So the app is iPhone-shaped *content* in an iPad-shaped *window*: the column keeps a
/// readable measure and is centred, and the things that are pictures rather than prose —
/// the track map, the speed chart, the turn drawing — are allowed the wider one, because a
/// map gets better as it gets bigger and a paragraph does not.
///
/// Deliberately not a `NavigationSplitView` redesign. The tab bar, the library list and the
/// session's four-way switcher are the same app they are on the phone; what changes at
/// regular width is only how much of the glass one column is entitled to.
enum ContentWidth {

    /// Prose, cards, forms, pickers — anything read left to right. About the width of a
    /// long line of body text, the same judgement `WelcomeView` already makes at 560 pt for
    /// a screen that is nothing but a paragraph and two buttons.
    static let column: CGFloat = 740

    /// A figure that is looked at rather than read: the track map, the speed chart, the
    /// turn strip. Wider than the column because the information in them is spatial, and a
    /// 2 km track on a 740 pt map is the same squint it is on a phone.
    static let figure: CGFloat = 1_000
}

/// `frame(maxWidth:)` twice: the inner one caps the content, the outer one takes the whole
/// container back so the capped column sits in the middle of it rather than against the
/// leading edge.
private struct ReadableColumn: ViewModifier {
    let maxWidth: CGFloat

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: SizeClass.isWideScreen(horizontalSizeClass, verticalSizeClass)
                       ? maxWidth : .infinity)
            .frame(maxWidth: .infinity)
    }
}

/// **"Is this an iPad-sized window?"**, asked in one place because three files ask it.
///
/// Not `horizontalSizeClass == .regular` on its own: a Pro Max phone turned sideways is
/// *also* regular horizontally, and it is 956 pt of a 440 pt app, not an iPad. Both axes
/// regular is exactly an iPad (either orientation, full screen or a wide split view) and
/// the Mac running the iPad app — and never a phone, which is vertically compact the moment
/// it is on its side.
enum SizeClass {

    static func isWideScreen(_ horizontal: UserInterfaceSizeClass?,
                             _ vertical: UserInterfaceSizeClass?) -> Bool {
        horizontal == .regular && vertical == .regular
    }
}

extension View {

    /// Caps this content at a readable measure and centres it **on an iPad-sized window
    /// only** (`SizeClass.isWideScreen`) — either orientation, and the Mac running the iPad
    /// app. Every phone, in every orientation, is left exactly as it was.
    func readableColumn(_ maxWidth: CGFloat = ContentWidth.column) -> some View {
        modifier(ReadableColumn(maxWidth: maxWidth))
    }
}
