import Foundation

/// **The rider's answer in the feedback mail: how the beta works, and what he wants next**
/// (Jan, 23 Sep 2026; reshaped 30 Sep 2026).
///
/// The feedback sheet offers two lists and one free line:
///
/// * **Beta features** — beta and dev only. Every beta door this build already has, each with
///   two ticks, *works* and *has a problem*. It is how a tester proves a feature, which is
///   how a feature moves to the App Store (docs/channels.md, the four rules).
/// * **Your wishlist** — what this build has not got: the beta rows in the release, and the
///   planned rows and the dev rows in the beta and the dev build. It was headed *Most
///   wanted* until 30 September 2026 (Jan).
/// * **Your idea** — one free line.
///
/// Every tick travels in the mail body as one line ending in the row's `id` from
/// `docs/copy/channels.json`, so a mailbox of replies can be tallied with a search:
/// `· appleHealth` counts the riders who ticked it.
///
/// **One source.** The ids are channels.json's beta ids and then its dev ids, in its order,
/// and `CopyContractTests` fails when they drift. The labels are short on purpose: a tick
/// row is read at a glance, and the full sentence is on the Beta page one tap away.
public enum MostWanted {

    public struct Wish: Sendable, Equatable, Hashable, Identifiable {
        /// The channels.json row id. What a reply is tallied by.
        public let id: String
        public let label: String
        /// Which channel list the row comes from: `.beta` for a door the beta has and the
        /// release lacks, `.dev` for one only the dev build has.
        public let channel: HelpChannel
        /// A row on the beta list that is a plan rather than a build. Nobody can say it
        /// works, so it stays on the wishlist in every channel.
        public var planned = false
    }

    /// The wishlist's fixed heading. Replies are tallied under it, so it does not change
    /// with a rewording anywhere else.
    public static let heading = "Your wishlist"

    /// The sheet's wishlist footer.
    public static let footer =
        "Tick what you want most. It decides what we build next. Nothing to tick? Tap Write mail."

    /// The beta features' heading, in the sheet and in the mail.
    public static let checkHeading = "Beta features"

    /// The beta features' footer in the sheet.
    public static let checkFooter = "Ridden with one of these? Tell us how it went."

    /// The free line's placeholder, and its label in the mail.
    public static let notePrompt = "Your idea"
    static let noteLabel = notePrompt + ": "

    public static let all: [Wish] = [
        Wish(id: "gpxTcx", label: "GPX and TCX files", channel: .beta),
        Wish(id: "appleHealth", label: "Apple Health, both ways", channel: .beta),
        Wish(id: "appleWatchApp", label: "The Apple Watch app", channel: .beta),
        Wish(id: "widgets", label: "Widgets and the complication", channel: .beta),
        Wish(id: "sessionVideo", label: "The session video", channel: .beta),
        Wish(id: "grouping", label: "Grouping and filters", channel: .beta),
        Wish(id: "sessionStory", label: "The session story", channel: .beta),
        Wish(id: "sendToDeveloper", label: "Send a session to us", channel: .beta),
        Wish(id: "appleWatchLive", label: "A live view on the Apple Watch", channel: .beta,
             planned: true),
        Wish(id: "garminLink", label: "The Garmin link", channel: .dev),
        Wish(id: "windsurf", label: "Windsurf, foil and fin", channel: .dev),
        Wish(id: "tuning", label: "The tuning page", channel: .dev),
        Wish(id: "ipad", label: "iPad", channel: .dev),
    ]

    /// **The wishlist a build offers**: what it has not got. The release offers the beta
    /// rows, which is exactly the list its Beta page and *Coming in a future release* show.
    /// The beta and the dev build offer the planned rows and the dev rows, the *Further out*
    /// list their page shows. Never a row a page does not.
    public static func offered(in channel: HelpChannel) -> [Wish] {
        channel == .release
            ? all.filter { $0.channel == .beta }
            : all.filter { $0.planned || $0.channel == .dev }
    }

    /// **The beta features a build can report on**: the beta rows it has, planned ones
    /// excepted. Nothing in the release, which has none of them.
    public static func checked(in channel: HelpChannel) -> [Wish] {
        channel == .release ? [] : all.filter { $0.channel == .beta && !$0.planned }
    }

    /// A tester's word on one beta feature.
    public enum Verdict: String, Sendable, CaseIterable {
        case works, problem

        /// The tick's label, in the sheet and in the mail.
        public var label: String {
            switch self {
            case .works: "Works"
            case .problem: "Has a problem"
            }
        }

        var mark: String { self == .works ? "✓" : "✗" }
    }

    /// The rider's answer: how the beta features went, which wishes he ticked, and the free
    /// line.
    public struct Vote: Sendable, Equatable {
        public var ticked: Set<String>
        public var checks: [String: Verdict]
        public var note: String

        public init(ticked: Set<String> = [], checks: [String: Verdict] = [:],
                    note: String = "") {
            self.ticked = ticked
            self.checks = checks
            self.note = note
        }

        public var isEmpty: Bool {
            ticked.isEmpty && checks.isEmpty
                && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        /// The blocks in the mail, or nothing when the rider ticked nothing and wrote
        /// nothing. Rows in the list's own order, whatever order they were tapped in.
        ///
        ///     Beta features
        ///       ✓ The Apple Watch app · works · appleWatchApp
        ///       ✗ The session video · has a problem · sessionVideo
        ///
        ///     Your wishlist
        ///       ✓ The Garmin link · garminLink
        ///       Your idea: dark mode
        public var lines: [String] {
            guard !isEmpty else { return [] }
            var out: [String] = []
            let checked = MostWanted.all.compactMap { wish in
                checks[wish.id].map { (wish, $0) }
            }
            if !checked.isEmpty {
                out.append(MostWanted.checkHeading)
                out += checked.map { wish, verdict in
                    "  " + verdict.mark + " " + wish.label + " · "
                        + verdict.label.lowercased() + " · " + wish.id
                }
                out.append("")
            }
            let note = UsageCounters.tidy(note)
            if !ticked.isEmpty || !note.isEmpty {
                out.append(MostWanted.heading)
                out += MostWanted.all.filter { ticked.contains($0.id) }
                    .map { "  ✓ " + $0.label + " · " + $0.id }
                if !note.isEmpty { out.append("  " + MostWanted.noteLabel + note) }
                out.append("")
            }
            return out
        }
    }
}
