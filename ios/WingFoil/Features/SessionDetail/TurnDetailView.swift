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
    /// Bumped whenever the page on screen is a clean jibe — on the open and on every swipe
    /// onto one — and the success haptic follows it. A counter rather than the selection so
    /// swiping between two clean jibes taps twice and a touchdown never taps.
    @State private var cheers = 0
    /// The pager's ‹ › request; the sheet has no buttons for it, so it stays nil.
    @State private var pageRequest: SessionPaging.Step?

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

    /// The turn `step` places away in the swipe set, as the pager's id; nil at either end.
    private func neighbour(_ step: Int) -> String? {
        guard let at = indices.firstIndex(of: selection),
              indices.indices.contains(at + step) else { return nil }
        return String(indices[at + step])
    }

    var body: some View {
        NavigationStack {
            // The session page's pager, not a page-style `TabView` (Jan, 28 Sep 2026: "scrolling
            // gets stuck"). The `TabView` is a paging scroll view around the page's own, and
            // a vertical scroll view inside a horizontal one gives the touch up on any drag
            // whose first points lean sideways — which a thumb's do — so the page would not
            // move. `SessionPager` is a drag beside the scroll, not a scroll view around it,
            // and it turns only on a clearly sideways drag (`SessionPaging.isHorizontal`).
            SessionPager(older: neighbour(-1), newer: neighbour(+1),
                         request: $pageRequest,
                         onTurn: { id in if let index = Int(id) { selection = index } },
                         page: TurnDetailPage(detail: detail, index: selection).id(selection),
                         preview: { id in TurnDetailPage(detail: detail, index: Int(id) ?? selection) })
            // One per visit to the turn page, not one per swipe: the question the beta has
            // is whether the page is reached at all.
            .task { Usage.record(.turnPage) }
            // The clean jibe gets its moment (UX review #5, 27 Sep 2026): one short success
            // tap as it comes on screen, the same feedback the Records page gives a new best.
            .onAppear { cheerIfClean(selection) }
            .onChange(of: selection) { _, new in cheerIfClean(new) }
            .sensoryFeedback(.success, trigger: cheers)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(title).font(.headline)
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.readableSecondary)
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
        // `.large` is a *detent*, and detents are a compact-width idea: on an iPad the same
        // sheet came up as the system's default form sheet — about 570 × 640 pt — with the
        // turn drawing, its strip and the numbers row folded into a window smaller than the
        // phone's. `.page` is the regular-width answer to the same request ("as much of the
        // screen as a sheet may have"), and it is ignored on the phone, where the detent
        // above is still what decides.
        .presentationSizing(.page)
        .presentationDragIndicator(.visible)
    }

    private func cheerIfClean(_ index: Int) {
        guard detail.analysis.turns.indices.contains(index),
              detail.analysis.turns[index].clean else { return }
        cheers += 1
    }

    /// **"Jibe 2 of 5"** — the turn, counted among its own kind (UX review #5, 27 Sep 2026).
    ///
    /// "Jibe 2" is what a rider means: his second jibe, not the second thing the detector
    /// saw. The title used to be "Turn 7 of 12" (pattern A: a screen needs a name, and the
    /// verdict is content), and it still is no verdict: that moved to the hero word under
    /// the drawing, where it is large. "of 5" says how many jibes the afternoon held.
    private var title: String {
        TurnDetailSheet.kindPosition(of: selection, in: detail)
            .map { "\($0.kind) \($0.ordinal) of \($0.count)" } ?? "Turn"
    }

    /// "42:15 · turn 7 of 12" — when on the session clock, as the Turns list prints it, and
    /// where in the swipe set you are. The set mixes jibes and tacks, so the title's "of 5"
    /// is not the swipe count and this line is. "swipe for the next" went: the page dots of
    /// every iPhone pager say it, and it sat inside the content line (UX review #5).
    private var subtitle: String {
        guard detail.analysis.turns.indices.contains(selection), let position else {
            return ""
        }
        let turn = detail.analysis.turns[selection]
        return Fmt.clock(turn.ts) + " · turn \(position) of \(indices.count)"
    }

    /// The turn's kind, its ordinal among the counted turns of that kind, and how many
    /// there are — the title's three numbers and the doubt mail's first line.
    static func kindPosition(of index: Int, in detail: SessionDetail)
        -> (kind: String, ordinal: Int, count: Int)? {
        let turns = detail.analysis.turns
        guard turns.indices.contains(index) else { return nil }
        let type = turns[index].type
        let same = turns.indices.filter { turns[$0].counted && turns[$0].type == type }
        guard let at = same.firstIndex(of: index) else { return nil }
        return (TurnAnalytics.typeLabel(type), at + 1, same.count)
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
    #if TUNING
    /// The drawn window, remembered per phone — see `TurnWindowControl`. Dev only: the public
    /// build's footnote promises 8 s either side and two turns drawn at one scale in time.
    @AppStorage("turnDetail.padBefore.v1") private var padBeforeS = TurnSlice.defaultPadS
    @AppStorage("turnDetail.padAfter.v1") private var padAfterS = TurnSlice.defaultPadS
    #endif

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
            turn, marginalSpeedKmh: detail.analysis.config.turnPumpedMarginalSpeed,
            discipline: detail.row.analysisDiscipline)
    }

    private var windUp: Bool { windUpPreferred && windKnown }
    private var showsGhost: Bool { ghostEnabled && ghost != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let turn, let slice {
                    controls
                    TurnDetailMapView(slice: slice, ghost: showsGhost ? ghost : nil,
                                      windUp: windUp, playheadRt: playheadRt,
                                      onPick: { playheadRt = $0 })
                    if !slice.hasGeometry { noGeometryNote }
                    verdict(turn, slice: slice)
                    TurnDetailStripView(slice: slice, ghost: showsGhost ? ghost : nil,
                                        windows: .init(config: detail.analysis.config),
                                        pumps: pumpTicks(turn),
                                        playheadRt: $playheadRt)
                    #if TUNING
                    extraStrips(slice)
                    #endif
                    numbers(turn, slice: slice)
                    #if TUNING
                    // The dev build's turn workbench (docs/presentation/channels-tuning.md, "Tuning this
                    // turn"): the ground-truth label, the outcome ladder's working, the
                    // what-if against the published defaults and the per-sample evidence
                    // table. A screen of its own since 19 Sep 2026, so this is the row that
                    // pushes it. One insertion, one view, compiled out of the app external
                    // testers get.
                    DevTurnWorkbenchLink(detail: detail, index: index)
                    #endif
                    TurnDoubtButton(detail: detail, index: index)
                    footnote(turn)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            // The sheet is page-sized on an iPad, so the page inside it needs the same
            // measure every other column of the app keeps.
            .readableColumn()
        }
        .task(id: buildKey) { build() }
    }

    /// The drawn window is what the slice was *cut* with, so a pad that changed without
    /// re-cutting would move a caption and nothing else. Keyed on the turn and both pads.
    private var buildKey: String { "\(index)-\(pads.beforeS)-\(pads.afterS)" }

    /// The lead-in and run-out in force. `.standard` in the public build, where there is no
    /// control and the footnote's "8 s either side" is a promise.
    private var pads: TurnWindowPads {
        #if TUNING
        return TurnWindowPads(beforeS: padBeforeS, afterS: padAfterS)
        #else
        return .standard
        #endif
    }

    private func build() {
        guard let turn else { return }
        slice = TurnSlice.make(samples: detail.sliceSamples, turn: turn,
                               windDirDeg: detail.windDirDeg,
                               padBeforeS: pads.beforeS, padAfterS: pads.afterS)
        ghost = TurnSlice.ghost(for: turn, in: detail.analysis.turns,
                                samples: detail.sliceSamples, windDirDeg: detail.windDirDeg,
                                padBeforeS: pads.beforeS, padAfterS: pads.afterS)
        playheadRt = nil
    }

    /// The pumping efforts this turn owns, as spans on its own clock — the same episodes the
    /// `pumped out` chip counts (`TurnAnalytics.pumpStrokes`), placed in time.
    private func pumpTicks(_ turn: TurnRecord) -> [TurnDetailStripView.PumpTick] {
        let window = turn.ts...(turn.endTs + turn.outcomeWindowS)
        return detail.analysis.pumpEpisodes.enumerated().compactMap { offset, episode in
            let owned = episode.turnIndex == index
            let overlaps = episode.endTs >= window.lowerBound
                && episode.startTs <= window.upperBound
            guard owned || overlaps else { return nil }
            return TurnDetailStripView.PumpTick(id: offset,
                                                startRt: episode.startTs - turn.ts,
                                                endRt: episode.endTs - turn.ts,
                                                strokes: episode.strokes)
        }
    }

    #if TUNING
    /// **The heading strip and the barometer strip**, under the speed one and on its clock.
    ///
    /// Dev only, both of them, and for the same reason: they are pictures of *detectors*.
    /// The heading strip draws the three numbers that decide where a jibe begins and ends,
    /// and the barometer strip draws the one line that decides whether a touchdown was
    /// really a fall. A rider does not ask what his rate of turn was in degrees per second;
    /// somebody tuning `turnPeakRate` asks nothing else.
    @ViewBuilder
    private func extraStrips(_ slice: TurnSlice) -> some View {
        let config = detail.analysis.config
        TurnHeadingStripView(
            angles: SliceAngles.make(points: slice.points, windDirDeg: slice.windDirDeg),
            sweep: 0...slice.speed.exitRt,
            domain: slice.timeDomain,
            axisRt: slice.axisRt,
            peakRateDegS: config.turnPeakRate,
            continueRateDegS: config.turnContinueRate ?? TurnConfig().continueRateDegS,
            playheadRt: $playheadRt)
        TurnBaroStripView(baro: detail.baro(points: slice.points, at: slice.turn.ts),
                          domain: slice.timeDomain,
                          sweep: 0...slice.speed.exitRt,
                          playheadRt: $playheadRt)
    }
    #endif

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
                Text(Copy.noWindForOrientation + " " + AppShellCopy.TurnPage.drawnNorthUp)
                    .font(.caption2)
                    .foregroundStyle(.readableSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            #if TUNING
            TurnWindowControl(beforeS: $padBeforeS, afterS: $padAfterS,
                              quietS: detail.analysis.config.turnCleanQuietS)
            #endif

            if ghost != nil {
                Toggle(AppShellCopy.TurnPage.compareWithBest, isOn: $ghostEnabled)
                    .font(.subheadline)
            } else {
                Text(AppShellCopy.TurnPage.nothingToCompare)
                    .font(.caption2)
                    .foregroundStyle(.readableSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var noGeometryNote: some View {
        Label(AppShellCopy.TurnPage.noGeometry, systemImage: "location.slash")
            .font(.caption)
            .foregroundStyle(.readableSecondary)
    }

    // MARK: - Numbers

    /// The engine's numbers, and only the engine's — and since 6 Sep the strip's markers are
    /// the same three numbers at the same times (`TurnSlice.marks`), drawn on the same
    /// maneuver channel, so the two surfaces cannot disagree.
    private func numbers(_ turn: TurnRecord, slice: TurnSlice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                speedStep(Fmt.knValue(turn.entryKn, digits: 1), "in")
                arrow
                speedStep(Fmt.knValue(turn.minKn, digits: 1), "low")
                arrow
                speedStep(Fmt.knValue(turn.exitKn, digits: 1), "out")
                Text(Fmt.knUnit)
                    .font(.footnote)
                    .foregroundStyle(.readableSecondary)
                Spacer(minLength: 0)
            }
            Text("held " + TurnAnalytics.scoreText(turn.score) + " % of entry speed")
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
                    .foregroundStyle(.readableSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The outcome and the star are the hero's now (`verdict`), so the chips are the
            // facts beside the verdict: why a flown jibe lost its star, the pump-out, the
            // wrist. Saying "touchdown" large and again in a chip was one fact twice.
            HStack(spacing: 8) {
                if !turn.clean, let reason = notCleanText(turn) {
                    // A jibe that flew through and held its speed and is still not clean
                    // (engine 0.17.0). Without this the page said "flew through", said
                    // nothing else, and left the missing star looking like a bug. The star
                    // chip's own rule is untouched: it reads the engine's `clean` and only it.
                    chip(reason, symbol: "star.slash", tint: .readableSecondary)
                }
                if turn.pumped {
                    // "pumped out · 7 strokes" where the analysis counted them. The count is
                    // the engine's own (`PumpEpisodeRecord.strokes` on the episodes this turn
                    // owns), and where there are none the chip says exactly what it said
                    // before rather than "0 strokes", which would be a claim.
                    chip(pumpStrokes.map { "pumped out · " + TurnAnalytics.strokesText($0) }
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
                    .foregroundStyle(.readableSecondary)
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
            Text(caption).font(.caption2).foregroundStyle(.readableSecondary)
        }
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.caption2)
            .foregroundStyle(.tertiary)
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
        .foregroundStyle(.readableSecondary)
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
        return String(format: Copy.axisSweepFormat, before, after)
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

    // MARK: - The verdict and the sentence

    /// **The verdict, large, and the coach line under it** (UX review #5 and #6, 27 Sep
    /// 2026). The word a rider opened the page to read — "Clean", "Flew through",
    /// "Touchdown", "Fell in" — in its outcome ink, with the star on a clean one. Then the
    /// one sentence about where the speed went and, on a turn that was not clean, what to
    /// try next time (`TurnCoach.tip`). The sentence used to sit under the numbers card,
    /// below six cells of facts; it is the page's story, so it comes straight after the
    /// word it explains.
    private func verdict(_ turn: TurnRecord, slice: TurnSlice) -> some View {
        let kind = TurnOutcomeKind(turn.outcome)
        let ink = turn.clean ? DesignTokens.Clean.jibe : TurnOutcomeStyle.color(kind)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(TurnCoach.verdictWord(turn))
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(ink)
                Image(systemName: turn.clean ? DesignTokens.Glyph.cleanJibe : kind.symbolName)
                    .font(.title2)
                    .foregroundStyle(ink)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Text(TurnCoach.line(turn: turn, slice: slice, pumpStrokes: pumpStrokes,
                                quietS: detail.analysis.config.turnCleanQuietS))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
            let lead = Int(pads.beforeS)
            let run = Int(pads.afterS)
            // Built in two locals: one `+` chain long enough to carry the whole paragraph
            // is what the type checker gives up on inside a ViewBuilder.
            let drawn = AppShellCopy.fill(AppShellCopy.TurnPage.footDrawn,
                                          ["before": String(lead), "after": String(run)])
            let ticks = " " + AppShellCopy.TurnPage.footTicks + " " + Copy.pathNumbers + "\n\n"
                + AppShellCopy.TurnPage.footRamp + " " + Copy.northAndWind
            Text(drawn + ticks)
            Text(AppShellCopy.TurnPage.footTap)
            // "Score is…" and the paragraph on the manoeuvre channel and the Doppler speed
            // went to the help (UX review #9, 27 Sep 2026): the page prints "held 87 %",
            // never "score", and which speed channel the verdict was scored on is a
            // mechanic for the interested rider, one tap away. The channel fact's home is
            // docs/presentation/turn-detail.md, "The strip".
            TurnHelpLink()
            // The windows are read off this analysis' own config echo, not `TurnConfig()`:
            // on a dev build with tuning on, the defaults are exactly what these are not.
            let windows = TurnDetailStripView.Windows(config: detail.analysis.config)
            let entryBand = AppShellCopy.fill(AppShellCopy.TurnPage.footEntryBand,
                                              ["seconds": String(Int(windows.entryS))]) + " "
            let sweepBand = AppShellCopy.fill(AppShellCopy.TurnPage.footSweepBand,
                                              ["seconds": String(Int(windows.minLagS))]) + " "
            let outcomeBand = Copy.outcomeWindow(seconds: Int(windows.outcomeS))
                + " " + AppShellCopy.TurnPage.footLighterBand
            Text(entryBand + sweepBand + outcomeBand)
            // The quiet tail (engine 0.17.0). Said in the footnote whether or not the strip
            // could fit its rule mark in — at the default 10 s the mark lands past the
            // drawing's own run-out, and this sentence is then the only place the number is.
            if let quiet = detail.analysis.config.turnCleanQuietS, quiet > 0 {
                Text(AppShellCopy.fill(AppShellCopy.TurnPage.footQuiet,
                                       ["seconds": String(Int(quiet))]))
            }
            if turn.axisTs != nil {
                Text(AppShellCopy.TurnPage.footAxis)
            }
            #if TUNING
            Text(thresholdLine)
            #endif
        }
        .font(.caption2)
        .foregroundStyle(.readableSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The `?` onto the clean-jibe topic at the foot of the turn page, with its own sheet so the
/// page owns none.
private struct TurnHelpLink: View {
    @State private var topic: HelpTopicID?

    var body: some View {
        HelpTopicLink(.turnSuccess) { topic = .turnSuccess }
            .sheet(item: $topic) { HelpTopicSheet(id: $0) }
    }
}

/// **"Not how I remember it?"** — the doubt, answered where it arises (UX review #4,
/// 27 Sep 2026), in every channel.
///
/// The beta and dev builds open the send sheet with this session's recording and the turn
/// already named in the note (`SendToDeveloperSheet`, docs/channels.md "Send a session to
/// us", beta). The App Store build has no send sheet and no attachment path, so there the
/// same button opens the ordinary feedback mail with the same first line and no file.
private struct TurnDoubtButton: View {
    let detail: SessionDetail
    let index: Int

    #if BETA
    @State private var sending = false
    #else
    @State private var request = 0
    #endif

    private var note: String? {
        guard let position = TurnDetailSheet.kindPosition(of: index, in: detail) else {
            return nil
        }
        let turn = detail.analysis.turns[index]
        return TurnDoubt.note(kind: position.kind, ordinal: position.ordinal,
                              count: position.count, clock: Fmt.clock(turn.ts),
                              verdict: TurnCoach.verdictWord(turn))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: open) {
                Label(TurnDoubt.button, systemImage: "text.bubble")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            #if BETA
            Text(TurnDoubt.betaHint)
                .font(.caption2)
                .foregroundStyle(.readableSecondary)
                .frame(maxWidth: .infinity)
            #else
            Text(TurnDoubt.releaseHint)
                .font(.caption2)
                .foregroundStyle(.readableSecondary)
                .frame(maxWidth: .infinity)
            #endif
        }
        #if BETA
        .sheet(isPresented: $sending) {
            SendToDeveloperSheet(row: detail.row, detail: detail, prefill: note ?? "")
        }
        #else
        .feedbackMail(on: $request, session: detail.row, note: note)
        #endif
    }

    private func open() {
        #if BETA
        sending = true
        #else
        request += 1
        #endif
    }
}
