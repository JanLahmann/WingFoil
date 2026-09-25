import Foundation
import Testing
@testable import WingFoilKit

/// **The beta's usage report** (docs/channels.md, docs/presentation/status-feedback-start-widgets-ipad.md "The beta's usage
/// report"). Every assertion here is about a line a rider reads before he sends it: nothing
/// in this type is allowed to be a surprise in his outbox.
@Suite struct UsageCountersTests {

    /// A fixed clock, in a fixed zone, so "13 Sep" means 13 September everywhere the suite
    /// runs. `DateFormatter` in the type under test is pinned to `en_US_POSIX` for the same
    /// reason — a German phone must not write a different report.
    private let zone = TimeZone(identifier: "Europe/Berlin")!

    private func date(_ day: Int, _ month: Int = 9, _ hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = month
        components.day = day
        components.hour = hour
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: components)!
    }

    private func counters(from day: Int = 1, month: Int = 8) -> UsageCounters {
        UsageCounters(firstLaunch: date(day, month))
    }

    // MARK: - Counting

    @Test func aFeatureCountsUpAndRemembersWhenItWasLastUsed() {
        var usage = counters()
        usage.record(.shareCard, at: date(11), timeZone: zone)
        usage.record(.shareCard, at: date(13), timeZone: zone)
        #expect(usage.count(.shareCard) == 2)
        #expect(usage.lastUse(.shareCard) == date(13))
        #expect(usage.count(.videoExported) == 0)
        #expect(usage.lastUse(.videoExported) == nil)
    }

    /// A batch of nine sessions through one door is nine sessions, not one import — the
    /// whole point of counting the doors is knowing how much comes through each.
    @Test func anImportCountsEverySessionItBrought() {
        var usage = counters()
        usage.record(.importZip, times: 9, at: date(12), timeZone: zone)
        #expect(usage.count(.importZip) == 9)
        #expect(usage.tally(.importZip).attempted == 9)
    }

    @Test func recordingNothingChangesNothing() {
        var usage = counters()
        usage.record(.importIcu, times: 0, at: date(12), timeZone: zone)
        #expect(usage.count(.importIcu) == 0)
        #expect(usage.activeDays == 0)
    }

    /// A phone whose clock has just been pulled back must not make "last used" travel
    /// backwards through the report.
    @Test func theClockGoingBackwardsDoesNotMoveLastUsed() {
        var usage = counters()
        usage.record(.sessionOpened, at: date(13), timeZone: zone)
        usage.record(.sessionOpened, at: date(11), timeZone: zone)
        #expect(usage.lastUse(.sessionOpened) == date(13))
        #expect(usage.count(.sessionOpened) == 2)
    }

    @Test func daysActiveCountsDaysAndNotUses() {
        var usage = counters()
        usage.record(.appOpen, at: date(11, 9, 7), timeZone: zone)
        usage.record(.sessionOpened, at: date(11, 9, 19), timeZone: zone)
        usage.record(.appOpen, at: date(12), timeZone: zone)
        usage.record(.appOpen, at: date(11, 9, 21), timeZone: zone)  // back to the 11th
        #expect(usage.activeDays == 2)
    }

    // MARK: - Failures

    /// Twenty identical sync failures are one line with a 20 beside it, not twenty lines
    /// that bury every other thing that went wrong on this phone.
    @Test func theSameFailureIsOneLineWithACount() {
        var usage = counters()
        for day in 10...13 {
            usage.recordFailure("Could not reach intervals.icu", at: date(day),
                                timeZone: zone)
        }
        #expect(usage.failures.count == 1)
        #expect(usage.failures[0].count == 4)
        #expect(usage.failures[0].last == date(13))
    }

    @Test func theNewestFailureIsFirst() {
        var usage = counters()
        usage.recordFailure("Could not write the backup", at: date(10), timeZone: zone)
        usage.recordFailure("Delete failed", at: date(11), timeZone: zone)
        #expect(usage.failures.map(\.message) == ["Delete failed", "Could not write the backup"])
        // …and a repeat of the older one brings it back to the front, because the report
        // reads "what goes wrong here, most recently first".
        usage.recordFailure("Could not write the backup", at: date(12), timeZone: zone)
        #expect(usage.failures.map(\.message) == ["Could not write the backup", "Delete failed"])
    }

    @Test func onlyTheLastTwentyDistinctFailuresAreKept() {
        var usage = counters()
        for n in 1...25 {
            usage.recordFailure("Failure number \(n)", at: date(12), timeZone: zone)
        }
        #expect(usage.failures.count == UsageCounters.failureLimit)
        #expect(usage.failures.first?.message == "Failure number 25")
        #expect(usage.failures.last?.message == "Failure number 6")
    }

    /// An import summary lists one line per file it could not read; a mail wants one entry
    /// per thing that went wrong, not a paragraph inside a bullet.
    @Test func aMultiLineFailureBecomesOneLine() {
        var usage = counters()
        usage.recordFailure("Could not read a.fit\nCould not read b.fit", at: date(12),
                            timeZone: zone)
        #expect(usage.failures[0].message == "Could not read a.fit · Could not read b.fit")
    }

    @Test func aRunawayFailureMessageIsTruncated() {
        var usage = counters()
        usage.recordFailure(String(repeating: "x", count: 500), at: date(12), timeZone: zone)
        #expect(usage.failures[0].message.count == UsageCounters.failureMessageLimit + 1)
        #expect(usage.failures[0].message.hasSuffix("…"))
    }

    @Test func anEmptyFailureIsNotRecorded() {
        var usage = counters()
        usage.recordFailure("   \n  ", at: date(12), timeZone: zone)
        #expect(usage.failures.isEmpty)
    }

    // MARK: - Tried, worked, failed

    @Test func aTryAndItsOutcomeAreTwoCallsAndOneAttempt() {
        var usage = counters()
        usage.attempt(.mapToWatch, at: date(12), timeZone: zone)
        usage.succeeded(.mapToWatch, at: date(12), timeZone: zone)
        usage.attempt(.mapToWatch, at: date(13), timeZone: zone)
        usage.failed(.mapToWatch, reason: "no answer", attempt: false, at: date(13),
                     timeZone: zone)
        usage.attempt(.mapToWatch, at: date(14), timeZone: zone)   // never answered
        let tally = usage.tally(.mapToWatch)
        #expect(tally.attempted == 3)
        #expect(tally.succeeded == 1)
        #expect(tally.failed == 1)
        #expect(tally.lastReason == "no answer")
        #expect(tally.firstUse == date(12))
    }

    /// The release gate's "no open failure": the newest outcome decides.
    @Test func aFailureIsOpenUntilTheFeatureWorksAgain() {
        var usage = counters()
        usage.failed(.healthExport, reason: "HKErrorDomain 5", at: date(12), timeZone: zone)
        #expect(usage.tally(.healthExport).failureIsOpen)
        usage.record(.healthExport, at: date(13), timeZone: zone)
        #expect(!usage.tally(.healthExport).failureIsOpen)
    }

    @Test func variantsAreCountedUnderTheirFeature() {
        var usage = counters()
        usage.record(.shareCard, detail: "story · lean · map", at: date(12), timeZone: zone)
        usage.record(.shareCard, detail: "story · lean · map", at: date(12), timeZone: zone)
        usage.record(.shareCard, detail: "square · complete · photo", at: date(13),
                     timeZone: zone)
        #expect(usage.tally(.shareCard).details == ["story · lean · map": 2,
                                                   "square · complete · photo": 1])
    }

    // MARK: - Reasons carry nothing personal

    private enum SampleError: Error { case notReachable, refused(path: String) }

    @Test func aSwiftErrorBecomesItsTypeAndCase() {
        let reason = UsageCounters.reason(for: SampleError.refused(path: "/Users/jan/Torbole.fit"))
        #expect(reason.hasSuffix("SampleError.refused"))
        #expect(!reason.contains("Torbole"))
        #expect(UsageCounters.reason(for: SampleError.notReachable).hasSuffix(".notReachable"))
    }

    @Test func aFoundationErrorBecomesItsDomainAndCode() {
        let error = URLError(.notConnectedToInternet,
                             userInfo: [NSURLErrorFailingURLStringErrorKey:
                                        "https://intervals.icu/athlete/i606193"])
        #expect(UsageCounters.reason(for: error) == "NSURLErrorDomain -1009")
    }

    @Test func aReasonIsShort() {
        var usage = counters()
        usage.failed(.fitShare, reason: String(repeating: "x", count: 300), at: date(12),
                     timeZone: zone)
        #expect(usage.tally(.fitShare).lastReason?.count == UsageCounters.reasonLimit + 1)
    }

    // MARK: - The report

    private func filledIn() -> UsageCounters {
        var usage = counters()
        usage.record(.appOpen, times: 87, at: date(14), timeZone: zone)
        usage.record(.importIcu, times: 38, at: date(14), timeZone: zone)
        usage.failed(.importIcu, reason: "NSURLErrorDomain -1009", at: date(12), timeZone: zone)
        usage.record(.shareCard, times: 12, detail: "story · lean · map", at: date(13),
                     timeZone: zone)
        usage.attempt(.mapToWatch, at: date(13), timeZone: zone)
        usage.recordFailure("Could not reach intervals.icu", at: date(12), timeZone: zone)
        usage.recordFailure("Could not reach intervals.icu", at: date(13), timeZone: zone)
        return usage
    }

    private func report(_ layout: UsageCounters.ReportLayout = .normal,
                        channel: HelpChannel = .dev) -> String {
        filledIn().report(appVersion: "1.1.0 (107)", device: "iPhone 17 Pro Max (iPhone18,2)",
                          channel: channel, layout: layout, now: date(14), timeZone: zone)
    }

    /// The build and the phone open the block in both layouts (F19 addendum).
    @Test func bothLayoutsOpenWithTheBuildAndThePhone() {
        for layout in UsageCounters.ReportLayout.allCases {
            let lines = report(layout).split(separator: "\n", omittingEmptySubsequences: false)
            #expect(lines[0] == "Usage and features")
            #expect(lines[1] == "  CleanJibe 1.1.0 (107) · iPhone 17 Pro Max (iPhone18,2)")
            #expect(lines[2] == "  First launch 1 Aug · 3 days active · written 14 Sep")
        }
    }

    @Test func normalIsOneLinePerUsedFeatureUnderItsGroup() {
        let text = report()
        #expect(text.contains("\n  Sources\n    intervals.icu sync ✓ 38 · ✗ 1\n"))
        #expect(text.contains("\n  Share\n    Share card ✓ 12\n"))
        // Tried and never answered: a line with nothing ticked, and no dates.
        #expect(text.contains("\n    Send map to watch ✓ 0\n"))
        #expect(!text.contains("worked "))
        #expect(!text.contains("story · lean · map"))
        #expect(!text.contains("Messages this phone showed"))
    }

    @Test func extendedAddsDatesReasonsVariantsAndMessages() {
        let text = report(.extended)
        #expect(text.contains("    intervals.icu sync ✓ 38 · ✗ 1 · first 12 Sep · "
                              + "worked 14 Sep · failed 12 Sep, NSURLErrorDomain -1009"))
        #expect(text.contains("    Send map to watch ✓ 0 · 1 without an answer · first 13 Sep"))
        #expect(text.contains("\n      story · lean · map ✓ 12"))
        #expect(text.contains("  Messages this phone showed, newest first"))
        #expect(text.contains("\n    Could not reach intervals.icu · 2 · last 13 Sep"))
    }

    /// The half of the block that decides what ships: a door nobody has opened is a door
    /// the release does not need yet (docs/channels.md, rule 1). Named once, and only for
    /// doors this build has.
    @Test func theDoorsNobodyOpenedAreNamedOnceAndOnlyWhereTheyExist() {
        let dev = report(channel: .dev)
        let line = dev.split(separator: "\n").first { $0.contains("Not used yet:") }
        #expect(line?.contains("Session video") == true)
        #expect(line?.contains("Send wind to watch") == true)
        #expect(line?.contains("Share card") == false)
        #expect(dev.components(separatedBy: "Not used yet:").count == 2)

        let beta = report(channel: .beta)
        let betaLine = beta.split(separator: "\n").first { $0.contains("Not used yet:") }
        #expect(betaLine?.contains("Session video") == true)
        #expect(betaLine?.contains("Send wind to watch") == false)
        #expect(betaLine?.contains("iCloud sync") == false)
    }

    @Test func aPhoneWithNoMessagesHasNoMessagesHeading() {
        var usage = counters()
        usage.record(.appOpen, at: date(14), timeZone: zone)
        #expect(!usage.report(appVersion: "1.1.0 (107)", device: "iPhone18,2",
                              layout: .extended, now: date(14), timeZone: zone)
            .contains("Messages"))
    }

    /// A fresh phone still produces a readable block rather than a heading with nothing
    /// under it.
    @Test func anUntouchedPhoneStillRendersABlock() {
        let text = counters(from: 14, month: 9)
            .report(appVersion: "1.1.0 (107)", device: "iPhone18,2", now: date(14),
                    timeZone: zone)
        #expect(text.hasPrefix("Usage and features\n  CleanJibe 1.1.0 (107) · iPhone18,2"))
        #expect(text.contains("0 days active"))
        #expect(text.contains("Not used yet: App opened"))
    }

    // MARK: - The mail

    private var facts: FeedbackFacts {
        FeedbackFacts(
            app: .init(version: "1.1.0", build: "107", channel: .beta, engineVersion: "0.24.0"),
            phone: .init(model: "iPhone18,2", system: "iOS 26.0", locale: "en_DE"),
            watch: .init(garminModel: nil, garminAppVersion: nil, appleWatchPaired: nil,
                         healthImport: nil, garminCrashRuns: nil),
            library: .init(sessionCount: 12, sources: []),
            session: nil, crashes: [])
    }

    @Test func theMailOpensWithTheRidersFeedback() {
        let body = UsageReportText.body(facts: facts, feedback: "  The map never arrives.\n",
                                        counters: filledIn(), layout: .normal,
                                        now: date(14), timeZone: zone)
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines[0] == "Your feedback:")
        #expect(lines[1] == "The map never arrives.")
        #expect(body.contains(UsageReportText.separator))
        // The build and the device, in the facts and in the counters.
        #expect(body.contains("CleanJibe 1.1.0 (107) · beta build"))
        #expect(body.contains("  CleanJibe 1.1.0 (107) · iPhone 17 Pro Max (iPhone18,2)"))
        #expect(body.hasSuffix("sent from CleanJibe"))
    }

    @Test func theLayoutSwitchChangesOnlyTheCounters() {
        let normal = UsageReportText.body(facts: facts, feedback: "", counters: filledIn(),
                                          layout: .normal, now: date(14), timeZone: zone)
        let extended = UsageReportText.body(facts: facts, feedback: "", counters: filledIn(),
                                            layout: .extended, now: date(14), timeZone: zone)
        #expect(!normal.contains("worked 14 Sep"))
        #expect(extended.contains("worked 14 Sep"))
        #expect(normal.hasPrefix("Your feedback:\n\n"))
    }

    // MARK: - The feature list is docs/channels.md's

    /// The table under "What the usage report counts" in docs/channels.md is this list,
    /// written by `COPY_WRITE=1 swift test --filter UsageCountersTests` and checked here.
    @Test func theFeatureListIsTheOneChannelsMdPrints() throws {
        let url = CopyContractTests.repoRoot.appendingPathComponent("docs/channels.md")
        let text = try String(contentsOf: url, encoding: .utf8)
        let begin = "<!-- usage-features:begin -->", end = "<!-- usage-features:end -->"
        let lower = try #require(text.range(of: begin), "docs/channels.md lacks \(begin)")
        let upper = try #require(text.range(of: end), "docs/channels.md lacks \(end)")
        let expected = "\n" + Self.featureTable() + "\n"
        if CopyContractTests.isWriting {
            let rewritten = text.replacingCharacters(in: lower.upperBound..<upper.lowerBound,
                                                     with: expected)
            try rewritten.write(to: url, atomically: true, encoding: .utf8)
            return
        }
        #expect(String(text[lower.upperBound..<upper.lowerBound]) == expected,
                """
                docs/channels.md's usage table is out of step with UsageCounters.Feature. \
                Regenerate it: COPY_WRITE=1 swift test --filter UsageCountersTests
                """)
    }

    static func featureTable() -> String {
        var rows = ["| group | feature | key | lowest channel |", "|---|---|---|---|"]
        for feature in UsageCounters.Feature.allCases {
            let channel: String = switch feature.channel {
            case .release: "release"
            case .beta: "beta"
            case .dev: "dev"
            }
            rows.append("| " + feature.group.title + " | " + feature.label + " | `"
                        + feature.rawValue + "` | " + channel + " |")
        }
        return rows.joined(separator: "\n")
    }

    /// The seventeen keys the blob had before the tallies must still be cases, or an older
    /// phone's counts would decode under keys nothing reads.
    @Test func theOldKeysAreStillFeatures() {
        let old = ["appOpen", "importIcu", "importFile", "importStrava", "importHealth",
                   "importShareSheet", "importZip", "sessionOpened", "turnPage", "shareCard",
                   "clipExported", "videoExported", "backupMade", "backupRestored",
                   "settingsOpened", "feedbackMail", "stravaConnected"]
        for key in old { #expect(UsageCounters.Feature(rawValue: key) != nil, "\(key)") }
    }

    // MARK: - Most wanted

    @Test func theReleaseOffersOnlyTheBetaRows() {
        #expect(MostWanted.offered(in: .release).allSatisfy { $0.channel == .beta })
        #expect(MostWanted.offered(in: .beta).count == MostWanted.all.count)
    }

    @Test func theVoteIsOneTalliableLinePerTick() {
        let vote = MostWanted.Vote(ticked: ["tuning", "appleHealth"], note: " dark mode ")
        #expect(vote.lines == ["Most wanted",
                               "  ✓ Apple Health, both ways · appleHealth",
                               "  ✓ The tuning page · tuning",
                               "  Also: dark mode",
                               ""])
        #expect(MostWanted.Vote().lines.isEmpty)
    }

    @Test func theFeedbackMailCarriesTheVoteAboveTheRule() {
        let body = FeedbackReport.body(facts, mostWanted: .init(ticked: ["gpxTcx"]))
        let vote = try? #require(body.range(of: "Most wanted\n  ✓ GPX and TCX files · gpxTcx"))
        let rule = body.range(of: FeedbackReport.Separator.rule)
        #expect(vote != nil && rule != nil && vote!.lowerBound < rule!.lowerBound)
        #expect(!FeedbackReport.body(facts).contains("Most wanted"))
    }

    // MARK: - The ask

    @Test func theAskComesAfterEveryFifthSession() {
        var usage = counters(from: 13, month: 9)
        #expect(!usage.askIsDue(now: date(14)))
        usage.sessionsSinceAsk = 4
        #expect(!usage.askIsDue(now: date(14)))
        usage.sessionsSinceAsk = 5
        #expect(usage.askIsDue(now: date(14)))
    }

    @Test func theAskComesAfterAFortnightWithNoSessionsAtAll() {
        let usage = counters(from: 1, month: 9)
        #expect(!usage.askIsDue(now: date(14)))
        #expect(usage.askIsDue(now: date(15)))
    }

    @Test func notNowBuysAFortnightOfQuiet() {
        var usage = counters(from: 13, month: 9)
        usage.sessionsSinceAsk = 9
        usage.askAnswered(now: date(14), snooze: true)
        #expect(usage.sessionsSinceAsk == 0)
        #expect(!usage.askIsDue(now: date(20)))
        #expect(!usage.askIsDue(now: date(27)))
        #expect(usage.askIsDue(now: date(28)))
    }

    /// Five more sessions during a snooze do not jump the queue: "not now" means not now.
    @Test func aSnoozeOutranksTheSessionCount() {
        var usage = counters(from: 13, month: 9)
        usage.askAnswered(now: date(14), snooze: true)
        usage.sessionsSinceAsk = 12
        #expect(!usage.askIsDue(now: date(20)))
    }

    @Test func sendingTheReportStartsTheCountAgain() {
        var usage = counters(from: 13, month: 9)
        usage.sessionsSinceAsk = 6
        usage.askAnswered(now: date(14), snooze: false)
        #expect(usage.sessionsSinceAsk == 0)
        #expect(!usage.askIsDue(now: date(15)))
        usage.sessionsSinceAsk = 5
        #expect(usage.askIsDue(now: date(15)))
    }

    // MARK: - Storage

    @Test func theBlobSurvivesARoundTrip() throws {
        let usage = filledIn()
        let back = try #require(UsageCounters.decode(usage.jsonData()))
        #expect(back == usage)
    }

    /// A build that adds a line to the report must not reset the season's tallies: a blob
    /// written before the field existed decodes with every count it had.
    @Test func anOlderBlobKeepsItsCounts() throws {
        let json = Data("""
            {"firstLaunch":"2026-08-01T10:00:00Z",
             "uses":{"shareCard":{"count":7,"last":"2026-09-13T10:00:00Z"}}}
            """.utf8)
        let back = try #require(UsageCounters.decode(json))
        #expect(back.count(.shareCard) == 7)
        #expect(back.tally(.shareCard).attempted == 7)
        #expect(back.tally(.shareCard).failed == 0)
        #expect(back.failures.isEmpty)
        #expect(back.sessionsSinceAsk == 0)
        // …and the next write is in the new shape, with the old key gone.
        let written = try #require(String(data: back.jsonData(), encoding: .utf8))
        #expect(written.contains("\"tallies\""))
        #expect(!written.contains("\"uses\""))
    }

    /// A counter this build has retired is carried through rather than thrown away with
    /// the whole file — the keys are strings for exactly this reason.
    @Test func anUnknownCounterDoesNotDiscardTheFile() throws {
        let json = Data("""
            {"firstLaunch":"2026-08-01T10:00:00Z",
             "uses":{"somethingRetired":{"count":3,"last":"2026-09-13T10:00:00Z"},
                     "appOpen":{"count":5,"last":"2026-09-13T10:00:00Z"}}}
            """.utf8)
        let back = try #require(UsageCounters.decode(json))
        #expect(back.count(.appOpen) == 5)
        #expect(back.tallies["somethingRetired"]?.succeeded == 3)
    }
}
