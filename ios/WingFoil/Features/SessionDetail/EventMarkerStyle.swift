import SwiftUI
import WingFoilKit

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

}

extension SessionDetail.EventMarker {

    /// The legend chip this marker answers to. Both channels of an outcome share one
    /// chip — the rider hides "touchdowns", not "solid touchdowns" — so the hollow
    /// straight-line variant disappears with its solid maneuver twin.
    var layer: MapLayer {
        switch tone {
        case .flew: return .flewThrough
        case .touchdown: return .touchdown
        case .fell: return .fellIn
        case .course: return .courseChange
        }
    }
}
