import Foundation

/// **The app's one menu, as data** (docs/review-checklist.md, pattern M).
///
/// Six rows in the order a rider meets the app: what it is, what else there is of it, how
/// to start it, then the two screens he comes back to — the switches and the reference —
/// and last the way to reach a human. The divider falls before *Settings*, which is where
/// "reading about it" ends and "operating it" begins.
///
/// *The CleanJibe family* sits directly under *What CleanJibe does* because it is the
/// second half of that question: what this is, and what else there is of it. A rider who
/// met one of the three apps had no way inside it of learning that the other two exist
/// (Jan, 23 September 2026).
///
/// It is here rather than in the app for the ordinary reason: it is copy, and one order on
/// four tab roots is a rule a test can hold (`AppMenuRowsTests`). The app draws the rows and
/// decides what each one opens.
public enum AppMenuRow: String, CaseIterable, Sendable, Identifiable {

    /// The welcome screen again.
    case whatItDoes
    /// The three apps and how a session travels between them (`CleanJibeFamily`).
    case family
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
        .whatItDoes, .family, .gettingStarted, .settings, .help, .support,
    ]

    public var title: String {
        switch self {
        case .whatItDoes: "What CleanJibe does"
        case .family: CleanJibeFamily.title
        case .gettingStarted: "Getting started"
        case .settings: "Settings"
        case .help: "Help"
        case .support: FeedbackDoors.menuRow
        }
    }

    public var symbolName: String {
        switch self {
        case .whatItDoes: "hand.wave"
        case .family: "square.stack.3d.up"
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
