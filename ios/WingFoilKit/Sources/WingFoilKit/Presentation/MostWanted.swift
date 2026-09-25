import Foundation

/// **"Most wanted": the rider's vote in the feedback mail** (Jan, 23 Sep 2026).
///
/// The feedback sheet offers the features on docs/channels.md's "coming" list as ticks, plus
/// one free line. The ticks travel in the mail body under one fixed heading, one line per
/// tick, each ending in the row's `id` from `docs/copy/channels.json`, so a mailbox of
/// replies can be tallied with a search: `· appleHealth` counts the riders who ticked it.
///
/// **One source.** The ids are channels.json's beta ids and then its dev ids, in its order,
/// and `CopyContractTests` fails when they drift. The labels are short on purpose: a tick
/// row is read at a glance, and the full sentence is on the "Coming in a future release"
/// page one tap away.
public enum MostWanted {

    public struct Wish: Sendable, Equatable, Hashable, Identifiable {
        /// The channels.json row id. What a reply is tallied by.
        public let id: String
        public let label: String
        /// Which channel list the row comes from: `.beta` for a door the beta has and the
        /// release lacks, `.dev` for one only the dev build has.
        public let channel: HelpChannel
    }

    /// The fixed heading. Replies are tallied under it, so it does not change with a
    /// rewording anywhere else.
    public static let heading = "Most wanted"

    /// The sheet's section footer.
    public static let footer =
        "Tick what you want most. It decides what we build next. Nothing to tick? Tap Write mail."

    /// The free line's placeholder.
    public static let notePrompt = "Something else you want"

    /// The label of the free line in the mail.
    static let noteLabel = "Also: "

    public static let all: [Wish] = [
        Wish(id: "gpxTcx", label: "GPX and TCX files", channel: .beta),
        Wish(id: "appleHealth", label: "Apple Health, both ways", channel: .beta),
        Wish(id: "appleWatchApp", label: "The Apple Watch app", channel: .beta),
        Wish(id: "widgets", label: "Widgets and the complication", channel: .beta),
        Wish(id: "sessionVideo", label: "The session video", channel: .beta),
        Wish(id: "grouping", label: "Grouping and filters", channel: .beta),
        Wish(id: "sendToDeveloper", label: "Send a session to us", channel: .beta),
        Wish(id: "appleWatchLive", label: "A live view on the Apple Watch", channel: .beta),
        Wish(id: "garminLink", label: "The Garmin link", channel: .dev),
        Wish(id: "windsurf", label: "Windsurf, foil and fin", channel: .dev),
        Wish(id: "tuning", label: "The tuning page", channel: .dev),
        Wish(id: "ipad", label: "iPad", channel: .dev),
    ]

    /// What a build offers. The release offers the beta rows, which is exactly the list
    /// its "Coming in a future release" page shows. The beta and dev builds add the dev
    /// rows, the same "Further out" list their page shows. Never a row a page does not.
    public static func offered(in channel: HelpChannel) -> [Wish] {
        channel == .release ? all.filter { $0.channel == .beta } : all
    }

    /// The rider's answer: which rows he ticked, and the free line.
    public struct Vote: Sendable, Equatable {
        public var ticked: Set<String>
        public var note: String

        public init(ticked: Set<String> = [], note: String = "") {
            self.ticked = ticked
            self.note = note
        }

        public var isEmpty: Bool {
            ticked.isEmpty && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        /// The block in the mail, or nothing when the rider ticked nothing and wrote
        /// nothing. Ticks in the list's own order, whatever order they were tapped in.
        ///
        ///     Most wanted
        ///       ✓ Apple Health, both ways · appleHealth
        ///       Also: dark mode
        public var lines: [String] {
            guard !isEmpty else { return [] }
            var out = [MostWanted.heading]
            out += MostWanted.all.filter { ticked.contains($0.id) }
                .map { "  ✓ " + $0.label + " · " + $0.id }
            let note = UsageCounters.tidy(note)
            if !note.isEmpty { out.append("  " + MostWanted.noteLabel + note) }
            out.append("")
            return out
        }
    }
}
