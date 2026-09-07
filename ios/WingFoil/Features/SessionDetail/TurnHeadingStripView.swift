#if TUNING
import Charts
import SwiftUI
import WingFoilKit

/// **Where the board was pointing, and how fast that was changing** — the strip that draws
/// the three numbers the turn *detector* actually runs on.
///
/// The speed strip above it says what the turn cost. It cannot say anything at all about why
/// this stretch of track is a turn and the stretch either side of it is not, and that is a
/// heading question from end to end: a sweep is kept when it clears `turnMinAngle` (90°)
/// inside `turnMaxDuration` and contains at least one sample at `turnPeakRate`, and it is
/// trimmed at both ends to where the rate falls below `turnContinueRate`. Three parameters
/// decide where every jibe on the page begins and ends, and before this strip none of them
/// had ever been drawn — they were sliders on the tuning page with numbers beside them and no
/// picture of what moving one would do.
///
/// **Dev only.** It is a picture of the detector, not of the ride: a rider does not ask what
/// his rate of turn was in degrees per second, and a strip that answered a question nobody
/// asked would be the fourth thing on a page that is already dense. The public build gets the
/// speed strip and stops there.
struct TurnHeadingStripView: View {
    let angles: SliceAngles
    /// The window this event is judged over, on its own clock — shaded in the same ink as on
    /// the speed strip, so a reader's eye carries it down the page. On a turn that is the
    /// sweep; on a flight end there is no sweep at all and it is the outcome window, which is
    /// why the caption is a parameter and not the word "sweep" hard-coded here.
    let sweep: ClosedRange<Double>
    var sweepCaption = "sweep"
    let domain: ClosedRange<Double>
    /// The wind-axis crossing, where the engine recorded one: the instant the line above
    /// crosses the dashed axis rule, drawn on both so the two agree by construction.
    var axisRt: Double?
    /// The detector's two rate thresholds, from this analysis' own config echo.
    var peakRateDegS: Double
    var continueRateDegS: Double
    @Binding var playheadRt: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(angles.isTwa ? "Wind angle and rate of turn" : "Heading and rate of turn")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            if angles.isEmpty {
                Text("No usable bearings through this window — the steps were shorter than "
                     + "the receiver's own scatter.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                chart
            }
        }
    }

    /// The rate axis is scaled to the *angle* axis' numbers so both series can share one y
    /// scale — Swift Charts gives a plot one domain, and a second axis is drawn by mapping
    /// the rate onto the angle's range and labelling the right-hand ticks with the inverse.
    /// The alternative is two stacked plots, which would cost the one thing the strip is for:
    /// seeing the rate cross its threshold *at* the moment the line steepens.
    private var rateDomain: ClosedRange<Double> {
        angles.rateDomain(atLeastDegS: max(peakRateDegS, continueRateDegS))
    }

    private var degDomain: ClosedRange<Double> { angles.degDomain }

    /// Rate → angle-axis coordinates.
    private func mapped(_ rateDegS: Double) -> Double {
        let rate = rateDomain
        let deg = degDomain
        let fraction = (rateDegS - rate.lowerBound) / max(rate.upperBound - rate.lowerBound, 0.001)
        return deg.lowerBound + fraction * (deg.upperBound - deg.lowerBound)
    }

    private var chart: some View {
        Chart {
            StripChrome.band(from: sweep.lowerBound, to: sweep.upperBound,
                             tint: StripChrome.Band.sweep, caption: sweepCaption)

            // The two thresholds, on the right axis: thin, unlabelled rules at ±peak and
            // ±continue. Four lines rather than two because the rate is signed — a jibe to
            // port has to clear the same bar as one to starboard, and drawing only the
            // positive half would make half the turns on the page look like they never did.
            ForEach([peakRateDegS, -peakRateDegS], id: \.self) { value in
                threshold(value, dash: [4, 3], opacity: 0.5)
            }
            ForEach([continueRateDegS, -continueRateDegS], id: \.self) { value in
                threshold(value, dash: [1, 3], opacity: 0.35)
            }
            // Zero rate: where the board stopped turning, which is what trims the sweep.
            threshold(0, dash: [2, 4], opacity: 0.25)

            // The rate, secondary — thin, and behind the angle line it explains.
            ForEach(Array(angles.points.enumerated()), id: \.offset) { _, point in
                if let rate = point.rateDegS {
                    LineMark(x: .value("Seconds", point.rt),
                             y: .value("Rate", mapped(rate)),
                             series: .value("Series", "rate"))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(DesignTokens.Outcome.touchdown.opacity(0.55))
                }
            }

            // The axis the maneuver is named by: 0 for a tack's head-to-wind, ±180 for a
            // jibe's dead downwind. Absent on a heading series, which has no axis to cross —
            // a compass 0 is north, and a rule there would invent a fact.
            if let crossing = angles.axisCrossingDeg {
                RuleMark(y: .value("Axis", crossing))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color(.label).opacity(0.35))
                    // Above the rule and hard left, not off its trailing end: the right edge
                    // is the rate axis' own numbers, and a word printed there put
                    // "downwind" straight through "5" and "−5" on Jibe 3.
                    .annotation(position: .top, alignment: .leading, spacing: 0) {
                        StripChrome.label(abs(crossing) < 1 ? "head to wind" : "downwind")
                    }
            }

            ForEach(Array(angles.points.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Seconds", point.rt),
                         y: .value("Angle", point.deg),
                         series: .value("Series", "angle"))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.8))
                    .foregroundStyle(Color.accentColor)
            }

            if let axisRt {
                StripChrome.rule(at: axisRt, dash: [3, 3],
                                 tint: Color(.label).opacity(0.35), caption: "axis")
            }
            StripChrome.playhead(playheadRt)
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: degDomain)
        .chartXAxis(.hidden)
        .chartYAxisLabel(angles.isTwa ? "TWA °" : "heading °")
        // The right axis carries the rate's own numbers, read back through `mapped`, so the
        // secondary line has real units rather than being a shape with no scale.
        .chartYAxis {
            AxisMarks(position: .leading)
            AxisMarks(position: .trailing, values: rateTicks.map(mapped)) { value in
                AxisValueLabel {
                    if let mappedValue = value.as(Double.self),
                       let rate = rateTicks.first(where: { abs(mapped($0) - mappedValue) < 0.01 }) {
                        Text("\(Int(rate))")
                            .foregroundStyle(DesignTokens.Outcome.touchdown.opacity(0.8))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            StripChrome.scrubSurface(proxy, domain: domain, playheadRt: $playheadRt)
        }
        .figureHeight(regular: 140, compact: 110)
        .accessibilityElement()
        .accessibilityLabel(spoken)
    }

    /// Ticks the right axis prints: the two thresholds and zero, which are the only rate
    /// values on this strip that mean anything.
    private var rateTicks: [Double] {
        [0, continueRateDegS, -continueRateDegS, peakRateDegS, -peakRateDegS]
            .filter { rateDomain.contains($0) }
    }

    @ChartContentBuilder
    private func threshold(_ rateDegS: Double, dash: [CGFloat],
                           opacity: Double) -> some ChartContent {
        RuleMark(y: .value("Rate", mapped(rateDegS)))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: dash))
            .foregroundStyle(DesignTokens.Outcome.touchdown.opacity(opacity))
    }

    private var spoken: String {
        let kind = angles.isTwa ? "wind angle" : "heading"
        return String(format: "%@ through the turn, peak rate %.0f degrees a second. "
                      + "Detector thresholds %.0f and %.0f degrees a second.",
                      kind, abs(angles.peakRateDegS), peakRateDegS, continueRateDegS)
    }
}
#endif
