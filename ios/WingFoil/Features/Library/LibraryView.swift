import SwiftUI
import UniformTypeIdentifiers
import WingFoilKit

struct LibraryView: View {
    @Environment(SessionStore.self) private var store
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var showHelp = false
    @State private var helpTopic: HelpTopicID?
    @State private var path: [String] = []

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
            List {
                if store.sessions.isEmpty {
                    emptyState
                        .id("setup")
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(store.sessions, id: \.id) { row in
                            NavigationLink(value: row.id) { SessionRowView(row: row) }
                        }
                        .onDelete(perform: delete)
                    } footer: {
                        Text("\(store.sessions.count) session"
                             + (store.sessions.count == 1 ? "" : "s")
                             + " · pull to sync intervals.icu")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Sessions")
            .navigationDestination(for: String.self) { SessionDetailView(sessionID: $0) }
            .refreshable { await store.syncFromIntervals() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { showSettings = true } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                        Button { showHelp = true } label: {
                            Label("What the numbers mean", systemImage: "questionmark.circle")
                        }
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showImporter = true } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .disabled(store.isBusy)
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showImporter) { ImportView() }
            .sheet(isPresented: $showHelp) { HelpView() }
            // A named topic opens as itself rather than as "the index, then the topic":
            // one sheet, one animation, and it is what the deep link actually meant.
            .sheet(item: $helpTopic) { HelpTopicSheet(id: $0) }
            // The setup topic offers "Open WingFoil Settings"; only this screen knows how
            // to get there, so it hands the action down rather than Help guessing.
            // Help's example topic offers "Load the example session"; only a screen with
            // the store can honour it, so it is handed down the same way Settings is.
            .environment(\.loadExampleSession) {
                showHelp = false
                Task { await store.loadExampleSession() }
            }
            .environment(\.openIcuSettings) {
                // One sheet at a time: let Help finish dismissing before Settings arrives,
                // or iOS drops the second presentation on the floor.
                showHelp = false
                showImporter = false
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    showSettings = true
                }
            }
            #if DEBUG && targetEnvironment(simulator)
            // Headless-driving hooks: `simctl launch` can't tap, so env vars import the
            // fixture corpus and open a session for automated screenshots.
            // `UI_OPEN_SESSION=latest` takes the newest; any other value is matched
            // against the archived filename (e.g. `UI_OPEN_SESSION=ciq`).
            .task {
                if ProcessInfo.processInfo.environment["UI_IMPORT_FIXTURES"] == "1" {
                    await store.importFixtures()
                }
                // `UI_LOAD_EXAMPLE=1` taps the setup card's example button for us, which
                // is the only way to photograph the loaded state (simctl cannot tap).
                if ProcessInfo.processInfo.environment["UI_LOAD_EXAMPLE"] == "1" {
                    await store.loadExampleSession()
                }
                // `UI_SHEET=help` parks the app on the Help index for a screenshot;
                // `UI_HELP_TOPIC=icuSetup` opens one topic straight away.
                if let raw = ProcessInfo.processInfo.environment["UI_HELP_TOPIC"],
                   let topic = HelpTopicID(rawValue: raw) {
                    helpTopic = topic
                }
                switch ProcessInfo.processInfo.environment["UI_SHEET"] {
                case "help": showHelp = true
                case "settings": showSettings = true
                default: break
                }
                // `UI_SCROLL_TO=setup` parks the (very tall) onboarding card on its
                // bottom edge, which is the only way to photograph the example-session
                // offer that lives under the key field — same hook family as the session
                // detail page's, same reason: simctl cannot scroll.
                if let anchor = ProcessInfo.processInfo.environment["UI_SCROLL_TO"] {
                    try? await Task.sleep(for: .milliseconds(600))
                    withAnimation(.none) { proxy.scrollTo(anchor, anchor: .bottom) }
                }
            }
            .onChange(of: store.sessions.count) {
                guard let wanted = ProcessInfo.processInfo.environment["UI_OPEN_SESSION"],
                      path.isEmpty else { return }
                let match = wanted == "latest"
                    ? store.sessions.first
                    : store.sessions.first { ($0.originalFilename ?? "").contains(wanted) }
                if let match { path = [match.id] }
            }
            #endif
            .safeAreaInset(edge: .bottom) { statusBar }
            .alert("Something went wrong",
                   isPresented: Binding(get: { store.errorMessage != nil },
                                        set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "")
            }
            }
        }
    }

    /// An empty library is either a first run (walk the intervals.icu setup inline) or a
    /// configured one that has nothing yet (say why, if we know why).
    @ViewBuilder
    private var emptyState: some View {
        switch store.onboardingState {
        case .setup, .problem:
            IcuSetupCard(state: store.onboardingState) { showImporter = true }
                .padding(.top, 8)
        case .waiting, .ready:
            ContentUnavailableView {
                Label("No sessions yet", systemImage: "water.waves")
            } description: {
                Text("Import a FIT file or a Garmin export ZIP, or sync your intervals.icu "
                     + "activities. Pull down to sync.")
            } actions: {
                Button("Import…") { showImporter = true }
                    .buttonStyle(.borderedProminent)
                Button("Sync intervals.icu") { Task { await store.syncFromIntervals() } }
            }
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        if store.isBusy || store.status != nil {
            HStack(spacing: 10) {
                if store.isBusy { ProgressView().controlSize(.small) }
                Text(store.status ?? "Working…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func delete(at offsets: IndexSet) {
        let rows = offsets.map { store.sessions[$0] }
        Task { for row in rows { await store.delete(row) } }
    }
}

extension UTType {
    /// FIT has no system-declared type; the Info.plist imports it so files picked from
    /// iCloud Drive/Files resolve here instead of a dynamic `dyn.*` identifier.
    static let fitActivity = UTType(filenameExtension: "fit", conformingTo: .data) ?? .data
}
