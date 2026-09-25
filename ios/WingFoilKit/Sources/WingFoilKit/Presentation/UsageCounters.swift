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
/// **Counts, not events.** Per feature, how often it was tried, how often it worked, how
/// often it failed, and the dates of the last of each (`Tally`), never a timestamped trail:
/// "Share card ✓ 12 · ✗ 1" answers the question the beta has, and a log of twelve moments
/// would additionally describe a rider's afternoons. The feature list is
/// `UsageFeatures.swift`, and docs/channels.md prints it. Failures are the one
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

    // MARK: - One feature's tally

    /// **Tried, worked, failed** — the three numbers that tell "used" from "works".
    ///
    /// `attempted` can run ahead of the other two: a map handed to the link and never
    /// acknowledged is an attempt with no outcome, and that gap is itself the finding.
    /// A door that is simply opened (a page, a tab) counts one attempt and one success.
    ///
    /// `lastReason` is short and never personal: an error's type and case, a domain and a
    /// code, or a fixed phrase from the call site. Never a file name, a spot or a sentence
    /// with a place in it. The rider-facing sentences live in `failures`, which only the
    /// Extended layout prints.
    public struct Tally: Codable, Equatable, Sendable {
        public var attempted: Int
        public var succeeded: Int
        public var failed: Int
        public var firstUse: Date?
        public var lastSuccess: Date?
        public var lastFailure: Date?
        public var lastReason: String?
        /// Variants of one feature and how often each worked: the share card's shape,
        /// preset and background, say. Keys are short codes, never free text.
        public var details: [String: Int]

        public init(attempted: Int = 0, succeeded: Int = 0, failed: Int = 0,
                    firstUse: Date? = nil, lastSuccess: Date? = nil,
                    lastFailure: Date? = nil, lastReason: String? = nil,
                    details: [String: Int] = [:]) {
            self.attempted = attempted
            self.succeeded = succeeded
            self.failed = failed
            self.firstUse = firstUse
            self.lastSuccess = lastSuccess
            self.lastFailure = lastFailure
            self.lastReason = lastReason
            self.details = details
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            attempted = try c.decodeIfPresent(Int.self, forKey: .attempted) ?? 0
            succeeded = try c.decodeIfPresent(Int.self, forKey: .succeeded) ?? 0
            failed = try c.decodeIfPresent(Int.self, forKey: .failed) ?? 0
            firstUse = try c.decodeIfPresent(Date.self, forKey: .firstUse)
            lastSuccess = try c.decodeIfPresent(Date.self, forKey: .lastSuccess)
            lastFailure = try c.decodeIfPresent(Date.self, forKey: .lastFailure)
            lastReason = try c.decodeIfPresent(String.self, forKey: .lastReason)
            details = try c.decodeIfPresent([String: Int].self, forKey: .details) ?? [:]
        }

        /// The last thing that happened to this feature, either way.
        public var lastUse: Date? {
            switch (lastSuccess, lastFailure) {
            case let (s?, f?): max(s, f)
            case let (s?, nil): s
            case let (nil, f?): f
            default: firstUse
            }
        }

        /// Whether the newest outcome is a failure: the release gate's "open failure".
        public var failureIsOpen: Bool {
            guard let lastFailure else { return false }
            guard let lastSuccess else { return true }
            return lastFailure > lastSuccess
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

    /// The pre-tally counter, read from blobs written up to build 107 and nothing else.
    struct LegacyUse: Codable, Equatable, Sendable {
        var count: Int
        var last: Date
    }

    // MARK: - The blob

    /// When this phone first recorded anything — which is the first launch of the first
    /// beta build on it, not the install date, because nothing before that wrote a file.
    public var firstLaunch: Date
    /// Keyed by `Feature.rawValue` rather than by `Feature`, so a build that has retired a
    /// case still decodes a blob that mentions it instead of throwing the whole file away.
    public var tallies: [String: Tally]
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

    public init(firstLaunch: Date, tallies: [String: Tally] = [:], failures: [Failure] = [],
                days: [String] = [], sessionsSinceAsk: Int = 0,
                lastAsked: Date? = nil, snoozedUntil: Date? = nil) {
        self.firstLaunch = firstLaunch
        self.tallies = tallies
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
    enum CodingKeys: String, CodingKey {
        case firstLaunch, tallies, failures, days, sessionsSinceAsk, lastAsked, snoozedUntil
        case uses
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(firstLaunch, forKey: .firstLaunch)
        try c.encode(tallies, forKey: .tallies)
        try c.encode(failures, forKey: .failures)
        try c.encode(days, forKey: .days)
        try c.encode(sessionsSinceAsk, forKey: .sessionsSinceAsk)
        try c.encodeIfPresent(lastAsked, forKey: .lastAsked)
        try c.encodeIfPresent(snoozedUntil, forKey: .snoozedUntil)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        firstLaunch = try c.decodeIfPresent(Date.self, forKey: .firstLaunch) ?? Date()
        // A blob from before the tallies (up to build 107) carries `uses`: a count and a
        // date per door. Each becomes a tally of that many attempts that all worked, which
        // is what a counted use was, and the key is dropped on the next write.
        if let stored = try c.decodeIfPresent([String: Tally].self, forKey: .tallies) {
            tallies = stored
        } else {
            let legacy = try c.decodeIfPresent([String: LegacyUse].self, forKey: .uses) ?? [:]
            tallies = legacy.mapValues {
                Tally(attempted: $0.count, succeeded: $0.count, firstUse: $0.last,
                      lastSuccess: $0.last)
            }
        }
        failures = try c.decodeIfPresent([Failure].self, forKey: .failures) ?? []
        days = try c.decodeIfPresent([String].self, forKey: .days) ?? []
        sessionsSinceAsk = try c.decodeIfPresent(Int.self, forKey: .sessionsSinceAsk) ?? 0
        lastAsked = try c.decodeIfPresent(Date.self, forKey: .lastAsked)
        snoozedUntil = try c.decodeIfPresent(Date.self, forKey: .snoozedUntil)
    }

    // MARK: - Counting

    public func tally(_ feature: Feature) -> Tally { tallies[feature.rawValue] ?? Tally() }

    /// How often this feature worked.
    public func count(_ feature: Feature) -> Int { tally(feature).succeeded }

    public func lastUse(_ feature: Feature) -> Date? { tally(feature).lastUse }

    /// One use that worked, start to finish: a page opened, a setting changed, a file
    /// written. `times` is for a batch that is several of one thing.
    public mutating func record(_ feature: Feature, times: Int = 1, detail: String? = nil,
                                at date: Date = Date(), timeZone: TimeZone = .current) {
        guard times > 0 else { return }
        update(feature, at: date, timeZone: timeZone) {
            $0.attempted += times
            $0.succeeded += times
            // `max` rather than an assignment: a clock that has just been set back must not
            // make "last worked" travel backwards through the report.
            $0.lastSuccess = max($0.lastSuccess ?? date, date)
            if let detail = Self.detailKey(detail) { $0.details[detail, default: 0] += times }
        }
    }

    /// One try whose outcome arrives later, through `succeeded` or `failed(... attempt:
    /// false)`: a map on its way to the watch, a recording that has started.
    public mutating func attempt(_ feature: Feature, at date: Date = Date(),
                                 timeZone: TimeZone = .current) {
        update(feature, at: date, timeZone: timeZone) { $0.attempted += 1 }
    }

    /// The outcome of an earlier `attempt`: it worked. Counts no second attempt.
    public mutating func succeeded(_ feature: Feature, detail: String? = nil,
                                   at date: Date = Date(), timeZone: TimeZone = .current) {
        update(feature, at: date, timeZone: timeZone) {
            $0.succeeded += 1
            $0.lastSuccess = max($0.lastSuccess ?? date, date)
            if let detail = Self.detailKey(detail) { $0.details[detail, default: 0] += 1 }
        }
    }

    /// It went wrong. `attempt: true` counts the try as well, for a door whose try and
    /// outcome are one call; `false` closes an earlier `attempt`.
    public mutating func failed(_ feature: Feature, reason: String, attempt: Bool = true,
                                at date: Date = Date(), timeZone: TimeZone = .current) {
        update(feature, at: date, timeZone: timeZone) {
            if attempt { $0.attempted += 1 }
            $0.failed += 1
            $0.lastFailure = max($0.lastFailure ?? date, date)
            $0.lastReason = Self.shortReason(reason)
        }
    }

    private mutating func update(_ feature: Feature, at date: Date, timeZone: TimeZone,
                                 _ change: (inout Tally) -> Void) {
        var tally = tallies[feature.rawValue] ?? Tally()
        tally.firstUse = min(tally.firstUse ?? date, date)
        change(&tally)
        tallies[feature.rawValue] = tally
        markDay(date, timeZone: timeZone)
    }

    // MARK: Reasons

    /// The longest a tally's reason may be. A reason is a code, not a sentence.
    static let reasonLimit = 60

    /// An error as a short code with nothing personal in it.
    ///
    /// A Foundation error reads as its domain and number ("NSURLErrorDomain -1009"). A Swift
    /// error reads as its type and case ("StravaAuth.ConnectError.denied"), with anything
    /// in parentheses dropped, because an associated value is where a path, a file name or
    /// a server's own message would be.
    public static func reason(for error: any Error) -> String {
        let swiftType = String(reflecting: type(of: error))
        let ns = error as NSError
        // A Swift error bridges with its own qualified type name as the domain. Anything
        // else (URLError, a Cocoa error, HealthKit's) has a real domain and a number, and
        // its description carries URLs and paths, so only those two are kept.
        guard ns.domain == swiftType else {
            return shortReason(ns.domain + " " + String(ns.code))
        }
        // Module dropped, and a private type's "(unknown context at $…)" with it.
        let name = swiftType.split(separator: ".").dropFirst()
            .filter { !$0.contains("(") && !$0.contains("$") }
            .joined(separator: ".")
        let typeName = name.isEmpty ? swiftType : name
        // The case name, when the description starts with one. A custom description that
        // is a sentence is not a case name and is not kept.
        let head = String(String(describing: error).prefix { $0 != "(" })
        let isCaseName = !head.isEmpty && head.count <= 40
            && head.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
        let lastComponent = typeName.split(separator: ".").last.map(String.init) ?? typeName
        guard isCaseName, head != lastComponent else { return shortReason(typeName) }
        return shortReason(typeName + "." + head)
    }

    static func shortReason(_ text: String) -> String {
        let one = tidy(text)
        guard one.count > reasonLimit else { return one }
        return String(one.prefix(reasonLimit)) + "…"
    }

    /// A detail key: short, one line, no separators that would break a report line.
    static func detailKey(_ detail: String?) -> String? {
        guard let detail else { return nil }
        let key = shortReason(detail)
        return key.isEmpty ? nil : key
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

    /// How much of the block the mail carries. The switch sits in the mail sheet, and
    /// Normal is what it opens on.
    public enum ReportLayout: String, CaseIterable, Sendable, Identifiable {
        /// One line per used feature: "Send map to watch ✓ 12 · ✗ 1".
        case normal
        /// The same lines with dates, attempts and the last failure's reason, the variants
        /// under each, and the failure sentences this phone showed.
        case extended

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .normal: "Normal"
            case .extended: "Extended"
            }
        }
    }

    /// The "Usage and features" block, as it appears in the usage mail.
    ///
    /// The first line is the build and the phone, in both layouts: a count without the
    /// build it was counted on cannot gate anything. Only doors that have been tried get a
    /// line, grouped under the report's headings. The zeroes are said once, in the "Not
    /// used yet" line, and only for doors this build has (`channel`).
    public func report(appVersion: String, device: String, channel: HelpChannel = .dev,
                       layout: ReportLayout = .normal, now: Date = Date(),
                       timeZone: TimeZone = .current) -> String {
        var lines: [String] = [Branding.appName + " " + appVersion + " · " + device]
        let dayNoun = activeDays == 1 ? " day" : " days"
        lines.append("First launch " + Self.day(firstLaunch, timeZone: timeZone) + " · "
                     + String(activeDays) + dayNoun + " active · "
                     + "written " + Self.day(now, timeZone: timeZone))

        for group in Group.allCases {
            let used = Feature.allCases.filter { $0.group == group && isUsed($0) }
            guard !used.isEmpty else { continue }
            lines.append(group.title)
            for feature in used {
                let tally = tally(feature)
                lines.append("  " + Self.line(feature.label, tally, layout: layout,
                                               timeZone: timeZone))
                if layout == .extended {
                    lines += tally.details.sorted { $0.key < $1.key }
                        .map { "    " + $0.key + " ✓ " + String($0.value) }
                }
            }
        }

        let unused = Feature.allCases.filter { $0.channel <= channel && !isUsed($0) }
        if !unused.isEmpty {
            lines.append("Not used yet: " + unused.map(\.label).joined(separator: " · "))
        }

        var out = ["Usage and features"] + lines.map { "  " + $0 }
        if layout == .extended, !failures.isEmpty {
            out.append("  Messages this phone showed, newest first")
            for failure in failures {
                let when = Self.day(failure.last, timeZone: timeZone)
                out.append("    " + failure.message + " · " + String(failure.count)
                           + " · last " + when)
            }
        }
        return out.joined(separator: "\n")
    }

    func isUsed(_ feature: Feature) -> Bool {
        let tally = tally(feature)
        return tally.attempted > 0 || tally.succeeded > 0 || tally.failed > 0
    }

    /// "Send map to watch ✓ 12 · ✗ 1". A feature that never failed says so by leaving the
    /// cross out. Extended adds the attempts when some are still open, the dates, and the
    /// reason of the last failure.
    static func line(_ label: String, _ tally: Tally, layout: ReportLayout,
                     timeZone: TimeZone) -> String {
        var parts = [label + " ✓ " + String(tally.succeeded)]
        if tally.failed > 0 { parts.append("✗ " + String(tally.failed)) }
        guard layout == .extended else { return parts.joined(separator: " · ") }
        let open = tally.attempted - tally.succeeded - tally.failed
        if open > 0 { parts.append(String(open) + " without an answer") }
        if let first = tally.firstUse { parts.append("first " + day(first, timeZone: timeZone)) }
        if let worked = tally.lastSuccess {
            parts.append("worked " + day(worked, timeZone: timeZone))
        }
        if let failed = tally.lastFailure {
            parts.append("failed " + day(failed, timeZone: timeZone)
                         + (tally.lastReason.map { ", " + $0 } ?? ""))
        }
        return parts.joined(separator: " · ")
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
