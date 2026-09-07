import Charts
import SwiftUI
import WingFoilKit

/// **The furniture every strip on a maneuver page shares.**
///
/// There are four of them now — speed, heading, barometer, and the same speed strip again on
/// the flight-end page — and they are only useful *because* they are the same picture: one
/// clock across all of them, one scrub that moves all of them, the same small words under the
/// same bands, the same dashed playhead. That is a contract between views, and a contract
/// four views each implement privately is a contract that lasts until the next edit.
///
/// So the bands, the rules, the captions and the scrub surface live here once. What stays
/// with each strip is the only thing that differs: what it plots and what its axes mean.
/// `@MainActor` because the pieces are views and gestures: they were instance members of a
/// `View` before they moved here, which made them main-actor by inheritance, and a free
/// function returning a `DragGesture` closure is not `Sendable`.
@MainActor
enum StripChrome {

    /// Closer than this on the x axis, two captions on the same edge overprint into
    /// "bout 9.0". Every strip's collision rules are expressed against this one number, so
    /// they cannot disagree about what "close" means.
    static let captionGapS = 1.5

    /// The small word under a window band, or beside a rule.
    static func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(.tertiary)
    }

    /// A caption in the speed strip's own voice — bigger than a band's word, because it names
    /// a *number* rather than a window.
    static func caption(_ text: String, tint: Color = .secondary) -> some View {
        Text(text)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(tint)
    }

    /// One of the engine's windows, shaded, with its name under it.
    ///
    /// The word goes on the **bottom** edge, always: that is where window names live on every
    /// strip, which is what lets the top edge belong entirely to the numbers. A band with no
    /// caption is one drawn inside another (the recovery inside the outcome window), where a
    /// second word would claim a second window.
    @ChartContentBuilder
    static func band(from: Double, to: Double, tint: Color, caption: String?) -> some ChartContent {
        RectangleMark(xStart: .value("From", from), xEnd: .value("To", to))
            .foregroundStyle(tint)
            .annotation(position: .bottom, alignment: .center, spacing: 2) {
                if let caption { label(caption) }
            }
    }

    /// A dashed vertical rule marking an instant — a window boundary, a threshold crossing,
    /// the axis. Never a `PointMark`: an instant has no value on the y axis, and a dot on the
    /// trace would claim it was a reading.
    @ChartContentBuilder
    static func rule(at rt: Double, dash: [CGFloat], tint: Color, width: CGFloat = 1,
                     caption: String?, onTop: Bool = false,
                     spacing: CGFloat = 2) -> some ChartContent {
        RuleMark(x: .value("Seconds", rt))
            .lineStyle(StrokeStyle(lineWidth: width, dash: dash))
            .foregroundStyle(tint)
            .annotation(position: onTop ? .top : .bottom, alignment: .center,
                        spacing: spacing) {
                if let caption { label(caption) }
            }
    }

    /// **The one playhead**, on every strip at once — the same rule the map and the session
    /// chart follow (docs/presentation.md, "Scrub and zoom"). Drawn last, above everything,
    /// because it is the only mark that answers to the reader's finger rather than to the data.
    @ChartContentBuilder
    static func playhead(_ rt: Double?) -> some ChartContent {
        if let rt {
            RuleMark(x: .value("Playhead", rt))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                .foregroundStyle(Color(.label))
                .zIndex(10)
        }
    }

    /// One finger, anywhere on the plot, moves the playhead on every other strip and the dot
    /// on the drawing. `minimumDistance: 0` so a tap works as well as a drag — the common
    /// gesture is "what was I doing *there*".
    ///
    /// Released, not cleared: the rider let go looking at a moment, and snatching the mark
    /// back would undo the one thing the gesture is for.
    static func scrubSurface(_ proxy: ChartProxy, domain: ClosedRange<Double>,
                             playheadRt: Binding<Double?>) -> some View {
        GeometryReader { geometry in
            if let plotFrame = proxy.plotFrame {
                let frame = geometry[plotFrame]
                Rectangle()
                    .fill(.clear)
                    .contentShape(.rect)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let rt: Double =
                                        proxy.value(atX: value.location.x - frame.origin.x)
                                else { return }
                                playheadRt.wrappedValue =
                                    min(max(rt, domain.lowerBound), domain.upperBound)
                            }
                            .onEnded { _ in })
            }
        }
    }

    /// The turn strip's ink for a window band, so the three strips shade the *same* window in
    /// the same colour and a reader can follow it down the page.
    enum Band {
        static let entry = Color.secondary.opacity(0.10)
        static let sweep = DesignTokens.Phase.flying.opacity(0.14)
        static let outcome = DesignTokens.Outcome.touchdown.opacity(0.05)
        static let recovery = DesignTokens.Phase.flying.opacity(0.08)
    }
}
