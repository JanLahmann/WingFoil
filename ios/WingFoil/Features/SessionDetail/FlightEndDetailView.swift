import Charts
import SwiftUI
import WingFoilKit

/// Which flight end the sheet was opened on — an index into `SessionDetail.analysis.flightEnds`.
struct FlightEndDetailRequest: Identifiable, Equatable {
    let id: Int
}

/// **One straight-line flight end, on a page of its own** — the drill-in the hollow rings on
/// the map have wanted since they were drawn.
///
/// Roughly half a session's losses do not happen in a maneuver. The engine has classified
/// every one of them for as long as it has carried `flightEnds`, the map has drawn each as a
/// hollow ring, and the ring was the end of the road: tapping it said "Fell in · straight-line
/// · stopped 7 s" and there was nowhere further to go. Meanwhile a jibe that ended in exactly
/// the same swim got a drawing, a strip, six numbers and a sentence — for no better reason
/// than that a turn detector had happened to fire.
///
/// So a flight end gets the same page, built from the same parts: the same `Canvas` through
/// `ManeuverFigure`, the same strip chrome, the same footnote voice. What differs is what
/// genuinely differs — see `FlightEndSlice`.
///
/// **The set is every *drawn* flight end**, in time order, swipeable, with a "3 of 9"
/// position: the ones no turn owns and the recording did not truncate
/// (`FlightEndAnalytics.drawnIndices`, which is `PresentationRules.drawnFlightEnds` by index).
/// A turn-owned end is the same swim already counted at its jibe, and a truncated one is a
/// recording that stopped — neither has anything for a page to say.
struct FlightEndDetailSheet: View {
    let detail: SessionDetail
    let start: Int

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int

    init(detail: SessionDetail, start: Int) {
        self.detail = detail
        self.start = start
        _selection = State(initialValue: start)
    }

    private var indices: [Int] { FlightEndAnalytics.drawnIndices(detail.analysis) }

    private var position: Int? { indices.firstIndex(of: selection).map { $0 + 1 } }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(indices, id: \.self) { index in
                    FlightEndDetailPage(detail: detail, index: index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(title).font(.headline)
                        if let position {
                            Text("\(position) of \(indices.count) · swipe for the next")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    /// "Flight 12 · fell in" — the rider's own ordinal, which is the *flight's* number and
    /// not the end's position in the list. He remembers the ride, not the tally.
    private var title: String {
        guard detail.analysis.flightEnds.indices.contains(selection) else { return "Flight end" }
        let end = detail.analysis.flightEnds[selection]
        return "Flight \(end.flightIndex + 1) · "
            + FlightEndAnalytics.outcomeLabel(end.outcome)
    }
}

/// One flight end's page: the drawing, the strips, the numbers and the sentence.
private struct FlightEndDetailPage: View {
    let detail: SessionDetail
    let index: Int

    /// The same preference the turn page keeps, under the same key: a rider who thinks in
    /// wind angles thinks in them on a fall in a straight line too, and two keys would make
    /// one control feel like two.
    @AppStorage("turnDetail.orientation.v1") private var windUpPreferred = true
    #if TUNING
    @AppStorage("turnDetail.padBefore.v1") private var padBeforeS = TurnSlice.defaultPadS
    @AppStorage("turnDetail.padAfter.v1") private var padAfterS = TurnSlice.defaultPadS
    #endif

    @State private var slice: FlightEndSlice?
    @State private var playheadRt: Double?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var end: FlightEndRecord? {
        detail.analysis.flightEnds.indices.contains(index)
            ? detail.analysis.flightEnds[index] : nil
    }

    private var windKnown: Bool { detail.windDirDeg != nil }
    private var windUp: Bool { windUpPreferred && windKnown }

    private var pads: TurnWindowPads {
        #if TUNING
        return TurnWindowPads(beforeS: padBeforeS, afterS: padAfterS)
        #else
        return .standard
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let end, let slice {
                    controls
                    TurnDetailMapView(figure: slice.figure, windUp: windUp,
                                      playheadRt: playheadRt,
                                      onPick: { playheadRt = $0 },
                                      spoken: spoken(end, slice: slice))
                    if !slice.hasGeometry { noGeometryNote }
                    FlightEndStripView(slice: slice, pumps: pumpTicks(end),
                                       playheadRt: $playheadRt)
                    #if TUNING
                    extraStrips(slice)
                    #endif
                    numbers(end, slice: slice)
                    footnote(end, slice: slice)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .task(id: buildKey) { build() }
    }

    /// Rebuild on the turn *and* on either pad: the window is what the slice was cut with,
    /// so a slider that did not re-cut it would move a label and nothing else.
    private var buildKey: String {
        "\(index)-\(pads.beforeS)-\(pads.afterS)"
    }

    private func build() {
        guard let end else { return }
        slice = FlightEndSlice.make(samples: detail.sliceSamples, end: end,
                                    windDirDeg: detail.windDirDeg,
                                    config: FlightEndConfig(),
                                    padBeforeS: pads.beforeS, padAfterS: pads.afterS)
        playheadRt = nil
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Orientation", selection: $windUpPreferred) {
                Text("North up").tag(false)
                Text("Wind up").tag(true)
            }
            .pickerStyle(.segmented)
            .disabled(!windKnown)
            .accessibilityLabel("Map orientation")

            if !windKnown {
                Text("Wind up needs a wind direction. This session has none the engine "
                     + "trusts, and none you set on the watch, so the track is drawn north up.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            #if TUNING
            TurnWindowControl(beforeS: $padBeforeS, afterS: $padAfterS, quietS: nil)
            #endif
        }
    }

    private var noGeometryNote: some View {
        Label("No GPS fixes through this flight end — numbers only.",
              systemImage: "location.slash")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - Strips

    #if TUNING
    @ViewBuilder
    private func extraStrips(_ slice: FlightEndSlice) -> some View {
        // The outcome window is the flight end's own "sweep": the span every verdict on this
        // page was read from. Shading it on all three strips is what makes them one picture.
        let window = 0...slice.windows.outcomeS
        TurnHeadingStripView(
            angles: SliceAngles.make(points: slice.points, windDirDeg: slice.windDirDeg),
            sweep: window,
            // A flight end has no sweep — it is an instant. The window every strip on this
            // page shades is the one the verdict was read from.
            sweepCaption: "outcome",
            domain: slice.timeDomain,
            axisRt: nil,
            peakRateDegS: detail.analysis.config.turnPeakRate,
            continueRateDegS: detail.analysis.config.turnContinueRate
                ?? TurnConfig().continueRateDegS,
            playheadRt: $playheadRt)
        TurnBaroStripView(baro: detail.baro(points: slice.points, at: slice.end.ts),
                          domain: slice.timeDomain, sweep: window,
                          sweepCaption: "outcome",
                          playheadRt: $playheadRt)
    }
    #endif

    /// The pumping efforts this end owns: the episodes overlapping the window the verdict was
    /// judged on. The engine names a turn on a `recovery` episode but never a flight end, so
    /// overlap is the only rule available — and it is the same one the turn chip falls back to.
    private func pumpTicks(_ end: FlightEndRecord) -> [TurnDetailStripView.PumpTick] {
        let window = end.ts...(end.ts + FlightEndConfig().outcomeWindowS)
        return detail.analysis.pumpEpisodes.enumerated().compactMap { offset, episode in
            guard episode.endTs >= window.lowerBound,
                  episode.startTs <= window.upperBound else { return nil }
            return TurnDetailStripView.PumpTick(id: offset,
                                                startRt: episode.startTs - end.ts,
                                                endRt: episode.endTs - end.ts,
                                                strokes: episode.strokes)
        }
    }

    // MARK: - Numbers

    private func numbers(_ end: FlightEndRecord, slice: FlightEndSlice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                speedStep(String(format: "%.1f", slice.speed.entryKn), "in")
                arrow
                speedStep(slice.speed.lowKn.map { String(format: "%.1f", $0) } ?? "—", "low")
                arrow
                speedStep(slice.speed.outKn.map { String(format: "%.1f", $0) } ?? "—", "out")
                Text("kn").font(.footnote).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            // Said here rather than only in the footnote, because it is the one place this
            // page differs from the turn page in a way a reader could be misled by: on a
            // turn all three numbers are the engine's, and here only the middle one is.
            Text(slice.speed.outKn == nil
                 ? "Never back up to flying speed inside the window."
                 : "Back to flying speed \(secondsText(slice.speed.recoverRt)) after the end.")
                .font(.subheadline.weight(.medium))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                                     count: typeSize.isAccessibilitySize ? 1 : 2),
                      alignment: .leading, spacing: 8) {
                cell("Stopped", String(format: "%.0f s", end.stoppedS))
                cell("Off foil", String(format: "%.0f s", end.offFoilS))
                cell("Flight", "#\(end.flightIndex + 1)")
                cell("Evidence", String(format: "%.0f s", end.windowS))
            }

            HStack(spacing: 8) {
                chip(FlightEndAnalytics.outcomeLabel(end.outcome)
                        + (end.borderline ? " (borderline)" : ""),
                     symbol: TurnOutcomeKind(end.outcome).symbolName,
                     tint: TurnOutcomeStyle.color(TurnOutcomeKind(end.outcome)))
                if end.pumped {
                    chip("pumped out", symbol: DesignTokens.Glyph.takeoffPumped,
                         tint: DesignTokens.Effort.pumping)
                }
                if end.submerged {
                    chip("wrist under", symbol: DesignTokens.Glyph.splash,
                         tint: DesignTokens.Effort.splash)
                }
                Spacer(minLength: 0)
            }

            Text(FlightEndAnalytics.outcomeText(end))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.10), in: .rect(cornerRadius: 12))
    }

    private func secondsText(_ rt: Double?) -> String {
        rt.map { String(format: "%.0f s", $0) } ?? "—"
    }

    private func speedStep(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption).font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var arrow: some View {
        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
    }

    private func cell(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption2).foregroundStyle(.tertiary)
            Text(value).font(.caption.monospacedDigit())
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func chip(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption2).foregroundStyle(tint)
            Text(text).font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.secondary.opacity(0.14)))
    }

    private func spoken(_ end: FlightEndRecord, slice: FlightEndSlice) -> String {
        var parts = [
            "Flight \(end.flightIndex + 1) ending, drawn \(windUp ? "wind up" : "north up")",
            FlightEndAnalytics.outcomeText(end),
        ]
        if let low = slice.speed.lowKn {
            parts.append(String(format: "down to %.1f knots", low))
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Footnote

    private func footnote(_ end: FlightEndRecord, slice: FlightEndSlice) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("The drawing is \(Int(slice.padBeforeS)) s before the end and "
                 + "\(Int(slice.padAfterS)) s after it. The thick, coloured part is the "
                 + "flight; everything past the dot is already off the foil. Ticks are one "
                 + "second apart and the numbers along the path are every five. North and "
                 + "the wind are marked top right.")
            Text("The bands are the engine's windows: \"entry\" is the "
                 + "\(Int(slice.windows.entryS)) s the flight was ending at, \"outcome\" is "
                 + "the \(Int(slice.windows.outcomeS)) s the verdict is read from, and "
                 + "\"evidence\" is how much gap-free recording there actually was.")
            // The honest sentence about the three numbers, which is the one thing this page
            // has to say that the turn page does not.
            Text("Only \"low\" is the engine's — it is the slowest sample of the off-foil "
                 + "run, placed where this window comes nearest it. \"In\" is the fastest "
                 + "sample of the entry window and \"out\" is where the speed came back to "
                 + "the engine's flying-again threshold, both read off the drawn line: a "
                 + "flight end record carries no entry or exit speed of its own.")
            Text("Speed here is the manoeuvre channel, derived from position — the GPS "
                 + "Doppler speed the records use is smoothed and would read differently.")
            if end.borderline {
                Text("\"Borderline\" means the stop ran past the touchdown limit without "
                     + "reaching the fall one.")
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The flight end's speed strip: the same picture as the turn's, over the windows a flight
/// end is actually judged on.
///
/// It is a separate view rather than a mode of `TurnDetailStripView` because the two draw
/// different windows from different config, and one view with an enum in it would spend more
/// lines on the branch than on either strip. What they *share* — the bands, the rules, the
/// captions, the scrub, the playhead — is `StripChrome`, and that is the part that had to be
/// shared or the two would drift.
private struct FlightEndStripView: View {
    let slice: FlightEndSlice
    var pumps: [TurnDetailStripView.PumpTick] = []
    @Binding var playheadRt: Double?

    private var domain: ClosedRange<Double> { slice.timeDomain }

    private var ceilingKn: Double {
        max((slice.points.map(\.kn).max() ?? slice.speed.entryKn) * 1.15, 5)
    }

    /// Would the `evidence` word land on the `outcome` band's own word? The band runs from the
    /// end to the lookahead, its label is centred on the part of it that is *visible*, and the
    /// evidence rule sits inside it whenever the recording was shorter than the lookahead —
    /// which is most falls.
    private var evidenceOverprints: Bool {
        let visibleEnd = min(slice.windows.outcomeS, domain.upperBound)
        return abs(slice.windows.evidenceS - visibleEnd / 2) < StripChrome.captionGapS
    }

    var body: some View {
        Chart {
            StripChrome.band(from: -slice.windows.entryS, to: 0,
                             tint: StripChrome.Band.entry, caption: "entry")
            StripChrome.band(from: 0, to: slice.windows.outcomeS,
                             tint: StripChrome.Band.outcome, caption: "outcome")
            // How much gap-free record there actually was past the end — a property of the
            // recording rather than of the configuration, which is why it is drawn as a rule
            // and not as a third band: it is a limit, not a window.
            //
            // Its caption steps aside where it would print over the word the `outcome` band
            // prints under it — the same "only when it fits" rule the turn strip's `quiet`
            // mark follows. On Flight 4 the evidence ran out at 5 s and the two words came out
            // as "evidenᵗoutcome". The rule itself is always drawn; only the word yields.
            if slice.windows.evidenceS > 0, slice.windows.evidenceS <= domain.upperBound {
                StripChrome.rule(at: slice.windows.evidenceS, dash: [2, 4],
                                 tint: Color.secondary.opacity(0.5),
                                 caption: evidenceOverprints ? nil : "evidence")
            }
            if let recoverRt = slice.speed.recoverRt, recoverRt > 0 {
                StripChrome.band(from: 0, to: recoverRt,
                                 tint: StripChrome.Band.recovery, caption: nil)
            }

            ForEach(Array(slice.points.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Seconds", point.rt), y: .value("Speed", point.kn))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.8))
                    .foregroundStyle(Color.accentColor)
            }

            // The end itself: the instant the flight machine said the foil had stopped
            // carrying. Everything the page is about is measured from here.
            StripChrome.rule(at: 0, dash: [2, 3], tint: Color.secondary.opacity(0.6),
                             width: 1, caption: nil, onTop: true)

            mark(at: slice.speed.entryRt, kn: slice.speed.entryKn, label: "in")
            if let lowRt = slice.speed.lowRt, let lowKn = slice.speed.lowKn {
                mark(at: lowRt, kn: lowKn, label: "low",
                     below: abs(lowRt) < StripChrome.captionGapS)
            }
            if let outRt = slice.speed.recoverRt, let outKn = slice.speed.outKn {
                mark(at: outRt, kn: outKn, label: "out")
            }

            ForEach(pumps) { tick in
                RectangleMark(xStart: .value("From", tick.startRt),
                              xEnd: .value("To", max(tick.endRt, tick.startRt + 0.15)),
                              yStart: .value("Floor", 0),
                              yEnd: .value("Tick", ceilingKn * 0.045))
                    .foregroundStyle(DesignTokens.Effort.pumping.opacity(0.75))
                    .annotation(position: .top, alignment: .center, spacing: 0) {
                        StripChrome.label(TurnAnalytics.strokesText(tick.strokes))
                            .foregroundStyle(DesignTokens.Effort.pumping)
                    }
            }

            StripChrome.playhead(playheadRt)
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...ceilingKn)
        .chartXAxisLabel("s from the end")
        .chartYAxisLabel("kn")
        .chartOverlay { proxy in
            StripChrome.scrubSurface(proxy, domain: domain, playheadRt: $playheadRt)
        }
        .figureHeight(regular: 170, compact: 130)
        .accessibilityElement()
        .accessibilityLabel(spoken)
    }

    @ChartContentBuilder
    private func mark(at rt: Double, kn: Double, label: String,
                      below: Bool = false) -> some ChartContent {
        RuleMark(x: .value("Seconds", rt))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            .foregroundStyle(Color.secondary.opacity(0.5))
            .annotation(position: below ? .bottom : .top, alignment: .center, spacing: 1) {
                StripChrome.caption("\(label) \(String(format: "%.1f", kn))")
            }
        PointMark(x: .value("Seconds", rt), y: .value("Speed", kn))
            .symbolSize(28)
            .foregroundStyle(Color.accentColor)
    }

    private var spoken: String {
        var text = String(format: "Speed through the flight end: %.1f knots coming in",
                          slice.speed.entryKn)
        if let low = slice.speed.lowKn { text += String(format: ", down to %.1f", low) }
        if let out = slice.speed.outKn, let rt = slice.speed.recoverRt {
            text += String(format: ", back to %.1f after %.0f seconds", out, rt)
        } else {
            text += ", never back to flying speed in the window"
        }
        return text + "."
    }
}
