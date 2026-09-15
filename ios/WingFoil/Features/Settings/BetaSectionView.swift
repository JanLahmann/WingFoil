import SwiftUI
import WingFoilKit

/// **Which build this is, and how to get the next one** — the app's half of
/// docs/channels.md.
///
/// The *lists* are not here: the beta rows, the dev rows and the section title live in the
/// kit as `ChannelFeatures`, pinned to `docs/copy/channels.json` by `CopyContractTests`, so
/// that one wording reaches the app, the website and the store texts. What stays here is
/// the part the kit cannot have — a compile flag and two URLs.
///
/// Two surfaces render the kit's lists:
///
/// * `BetaSectionView` — beta and dev only. What the tester has that the App Store build
///   does not, so a report can say "the video export" rather than "the thing that makes a
///   film", plus the one row that asks him what is missing.
/// * `ComingSoonSection` — every channel. What is being tried before it arrives here. In
///   the release it carries the TestFlight link, because there the answer to "can I have
///   it" is one tap; in the beta it is the same list with no link, because the reader is
///   already there, plus the dev doors under it.
enum AppChannel {

    /// **Which build this is** — the one place the app answers that for the kit.
    ///
    /// The kit compiles every screen and every help topic in every channel and cannot see a
    /// compile flag, so anything in it that has to know — today, `HelpCatalog`, which must
    /// not offer a rider a page about a door his build does not have — is handed this.
    /// Gated here and nowhere else.
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
            // "Check for a newer build now", with the last check and the verdict — the
            // manual door to the once-a-day check (`UpdateReminder`).
            UpdateReminderSettingsRow()
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

// MARK: - Coming in a future release

/// **"Coming in a future release"** — in Settings, and only in Settings (docs/channels.md).
///
/// Two renamings and one move, both from what a rider actually reads. It said *"Curious
/// about what is coming"* until 14 September 2026 — an App Store app that opens by being
/// curious about itself reads as an apology — and then *"What is being tested"* until
/// 15 September, which describes the *room* rather than the reader's question. What he is
/// asking is when he gets these things, so the row answers that: they come in a future
/// release, and the beta is where they can be had now.
///
/// It also had a row in the library menu in the release channel, and does not any more
/// (Jan, build 58): the menu is for what a rider needs *now* — how to start, where the
/// switches are, who to write to, what the app is, what its numbers mean — and a list of
/// what this build does not have is none of those.
struct ComingSoonSection: View {

    /// One name, used by the row, the page title, docs/presentation.md and the website's
    /// own heading — which is why it is the kit's and not a literal here
    /// (`docs/copy/channels.json`, `sectionTitle`).
    static let title = ChannelFeatures.sectionTitle

    var body: some View {
        Section {
            NavigationLink {
                ComingSoonPage()
            } label: {
                Label(Self.title, systemImage: "binoculars")
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
        "These functions are not in this app yet. Every one of them can be ridden today in "
        + "the public beta — joining takes one tap, and your library comes with you."
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

            #if !BETA
            // **The way in, as a step rather than as a footnote.** It sat at the foot of
            // the page under the lists, which is where a rider stops reading — and it is
            // the one thing on the page he can act on today (Jan, build 58). So it is the
            // first section, it says what the tap costs and what it keeps, and the link is
            // a prominent button rather than a row of small blue text.
            Section {
                joinStep
            } header: {
                Text("How to join the beta")
            } footer: {
                Text("TestFlight is Apple's own app for trying a build before it ships. "
                     + "CleanJibe's beta reads and writes the same library as this app, so "
                     + "every session, spot and piece of gear you have comes with you — and "
                     + "you can go back to the App Store version whenever you like.")
            }
            #endif

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

            FeedbackFooter.section
        }
        .readableColumn()
        .navigationTitle(ComingSoonSection.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    #if !BETA
    /// Release only: in the beta this would point the reader at the build he is already
    /// holding (docs/channels.md).
    private var joinStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("One tap. Your library is kept.")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: AppChannel.testFlight) {
                Label("Open TestFlight", systemImage: "arrow.up.forward.app")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            // The other way in, and the one that survives a full TestFlight group.
            Link(destination: AppChannel.invite) {
                Label("cleanjibe.org/invite", systemImage: "link")
                    .font(.footnote.weight(.semibold))
            }
        }
        .padding(.vertical, 4)
    }
    #endif

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
        "These functions come in a future release, and can be previewed now in the public "
        + "beta. CleanJibe grows in the open: everything in this app is finished and ridden "
        + "with, and the features that are still proving themselves are tried in the beta "
        + "first, then arrive here once they have held up."
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
