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

    /// The three layers that are about *effort and water* rather than about an outcome.
    /// They are deliberately outside the green/amber/red ladder: nothing here is a verdict,
    /// so borrowing the verdict palette would make a takeoff look like a good jibe.
    static let pumping = Color.indigo
    static let takeoff = Color.blue
    static let splash = Color.cyan
    /// The one exception, and it earns it: a *failed* attempt is the single event in these
    /// three layers that has an outcome, so it borrows the ladder's red. Shape and fill
    /// carry the distinction on their own (see `takeoffMark`), so nothing here depends on
    /// telling red from blue.
    static let failedTakeoff = Color.red

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

    /// Takeoffs and splashes are glyphs, not dots, so they can never be mistaken for an
    /// outcome at a glance on a busy track. A `free` takeoff — up on wind alone — gets the
    /// hollow arrow: the pumped one is the filled, "this cost something" variant.
    ///
    /// A **failed** attempt turns the arrow around. It is the only mark in this layer that
    /// did not end in a flight, so it must not merely be a differently-tinted up-arrow: the
    /// u-turn glyph says "went at it and came back down" at any zoom, hollow says nothing
    /// came of it, and red says it on a third channel for anyone who cannot use the first
    /// two. The takeoff arrows stay blue and unchanged around it.
    static func takeoffSymbol(_ kind: SessionDetail.TakeoffMark.Kind) -> String {
        switch kind {
        case .pumped: return "arrow.up.circle.fill"
        case .free: return "arrow.up.circle"
        case .failed: return "arrow.uturn.down.circle"
        }
    }

    @ViewBuilder
    static func takeoffMark(_ mark: SessionDetail.TakeoffMark,
                            size: CGFloat = 11) -> some View {
        let hollow = mark.kind != .pumped
        Image(systemName: takeoffSymbol(mark.kind))
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(mark.isFailed ? failedTakeoff : takeoff)
            .background(Circle().fill(.white.opacity(hollow ? 0.85 : 0)).padding(1))
            .shadow(radius: 1)
    }

    @ViewBuilder
    static func splashMark(size: CGFloat = 12) -> some View {
        Image(systemName: "drop.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(splash)
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
