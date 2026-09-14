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
/// * `ComingSoonSection` — every channel. What is not in *this* build yet. In the release it
///   carries the TestFlight link, because there the answer to "can I have it" is one tap; in
///   the beta it is the same list with no link, because the reader is already there.
enum ChannelFeatures {

    /// The beta doors, in the order docs/channels.md lists them: getting a session in, the
    /// analysis, the library, sharing, the watches.
    static let beta: [String] = [
        "GPX and TCX files, so a Polar, Suunto or Coros session opens straight from Files",
        "Your whole Garmin history in one go, from the Export Your Data ZIP",
        "Apple Health both ways — read what Apple's Workout app recorded, write your "
            + "sessions back as workouts",
        "The CleanJibe Apple Watch app: record on your wrist, live numbers, straight to "
            + "the phone",
        "Home-screen widgets and the watch complication",
        "The session video — your afternoon as a film, not a card",
        "Group the library by month, year or spot, and filter it",
    ]

    /// The dev doors. Unproven by construction — a handful of hand-picked testers — and
    /// listed so a rider can ask for one rather than discover it does not exist.
    static let dev: [String] = [
        "The Garmin link: a summary card from your watch the moment you stop, the map of "
            + "your spot and the wind direction sent back to it",
        "Windsurf, foil and fin, with thresholds of its own",
        "The tuning page: every analysis threshold on a slider, tried against your own "
            + "sessions",
        "iPad",
    ]

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
                 + "delete any line of it before you send it.")
        }
    }
}
#endif

// MARK: - What is coming

/// **"Curious about what is coming"** — in Settings, and from the library menu in the
/// release channel (docs/channels.md).
struct ComingSoonSection: View {

    var body: some View {
        Section {
            NavigationLink {
                ComingSoonPage()
            } label: {
                Label("Curious about what is coming", systemImage: "binoculars")
            }
        } footer: {
            Text(Self.footer)
        }
    }

    #if BETA
    private static let footer =
        "The doors that are not open yet, including the ones only a handful of testers have."
    #else
    private static let footer =
        "What the beta already has, and what is being worked on behind it. Joining takes "
        + "one tap and your library comes with you."
    #endif
}

/// The list itself, as a page rather than a wall of rows in a form that is already long.
struct ComingSoonPage: View {

    var body: some View {
        List {
            Section {
                ForEach(ChannelFeatures.beta, id: \.self) { row($0) }
            } header: {
                Text("In the beta")
            } footer: {
                Text("Ridden with every week and reported on. A feature moves into the App "
                     + "Store build once it has ten sessions from two riders behind it, a "
                     + "help topic, and no open report.")
            }

            Section {
                ForEach(ChannelFeatures.dev, id: \.self) { row($0) }
            } header: {
                Text("Further out")
            } footer: {
                Text("Experimental, and on a handful of phones. Ask for one and it will be "
                     + "worked on sooner — that is what the list is for.")
            }

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
        .navigationTitle("What is coming")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ feature: String) -> some View {
        Label {
            Text(feature).font(.footnote)
        } icon: {
            Image(systemName: "circle.dashed")
                .foregroundStyle(.secondary)
        }
    }
}
