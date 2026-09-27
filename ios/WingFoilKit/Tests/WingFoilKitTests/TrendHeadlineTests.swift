import Foundation
import Testing
@testable import WingFoilKit

/// The one-line verdicts over the Trends charts and the season line above them.
@Suite struct TrendHeadlineTests {

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    static func day(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 14))!
    }

    static func sample(_ month: Int, _ d: Int, _ value: Double, hours: Double = 1)
        -> TrendHeadline.Sample {
        TrendHeadline.Sample(date: day(month, d), value: value, hours: hours)
    }

    static let now = day(9, 27)

    static func line(_ samples: [TrendHeadline.Sample], _ spec: TrendHeadline.Spec)
        -> String? {
        TrendHeadline.line(samples, spec: spec, now: now, calendar: calendar)
    }

    @Test func thisMonthAgainstTheMonthBefore() {
        let samples = [Self.sample(8, 3, 8), Self.sample(8, 20, 10),
                       Self.sample(9, 5, 12), Self.sample(9, 19, 16)]
        #expect(Self.line(samples, TrendHeadline.cleanJibes)
                == "14 a session this month, up from 9 in August.")
    }

    @Test func downAndLevel() {
        let down = [Self.sample(8, 3, 10), Self.sample(8, 20, 10),
                    Self.sample(9, 5, 6), Self.sample(9, 19, 6)]
        #expect(Self.line(down, TrendHeadline.cleanJibes)
                == "6 a session this month, down from 10 in August.")
        let level = [Self.sample(8, 3, 10), Self.sample(8, 20, 10),
                     Self.sample(9, 5, 10.2), Self.sample(9, 19, 9.9)]
        #expect(Self.line(level, TrendHeadline.cleanJibes)
                == "10 a session this month, level with August.")
    }

    @Test func tooFewSessionsSaysNothing() {
        #expect(Self.line([], TrendHeadline.cleanJibes) == nil)
        // One session this month.
        #expect(Self.line([Self.sample(8, 3, 8), Self.sample(8, 20, 10),
                           Self.sample(9, 5, 12)], TrendHeadline.cleanJibes) == nil)
        // Nothing to compare with.
        #expect(Self.line([Self.sample(9, 5, 12), Self.sample(9, 19, 16)],
                          TrendHeadline.cleanJibes) == nil)
    }

    @Test func aGapFallsBackToTheMonthsBefore() {
        let samples = [Self.sample(5, 3, 4), Self.sample(6, 20, 6),
                       Self.sample(9, 5, 12), Self.sample(9, 19, 16)]
        #expect(Self.line(samples, TrendHeadline.cleanJibes)
                == "14 a session this month, up from 5 in the months before.")
    }

    @Test func aPastMonthIsNamed() {
        let samples = [Self.sample(7, 3, 8), Self.sample(7, 20, 10),
                       Self.sample(8, 5, 12), Self.sample(8, 19, 16)]
        #expect(Self.line(samples, TrendHeadline.cleanJibes)
                == "14 a session in August, up from 9 in July.")
    }

    @Test func bestMonthYetNeedsTwoEarlierMonthsBeaten() {
        let samples = [Self.sample(6, 3, 5), Self.sample(6, 20, 5),
                       Self.sample(7, 3, 8), Self.sample(7, 20, 8),
                       Self.sample(8, 3, 9), Self.sample(8, 20, 9),
                       Self.sample(9, 5, 12), Self.sample(9, 19, 16)]
        #expect(Self.line(samples, TrendHeadline.cleanJibes)
                == "14 a session this month, up from 9 in August. That is your best month yet.")
        // One earlier month is not enough for "yet".
        #expect(Self.line(Array(samples.suffix(4)), TrendHeadline.cleanJibes)
                == "14 a session this month, up from 9 in August.")
        // Beaten by June: no best.
        var beaten = samples
        beaten[0].value = 20
        beaten[1].value = 20
        #expect(Self.line(beaten, TrendHeadline.cleanJibes)
                == "14 a session this month, up from 9 in August.")
    }

    @Test func fewerPumpsIsTheBetterMonth() {
        let samples = [Self.sample(6, 3, 14), Self.sample(6, 20, 14),
                       Self.sample(7, 3, 12), Self.sample(7, 20, 12),
                       Self.sample(8, 3, 10), Self.sample(8, 20, 10),
                       Self.sample(9, 5, 8), Self.sample(9, 19, 8)]
        #expect(Self.line(samples, TrendHeadline.pumpsToTakeoff)
                == "8 pumps this month, down from 10 in August. That is your best month yet.")
    }

    @Test func portShareHasNoBest() {
        let samples = [Self.sample(6, 3, 30), Self.sample(6, 20, 30),
                       Self.sample(7, 3, 36), Self.sample(7, 20, 36),
                       Self.sample(9, 5, 48), Self.sample(9, 19, 48)]
        #expect(Self.line(samples, TrendHeadline.portShare)
                == "48 % on port this month, up from 33 % in the months before.")
    }

    /// A rate over a month is the month's totals over its hours: a one-hour session at 2 an
    /// hour and a three-hour one at 6 make 5, not the mean 4.
    @Test func ratesWeighByHours() {
        let samples = [Self.sample(8, 3, 3, hours: 1), Self.sample(8, 20, 3, hours: 1),
                       Self.sample(9, 5, 2, hours: 1), Self.sample(9, 19, 6, hours: 3)]
        #expect(Self.line(samples, TrendHeadline.cleanJibesPerHour)
                == "5.0 an hour this month, up from 3.0 in August.")
    }

    @Test func bestTakesTheMonthsTopSession() {
        let samples = [Self.sample(8, 3, 3.0), Self.sample(8, 20, 4.5),
                       Self.sample(9, 5, 2.0), Self.sample(9, 19, 5.2)]
        #expect(Self.line(samples, TrendHeadline.longestFlight)
                == "5.2 min this month, up from 4.5 min in August.")
        #expect(Self.line(samples, TrendHeadline.best2s(unit: "kn"))
                == "5.2 kn this month, up from 4.5 kn in August.")
    }

    @Test func deterministic() {
        let samples = [Self.sample(9, 19, 16), Self.sample(8, 20, 10),
                       Self.sample(9, 5, 12), Self.sample(8, 3, 8)]
        #expect(Self.line(samples, TrendHeadline.cleanJibes)
                == Self.line(samples.reversed(), TrendHeadline.cleanJibes))
    }

    // MARK: - Season line

    @Test func streaks() {
        #expect(SeasonLine.currentStreak([1, 1, 0, 2, 1, 1]) == 3)
        // A week still under way with no session keeps the run alive.
        #expect(SeasonLine.currentStreak([1, 1, 0, 2, 1, 0]) == 2)
        #expect(SeasonLine.currentStreak([1, 0, 0]) == 0)
        #expect(SeasonLine.bestStreak([1, 1, 1, 1, 0, 2, 1, 0]) == 4)
        #expect(SeasonLine.bestStreak([]) == 0)
    }

    @Test func seasonText() {
        #expect(SeasonLine.text(weekCounts: [1, 1, 0, 1, 1, 1], cleanJibesThisMonth: 40)
                == "3 weeks on the water in a row. That is your best run this season. "
                    + "40 clean jibes this month.")
        #expect(SeasonLine.text(weekCounts: [1, 1, 1, 1, 0, 1, 1], cleanJibesThisMonth: 1)
                == "2 weeks on the water in a row. Your best this season is 4. "
                    + "1 clean jibe this month.")
        #expect(SeasonLine.text(weekCounts: [1, 1, 1, 0, 0, 1], cleanJibesThisMonth: nil)
                == "Your best run this season is 3 weeks in a row.")
        #expect(SeasonLine.text(weekCounts: [1, 0, 1], cleanJibesThisMonth: 0) == nil)
    }
}
