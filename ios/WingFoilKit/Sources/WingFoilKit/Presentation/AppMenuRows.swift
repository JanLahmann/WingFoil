import Foundation

/// **The app's one menu, as data** (docs/review-checklist.md, pattern M).
///
/// Six rows in the order a rider meets the app: what it is, how to start it, then the two
/// screens he comes back to — the switches and the reference — and last the two ways to
/// reach us: a mail, and the beta. The divider falls before *Settings*, which is where
/// "reading about it" ends and "operating it" begins.
///
/// *The CleanJibe family* had a row of its own under *What CleanJibe does* from
/// 23 September 2026; since 25 September it is a section of that page (Jan, F4), so the
/// row went. *Join the beta* sits next to *Support & ideas* (Jan's plan of 24 September,
/// section 6): both are how a rider takes part in what the app becomes.
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
    /// The Beta page (`BetaGuide`): how to join, or, in the beta, what the rider is in.
    case beta

    public var id: String { rawValue }

    /// The order, once. Nothing reads `allCases` for it.
    public static let ordered: [AppMenuRow] = [
        .whatItDoes, .gettingStarted, .settings, .help, .support, .beta,
    ]

    public var title: String {
        switch self {
        case .whatItDoes: "What CleanJibe does"
        case .gettingStarted: "Getting started"
        case .settings: "Settings"
        case .help: "Help"
        case .support: FeedbackDoors.menuRow
        case .beta: "Join the beta"
        }
    }

    public var symbolName: String {
        switch self {
        case .whatItDoes: "hand.wave"
        case .gettingStarted: "book"
        case .settings: "gearshape"
        case .help: "questionmark.circle"
        case .support: "envelope"
        case .beta: "testtube.2"
        }
    }

    /// The title a build on `channel` shows. Only the beta row differs: a rider already in
    /// the beta is not asked to join it, and the row names where he is instead
    /// (`BetaGuide.title(for:)`). The website is not a channel and shows `title`.
    public func title(in channel: HelpChannel) -> String {
        self == .beta ? BetaGuide.title(for: channel) : title
    }

    /// Whether a separator is drawn above this row. One divider, and it falls where reading
    /// ends and operating begins.
    public var opensAfterDivider: Bool { self == .settings }
}
