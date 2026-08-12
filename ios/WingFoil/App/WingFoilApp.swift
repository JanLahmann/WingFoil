import SwiftUI

@main
struct WingFoilApp: App {
    @State private var store: SessionStore

    init() {
        #if DEBUG
        // `UI_RESET=1` (simulator only) has to run before the store reads the keychain.
        SessionStore.resetIfRequested()
        #endif
        _store = State(initialValue: SessionStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                // Owned by the store rather than by the list, so a thumbnail cache built
                // while scrolling survives a tab switch.
                .environment(store.thumbnails)
                .task {
                    await store.load()
                    // First launch with a configured key: fill the empty library
                    // without requiring a manual pull-to-refresh.
                    if store.sessions.isEmpty && !store.apiKey.isEmpty {
                        await store.syncFromIntervals()
                    }
                    // A schema migration or an engine bump leaves every summary row
                    // stale; the aggregate tabs must not read those.
                    await store.refreshDerived()
                    await store.nameSpots()
                }
                // Share sheet / "Open in WingFoil" hands us a FIT or a ZIP.
                .onOpenURL { url in
                    Task { await store.importPicked(urls: [url]) }
                }
        }
    }
}
