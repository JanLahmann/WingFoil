#if TUNING
import Charts
import SwiftUI
import WingFoilKit

/// **What the barometer saw** — the third strip, and the only place in the app that draws the
/// measurement the "wrist under" chip is made of.
///
/// `submerged` is one line of arithmetic against one threshold: a sample counts as underwater
/// when the pressure altitude reads `turnBaroDrop` metres below the session median. It is the
/// evidence that promotes a touchdown to a fall, so it decides verdicts — and until this
/// strip existed the only thing any screen showed of it was a chip saying yes or no. A dunk
/// that grazed the line and one that went forty metres under looked identical, and the
/// question "is 25 m the right number" had no picture to be answered from.
///
/// **Relative metres, always.** On the water the absolute altitude is meaningless — it is a
/// pressure reading, and the median is whatever the air was doing that afternoon — so
/// everything is drawn against the session reference, which puts the threshold at a fixed
/// −`dropM` and makes two sessions comparable (`SliceBaro`).
///
/// **Dev only**, for the reason the heading strip is: it is a picture of a detector.
struct TurnBaroStripView: View {
    let baro: SliceBaro
    let domain: ClosedRange<Double>
    /// The sweep on a turn, or the outcome window on a flight end — shaded in the same ink as
    /// on the strips above, and named by the caller for the same reason.
    let sweep: ClosedRange<Double>
    var sweepCaption = "sweep"
    @Binding var playheadRt: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Barometer").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            if baro.hasBarometer {
                chart
            } else {
                // One line, and it says which of the two absences this is: nobody was
                // looking. A flat trace at zero would read as "the wrist stayed up".
                Text("No barometer in this recording — nothing here could say whether the "
                     + "wrist went under.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var chart: some View {
        Chart {
            StripChrome.band(from: sweep.lowerBound, to: sweep.upperBound,
                             tint: StripChrome.Band.sweep, caption: sweepCaption)

            // Each submersion episode, shaded in the splash ink. The spans are the engine's
            // own episodes, not a threshold re-applied here, so the shading and the chip
            // above cannot disagree by a sample.
            ForEach(Array(baro.submergedSpans.enumerated()), id: \.offset) { _, span in
                RectangleMark(xStart: .value("From", span.lowerBound),
                              xEnd: .value("To", span.upperBound))
                    .foregroundStyle(DesignTokens.Effort.splash.opacity(0.18))
            }

            // The wrist-under line: `turnBaroDrop` below the session reference, by
            // construction at −dropM whatever the afternoon's pressure was.
            RuleMark(y: .value("Wrist under", baro.thresholdM))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(DesignTokens.Effort.splash.opacity(0.7))
                // Above the rule and hard left, for the reason the heading strip's axis
                // caption is: past the trailing edge is the y axis' own numbers.
                .annotation(position: .top, alignment: .leading, spacing: 0) {
                    StripChrome.label("wrist under")
                }
            // The reference itself, so the trace has a zero to be read against.
            RuleMark(y: .value("Session reference", 0))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [1, 3]))
                .foregroundStyle(Color.secondary.opacity(0.4))

            ForEach(Array(baro.points.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Seconds", point.rt),
                         y: .value("Metres", point.m))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.4))
                    .foregroundStyle(Color.accentColor.opacity(0.85))
            }
            // The submerged samples themselves, marked — the shading says "in an episode",
            // these say "this sample was under", which is the mask's own granularity.
            ForEach(Array(baro.points.filter(\.submerged).enumerated()), id: \.offset) { _, point in
                PointMark(x: .value("Seconds", point.rt), y: .value("Metres", point.m))
                    .symbolSize(16)
                    .foregroundStyle(DesignTokens.Effort.splash)
            }

            StripChrome.playhead(playheadRt)
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: baro.metreDomain)
        .chartXAxis(.hidden)
        .chartYAxisLabel("m vs session")
        .chartOverlay { proxy in
            StripChrome.scrubSurface(proxy, domain: domain, playheadRt: $playheadRt)
        }
        .figureHeight(regular: 120, compact: 95)
        .accessibilityElement()
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        let deepest = baro.points.map(\.m).min() ?? 0
        let episodes = baro.submergedSpans.count
        return String(format: "Barometer through the window: %.0f metres below the session "
                      + "reference at the deepest, threshold %.0f. %d submersion%@.",
                      deepest, baro.thresholdM, episodes, episodes == 1 ? "" : "s")
    }
}
#endif
