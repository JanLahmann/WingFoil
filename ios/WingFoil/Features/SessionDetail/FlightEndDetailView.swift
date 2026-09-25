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

    private var indices: [Int] { detail.drawnFlightEndIndices }

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
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        // Same trade as the turn sheet: a detent is a compact-width idea, `.page` is the
        // regular-width one, and each is ignored where the other applies.
        .presentationSizing(.page)
        .presentationDragIndicator(.visible)
    }

    /// **"Flight end 3 of 9"** — the screen's name, and where in the set you are (pattern A,
    /// the same rename as the turn page's).
    private var title: String {
        guard let position else { return "Flight end" }
        return "Flight end \(position) of \(indices.count)"
    }

    /// "Flight 12 · fell in · swipe for the next" — the rider's own ordinal, which is the
    /// *flight's* number and not the end's position in the list. He remembers the ride, not
    /// the tally.
    private var subtitle: String {
        guard detail.analysis.flightEnds.indices.contains(selection) else {
            return "swipe for the next"
        }
        let end = detail.analysis.flightEnds[selection]
        return "Flight " + String(end.flightIndex + 1) + " · "
            + FlightEndAnalytics.outcomeLabel(end.outcome) + " · swipe for the next"
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
            // Page-sized sheet on an iPad, same readable measure inside it as the turn page.
            .readableColumn()
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
                Text(Copy.noWindForOrientation + " The track is drawn north up.")
                    .font(.caption2)
                    .foregroundStyle(.readableSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            #if TUNING
            TurnWindowControl(beforeS: $padBeforeS, afterS: $padAfterS, quietS: nil)
            #endif
        }
    }

    private var noGeometryNote: some View {
        Label("No GPS fixes through this flight end. Numbers only.",
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
                speedStep(Fmt.knValue(slice.speed.entryKn, digits: 1), "in")
                arrow
                speedStep(Fmt.knValue(slice.speed.lowKn, digits: 1), "low")
                arrow
                speedStep(Fmt.knValue(slice.speed.outKn, digits: 1), "out")
                Text(Fmt.knUnit).font(.footnote).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            // Said here rather than only in the footnote, because it is the one place this
            // page differs from the turn page in a way a reader could be misled by: on a
            // turn all three numbers are the engine's, and here only the middle one is.
            Text(slice.speed.outKn == nil
                 ? "Never back up to flying speed inside the window."
                 : "Back to flying speed " + secondsText(slice.speed.recoverRt)
                    + " after the end.")
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
                     // A glide-out wears its own neutral ring, never the flew check (F9e).
                     symbol: FlightPairing.Outcome(endOutcome: end.outcome,
                                                   truncated: end.truncated).symbolName,
                     tint: FlightEndMark.color(FlightPairing.Outcome(endOutcome: end.outcome,
                                                                     truncated: end.truncated)))
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
            Text(caption).font(.caption2).foregroundStyle(.readableSecondary)
        }
    }

    private var arrow: some View {
        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
    }

    private func cell(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption2).foregroundStyle(.readableSecondary)
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
            "Flight " + String(end.flightIndex + 1) + " ending, drawn "
                + (windUp ? "wind up" : "north up"),
            FlightEndAnalytics.outcomeText(end),
        ]
        if let low = slice.speed.lowKn {
            parts.append("down to " + Fmt.kn(low, digits: 1))
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Footnote

    private func footnote(_ end: FlightEndRecord, slice: FlightEndSlice) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            // Built in locals: one `+` chain long enough to carry a whole paragraph is what
            // the type checker gives up on inside a ViewBuilder.
            let drawn = "The drawing is " + String(Int(slice.padBeforeS))
                + " s before the end and " + String(Int(slice.padAfterS)) + " s after it. "
            let marks = "The thick, coloured part is the flight. "
                + "Everything past the dot is already off the foil. "
                + "Ticks are one second apart. "
                + Copy.pathNumbers + " " + Copy.northAndWind
            Text(drawn + marks)
            let entryBand = "The bands are the engine's windows. \"Entry\" is the "
                + String(Int(slice.windows.entryS)) + " s the flight was ending at. "
            let outcomeBand = Copy.outcomeWindow(seconds: Int(slice.windows.outcomeS))
                + " \"Evidence\" is how much gap-free recording there actually was."
            Text(entryBand + outcomeBand)
            // The honest sentence about the three numbers, which is the one thing this page
            // has to say that the turn page does not.
            Text("Only \"low\" is the engine's. "
                 + "It is the slowest sample of the off-foil run, placed where this window "
                 + "comes nearest it.\n\n"
                 + "\"In\" is the fastest sample of the entry window. "
                 + "\"Out\" is where the speed came back to the engine's flying-again "
                 + "threshold.\n\n"
                 + "Both are read off the drawn line. "
                 + "A flight end record holds no entry or exit speed of its own.")
            Text("Speed here is the manoeuvre channel, derived from position. "
                 + "The GPS Doppler speed the records use is smoothed. "
                 + "It would read differently.")
            if end.borderline {
                Text("\"Borderline\" means the stop ran past the touchdown limit without "
                     + "reaching the fall one.")
            }
        }
        .font(.caption2)
        .foregroundStyle(.readableSecondary)
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

    /// The top of the y axis, **in the rider's unit** (Settings → Units) — the series is
    /// converted onto the plot, so the domain travels with it.
    private var ceiling: Double {
        Speed.value(max((slice.points.map(\.kn).max() ?? slice.speed.entryKn) * 1.15, 5))
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
                LineMark(x: .value("Seconds", point.rt),
                         y: .value("Speed", Speed.value(point.kn)))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.8))
                    .foregroundStyle(Color.accentColor)
            }

            // The end itself: the instant the flight machine said the foil had stopped
            // carrying. Everything the page is about is measured from here.
            StripChrome.rule(at: 0, dash: [2, 3], tint: Color.secondary.opacity(0.6),
                             width: 1, caption: nil, onTop: true)

            // A caption that would print over one already placed climbs a row
            // (`captionRows`) — never under the plot, where the time axis' numbers are.
            let rows = captionRows
            mark(at: slice.speed.entryRt, kn: slice.speed.entryKn, label: "in", row: rows[0])
            if let lowRt = slice.speed.lowRt, let lowKn = slice.speed.lowKn {
                mark(at: lowRt, kn: lowKn, label: "low", row: rows[1])
            }
            if let outRt = slice.speed.recoverRt, let outKn = slice.speed.outKn {
                mark(at: outRt, kn: outKn, label: "out", row: rows[2])
            }

            ForEach(pumps) { tick in
                RectangleMark(xStart: .value("From", tick.startRt),
                              xEnd: .value("To", max(tick.endRt, tick.startRt + 0.15)),
                              yStart: .value("Floor", 0),
                              yEnd: .value("Tick", ceiling * 0.045))
                    .foregroundStyle(DesignTokens.Effort.pumping.opacity(0.75))
                    .annotation(position: .top, alignment: .center, spacing: 0) {
                        StripChrome.label(TurnAnalytics.strokesText(tick.strokes))
                            .foregroundStyle(DesignTokens.Effort.pumping)
                    }
            }

            StripChrome.playhead(playheadRt)
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...ceiling)
        .padding(.top, CGFloat(captionRows.max() ?? 0) * StripChrome.captionRowStep)
        .chartXAxisLabel("s from the end")
        .chartYAxisLabel(Fmt.knUnit)
        .chartOverlay { proxy in
            StripChrome.scrubSurface(proxy, domain: domain, playheadRt: $playheadRt)
        }
        .figureHeight(regular: 170, compact: 130, wide: 220)
        .accessibilityElement()
        .accessibilityLabel(spoken)
    }

    /// The row each of "in", "low" and "out" goes on (`LabelSpacing.rows`). A caption the
    /// slice has no number for is placed far off the window, where it collides with nothing.
    private var captionRows: [Int] {
        let away = domain.upperBound + 1_000
        return LabelSpacing.rows([slice.speed.entryRt,
                                  slice.speed.lowKn == nil ? away : (slice.speed.lowRt ?? away),
                                  slice.speed.outKn == nil ? away + 1_000
                                                           : (slice.speed.recoverRt ?? away)],
                                 gap: max(StripChrome.captionGapS,
                                          (domain.upperBound - domain.lowerBound) / 8))
    }

    @ChartContentBuilder
    private func mark(at rt: Double, kn: Double, label: String,
                      row: Int = 0) -> some ChartContent {
        RuleMark(x: .value("Seconds", rt))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            .foregroundStyle(Color.secondary.opacity(0.5))
            .annotation(position: .top, alignment: .center,
                        spacing: StripChrome.captionSpacing(row: row)) {
                StripChrome.caption("\(label) \(Fmt.knValue(kn, digits: 1))")
            }
        PointMark(x: .value("Seconds", rt), y: .value("Speed", Speed.value(kn)))
            .symbolSize(28)
            .foregroundStyle(Color.accentColor)
    }

    private var spoken: String {
        // Spoken in the rider's unit, the one the strip above is drawn in (Settings → Units).
        var text = "Speed through the flight end: " + Fmt.kn(slice.speed.entryKn, digits: 1)
            + " coming in"
        if let low = slice.speed.lowKn { text += ", down to " + Fmt.knValue(low, digits: 1) }
        if let out = slice.speed.outKn, let rt = slice.speed.recoverRt {
            text += String(format: ", back to %@ after %.0f seconds",
                           Fmt.knValue(out, digits: 1), rt)
        } else {
            text += ", never back to flying speed in the window"
        }
        return text + "."
    }
}
