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

    // MARK: - The report

    private func filledIn() -> UsageCounters {
        var usage = counters()
        usage.record(.appOpen, times: 87, at: date(14), timeZone: zone)
        usage.record(.importIcu, times: 38, at: date(14), timeZone: zone)
        usage.record(.shareCard, times: 12, at: date(13), timeZone: zone)
        usage.recordFailure("Could not reach intervals.icu", at: date(12), timeZone: zone)
        usage.recordFailure("Could not reach intervals.icu", at: date(13), timeZone: zone)
        return usage
    }

    @Test func theReportOpensWithTheBuildAndTheDates() {
        let lines = filledIn().report(appVersion: "1.1.0 (23)", now: date(14),
                                      timeZone: zone)
            .split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines[0] == "Usage and features")
        #expect(lines[1] == "  CleanJibe 1.1.0 (23)")
        #expect(lines[2] == "  First launch 1 Aug · 3 days active · written 14 Sep")
    }

    @Test func aUsedFeatureIsOneLineWithACountAndADate() {
        let report = filledIn().report(appVersion: "1.1.0 (23)", now: date(14),
                                       timeZone: zone)
        #expect(report.contains("\n  share card · 12 · last 13 Sep"))
        #expect(report.contains("\n  imported · intervals.icu · 38 · last 14 Sep"))
    }

    /// The half of the block that decides what ships: a door nobody has opened in four
    /// months is a door the release does not need yet (docs/channels.md, rule 1).
    @Test func theDoorsNobodyOpenedAreNamedOnce() {
        let report = filledIn().report(appVersion: "1.1.0 (23)", now: date(14),
                                       timeZone: zone)
        let line = report.split(separator: "\n")
            .first { $0.contains("Not used yet:") }
        #expect(line != nil)
        #expect(line?.contains("session video") == true)
        #expect(line?.contains("backup restored") == true)
        // …and nothing that *was* used is in it.
        #expect(line?.contains("share card") == false)
        // One line, not seventeen.
        #expect(report.components(separatedBy: "Not used yet:").count == 2)
    }

    @Test func theFailuresAreListedUnderTheirOwnHeading() {
        let report = filledIn().report(appVersion: "1.1.0 (23)", now: date(14),
                                       timeZone: zone)
        #expect(report.contains("  Failures this phone showed, newest first"))
        #expect(report.contains("\n    Could not reach intervals.icu · 2 · last 13 Sep"))
    }

    @Test func aPhoneWithNoFailuresHasNoFailuresHeading() {
        var usage = counters()
        usage.record(.appOpen, at: date(14), timeZone: zone)
        #expect(!usage.report(appVersion: "1.1.0 (23)", now: date(14), timeZone: zone)
            .contains("Failures"))
    }

    /// A fresh phone still produces a readable block rather than a heading with nothing
    /// under it — the first tester to send one will have opened the app twice.
    @Test func anUntouchedPhoneStillRendersABlock() {
        let report = counters(from: 14, month: 9)
            .report(appVersion: "1.1.0 (23)", now: date(14), timeZone: zone)
        #expect(report.hasPrefix("Usage and features\n  CleanJibe 1.1.0 (23)"))
        #expect(report.contains("0 days active"))
        #expect(report.contains("Not used yet: app opened"))
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
        #expect(back.failures.isEmpty)
        #expect(back.sessionsSinceAsk == 0)
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
        #expect(back.uses["somethingRetired"]?.count == 3)
    }
}
