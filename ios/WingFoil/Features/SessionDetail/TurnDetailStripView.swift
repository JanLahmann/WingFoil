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
    /// The windows this analysis was measured with — the bands are drawn to them.
    var windows = Windows()
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
            // Every window the engine reads, drawn and named (Jan, 7 Sep 2026: "it's not
            // clear when the jibe starts and ends, and what extended windows we look at").
            // Entry: the seconds before the sweep the entry speed is the maximum of.
            RectangleMark(xStart: .value("Entry window", -windows.entryS),
                          xEnd: .value("Turn start", 0))
                .foregroundStyle(Color.secondary.opacity(0.10))
                .annotation(position: .bottom, alignment: .center, spacing: 2) {
                    windowLabel("entry")
                }
            // Sweep: where the heading turned. "low" is searched to `minSpeedLagS` past it.
            RectangleMark(xStart: .value("Turn start", 0),
                          xEnd: .value("Turn end", slice.speed.exitRt))
                .foregroundStyle(DesignTokens.Phase.flying.opacity(0.14))
                .annotation(position: .bottom, alignment: .center, spacing: 2) {
                    windowLabel("sweep")
                }
            // Outcome: the lookahead the verdict is read from; the lighter band inside it
            // ends where the speed was back at the recovery threshold — flying again.
            RectangleMark(xStart: .value("Turn end", slice.speed.exitRt),
                          xEnd: .value("Outcome window",
                                       slice.speed.exitRt + windows.outcomeS))
                .foregroundStyle(TurnOutcomeStyle.color(.touchdown).opacity(0.05))
                .annotation(position: .bottom, alignment: .center, spacing: 2) {
                    windowLabel("outcome")
                }
            if let recoverRt = slice.speed.recoverRt, recoverRt > slice.speed.exitRt {
                RectangleMark(xStart: .value("Turn end", slice.speed.exitRt),
                              xEnd: .value("Flying again", recoverRt))
                    .foregroundStyle(DesignTokens.Phase.flying.opacity(0.08))
            }

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
            // "low" and "out" fall within a second of each other on every jibe whose speed
            // bottomed out at the exit — the fallen ones — and two captions on one x
            // overprint into "bout 9.0". When they are that close, "out" takes the bottom
            // edge; when the minimum is at the entry it is "low" that steps down instead.
            let lowNearIn = abs(slice.speed.minRt) < Self.captionGapS
            let outNearLow = abs(slice.speed.exitRt - slice.speed.minRt) < Self.captionGapS
            mark(at: slice.speed.entryRt, kn: slice.speed.entryKn, label: "in", below: false)
            mark(at: slice.speed.minRt, kn: slice.speed.minKn, label: "low", below: lowNearIn)
            mark(at: slice.speed.exitRt, kn: slice.speed.exitKn, label: "out",
                 below: outNearLow && !lowNearIn)

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
    /// Closer than this, two captions on the top edge overprint. ("in" now sits at the
    /// engine's entry-window maximum, up to `entrySpeedWindowS` before 0; it never collides
    /// with "low", which is inside the sweep.)
    private static let captionGapS = 1.5

    /// The engine's windows, read off the analysis' own config echo so the strip is drawn
    /// to the numbers in force — on a tuned dev build those are not `TurnConfig()`'s.
    struct Windows {
        var entryS: Double = TurnConfig().entrySpeedWindowS
        var minLagS: Double = TurnConfig().minSpeedLagS
        var outcomeS: Double = TurnConfig().outcomeLookaheadS

        init() {}

        init(config: AnalysisConfig) {
            entryS = config.entrySpeedWindow ?? entryS
            minLagS = config.minSpeedLag ?? minLagS
            outcomeS = config.turnOutcomeLookahead
        }
    }

    /// The small word under a window band.
    private func windowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(.tertiary)
    }

    @ChartContentBuilder
    private func mark(at rt: Double, kn: Double, label: String, below: Bool) -> some ChartContent {
        RuleMark(x: .value("Seconds", rt))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            .foregroundStyle(Color.secondary.opacity(0.5))
            .annotation(position: below ? .bottom : .top, alignment: .center, spacing: 1) {
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
