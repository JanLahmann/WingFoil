import Foundation

/// **One line of verdict over a Trends chart** (UX review fix 10, Jan, 27 Sep 2026): the
/// latest month against the month before it, or against the months before that, so the page
/// says how the season is going instead of leaving the rider to read ten lines himself.
///
/// Deterministic: the caller hands in `now` and the calendar, and the answer is a pure
/// function of the samples. Nothing is said when the data cannot carry a claim — fewer than
/// `minimumSamples` sessions in the latest month, or fewer than that to compare against.
///
/// The month's figure is aggregated the way the chart's metric is defined:
/// - `.perSession` — the mean over the month's sessions (clean jibes a session, pumps).
/// - `.overHours` — weighted by each session's own hours, which is the period's totals over
///   its hours: the Periods rule, never the average of the sessions' own rates
///   (docs/presentation/trends-periods.md, "The aggregate block").
/// - `.best` — the month's best single session (longest flight, best 2 s).
public enum TrendHeadline {

    public enum Aggregate: Sendable { case perSession, overHours, best }

    /// Which way is better. `.neither` never says "best month yet": a port share has no
    /// better direction, only a side you avoid.
    public enum Better: Sendable { case higher, lower, neither }

    /// One session's value on one chart. `hours` is only read by `.overHours`.
    public struct Sample: Sendable, Equatable {
        public var date: Date
        public var value: Double
        public var hours: Double

        public init(date: Date, value: Double, hours: Double = 1) {
            self.date = date
            self.value = value
            self.hours = hours
        }
    }

    /// How one chart speaks: how its month is summed up, which way is better, and how a
    /// figure reads in a sentence. `number` is the figure (`"14"`, `"62 %"`); `tail` follows
    /// it the first time (`" a session"`), and again on the figure it is compared with only
    /// when `repeatTail` says so — a unit (`" min"`) is repeated, a phrase is not.
    public struct Spec: Sendable {
        public var aggregate: Aggregate
        public var better: Better
        public var number: @Sendable (Double) -> String
        public var tail: String
        public var repeatTail: Bool

        public init(aggregate: Aggregate, better: Better, tail: String = "",
                    repeatTail: Bool = false,
                    number: @escaping @Sendable (Double) -> String) {
            self.aggregate = aggregate
            self.better = better
            self.number = number
            self.tail = tail
            self.repeatTail = repeatTail
        }

        func phrase(_ value: Double) -> String { number(value) + tail }
        func reference(_ value: Double) -> String { number(value) + (repeatTail ? tail : "") }
    }

    /// A month needs at least this many sessions with the metric before it is summed up.
    public static let minimumSamples = 2
    /// "Your best month yet" needs at least this many earlier months to have beaten.
    public static let minimumEarlierMonths = 2

    // MARK: - The chart specs

    public static let onFoil = Spec(aggregate: .overHours, better: .higher) { percent($0) }
    public static let longestFlight = Spec(aggregate: .best, better: .higher, tail: " min",
                                           repeatTail: true) { decimal($0) }
    public static let flewThrough = Spec(aggregate: .perSession, better: .higher) {
        percent($0)
    }
    public static let cleanJibes = Spec(aggregate: .perSession, better: .higher,
                                        tail: " a session") { whole($0) }
    public static let cleanJibesPerHour = Spec(aggregate: .overHours, better: .higher,
                                               tail: " an hour") { decimal($0) }
    public static let jibesPerHour = cleanJibesPerHour
    public static let turnsPerHour = cleanJibesPerHour
    public static let pumpsToTakeoff = Spec(aggregate: .perSession, better: .lower,
                                            tail: " pumps") { whole($0) }
    public static let portShare = Spec(aggregate: .perSession, better: .neither,
                                       tail: " on port") { percent($0) }

    /// Best 2 s in the rider's unit. The caller converts the samples and names the unit, so
    /// the sentence and the axis under it can never disagree.
    public static func best2s(unit: String) -> Spec {
        Spec(aggregate: .best, better: .higher, tail: " " + unit, repeatTail: true) {
            decimal($0)
        }
    }

    // MARK: - The line

    public static func line(_ samples: [Sample], spec: Spec, now: Date = Date(),
                            calendar: Calendar = .current) -> String? {
        guard let latestDate = samples.map(\.date).max() else { return nil }
        let monthOf = { (date: Date) -> Date in
            calendar.dateInterval(of: .month, for: date)?.start ?? date
        }
        let latest = monthOf(latestDate)
        let byMonth = Dictionary(grouping: samples, by: { monthOf($0.date) })
        guard let current = byMonth[latest], current.count >= minimumSamples,
              let value = aggregate(current, spec.aggregate, spec.better) else { return nil }

        // The month before, when it has enough to say; otherwise every earlier session in
        // the range, summed up the same way.
        let earlier = samples.filter { monthOf($0.date) < latest }
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: latest)
        let before: (samples: [Sample], name: String)
        if let previousMonth, let prior = byMonth[previousMonth], prior.count >= minimumSamples {
            before = (prior, monthName(previousMonth, calendar: calendar))
        } else if earlier.count >= minimumSamples {
            before = (earlier, "the months before")
        } else {
            return nil
        }
        guard let reference = aggregate(before.samples, spec.aggregate, spec.better)
        else { return nil }

        let isThisMonth = latest == monthOf(now)
        let when = isThisMonth ? "this month" : "in " + monthName(latest, calendar: calendar)
        let shown = spec.phrase(value)
        let shownBefore = spec.reference(reference)
        let change: String
        if spec.number(value) == spec.number(reference) {
            change = "level with " + before.name
        } else {
            change = (value > reference ? "up from " : "down from ") + shownBefore + " in "
                + before.name
        }
        var sentence = shown + " " + when + ", " + change + "."

        // Best month yet: better than every earlier month that could be summed up, and
        // there were enough of them for the word "yet" to mean something.
        let earlierMonths = byMonth.filter { $0.key < latest && $0.value.count >= minimumSamples }
            .compactMap { aggregate($0.value, spec.aggregate, spec.better) }
        if spec.better != .neither, earlierMonths.count >= minimumEarlierMonths,
           earlierMonths.allSatisfy({ beats(value, $0, spec.better) && spec.number($0) != spec.number(value) }) {
            sentence += " That is your best month yet."
        }
        return sentence
    }

    // MARK: - Arithmetic

    static func aggregate(_ samples: [Sample], _ kind: Aggregate, _ better: Better) -> Double? {
        guard !samples.isEmpty else { return nil }
        switch kind {
        case .perSession:
            return samples.reduce(0) { $0 + $1.value } / Double(samples.count)
        case .overHours:
            let hours = samples.reduce(0) { $0 + $1.hours }
            guard hours > 0 else { return nil }
            return samples.reduce(0) { $0 + $1.value * $1.hours } / hours
        case .best:
            let values = samples.map(\.value)
            return better == .lower ? values.min() : values.max()
        }
    }

    static func beats(_ a: Double, _ b: Double, _ better: Better) -> Bool {
        switch better {
        case .higher: a > b
        case .lower: a < b
        case .neither: false
        }
    }

    static func monthName(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM"
        return formatter.string(from: date)
    }

    static func whole(_ value: Double) -> String { String(format: "%.0f", value) }
    static func decimal(_ value: Double) -> String { String(format: "%.1f", value) }
    static func percent(_ value: Double) -> String { String(format: "%.0f %%", value) }
}

/// **The season line at the top of Trends**: weeks on the water in a row, now and at best,
/// and the clean jibes of this month. Built from the sessions-per-week buckets and the
/// month's own sessions; nil when there is nothing worth saying.
public enum SeasonLine {

    /// The run of weeks with a session that ends at the latest week. A week still under
    /// way with no session yet does not break the run: Monday morning is not a lost streak.
    public static func currentStreak(_ counts: [Int]) -> Int {
        var weeks = counts
        if weeks.last == 0 { weeks.removeLast() }
        var run = 0
        for count in weeks.reversed() {
            guard count > 0 else { break }
            run += 1
        }
        return run
    }

    public static func bestStreak(_ counts: [Int]) -> Int {
        var best = 0
        var run = 0
        for count in counts {
            run = count > 0 ? run + 1 : 0
            best = max(best, run)
        }
        return best
    }

    /// `weekCounts` oldest first, the last one the current week. `cleanJibesThisMonth` is
    /// nil when no session this month could count them.
    public static func text(weekCounts: [Int], cleanJibesThisMonth: Int?) -> String? {
        let current = currentStreak(weekCounts)
        let best = bestStreak(weekCounts)
        var parts: [String] = []
        if current >= 2 {
            parts.append(String(current) + " weeks on the water in a row.")
            parts.append(current >= best ? "That is your best run this season."
                         : "Your best this season is " + String(best) + ".")
        } else if best >= 2 {
            parts.append("Your best run this season is " + String(best) + " weeks in a row.")
        }
        if let clean = cleanJibesThisMonth, clean > 0 {
            parts.append(String(clean) + (clean == 1 ? " clean jibe" : " clean jibes")
                         + " this month.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
