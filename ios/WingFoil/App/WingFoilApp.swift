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
        // The one field-failure signal the app has, and the only one that keeps the
        // no-servers stance: iOS hands over its own crash and hang diagnostics, on device,
        // and the feedback mail carries them (docs/engineering.md, "Monitoring"). Every
        // channel, because the App Store one is the channel with no other route.
        CrashDiagnostics.shared.subscribe()
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
                    // Last, and after the spots have their names: the watch's map snapshot
                    // (docs/watch-map-snapshot.md). A no-op unless the top two spots or the
                    // chosen watch have actually changed since the last successful push.
                    await store.refreshWatchMapIfNeeded()
                }
                // The watch's session cards, for as long as the app is alive. A separate
                // task from the load above because it never finishes: it is a stream, not
                // a step, and it must not delay the library appearing.
                //
                // DEV only, with the rest of the Garmin link (docs/channels.md).
                #if DEV
                .task { await store.watchForCompanionCards() }
                // And the recording behind the card, when the watch sends it straight over
                // (docs/transfer-format.md). A separate task because it is a sweep and not a
                // stream: the pages arrive through the same link, and this only picks up
                // what they became.
                .task { await store.watchForDirectTransfers() }
                #endif
                // The Apple Watch recorder's own link. A separate WCSession delegate from
                // the Garmin one above and unrelated to it: this one receives whole
                // recordings over WatchConnectivity, that one receives summary cards through
                // Garmin Connect Mobile.
                .task { await store.watchForAppleWatchSessions() }
                // And the third watch story: a workout somebody else's app — Apple's own —
                // wrote into Health. Opt-in, so this returns immediately on every install
                // that has not asked for it. It registers the HealthKit observer and sweeps
                // once; the sweep is the half that always works (ADR-017).
                //
                // BETA only: the release channel has no HealthKit entitlement to observe
                // with (docs/channels.md).
                #if BETA
                .task { await store.watchHealthForNewWorkouts() }
                #endif
                // The second cloud source (ADR-023). Reads the stored tokens so the Import
                // and Settings screens know the connection state before anybody taps, then
                // — only if the rider asked for automatic pickup — looks for new activities.
                .task {
                    store.refreshStravaConnection()
                    await store.checkStravaForNewActivities()
                }
                // Two kinds of URL land here: Garmin Connect returning the watch the rider
                // picked, and the share sheet handing us a recording. The companion link
                // answers only on its own scheme, so it gets first refusal — and only in the
                // dev channel, which is the only one that ever sent the rider to Garmin
                // Connect in the first place (docs/channels.md).
                .onOpenURL { url in
                    #if DEV
                    guard !store.handleCompanionURL(url) else { return }
                    #endif
                    Task { await store.importPicked(urls: [url]) }
                }
                // A background wake may have imported a session while the app was away —
                // the library in memory would otherwise be one session behind until the
                // next launch. Silent and free on every ordinary foreground.
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await store.absorbBackgroundImports()
                        // The reliable half of the automatic Health pickup: the rider has
                        // just finished a workout and opened the app, which is the moment
                        // iOS's own background delivery is least likely to have run yet.
                        // BETA only (docs/channels.md).
                        #if BETA
                        await store.checkHealthForNewWorkouts()
                        #endif
                        // …and the same reasoning for Strava: the rider's watch has just
                        // finished uploading, and opening the app is when he expects to see
                        // the session. Returns at once unless he switched the pickup on.
                        await store.checkStravaForNewActivities()
                    }
                }
        }
    }
}
