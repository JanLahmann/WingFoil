import Foundation

/// **Every feature the beta's usage report counts** — the list docs/channels.md prints under
/// "What the usage report counts", and the one `UsageCountersTests` holds that table to.
///
/// Jan's rule (F16, 24 Sep 2026): a feature enters the release only after testers have used
/// it *successfully*. So the list is the channel file's feature list cut into the pieces a
/// tester actually does, one row each, and every row counts what was tried, what worked and
/// what failed (`UsageCounters.Tally`). "Used" and "works" are two different numbers.
///
/// The order is the report's order: getting a session in, the watches, the analysis, reading
/// it, sharing it, the library's machinery, Settings, and the beta's own furniture.
extension UsageCounters {

    /// The report's headings, in order.
    public enum Group: String, CaseIterable, Sendable {
        case app, sources, watch, analysis, reading, share, library, settings, feedback

        public var title: String {
            switch self {
            case .app: "App"
            case .sources: "Sources"
            case .watch: "Watch"
            case .analysis: "Analysis"
            case .reading: "Reading"
            case .share: "Share"
            case .library: "Library"
            case .settings: "Settings"
            case .feedback: "Feedback"
            }
        }
    }

    /// A closed set rather than free-form strings: a counter named at the call site is a
    /// counter a refactor renames, and the renamed one silently starts a second tally.
    ///
    /// **The raw values are storage keys.** The first seventeen are the counters of
    /// `usage.counters.v1` from before the tallies existed (builds up to 107), kept verbatim
    /// so an older blob decodes into the same rows. A new case gets a new key. A retired
    /// case keeps its key out of use for good.
    public enum Feature: String, Codable, CaseIterable, Sendable {
        // App
        case appOpen
        // Sources
        case importIcu
        case icuBackground
        case stravaConnected
        case importStrava
        case importHealth
        case healthAutoImport
        case importFile
        case importShareSheet
        case importZip
        case watchTransfer
        // Watch
        case mapToWatch
        case windToWatch
        case chooseWatch
        case appleWatchRecording
        // Analysis
        case sessionOpened
        case reanalysis
        case tuning
        case windsurfMode
        case turnDirection
        // Reading
        case turnPage
        case flightEndPage
        case replay
        case recordReplay
        case mapStyle
        case fullScreenMap
        case filters
        case grouping
        case sessionPaging
        case trends
        case records
        case periods
        // Share
        case shareCard
        case clipExported
        case videoExported
        case fitShare
        case sendToDeveloper
        case periodShare
        // Library
        case rename
        case riderAssign
        case gearSpots
        case deleteSession
        case restoreDeleted
        case backupMade
        case backupRestored
        case iCloudSync
        case startOver
        // Settings
        case settingsOpened
        case units
        case speedRecordPolicy
        case rowMetrics
        case notifications
        case healthExport
        // Feedback
        case feedbackMail
        case usageReport
        case mostWanted

        public var group: Group {
            switch self {
            case .appOpen: .app
            case .importIcu, .icuBackground, .stravaConnected, .importStrava, .importHealth,
                 .healthAutoImport, .importFile, .importShareSheet, .importZip,
                 .watchTransfer: .sources
            case .mapToWatch, .windToWatch, .chooseWatch, .appleWatchRecording: .watch
            case .sessionOpened, .reanalysis, .tuning, .windsurfMode, .turnDirection: .analysis
            case .turnPage, .flightEndPage, .replay, .recordReplay, .mapStyle, .fullScreenMap,
                 .filters, .grouping, .sessionPaging, .trends, .records, .periods: .reading
            case .shareCard, .clipExported, .videoExported, .fitShare, .sendToDeveloper,
                 .periodShare: .share
            case .rename, .riderAssign, .gearSpots, .deleteSession, .restoreDeleted,
                 .backupMade, .backupRestored, .iCloudSync, .startOver: .library
            case .settingsOpened, .units, .speedRecordPolicy, .rowMetrics, .notifications,
                 .healthExport: .settings
            case .feedbackMail, .usageReport, .mostWanted: .feedback
            }
        }

        /// The words the mail prints. The reader is Jan; the writer is a tester who has to
        /// be able to tell whether a line describes something he did.
        public var label: String {
            switch self {
            case .appOpen: "App opened"
            case .importIcu: "intervals.icu sync"
            case .icuBackground: "intervals.icu in the background"
            case .stravaConnected: "Strava connect"
            case .importStrava: "Strava import"
            case .importHealth: "Apple Health import"
            case .healthAutoImport: "Apple Health auto-import"
            case .importFile: "File import"
            case .importShareSheet: "Share-sheet import"
            case .importZip: "Garmin ZIP import"
            case .watchTransfer: "Direct watch transfer"
            case .mapToWatch: "Send map to watch"
            case .windToWatch: "Send wind to watch"
            case .chooseWatch: "Choose or forget a watch"
            case .appleWatchRecording: "Apple Watch recording"
            case .sessionOpened: "Open a session"
            case .reanalysis: "Re-run analysis"
            case .tuning: "Tuning"
            case .windsurfMode: "Windsurf mode"
            case .turnDirection: "Turn-direction setting"
            case .turnPage: "Turn detail"
            case .flightEndPage: "Flight-end detail"
            case .replay: "Replay"
            case .recordReplay: "Record replay"
            case .mapStyle: "Map styles"
            case .fullScreenMap: "Full-screen map"
            case .filters: "Filters"
            case .grouping: "Month, year or spot grouping"
            case .sessionPaging: "Session paging"
            case .trends: "Trends"
            case .records: "Records"
            case .periods: "Periods"
            case .shareCard: "Share card"
            case .clipExported: "Replay clip saved"
            case .videoExported: "Session video"
            case .fitShare: "FIT share"
            case .sendToDeveloper: "Send session to us"
            case .periodShare: "Period share"
            case .rename: "Rename or caption"
            case .riderAssign: "Assign a rider"
            case .gearSpots: "Gear and spots"
            case .deleteSession: "Delete a session"
            case .restoreDeleted: "Restore deleted sessions"
            case .backupMade: "Backup"
            case .backupRestored: "Restore from backup"
            case .iCloudSync: "iCloud sync"
            case .startOver: "Start over"
            case .settingsOpened: "Settings opened"
            case .units: "Units"
            case .speedRecordPolicy: "Speed-record rule"
            case .rowMetrics: "Row metrics"
            case .notifications: "Notifications delivered"
            case .healthExport: "Apple Health export"
            case .feedbackMail: "Feedback mail"
            case .usageReport: "Usage report"
            case .mostWanted: "Most-wanted ticks"
            }
        }

        /// The lowest channel whose build has this door (docs/channels.md, "Feature by
        /// channel"). The report names a door as "not used yet" only in a build that has it,
        /// so a beta phone is never asked about the dev-only Garmin link.
        public var channel: HelpChannel {
            switch self {
            case .importHealth, .healthAutoImport, .appleWatchRecording, .filters, .grouping,
                 .videoExported, .sendToDeveloper, .startOver, .healthExport, .usageReport:
                .beta
            case .watchTransfer, .mapToWatch, .windToWatch, .chooseWatch, .tuning,
                 .windsurfMode, .iCloudSync:
                .dev
            default:
                .release
            }
        }
    }
}
