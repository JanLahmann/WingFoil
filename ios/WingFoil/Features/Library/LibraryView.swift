import SwiftUI
import UniformTypeIdentifiers
import WingFoilKit

struct LibraryView: View {
    @Environment(SessionStore.self) private var store
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var path: [String] = []

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $path) {
            List {
                if store.sessions.isEmpty {
                    emptyState
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
                    Button { showSettings = true } label: {
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
            #if DEBUG && targetEnvironment(simulator)
            // Headless-driving hooks: `simctl launch` can't tap, so env vars import the
            // fixture corpus and open a session for automated screenshots.
            // `UI_OPEN_SESSION=latest` takes the newest; any other value is matched
            // against the archived filename (e.g. `UI_OPEN_SESSION=ciq`).
            .task {
                if ProcessInfo.processInfo.environment["UI_IMPORT_FIXTURES"] == "1" {
                    await store.importFixtures()
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

    private var emptyState: some View {
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
