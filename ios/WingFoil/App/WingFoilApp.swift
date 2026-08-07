import SwiftUI

@main
struct WingFoilApp: App {
    @State private var store = SessionStore()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(store)
                .task {
                    await store.load()
                    // First launch with a configured key: fill the empty library
                    // without requiring a manual pull-to-refresh.
                    if store.sessions.isEmpty && !store.apiKey.isEmpty {
                        await store.syncFromIntervals()
                    }
                }
                // Share sheet / "Open in WingFoil" hands us a FIT or a ZIP.
                .onOpenURL { url in
                    Task { await store.importPicked(urls: [url]) }
                }
        }
    }
}
