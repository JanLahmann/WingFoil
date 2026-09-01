import SwiftUI
import WingFoilKit

struct SettingsView: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var confirmReanalyze = false
    @State private var setupTopic: HelpTopicID?

    var body: some View {
        NavigationStack {
            Form {
                helpSection
                icuSection
                deletedSessionsSection
                notificationsSection
                WatchLinkSection()
                analysisSection
                healthSection
                storageSection
                #if DEBUG
                debugSection
                #endif
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await store.refreshStorage() }
            .sheet(item: $setupTopic) { HelpTopicSheet(id: $0) }
            .confirmationDialog("Re-run analysis for all sessions?",
                                isPresented: $confirmReanalyze, titleVisibility: .visible) {
                Button("Re-analyze \(store.sessions.count) sessions") {
                    Task { await store.rerunAnalysis() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Cached analysis.json files are dropped and recomputed from the archived "
                     + "FITs. Original recordings are never touched.")
            }
        }
    }

    // MARK: - Sections

    /// The two "what is this?" answers, in the order a reader needs them: what the app is
    /// for, then what its numbers mean.
    ///
    /// The welcome screen lives here rather than in the Help catalogue because the
    /// catalogue is a *glossary* — one topic per metric, deep-linked from the `?` on the
    /// card that shows it — and "what does this app do" is not a metric. It is also the
    /// only row in Help or Settings that is a whole screen rather than a page of prose.
    private var helpSection: some View {
        Section {
            Button {
                // Asked for, not re-armed: `replayWelcome` deliberately leaves the
                // first-run flag alone. Settings has to get out of the way first, so the
                // screen is *requested* here and raised by `RootView` once this sheet is
                // gone — the same etiquette every other app-owned presentation keeps.
                dismiss()
                store.replayWelcome()
            } label: {
                Label("What CleanJibe does", systemImage: "hand.wave")
            }
            NavigationLink {
                HelpIndexPage()
            } label: {
                Label("What the numbers mean", systemImage: "questionmark.circle")
            }
        } footer: {
            Text("The welcome screen again — what the app measures, and the example "
                 + "session. Then plain-language explanations of every metric: foil %, the "
                 + "GP3S record set, turn outcomes, takeoff attempts, the wind axis and "
                 + "what an uncertified record means.")
        }
    }

    private var icuSection: some View {
        Section {
            // Typing the key and proving it works is one action, and it is the same view
            // the first-run setup card embeds — one storage path, one verdict wording.
            IcuKeyEntry()
                .padding(.vertical, 4)
            Button {
                Task { await store.syncFromIntervals() }
            } label: {
                HStack {
                    Text("Sync now")
                    if store.isBusy { Spacer(); ProgressView().controlSize(.small) }
                }
            }
            .disabled(store.isBusy || store.apiKey.isEmpty)
            if let last = store.lastSyncDate {
                // `.current` deliberately: this is when *you* last synced, on your own clock —
                // the one date on this screen that is not about any session.
                LabeledContent("Last sync", value: Fmt.date(last, zone: .current))
            }
            Button { setupTopic = .icuSetup } label: {
                Label("How to get a key (4 steps)", systemImage: "list.number")
            }
            Button { setupTopic = .icuTroubleshooting } label: {
                Label("Sync not working?", systemImage: "wrench.and.screwdriver")
            }
        } header: {
            Text("intervals.icu")
        } footer: {
            Text("Downloads the original FIT of every windsurf, wing, kite, surf and SUP "
                 + "activity in your intervals.icu account, going two years back. "
                 + "Activities already in the library are never downloaded again.")
        }
    }

    /// The quiet way out of a deletion, and the only place the tombstones
    /// (`SessionTombstoneRow`) are ever visible.
    ///
    /// It is right under the sync section because that is the only thing they affect: a
    /// deleted session is skipped by intervals.icu and by nothing else — a FIT the rider
    /// picks by hand always imports, whatever he deleted before.
    ///
    /// Absent when there is nothing deleted, which is almost every install. A permanent row
    /// reading "Previously deleted: 0" would be a feature announcing itself to people who
    /// have never used it, on a screen that is already eight sections long.
    @ViewBuilder
    private var deletedSessionsSection: some View {
        if store.deletedSessionCount > 0 {
            Section {
                LabeledContent("Previously deleted",
                               value: "\(store.deletedSessionCount)")
                Button("Restore all") {
                    Task { await store.restoreAllDeletedSessions() }
                }
                .disabled(store.isBusy || store.apiKey.isEmpty)
            } header: {
                Text("Deleted sessions")
            } footer: {
                Text("Sessions you deleted stay deleted: syncing intervals.icu — by hand or "
                     + "in the background — leaves them alone rather than downloading them "
                     + "again. Restoring forgets that, and the next sync brings back every "
                     + "one of them that is still on intervals.icu.")
            }
        }
    }

    /// Off by default, and the toggle itself is what asks iOS for permission — a launch
    /// that opens with a notification prompt before the rider has seen a single session is
    /// a prompt he says no to.
    ///
    /// The footer is honest about the one thing that decides whether this works at all:
    /// background refresh is granted by iOS, not requested by us. A wake half an hour after
    /// the upload is the good case, and there is no bad case worth hiding — pull-to-refresh
    /// on the Sessions list is still the way to get a session *now*.
    private var notificationsSection: some View {
        Section {
            Toggle("Notify on new Garmin activities", isOn: Binding(
                get: { store.notifyOnNewActivities },
                set: { store.notifyOnNewActivities = $0 }))
                .disabled(store.apiKey.isEmpty)
        } header: {
            Text("Notifications")
        } footer: {
            Text(store.apiKey.isEmpty
                 ? "Add your intervals.icu API key above first — the check is a call to "
                   + "your account."
                 : "While the phone is idle, CleanJibe asks intervals.icu whether a new "
                   + "windsurf, wing, kite, surf or SUP activity has arrived, and tells you "
                   + "about the ones that are not in your library yet. The session is "
                   + "downloaded and analysed in the background where there is time for it, "
                   + "so tapping the notification usually opens a finished analysis.\n\n"
                   + "iOS decides when a background app may run: it learns your habits and "
                   + "may hold a check back for hours, and it never runs at all while "
                   + "Background App Refresh is off (Settings → General → Background App "
                   + "Refresh) or in Low Power Mode. Pull down on Sessions to sync now.")
        }
    }

    // The "Places → Spots" section used to sit here, and that was the whole problem
    // (app-ui-review.md §6.1): reaching it meant the gear icon, then scrolling past the
    // help rows, the intervals.icu key field, the sync section and the watch section — for
    // a dimension that is a top-level filter chip on *both* Records and Trends. It now has
    // two first-class homes, both of them where the rider already is: a section at the top
    // of the Gear tab, which is the tab that owns named things sessions reference, and a
    // "Manage spots…" row inside the spot filter menu itself, so the chip that filters by
    // spot is the chip that manages them.

    /// The one engine parameter the rider owns (docs/algorithms.md "Default turn type").
    ///
    /// The wind axis is a line, so which end of it the wind blows from is a coin flip until
    /// something breaks the tie. The no-go zone usually does; where it cannot, "I mostly
    /// jibe" does, because flipping the wind 180° swaps every jibe and tack. The footer says
    /// exactly that, in the rider's words rather than the estimator's.
    private var analysisSection: some View {
        Section {
            Picker("Most of my turns are", selection: Binding(
                get: { store.defaultTurnType },
                set: { newValue in
                    guard newValue != store.defaultTurnType else { return }
                    store.defaultTurnType = newValue
                    // Stored analyses are not stale by engine version, so only an explicit
                    // re-run applies this to sessions already in the library.
                    if !store.sessions.isEmpty { confirmReanalyze = true }
                })) {
                ForEach(DefaultTurnType.allCases, id: \.self) { type in
                    Text(type.label).tag(type)
                }
            }
        } header: {
            Text("Analysis")
        } footer: {
            Text("The wind axis comes out of your track as a *line* — which end of it the "
                 + "wind blew from is the hard half. Usually the no-go zone settles it: you "
                 + "can sail any downwind course but none straight into the wind. When a "
                 + "session cannot settle it that way, your habit does, because flipping "
                 + "the wind end for end turns every jibe into a tack. Sessions already in "
                 + "the library only change if you re-run the analysis.")
        }
    }

    private var healthSection: some View {
        Section {
            Toggle("Add sessions to Apple Health", isOn: Binding(
                get: { store.healthWriteEnabled },
                set: { store.healthWriteEnabled = $0 }))
        } header: {
            Text("Apple Health")
        } footer: {
            Text("Off by default. Each session is written as a **Surfing** workout — the "
                 + "closest type Apple Health offers, since it has no wingfoil or windsurf "
                 + "activity — carrying the discipline, foil share, flights and best 2 s in "
                 + "its metadata. CleanJibe never reads health data.")
        }
    }

    private var storageSection: some View {
        Section("Storage") {
            LabeledContent("Sessions", value: "\(store.storage.sessionCount)")
            LabeledContent("FIT archive", value: Fmt.bytes(store.storage.archiveBytes))
            LabeledContent("Database", value: Fmt.bytes(store.storage.databaseBytes))
            Button("Re-run analysis") { confirmReanalyze = true }
                .disabled(store.isBusy || store.sessions.isEmpty)
        }
    }

    #if DEBUG
    @ViewBuilder
    private var debugSection: some View {
        if store.fixturesAvailable {
            Section {
                Button("Import fixtures") { Task { await store.importFixtures() } }
                    .disabled(store.isBusy)
            } header: {
                Text("Debug")
            } footer: {
                Text("Simulator only: ingests every .fit under \(SessionStore.fixturesPath).")
            }
        }
    }
    #endif

    private var aboutSection: some View {
        Section {
            LabeledContent("App", value: Self.appVersion)
            LabeledContent("Analysis engine", value: AnalysisEngine.version)
        } header: {
            Text("About")
        } footer: {
            Text("Wind data by Open-Meteo.com, CC BY 4.0.")
        }
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }
}
