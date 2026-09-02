import SwiftUI
import WingFoilKit

/// One line of replay commentary, under the map, while the playhead is standing on it.
///
/// **Why under the map and not over it.** The same reason `TrackCalloutCard` sits there: the
/// map is what the rider is watching, and a caption laid over the track covers the dot the
/// caption is about. It is also the only placement that survives a phone in landscape, where
/// the map is 190 pt tall (`AdaptiveFigure`) and an overlay would be a third of it.
///
/// **Why the ink is mostly neutral.** `docs/presentation.md` — the outcome ladder is a
/// verdict scale and nothing else may borrow it. "10 jibes" and "New streak — 5 dry jibes"
/// are *counts*, not verdicts, so they get the plain foreground; the lines that really are
/// the thing a token names (a takeoff, a swim, the record window, a flight) use it. The
/// clean-jibe line is the one addition: it is a verdict, and it wears the clean ink the map
/// star wears — never the ladder's green, for the reason spelled out under "Clean jibe".
///
/// **Why there are two sizes.** The inline bubble is read by the rider, on his own phone,
/// six inches away, under a map he is scrubbing — `.footnote` is right and anything larger
/// steals height from the figure it is about. The cinema bubble is read by *somebody else*,
/// off a video, in a chat app, at whatever size that app decided to play it — often a third
/// of a screen. It is the same sentence with the same ink and the same symbol, set in fixed
/// point sizes rather than text styles, because a clip must come out the same on every
/// rider's phone whatever Dynamic Type they run.
struct ReplayCommentaryBubble: View {
    let milestone: ReplayMilestone
    /// Defaults to the inline map's size, so the two existing callers are unchanged.
    var size = Size.inline

    /// The two readings — see the type comment.
    enum Size {
        /// Under the inline map, and in the full-screen map.
        case inline
        /// In a clip somebody else will watch.
        case cinema

        var textFont: Font {
            switch self {
            case .inline: .footnote.weight(.medium)
            case .cinema: .system(size: 20, weight: .semibold)
            }
        }

        var symbolFont: Font {
            switch self {
            case .inline: .footnote
            case .cinema: .system(size: 20)
            }
        }

        var horizontalPadding: CGFloat { self == .inline ? 11 : 16 }
        var verticalPadding: CGFloat { self == .inline ? 7 : 12 }
        var spacing: CGFloat { self == .inline ? 7 : 11 }
        var cornerRadius: CGFloat { self == .inline ? 10 : 15 }
        var rulePoints: CGFloat { self == .inline ? 3 : 4.5 }
    }

    var body: some View {
        HStack(spacing: size.spacing) {
            Image(systemName: Self.symbol(of: milestone.kind))
                .font(size.symbolFont)
                .foregroundStyle(ink)
                .symbolRenderingMode(.hierarchical)
            Text(milestone.text)
                .font(size.textFont)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: size.cornerRadius))
        // A hairline in the milestone's own ink, so the kind reads before the words do
        // without tinting a whole card in a hue that would compete with the track.
        .overlay(alignment: .leading) {
            Capsule().fill(ink).frame(width: size.rulePoints)
                .padding(.vertical, 6).padding(.leading, 2)
        }
        .accessibilityElement()
        .accessibilityLabel(milestone.text)
    }

    /// Shape first: a symbol is a channel of its own, so the line still reads a kind in
    /// greyscale and to a colour-blind rider.
    ///
    /// Static because the clip's closing card draws the same glyph beside the same three
    /// milestones (`ReplayOutroCardView`), and a second switch over the same enum is a second
    /// vocabulary waiting to drift.
    static func symbol(of kind: ReplayMilestone.Kind) -> String {
        switch kind {
        case .sessionStart: "flag"
        case .sessionEnd: "flag.checkered"
        case .firstTakeoff: DesignTokens.Glyph.takeoffPumped
        case .jibe: "arrow.triangle.turn.up.right.circle"
        // The same star the map draws over a clean jibe — one mark, one meaning, wherever
        // the strict verdict appears (docs/presentation.md, "Clean jibe").
        case .cleanJibe: DesignTokens.Glyph.cleanJibe
        case .streak: "flame"
        case .splash: DesignTokens.Glyph.splash
        case .topSpeed: "speedometer"
        case .longestFlight: "wind"
        }
    }

    private var ink: Color {
        switch milestone.kind {
        case .sessionStart, .sessionEnd: .secondary
        case .firstTakeoff: DesignTokens.Effort.takeoff
        // A swim *is* a verdict on a flight end — the ladder's own red, the same one the
        // marker under it is drawn in.
        case .splash: DesignTokens.Outcome.fellIn
        case .topSpeed: DesignTokens.Effort.window
        case .longestFlight: DesignTokens.Phase.flying
        // The clean jibe's own ink, which is the map star's — and, like it, deliberately
        // not the outcome ladder's green.
        case .cleanJibe: DesignTokens.Clean.jibe
        case .jibe, .streak: .primary
        }
    }
}
