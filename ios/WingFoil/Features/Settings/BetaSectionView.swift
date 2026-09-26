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
/// One surface renders the kit's lists, and it is not the Beta section:
///
/// * `ComingSoonSection` — every channel. What is being tried before it arrives here. In
///   the release it carries the TestFlight link, because there the answer to "can I have
///   it" is one tap; in the beta the same rows are headed "In the public beta", because
///   the reader is already there, with the dev doors under them as "Further out".
/// * `BetaSectionView` — beta and dev only, and actions only. It checked the beta rows off
///   as a list of its own until dev 68, one row above the page that lists them again, so a
///   tester read the same six sentences twice on one screen (Jan, dev 68).
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
/// **Settings → Beta.** The four things a tester does: ask for a feature, send what this
/// phone has counted, check for a newer build, start again from nothing.
///
/// No list here. What this build has and the App Store one does not is one row below, on
/// "Coming in a future release" under the heading "In the public beta" (Jan, dev 68).
struct BetaSectionView: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var confirmStartOver = false

    var body: some View {
        Section {
            // The existing composer, with a subject of its own: a feature request filed as
            // "CleanJibe 0.15.0 (52): …" reads like a bug report and gets answered like one.
            VStack(alignment: .leading, spacing: 4) {
                FeedbackMailRow(title: "Request a feature", systemImage: "lightbulb",
                                subjectOverride: "CleanJibe feature request")
                // **The one test ask that had no home** (Jan, dev 70). It lived on /start,
                // which was cut; a beta door's ask belongs beside the beta's own feedback
                // doors (docs/channels.md, "Feedback and channel furniture"). It names the
                // three things a tester gets wrong: the preset, the wait, the share.
                note("Opens a mail with this build already filled in.",
                     more: ["Testing the session video? Keep the 20 s preset, wait for the "
                            + "bar, then share the clip."])
            }
            // The usage and feature statistics docs/channels.md promises the beta:
            // counters kept on the phone, sent only in a mail the rider edits. Permanent,
            // because the library's own card (`UsageAskCard`) is occasional and because
            // "not now" has to leave a way back.
            VStack(alignment: .leading, spacing: 4) {
                UsageReportRow()
                note("Adds what this phone has counted to a mail. Nothing goes until you "
                     + "tap Send.")
            }
            // "Check for a newer build now", with the last check and the verdict — the
            // manual door to the once-a-day check (`UpdateReminder`). Its own status line
            // is its caption.
            UpdateReminderSettingsRow()
            // Last row of the section, and the only destructive one in the app. See
            // `SessionStore.startOver`: the thing deleting the app *should* do, and does
            // not, because iOS keeps keychain items across a delete.
            VStack(alignment: .leading, spacing: 4) {
                startOverRow
                note("Removes your library, your settings, your intervals.icu key and your "
                     + "Strava connection.",
                     more: ["Deleting the app leaves the last two behind in the iOS "
                            + "keychain."])
            }
        } header: {
            Text("Beta")
        }
    }

    /// **Each row says what it does, under itself** (Jan, 26 September 2026: the section's
    /// footer was six paragraphs about four rows). One line in the concise reading, the rest
    /// only in the extensive one (`ExplainedFootnote`, Settings → How much to say). The
    /// sentence about "Coming in a future release" went: that row's own footer, one section
    /// down, already says what its page lists.
    private func note(_ line: String, more: [String] = []) -> some View {
        ExplainedFootnote(line: line, topic: nil, more: more) { _ in }
            .font(.caption)
            .foregroundStyle(.secondary)
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
        "CleanJibe goes back to the day you installed it. This cannot be undone.\n\n"
        + "• Your whole library. Every session, its analysis and its archived recording, "
        + "the deleted-session memory, and any backup file still waiting on this phone.\n"
        + "• Your intervals.icu key and your Strava connection. Both live in the iOS "
        + "keychain. Deleting the app leaves them behind. This does not.\n"
        + "• Every setting: the welcome screen's flag, map style and layers, replay "
        + "length, framing and music.\n"
        + "• The notification choices, the map picks for the watch, and the tuning "
        + "sliders.\n"
        + "• The beta's usage counters and the widgets' snapshot.\n"
        + "• Cached thumbnails, imported files and anything half-exported.\n\n"
        + "Nothing leaves this phone, and nothing elsewhere is touched.\n\n"
        + "Your sessions on intervals.icu, your activities on Strava and the recordings "
        + "on your watch all stay. Make a backup first if you want one."
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
        "This lists what testers ride with in this build, and what only a few of them "
        + "have tried."
    #else
    private static let footer =
        "These features are not in this app yet. Ride every one of them today in the "
        + "public beta.\n\n"
        + "Joining takes one tap, and your library comes with you."
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
                Text("TestFlight is Apple's own app for trying a build before it "
                     + "ships.\n\n"
                     + "CleanJibe's beta reads and writes the same library as this app. "
                     + "Every session, spot and piece of gear comes with you.\n\n"
                     + "Go back to the App Store version whenever you like.")
            }
            #endif

            Section {
                ForEach(ChannelFeatures.beta, id: \.self) { row($0) }
            } header: {
                Text("In the public beta")
            } footer: {
                Text("Testers ride with these every week and tell us how they went.\n\n"
                     + "A feature reaches the App Store app with ten sessions from two "
                     + "riders behind it. It also needs a help topic and no open report.")
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
                Text("These are experiments, on a handful of phones. Ask for one here "
                     + "and we work on it sooner.")
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
            Text("It takes one tap, and your library is kept.")
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
        "CleanJibe grows in the open. You are holding the public beta, so everything "
        + "below is in your hands already.\n\n"
        + "Ride it and report on it. Each one moves into the App Store app once it has "
        + "held up."
    #else
    private static let intro =
        "These functions come in a future release. Preview them now in the public "
        + "beta.\n\n"
        + "CleanJibe grows in the open. Everything in this app is finished and ridden "
        + "with.\n\n"
        + "A feature that is still proving itself is ridden in the beta first, then "
        + "arrives here."
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
