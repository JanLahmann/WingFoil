import AuthenticationServices
import SwiftUI
import WingFoilKit

struct SettingsView: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var confirmReanalyze = false
    @State private var setupTopic: HelpTopicID?
    /// Settings → How much to say (F11). Every footer on this screen reads it through
    /// `ExplainedFootnote`; this copy is the picker's.
    @AppStorage(ExplainDetail.storageKey) private var detail: ExplainDetail = .concise

    var body: some View {
        NavigationStack {
            // `ScrollViewReader` for one reason: the screenshot hook below. A Form this
            // long puts most of its sections off screen, and `simctl` cannot scroll, so a
            // section added near the bottom could never be photographed
            // (docs/testing.md, "iOS screenshot hooks").
            ScrollViewReader { proxy in
            Form {
                // **Settings keeps switches and accounts, and nothing else** (Jan, build
                // 58). A block of three rows used to open this screen — "What CleanJibe
                // does", "Help" (then called "What the numbers mean") and "Send feedback"
                // — with two paragraphs of footer under them — and every one of the three
                // is a row of the library
                // menu one tap away (docs/presentation/copy-menu-settings.md, "The library menu"). Two homes
                // for the same door is two places to keep in step and one more screen for a
                // rider to search; the menu is the one that greets him, so the menu keeps
                // them. Nothing was lost: the menu's rows open the same screens, and
                // `UI_SHEET=help` still parks on the Help index from the library.
                //
                // **The contents, then the one switch every footer obeys** (F15a, F11,
                // Jan 25 September 2026). The page is the longest in the app; the chips
                // are its table of contents, and "how much to say" sits above everything
                // it changes, where the browser app has it too.
                jumpSection(proxy)
                detailSection
                icuSection
                    .id("icu")
                stravaSection
                    .id("strava")
                deletedSessionsSection
                notificationsSection
                    .id("notifications")
                // Settings → Garmin watch: DEV (docs/channels.md). Garmin Connect Mobile
                // owns the Bluetooth link and it stays behind the flag until the link has
                // real sessions behind it.
                #if DEV
                WatchLinkSection()
                    .id("watch")
                #endif
                analysisSection
                    .id("analysis")
                sessionListSection
                    .id("sessionList")
                rowShowsSection
                unitsSection
                    .id("units")
                speedRecordsSection
                    .id("speedRecords")
                // Windsurf, and the per-discipline thresholds behind it: DEV.
                #if DEV
                windsurfSection
                #endif
                #if TUNING
                tuningSection
                #endif
                // Apple Health, both directions: BETA. Unproven, and the release channel
                // carries no HealthKit entitlement to ask with.
                #if BETA
                healthSection
                betaSection
                    .id("beta")
                #endif
                // Every channel, with the TestFlight link only where the reader is not
                // already on it (docs/channels.md).
                comingSoonSection
                    .id("coming")
                storageSection
                    .id("storage")
                // Right under Storage, which is the section that just told the rider how
                // many megabytes his library is: "and here is how to keep a copy of it"
                // is the next sentence, not a separate topic.
                LibraryBackupSection()
                    .id("backup")
                // And right under the backup, which is the same subject one step further on:
                // a copy of the library is for getting it back, this is for having it in two
                // places at once. Dev only (docs/channels.md, ADR-026).
                #if DEV
                ICloudSyncSection()
                    .id("icloud")
                #endif
                #if DEBUG
                debugSection
                #endif
                aboutSection
                    .id("about")
            }
            // …and inside the page-sized sheet, the same measure every other list keeps.
            .readableColumn()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                Usage.record(.settingsOpened)
                await store.refreshStorage()
            }
            .sheet(item: $setupTopic) { HelpTopicSheet(id: $0) }
            .confirmationDialog("Re-run analysis for all sessions?",
                                isPresented: $confirmReanalyze, titleVisibility: .visible) {
                Button("Re-analyse \(store.sessions.count) sessions") {
                    Task { await store.rerunAnalysis() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every session is worked out again from its original recording. The "
                     + "recordings themselves are never changed.")
            }
            // Twelve sections of form. On an iPad the default sheet is the system's form
            // sheet — about 570 × 640 pt — which is a smaller window than the phone's for a
            // screen that scrolls twice as far as any other in the app. `.page` is the
            // regular-width way to ask for the room a `.large` detent asks for on a phone,
            // and it does nothing at compact width, where there is no other size to have.
            .presentationSizing(.page)
            #if DEBUG && targetEnvironment(simulator)
            // `UI_SCROLL_TO=<id>` parks the screen on one section — the anchors are the
            // `.id(…)`s above, and an unknown one is a no-op rather than a wrong screen.
            .task {
                guard let anchor = ProcessInfo.processInfo.environment["UI_SCROLL_TO"]
                else { return }
                // The Form has to have laid out once before an id resolves.
                try? await Task.sleep(nanoseconds: 400_000_000)
                withAnimation(.none) { proxy.scrollTo(anchor, anchor: .center) }
            }
            #endif
            }
        }
    }

    // MARK: - The one footer

    /// **What you get, in one line, and the way to the page that says how** (pattern K in
    /// docs/review-checklist.md, and Jan on 20 September 2026 reading the Notifications
    /// switch: seven paragraphs under one toggle).
    ///
    /// Every section's footer on this screen is now the same two things: the section's
    /// `lead` out of `SettingsCopy` — one sentence, twenty words at the outside, the same
    /// sentence the browser app prints — and, where a topic covers the section, a row that
    /// opens it. Nothing was deleted: rule 10 of docs/voice.md says a cut fact keeps a
    /// home, and every paragraph that came off this screen is in the help catalogue, which
    /// is where a reader who wants the mechanism was always going to end up.
    ///
    /// The channel is handed in because a topic's title can differ by channel
    /// (`HelpCatalog.topic(_:channel:)`), exactly as `settingFooter(_: HealthSwitch)` has
    /// always done it.
    ///
    /// Since 25 September 2026 the footer obeys Settings → How much to say (F11): concise is
    /// the lead and the `?`, extensive adds the section's own paragraphs, or the topic's
    /// where the section has none (`ExplainedFootnote`).
    private func settingFooter(_ id: String) -> some View {
        let section = SettingsCopy.section(id)
        return ExplainedFootnote(line: section.lead, topic: section.help,
                                 more: section.footer) { setupTopic = $0 }
    }

    // MARK: - Finding your way

    /// **The chips that jump to a section** (F15a). One per section this build draws, in
    /// the page's order, each the section's own header; `Health` and `Beta` only where the
    /// channel has them, the dev rows only in dev. The ids are the `.id(…)`s in `body`,
    /// which `UI_SCROLL_TO` uses as well.
    private var jumpChips: [JumpChips.Chip] {
        var chips: [JumpChips.Chip] = [
            .init(id: "icu", title: SettingsCopy.section("icu").title),
            .init(id: "strava", title: "Strava"),
            .init(id: "notifications", title: "Notifications"),
        ]
        #if DEV
        chips.append(.init(id: "watch", title: "Watch"))
        #endif
        chips += [
            .init(id: "analysis", title: "Analysis"),
            .init(id: "sessionList", title: SettingsCopy.section("sessionList").title),
            .init(id: "units", title: SettingsCopy.section("units").title),
            .init(id: "speedRecords", title: SettingsCopy.section("speedRecords").title),
        ]
        #if BETA
        chips += [.init(id: "health", title: "Apple Health"), .init(id: "beta", title: "Beta")]
        #endif
        chips += [
            .init(id: "coming", title: "Coming"),
            .init(id: "storage", title: SettingsCopy.section("storage").title),
            .init(id: "backup", title: "Backup"),
        ]
        #if DEV
        chips.append(.init(id: "icloud", title: "iCloud"))
        #endif
        chips.append(.init(id: "about", title: SettingsCopy.section("about").title))
        return chips
    }

    private func jumpSection(_ proxy: ScrollViewProxy) -> some View {
        Section {
            JumpChips(chips: jumpChips) { id in
                withAnimation { proxy.scrollTo(id, anchor: .top) }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .listRowBackground(Color.clear)
        }
    }

    /// **How much to say** (F11): one line and a `?` under every section, or the whole
    /// explanation. Concise by default. The words are the browser app's.
    private var detailSection: some View {
        Section {
            Picker(SettingsCopy.detailTitle, selection: $detail) {
                ForEach(ExplainDetail.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text(SettingsCopy.detailTitle)
        } footer: {
            Text(SettingsCopy.detailCaption)
        }
    }

    // MARK: - Sections

    /// **Why this account is here, before the field that asks for a key** (Jan, 15 Sep
    /// 2026). The section opened on an empty text field asking for something called an API
    /// key, and a rider who has never heard of intervals.icu has no way to tell whether he
    /// is being asked to sign up for a service or to skip the section. One caption answers
    /// it, and it is `GettingStartedGuide.settingsIcu` rather than a fourth wording of the
    /// same sentence: the guide, the help topic and this screen say one thing.
    private var icuSection: some View {
        Section {
            Text(GettingStartedGuide.settingsIcu)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // Typing the key and proving it works is one action, and this is its one
            // home: the first-run card that embedded the same view went on dev 70, so
            // there is one storage path and one verdict wording and nowhere else to type.
            IcuKeyEntry()
                .padding(.vertical, 4)
            // **"Sync now" is not here any more** (Jan, build 63: *Import does, Settings
            // configures*). Fetching sessions is an import, and the Import sheet's
            // "Sync intervals.icu" is the same call — as is a pull on the Sessions list.
            // What stays is what this section is for: the key, proving it, when it last
            // ran, and the two help topics.
            if let last = store.lastCheckAt ?? store.lastSyncDate {
                // `.current` deliberately: this is when *you* last synced, on your own clock —
                // the one date on this screen that is not about any session. `lastCheckAt`
                // is the one that actually moves on a background wake; the fallback is only
                // for a phone that has never had one land yet.
                LabeledContent("Last sync", value: Fmt.date(last, zone: .current))
            }
            if let trouble = store.syncTroubles[.intervals], trouble.isShown {
                Text(trouble.settingsLine)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Button { setupTopic = .icuSetup } label: {
                Label("Get a key in 4 steps", systemImage: "list.number")
            }
            Button { setupTopic = .icuTroubleshooting } label: {
                Label("Sync not working?", systemImage: "wrench.and.screwdriver")
            }
        } header: {
            Text(SettingsCopy.section("icu").title)
        } footer: {
            // The words are the kit's since 20 September 2026 (`SettingsCopy`), so the
            // browser app's Settings page prints the same line rather than a second one.
            settingFooter("icu")
        }
    }

    /// The second cloud source's account (ADR-023), and **the only place it is connected,
    /// named and disconnected** (Jan, build 63: *Import does, Settings configures*). All
    /// this page owns is "am I connected, as whom, and how do I stop" — plus the sentence
    /// about the ceiling Strava has put on the application until it reviews it, which
    /// belongs where a rider wondering why it will not connect would go looking. Picking the
    /// sessions stays on Import, which until a connection exists shows one line back to here.
    ///
    /// It opens on the same kind of caption the intervals.icu section does, and for the same
    /// reason: the section used to start with a button, and a button is not an answer to
    /// "why is Strava in a wingfoil app". `GettingStartedGuide.settingsStrava` is that
    /// answer, in the guide's own words — the route that needs no file, and what it costs.
    @ViewBuilder
    private var stravaSection: some View {
        Section {
            Text(GettingStartedGuide.settingsStrava)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !store.isStravaConfigured {
                Text("Not available in this build")
                    .foregroundStyle(.secondary)
            } else if store.isStravaConnected {
                LabeledContent("Connected",
                               value: store.stravaAthlete ?? "your Strava account")
                if let trouble = store.syncTroubles[.strava], trouble.isShown {
                    Text(trouble.settingsLine)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    // The fix, right under the cause. Strava's own button, as everywhere
                    // this app connects (`StravaBrand`).
                    if trouble.kind == .reconnect {
                        StravaConnectButton {
                            Task { await store.connectStrava(anchor: StravaConsent.anchor()) }
                        }
                        .disabled(store.isReadingStrava)
                    }
                }
                Button(role: .destructive) {
                    Task { await store.disconnectStrava() }
                } label: {
                    Text("Disconnect Strava")
                }
                .disabled(store.isBusy)
            } else {
                // The connect (Jan, 13 Sep 2026: a rider who opens Settings to "set up
                // Strava" should not be told to find another screen first) — and since
                // build 63 the *only* one: Import lists what a connected account holds and
                // otherwise points back here. Strava's own artwork, because the guidelines
                // are about the action and not about the screen it is on.
                StravaConnectButton {
                    Task { await store.connectStrava(anchor: StravaConsent.anchor()) }
                }
                .disabled(store.isReadingStrava)
            }
        } header: {
            Text("Strava")
        } footer: {
            if store.isStravaConfigured {
                // One line and the topic behind it (pattern K). The five paragraphs are
                // `SettingsCopy.footer("strava")` still, read by the browser's extensive
                // mode and by the Strava help topic this links to.
                settingFooter("strava")
            } else {
                Text("Strava is not available in this build. Everything else works as "
                     + "usual.")
            }
        }
    }

    /// The quiet way out of a deletion, and the only place the tombstones
    /// (`SessionTombstoneRow`) are ever visible.
    ///
    /// It is right under the sync section because that is the only thing they affect: a
    /// deleted session is skipped by intervals.icu and by nothing else — a FIT the rider
    /// picks by hand always imports, whatever he deleted before.
    ///
    /// Absent when there is nothing deleted, which is almost every install. A permanent row
    /// reading "Previously deleted: 0" would be a feature announcing itself to people who
    /// have never used it, on a screen that is already eight sections long.
    @ViewBuilder
    private var deletedSessionsSection: some View {
        if store.deletedSessionCount > 0 {
            Section {
                LabeledContent("Previously deleted",
                               value: "\(store.deletedSessionCount)")
                Button("Restore all") {
                    Task { await store.restoreAllDeletedSessions() }
                }
                .disabled(store.isBusy || store.apiKey.isEmpty)
            } header: {
                Text(SettingsCopy.section("deleted").title)
            } footer: {
                settingFooter("deleted")
            }
        }
    }

    /// Off by default, and the toggle itself is what asks iOS for permission — a launch
    /// that opens with a notification prompt before the rider has seen a single session is
    /// a prompt he says no to. The app makes the offer once by itself as well, right after
    /// a key has been *proved* against intervals.icu (`SessionStore.askAbout…`), which is
    /// the one moment a rider has just told us he wants sessions to arrive by themselves.
    ///
    /// **It says intervals.icu, not Garmin** (Jan, build 58). The switch read "Notify on new
    /// Garmin activities" and the check behind it has never been a Garmin one: it is a call
    /// to the rider's intervals.icu account, and every watch that syncs there — a Garmin, a
    /// Polar, a Suunto, a COROS, an Apple Watch through Health — is announced by it. Naming
    /// Garmin both under-promised the feature and pointed a rider with a problem at the
    /// wrong account.
    ///
    /// The footer is honest about the one thing that decides whether this works at all:
    /// background refresh is granted by iOS, not requested by us. A wake half an hour after
    /// the upload is the good case, and there is no bad case worth hiding — pull-to-refresh
    /// on the Sessions list is still the way to get a session *now*.
    private var notificationsSection: some View {
        Section {
            Toggle(SettingsCopy.notifyToggle, isOn: Binding(
                get: { store.notifyOnNewActivities },
                set: { store.notifyOnNewActivities = $0 }))
                .disabled(store.apiKey.isEmpty)
        } header: {
            Text("Notifications")
        } footer: {
            notificationsFooter
        }
    }

    /// **One line, and the topic that holds the rest** (20 September 2026, pattern K).
    ///
    /// This footer was seven paragraphs under one switch — what the check does, what it
    /// looks for, what you hear about, what happens on a tap, and three more about what
    /// iOS grants a background app. Every one of them is now `HelpTopicID.notifications`,
    /// which the line below opens. The disabled state keeps its own sentence, because a
    /// switch that cannot be used has to say why on the spot (pattern G).
    @ViewBuilder
    private var notificationsFooter: some View {
        if store.apiKey.isEmpty {
            Text("Add your intervals.icu API key above first. The check looks in your "
                 + "account.")
                .fixedSize(horizontal: false, vertical: true)
        } else {
            settingFooter("notifications")
        }
    }

    // The "Places → Spots" section used to sit here, and that was the whole problem
    // (app-ui-review.md §6.1): reaching it meant the gear icon, then scrolling past the
    // help rows, the intervals.icu key field, the sync section and the watch section — for
    // a dimension that is a top-level filter chip on *both* Records and Trends. It now has
    // two first-class homes, both of them where the rider already is: a section at the top
    // of the Gear tab, which is the tab that owns named things sessions reference, and a
    // "Manage spots…" row inside the spot filter menu itself, so the chip that filters by
    // spot is the chip that manages them.

    /// The one engine parameter the rider owns (docs/algorithms/wind.md "Default turn type").
    ///
    /// The wind axis is a line, so which end of it the wind blows from is a coin flip until
    /// something breaks the tie. The no-go zone usually does; where it cannot, "I mostly
    /// jibe" does, because flipping the wind 180° swaps every jibe and tack. The footer says
    /// exactly that, in the rider's words rather than the estimator's.
    private var analysisSection: some View {
        Section {
            // **"I mostly ride"** — the preset every imported session gets when its recording
            // does not say, which is every source but the CleanJibe watch app: wingfoil is not
            // a sport in Garmin, Strava, intervals.icu or Apple Health (docs/presentation/labels.md,
            // "Confirming the discipline on import"). Above the turn habit because it is the
            // more basic of the two questions — which rig, then which turn.
            //
            // Only worth asking where there is more than one answer: with the windsurf switch
            // off, "I mostly ride" has one option, and a picker with one option is a row that
            // takes up space to say nothing.
            if store.windsurfEnabled {
                Picker("I mostly ride", selection: Binding(
                    get: { store.riderDiscipline },
                    set: { store.riderDiscipline = $0 })) {
                    ForEach(Discipline.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Picker("Most of my turns are", selection: Binding(
                get: { store.defaultTurnType },
                set: { newValue in
                    guard newValue != store.defaultTurnType else { return }
                    store.defaultTurnType = newValue
                    Usage.record(.turnDirection)
                    // Stored analyses are not stale by engine version, so only an explicit
                    // re-run applies this to sessions already in the library.
                    if !store.sessions.isEmpty { confirmReanalyze = true }
                })) {
                ForEach(DefaultTurnType.allCases, id: \.self) { type in
                    Text(type.label).tag(type)
                }
            }
        } header: {
            Text("Analysis")
        } footer: {
            settingFooter("analysis")
        }
    }

    // The rig and wind-axis paragraphs that used to sit here are in the help catalogue
    // now: the rig in `HelpTopicID.windsurf`, which already said all three sentences, and
    // the wind axis in `.turnTypes` and `.windAxis`, which the footer's `?` opens
    // (20 September 2026, pattern K and rule 10 of docs/voice.md).


    /// **The map behind a row's track** (item 6 of the 18 Sep 2026 round).
    ///
    /// Off by default, and it stays that way unless a rider asks: the plain outline is the
    /// shape at a glance, and a snapshot per row costs a network round trip he did not ask
    /// for. The ground is whatever the maps are already drawn on (`MapStyleChoice`), so
    /// there is no second style choice to keep in step.
    private var sessionListSection: some View {
        Section {
            Toggle("Map behind the track in the list", isOn: Binding(
                get: { store.listMapBackdrop },
                set: { store.listMapBackdrop = $0 }))
        } header: {
            Text(SettingsCopy.section("sessionList").title)
        } footer: {
            settingFooter("sessionList")
        }
    }

    /// **Which three numbers a library row carries** (Jan, Beta 75: *"review meaning of
    /// numbers and the icons, maybe make configurable"*).
    ///
    /// Directly under the switch that is also about the list, and the three pickers are the
    /// list's three cells in the order they are drawn. Every option is offered by its word
    /// and its glyph together (`RowMetric`), which is the same pair the row draws — so the
    /// picker teaches the row rather than describing it.
    private var rowShowsSection: some View {
        Section {
            ForEach(0..<RowMetric.slots, id: \.self) { slot in
                Picker(Self.slotName(slot), selection: Binding(
                    get: { Self.metric(store.rowMetrics, slot) },
                    set: {
                        store.rowMetrics[slot] = $0
                        Usage.record(.rowMetrics)
                    })) {
                        ForEach(RowMetric.allCases) { metric in
                            Label(metric.label, systemImage: metric.icon).tag(metric)
                        }
                    }
            }
        } header: {
            Text(SettingsCopy.section("rowShows").title)
        } footer: {
            settingFooter("rowShows")
        }
    }

    /// **Knots or km/h, once, for every speed the phone shows** (Jan, 20 September 2026,
    /// relaying a user's request from a shared card).
    ///
    /// The engine stays in m/s and knots from end to end — the record windows are defined
    /// in knots and a golden may not move because a rider changed a picker
    /// (docs/algorithms/records.md, "Speed records"). This converts on the way to the screen only,
    /// through the platform's one formatter (`Speed`), which is why the share card and the
    /// records follow it without a line of their own.
    ///
    /// Right under "Row shows" because that is the other question about how the library
    /// reads, and it is where the browser app already draws it.
    private var unitsSection: some View {
        Section {
            Picker(SettingsCopy.section("units").title, selection: Binding(
                get: { store.speedUnit },
                set: {
                    store.speedUnit = $0
                    Usage.record(.units, detail: $0.rawValue)
                })) {
                    ForEach(SpeedUnit.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
        } header: {
            Text(SettingsCopy.section("units").title)
        } footer: {
            settingFooter("units")
        }
    }

    /// **Whether a record from a track that never measured a speed may stand** (Jan,
    /// 22 September 2026).
    ///
    /// Right under Units because it is the other question about how a speed reads. A
    /// wheel rather than a segmented control: three labels of two words each do not fit
    /// three segments on a phone, and the chosen line needs a sentence under it — the modes
    /// differ by *when* an unverified record counts, which is not legible from a label.
    ///
    /// The picker writes `store.speedRecordPolicy`, which is all the redraw there is: the
    /// Records and Trends screens key their query on it and re-read the same
    /// `record_effort` rows under the new rule (`LibraryStore.records(_:policy:)`).
    /// Nothing is re-imported and no stored number moves.
    private var speedRecordsSection: some View {
        Section {
            Picker(SettingsCopy.section("speedRecords").title, selection: Binding(
                get: { store.speedRecordPolicy },
                set: {
                    store.speedRecordPolicy = $0
                    Usage.record(.speedRecordPolicy, detail: $0.rawValue)
                })) {
                    ForEach(SpeedRecordPolicy.allCases) { Text($0.label).tag($0) }
                }
            Text(store.speedRecordPolicy.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text(SettingsCopy.section("speedRecords").title)
        } footer: {
            settingFooter("speedRecords")
        }
    }

    /// The cells in the order the row draws them. Position, not "left": a row is read in
    /// the reader's own direction.
    private static func slotName(_ slot: Int) -> String {
        ["First", "Second", "Third"][min(max(slot, 0), 2)]
    }

    /// The slot's metric, with the default standing in for a choice that is not there —
    /// the picker must draw something even if the stored triple is short.
    private static func metric(_ triple: [RowMetric], _ slot: Int) -> RowMetric {
        slot < triple.count ? triple[slot] : RowMetric.defaultTriple[slot]
    }

    #if DEV
    /// **"Windsurf (experimental)"** — the one switch every windsurf-facing control hangs off
    /// (Jan, 13 Sep 2026: *"windsurf should be hidden. Maybe enable with a switch"*).
    ///
    /// Off on a fresh install, and off is the app a wingfoiler downloaded: no rig picker above,
    /// no "Analyse as" card on a session's Log tab, no question after an import, no `?` on a
    /// library row and no windsurf topic on the Help index. On, everything is where it was.
    ///
    /// Its own section rather than a fourth row in Analysis, because the footer is a warning
    /// about what the feature cannot do yet and it has to sit under the switch it is warning
    /// about rather than under three unrelated rows — and because a switch that changes what
    /// the section above it contains should not be inside that section.
    private var windsurfSection: some View {
        Section {
            Toggle("Windsurf (experimental)", isOn: Binding(
                get: { store.windsurfEnabled },
                set: { store.setWindsurfEnabled($0) }))
        } footer: {
            // The honest version of "experimental": what works, what is switched off, and
            // what is a guess — in that order, so a windsurfer who turns it on knows which
            // numbers he may believe before he sees one.
            Text("Analyse sessions as windsurf foil or fin. Jibes and tacks work, and "
                 + "pumping is off. The planing speeds are still a guess.")
        }
    }
    #endif

    #if TUNING
    /// **Dev build only.** The whole section — and the page behind it — is compiled out of the
    /// app external testers get (`#if TUNING`, the "WingFoil Dev" scheme). A rider on the
    /// public build has no tuning UI, no stored overrides read, and an engine that can only
    /// run the published defaults.
    ///
    /// It sits under Analysis because that is the section it deepens: "Most of my turns are"
    /// is the one engine setting *everybody* owns; this is every other one, for the two of us
    /// working out where they should sit.
    private var tuningSection: some View {
        Section {
            NavigationLink {
                TuningView(initial: store.tuning)
            } label: {
                HStack {
                    Label("Tuning", systemImage: "slider.horizontal.3")
                    Spacer()
                    if !store.tuning.isEmpty {
                        Text("\(store.tuning.totalChangedCount) changed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            // **`dev`, not `beta`** — the header said one channel and the first two words
            // of its own footer said the other, eight points apart. Tuning is a dev door
            // (docs/channels.md: "Tuning page, sliders, turn workbench, tuned chips | dev"),
            // and this whole section is behind `#if TUNING`.
            Text("Tuning · dev")
        } footer: {
            // One line here too (pattern K). The three paragraphs are on the Tuning page
            // itself, which is where a reader who opened it is.
            Text("Dev build only. It puts the analysis thresholds on sliders, on this "
                 + "phone.")
        }
    }
    #endif

    #if BETA
    /// Both directions, in one section, because the rider thinks of Health as one place.
    ///
    /// **Both switches are always here** (docs/review-checklist.md, pattern E/G). The
    /// automatic pickup used to appear only once a workout had actually come in that way,
    /// so a rider who wanted it armed before his first import was shown nothing and told
    /// nothing. Visibility never depends on "has done X before": what he has done changes a
    /// footer, never whether a control exists.
    ///
    /// The two directions never meet — a session that came *out* of Health is excluded from
    /// what goes back in, or importing a workout would be how you end up with two of them.
    ///
    /// The titles and the footers are `HealthSwitch`'s, so the automatic pickup reads the
    /// same here and on Import → Apple Health, which are two places showing one control.
    @ViewBuilder
    private var healthSection: some View {
        Section {
            Toggle(HealthSwitch.write.title, isOn: Binding(
                get: { store.healthWriteEnabled },
                set: { store.healthWriteEnabled = $0 }))
        } header: {
            Text("Apple Health")
        } footer: {
            settingFooter(HealthSwitch.write)
        }
        .id("health")

        Section {
            Toggle(HealthSwitch.autoImport.title, isOn: Binding(
                get: { store.healthAutoImport },
                set: { store.healthAutoImport = $0 }))
        } footer: {
            settingFooter(HealthSwitch.autoImport)
        }
    }

    /// **What you get, in one line, and the way to the page that says how** (pattern K and
    /// pattern B). The footer stops explaining the mechanism; the help topic keeps it.
    private func settingFooter(_ setting: HealthSwitch) -> some View {
        ExplainedFootnote(line: setting.footer, topic: setting.helpTopic) { setupTopic = $0 }
    }
    #endif

    #if BETA
    /// **Settings → Beta** — what this build has that the App Store one does not, and the
    /// row that asks what neither has (docs/channels.md). See `BetaSectionView`.
    private var betaSection: some View { BetaSectionView() }
    #endif

    /// **"Coming in a future release"** — the channel list, read the way a rider asks it.
    /// Present in every channel; the release one carries the way into the beta, as a step
    /// on the page rather than a footnote under it.
    private var comingSoonSection: some View { ComingSoonSection() }

    private var storageSection: some View {
        Section(SettingsCopy.section("storage").title) {
            LabeledContent("Sessions", value: "\(store.storage.sessionCount)")
            LabeledContent("FIT archive", value: Fmt.bytes(store.storage.archiveBytes))
            LabeledContent("Database", value: Fmt.bytes(store.storage.databaseBytes))
            Button("Re-run analysis") { confirmReanalyze = true }
                .disabled(store.isBusy || store.sessions.isEmpty)
        }
    }

    #if DEBUG
    @ViewBuilder
    private var debugSection: some View {
        if store.fixturesAvailable {
            Section {
                Button("Import fixtures") { Task { await store.importFixtures() } }
                    .disabled(store.isBusy)
            } header: {
                Text("Debug")
            } footer: {
                Text("Simulator only. Ingests every .fit under "
                     + SessionStore.fixturesPath + ".")
            }
        }
    }
    #endif

    private var aboutSection: some View {
        Section {
            // " · dev" on the dev variant. Both variants carry the same bundle id, the same
            // marketing version and consecutive build numbers, so a screenshot is otherwise
            // indistinguishable — and "which build is this" is the first question of every bug
            // report that comes back from TestFlight.
            LabeledContent("App", value: SessionStore.appVersion + Self.variantSuffix)
            LabeledContent("Analysis engine", value: AnalysisEngine.version)
            // **The policy, reachable from inside the app** (15 September 2026). It was
            // not: docs/channels.md makes privacy-page coverage one of the four rules a
            // feature meets before it moves up a channel, and the App Store record carries
            // the URL, but a rider holding the app had no way to open the page that
            // describes what his phone is doing. The help topic answers in three sentences
            // (`HelpTopicID.privacy`); this is the door for the rider who never opens Help.
            Link(destination: URL(string: Branding.siteURL + "/privacy/")!) {
                Label("Privacy", systemImage: "hand.raised")
            }
            // The open-source libraries the kit is built on, and CleanJibe's own licence
            // (docs/release/privacy-labels.md audit, 26 September 2026). Same pattern as
            // the Tuning row above: a `NavigationLink` pushed inside this screen's own
            // `NavigationStack`, nothing new to present.
            NavigationLink {
                LicencesView()
            } label: {
                Label("Licences", systemImage: "doc.text")
            }
        } header: {
            Text(SettingsCopy.section("about").title)
        } footer: {
            settingFooter("about")
        }
    }

    /// Which channel this screenshot came from, and the first question of every report that

    /// comes back from TestFlight. The release channel says nothing, because there is nothing
    /// to distinguish it from — it is the app (docs/channels.md).
    static var variantSuffix: String {
        #if DEV
        " · dev"
        #elseif BETA
        " · beta"
        #else
        ""
        #endif
    }
}
