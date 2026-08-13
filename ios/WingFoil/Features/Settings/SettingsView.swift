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
                WatchLinkSection()
                placesSection
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

    private var helpSection: some View {
        Section {
            NavigationLink {
                HelpIndexPage()
            } label: {
                Label("What the numbers mean", systemImage: "questionmark.circle")
            }
        } footer: {
            Text("Plain-language explanations of every metric — foil %, the GP3S record "
                 + "set, turn outcomes, takeoff attempts, the wind axis and what an "
                 + "uncertified record means.")
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
                LabeledContent("Last sync", value: Fmt.date(last))
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

    private var placesSection: some View {
        Section {
            NavigationLink {
                SpotsView()
            } label: {
                LabeledContent("Spots", value: "\(store.spots.count)")
            }
        } header: {
            Text("Places")
        } footer: {
            Text("Sessions starting within \(Int(SpotClusterer.defaultRadiusM)) m of each "
                 + "other are one spot. Names come from the map when the network allows; "
                 + "rename any of them and it sticks.")
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
                 + "its metadata. WingFoil never reads health data.")
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
            Text("Wind data (coming in phase 2) by Open-Meteo.com, CC BY 4.0.")
        }
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }
}
