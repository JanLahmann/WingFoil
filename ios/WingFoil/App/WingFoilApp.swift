import SwiftUI

@main
struct WingFoilApp: App {
    @State private var store: SessionStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        // `UI_RESET=1` (simulator only) has to run before the store reads the keychain.
        SessionStore.resetIfRequested()
        #endif
        let store = SessionStore()
        _store = State(initialValue: store)
        // Both halves of the background wake have to be in place before launch finishes:
        // BGTaskScheduler throws at launch over an unregistered permitted identifier, and
        // a cold start *from* a notification delivers the tap to the delegate immediately.
        ActivityNotifier.shared.register(store: store)
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
                // The watch's session cards, for as long as the app is alive. A separate
                // task from the load above because it never finishes: it is a stream, not
                // a step, and it must not delay the library appearing.
                .task { await store.watchForCompanionCards() }
                // The Apple Watch recorder's own link. A separate WCSession delegate from
                // the Garmin one above and unrelated to it: this one receives whole
                // recordings over WatchConnectivity, that one receives summary cards through
                // Garmin Connect Mobile.
                .task { await store.watchForAppleWatchSessions() }
                // Two kinds of URL land here: Garmin Connect returning the watch the rider
                // picked, and the share sheet handing us a FIT or a ZIP. The companion
                // link answers only on its own scheme, so it gets first refusal.
                .onOpenURL { url in
                    guard !store.handleCompanionURL(url) else { return }
                    Task { await store.importPicked(urls: [url]) }
                }
                // A background wake may have imported a session while the app was away —
                // the library in memory would otherwise be one session behind until the
                // next launch. Silent and free on every ordinary foreground.
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await store.absorbBackgroundImports() }
                }
        }
    }
}
