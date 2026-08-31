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
/// are *counts*, not verdicts, so they get the plain foreground; the four lines that really
/// are the thing a token names (a takeoff, a swim, the record window, a flight) use it.
struct ReplayCommentaryBubble: View {
    let milestone: ReplayMilestone

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(ink)
                .symbolRenderingMode(.hierarchical)
            Text(milestone.text)
                .font(.footnote.weight(.medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 10))
        // A hairline in the milestone's own ink, so the kind reads before the words do
        // without tinting a whole card in a hue that would compete with the track.
        .overlay(alignment: .leading) {
            Capsule().fill(ink).frame(width: 3).padding(.vertical, 6).padding(.leading, 2)
        }
        .accessibilityElement()
        .accessibilityLabel(milestone.text)
    }

    /// Shape first: a symbol is a channel of its own, so the line still reads a kind in
    /// greyscale and to a colour-blind rider.
    private var symbol: String {
        switch milestone.kind {
        case .sessionStart: "flag"
        case .sessionEnd: "flag.checkered"
        case .firstTakeoff: DesignTokens.Glyph.takeoffPumped
        case .jibe: "arrow.triangle.turn.up.right.circle"
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
        case .jibe, .streak: .primary
        }
    }
}
