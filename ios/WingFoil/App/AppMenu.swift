import SwiftUI
import WingFoilKit

/// **The app's one menu, on every tab, in the same place** (docs/review-checklist.md,
/// pattern M).
///
/// It lived in `LibraryView`'s toolbar and nowhere else, so *What CleanJibe does*,
/// *Getting started*, *Settings*, *Help* and *Support & ideas* were doors a rider could only
/// reach from the Sessions tab. App-wide furniture is not one
/// tab's property: a rider reading Trends who wants to know what a number means should not
/// have to remember which tab keeps the reference.
///
/// One `View`, four call sites. `AppMenuButton` is the menu itself, used by all four tab
/// roots through `ToolbarItem(placement: .topBarLeading)`; `appMenuHost()` is the plumbing
/// the three aggregate tabs need with it (the sheet it opens, the composer it raises, the
/// actions Help hands back). The Sessions tab owns a richer version of that plumbing
/// already — it has the importer, the filter's date editor and the screenshot hooks on the
/// same binding — so it takes the button and keeps its own host.
///
/// The rows are the kit's (`AppMenuRow`): one order, one wording, and a test that holds
/// them.
struct AppMenuButton: View {
    /// The one sheet the owning screen presents. Writing this property is how every row
    /// opens what it opens — see `LibraryView.sheet` for why one property and not five.
    @Binding var sheet: LibrarySheet?
    /// Bumped by *Support & ideas*; a `feedbackMail(on:)` on the owning screen does the rest.
    @Binding var supportRequest: Int

    @Environment(SessionStore.self) private var store

    var body: some View {
        Menu {
            ForEach(AppMenuRow.ordered) { row in
                if row.opensAfterDivider { Divider() }
                Button { tap(row) } label: {
                    // The beta row names where the rider is in the beta and the dev build
                    // ("You are in the beta"), and asks him in everywhere else.
                    Label(row.title(in: AppChannel.channel), systemImage: row.symbolName)
                }
            }
            Divider()
            Text(Self.buildLine)
        } label: {
            Label("Menu", systemImage: "line.3.horizontal")
        }
    }

    private func tap(_ row: AppMenuRow) {
        switch row {
        // Asked for, not re-armed: the welcome screen again, raised by RootView once the
        // menu is gone (`SessionStore.replayWelcome`).
        case .whatItDoes: store.replayWelcome()
        case .beta: sheet = .beta
        case .gettingStarted: sheet = .helpTopic(.gettingStarted)
        case .settings: sheet = .settings
        case .help: sheet = .help
        case .support: supportRequest += 1
        }
    }

    /// "CleanJibe 0.15.0 (45)", with " · beta" or " · dev" after it — the same string as
    /// Settings → About, and from the same place, so the two never disagree about which
    /// channel this build is (docs/channels.md).
    static var buildLine: String {
        "\(Branding.appName) \(SessionStore.appVersion)" + SettingsView.variantSuffix
    }
}

/// The three aggregate tabs' half of the menu: what its rows open, and the two actions a
/// help topic can hand back. `LibraryView` does all of this itself, with four more cases on
/// the same binding, so it is deliberately not a caller.
private struct AppMenuHost: ViewModifier {
    @Environment(SessionStore.self) private var store
    @State private var sheet: LibrarySheet?
    @State private var supportRequest = 0

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AppMenuButton(sheet: $sheet, supportRequest: $supportRequest)
                }
            }
            .sheet(item: $sheet) { which in
                switch which {
                case .settings: SettingsView()
                case .importer: ImportView()
                case .beta: BetaView()
                case .help: HelpView()
                case .helpTopic(let topic): HelpTopicSheet(id: topic)
                default: EmptyView()
                }
            }
            .feedbackMail(on: $supportRequest)
            // Help's own offers, honoured by the screen that can honour them. Same 400 ms
            // wait as the library's: the second presentation must not arrive while the
            // first is still dismissing, or iOS drops it on the floor.
            .environment(\.openIcuSettings) {
                sheet = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    sheet = .settings
                }
            }
            .environment(\.sendFeedback) {
                sheet = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    supportRequest += 1
                }
            }
            .environment(\.loadExampleSession) {
                sheet = nil
                Task { await store.loadExampleSession() }
            }
            // Getting started → What CleanJibe does: the menu row's own door, raised by
            // RootView once this sheet has finished closing.
            .environment(\.openWelcome) {
                sheet = nil
                store.replayWelcome()
            }
            // The root's own questions must not land on top of a sheet this tab opened.
            .onChange(of: sheet != nil) { _, presenting in
                store.isPresentingSheet = presenting
            }
    }
}

extension View {
    /// The app menu and everything its rows need. For the three aggregate tabs; the
    /// Sessions tab places `AppMenuButton` itself.
    func appMenuHost() -> some View { modifier(AppMenuHost()) }
}
