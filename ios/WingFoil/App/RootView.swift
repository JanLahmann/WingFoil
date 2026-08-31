import SwiftUI
import WingFoilKit

/// The four library screens. Sessions is the home tab; Records, Trends and Gear are the
/// aggregate views phase 4 adds on top of the same GRDB tables.
struct RootView: View {
    @Environment(SessionStore.self) private var store
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
