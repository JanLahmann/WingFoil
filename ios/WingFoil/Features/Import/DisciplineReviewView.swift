// "Which rig?" after an import is part of windsurf, which is a DEV door
// (docs/channels.md): release and beta analyse every session as wingfoil and never ask.
#if DEV
import SwiftUI
import WingFoilKit

/// **"Analysed as Wingfoil — is that right?"**, asked once, on the way out of an import
/// (docs/presentation/labels.md, "Confirming the discipline on import").
///
/// Wingfoil is not a sport in Garmin, Strava, intervals.icu or Apple Health. Every recording
/// but the CleanJibe watch app's own therefore arrives saying nothing about the rig — or
/// saying *windsurfing*, which is the profile ADR-004 files a wingfoil afternoon under. So the
/// import reads the session under the rider's declared default, marks that nobody said so, and
/// this sheet is where he agrees or corrects.
///
/// **After the import, not before it.** The rider prompt next door asks its question first,
/// because attribution decides whether a session may touch Records and Health and a wrong
/// answer there cannot be taken back. This one is the opposite: every number is re-derived
/// from the archived recording the moment the preset moves, so the safe order is to import,
/// show the result, and offer to change it — which is also the only order a two-hundred-file
/// ZIP can survive.
struct DisciplineReviewView: View {
    let request: SessionStore.DisciplineReviewRequest

    @Environment(SessionStore.self) private var store

    /// The rows as they stand now, not as they stood when the sheet opened: changing one
    /// re-derives that session, and the picker has to show what it re-derived to.
    private var rows: [SessionRow] {
        request.sessionIDs.compactMap { store.session(id: $0) }
    }

    private var allOne: Discipline? {
        let presets = Set(rows.map(\.analysisDiscipline))
        return presets.count == 1 ? presets.first : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                // First, above the list, because it is the control that saves the most work
                // and a rider who has just imported a season should not have to scroll past
                // forty rows to find it. Offered only where it saves something: with one
                // session on the list it is the same control twice, and the row's own picker
                // is the one with the date beside it.
                if rows.count > 1 {
                    Section {
                        ForEach(Discipline.allCases, id: \.self) { choice in
                            Button {
                                Task { await store.applyDisciplineToAllInReview(choice) }
                            } label: {
                                HStack {
                                    Text("All " + String(rows.count) + " as " + choice.title)
                                    Spacer()
                                    if allOne == choice {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .disabled(store.isBusy)
                        }
                    } header: {
                        Text("Apply to all")
                    }
                }

                Section {
                    ForEach(rows, id: \.id) { row in
                        sessionRow(row)
                    }
                } header: {
                    Text(rows.count == 1 ? "1 new session" : "\(rows.count) new sessions")
                } footer: {
                    Text(DisciplineReview.footnote)
                }
            }
            // Three words, because the bar also carries "Not now" and "Confirm" — and it is
            // the question, in the words the presets are named in.
            .navigationTitle("Which rig?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Skipping keeps every guess and loses nothing: the sessions stay in the
                    // library, analysed, with a `?` on the badge until somebody says.
                    Button("Not now") { store.dismissDisciplineReview() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { Task { await store.confirmDisciplineReview() } }
                }
            }
        }
        .presentationDetents(rows.count > 2 ? [.large] : [.medium, .large])
    }

    @ViewBuilder
    private func sessionRow(_ row: SessionRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(SessionDisplay.title(row))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(subtitle(row))
                .font(.caption)
                .foregroundStyle(.secondary)
            // The sport code, said out loud and never acted on. Without this line the app
            // looks wrong on exactly the sessions a rider is most likely to query — his watch
            // says windsurfing and CleanJibe says Wingfoil, and the disagreement is silent.
            if let hint = DisciplineReview.sportHint(row.sport) {
                Label(hint, systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("Analyse as", selection: Binding(
                get: { row.analysisDiscipline },
                set: { choice in
                    Task { await store.setReviewDiscipline(choice, for: row) }
                })) {
                    ForEach(Discipline.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(store.isBusy)
        }
        .padding(.vertical, 4)
    }

    /// "Sun 30 Aug, 14:07 · Nago Torbole · via icu" — the three things that tell one session
    /// in a batch of forty from another.
    private func subtitle(_ row: SessionRow) -> String {
        var parts = [Fmt.date(row.startDate, zone: row.displayZone)]
        if let spot = store.spot(id: row.spotId)?.name { parts.append(spot) }
        if let source = row.importSource { parts.append("via \(source)") }
        return parts.joined(separator: " · ")
    }
}

#endif
