import SwiftUI
import UniformTypeIdentifiers
import WingFoilKit

struct LibraryView: View {
    @Environment(SessionStore.self) private var store
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var showHelp = false
    #if !BETA
    /// The release channel's "what is coming" page, from the menu (docs/channels.md).
    @State private var showComingSoon = false
    #endif
    #if DEBUG && targetEnvironment(simulator) && TUNING
    /// Screenshot hook only (`UI_SHEET=tuning`), dev build only.
    @State private var showTuning = false
    #endif
    @State private var helpTopic: HelpTopicID?
    @State private var path: [String] = []
    /// **The two controls at the top of the list** (docs/presentation.md, "Session list").
    /// The filter is per-visit — a narrowing is a question, not a setting — while the
    /// grouping is remembered, because "I read my library by month" is a fact about the
    /// rider. Empty string means he has never said, which is what lets the default rule
    /// (`LibraryGrouping.default`) answer for him until he does.
    #if BETA
    @AppStorage("library.groupBy.v1") private var groupByRaw = ""
    #endif
    @State private var filter = LibraryListFilter()
    @State private var editingRange = false
    /// Bumped by the menu's Support item; `feedbackMail(on:)` on the list does the rest.
    @State private var supportRequest = 0

    var body: some View {
        @Bindable var store = store
        let visible = filter.apply(to: store.sessions)
        let groups = grouping.groups(visible, spotName: { store.spot(id: $0)?.name })
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
            List {
                if store.sessions.isEmpty {
                    emptyState
                        .id("setup")
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    if let banner = store.disciplineBanner {
                        disciplineBannerRow(banner)
                            .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                    // The chips, the segmented control and the filter menu in the toolbar
                    // are one feature and one BETA door (docs/channels.md). Without them
                    // the list is what it has always been underneath: every session,
                    // newest first, in one flat run.
                    #if BETA
                    if filter.isActive {
                        LibraryFilterChips(filter: $filter)
                            .listRowInsets(.init(top: 4, leading: 16, bottom: 0, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    groupControl
                    #endif
                    if groups.isEmpty {
                        noMatchState
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.rows, id: \.id) { row in
                                NavigationLink(value: row.id) { SessionRowView(row: row) }
                            }
                            .onDelete { delete($0, in: group.rows) }
                        } header: {
                            if !group.title.isEmpty { Text(group.title) }
                        } footer: {
                            // One count line for the whole list, under the last section —
                            // a footer per month would say the same thing over and over.
                            if group.id == groups.last?.id {
                                Text(countLine(showing: visible.count, of: store.sessions.count))
                            }
                        }
                    }
                    FeedbackFooter.section
                }
            }
            .listStyle(.insetGrouped)
            // A session row is a thumbnail, a title, a date and five numbers; stretched over
            // an iPad it puts the sport badge a hand's width from the name it belongs to.
            // The list keeps its own card shape and sits in the middle of the window.
            .readableColumn()
            .navigationTitle("Sessions")
            .navigationDestination(for: String.self) { SessionDetailView(sessionID: $0) }
            .refreshable { await store.syncFromIntervals() }
            .toolbar {
                // The app's one menu (docs/presentation.md, "The library menu"), in the
                // order a new rider needs its answers: how to start, where the switches
                // are, who to write to, and only then the two "what is this" screens.
                // The line at the foot is the build, because it is the first thing every
                // support mail asks and the last thing a rider can find in Settings.
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { helpTopic = .betaGettingStarted } label: {
                            Label("Getting started", systemImage: "book")
                        }
                        Button { showSettings = true } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                        Button { supportRequest += 1 } label: {
                            Label("Support", systemImage: "envelope")
                        }
                        Divider()
                        // Asked for, not re-armed: the welcome screen again, raised by
                        // RootView once the menu is gone (SessionStore.replayWelcome).
                        Button { store.replayWelcome() } label: {
                            Label("What CleanJibe does", systemImage: "hand.wave")
                        }
                        // Straight under it, because it is the same question one build
                        // further on. Release only: a beta tester reading this menu is
                        // already past the door it opens (docs/channels.md).
                        #if !BETA
                        Button { showComingSoon = true } label: {
                            Label("Curious about what is coming", systemImage: "binoculars")
                        }
                        #endif
                        Button { showHelp = true } label: {
                            Label("What the numbers mean", systemImage: "questionmark.circle")
                        }
                        Divider()
                        Text(Self.buildLine)
                    } label: {
                        Label("Menu", systemImage: "line.3.horizontal")
                    }
                }
                // Beside Import rather than in the list: the filter is about the list, and a
                // control that narrows a list is not one of the list's rows.
                #if BETA
                ToolbarItem(placement: .topBarTrailing) {
                    LibraryFilterMenu(filter: $filter, editingRange: $editingRange,
                                      library: store.sessions)
                        .disabled(store.sessions.isEmpty)
                }
                #endif
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showImporter = true } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .disabled(store.isBusy)
                }
            }
            #if BETA
            .sheet(isPresented: $editingRange) {
                LibraryDateRangeSheet(filter: $filter, seed: rangeSeed)
            }
            #endif
            .feedbackMail(on: $supportRequest)
            .sheet(isPresented: $showSettings) { SettingsView() }
            #if DEBUG && targetEnvironment(simulator) && TUNING
            // `UI_SHEET=tuning` — a sheet of its own rather than "Settings, then push",
            // because `simctl` cannot tap the row. Same hook family, same reason as
            // `UI_SHEET=help` above; dev build only, like the page.
            .sheet(isPresented: $showTuning) {
                NavigationStack { TuningView(initial: store.tuning) }
                    .presentationSizing(.page)
            }
            #endif
            .sheet(isPresented: $showImporter) { ImportView() }
            .sheet(isPresented: $showHelp) { HelpView() }
            #if !BETA
            .sheet(isPresented: $showComingSoon) {
                NavigationStack { ComingSoonPage() }
                    .presentationSizing(.page)
            }
            #endif
            // A named topic opens as itself rather than as "the index, then the topic":
            // one sheet, one animation, and it is what the deep link actually meant.
            .sheet(item: $helpTopic) { HelpTopicSheet(id: $0) }
            // The setup topic offers "Open CleanJibe Settings"; only this screen knows how
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
            // The root's one-time notification offer must not land on top of a sheet this
            // screen opened — most of all Settings, which is where the key that *arms* the
            // offer is usually typed. The sheets are this view's state and the alert is two
            // levels up, so the state is reported rather than guessed at.
            .onChange(of: showSettings || showImporter || showHelp || editingRange
                      || helpTopic != nil) {
                _, presenting in store.isPresentingSheet = presenting
            }
            // Where a tapped "new session" notification lands. Two hooks rather than one:
            // on a cold start from the notification the id is already waiting when this
            // screen appears, and on a warm one it arrives seconds later, after the sync
            // the tap kicked off.
            .task { openPendingSession() }
            .onChange(of: store.pendingSessionID) { _, _ in openPendingSession() }
            #if DEBUG && targetEnvironment(simulator)
            // Headless-driving hooks: `simctl launch` can't tap, so env vars import the
            // fixture corpus and open a session for automated screenshots.
            // `UI_OPEN_SESSION=latest` takes the newest; any other value is matched
            // against the archived filename (e.g. `UI_OPEN_SESSION=ciq`).
            .task {
                // Before the import, not after it: the review question is asked *at* import
                // time (`SessionIngestor.windsurfEnabled` writes the row down as confirmed
                // while the switch is off), so a hook that wants the sheet has to turn the
                // feature on before there is anything to ask about.
                if ProcessInfo.processInfo.environment["UI_SHEET"] == "discipline" {
                    store.setWindsurfEnabled(true)
                }
                if ProcessInfo.processInfo.environment["UI_IMPORT_FIXTURES"] == "1" {
                    await store.importFixtures()
                }
                // `UI_LOAD_EXAMPLE=1` taps the setup card's example button for us, which
                // is the only way to photograph the loaded state (simctl cannot tap).
                if ProcessInfo.processInfo.environment["UI_LOAD_EXAMPLE"] == "1" {
                    await store.loadExampleSession()
                }
                // `UI_SEND_WATCH_MAP=1` renders the first spot's watch map headless and
                // writes what happened to Documents/watchmap-probe.txt — the one way to
                // see MapKit's answer without a watch on the desk. DEV, with the link.
                #if DEV
                if ProcessInfo.processInfo.environment["UI_SEND_WATCH_MAP"] == "1" {
                    var lines = ["spots: \(store.watchMapSpots.map { "\($0.spot.name) ×\($0.sessions) @\($0.spot.lat),\($0.spot.lon)" })"]
                    if let first = store.watchMapSpots.first {
                        let drawn = await WatchMapSender.gridOrReason(
                            centreLat: first.spot.lat, centreLon: first.spot.lon)
                        lines.append(drawn.grid.map { "grid \($0.width)×\($0.height), \($0.encoded.count) bytes" }
                                     ?? "failed: \(drawn.reason ?? "?")")
                    }
                    let url = URL.documentsDirectory.appending(path: "watchmap-probe.txt")
                    try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
                }
                #endif
                // `UI_GROUP_BY=none|month|year|spot` and `UI_FILTER_SOURCE=<raw>` stage the
                // two controls at the top of the list (docs/presentation.md, "Session
                // list"): a segmented control and a menu are both taps `simctl` cannot make.
                // The group-by hook writes the stored preference, exactly as a tap would —
                // there is nothing to leak, the list is drawn from it either way.
                #if BETA
                if let raw = ProcessInfo.processInfo.environment["UI_GROUP_BY"],
                   let grouping = LibraryGrouping(rawValue: raw) {
                    groupByRaw = grouping.rawValue
                }
                #endif
                if let raw = ProcessInfo.processInfo.environment["UI_FILTER_SOURCE"],
                   let source = ImportSource(rawValue: raw) {
                    filter.source = source
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
                // `import` is the way to reach the Apple Health source (ADR-017), which is
                // otherwise two taps behind a toolbar button `simctl` cannot press. It stages
                // only the sheet: the Health screen behind it fills itself from the machine's
                // real Health database, because the app is a reader there and staging a
                // workout would mean shipping code that writes fake ones into it.
                case "import": showImporter = true
                // `UI_SHEET=discipline` raises the post-import review over whatever the
                // fixtures just imported — simctl cannot tap the banner, and the sheet the
                // import itself raises has usually been and gone by the time a screenshot
                // is taken.
                case "discipline":
                    // The library has to be in memory before there is anything to review,
                    // and on a fixture run it is still importing when this task starts.
                    for _ in 0..<60 where store.disciplineToReview.isEmpty {
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                    store.raiseDisciplineReview()
                #if TUNING
                case "tuning": showTuning = true
                #endif
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
                // …and then push the session, here rather than only on the count change.
                //
                // The `onChange` below used to be the whole of it, and it only ever worked on
                // a run that *imported* something: `UI_OPEN_SESSION` on a simulator whose
                // library already holds the session never changed the count, so the hook
                // watched for a transition that had happened before the app launched and the
                // staging run sat on the list. Asking directly, once the imports above have
                // finished, covers that; the handler stays for the run where the import is
                // still landing when this task ends.
                openRequestedSession()
            }
            .onChange(of: store.sessions.count) { openRequestedSession() }
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

    /// "CleanJibe 0.15.0 (45)", with " · beta" or " · dev" after it — the same string as
    /// Settings → About, and from the same place, so the two never disagree about which
    /// channel this build is (docs/channels.md).
    private static var buildLine: String {
        "\(Branding.appName) \(SessionStore.appVersion)" + SettingsView.variantSuffix
    }

    // MARK: - Grouping

    /// What the rider last chose, or — until he chooses — what the size of his library
    /// says (`LibraryGrouping.default`). The count is the **whole** library, never the
    /// filtered view: the default is a fact about how much he has, not about what a chip
    /// is showing him this second.
    ///
    /// Without the beta's control there is nothing to remember and nothing to default from:
    /// the release channel's list is `.none`, one flat run of sessions newest first, which
    /// is what every library under a few dozen afternoons looked like anyway
    /// (docs/channels.md).
    #if BETA
    private var grouping: LibraryGrouping {
        LibraryGrouping(rawValue: groupByRaw)
            ?? .default(librarySize: store.sessions.count)
    }
    #else
    private var grouping: LibraryGrouping { .none }
    #endif

    #if BETA
    /// **None · Month · Year · Spot**, at the top of the list where the list's own shape is
    /// decided. A segmented control rather than a menu: four fixed answers, and the one in
    /// force is worth seeing without opening anything.
    private var groupControl: some View {
        Picker("Group by", selection: Binding(
            get: { grouping },
            set: { groupByRaw = $0.rawValue })) {
            ForEach(LibraryGrouping.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    /// The seed for "Custom range…": the month of the newest session the library holds.
    private var rangeSeed: ClosedRange<Date> {
        let newest = store.sessions.first?.startDate ?? Date()
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: newest))
        return (start ?? newest)...newest
    }
    #endif

    /// **"3 of 41 sessions"** while a filter is on, the plain count otherwise. The footer
    /// has always said how much there is; under a filter it has to say how much there is
    /// *and* how much it is not showing, or the number becomes a quiet lie about the library.
    private func countLine(showing: Int, of total: Int) -> String {
        let tail = " · pull to sync intervals.icu"
        guard filter.isActive else { return LibraryListing.sessionCount(total) + tail }
        return "\(showing) of \(LibraryListing.sessionCount(total))" + tail
    }

    /// What a filter that matches nothing says. Distinct from the empty-library state on
    /// purpose: "you have no sessions" in front of a rider with forty of them is the app
    /// being wrong about him, and the way out is one button, not a hunt through the menu.
    private var noMatchState: some View {
        ContentUnavailableView {
            Label("No session matches these filters", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("Nothing in the library answers to all of them at once.")
        } actions: {
            Button("Clear filters") { filter = LibraryListFilter() }
                .buttonStyle(.borderedProminent)
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
                Text(Self.emptyLibraryHint)
            } actions: {
                Button("Import…") { showImporter = true }
                    .buttonStyle(.borderedProminent)
                Button("Sync intervals.icu") { Task { await store.syncFromIntervals() } }
            }
        }
    }

    /// The Garmin export ZIP is a beta door (docs/channels.md), so only the beta's empty
    /// state offers it as the way in.
    #if BETA
    private static let emptyLibraryHint =
        "Import a FIT file or a Garmin export ZIP, or sync your intervals.icu "
        + "activities. Pull down to sync."
    #else
    private static let emptyLibraryHint =
        "Import a FIT file, or sync your intervals.icu activities. Pull down to sync."
    #endif

    /// **"3 new sessions analysed as Wingfoil · Review".**
    ///
    /// What an import the rider did not ask for is allowed to do: a Health auto-import, a
    /// Strava poll or an intervals.icu pickup must not throw a sheet in front of somebody who
    /// opened the app to look at yesterday's afternoon. It is not urgent either — the numbers
    /// are right under one preset and re-derivable under another, for ever — so it sits at the
    /// top of the list, says what was already done rather than asking a question, and goes
    /// away for good when he taps it or says "not now" to the sheet behind it.
    private func disciplineBannerRow(_ banner: String) -> some View {
        Button {
            store.raiseDisciplineReview()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(banner)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("Review")
                        .font(.footnote)
                        .foregroundStyle(.teal)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.teal.opacity(0.10), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
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

    /// Pushes the session a notification tap asked for, once. Replacing the path rather
    /// than appending: the rider tapped a banner, not a back button, and whatever he had
    /// open before is not where he asked to be.
    private func openPendingSession() {
        guard let id = store.pendingSessionID else { return }
        store.pendingSessionID = nil
        path = [id]
    }

    #if DEBUG && targetEnvironment(simulator)
    /// `UI_OPEN_SESSION=latest|<name>` — the staging hook that stands in for a tap on a row.
    /// `latest` takes the newest; anything else is matched against the archived filename
    /// (e.g. `UI_OPEN_SESSION=ciq`).
    private func openRequestedSession() {
        guard let wanted = ProcessInfo.processInfo.environment["UI_OPEN_SESSION"],
              path.isEmpty else { return }
        let match = wanted == "latest"
            ? store.sessions.first
            : store.sessions.first { ($0.originalFilename ?? "").contains(wanted) }
        guard let match else { return }
        // `UI_DISCIPLINE=windsurfFin` re-analyses that session under a preset before the page
        // opens (docs/algorithms.md "Disciplines"). `simctl` cannot tap a segmented control,
        // and the preset has to be in force *before* the detail loads or the shot is of the
        // wingfoil reading with a windsurf chip on it.
        if let raw = ProcessInfo.processInfo.environment["UI_DISCIPLINE"],
           let discipline = Discipline(rawValue: raw),
           discipline != match.analysisDiscipline {
            Task {
                await store.setDiscipline(discipline, for: match)
                path = [match.id]
            }
            return
        }
        path = [match.id]
    }
    #endif

    /// A swipe deletes the row that was swiped, which since the list has sections is an
    /// offset **into that section** and not into the library. Resolved against the group's
    /// own rows for that reason: indexing `store.sessions` here would delete August's third
    /// session because September's third was swiped.
    private func delete(_ offsets: IndexSet, in rows: [SessionRow]) {
        let doomed = offsets.map { rows[$0] }
        Task { for row in doomed { await store.delete(row) } }
    }
}

extension UTType {
    /// FIT has no system-declared type; the Info.plist imports it so files picked from
    /// iCloud Drive/Files resolve here instead of a dynamic `dyn.*` identifier.
    static let fitActivity = UTType(filenameExtension: "fit", conformingTo: .data) ?? .data
    /// Nor does GPX, on iOS. Same treatment (ios/project.yml declares both), except that
    /// this one conforms to `.xml` — a GPX *is* XML, and saying so lets a picker show it
    /// under any app that already claims XML rather than only under ours.
    static let gpxTrack = UTType(filenameExtension: "gpx", conformingTo: .xml) ?? .xml
    /// And TCX — how a Polar, Suunto or Coros session usually arrives. Same treatment as
    /// GPX for the same reasons; the two are read by the same picker and told apart by
    /// their bytes (`TrackParser`), never by which type the system resolved.
    static let tcxTrack = UTType(filenameExtension: "tcx", conformingTo: .xml) ?? .xml
}
