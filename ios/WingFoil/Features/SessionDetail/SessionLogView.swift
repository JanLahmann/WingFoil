import SwiftUI
import WingFoilKit

/// **The Log tab: the session's own facts, as opposed to the riding.**
///
/// Ride, Turns and Takeoffs are three readings of what happened on the water. This is the
/// fourth thing a session is — a *record*, with a provenance — and until 6 Sep 2026 the app
/// had nowhere to put that. The gear card was filed under "Effort" because a wing is the
/// other half of what the heart rate cost; the wind the whole analysis is named against was a
/// single grey line under the date; where the file came from was a three-line footer repeated
/// under all four tabs; and the watch-vs-phone comparison was hidden inside a warning banner
/// that most riders dismiss. Four facts about the recording, filed as furniture.
///
/// They are one subject and they are on one tab now, in the order a reader asks them in:
/// what did I ride, what was the wind doing, where did these numbers come from, and where do
/// the two devices disagree.
struct SessionLogView: View {
    let detail: SessionDetail
    let sessionID: String

    @Environment(SessionStore.self) private var store

    var body: some View {
        // Gear first: it is the only block here the rider can *change*, and the only one he
        // came looking for. The rest are the record answering for itself.
        SessionGearCard(sessionID: sessionID)
            .id("gear")
        WindDetailCard(detail: detail)
        FlightEndsCard(detail: detail)
        RecordingCard(detail: detail)
        // Behind Settings → Analysis → "Windsurf (experimental)", and gated here rather than
        // inside the card so the stack does not keep a gap where it used to be. A session
        // already analysed as windsurf keeps that analysis, its badge and its chip with the
        // switch off — only the control that could change it is gone.
        if store.windsurfEnabled {
            DisciplineCard(detail: detail)
        }
        if !detail.divergences.isEmpty {
            DivergenceDetailCard(divergences: detail.divergences)
        }
    }
}

// MARK: - Flight ends

/// **Every loss no turn owns, as a list you can open.**
///
/// The Turns tab has been a list of maneuvers with a page behind every row since it was
/// built. The other half of a session's losses — the gust that died, the ventilation on a
/// reach, the tip that caught — existed only as hollow rings on the map: findable if you
/// happened to tap the right forty metres of water, and invisible otherwise. This is the same
/// list the map draws, in time order, and each row opens the same page the ring does.
///
/// It is on **Log** rather than on Ride or Turns on purpose. Ride is the map, Turns is the
/// maneuvers, and a straight-line flight end is neither: it is what the *record* says happened
/// when the foil stopped carrying, which is the question this tab exists to answer.
private struct FlightEndsCard: View {
    let detail: SessionDetail

    @State private var opened: FlightEndDetailRequest?

    private var indices: [Int] { detail.drawnFlightEndIndices }

    var body: some View {
        if !indices.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("Flight ends").font(.headline)
                    Spacer()
                    Text("\(indices.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(indices, id: \.self) { index in
                        row(index, end: detail.analysis.flightEnds[index])
                        if index != indices.last { Divider() }
                    }
                }
                // The two exclusions, said once, because a rider who counts the rings on the
                // map and the rows here has to be told why the session's own tally is larger.
                Text("Straight-line ends only. "
                     + "An end inside a turn's window belongs to that turn. "
                     + "Find it on the Turns tab. "
                     + "An end the recording cut short has no evidence to judge.")
                    .font(.caption2)
                    .foregroundStyle(.readableSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.10), in: .rect(cornerRadius: 14))
            .id("flight-ends")
            .sheet(item: $opened) { request in
                FlightEndDetailSheet(detail: detail, start: request.id)
                    .task { Usage.record(.flightEndPage) }
            }
            #if DEBUG && targetEnvironment(simulator)
            // `UI_OPEN_FLIGHT_END=<index>` opens one flight end's page, for a picture of it.
            // The same family as `UI_OPEN_TURN`, and the same index: into `flightEnds`.
            .onAppear {
                guard let raw = ProcessInfo.processInfo.environment["UI_OPEN_FLIGHT_END"],
                      let id = Int(raw),
                      detail.analysis.flightEnds.indices.contains(id) else { return }
                opened = FlightEndDetailRequest(id: id)
            }
            #endif
        }
    }

    private func row(_ index: Int, end: FlightEndRecord) -> some View {
        Button {
            opened = FlightEndDetailRequest(id: index)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: TurnOutcomeKind(end.outcome).symbolName)
                    .font(.caption)
                    .foregroundStyle(TurnOutcomeStyle.color(TurnOutcomeKind(end.outcome)))
                    .scaledColumn(16, alignment: .center, relativeTo: .caption)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Flight " + String(end.flightIndex + 1))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text(FlightEndAnalytics.outcomeText(end))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 7)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Wind

/// The wind axis in full, which is the assumption the rest of the page rests on.
///
/// The header's one-line version is the summary ("Wind from WSW 248° · 71 % confident"); this
/// is what that line is short for, and it is here rather than there because it is three facts
/// and a consequence, not a caption. The consequence is the part that matters: below
/// `windMinConfidence` the estimate does not name turns, so a session whose axis is too weak
/// has tacks and jibes it is not allowed to call tacks and jibes — and the reader is entitled
/// to know that is why, rather than wondering where his jibe count went.
private struct WindDetailCard: View {
    let detail: SessionDetail

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if detail.analysis.wind != nil || detail.windDirUserDeg != nil {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("Wind").font(.headline)
                    HelpButton(topic: .windAxis, size: .footnote)
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 6) {
                    if let user = detail.windDirUserDeg {
                        // The rider's own value leads: he set it on the beach, so it is a
                        // statement rather than an inference, and it is what the turn
                        // drawings rotate by when it exists.
                        row("Set on the watch",
                            "\(Fmt.compass(user)) · \(Int(user.rounded()))°",
                            note: "your own value, from the session's wind field")
                    }
                    if let wind = detail.analysis.wind {
                        let confidence = String(Int((wind.confidence * 100).rounded()))
                        let weak = wind.usable ? "" : ". Too weak to name turns"
                        row("Estimated from the track",
                            "\(Fmt.compass(wind.dirDeg)) · \(Int(wind.dirDeg.rounded()))°",
                            note: confidence + " % confident" + weak)
                    }
                }
                Text(consequence)
                    .font(.caption2)
                    .foregroundStyle(.readableSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.10), in: .rect(cornerRadius: 14))
            .id("wind")
        }
    }

    private var consequence: String {
        let usable = detail.analysis.wind?.usable ?? false
        if detail.windDirUserDeg != nil {
            return "Turn drawings are rotated by your own value. Tacks and jibes are named "
                + "against the wind axis, which is why it has to be good enough to trust."
        }
        return usable
            ? "Good enough to name turns, so tacks and jibes are called what they are."
            : "Not good enough to name turns, so the maneuvers stay unnamed rather than "
                + "being guessed at. Setting the wind on the watch fixes it."
    }

    /// Label beside value — until the label alone is wider than the phone, at which point
    /// the pair stacks. A 150 pt title column scaled to an accessibility size leaves the
    /// value nowhere to go, and the value is the half the rider came for.
    @ViewBuilder
    private func row(_ title: String, _ value: String, note: String) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                rowValue(value, note: note)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.subheadline)
                    .scaledColumn(150, relativeTo: .subheadline)
                rowValue(value, note: note)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func rowValue(_ value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.subheadline.weight(.semibold))
            Text(note)
                .font(.caption2)
                .foregroundStyle(.readableSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Recording

/// Where these numbers came from. It was a three-line footer under every tab — the same
/// sentence about source class, the same engine version, the same filename, on all four
/// sections of every session forever. It is one fact about the record, so it is on the tab
/// the record's facts are on, once.
private struct RecordingCard: View {
    let detail: SessionDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Recording").font(.headline)
                HelpButton(topic: .sourceClass, size: .footnote)
                Spacer()
            }
            Text(SessionDisplay.sourceClassNote(detail.row.sourceClass,
                                                importSource: detail.row.importSource))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(provenance)
                if let file = detail.row.originalFilename { Text(file) }
            }
            .font(.caption2)
            .foregroundStyle(.readableSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Rule 3 of Strava's brand guidelines: anything showing data taken from Strava
            // links back to the activity it came from. This is the card that says where the
            // numbers came from, so it is the card the link belongs on — and the id is read
            // back out of the recording's own filename rather than stored in a column of its
            // own (`StravaImport.activityId`).
            if let activity = StravaImport.activityId(
                originalFilename: detail.row.originalFilename) {
                StravaActivityLink(activityID: activity)
                    .padding(.top, 2)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.10), in: .rect(cornerRadius: 14))
        .id("recording")
    }

    private var provenance: String {
        let rate = String(format: "%.1f", detail.analysis.capabilities.sampleRateHz)
        let head = "Engine " + detail.analysis.engineVersion + " · " + rate + " Hz"
        let sport = " · sport " + SessionDisplay.sportLabel(detail.row.sport)
        return head + sport + (detail.row.importSource.map { " · via \($0)" } ?? "")
    }
}

// MARK: - Analyse as

/// **DEV only** (docs/channels.md) — windsurf, and the per-discipline thresholds with it.
/// The card is behind `store.windsurfEnabled`, which is the constant `false` in the release
/// and beta channels, so it is already unreachable there; this note says why.
///
/// **"Analyse as" — the discipline this session is read in** (docs/algorithms/disciplines.md
/// "Disciplines", GitHub issue #6).
///
/// It is on Log, under Recording, and that placement is the feature's first decision. Jan's
/// brief was to *hide it a bit and mark it as experimental*: windsurf analysis has never been
/// checked against a windsurf session with ground truth, so the row belongs where a rider who
/// is looking for it will find it and a rider who is not will never be offered a choice he
/// has no way to evaluate. Log is the tab about the *record* rather than the riding, which is
/// exactly the question this row asks — not "what did you do", but "how should this be read".
///
/// Changing it re-derives **this session and nothing else**: the preset rides in the stored
/// analysis' `engineVersion` (`DisciplineStamp`), which is the staleness key the library has
/// swept on since tuning existed, so there is no second invalidation rule here.
private struct DisciplineCard: View {
    let detail: SessionDetail

    @Environment(SessionStore.self) private var store

    /// What is on screen while the re-analysis runs — the picker moves at once, the numbers
    /// a second later, and a control that snaps back to its old value would read as a bug.
    @State private var pending: Discipline?

    private var current: Discipline { pending ?? detail.row.analysisDiscipline }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Analyse as").font(.headline)
                HelpButton(topic: .windsurf, size: .footnote)
                Spacer()
            }
            Picker("Analyse as", selection: Binding(
                get: { current },
                set: { choice in
                    guard choice != current else { return }
                    pending = choice
                    Task {
                        await store.setDiscipline(choice, for: detail.row)
                        pending = nil
                    }
                })) {
                    ForEach(Discipline.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Analysis discipline")
            Text(DisciplineLexicon.experimentalNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.10), in: .rect(cornerRadius: 14))
        .id("discipline")
    }
}

// MARK: - Divergences

/// The watch-vs-phone table, out from behind the banner's disclosure.
///
/// The banner above the switcher is a one-line warning now and its job is to *say there is
/// one* — the numbers are here, on the tab about the recording, because that is what they
/// are about: not an error the rider has to act on, but a note about where a number came
/// from. The phone's recompute is authoritative (docs/plan.md §5), which is why the advice
/// says so in the rider's own words rather than asking him to choose.
private struct DivergenceDetailCard: View {
    let divergences: [Divergence]

    /// True when the only things that disagree are the takeoff counts — the expected
    /// disagreement, since the watch counts attempts live on a wrist and the phone reads the
    /// whole session back afterwards. It earns a calmer sentence than a speed does.
    private var takeoffOnly: Bool { DivergenceText.isTakeoffOnly(divergences) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Watch vs phone").font(.headline)
                HelpButton(topic: .divergence, size: .footnote)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                Divider()
                ForEach(divergences) { d in
                    HStack(spacing: 10) {
                        Text(DivergenceText.metric(d))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(DivergenceText.watch(d))
                            .scaledColumn(66, alignment: .trailing, relativeTo: .caption)
                        Text(DivergenceText.phone(d))
                            .scaledColumn(66, alignment: .trailing, relativeTo: .caption)
                        Text(DivergenceText.delta(d))
                            .scaledColumn(60, alignment: .trailing, relativeTo: .caption)
                            .foregroundStyle(.orange)
                    }
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    Divider()
                }
            }
            // Four columns of numbers. They scale, and the table stops at
            // `.accessibility2` — past that, metric + watch + phone + Δ is wider than a
            // phone whatever the columns do.
            .denseRowTypeSizeCap()
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
            Text(advice)
                .font(.caption2)
                .foregroundStyle(.readableSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id("divergence")
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Text("metric").frame(maxWidth: .infinity, alignment: .leading)
            Text("watch").scaledColumn(66, alignment: .trailing, relativeTo: .caption)
            Text("phone").scaledColumn(66, alignment: .trailing, relativeTo: .caption)
            Text("Δ").scaledColumn(60, alignment: .trailing, relativeTo: .caption)
        }
        .font(.caption2)
        .foregroundStyle(.readableSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var advice: String {
        let base = "Trust the phone's numbers. It reads the whole session back afterwards. "
            + "The watch has to work these out live on your wrist, as you ride. "
            + "Nothing is wrong with your session."
        guard takeoffOnly else { return base }
        return base + " Takeoff and pump counting is where the two differ most. "
            + "Keep the watch app up to date to narrow the gap."
    }
}
