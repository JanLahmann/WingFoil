import Foundation

/// **What the beta counts on one phone** (docs/channels.md, "Beta section": *feature list,
/// request a feature, extended feedback mail with usage and feature statistics*).
///
/// A beta answers two questions a bug report cannot. *Is this door ever opened?* — four
/// months of testing with nobody once exporting a video says more about the video export
/// than any single mail. And *what went wrong that nobody wrote in about?* — a rider who
/// hits "Could not read that backup" at a slipway does not write a mail from the water, and
/// by the evening he has forgotten the wording.
///
/// **This is not telemetry, and the difference is not a promise but a mechanism.** There is
/// no CleanJibe server. These counters live in this phone's `UserDefaults` under
/// `usage.counters.v1`, they are never uploaded, never read at launch by anything but the
/// rider's own Settings screen, and the only way a single number leaves the phone is a mail
/// the rider opens, reads in full and sends from his own account — with every line of it
/// editable first. A counter that cannot be read before it is sent would be telemetry with
/// a longer path; one printed as plain text in a mail body is a rider telling us something.
///
/// **Counts, not events.** A count and a last-used date per feature, never a timestamped
/// trail: "share card · 12 · last 13 Sep" answers the question the beta has, and a log of
/// twelve moments would additionally describe a rider's afternoons. Failures are the one
/// place a *string* is kept, and it is the rider-facing sentence he was shown — the same
/// words that are on the screen he could photograph — deduplicated, so twenty identical
/// sync failures are one line with a 20 beside it.
///
/// Beta only. The app's `Usage` helper compiles to nothing outside `BETA`, so the release
/// channel neither writes this blob nor reads one a beta left behind.
public struct UsageCounters: Codable, Equatable, Sendable {

    /// Where the whole blob lives, as JSON, in the phone's own defaults.
    public static let defaultsKey = "usage.counters.v1"

    /// At most this many distinct failure messages are kept, newest first.
    public static let failureLimit = 20

    /// The longest a remembered failure message may be. A rider-facing sentence is one or
    /// two lines; anything past this is an `Error`'s own debug description that leaked into
    /// one, and the first 200 characters of it identify it just as well.
    static let failureMessageLimit = 200

    /// Roughly a year of "was the app used today?". Far past any window the report shows,
    /// and still a few kilobytes.
    static let dayLimit = 400

    // MARK: - The features

    /// Every door the beta counts, in the order the report prints them: getting in, the
    /// session screens, what leaves the phone, the library's own machinery, and the two
    /// rows that are about the beta itself.
    ///
    /// A closed set rather than free-form strings: a counter named at the call site is a
    /// counter that gets renamed by a refactor and silently starts a second tally.
    public enum Feature: String, Codable, CaseIterable, Sendable {
        case appOpen
        case importIcu
        case importFile
        case importStrava
        case importHealth
        case importShareSheet
        case importZip
        case sessionOpened
        case turnPage
        case shareCard
        case clipExported
        case videoExported
        case backupMade
        case backupRestored
        case settingsOpened
        case feedbackMail
        case stravaConnected

        /// The words the mail prints. Rider vocabulary, not the app's internals: the reader
        /// of the mail is Jan, and the writer of it is a rider who has to be able to tell
        /// whether a line is describing something he did.
        public var label: String {
            switch self {
            case .appOpen: "app opened"
            case .importIcu: "imported · intervals.icu"
            case .importFile: "imported · file"
            case .importStrava: "imported · Strava"
            case .importHealth: "imported · Apple Health"
            case .importShareSheet: "imported · share sheet"
            case .importZip: "imported · Garmin ZIP"
            case .sessionOpened: "session opened"
            case .turnPage: "turn page"
            case .shareCard: "share card"
            case .clipExported: "replay clip"
            case .videoExported: "session video"
            case .backupMade: "backup made"
            case .backupRestored: "backup restored"
            case .settingsOpened: "settings opened"
            case .feedbackMail: "feedback mail"
            case .stravaConnected: "Strava connected"
            }
        }
    }

    /// One feature's tally: how often, and when last.
    public struct Use: Codable, Equatable, Sendable {
        public var count: Int
        public var last: Date

        public init(count: Int, last: Date) {
            self.count = count
            self.last = last
        }
    }

    /// One rider-facing failure sentence, and how often it has been shown.
    public struct Failure: Codable, Equatable, Sendable {
        public var message: String
        public var count: Int
        public var last: Date

        public init(message: String, count: Int, last: Date) {
            self.message = message
            self.count = count
            self.last = last
        }
    }

    // MARK: - The blob

    /// When this phone first recorded anything — which is the first launch of the first
    /// beta build on it, not the install date, because nothing before that wrote a file.
    public var firstLaunch: Date
    /// Keyed by `Feature.rawValue` rather than by `Feature`, so a build that has retired a
    /// case still decodes a blob that mentions it instead of throwing the whole file away.
    public var uses: [String: Use]
    /// Newest first, at most `failureLimit`, one entry per distinct message.
    public var failures: [Failure]
    /// `yyyy-MM-dd` in the phone's own zone, oldest first. Days, not times: "used on 14
    /// days" is the fact the beta wants, and a list of moments is a diary.
    public var days: [String]

    // MARK: The ask

    /// Sessions imported since the report was last asked for or put off.
    public var sessionsSinceAsk: Int
    /// When the rider last saw the ask — sent, or "Not now". Nil until he has seen one.
    public var lastAsked: Date?
    /// Set by "Not now": no ask before this.
    public var snoozedUntil: Date?

    public init(firstLaunch: Date, uses: [String: Use] = [:], failures: [Failure] = [],
                days: [String] = [], sessionsSinceAsk: Int = 0,
                lastAsked: Date? = nil, snoozedUntil: Date? = nil) {
        self.firstLaunch = firstLaunch
        self.uses = uses
        self.failures = failures
        self.days = days
        self.sessionsSinceAsk = sessionsSinceAsk
        self.lastAsked = lastAsked
        self.snoozedUntil = snoozedUntil
    }

    /// Every field optional-with-a-default on decode, so a blob written by an older beta
    /// build keeps its counts when a new field arrives. The alternative — a throw, caught
    /// by the caller, replaced with a fresh blob — silently resets the season's tallies on
    /// the first build that adds a line to the report.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        firstLaunch = try c.decodeIfPresent(Date.self, forKey: .firstLaunch) ?? Date()
        uses = try c.decodeIfPresent([String: Use].self, forKey: .uses) ?? [:]
        failures = try c.decodeIfPresent([Failure].self, forKey: .failures) ?? []
        days = try c.decodeIfPresent([String].self, forKey: .days) ?? []
        sessionsSinceAsk = try c.decodeIfPresent(Int.self, forKey: .sessionsSinceAsk) ?? 0
        lastAsked = try c.decodeIfPresent(Date.self, forKey: .lastAsked)
        snoozedUntil = try c.decodeIfPresent(Date.self, forKey: .snoozedUntil)
    }

    // MARK: - Counting

    public func count(_ feature: Feature) -> Int { uses[feature.rawValue]?.count ?? 0 }

    public func lastUse(_ feature: Feature) -> Date? { uses[feature.rawValue]?.last }

    /// One use of one door. `times` is for the imports, where a batch of nine sessions
    /// through one door is nine sessions and not one import.
    public mutating func record(_ feature: Feature, times: Int = 1,
                                at date: Date = Date(),
                                timeZone: TimeZone = .current) {
        guard times > 0 else { return }
        let existing = uses[feature.rawValue]
        uses[feature.rawValue] = Use(count: (existing?.count ?? 0) + times,
                                     // `max` rather than an assignment: a clock that has
                                     // just been set back must not make "last used" travel
                                     // backwards through the report.
                                     last: max(existing?.last ?? date, date))
        markDay(date, timeZone: timeZone)
    }

    /// A failure the rider was *shown*, in the words he was shown it in.
    ///
    /// Deduplicated by message and moved to the front, so the report reads as "these are
    /// the things that go wrong here, worst first" rather than as a scrolling log in which
    /// one flaky sync buries the other nineteen.
    public mutating func recordFailure(_ message: String, at date: Date = Date(),
                                       timeZone: TimeZone = .current) {
        let trimmed = Self.tidy(message)
        guard !trimmed.isEmpty else { return }
        if let index = failures.firstIndex(where: { $0.message == trimmed }) {
            var hit = failures.remove(at: index)
            hit.count += 1
            hit.last = max(hit.last, date)
            failures.insert(hit, at: 0)
        } else {
            failures.insert(Failure(message: trimmed, count: 1, last: date), at: 0)
        }
        if failures.count > Self.failureLimit {
            failures.removeLast(failures.count - Self.failureLimit)
        }
        markDay(date, timeZone: timeZone)
    }

    /// One line, not many: a multi-line failure (an import summary lists every file it
    /// could not read) is collapsed so one entry is one sentence, and truncated so an
    /// `Error`'s debug description cannot fill the mail.
    static func tidy(_ message: String) -> String {
        let oneLine = message
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        guard oneLine.count > failureMessageLimit else { return oneLine }
        return String(oneLine.prefix(failureMessageLimit)) + "…"
    }

    private mutating func markDay(_ date: Date, timeZone: TimeZone) {
        let key = Self.dayKey(date, timeZone: timeZone)
        guard days.last != key else { return }       // the overwhelmingly common case
        guard !days.contains(key) else { return }
        days.append(key)
        if days.count > Self.dayLimit { days.removeFirst(days.count - Self.dayLimit) }
    }

    /// Distinct days on which this phone recorded anything.
    public var activeDays: Int { days.count }

    // MARK: - The ask (docs/channels.md, the beta's usage report)

    /// Every fifth session imported, or a fortnight since the last ask — whichever comes
    /// first, and never while a "Not now" is still running.
    public static let askAfterSessions = 5
    public static let askAfterDays = 14

    public func askIsDue(now: Date = Date()) -> Bool {
        if let snoozedUntil, now < snoozedUntil { return false }
        if sessionsSinceAsk >= Self.askAfterSessions { return true }
        // Nothing has ever been asked: the fortnight runs from the first launch, so a
        // phone that imports nothing still gets asked once, two weeks in.
        let since = lastAsked ?? firstLaunch
        return now.timeIntervalSince(since) >= Double(Self.askAfterDays) * 86_400
    }

    /// The rider answered — he opened the mail, or he said Not now. Either way the count
    /// starts again; "Not now" additionally buys a fortnight of quiet.
    public mutating func askAnswered(now: Date = Date(), snooze: Bool) {
        lastAsked = now
        sessionsSinceAsk = 0
        snoozedUntil = snooze
            ? now.addingTimeInterval(Double(Self.askAfterDays) * 86_400)
            : nil
    }

    // MARK: - The report

    /// The "Usage and features" block, as it appears at the foot of the usage mail.
    ///
    /// Only doors that have been opened get a line — a wall of zeroes is unreadable, and
    /// the zeroes still get said, once, in the "Not used yet" line, which is the half of
    /// this block that actually decides what ships (docs/channels.md's rule 1).
    public func report(appVersion: String, now: Date = Date(),
                       timeZone: TimeZone = .current) -> String {
        var lines: [String] = ["\(Branding.appName) \(appVersion)"]
        lines.append("First launch \(Self.day(firstLaunch, timeZone: timeZone)) · "
                     + "\(activeDays) day\(activeDays == 1 ? "" : "s") active · "
                     + "written \(Self.day(now, timeZone: timeZone))")

        let used = Feature.allCases.filter { count($0) > 0 }
        for feature in used {
            guard let use = uses[feature.rawValue] else { continue }
            lines.append("\(feature.label) · \(use.count) · "
                         + "last \(Self.day(use.last, timeZone: timeZone))")
        }

        let unused = Feature.allCases.filter { count($0) == 0 }
        if !unused.isEmpty {
            lines.append("Not used yet: " + unused.map(\.label).joined(separator: " · "))
        }

        var out = ["Usage and features"] + lines.map { "  " + $0 }
        if !failures.isEmpty {
            out.append("  Failures this phone showed (newest first)")
            out += failures.map {
                "    \($0.message) · \($0.count) · last \(Self.day($0.last, timeZone: timeZone))"
            }
        }
        return out.joined(separator: "\n")
    }

    // MARK: - Dates

    /// "13 Sep". Fixed to `en_US_POSIX` on purpose: the mail is read in one language by one
    /// reader, and a date that renders as "13.09." on a German phone and "Sep 13" on an
    /// American one is two spellings of a line the test suite pins to one.
    static func day(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    static func dayKey(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - JSON

    /// The blob as it is stored. The app owns the `UserDefaults` call; the shape of what
    /// goes in it is the kit's, so the test suite reads the same bytes the phone writes.
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) -> UsageCounters? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UsageCounters.self, from: data)
    }
}
