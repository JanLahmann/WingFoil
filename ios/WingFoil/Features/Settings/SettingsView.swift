import SwiftUI
import WingFoilKit

struct SettingsView: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var keyDraft = ""
    @State private var keyLoaded = false
    @State private var confirmReanalyze = false

    var body: some View {
        NavigationStack {
            Form {
                icuSection
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
            .task {
                guard !keyLoaded else { return }
                keyDraft = store.apiKey
                keyLoaded = true
                await store.refreshStorage()
            }
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

    private var icuSection: some View {
        Section {
            SecureField("Personal API key", text: $keyDraft)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .disabled(store.apiKeyIsInjected)
            Button("Save key") { store.setApiKey(keyDraft) }
                .disabled(store.apiKeyIsInjected || keyDraft == store.apiKey)
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
        } header: {
            Text("intervals.icu")
        } footer: {
            if store.apiKeyIsInjected {
                Text("Using the ICU_API_KEY scheme environment variable (DEBUG build).")
            } else {
                Text("intervals.icu → Settings → Developer → API Key. Stored in the "
                     + "keychain and sent as HTTP Basic user \"API_KEY\". Downloads the "
                     + "original FIT of every windsurf/wing activity.")
            }
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
