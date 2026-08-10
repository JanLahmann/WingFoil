import SwiftUI

/// One palette for the outcome markers so the map, the chart and the legend can never
/// drift apart. Colour carries the verdict (docs/algorithms.md "Turn outcome" /
/// "Flight-end outcome"), fill carries the *channel*: solid = a maneuver's outcome,
/// hollow = a straight-line flight end that no turn explains.
enum EventMarkerStyle {

    static func color(_ tone: SessionDetail.EventMarker.Tone) -> Color {
        switch tone {
        case .flew: return .green
        case .touchdown: return .orange
        case .fell: return .red
        case .course: return .gray
        }
    }

    /// The dot itself, at a size that stays legible on a zoomed-out track.
    @ViewBuilder
    static func dot(_ marker: SessionDetail.EventMarker, size: CGFloat = 11) -> some View {
        let tint = color(marker.tone)
        Circle()
            .fill(marker.filled ? tint : Color.clear)
            .stroke(marker.filled ? Color.white.opacity(0.9) : tint, lineWidth: 2)
            .frame(width: size, height: size)
            .shadow(radius: 1)
    }

    static func legend() -> some View {
        HStack(spacing: 12) {
            item(.flew, "flew through")
            item(.touchdown, "touchdown")
            item(.fell, "fell in")
            item(.course, "course change")
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private static func item(_ tone: SessionDetail.EventMarker.Tone,
                             _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color(tone)).frame(width: 8, height: 8)
            Text(label)
        }
    }
}
