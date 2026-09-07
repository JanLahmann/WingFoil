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

    var body: some View {
        // Gear first: it is the only block here the rider can *change*, and the only one he
        // came looking for. The rest are the record answering for itself.
        SessionGearCard(sessionID: sessionID)
            .id("gear")
        WindDetailCard(detail: detail)
        FlightEndsCard(detail: detail)
        RecordingCard(detail: detail)
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

    private var indices: [Int] { FlightEndAnalytics.drawnIndices(detail.analysis) }

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
                Text("Straight-line ends only. One inside a turn's window is that turn's, and "
                     + "is on the Turns tab; one the recording cut short has no evidence to "
                     + "judge.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.10), in: .rect(cornerRadius: 14))
            .id("flight-ends")
            .sheet(item: $opened) { request in
                FlightEndDetailSheet(detail: detail, start: request.id)
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
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Flight \(end.flightIndex + 1)")
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
                        row("Estimated from the track",
                            "\(Fmt.compass(wind.dirDeg)) · \(Int(wind.dirDeg.rounded()))°",
                            note: "\(Int((wind.confidence * 100).rounded())) % confident"
                                + (wind.usable ? "" : " — too weak to name turns"))
                    }
                }
                Text(consequence)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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

    private func row(_ title: String, _ value: String, note: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .frame(width: 150, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.subheadline.weight(.semibold))
                Text(note).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
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
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.10), in: .rect(cornerRadius: 14))
        .id("recording")
    }

    private var provenance: String {
        let rate = String(format: "%.1f", detail.analysis.capabilities.sampleRateHz)
        return "Engine \(detail.analysis.engineVersion) · \(rate) Hz · "
            + "sport \(SessionDisplay.sportLabel(detail.row.sport))"
            + (detail.row.importSource.map { " · via \($0)" } ?? "")
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
    private var takeoffOnly: Bool {
        !divergences.isEmpty && divergences.allSatisfy { $0.metric.hasPrefix("Takeoff") }
    }

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
                        Text(d.metric).frame(maxWidth: .infinity, alignment: .leading)
                        Text(d.watch).frame(width: 66, alignment: .trailing)
                        Text(d.phone).frame(width: 66, alignment: .trailing)
                        Text(d.delta).frame(width: 60, alignment: .trailing)
                            .foregroundStyle(.orange)
                    }
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    Divider()
                }
            }
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
            Text(advice)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id("divergence")
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Text("metric").frame(maxWidth: .infinity, alignment: .leading)
            Text("watch").frame(width: 66, alignment: .trailing)
            Text("phone").frame(width: 66, alignment: .trailing)
            Text("Δ").frame(width: 60, alignment: .trailing)
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var advice: String {
        let base = "The phone's numbers are the ones to trust: it reads the whole session "
            + "back afterwards, while the watch has to work these out live on your wrist, "
            + "as you ride. Nothing is wrong with your session."
        guard takeoffOnly else { return base }
        return base + " Takeoff and pump counting is where the two differ most; keeping the "
            + "watch app up to date narrows the gap."
    }
}
