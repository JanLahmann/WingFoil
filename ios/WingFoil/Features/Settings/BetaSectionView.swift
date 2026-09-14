import SwiftUI
import WingFoilKit

/// **What is in this build, and what is in the next one** — the app's half of
/// docs/channels.md.
///
/// That file is the single source for which feature sits in which channel; this is the same
/// list in the rider's words, and it is written *from* it and never the other way round. Two
/// surfaces read it:
///
/// * `BetaSectionView` — beta and dev only. What the tester has that the App Store build does
///   not, so a report can say "the video export" rather than "the thing that makes a film",
///   plus the one row that asks him what is missing.
/// * `ComingSoonSection` — every channel. What is being tried before it arrives here. In the
///   release it carries the TestFlight link, because there the answer to "can I have it" is
///   one tap; in the beta it is the same list with no link, because the reader is already
///   there, plus the dev doors under it.
enum ChannelFeatures {

    /// The beta doors, one sentence each, in the order docs/channels.md lists them: getting
    /// a session in, the library, sharing, the watches.
    ///
    /// **This list is docs/channels.md's beta rows and nothing else.** A row that is not in
    /// that table is a promise nobody made; the Garmin export ZIP left this list on
    /// 14 September 2026 when it became a release feature, and the release's own Import
    /// screen has offered it all along ("FIT or ZIP…").
    static let beta: [String] = [
        ".gpx and .tcx files, so a session exported from a Polar, a Suunto or a COROS "
            + "opens straight from Files.",
        "Apple Health, both ways: what Apple's Workout app recorded is read in, and your "
            + "sessions are written back as workouts.",
        "The CleanJibe Apple Watch app, which records on your wrist with live numbers and "
            + "hands the session to the phone.",
        "Home-screen widgets and the watch complication.",
        "The session video: your afternoon as a film rather than a card.",
        "Grouping the library by month, year or spot, and filtering it.",
    ]

    /// The dev doors. Unproven by construction — a handful of hand-picked testers — and
    /// listed so a rider can ask for one rather than discover it does not exist.
    ///
    /// **Beta and dev only.** None of these is promised to anybody on the App Store: the
    /// release build lists what is being tested one channel up, and nothing beyond it.
    static let dev: [String] = [
        "The Garmin link: a summary card from your watch the moment you stop, the map of "
            + "your spot and the wind direction sent back to it",
        "Windsurf, foil and fin, with thresholds of its own",
        "The tuning page: every analysis threshold on a slider, tried against your own "
            + "sessions",
        "iPad",
    ]

    /// **Which build this is** — the one place the app answers that for the kit.
    ///
    /// The kit compiles every screen and every help topic in every channel and cannot see a
    /// compile flag, so anything in it that has to know — today, `HelpCatalog`, which must
    /// not offer a rider a page about a door his build does not have — is handed this.
    /// Gated here and nowhere else, beside the two feature lists it belongs with.
    #if DEV
    static let channel: HelpChannel = .dev
    #elseif BETA
    static let channel: HelpChannel = .beta
    #else
    static let channel: HelpChannel = .release
    #endif

    /// The public TestFlight link (docs/channels.md). Release only: in the beta it would
    /// point the reader at the build he is holding.
    static let testFlight = URL(string: "https://testflight.apple.com/join/nygqGGcn")!

    /// The other way in, and the one that survives a full TestFlight group.
    static let invite = URL(string: "https://cleanjibe.org/invite")!
}

// MARK: - The beta's own section

#if BETA
/// **Settings → Beta.** What this build has that the App Store one does not, and one row to
/// ask for what neither has.
///
/// A placeholder in the honest sense: the list is real and the mail is real, and what is
/// still to come is the usage and feature statistics docs/channels.md promises beside it —
/// counters kept on the phone and sent only in a mail the rider edits.
struct BetaSectionView: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var confirmStartOver = false

    var body: some View {
        Section {
            ForEach(ChannelFeatures.beta, id: \.self) { feature in
                Label {
                    Text(feature).font(.footnote)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.teal)
                }
            }
            // The existing composer, with a subject of its own: a feature request filed as
            // "CleanJibe 0.15.0 (52): …" reads like a bug report and gets answered like one.
            FeedbackMailRow(title: "Request a feature", systemImage: "lightbulb",
                            subjectOverride: "CleanJibe feature request")
            // The usage and feature statistics docs/channels.md promises beside the list:
            // counters kept on the phone, sent only in a mail the rider edits. Permanent,
            // because the library's own card (`UsageAskCard`) is occasional and because
            // "not now" has to leave a way back.
            UsageReportRow()
            // Last row of the section, and the only destructive one in the app. See
            // `SessionStore.startOver`: the thing deleting the app *should* do, and does
            // not, because iOS keeps keychain items across a delete.
            startOverRow
        } header: {
            Text("Beta")
        } footer: {
            Text("You are on the beta. These are the doors it opens that the App Store "
                 + "build does not have yet — every one of them is here to be ridden with "
                 + "and reported on.\n\n"
                 + "\"Request a feature\" opens the same mail as Send feedback, with this "
                 + "build and your library's shape already written in. Nothing is sent "
                 + "until you tap Send.\n\n"
                 + "\"Send usage report\" adds what this phone has counted — which parts of "
                 + "CleanJibe you have used, how often, and anything that has gone wrong. "
                 + "The counters never leave this phone except in that mail, and you can "
                 + "delete any line of it before you send it.\n\n"
                 + "\"Start over\" is here because deleting the app is not enough: iOS "
                 + "keeps your intervals.icu key and your Strava connection in its keychain "
                 + "and hands them back to the reinstall, so the first run you wanted to "
                 + "test never happens. This removes those too.")
        }
    }

    /// **Start over.** Red, last, and behind an alert that names everything it takes —
    /// there is no undo and no backup made on the way out, so the list *is* the safeguard.
    private var startOverRow: some View {
        Button(role: .destructive) {
            confirmStartOver = true
        } label: {
            Label("Start over", systemImage: "trash")
        }
        .disabled(store.isBusy)
        .alert("Start over?", isPresented: $confirmStartOver) {
            Button("Start over", role: .destructive) {
                // Settings has to be out of the way before the welcome screen can come up —
                // the store refuses to raise it over a sheet — so the same etiquette as
                // "What CleanJibe does": dismiss first, then ask.
                dismiss()
                Task { await store.startOver() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.warning)
        }
    }

    /// Every line of it is a thing that actually goes. A confirmation that says "all data"
    /// is a confirmation the rider cannot check, and the two items he would never guess at
    /// — the keychain pair — are the whole reason this row exists, so they are named.
    private static let warning =
        "CleanJibe will be exactly as it was the day you installed it. This cannot be "
        + "undone.\n\n"
        + "• Your whole library: every session, its analysis and its archived recording, "
        + "the deleted-session memory, and any backup file still waiting on this phone.\n"
        + "• Your intervals.icu key and your Strava connection. Both live in the iOS "
        + "keychain, which is why deleting the app leaves them behind — this does not.\n"
        + "• Every setting: the welcome screen's flag, map style and layers, replay "
        + "length, framing and music, the notification choices, the map picks for the "
        + "watch, and the tuning sliders.\n"
        + "• The beta's usage counters and the widgets' snapshot.\n"
        + "• Cached thumbnails, imported files and anything half-exported.\n\n"
        + "Nothing leaves this phone and nothing elsewhere is touched: your sessions on "
        + "intervals.icu, your activities on Strava and the recordings on your watch are "
        + "all still there. Make a backup first if you want one."
}
#endif

// MARK: - What is being tested

/// **"What is being tested"** — in Settings, and from the library menu in the release
/// channel (docs/channels.md).
///
/// It said *"Curious about what is coming"* until 14 September 2026. The App Store build is
/// a finished app, and a row that opens with the app being curious about itself reads as an
/// apology; what it actually points at is the place new things are ridden with first, so
/// that is what it is called now.
struct ComingSoonSection: View {

    var body: some View {
        Section {
            NavigationLink {
                ComingSoonPage()
            } label: {
                Label("What is being tested", systemImage: "binoculars")
            }
        } footer: {
            Text(Self.footer)
        }
    }

    #if BETA
    private static let footer =
        "What is being ridden with in this build, and the doors only a handful of testers "
        + "have behind it."
    #else
    private static let footer =
        "The features still proving themselves in the public TestFlight beta. Joining takes "
        + "one tap and your library comes with you."
    #endif
}

/// The list itself, as a page rather than a wall of rows in a form that is already long.
struct ComingSoonPage: View {

    var body: some View {
        List {
            Section {
                Text(Self.intro)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                ForEach(ChannelFeatures.beta, id: \.self) { row($0) }
            } header: {
                Text("In the public beta")
            } footer: {
                Text("Ridden with every week and reported on. A feature arrives in the App "
                     + "Store app once it has ten sessions from two riders behind it, a "
                     + "help topic, and no open report.")
            }

            // Beta and dev only. The dev doors are on a handful of hand-picked phones and
            // are promised to nobody; a list of them in the App Store build would be a
            // roadmap the release cannot keep (docs/channels.md).
            #if BETA
            Section {
                ForEach(ChannelFeatures.dev, id: \.self) { row($0) }
            } header: {
                Text("Further out")
            } footer: {
                Text("Experimental, and on a handful of phones. Ask for one and it will be "
                     + "worked on sooner — that is what the list is for.")
            }
            #endif

            #if !BETA
            // Release only: in the beta this would point the reader at the build he is
            // already holding (docs/channels.md).
            Section {
                Link(destination: ChannelFeatures.testFlight) {
                    Label("Join the beta on TestFlight", systemImage: "arrow.up.forward.app")
                }
                Link(destination: ChannelFeatures.invite) {
                    Label("cleanjibe.org/invite", systemImage: "link")
                }
            } footer: {
                Text("TestFlight is Apple's own beta app. The beta reads and writes the same "
                     + "library as this build, so switching keeps every session you have.")
            }
            #endif

            FeedbackFooter.section
        }
        .readableColumn()
        .navigationTitle("What is being tested")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The paragraph the page opens with. It says what the list *is*: not a wish list and
    /// not an apology for something missing, but the room next door where a feature is
    /// ridden with until it has earned its way into this app.
    #if BETA
    private static let intro =
        "CleanJibe grows in the open. You are holding the public beta, so everything below "
        + "is in your hands already — it is here to be ridden with and reported on, and it "
        + "moves into the App Store app once it has held up."
    #else
    private static let intro =
        "CleanJibe grows in the open. Everything in this app is finished and ridden with; "
        + "the features that are still proving themselves are tried in a public TestFlight "
        + "beta first, and arrive here once they have held up."
    #endif

    private func row(_ feature: String) -> some View {
        Label {
            Text(feature).font(.footnote)
        } icon: {
            Image(systemName: "circle.dashed")
                .foregroundStyle(.secondary)
        }
    }
}
