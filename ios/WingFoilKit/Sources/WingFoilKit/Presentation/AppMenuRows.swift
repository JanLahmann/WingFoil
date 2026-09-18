import Foundation

/// **The app's one menu, as data** (docs/review-checklist.md, pattern M).
///
/// Five rows in the order a rider meets the app: what it is, how to start it, then the two
/// screens he comes back to — the switches and the reference — and last the way to reach a
/// human. The divider falls before *Settings*, which is where "reading about it" ends and
/// "operating it" begins.
///
/// It is here rather than in the app for the ordinary reason: it is copy, and one order on
/// four tab roots is a rule a test can hold (`AppMenuRowsTests`). The app draws the rows and
/// decides what each one opens.
public enum AppMenuRow: String, CaseIterable, Sendable, Identifiable {

    /// The welcome screen again.
    case whatItDoes
    /// `HelpTopicID.gettingStarted`.
    case gettingStarted
    case settings
    /// The Help index.
    case help
    /// The composer, `FeedbackDoors.menuRow`.
    case support

    public var id: String { rawValue }

    /// The order, once. Nothing reads `allCases` for it.
    public static let ordered: [AppMenuRow] = [
        .whatItDoes, .gettingStarted, .settings, .help, .support,
    ]

    public var title: String {
        switch self {
        case .whatItDoes: "What CleanJibe does"
        case .gettingStarted: "Getting started"
        case .settings: "Settings"
        case .help: "Help"
        case .support: FeedbackDoors.menuRow
        }
    }

    public var symbolName: String {
        switch self {
        case .whatItDoes: "hand.wave"
        case .gettingStarted: "book"
        case .settings: "gearshape"
        case .help: "questionmark.circle"
        case .support: "envelope"
        }
    }

    /// Whether a separator is drawn above this row. One divider, and it falls where reading
    /// ends and operating begins.
    public var opensAfterDivider: Bool { self == .settings }
}
