import SwiftUI
import WingFoilKit

/// Which turn the sheet was opened on — an index into `SessionDetail.analysis.turns`, wrapped
/// so `.sheet(item:)` can carry it.
struct TurnDetailRequest: Identifiable, Equatable {
    let id: Int
}

/// One turn, on a page of its own — the drill-in the session map's dots and the Turns tab's
/// rows have both wanted since they were built.
///
/// **Why it is a sheet over a swipeable set and not a pushed page.** A rider reading his jibes
/// is comparing them: the question after "how was that one" is always "how was the next one",
/// and a push-and-pop between every pair is four taps to answer it. So the sheet holds *every
/// counted turn of the session* in time order and swipes between them, whichever one it was
/// opened on and whatever filter the Turns tab happened to be showing — the filter is a way of
/// looking at the list, not a claim about which turns exist.
///
/// **Course changes are not in the set.** A bear-away has no verdict, no score, no entry tack
/// and no outcome word; the numbers row would be five dashes and the coach line would have
/// nothing to say. They keep their grey dot and their callout on the map, and the "Details"
/// affordance is simply absent on them (`SessionDetail.EventMarker.turnIndex`).
struct TurnDetailSheet: View {
    let detail: SessionDetail
    /// The turn the rider tapped.
    let start: Int

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int

    init(detail: SessionDetail, start: Int) {
        self.detail = detail
        self.start = start
        _selection = State(initialValue: start)
    }

    /// Every counted turn, in time order — the engine already emits turns in time order, so
    /// this is the array's own order with the course changes taken out.
    private var indices: [Int] {
        detail.analysis.turns.indices.filter { detail.analysis.turns[$0].counted }
    }

    private var position: Int? {
        indices.firstIndex(of: selection).map { $0 + 1 }
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(indices, id: \.self) { index in
                    TurnDetailPage(detail: detail, index: index)
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

    /// "Jibe 7 · flew through" — the session map's own wording for the turn
    /// (`SessionDetail.turnTitle`), with the rider's ordinal in front of it. The ordinal
    /// counts turns of the same *kind*, because "jibe 7" is what a rider means: it is his
    /// seventh jibe, not the seventh thing the detector saw.
    private var title: String {
        guard detail.analysis.turns.indices.contains(selection) else { return "Turn" }
        let turn = detail.analysis.turns[selection]
        let ordinal = indices
            .filter { detail.analysis.turns[$0].type == turn.type }
            .firstIndex(of: selection)
            .map { $0 + 1 }
        let kind = TurnAnalytics.typeLabel(turn.type)
        let head = ordinal.map { "\(kind) \($0)" } ?? kind
        return "\(head) · \(TurnOutcomeKind(turn.outcome).label)"
    }
}

/// One turn's page: the drawing, the strip, the numbers and the sentence.
private struct TurnDetailPage: View {
    let detail: SessionDetail
    /// Index into `detail.analysis.turns`.
    let index: Int

    /// Both remembered, because both are a way of *reading* turns rather than a fact about
    /// one: a rider who thinks in wind angles thinks in them on every jibe, and one who has
    /// stopped comparing has stopped comparing.
    @AppStorage("turnDetail.orientation.v1") private var windUpPreferred = true
    @AppStorage("turnDetail.ghost.v1") private var ghostEnabled = true

    /// Built once per turn rather than in `body`: scrubbing re-evaluates this view many times
    /// a second, and re-cutting the window on every frame would walk the sample array with it.
    @State private var slice: TurnSlice?
    @State private var ghost: TurnSlice?
    /// Seconds from the turn's start, while the strip is being scrubbed.
    @State private var playheadRt: Double?
    /// Two columns of small facts is a table at body size and a stack of truncations at
    /// accessibility sizes, so past the threshold it becomes one column.
    @Environment(\.dynamicTypeSize) private var typeSize

    private var turn: TurnRecord? {
        detail.analysis.turns.indices.contains(index) ? detail.analysis.turns[index] : nil
    }

    /// Wind up needs a wind. Where the session has none, the control's second option is
    /// disabled and says why rather than silently drawing north up under a "wind up" label.
    private var windKnown: Bool { detail.windDirDeg != nil }

    /// How many strokes he put in to get out of this one, where the analysis knows — the
    /// chip and the coach line print the same number, and neither prints one when it does
    /// not (`TurnAnalytics.pumpStrokes`).
    private var pumpStrokes: Int? {
        guard let turn, turn.pumped else { return nil }
        return TurnAnalytics.pumpStrokes(for: index, turn: turn,
                                         in: detail.analysis.pumpEpisodes)
    }

    /// How long the wrist was under in this turn, where the engine caught an episode of it
    /// (engine 0.16.0) — the longest one attributed to this turn, since the chip is about
    /// the dunk a rider remembers. Nil under 1 s: at 1 Hz that is a single sample, and "0 s"
    /// would read as a measurement.
    private var submersionS: Double? {
        guard let turn, turn.submerged else { return nil }
        let longest = detail.analysis.submersions
            .filter { $0.turnIndex == index }
            .map(\.durationS)
            .max()
        return longest.flatMap { $0.rounded() >= 1 ? $0 : nil }
    }

    /// Why the star is missing from a jibe that flew through and held its speed (engine
    /// 0.17.0) — the kit's wording, with this analysis' own flight ends and quiet tail, so
    /// the chip says "6 s after" only where the document it was written from can prove it.
    private func notCleanText(_ turn: TurnRecord) -> String? {
        TurnAnalytics.notCleanText(turn, ends: detail.analysis.flightEnds,
                                   quietS: detail.analysis.config.turnCleanQuietS)
    }

    /// Why this turn is a touchdown or a fall (engine 0.18.0) — the kit's wording, with this
    /// analysis' own `turnPumpedMarginalSpeed`, so the one sentence that names a speed names
    /// the speed the run was actually judged against rather than the published default. nil on
    /// a fly-through and on a stored document written before the reason existed.
    private func outcomeText(_ turn: TurnRecord) -> String? {
        TurnAnalytics.outcomeText(
            turn, marginalSpeedKmh: detail.analysis.config.turnPumpedMarginalSpeed)
    }

    private var windUp: Bool { windUpPreferred && windKnown }
    private var showsGhost: Bool { ghostEnabled && ghost != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let turn, let slice {
                    controls
                    TurnDetailMapView(slice: slice, ghost: showsGhost ? ghost : nil,
                                      windUp: windUp, playheadRt: playheadRt)
                    if !slice.hasGeometry { noGeometryNote }
                    TurnDetailStripView(slice: slice, ghost: showsGhost ? ghost : nil,
                                        windows: .init(config: detail.analysis.config),
                                        playheadRt: $playheadRt)
                    numbers(turn, slice: slice)
                    coach(turn, slice: slice)
                    footnote(turn)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .task(id: index) { build() }
    }

    private func build() {
        guard let turn else { return }
        slice = TurnSlice.make(samples: detail.turnSamples, turn: turn,
                               windDirDeg: detail.windDirDeg)
        ghost = TurnSlice.ghost(for: turn, in: detail.analysis.turns,
                                samples: detail.turnSamples, windDirDeg: detail.windDirDeg)
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
                     + "trusts, and none you set on the watch, so the turn is drawn north up.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if ghost != nil {
                Toggle("Compare with best clean jibe", isOn: $ghostEnabled)
                    .font(.subheadline)
            } else {
                Text("Nothing to compare with — this session has no other jibe that flew "
                     + "through the same way round.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var noGeometryNote: some View {
        Label("No GPS fixes through this turn — numbers only.", systemImage: "location.slash")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - Numbers

    /// The engine's numbers, and only the engine's — and since 6 Sep the strip's markers are
    /// the same three numbers at the same times (`TurnSlice.marks`), drawn on the same
    /// maneuver channel, so the two surfaces cannot disagree.
    private func numbers(_ turn: TurnRecord, slice: TurnSlice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                speedStep(String(format: "%.1f", turn.entryKn), "in")
                arrow
                speedStep(String(format: "%.1f", turn.minKn), "low")
                arrow
                speedStep(String(format: "%.1f", turn.exitKn), "out")
                Text("kn")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Text("held \(TurnAnalytics.scoreText(turn.score)) % of entry speed")
                .font(.subheadline.weight(.medium))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                                     count: typeSize.isAccessibilitySize ? 1 : 2),
                      alignment: .leading, spacing: 8) {
                cell("Stopped", String(format: "%.0f s", turn.stoppedS))
                cell("Off foil", String(format: "%.0f s", turn.offFoilS))
                cell("Radius", String(format: "%.0f m", turn.radiusM))
                cell("Heading change", String(format: "%.0f°", abs(turn.netDeg)))
                cell("Entry tack", TurnAnalytics.sideLabel(turn.side))
                cell("Rotation", Self.rotationLabel(turn.direction))
            }

            // The crossing, in words (engine 0.15.0). One row rather than two cells in the
            // grid above: the two angles are one fact read either side of one instant, and
            // splitting them would invite a reader to compare them with the speeds.
            if let axis = Self.axisLine(turn) {
                Text(axis)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                chip(TurnOutcomeKind(turn.outcome).label,
                     symbol: TurnOutcomeKind(turn.outcome).symbolName,
                     tint: TurnOutcomeStyle.color(TurnOutcomeKind(turn.outcome)))
                // The engine's `clean` verdict, not the score flag beside it: a jibe that
                // held its speed and still went in wears the outcome chip alone.
                if turn.clean {
                    chip("clean", symbol: DesignTokens.Glyph.cleanJibe,
                         tint: DesignTokens.Clean.jibe)
                } else if let reason = notCleanText(turn) {
                    // A jibe that flew through and held its speed and is still not clean
                    // (engine 0.17.0). Without this the page said "flew through", said
                    // nothing else, and left the missing star looking like a bug. The star
                    // chip's own rule is untouched: it reads the engine's `clean` and only it.
                    chip(reason, symbol: "star.slash", tint: .secondary)
                }
                if turn.pumped {
                    // "pumped out · 7 strokes" where the analysis counted them. The count is
                    // the engine's own (`PumpEpisodeRecord.strokes` on the episodes this turn
                    // owns), and where there are none the chip says exactly what it said
                    // before rather than "0 strokes", which would be a claim.
                    chip(pumpStrokes.map { "pumped out · \(TurnAnalytics.strokesText($0))" }
                            ?? "pumped out",
                         symbol: DesignTokens.Glyph.takeoffPumped,
                         tint: DesignTokens.Effort.pumping)
                }
                if turn.submerged {
                    // "wrist under 4 s" where an episode of the layer's own list falls in
                    // this turn's outcome window (engine 0.16.0). The flag says the wrist
                    // went under; the episode says for how long, and the two are read from
                    // the one mask so the chip and the map's diamond cannot disagree. No
                    // episode ⇒ the chip says exactly what it said before, never "0 s".
                    chip(submersionS.map { String(format: "wrist under %.0f s", $0) }
                            ?? "wrist under",
                         symbol: DesignTokens.Glyph.splash,
                         tint: DesignTokens.Effort.splash)
                }
                Spacer(minLength: 0)
            }

            // **Why it ended that way** (engine 0.18.0), directly under the chips. Jan asked
            // for "a short comment for the user why a jibe is a touchdown or a fall": the
            // numbers were all on the page already — stopped, off foil, wrist under — and the
            // rider was left to assemble the verdict out of them. One sentence, the engine's
            // own reason, and the same sentence the web session page prints.
            if let why = outcomeText(turn) {
                Text(why)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.10), in: .rect(cornerRadius: 12))
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
        Image(systemName: "arrow.right")
            .font(.caption2)
            .foregroundStyle(.tertiary)
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

    /// "Through the axis · 87° before, 72° after" — the wind-axis crossing, in integers
    /// (engine 0.15.0).
    ///
    /// nil where the engine recorded no crossing, which is every course change, every session
    /// with no usable wind, and every analysis stored before 0.15.0. Absent, not zeroed: "he
    /// started on the axis" and "nobody knows where the axis was" are different sentences, and
    /// only one of them is ever true here.
    static func axisLine(_ turn: TurnRecord) -> String? {
        guard let before = turn.axisBeforeDeg, let after = turn.axisAfterDeg,
              before.isFinite, after.isFinite else { return nil }
        return String(format: "Through the axis · %.0f° before, %.0f° after", before, after)
    }

    /// The direction the **board rotated**, never the tack it was entered on. The engine's
    /// `direction` is signed net heading change — "starboard" is clockwise — and the Turns
    /// tab already says out loud that this is a different field from `side`.
    static func rotationLabel(_ direction: String) -> String {
        switch direction {
        case "starboard": return "clockwise"
        case "port": return "counter-clockwise"
        default: return "unknown"
        }
    }

    // MARK: - The sentence

    private func coach(_ turn: TurnRecord, slice: TurnSlice) -> some View {
        Text(TurnCoach.line(turn: turn, slice: slice, pumpStrokes: pumpStrokes))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    #if TUNING
    /// "Measured at: turnSuccessPct 70 % · minSpeedLag 2 s · turnOutcomeLookahead 12 s" —
    /// the three parameters that define what the strip actually draws, taken from the stored
    /// analysis' `config` echo, which is by construction the values the run used.
    ///
    /// `minSpeedLag` is optional in the echo because it was only written down from engine
    /// 0.14.0; an older stored document simply omits that clause rather than guessing.
    private var thresholdLine: String {
        let config = detail.analysis.config
        // Formatted by the tuning page's own specs, so the footnote and the slider that moved
        // the value print the same string for the same number.
        func say(_ parameter: TuningParameter, _ value: Double) -> String {
            "\(parameter.rawValue) \(parameter.spec.formatted(value))"
        }
        var parts = [say(.turnSuccessPct, config.turnSuccessPct)]
        if let lag = config.minSpeedLag { parts.append(say(.minSpeedLag, lag)) }
        parts.append(say(.turnOutcomeLookahead, config.turnOutcomeLookahead))
        return "Measured at: " + parts.joined(separator: " · ") + "."
    }
    #endif

    private func footnote(_ turn: TurnRecord) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("The drawing is \(Int(TurnSlice.defaultPadS)) s either side of the sweep. "
                 + "Ticks are one second apart; the line is coloured by speed on the ramp at "
                 + "the foot of the picture — cold at a standstill, teal at the speed you "
                 + "came in at, hot above it. North and the wind are marked top right.")
            Text("Score is how much of your entry speed you held through the turn. Speed here is "
                 + "the manoeuvre channel the verdict was scored on, derived from position — "
                 + "the GPS Doppler speed the records use is smoothed through a turn and "
                 + "would read lower at the low point.")
            // The windows are read off this analysis' own config echo, not `TurnConfig()`:
            // on a dev build with tuning on, the defaults are exactly what these are not.
            let windows = TurnDetailStripView.Windows(config: detail.analysis.config)
            Text("The bands under the strip are the engine's windows: \"entry\" is the "
                 + "\(Int(windows.entryS)) s before the sweep, where the entry speed is the "
                 + "maximum; \"sweep\" is where the heading turned; the low point is searched "
                 + "to \(Int(windows.minLagS)) s past the sweep, so it can sit after \"out\"; "
                 + "\"outcome\" is the \(Int(windows.outcomeS)) s the verdict is read from, and "
                 + "the lighter band inside it ends where you were flying again.")
            // The quiet tail (engine 0.17.0). Said in the footnote whether or not the strip
            // could fit its rule mark in — at the default 10 s the mark lands past the
            // drawing's own run-out, and this sentence is then the only place the number is.
            if let quiet = detail.analysis.config.turnCleanQuietS, quiet > 0 {
                Text("A clean jibe also needs \(Int(quiet)) s after the sweep with no "
                     + "touchdown, fall or wrist under.")
            }
            if turn.axisTs != nil {
                Text("The tick marked \"axis\" is the moment the board went through the wind "
                     + "axis — dead downwind on a jibe, head to wind on a tack — which is the "
                     + "crossing the turn is named after.")
            }
            #if TUNING
            Text(thresholdLine)
            #endif
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
