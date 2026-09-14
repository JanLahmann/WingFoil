import SwiftUI
import WingFoilKit

/// The four library screens. Sessions is the home tab; Records, Trends and Gear are the
/// aggregate views phase 4 adds on top of the same GRDB tables.
struct RootView: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection = Tab.sessions
    /// The brand screen the launch screen hands over to (`SplashView`). Initialised here and
    /// never set back to `true`, which is exactly the rule: `RootView` is built once per
    /// process, so "the splash is up" and "this is a cold start" are the same fact. A return
    /// from the background rebuilds nothing and therefore shows nothing.
    @State private var isShowingSplash = Splash.isWanted

    enum Tab: String, Hashable {
        case sessions, records, trends, gear
    }

    /// Split into "the tabs", "the things the app puts on top of them" and "the moments that
    /// decide whether to". One expression carrying all three overflowed the type checker
    /// outright once the deleted-sessions sheet joined the other two presentations — and
    /// three named groups are what the comments were already describing anyway.
    var body: some View {
        hooks(presentations(tabs))
            // In front of everything, including the splash: a library this build cannot
            // read is not a state the four tabs have an honest picture of, and the one
            // screen that explains it is the whole of the app until it is resolved
            // (docs/channels.md, "Switching channels").
            .overlay { splash }
            .overlay {
                if let refusal = store.libraryNewerThanApp {
                    LibraryNewerThanAppView(refusal: refusal)
                        .transition(.opacity)
                }
            }
            // The other library state nothing behind it has an honest picture of: a
            // "Start over" that wiped everything and then could not reopen the file it
            // wiped. Beta and dev only, because the door that produces it is
            // (docs/channels.md), and never seen on an ordinary run.
            #if BETA || DEBUG
            .overlay {
                if store.startOverNeedsRelaunch {
                    StartOverRelaunchView()
                        .transition(.opacity)
                }
            }
            #endif
    }

    /// The launch screen, continued — in front of the tabs rather than instead of them, so
    /// the library goes on loading underneath and the hold is spent on work rather than on
    /// waiting. See `SplashView` for what "the same picture" means and `Splash` for the
    /// numbers both screens obey.
    @ViewBuilder private var splash: some View {
        if isShowingSplash {
            SplashView(onFinished: dismissSplash)
                .transition(.opacity)
        }
    }

    /// A 0.4 s crossfade into the Sessions list — or, under Reduce Motion, a cut after the
    /// same hold. The animation lives here rather than in the splash because the thing being
    /// faded *to* is the thing this view owns.
    private func dismissSplash() {
        guard !reduceMotion else {
            isShowingSplash = false
            return
        }
        withAnimation(.easeInOut(duration: Splash.crossfade)) { isShowingSplash = false }
    }

    private var tabs: some View {
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
    }

    // MARK: - The three questions the app owns

    /// Everything the app itself puts on screen, as opposed to what a tab does: whose session
    /// is this, shall I notify you, did you mean to un-delete those — and the welcome screen.
    /// All four live here rather than in a tab because none of them belongs to one, and they
    /// all go through the store's single "is anything else up?" predicate, so they can never
    /// stack on each other.
    private func presentations(_ content: some View) -> some View {
        content
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
            Text("When a new Garmin activity syncs, CleanJibe can let you know — "
                 + "even in the background.")
        }
        // "You have pulled twice in ten seconds and the sessions you deleted are still not
        // here — did you mean to get any of them back?". The third question the app owns,
        // raised here beside the other two and going through the same "is anything else up?"
        // predicate, so it can never stack on the rider prompt or the notification offer.
        //
        // A sheet rather than an alert, and this is the one of the three that could not be an
        // alert: the answer is a *selection* over several afternoons, not a yes/no — see
        // `ReAddDeletedSheet`. It only ever appears after a deliberate immediate second pull,
        // because the default answer is the one the rider already gave by deleting.
        .sheet(item: Binding(get: { store.pendingReAdd },
                             set: { if $0 == nil { store.declineReAdd() } })) { offer in
            ReAddDeletedSheet(offer: offer)
        }
        // "Analysed as Wingfoil — is that right?". The fourth question the app owns, and the
        // only one asked *after* the work rather than before it: wingfoil is not a sport in
        // Garmin, Strava, intervals.icu or Apple Health, so every import that is not the
        // CleanJibe watch app's own is a guess the rider gets to correct. Here rather than on
        // the Import screen for the same reason the rider prompt is: an import also arrives by
        // itself, from a sync or a file tapped in another app. It goes through the store's
        // same "is anything else up?" predicate, so it can never stack on the other three —
        // and an automatic pickup never raises it at all, it only leaves the library's banner.
        //
        // DEV only (docs/channels.md): "Which rig?" belongs to windsurf, and a channel with
        // no windsurf switch analyses every session as wingfoil and has nothing to ask. The
        // store agrees from the other side — `disciplineToReview` is empty without the
        // switch — so this is the sheet, not the question, that the flag removes.
        #if DEV
        .sheet(item: Binding(get: { store.disciplineReview },
                             set: { if $0 == nil { store.dismissDisciplineReview() } })) {
            DisciplineReviewView(request: $0)
        }
        #endif
        // The first thing a first launch shows, in front of the setup card the library
        // would otherwise open on. A cover rather than a sheet: it is one screen with three
        // answers on it and nothing behind it worth peeking at, and a half-swipe that
        // reveals an empty list is not a fourth answer. Raised here for the same reason the
        // two prompts above are — it belongs to the app, not to any one tab — and it goes
        // through the same "is anything else up?" predicate, so it can never stack.
        //
        // `&& !isShowingSplash` is the one thing the splash asks of the rest of the app: on a
        // genuine first run both want the screen in the same second, and a cover raised over
        // the brand screen would cut the hold in half. The welcome is not *cancelled* by the
        // wait — the store still thinks it is showing, and the cover goes up the moment the
        // splash crossfades out.
        .fullScreenCover(isPresented: Binding(get: { store.isShowingWelcome && !isShowingSplash },
                                              set: { if !$0 { store.dismissWelcome() } })) {
            WelcomeView(
                onTryExample: {
                    store.dismissWelcome()
                    Task { await store.loadExampleSessionAndOpen() }
                },
                // Straight into the ordinary first run: the library is empty and no key is
                // stored, so `IcuSetupCard` is already the thing underneath. Nothing to do
                // but get out of its way.
                onConnect: { store.dismissWelcome() },
                onLater: { store.dismissWelcome() })
        }
    }

    // MARK: - When to ask them

    /// Every moment at which one of the answers above can change. Each is the *same* question
    /// asked again after a "not yet": the predicates say no while another modal is up and the
    /// store only spends an offer when it actually appears, so the deferrals cost nothing.
    private func hooks(_ content: some View) -> some View {
        content
        // A tapped "new session" notification names a session, and sessions live on the
        // first tab. The library does the pushing; this only makes sure the tab it pushes
        // onto is the one on screen.
        .onChange(of: store.pendingSessionID) { _, pending in
            if pending != nil { selection = .sessions }
        }
        .task {
            // One per launch, not per return from the background: `RootView` is built once
            // per process, which is exactly what "the app was opened" means here.
            Usage.record(.appOpen)
            store.showWelcomeIfNeeded()
            store.askAboutNewActivitiesIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.askAboutNewActivitiesIfNeeded() }
        }
        // The library arriving is what settles whether this install has a history, and it
        // lands *after* the `task` above — `SessionStore.load` is asynchronous, and the
        // first read of an empty list means "not read yet", not "no sessions". So the real
        // decision happens here, on the generation counter, which is bumped by every load
        // including the one that finds nothing.
        .onChange(of: store.libraryGeneration) { _, _ in store.showWelcomeIfNeeded() }
        // …and the moment whatever was in the way goes away — the same two hooks the
        // notification offer waits on, for the same reason. Both halves are re-asked: the
        // first run because a deferral is not a refusal, and the Settings replay because
        // the sheet it was tapped in has to finish closing first.
        .onChange(of: store.isPresentingSheet) { _, _ in
            store.showWelcomeIfNeeded()
            store.raiseRequestedWelcome()
        }
        .onChange(of: store.pendingImport?.id) { _, _ in
            store.showWelcomeIfNeeded()
            store.raiseRequestedWelcome()
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
        // `UI_START_OVER=1` — the other half of `UI_RESET=1`, and the half that proves the
        // rider-facing door rather than the screenshot one. `UI_RESET` wipes before the
        // store exists; this runs the in-process reset a tap on Settings → Beta → Start
        // over runs, so what a screenshot catches afterwards is the real result of the
        // real button. It waits for the first library read, because a wipe racing the load
        // that is still opening the file it is deleting proves nothing.
        .task {
            guard ProcessInfo.processInfo.environment["UI_START_OVER"] == "1" else { return }
            for _ in 0..<100 where !store.hasLoadedLibrary {
                try? await Task.sleep(for: .milliseconds(100))
            }
            await store.startOver()
        }
        #endif
    }
}
