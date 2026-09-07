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
    /// **The pump strokes, as ticks along the foot of the trace** (engine 0.3.0).
    ///
    /// The page already says *whether* he pumped out and *how many* strokes it took; what it
    /// could not say is **when** — and on a touchdown that is most of the question, because a
    /// rider who pumps the instant he lands and one who drifts for six seconds first have the
    /// same chip and very different jibes. Empty on a source with no accelerometer, and on a
    /// turn no episode names, which is the same absence the chip already handles.
    var pumps: [PumpTick] = []
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
            StripChrome.band(from: -windows.entryS, to: 0,
                             tint: StripChrome.Band.entry, caption: "entry")
            // Sweep: where the heading turned. "low" is searched to `minSpeedLagS` past it.
            StripChrome.band(from: 0, to: slice.speed.exitRt,
                             tint: StripChrome.Band.sweep, caption: "sweep")
            // Outcome: the lookahead the verdict is read from; the lighter band inside it
            // ends where the speed was back at the recovery threshold — flying again.
            StripChrome.band(from: slice.speed.exitRt,
                             to: slice.speed.exitRt + windows.outcomeS,
                             tint: StripChrome.Band.outcome, caption: "outcome")
            if let recoverRt = slice.speed.recoverRt, recoverRt > slice.speed.exitRt {
                StripChrome.band(from: slice.speed.exitRt, to: recoverRt,
                                 tint: StripChrome.Band.recovery, caption: nil)
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

            // Where the board went through the wind (engine 0.15.0). The crossing sits inside
            // the sweep and so lands near "low" on most jibes — see `axisLifted`.
            if let axisRt = slice.axisRt {
                axisMark(at: axisRt, lifted: axisLifted(axisRt, lowNearIn: lowNearIn,
                                                        outNearLow: outNearLow))
            }

            // Where the quiet tail closes (engine 0.17.0) — the last instant a touchdown or a
            // fall still costs this jibe its star. Drawn only where it *fits*: at the default
            // 10 s it lands past the drawing's own 8 s of run-out, and a rule clipped off the
            // right edge is a mark nobody can read. The footnote says the number either way.
            if let quietRt = quietRt {
                quietMark(at: quietRt, captioned: !quietOverprints(quietRt))
            }

            // The strokes, along the floor of the plot. Deliberately at the bottom rather
            // than on the trace: a stroke has no speed of its own, and a glyph on the line
            // would read as a reading taken there.
            ForEach(pumps) { tick in
                pumpMark(tick)
            }

            StripChrome.playhead(playheadRt)
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...ceilingKn)
        .chartXAxisLabel("s from the turn")
        .chartYAxisLabel("kn")
        .chartOverlay { proxy in
            StripChrome.scrubSurface(proxy, domain: domain, playheadRt: $playheadRt)
        }
        .figureHeight(regular: 170, compact: 130)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    /// One pumping effort on the strip's clock.
    ///
    /// **A span, not a point, and the reason is what the engine stores.** A `PumpEpisodeRecord`
    /// carries the first stroke, the last stroke and how many there were between them — the
    /// individual stroke times are never persisted. So a tick per stroke would be an
    /// invention; the honest mark is the episode's own span with its count on it, which is
    /// also the number the chip and the coach line print.
    struct PumpTick: Identifiable, Equatable {
        var id: Int
        /// The first stroke, on the event's clock.
        var startRt: Double
        /// The last stroke. Equal to `startRt` on a single-stroke effort, where the mark
        /// degrades to a tick rather than a band, which is exactly right.
        var endRt: Double
        var strokes: Int
    }

    @ChartContentBuilder
    private func pumpMark(_ tick: PumpTick) -> some ChartContent {
        let floor = ceilingKn * 0.045
        RectangleMark(xStart: .value("From", tick.startRt),
                      xEnd: .value("To", max(tick.endRt, tick.startRt + 0.15)),
                      yStart: .value("Floor", 0),
                      yEnd: .value("Tick", floor))
            .foregroundStyle(DesignTokens.Effort.pumping.opacity(0.75))
            .annotation(position: .top, alignment: .center, spacing: 0) {
                StripChrome.label(TurnAnalytics.strokesText(tick.strokes))
                    .foregroundStyle(DesignTokens.Effort.pumping)
            }
    }

    /// A rule and its caption. The caption sits at the top of the plot rather than beside the
    /// point, because three labels chasing three points on a six-second window overlap on
    /// every turn that mattered.
    /// Closer than this, two captions on the top edge overprint. ("in" now sits at the
    /// engine's entry-window maximum, up to `entrySpeedWindowS` before 0; it never collides
    /// with "low", which is inside the sweep.) The number is `StripChrome`'s, so all four
    /// strips agree on what "close" means.
    private static let captionGapS = StripChrome.captionGapS

    /// The engine's windows, read off the analysis' own config echo so the strip is drawn
    /// to the numbers in force — on a tuned dev build those are not `TurnConfig()`'s.
    struct Windows {
        var entryS: Double = TurnConfig().entrySpeedWindowS
        var minLagS: Double = TurnConfig().minSpeedLagS
        var outcomeS: Double = TurnConfig().outcomeLookaheadS
        /// The clean jibe's quiet tail (engine 0.17.0) — nil in an analysis stored before it,
        /// where nothing measured one and the footnote says nothing about it.
        var quietS: Double? = TurnConfig().cleanQuietS

        init() {}

        init(config: AnalysisConfig) {
            entryS = config.entrySpeedWindow ?? entryS
            minLagS = config.minSpeedLag ?? minLagS
            outcomeS = config.turnOutcomeLookahead
            quietS = config.turnCleanQuietS
        }
    }

    /// Where the quiet tail closes, in seconds from the turn's start — or nil when there is
    /// none (the parameter is off, or the analysis predates it) or when it lands outside the
    /// drawn window, which at the default 10 s against an 8 s run-out is the usual case.
    private var quietRt: Double? {
        guard let quietS = windows.quietS, quietS > 0 else { return nil }
        let rt = slice.speed.exitRt + quietS
        return rt <= domain.upperBound ? rt : nil
    }

    /// Would the `quiet` caption land on the word the `outcome` band prints under it? The band
    /// runs from the sweep's end to the right edge of the plot, and its label is centred on
    /// the part of it that is *visible*.
    private func quietOverprints(_ rt: Double) -> Bool {
        let visibleEnd = min(slice.speed.exitRt + windows.outcomeS, domain.upperBound)
        return abs(rt - 0.5 * (slice.speed.exitRt + visibleEnd)) < Self.captionGapS
    }

    /// The end of the quiet tail: a thin dashed rule, captioned on the **bottom** edge where
    /// the other window words live, because it is a window boundary and not a speed.
    @ChartContentBuilder
    private func quietMark(at rt: Double, captioned: Bool) -> some ChartContent {
        StripChrome.rule(at: rt, dash: [2, 4],
                         tint: DesignTokens.Clean.jibe.opacity(0.55),
                         caption: captioned ? "quiet" : nil)
    }

    /// Does the "axis" caption have to step up out of the row the speed captions sit in?
    ///
    /// It is lifted rather than dropped, which is where "low" and "out" go when *they*
    /// collide. The bottom edge of this plot is not free: the three window bands each print
    /// their own word there (`windowLabel`), and the crossing lands inside the `sweep` band by
    /// construction — so sending "axis" down would trade one overprint for another. Lifted, it
    /// gets a line of its own above the speeds and can collide with nothing.
    private func axisLifted(_ axisRt: Double, lowNearIn: Bool, outNearLow: Bool) -> Bool {
        let occupied = [slice.speed.entryRt]
            + (lowNearIn ? [] : [slice.speed.minRt])
            + (outNearLow && !lowNearIn ? [] : [slice.speed.exitRt])
        return occupied.contains { abs($0 - axisRt) < Self.captionGapS }
    }

    /// The crossing: a dashed rule and the word `axis`, and deliberately no dot.
    ///
    /// No `PointMark`, because there is no *speed* being named here — the other three rules
    /// each mark a number the score is made of, and putting a fourth dot on the trace would
    /// claim the crossing was a fourth reading. It is an instant, so it gets a line.
    @ChartContentBuilder
    private func axisMark(at rt: Double, lifted: Bool) -> some ChartContent {
        RuleMark(x: .value("Seconds", rt))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .foregroundStyle(Color(.label).opacity(0.35))
            .annotation(position: .top, alignment: .center, spacing: lifted ? 13 : 1) {
                Text("axis")
                    .font(.caption2)
                    .foregroundStyle(Color(.label).opacity(0.55))
            }
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

    private var accessibilityText: String {
        var text = String(format: "Speed through the turn: %.1f knots coming in, "
                          + "down to %.1f after %.0f seconds, %.1f knots at the exit "
                          + "%.0f seconds in.",
                          slice.speed.entryKn, slice.speed.minKn, slice.speed.minRt,
                          slice.speed.exitKn, slice.speed.exitRt)
        if let axisRt = slice.axisRt {
            text += String(format: " Through the wind axis %.0f seconds in.", axisRt)
        }
        if ghost != nil { text += " Your best clean jibe is drawn dashed beside it." }
        return text
    }
}
