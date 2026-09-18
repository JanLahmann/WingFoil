import Foundation

/// **The ways a session gets in, in the one order every surface prints them**
/// (docs/review-checklist.md, pattern J).
///
/// The order is `docs/guide/getting-started.json` → `GettingStartedGuide.routes`: Garmin
/// through intervals.icu, the CleanJibe Apple Watch app, Apple's own Workout app, any file,
/// Strava. The Garmin export ZIP is not a route in that guide — it is a backfill, not a way
/// to record an afternoon — so it is appended last and stays last. `ImportDoorsTests` holds
/// the two lists against each other, per channel, so the Import screen cannot drift from the
/// guide the website and the help topic print.
///
/// **Every door is visible in a channel that has it** (pattern E/G). What a rider has or has
/// not done before changes a door's label and its footer, never whether the row is drawn: a
/// screen that hides the Strava row until a key exists answers "where is Strava" with
/// silence. The channel is the one thing that removes a door, because a build without the
/// entitlement genuinely has no door (docs/channels.md).
///
/// **A footer says what you get, in one line** (pattern K). The *how* is the help topic each
/// door names, opened from the footer itself rather than described in it (pattern B). The
/// prose that used to spell out each mechanism on the Import screen lives in those topics.
public enum ImportDoor: String, CaseIterable, Sendable, Identifiable {

    /// Garmin, and every other watch that syncs to intervals.icu.
    case icu
    /// The CleanJibe Apple Watch app. Nothing to import: the session crosses by itself.
    case appleWatchApp
    /// A workout Apple's own Workout app wrote into Health (ADR-017).
    case appleHealth
    /// One file the rider picks: FIT everywhere, GPX and TCX in the beta.
    case file
    /// The second cloud source (ADR-023).
    case strava
    /// Garmin's GDPR "Export Your Data" archive. **Last, always.**
    case garminZip

    public var id: String { rawValue }

    /// The order, once, here. Nothing reads `allCases` for it: a case added in the wrong
    /// place would silently reorder the screen.
    private static let order: [ImportDoor] = [
        .icu, .appleWatchApp, .appleHealth, .file, .strava, .garminZip,
    ]

    /// **The lowest channel that has this door** (docs/channels.md), the way
    /// `HelpTopic.channel` means it.
    public var channel: HelpChannel {
        switch self {
        case .icu, .file, .strava: .release
        case .appleWatchApp, .appleHealth, .garminZip: .beta
        }
    }

    /// The doors a build on `channel` draws, in order.
    public static func ordered(channel: HelpChannel) -> [ImportDoor] {
        order.filter { channel.has($0.channel) }
    }

    /// The `GettingStartedGuide.routes` id this door is the same way in as, or nil where the
    /// guide has no route for it. Only the ZIP has none.
    public var guideRouteID: String? {
        switch self {
        case .icu: "garmin"
        case .appleWatchApp: "appleWatchApp"
        case .appleHealth: "appleWorkoutApp"
        case .file: "fit"
        case .strava: "strava"
        case .garminZip: nil
        }
    }

    /// The section header: the service, or the kind of thing. Never the action, which is
    /// the row's own word.
    public var sectionTitle: String {
        switch self {
        case .icu: "intervals.icu"
        case .appleWatchApp: "Apple Watch"
        case .appleHealth: "Apple Health"
        case .file: "Files"
        case .strava: "Strava"
        case .garminZip: "Full history"
        }
    }

    /// What the row does, in the rider's words. `nil` where the door has no action at all:
    /// the CleanJibe watch app delivers on its own, so its section is a statement and a way
    /// to the page that explains it.
    public func actionTitle(channel: HelpChannel) -> String? {
        switch self {
        case .icu: "Sync intervals.icu"
        case .appleWatchApp: nil
        case .appleHealth: "Import from Health…"
        case .file: channel.has(.beta) ? "FIT, GPX, TCX or ZIP…" : "FIT or ZIP…"
        case .strava: "Import from Strava…"
        case .garminZip: "Garmin export ZIP…"
        }
    }

    /// The SF Symbol on the row.
    public var symbolName: String {
        switch self {
        case .icu: "arrow.triangle.2.circlepath"
        case .appleWatchApp: "applewatch"
        case .appleHealth: "heart.text.square"
        case .file: "doc.badge.plus"
        case .strava: "figure.wave"
        case .garminZip: "shippingbox"
        }
    }

    /// The recording classes this door yields (docs/copy/recording-classes.json), as the
    /// letter and the thing — the label a rider matches against the table he read on
    /// cleanjibe.org (pattern H). A label, not a sentence: the *line* about what each class
    /// costs is the help topic's.
    public func recordingClasses(channel: HelpChannel) -> [RecordingClass] {
        switch self {
        case .icu: [.a, .b]
        case .appleWatchApp: [.bPlus]
        case .appleHealth: [.b]
        case .file: channel.has(.beta) ? [.a, .b, .c] : [.a, .b]
        case .strava: [.c]
        case .garminZip: [.a, .b]
        }
    }

    /// "Class A · Garmin watch app or Class B · any speed-certified file".
    public func classLabel(channel: HelpChannel) -> String {
        let names = recordingClasses(channel: channel).map(\.name)
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " or " + names[names.count - 1]
    }

    /// **What you get, in one line** (pattern K, and 25 words). Not how to get it: that is
    /// `helpTopic`, one tap under this sentence.
    public func footer(channel: HelpChannel) -> String {
        switch self {
        case .icu:
            "Every windsurf, wing, kite, surf and SUP activity in your intervals.icu "
            + "account. The original file from the watch comes with it."
        case .appleWatchApp:
            "Sessions you record with CleanJibe on the Apple Watch arrive by themselves. "
            + "Nothing to import here."
        case .appleHealth:
            "Workouts recorded with Apple's own Workout app. Speed comes off the watch, "
            + "so those records certify."
        case .file:
            channel.has(.beta)
            ? "One FIT, GPX, TCX or ZIP from any watch. AirDrop and the share sheet land "
              + "here too."
            : "One FIT or ZIP from any watch. AirDrop and the share sheet land here too."
        case .strava:
            "Sessions you pick from your Strava account. Positions only, so records are "
            + "uncertified. " + Copy.stravaFall
        case .garminZip:
            "Every original FIT your Garmin account holds. Ask for the ZIP under "
            + "Account → Export Your Data. Duplicates are skipped."
        }
    }

    /// The topic that answers *how*. Every one of them already exists: the Import screen
    /// links to the help, it does not grow a second copy of it.
    public var helpTopic: HelpTopicID {
        switch self {
        case .icu: .icuSetup
        case .appleWatchApp: .appleWatchApp
        case .appleHealth: .appleWorkoutApp
        case .file, .garminZip: .shareFromWatchApp
        case .strava: .stravaImport
        }
    }

    /// The one line a door shows **instead of its action** while it is not set up yet, with
    /// the Settings section it is set up in. The row stays; only its label changes (pattern
    /// E/G). Nil for a door that needs no account.
    public var settingsSection: String? {
        switch self {
        case .icu: "intervals.icu"
        case .strava: "Strava"
        case .appleWatchApp, .appleHealth, .file, .garminZip: nil
        }
    }

    /// "Set up in Settings → Strava".
    public var setUpTitle: String? {
        settingsSection.map { "Set up in Settings → " + $0 }
    }

    /// What a build carrying no keys for this source says where the action would be. One
    /// line, and the same one Settings gives, so the two screens do not send a rider back
    /// and forth over it.
    public static let unavailableInBuild = "Not available in this build"

    /// What a device with no HealthKit says in the same slot.
    public static let unavailableOnDevice = "Not available on this iPhone"
}
