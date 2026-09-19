import AuthenticationServices
import SwiftUI
import WingFoilKit

/// Import → Strava: the second cloud source beside intervals.icu (docs/decisions.md ADR-023).
///
/// Four states, in the order a first-time reader meets them: a build with no Strava
/// application behind it (which says what is missing rather than failing), an explainer with
/// one Connect button, the activity list, and — once something has actually come in — the
/// automatic-pickup toggle. The look follows the Apple Health screen deliberately: these are
/// the same question asked of two different services, and answering them should feel the same.
struct StravaImportView: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Rows the rider has picked. Empty means "import all new", which is what the toolbar
    /// offers when nothing is selected — the common case is one new afternoon.
    @State private var selection: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                if !store.isStravaConfigured {
                    unconfiguredSection
                } else if !store.isStravaConnected {
                    connectSection
                } else {
                    connectedSection
                    if store.stravaScopeIsNarrow { narrowScopeSection }
                    if store.isReadingStrava && store.stravaCandidates.isEmpty {
                        Section {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Reading Strava…")
                            }
                        }
                    } else if store.stravaCandidates.isEmpty {
                        emptySection
                    } else {
                        activitySection
                        // Always, never "once a session has come in that way"
                        // (pattern E/G): a rider who wants the pickup armed before his
                        // first import is the rider this switch is for.
                        automaticSection
                    }
                    typesSection
                }
                qualitySection
            }
            .navigationTitle("Strava")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    if !importable.isEmpty {
                        Button(selection.isEmpty ? "Import all new"
                                                 : "Import \(selection.count)") {
                            Task { await runImport() }
                        }
                        .disabled(store.isBusy || store.isReadingStrava)
                    }
                }
            }
            .task {
                store.refreshStravaConnection()
                guard store.isStravaConnected, store.stravaCandidates.isEmpty else { return }
                await store.refreshStravaCandidates()
            }
        }
    }

    // MARK: - Sections

    /// The honest answer for a build whose `Strava.xcconfig` was never filled in — a fresh
    /// clone of the repository, most of all. It says what is missing and where it goes,
    /// because a Connect button that always fails is worse than no button.
    private var unconfiguredSection: some View {
        Section {
            Label("No Strava application configured", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        } header: {
            Text("Strava")
        } footer: {
            Text("This build of CleanJibe carries no Strava API keys, so it cannot ask "
                 + "Strava for anything.\n\n"
                 + "If you built it yourself: create an application at "
                 + "strava.com/settings/api and put its client id and secret into "
                 + "`ios/Strava.xcconfig`.\n\n"
                 + "The two lines are shown in `ios/Strava.example.xcconfig`. Everything "
                 + "else on this screen works the moment they are there.")
        }
    }

    private var connectSection: some View {
        Section {
            // Strava's own button artwork, unaltered, and the wording is theirs too:
            // "Connect with Strava" (developers.strava.com/guidelines). See `StravaBrand`
            // for why an app that draws its own version of this risks its application.
            StravaConnectButton {
                Task { await store.connectStrava(anchor: StravaConsent.anchor()) }
            }
            .disabled(store.isReadingStrava)
        } header: {
            Text("Already on Strava?")
        } footer: {
            Text(markdown: "Strava opens and you say yes. CleanJibe can then list your "
                 + "activities and download the GPS track of the ones you pick.\n\n"
                 + "It only reads. It never writes, renames or posts anything to your "
                 + "Strava account.\n\n"
                 + "Strava lets a new app connect a **limited number of riders**. "
                 + "Connecting is refused while CleanJibe is full.\n\n"
                 + Copy.stravaAskForMore)
        }
    }

    private var connectedSection: some View {
        Section {
            LabeledContent("Connected", value: store.stravaAthlete ?? "your Strava account")
            Button {
                Task { await store.refreshStravaCandidates() }
            } label: {
                Label("Look again", systemImage: "arrow.clockwise")
            }
            .disabled(store.isReadingStrava || store.isBusy)
            Button(role: .destructive) {
                Task { await store.disconnectStrava() }
            } label: {
                Label("Disconnect", systemImage: "link.badge.plus")
            }
            .disabled(store.isBusy)
        } header: {
            Text("Strava")
        }
    }

    /// Strava lets a rider untick "private activities" on its own consent screen. The
    /// connection then works and shows fewer sessions than he has, which looks exactly like a
    /// bug — so it is named rather than left to be discovered.
    private var narrowScopeSection: some View {
        Section {
            Label("Private activities are not shared", systemImage: "eye.slash")
                .foregroundStyle(.secondary)
        } footer: {
            Text("When you approved CleanJibe you left out permission to read activities "
                 + "you have marked \"Only you\". Those are missing from the list "
                 + "below.\n\n"
                 + "Disconnect and connect again to change your mind.")
        }
    }

    private var emptySection: some View {
        Section {
            EmptyView()
        } header: {
            Text("Nothing to import")
        } footer: {
            Text(emptyFooter)
        }
    }

    private var activitySection: some View {
        Section {
            ForEach(store.stravaCandidates) { candidate in
                StravaActivityRow(candidate: candidate,
                                  isSelected: selection.contains(candidate.id)) {
                    guard !candidate.isAlreadyImported else { return }
                    if selection.contains(candidate.id) {
                        selection.remove(candidate.id)
                    } else {
                        selection.insert(candidate.id)
                    }
                }
            }
        } header: {
            Text("Activities on Strava")
        } footer: {
            Text("Tap to pick, or use Import all new. " + importableLine
                 + " The rest are already in your library.\n\n"
                 + "Strava answers 200 requests every 15 minutes, and each activity costs "
                 + "one.\n\n"
                 + "A first big import takes its time and may ask you to come back.")
        }
    }

    private var automaticSection: some View {
        Section {
            Toggle("Import new Strava activities automatically", isOn: Binding(
                get: { store.stravaAutoImport },
                set: { store.stravaAutoImport = $0 }))
        } footer: {
            Text("CleanJibe checks Strava when you open the app and imports anything new "
                 + "of the types below.\n\n"
                 + "A session you imported and then deleted is not brought back.")
        }
    }

    private var typesSection: some View {
        Section {
            ForEach(StravaActivityType.allCases) { type in
                Toggle(type.label, isOn: Binding(
                    get: { store.stravaTypes.contains(type) },
                    set: { on in
                        var types = store.stravaTypes
                        if on { types.insert(type) } else { types.remove(type) }
                        store.stravaTypes = types
                        selection = []
                        Task { await store.refreshStravaCandidates() }
                    }))
            }
        } header: {
            Text("Which activities to offer")
        } footer: {
            Text(markdown: "Strava has no wingfoil activity, so pick whichever one you "
                 + "record under.\n\n"
                 + "Sail and Stand-up paddling are off by default, because for most people "
                 + "those buckets hold boats and flat water.\n\n"
                 + "Whatever you choose, an activity whose **name** says wing, foil, kite, "
                 + "surf or SUP is offered too.")
        }
    }

    /// The sentence that has to be read *before* the import, not after the pump section is
    /// found missing. Same limits a GPX has, and the same words.
    private var qualitySection: some View {
        Section {
            EmptyView()
        } header: {
            Text("What a Strava session can show")
        } footer: {
            Text(markdown: "Everything that comes from the track: foil time, flights, "
                 + "every turn with its verdict, the wind axis, the map.\n\n"
                 + "What is missing is what Strava does not hand over. There is no speed "
                 + "channel.\n\n"
                 + "Strava works speed out from the positions, the same way CleanJibe "
                 + "would. Speed records from these sessions are marked "
                 + "**uncertified**.\n\n"
                 + "Nothing records your wrist, so there are no pump strokes and no "
                 + "failed takeoff attempts.\n\n"
                 + "If the same session is also on intervals.icu, import it there "
                 + "instead. That is the original file from your watch, and it "
                 + "certifies.")
        }
    }

    // MARK: - Helpers

    private var importable: [StravaCandidate] {
        store.stravaCandidates.filter { !$0.isAlreadyImported }
    }

    /// "4 of 30 can be imported." Built with `+` and held in one place, so the sentence
    /// in the footer carries no brackets and the footer stays a short chain to type-check.
    private var importableLine: String {
        String(importable.count) + " of " + String(store.stravaCandidates.count)
            + " can be imported."
    }

    /// Nothing on the list, and the two ways out of it: the type switches below, or a
    /// name on Strava that says wing or foil.
    private var emptyFooter: String {
        let opening = "No " + typeList + " activity from the last two years that is not "
            + "already in your library."
        let ways = "\n\nStrava has no wingfoil type. If your sessions are filed under "
            + "something else, switch that type on below."
            + "\n\nOr put \"wing\" or \"foil\" in the activity's name on Strava, and "
            + "CleanJibe finds it whatever type it is."
        return opening + ways
    }

    private var typeList: String {
        let names = StravaActivityType.allCases
            .filter { store.stravaTypes.contains($0) }
            .map(\.label)
        guard !names.isEmpty else { return "matching" }
        guard names.count > 1 else { return names[0] }
        return names.dropLast().joined(separator: ", ") + " or " + names[names.count - 1]
    }

    private func runImport() async {
        let ids = selection.isEmpty ? importable.map(\.id)
                                    : importable.filter { selection.contains($0.id) }.map(\.id)
        selection = []
        await store.importFromStrava(ids)
    }

}

/// One activity, as much as can be said about it before its streams have been fetched: when,
/// how long, how far, and what Strava called it.
private struct StravaActivityRow: View {
    let candidate: StravaCandidate
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(candidate.isAlreadyImported
                                     ? AnyShapeStyle(.secondary)
                                     : AnyShapeStyle(Color.accentColor))
                    .scaledColumn(22, alignment: .center)
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.activity.name ?? "Strava activity")
                        .font(.subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if candidate.isAlreadyImported {
                    Text("In your library")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(candidate.isAlreadyImported)
    }

    /// Drawn on the **rider's** clock, which Strava states exactly (`utc_offset`) — the one
    /// screen in this app where the session's own zone is known before it is imported.
    private var subtitle: String {
        var parts: [String] = []
        if let start = candidate.activity.startDate {
            let zone = candidate.activity.resolvedUtcOffsetS
                .flatMap { TimeZone(secondsFromGMT: $0) } ?? .current
            parts.append(Fmt.date(start, zone: zone))
        }
        if let duration = candidate.activity.durationS {
            parts.append(Fmt.duration(duration))
        }
        if let type = candidate.activity.sportType { parts.append(type) }
        return parts.joined(separator: " · ")
    }

    private var symbol: String {
        if candidate.isAlreadyImported { return "checkmark.circle.fill" }
        return isSelected ? "circle.inset.filled" : "circle"
    }
}
