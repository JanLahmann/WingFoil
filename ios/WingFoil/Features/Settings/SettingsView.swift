import AuthenticationServices
import SwiftUI
import WingFoilKit

struct SettingsView: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var confirmReanalyze = false
    @State private var setupTopic: HelpTopicID?

    var body: some View {
        NavigationStack {
            Form {
                // **Settings keeps switches and accounts, and nothing else** (Jan, build
                // 58). A block of three rows used to open this screen — "What CleanJibe
                // does", "Help" (then called "What the numbers mean") and "Send feedback"
                // — with two paragraphs of footer under them — and every one of the three
                // is a row of the library
                // menu one tap away (docs/presentation.md, "The library menu"). Two homes
                // for the same door is two places to keep in step and one more screen for a
                // rider to search; the menu is the one that greets him, so the menu keeps
                // them. Nothing was lost: the menu's rows open the same screens, and
                // `UI_SHEET=help` still parks on the Help index from the library.
                icuSection
                stravaSection
                deletedSessionsSection
                notificationsSection
                // Settings → Garmin watch: DEV (docs/channels.md). Garmin Connect Mobile
                // owns the Bluetooth link and it stays behind the flag until the link has
                // real sessions behind it.
                #if DEV
                WatchLinkSection()
                #endif
                analysisSection
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
                #endif
                // Every channel, with the TestFlight link only where the reader is not
                // already on it (docs/channels.md).
                comingSoonSection
                storageSection
                // Right under Storage, which is the section that just told the rider how
                // many megabytes his library is: "and here is how to keep a copy of it"
                // is the next sentence, not a separate topic.
                LibraryBackupSection()
                #if DEBUG
                debugSection
                #endif
                aboutSection
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
                Button("Re-analyze \(store.sessions.count) sessions") {
                    Task { await store.rerunAnalysis() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Cached analysis.json files are dropped and recomputed from the archived "
                     + "FITs. Original recordings are never touched.")
            }
            // Twelve sections of form. On an iPad the default sheet is the system's form
            // sheet — about 570 × 640 pt — which is a smaller window than the phone's for a
            // screen that scrolls twice as far as any other in the app. `.page` is the
            // regular-width way to ask for the room a `.large` detent asks for on a phone,
            // and it does nothing at compact width, where there is no other size to have.
            .presentationSizing(.page)
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
            if let last = store.lastSyncDate {
                // `.current` deliberately: this is when *you* last synced, on your own clock —
                // the one date on this screen that is not about any session.
                LabeledContent("Last sync", value: Fmt.date(last, zone: .current))
            }
            Button { setupTopic = .icuSetup } label: {
                Label("Get a key in 4 steps", systemImage: "list.number")
            }
            Button { setupTopic = .icuTroubleshooting } label: {
                Label("Sync not working?", systemImage: "wrench.and.screwdriver")
            }
        } header: {
            Text("intervals.icu")
        } footer: {
            Text("Downloads the original FIT of every windsurf, wing, kite, surf and SUP "
                 + "activity in your intervals.icu account, going two years back.\n\n"
                 + "Activities already in the library are never downloaded again.")
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
                Text(markdown: "Strava opens, you say yes, and CleanJibe can list your "
                     + "activities on the Import screen.\n\n"
                     + "CleanJibe only **reads** your Strava account. It never writes, "
                     + "renames or posts anything.\n\n"
                     + "Sessions imported this way are analysed from positions alone. "
                     + "Their speed records are marked uncertified.\n\n"
                     + "Strava lets a new app connect a limited number of riders. "
                     + "Connecting is refused while CleanJibe is full.\n\n"
                     + "That says nothing about your account. "
                     + Copy.stravaAskForMore)
            } else {
                Text("This build carries no Strava API keys, so the Strava source is not "
                     + "offered. Everything else works as usual.")
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
                Text("Deleted sessions")
            } footer: {
                Text("Sessions you deleted stay deleted. Syncing intervals.icu leaves "
                     + "them alone, by hand and in the background.\n\n"
                     + "Restoring forgets that. The next sync brings back every one of "
                     + "them that is still on intervals.icu.")
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
            Text(notificationsFooter)
        }
    }

    /// What the switch does, and the one thing that decides whether it works at all:
    /// background refresh is granted by iOS, not requested by the app.
    private var notificationsFooter: String {
        guard !store.apiKey.isEmpty else {
            return "Add your intervals.icu API key above first. The check is a call to "
                + "your account."
        }
        let ios = "iOS decides when a background app may run. It learns your habits and "
            + "may hold a check back for hours.\n\n"
            + "It never runs in Low Power Mode, or while Background App Refresh is off "
            + "under Settings → General → Background App Refresh.\n\n"
            + "Pull down on Sessions to sync now."
        return SettingsCopy.notifyExplanation + "\n\n" + ios
    }

    // The "Places → Spots" section used to sit here, and that was the whole problem
    // (app-ui-review.md §6.1): reaching it meant the gear icon, then scrolling past the
    // help rows, the intervals.icu key field, the sync section and the watch section — for
    // a dimension that is a top-level filter chip on *both* Records and Trends. It now has
    // two first-class homes, both of them where the rider already is: a section at the top
    // of the Gear tab, which is the tab that owns named things sessions reference, and a
    // "Manage spots…" row inside the spot filter menu itself, so the chip that filters by
    // spot is the chip that manages them.

    /// The one engine parameter the rider owns (docs/algorithms.md "Default turn type").
    ///
    /// The wind axis is a line, so which end of it the wind blows from is a coin flip until
    /// something breaks the tie. The no-go zone usually does; where it cannot, "I mostly
    /// jibe" does, because flipping the wind 180° swaps every jibe and tack. The footer says
    /// exactly that, in the rider's words rather than the estimator's.
    private var analysisSection: some View {
        Section {
            // **"I mostly ride"** — the preset every imported session gets when its recording
            // does not say, which is every source but the CleanJibe watch app: wingfoil is not
            // a sport in Garmin, Strava, intervals.icu or Apple Health (docs/presentation.md,
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
            Text(markdown: analysisFooter)
        }
    }

    /// The rig paragraph only where there is a rig row to explain: with the windsurf switch
    /// off nothing above it asks which rig this was, and a footer that answers an unasked
    /// question is the app talking to itself.
    private var analysisFooter: String {
        let rig = "Wingfoil is not a sport in Garmin, Strava, intervals.icu or Apple Health. "
            + "A new session cannot say which rig you were on.\n\n"
            + "What you mostly ride answers for it. CleanJibe asks you to confirm after "
            + "each import.\n\n"
            + "Sessions already in your library are not changed.\n\n"
        // The *why* behind the habit clause, kept out of the footer: flipping the wind
        // end for end turns every jibe into a tack, so the wrong end is not a small error.
        let wind = "Your track gives the wind axis as a *line*. Which end the wind blew "
            + "from is the hard half.\n\n"
            + "The no-go zone usually settles it. You can sail any downwind course, but "
            + "none straight into the wind.\n\n"
            + "When a session cannot settle it, your habit does.\n\n"
            + "Sessions already in the library change only when you re-run the analysis."
        return store.windsurfEnabled ? rig + wind : wind
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
            Text("Analyse sessions as windsurf foil or fin. Untested: jibes and tacks work, "
                 + "pumping is off, planing thresholds are provisional.")
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
            Text("Dev build only.\n\n"
                 + "Puts the analysis thresholds on sliders, so a parameter can be tried "
                 + "against your own sessions in a minute instead of a rebuild.\n\n"
                 + "They apply on this phone only, and every screen showing a tuned "
                 + "number says so.")
        }
    }
    #endif

    #if BETA
    /// Both directions, in one section, because the rider thinks of Health as one place.
    ///
    /// The read toggle appears only once a session has actually arrived that way (ADR-017):
    /// until then the door is on the Import screen where a first import belongs, and a switch
    /// here would be a question about a source the rider has never used. The two directions
    /// never meet — a session that came *out* of Health is excluded from what goes back in,
    /// or importing a workout would be how you end up with two of them.
    @ViewBuilder
    private var healthSection: some View {
        Section {
            Toggle("Add sessions to Apple Health", isOn: Binding(
                get: { store.healthWriteEnabled },
                set: { store.healthWriteEnabled = $0 }))
        } header: {
            Text("Apple Health")
        } footer: {
            Text(markdown: "Off by default. Each session is written as a **Surfing** "
                 + "workout.\n\n"
                 + "Apple Health has no wingfoil or windsurf activity, and Surfing is the "
                 + "closest.\n\n"
                 + "The discipline, foil share, flights and best 2 s ride in its "
                 + "metadata.\n\n"
                 + "Sessions you imported *from* Health are left alone, so a workout "
                 + "never appears twice.")
        }

        if store.hasImportedFromHealth {
            Section {
                Toggle("Import new Health workouts automatically", isOn: Binding(
                    get: { store.healthAutoImport },
                    set: { store.healthAutoImport = $0 }))
            } footer: {
                Text("CleanJibe checks Apple Health when you open it and imports any new "
                     + "workout of the types you chose on the Import screen.\n\n"
                     + "Anything already in your library is recognised, and a workout you "
                     + "imported and then deleted is not brought back.\n\n"
                     + "iOS can also wake the app when a workout is saved. iOS decides "
                     + "when, and that may be hours later.\n\n"
                     + "It never happens with Background App Refresh off. "
                     + Copy.openToPickUp)
            }
        }
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
        Section("Storage") {
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
            // **What changed in the build those two numbers name.** The notes are kit data
            // (`WhatsNew`, generated from docs/copy/whats-new.json), filtered by this
            // build's channel, and the same screen the Help topic opens.
            NavigationLink { WhatsNewPage() } label: {
                Label("What's new", systemImage: "sparkles")
            }
            // **The policy, reachable from inside the app** (15 September 2026). It was
            // not: docs/channels.md makes privacy-page coverage one of the four rules a
            // feature meets before it moves up a channel, and the App Store record carries
            // the URL, but a rider holding the app had no way to open the page that
            // describes what his phone is doing. The help topic answers in three sentences
            // (`HelpTopicID.privacy`); this is the door for the rider who never opens Help.
            Link(destination: URL(string: Branding.siteURL + "/privacy/")!) {
                Label("Privacy", systemImage: "hand.raised")
            }
        } header: {
            Text("About")
        } footer: {
            Text("Wind is estimated on this device from your track.")
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

/// **One wording per switch, wherever the switch is offered.**
///
/// The new-sessions notification is offered twice — as a switch in Settings, and once per
/// install as an alert the app raises by itself the moment an intervals.icu key has been
/// proved (`SessionStore.askAboutNewActivitiesIfNeeded`). The alert used to have a sentence
/// of its own ("When a new Garmin activity syncs…"), which named the wrong account and
/// described less than the switch does. It is the same feature, so it is the same sentence.
enum SettingsCopy {

    /// The switch, and the alert's title in the affirmative.
    static let notifyToggle = "Notify on new sessions from intervals.icu"

    /// What the switch does, in one paragraph. Used verbatim as the one-time offer's
    /// message, which is what "with the switch's own explanation" means.
    static let notifyExplanation =
        "While the phone is idle, CleanJibe asks intervals.icu for new activity.\n\n"
        + "It looks for windsurf, wing, kite, surf and SUP, from any watch that syncs "
        + "there.\n\n"
        + "You hear about the ones that are not in your library yet.\n\n"
        + "The session is downloaded and analysed in the background, so tapping the "
        + "notification usually opens a finished analysis."
}
