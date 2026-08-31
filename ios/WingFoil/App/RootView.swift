import SwiftUI
import WingFoilKit

/// The four library screens. Sessions is the home tab; Records, Trends and Gear are the
/// aggregate views phase 4 adds on top of the same GRDB tables.
struct RootView: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = Tab.sessions

    enum Tab: String, Hashable {
        case sessions, records, trends, gear
    }

    var body: some View {
        TabView(selection: $selection) {
            LibraryView()
                .tag(Tab.sessions)
                .tabItem { Label("Sessions", systemImage: "water.waves") }
            RecordsView()
                .tag(Tab.records)
                .tabItem { Label("Records", systemImage: "trophy") }
            TrendsView()
                .tag(Tab.trends)
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
            // "Gear" rather than "Gear & spots" on the tab item: four tab labels share a
            // 390 pt bar, and the screen's own title carries the longer name. Spots moved
            // in here from the fourth level of the Settings sheet (app-ui-review.md §6.1).
            GearView()
                .tag(Tab.gear)
                .tabItem { Label("Gear", systemImage: "bag") }
        }
        // A tapped "new session" notification names a session, and sessions live on the
        // first tab. The library does the pushing; this only makes sure the tab it pushes
        // onto is the one on screen.
        .onChange(of: store.pendingSessionID) { _, pending in
            if pending != nil { selection = .sessions }
        }
        // "Whose session is this?" — asked here rather than on the Import screen because a
        // FIT also arrives by being tapped in another app (`onOpenURL`), with no screen of
        // ours on top. One presentation, wherever the file came from.
        .sheet(item: Binding(get: { store.pendingImport },
                             set: { if $0 == nil { store.cancelPendingImport() } })) { pending in
            RiderPromptView(pending: pending)
        }
        // The one thing the app ever asks for by itself: "shall I tell you when a session
        // lands?". An alert rather than a sheet — it is one sentence and two answers, and
        // an alert is the one presentation that cannot be mistaken for a screen with more
        // behind it. Raised here, next to the rider prompt, because both are questions the
        // app owns rather than any one tab; the store makes sure only one is ever up.
        //
        // Every hook below is the *same* question asked again after a "not now yet": the
        // predicate says no while another modal is up and the store only spends the offer
        // when the alert actually appears, so the deferrals cost nothing.
        .alert("Get notified of new sessions",
               isPresented: Binding(get: { store.isAskingAboutNewActivities },
                                    set: { if !$0 { store.declineNewActivityNotifications() } })) {
            Button("Enable") { store.acceptNewActivityNotifications() }
            Button("Not now", role: .cancel) { store.declineNewActivityNotifications() }
        } message: {
            Text("When a new Garmin activity syncs, WingFoil can let you know — "
                 + "even in the background.")
        }
        .task { store.askAboutNewActivitiesIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.askAboutNewActivitiesIfNeeded() }
        }
        // The moment setup finishes: a key typed into the first-run card or into Settings,
        // proved against intervals.icu, and the screen behind it now worth notifying about.
        .onChange(of: store.apiKey) { _, _ in store.askAboutNewActivitiesIfNeeded() }
        .onChange(of: store.isCheckingKey) { _, _ in store.askAboutNewActivitiesIfNeeded() }
        // …and the moment whatever was in the way goes away: the Settings sheet the key was
        // typed into, or the import prompt.
        .onChange(of: store.isPresentingSheet) { _, _ in store.askAboutNewActivitiesIfNeeded() }
        .onChange(of: store.pendingImport?.id) { _, _ in store.askAboutNewActivitiesIfNeeded() }
        #if DEBUG && targetEnvironment(simulator)
        // Headless-driving hook (see LibraryView): `simctl launch` cannot tap, so
        // `UI_TAB=records|trends|gear` parks the app on a tab for an automated screenshot.
        .task {
            if let wanted = ProcessInfo.processInfo.environment["UI_TAB"],
               let tab = Tab(rawValue: wanted) {
                selection = tab
            }
        }
        #endif
    }
}
