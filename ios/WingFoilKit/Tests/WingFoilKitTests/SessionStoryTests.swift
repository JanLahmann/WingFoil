import Foundation
import Testing
@testable import WingFoilKit

/// The session's Coach line and the records it holds (UX review 26 Sep 2026, fixes 2 and 3).
/// Every fixture is a library of rows in UTC, so a month and a season are calendar facts and
/// `now` is pinned.
@Suite struct SessionStoryTests {

    /// 20 Sep 2026, 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_789_905_600)

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour) = (y, m, d, 14)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: c)!
    }

    private func row(_ id: String, _ date: Date, jibes: Int = 14, fell: Int = 0,
                     clean: Int? = 0, best2s: Double? = 20, streak: Int? = nil,
                     sourceClass: String = "a") -> SessionRow {
        var r = SessionRow(id: id, startDate: date, durationS: 3600, sourceClass: sourceClass)
        r.startUtcOffsetS = 0
        r.jibes = jibes
        r.jibesFellIn = fell
        r.jibesSuccessful = clean
        r.best2sKn = best2s
        r.longestDryStreak = streak
        r.distanceKm = 10
        return r
    }

    private func story(_ session: SessionRow, _ history: [SessionRow],
                       policy: SpeedRecordPolicy = .preferVerified) -> SessionStory? {
        SessionStory.make(session: session, history: history + [session], now: now,
                          policy: policy)
    }

    /// The review's own example, word for word: the tally, then the one best true thing.
    @Test func theTallyThenTheMonthsFastest() {
        let history = [row("old", day(2025, 6, 1), clean: 12, best2s: 25),
                       row("aug", day(2026, 8, 20), clean: 11, best2s: 24),
                       row("sep1", day(2026, 9, 3), clean: 10, best2s: 21)]
        let today = row("sep2", day(2026, 9, 18), jibes: 16, fell: 2, clean: 9, best2s: 22)
        let s = story(today, history)
        #expect(s?.line == "14 dry jibes, 9 clean, your fastest 2 s this month.")
        #expect(s?.honours == [SessionHonour(kind: .best2s, scope: .month)])
        // A month best is the line's, not a chip's.
        #expect(s?.chip(forCell: "max2s") == nil)
        #expect(s?.cardBadge == nil)
        #expect((s?.line.split(separator: " ").count ?? 99) <= 15)
    }

    /// Wider beats narrower, and inside one scope the clean jibes come first.
    @Test func anAllTimeBestLeadsAndWearsTheChipAndTheRibbon() {
        let history = [row("a", day(2025, 7, 1), clean: 5, best2s: 25),
                       row("b", day(2026, 9, 2), clean: 3, best2s: 21)]
        let today = row("c", day(2026, 9, 18), clean: 8, best2s: 22)
        let s = story(today, history)!
        #expect(s.line == "14 dry jibes, 8 clean, your most clean jibes ever.")
        #expect(s.chip(forCell: "cleanJibes") == "Best ever")
        // The 2 s is this season's best too, and wears its own, narrower chip.
        #expect(s.chip(forCell: "max2s") == "Season best")
        #expect(s.cardBadge == "Best ever · clean jibes")
        #expect(s.holdsAllTimeRecord)
    }

    @Test func aSeasonBestReadsThisSeasonAndGetsTheSeasonChip() {
        let history = [row("a", day(2025, 7, 1), best2s: 30),
                       row("b", day(2026, 5, 2), best2s: 21)]
        let today = row("c", day(2026, 9, 18), best2s: 23)
        let s = story(today, history)!
        #expect(s.line == "14 dry jibes, your fastest 2 s this season.")
        #expect(s.chip(forCell: "max2s") == "Season best")
        #expect(s.cardBadge == "Season best · best 2 s")
    }

    /// An old session reads "that month", not "this month".
    @Test func aPastScopeSaysThat() {
        let history = [row("a", day(2025, 5, 1), best2s: 30),
                       row("b", day(2025, 7, 20), best2s: 21)]
        let today = row("c", day(2025, 7, 10), best2s: 23)
        #expect(story(today, history)?.line == "14 dry jibes, your fastest 2 s that month.")
    }

    @Test func theFirstCleanJibeEverBeatsEverything() {
        let history = [row("a", day(2026, 8, 1), clean: 0, best2s: 30),
                       row("b", day(2026, 8, 20), clean: 0, best2s: 21)]
        let one = row("c", day(2026, 9, 18), clean: 1, best2s: 35)
        let s = story(one, history)!
        #expect(s.firstCleanJibe)
        #expect(s.line == "14 dry jibes, 1 clean, your first clean jibe ever.")
        #expect(s.chip(forCell: "max2s") == "Best ever")
        let two = row("c", day(2026, 9, 18), clean: 2)
        #expect(story(two, history)?.line
                == "14 dry jibes, 2 clean, your first clean jibes ever.")
    }

    /// An earlier row without a clean count cannot prove the first one.
    @Test func noFirstCleanClaimOverAnUnmeasuredPast() {
        let history = [row("a", day(2026, 8, 1), clean: nil)]
        let today = row("c", day(2026, 9, 18), clean: 2)
        #expect(story(today, history)?.firstCleanJibe == false)
    }

    @Test func aDryStreakRecordIsTold() {
        let history = [row("a", day(2025, 7, 1), best2s: 30, streak: 4),
                       row("b", day(2026, 9, 2), best2s: 25, streak: 5)]
        let today = row("c", day(2026, 9, 18), best2s: 20, streak: 9)
        let s = story(today, history)!
        #expect(s.line == "14 dry jibes, your longest dry streak ever.")
        #expect(s.chip(forCell: "streaks") == "Best ever")
    }

    /// Nothing to celebrate: the plain tally. And the falls are never named, even when every
    /// jibe went in.
    @Test func thePlainTallyAndNeverTheFalls() {
        let history = [row("a", day(2026, 9, 1), clean: 20, best2s: 30, streak: 20)]
        #expect(story(row("c", day(2026, 9, 18), clean: 3), history)?.line
                == "14 dry jibes, 3 clean.")
        let wet = row("d", day(2026, 9, 18), jibes: 12, fell: 12, clean: 0, best2s: nil)
        let line = story(wet, history)?.line ?? ""
        #expect(line == "12 jibes.")
        #expect(!line.contains("fell") && !line.contains("swim"))
    }

    /// A tie goes to the earlier afternoon, the Records table's rule.
    @Test func aTieStaysWithTheEarlierSession() {
        let history = [row("a", day(2026, 9, 1), best2s: 22)]
        let later = row("c", day(2026, 9, 18), best2s: 22)
        #expect(story(later, history)?.honours.contains { $0.kind == .best2s } == false)
        let earlier = row("a", day(2026, 9, 1), best2s: 22)
        let s = SessionStory.make(session: earlier, history: [earlier, later], now: now)
        #expect(s?.honour(forCell: "max2s") == SessionHonour(kind: .best2s, scope: .allTime))
    }

    /// The first session of a library beats nobody; a friend's or the example beats nobody.
    @Test func noRivalsNoRecords() {
        let alone = row("c", day(2026, 9, 18), clean: 5, best2s: 30)
        #expect(story(alone, [])?.honours == [])
        #expect(story(alone, [])?.line == "14 dry jibes, 5 clean.")
        var friend = row("f", day(2026, 9, 18), clean: 30, best2s: 40)
        friend.rider = "Freddy"
        let s = story(friend, [row("a", day(2026, 9, 1))])
        #expect(s?.honours == [] && s?.firstCleanJibe == false)
    }

    /// The rider's Speed records setting decides which speeds may stand.
    @Test func anUncertifiedSpeedYieldsToACertifiedOne() {
        let history = [row("a", day(2026, 9, 1), best2s: 20)]
        let estimated = row("c", day(2026, 9, 18), best2s: 30, sourceClass: "c")
        #expect(story(estimated, history)?.honours.contains { $0.kind == .best2s } == false)
        #expect(story(estimated, history, policy: .includeUnverified)?
            .honours.contains { $0.kind == .best2s } == true)
    }

    @Test func turnsAndFlightsWhenThereAreNoJibes() {
        var turns = row("t", day(2026, 9, 18), jibes: 0, best2s: nil)
        turns.turnsCounted = 6
        turns.turnsFellIn = 1
        #expect(story(turns, [])?.line == "5 dry turns.")
        var flights = row("f", day(2026, 9, 18), jibes: 0, best2s: nil)
        flights.flightCount = 12
        flights.foilTimeS = 42 * 60
        #expect(story(flights, [])?.line == "12 flights, 42 min on the foil.")
        let nothing = row("n", day(2026, 9, 18), jibes: 0, best2s: nil)
        #expect(story(nothing, []) == nil)
    }

    /// The share caption leads with the story and does not count the clean jibes twice.
    @Test func theCaptionLeadsWithTheStory() {
        let caption = ShareCaption.line(story: "14 dry jibes, 9 clean.", title: "Torbole",
                                        dateLine: "30 August 2026", foilPct: 66,
                                        cleanJibes: 9)
        #expect(caption == "14 dry jibes, 9 clean. Torbole · 30 August 2026 · 66 % on the foil"
                + " — " + ShareCaption.offer)
        #expect(ShareCaption.line(story: nil, title: "Torbole", dateLine: "30 August 2026",
                                  foilPct: 66, cleanJibes: 9)
                == ShareCaption.line(title: "Torbole", dateLine: "30 August 2026",
                                     foilPct: 66, cleanJibes: 9))
    }
}
