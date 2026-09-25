import Foundation

/// **The beta's usage report, as a mail** (docs/channels.md, "What the usage report
/// counts"; docs/presentation/status-feedback-start-widgets-ipad.md, "The beta's usage
/// report").
///
/// The rider's own words first, under "Your feedback", then the rule and the sentence that
/// says what the rest is, then the same App, Phone, Watch and Library blocks every feedback
/// mail carries, then the counters. The build and the phone are in the App and Phone
/// blocks and again on the counters' first line, in both layouts: a tally with no build
/// beside it cannot gate a release.
///
/// Composed here rather than in the app so the suite reads every line a tester sends.
public enum UsageReportText {

    /// One subject for both doors, the library's card and Settings → Beta, so a mailbox
    /// sorted by subject has one thread of them.
    public static let subject = Branding.appName + " beta usage report"

    /// The heading over the rider's own words, and the sheet's first section.
    public static let feedbackHeading = "Your feedback"

    /// The sheet's placeholder for it.
    public static let feedbackPrompt = "What works, what does not, what you miss"

    /// The sentence between the rider's half and the counters.
    public static let separator =
        "Below is what the beta counts on this phone. It shows which features work. "
        + Copy.deleteAnyLine

    /// The sheet's footer under the layout switch.
    public static let layoutFooter =
        "Normal gives one line per feature you used. Extended adds dates and the last error."

    public static func body(facts: FeedbackFacts, feedback: String, counters: UsageCounters,
                            layout: UsageCounters.ReportLayout,
                            now: Date = Date(), timeZone: TimeZone = .current) -> String {
        var out: [String] = [feedbackHeading + ":"]
        let words = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        out.append(words)
        out.append("")
        out.append(FeedbackReport.Separator.rule)
        out.append(separator)
        out.append("")
        out += FeedbackReport.blocks(facts)
        out.append(counters.report(appVersion: facts.app.version + " (" + facts.app.build + ")",
                                   device: facts.phone.described, channel: facts.app.channel,
                                   layout: layout, now: now, timeZone: timeZone))
        out.append("")
        out.append("sent from " + Branding.appName)
        return out.joined(separator: "\n")
    }

    /// The `mailto:` fallback, escaped the way `FeedbackReport.mailtoURL` escapes: `&`,
    /// `=`, `+` and `?` removed from the allowed set, so a body carrying one is not cut short.
    public static func mailtoURL(subject: String, body: String) -> URL? {
        let allowed = CharacterSet.urlQueryAllowed
            .subtracting(CharacterSet(charactersIn: "&=+?"))
        guard let subject = subject.addingPercentEncoding(withAllowedCharacters: allowed),
              let body = body.addingPercentEncoding(withAllowedCharacters: allowed)
        else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = FeedbackReport.recipient
        components.percentEncodedQuery = "subject=\(subject)&body=\(body)"
        return components.url
    }
}
