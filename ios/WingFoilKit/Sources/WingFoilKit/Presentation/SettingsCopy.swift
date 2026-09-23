import Foundation

/// **Every word the Settings screen says, in one place, for all three shells.**
///
/// Jan, 20 September 2026, reading the browser app on his phone: *"/app/#/settings is way
/// too long, do we need all this?"*. Part of the answer was that the phone and the browser
/// had written their own Settings text twice — the phone's footers in the app target, the
/// browser's typed into `web/app/index.html` — so neither could be shortened without the
/// other drifting. One home fixes both (docs/review-checklist.md, pattern F).
///
/// A section is therefore two texts, not one:
///
///   * `lead` — **what you get, in one line** (pattern K). It is what a rider reads by
///     default, in the browser as on the phone, and it is never more than twenty words.
///     Register 3 of docs/voice.md, the datasheet.
///   * `footer` — the paragraphs the phone has always printed under the section. They are
///     the *extensive* reading: the browser shows them only when the reader asks, and he
///     asks once, site-wide (`web/js/explain.js`).
///
/// `help` is the topic the section's `?` opens. A section with no topic has no `?`, and
/// nothing is lost: `lead` already says what the rows do.
///
/// `web` and `phone` say which shell has the section at all. A browser has no notification
/// daemon and no stored analysis to re-run; a phone has no per-origin storage to explain.
/// Neither is a deviation to fix, so both are written down here rather than left for a
/// reader to discover (docs/screens.md, "Deviations of the web, with reasons").
///
/// The order is `SettingsView`'s, top to bottom, and it is the order the browser draws as
/// well. `web/tools/make_app_copy.py` renders the web's half out of
/// `docs/copy/settings.json`, which `SettingsCopyExportTests` writes from this file.
public struct SettingsSectionCopy: Sendable, Equatable {

    /// The section's id. Stable: the web's markup anchors on it (`#settings-<id>`).
    public let id: String
    /// The section header, as the phone prints it.
    public let title: String
    /// What you get, in one line. Twenty words at the outside.
    public let lead: String
    /// The phone's own footer, paragraph by paragraph.
    public let footer: [String]
    /// The help topic the `?` opens, where one covers the section.
    public let help: HelpTopicID?
    /// The lowest channel that has the section (docs/channels.md).
    public let channel: HelpChannel
    /// Whether the browser app draws it.
    public let web: Bool
    /// Whether the iPhone app draws it.
    public let phone: Bool

    public init(id: String, title: String, lead: String, footer: [String] = [],
                help: HelpTopicID? = nil, channel: HelpChannel = .release,
                web: Bool = false, phone: Bool = true) {
        self.id = id
        self.title = title
        self.lead = lead
        self.footer = footer
        self.help = help
        self.channel = channel
        self.web = web
        self.phone = phone
    }
}

/// **One wording per setting, wherever the setting is offered.**
///
/// The new-sessions notification is offered twice — as a switch in Settings, and once per
/// install as an alert the app raises by itself the moment an intervals.icu key has been
/// proved (`SessionStore.askAboutNewActivitiesIfNeeded`). It is the same feature, so it is
/// the same sentence. Everything else here arrived on 20 September 2026, when the browser
/// stopped writing its own Settings text and started reading the phone's.
public enum SettingsCopy {

    // MARK: - The notification switch, which is offered on two screens

    /// The switch, and the alert's title in the affirmative.
    public static let notifyToggle = "Notify on new sessions from intervals.icu"

    /// What the switch does, in one paragraph. Used verbatim as the one-time offer's
    /// message, which is what "with the switch's own explanation" means.
    public static let notifyExplanation =
        "While the phone is idle, CleanJibe asks intervals.icu for new activity.\n\n"
        + "It looks for windsurf, wing, kite, surf and SUP, from any watch that syncs "
        + "there.\n\n"
        + "You hear about the ones that are not in your library yet.\n\n"
        + "The session is downloaded and analysed in the background, so tapping the "
        + "notification usually opens a finished analysis."

    // MARK: - The sections, in the order SettingsView draws them

    public static let sections: [SettingsSectionCopy] = [
        SettingsSectionCopy(
            id: "icu",
            title: "intervals.icu",
            lead: "Your sessions arrive by themselves, from any watch that syncs there.",
            footer: [
                "CleanJibe takes the original FIT of every windsurf, wing, kite, surf and "
                + "SUP activity in your intervals.icu account. It goes two years back.",
                "Activities already in the library are never downloaded again.",
            ],
            help: .icuSetup, web: true),

        SettingsSectionCopy(
            id: "strava",
            title: "Strava",
            lead: "Import what you already ride with. CleanJibe only ever reads it.",
            footer: [
                "Strava opens, you say yes, and CleanJibe can list your activities on the "
                + "Import screen.",
                "CleanJibe only reads your Strava account. It never writes, renames or "
                + "posts anything.",
                "A session imported this way is analysed from your track alone, so its "
                + "speed records are marked uncertified.",
                "Strava lets a new app connect a limited number of riders. Connecting is "
                + "refused while CleanJibe is full.",
                "That says nothing about your account.",
            ],
            help: .stravaImport, web: true),

        SettingsSectionCopy(
            id: "deleted",
            title: "Deleted sessions",
            lead: "Put back a session you deleted.",
            footer: [
                "Sessions you deleted stay deleted. Every sync of intervals.icu leaves "
                + "them alone, by hand or in the background.",
                "Restoring forgets that. The next sync brings back every one of them that "
                + "is still on intervals.icu.",
            ],
            help: .libraryBackup, web: true),

        SettingsSectionCopy(
            id: "notifications",
            title: "Notifications",
            lead: "Hear about a new session while the phone is idle.",
            footer: [notifyExplanation],
            help: .notifications),

        SettingsSectionCopy(
            id: "analysis",
            title: "Analysis",
            lead: "Say which way your turns usually go, so a flat day still reads right.",
            help: .turnTypes),

        SettingsSectionCopy(
            id: "sessionList",
            title: "Session list",
            lead: "Draw the water behind each row's track.",
            footer: [
                "Each row draws its track over a map of the water it was ridden on. The "
                + "map style is the one your session maps use.",
            ]),

        SettingsSectionCopy(
            id: "rowShows",
            title: "Row shows",
            lead: "Pick the three numbers you read your library by.",
            footer: [
                "Each row carries three numbers, each with its own word under it.",
            ]),

        SettingsSectionCopy(
            id: "units",
            title: "Units",
            lead: "Read speeds in knots or in km/h.",
            footer: [
                "Speeds are read in knots by the speedsurfing world. Pick km/h if that is "
                + "the number you think in.",
            ],
            help: .speedRecords, web: true),

        // Right under Units, because it is the other question about how a speed reads.
        SettingsSectionCopy(
            id: "speedRecords",
            title: "Speed records",
            lead: "Choose whether records from tracks without measured speed count.",
            footer: [
                "Verified means your watch measured the speed with Doppler.",
                "Unverified means CleanJibe worked it out from positions. That reads high.",
                "Prefer verified fills a row with an unverified record only when no "
                + "verified one exists.",
            ],
            help: .verifiedRecords, web: true),

        SettingsSectionCopy(
            id: "storage",
            title: "Storage",
            lead: "What the library costs, and the way to analyse it all again.",
            help: .engineVersion),

        SettingsSectionCopy(
            id: "backup",
            title: "Library backup",
            lead: "One file that holds every session and everything you typed on it.",
            footer: [
                "Setting up a new iPhone from this one carries your library across by "
                + "itself, and so does an iCloud backup.",
                "This is for the case neither covers: a phone set up as new, or the app "
                + "deleted and installed again.",
                "The file holds every recording you have imported and what nothing else "
                + "can bring back.",
                "That is session names, captions, riders, gear, spot names, and the "
                + "sessions you deleted on purpose.",
            ],
            help: .libraryBackup),

        SettingsSectionCopy(
            id: "data",
            title: "Your data",
            lead: "What this browser holds, a copy you keep, and the way to wipe it.",
            footer: [
                "Your saved sessions live in this browser's own private storage.",
                "They are not synced, not backed up and not visible to any other site.",
                "Clearing this site's data, or using a private window, deletes them.",
                "Download all gives you one zip. Restore from a backup reads that same "
                + "file back.",
            ],
            help: .libraryBackup, web: true, phone: false),

        SettingsSectionCopy(
            id: "about",
            title: "About",
            lead: "What is running here, and where the privacy policy is.",
            footer: ["Wind is estimated on this device from your track."],
            help: .privacy, web: true),

        SettingsSectionCopy(
            id: "whatsNew",
            title: "What's new",
            lead: "The release notes, newest first.",
            help: .whatsNew, web: true, phone: false),
    ]

    /// One section by id. Trapping is deliberate: the ids are written in this file and read
    /// from it, so a miss is a typo rather than a state a shipped app can reach.
    public static func section(_ id: String) -> SettingsSectionCopy {
        guard let found = sections.first(where: { $0.id == id }) else {
            preconditionFailure("no settings section \(id)")
        }
        return found
    }

    /// The phone's footer, as one string with a blank line between the paragraphs — the
    /// shape SwiftUI's `Section(footer:)` has always been handed.
    public static func footer(_ id: String) -> String {
        section(id).footer.joined(separator: "\n\n")
    }
}
