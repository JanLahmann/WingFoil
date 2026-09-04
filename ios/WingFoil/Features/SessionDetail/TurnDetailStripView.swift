import Charts
import SwiftUI
import WingFoilKit

/// The turn's speed, on the turn's own clock: seconds from the moment the sweep began, with
/// the sweep itself shaded and the three speeds that decide the score labelled on it.
///
/// The session's speed chart cannot answer this. It is bucketed by max over the whole
/// afternoon, so a six-second jibe is one or two points of it — the dip that *is* the turn is
/// exactly what the thinning removes. This draws the recorded samples of one window, at the
/// rate they were recorded.
///
/// It is also the sheet's scrub handle: a finger on the strip drives the dot on the drawing
/// above it, which is the same one-playhead rule the map and the chart follow on the session
/// page (docs/presentation.md, "Scrub and zoom").
struct TurnDetailStripView: View {
    let slice: TurnSlice
    let ghost: TurnSlice?
    /// Seconds from the turn's start; nil when nothing is being scrubbed.
    @Binding var playheadRt: Double?

    private var domain: ClosedRange<Double> { slice.timeDomain }

    private var ceilingKn: Double {
        let highest = slice.points.map(\.kn).max() ?? slice.speed.entryKn
        return max(highest * 1.15, 5)
    }

    var body: some View {
        Chart {
            // The sweep, shaded — everything outside it is approach and run-out.
            RectangleMark(xStart: .value("Turn start", 0),
                          xEnd: .value("Turn end", slice.speed.exitRt))
                .foregroundStyle(DesignTokens.Phase.flying.opacity(0.14))

            if let ghost, ghost.hasGeometry {
                ForEach(Array(ghost.points.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Seconds", point.rt),
                             y: .value("Speed", point.kn),
                             series: .value("Turn", "ghost"))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                        .foregroundStyle(DesignTokens.Clean.jibe.opacity(0.7))
                }
            }
            ForEach(Array(slice.points.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Seconds", point.rt),
                         y: .value("Speed", point.kn),
                         series: .value("Turn", "this"))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.8))
                    .foregroundStyle(Color.accentColor)
            }

            // The three numbers the score is made of, on the trace they were read from.
            mark(at: 0, kn: slice.speed.entryKn, label: "in")
            mark(at: slice.speed.minRt, kn: slice.speed.minKn, label: "low")
            mark(at: slice.speed.exitRt, kn: slice.speed.exitKn, label: "out")

            if let playheadRt {
                RuleMark(x: .value("Playhead", playheadRt))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    .foregroundStyle(Color(.label))
                    .zIndex(10)
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...ceilingKn)
        .chartXAxisLabel("s from the turn")
        .chartYAxisLabel("kn")
        .chartOverlay { proxy in scrubSurface(proxy) }
        .figureHeight(regular: 170, compact: 130)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    /// A rule and its caption. The caption sits at the top of the plot rather than beside the
    /// point, because three labels chasing three points on a six-second window overlap on
    /// every turn that mattered.
    @ChartContentBuilder
    private func mark(at rt: Double, kn: Double, label: String) -> some ChartContent {
        RuleMark(x: .value("Seconds", rt))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            .foregroundStyle(Color.secondary.opacity(0.5))
            .annotation(position: .top, alignment: .center, spacing: 1) {
                Text("\(label) \(String(format: "%.1f", kn))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        PointMark(x: .value("Seconds", rt), y: .value("Speed", kn))
            .symbolSize(28)
            .foregroundStyle(Color.accentColor)
    }

    /// One finger, anywhere on the plot, moves the dot on the drawing. `minimumDistance: 0`
    /// so a tap works as well as a drag — the common gesture is "what was I doing *there*".
    private func scrubSurface(_ proxy: ChartProxy) -> some View {
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
                                playheadRt = min(max(rt, domain.lowerBound),
                                                 domain.upperBound)
                            }
                            // Released, not cleared: the rider let go looking at a moment,
                            // and snatching the dot back off the drawing would undo the one
                            // thing the gesture is for.
                            .onEnded { _ in })
            }
        }
    }

    private var accessibilityText: String {
        var text = String(format: "Speed through the turn: %.1f knots coming in, "
                          + "down to %.1f after %.0f seconds, %.1f knots at the exit "
                          + "%.0f seconds in.",
                          slice.speed.entryKn, slice.speed.minKn, slice.speed.minRt,
                          slice.speed.exitKn, slice.speed.exitRt)
        if ghost != nil { text += " Your best clean jibe is drawn dashed beside it." }
        return text
    }
}
