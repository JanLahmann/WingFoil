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

    /// The engine's numbers, and only the engine's. The strip's markers come off the recorded
    /// samples of this window and can differ by a tenth; the verdict does not, so the row that
    /// carries the verdict prints `TurnRecord` and nothing derived.
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

            HStack(spacing: 8) {
                chip(TurnOutcomeKind(turn.outcome).label,
                     symbol: TurnOutcomeKind(turn.outcome).symbolName,
                     tint: TurnOutcomeStyle.color(TurnOutcomeKind(turn.outcome)))
                if turn.type == "jibe" && turn.success {
                    chip("clean", symbol: DesignTokens.Glyph.cleanJibe,
                         tint: DesignTokens.Clean.jibe)
                }
                if turn.pumped {
                    chip("pumped out", symbol: DesignTokens.Glyph.takeoffPumped,
                         tint: DesignTokens.Effort.pumping)
                }
                if turn.submerged {
                    chip("wrist under", symbol: DesignTokens.Glyph.splash,
                         tint: DesignTokens.Effort.splash)
                }
                Spacer(minLength: 0)
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
        Text(TurnCoach.line(turn: turn, slice: slice))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footnote(_ turn: TurnRecord) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("The drawing is \(Int(TurnSlice.defaultPadS)) s either side of the sweep. "
                 + "Ticks are one second apart; the line runs from the off-foil grey at a "
                 + "standstill to the flying teal at your entry speed.")
            Text("Score is how much of your entry speed you carried through. The numbers are "
                 + "the engine's; the marks on the strip are read off this window's own "
                 + "samples and can differ by a tenth of a knot.")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
