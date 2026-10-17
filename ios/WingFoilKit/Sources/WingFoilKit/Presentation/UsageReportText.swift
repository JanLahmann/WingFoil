import Foundation

/// **The usage statistics a feedback mail can carry** (docs/channels.md, "What the usage
/// report counts"; docs/presentation/status-feedback-start-widgets-ipad.md, "Feedback and
/// usage, one mail").
///
/// Until 17 Oct 2026 this was a mail of its own, the beta's "usage report", with its own
/// sheet and subject beside the feedback mail. Jan: one mail, one sheet, in every channel,
/// because asking riders what works is how a community-driven app decides what ships. So the
/// feedback sheet carries a *Usage statistics* choice, and the counters ride under the facts
/// of the one mail (`FeedbackReport.body(…usage:)`). Extended by default in the beta and dev,
/// Normal in the App Store build.
///
/// Composed here rather than in the app so the suite reads every line a rider sends.
public enum UsageReportText {

    /// The heading over the counters in the mail, and the sheet's section.
    public static let heading = "Usage statistics"

    /// The sentence between the facts and the counters.
    public static let separator =
        "Below is what the app counts on this phone. It shows which features work. "
        + Copy.deleteAnyLine

    /// The sheet's footer under the choice.
    public static let choiceFooter =
        "Counts of what you used, what worked and what failed, kept on this phone. "
        + "You see every line in the mail and can delete it."

    /// How much of the counters the mail carries.
    public enum Choice: String, CaseIterable, Identifiable, Sendable {
        case off, normal, extended

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .off: "Off"
            case .normal: UsageCounters.ReportLayout.normal.label
            case .extended: UsageCounters.ReportLayout.extended.label
            }
        }

        public var layout: UsageCounters.ReportLayout? {
            switch self {
            case .off: nil
            case .normal: .normal
            case .extended: .extended
            }
        }
    }

    /// **Extended in the beta and dev, Normal in the App Store build** (Jan, 17 Oct 2026). A
    /// tester's mail is evidence for a release gate and wants the dates and the last error;
    /// a release rider's wants one line per feature.
    public static func defaultChoice(for channel: HelpChannel) -> Choice {
        channel == .release ? .normal : .extended
    }

    /// The counters, as they ride in a mail.
    public struct Attached: Sendable {
        public var counters: UsageCounters
        public var layout: UsageCounters.ReportLayout
        public var now: Date
        public var timeZone: TimeZone

        public init(counters: UsageCounters, layout: UsageCounters.ReportLayout,
                    now: Date = Date(), timeZone: TimeZone = .current) {
            self.counters = counters
            self.layout = layout
            self.now = now
            self.timeZone = timeZone
        }
    }

    /// The block under the facts: the heading, the sentence, the counters. The build and the
    /// phone are on the counters' first line in both layouts: a tally with no build beside it
    /// cannot gate a release.
    static func block(_ usage: Attached, facts: FeedbackFacts) -> [String] {
        [heading + ":", separator, "",
         usage.counters.report(appVersion: facts.app.version + " (" + facts.app.build + ")",
                               device: facts.phone.described, channel: facts.app.channel,
                               layout: usage.layout, now: usage.now,
                               timeZone: usage.timeZone),
         ""]
    }
}
