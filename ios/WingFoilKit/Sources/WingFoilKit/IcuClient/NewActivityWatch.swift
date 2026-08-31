import Foundation

/// What the background poller remembers between wakes.
///
/// Two facts, and they do different jobs. `lastStartDate` is the high-water mark: it only
/// anchors how far back the next list call reaches, so a rider who was away for a month
/// still gets the whole month listed in one request. `announcedIds` is the actual memory —
/// an activity is announced the first time it is *seen*, and never again, whatever the
/// clocks say. Ordering by date alone would be wrong: intervals.icu dates an activity by
/// when it was ridden, not by when Garmin got round to uploading it, so a session that
/// lands late would sort below the mark and be silently swallowed.
public struct NewActivityMark: Sendable, Codable, Equatable {

    /// Newest activity start seen so far. `nil` until the first poll — see `isSeeded`.
    public var lastStartDate: Date?
    /// Activities already seen, oldest first. Everything in the poll window goes in here,
    /// announced or not, so a session imported by hand cannot be announced afterwards.
    public var announcedIds: [String]

    /// Plenty for a four-day window; the cap only exists so the defaults entry cannot grow
    /// without bound over years of polling.
    public static let announcedLimit = 100

    /// False exactly once, on the first poll after the rider turns the feature on. That
    /// poll announces nothing — see `NewActivityWatch.evaluate`.
    public var isSeeded: Bool { lastStartDate != nil }

    public init(lastStartDate: Date? = nil, announcedIds: [String] = []) {
        self.lastStartDate = lastStartDate
        self.announcedIds = announcedIds
    }

    /// Adds ids that were not known yet, keeping insertion order so the cap evicts the
    /// oldest. Re-seeing an id is a no-op rather than a bump: within one poll window every
    /// id is re-seen on every pass, so "most recently seen" would carry no information.
    public mutating func remember(ids: [String]) {
        var known = Set(announcedIds)
        for id in ids where !known.contains(id) {
            announcedIds.append(id)
            known.insert(id)
        }
        if announcedIds.count > Self.announcedLimit {
            announcedIds.removeFirst(announcedIds.count - Self.announcedLimit)
        }
    }
}

/// One notification, resolved to the strings that go on screen.
public struct NewActivityNotice: Sendable, Equatable, Identifiable {
    public let activityId: String
    public let title: String
    /// The activity's own name, when it has one worth showing.
    public let subtitle: String?
    public let body: String

    public var id: String { activityId }

    public init(activityId: String, title: String, subtitle: String?, body: String) {
        self.activityId = activityId
        self.title = title
        self.subtitle = subtitle
        self.body = body
    }
}

/// The decision half of "tell me when a new Garmin session shows up" (plan §3.3, the
/// intervals.icu polling bullet). Pure functions only: what the background wake fetches,
/// which of it is new, what the notification says, and what the mark becomes afterwards.
/// The `BGAppRefreshTask` and `UNUserNotificationCenter` glue lives in the app target and
/// does none of this thinking.
public enum NewActivityWatch {

    /// A session already in the library, reduced to the three fields the dedupe key reads.
    /// A value type rather than `SessionRow` so the rule is testable without a database.
    public struct KnownSession: Sendable, Equatable {
        public var icuActivityId: String?
        public var startDate: Date
        public var durationS: Double

        public init(icuActivityId: String?, startDate: Date, durationS: Double) {
            self.icuActivityId = icuActivityId
            self.startDate = startDate
            self.durationS = durationS
        }

        public init(_ row: SessionRow) {
            self.init(icuActivityId: row.icuActivityId, startDate: row.startDate,
                      durationS: row.durationS)
        }
    }

    public struct Decision: Sendable, Equatable {
        /// What to post, oldest first. Empty on the seeding pass by construction.
        public var notices: [NewActivityNotice]
        /// The mark to persist once the notices are out.
        public var mark: NewActivityMark
        /// True on the first poll after the feature was enabled: nothing is announced, the
        /// existing history is simply written down as seen.
        public var seeding: Bool

        public init(notices: [NewActivityNotice], mark: NewActivityMark, seeding: Bool) {
            self.notices = notices
            self.mark = mark
            self.seeding = seeding
        }
    }

    /// The shortest window a poll ever asks for. Four days rather than one: a background
    /// wake is a *request*, not a promise (iOS grants them when it feels like it), and a
    /// phone that stayed in a drawer over a long weekend must not lose the sessions.
    public static let lookbackDays = 4
    /// …and the longest, so a rider coming back after a winter still makes one cheap call.
    public static let windowCeilingDays = 90
    /// At most this many notifications per wake. Three arriving at once is already a lot;
    /// a backfill of forty would be a punishment, not a notice.
    public static let noticeLimit = 3

    /// How far back the next list call reaches: from the high-water mark, but never a
    /// window narrower than `lookbackDays` and never wider than `windowCeilingDays`.
    public static func windowStart(mark: NewActivityMark, now: Date = Date()) -> Date {
        let day = 86_400.0
        let shortest = now.addingTimeInterval(-Double(lookbackDays) * day)
        let longest = now.addingTimeInterval(-Double(windowCeilingDays) * day)
        guard let last = mark.lastStartDate else { return shortest }
        return max(longest, min(last, shortest))
    }

    /// THE decision. `library` is every session already in the library; `activities` is
    /// whatever intervals.icu listed for `windowStart(mark:)…now`.
    public static func evaluate(activities: [IcuActivity],
                                library: [KnownSession],
                                mark: NewActivityMark,
                                now: Date = Date(),
                                toleranceS: TimeInterval = 60,
                                limit: Int = noticeLimit) -> Decision {
        // Same gate the manual sync uses (`IcuSyncService.sync`), so the two can never
        // disagree about what counts as a session worth having: the watersport types plus
        // the CIQ recordings that Garmin files as Walk and only the name gives away.
        let relevant = activities.filter { IcuClient.isWatersport($0) && $0.startDate != nil }
        let seeding = !mark.isSeeded

        var fresh: [IcuActivity] = []
        if !seeding {
            let seen = Set(mark.announcedIds)
            fresh = relevant
                .filter { !seen.contains($0.id) }
                .filter { !isInLibrary($0, library: library, toleranceS: toleranceS) }
                .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            // Over the limit, the newest are the ones the rider cares about.
            if fresh.count > limit { fresh.removeFirst(fresh.count - limit) }
        }

        var mark = mark
        // Everything listed counts as seen, including what was skipped for being in the
        // library already — otherwise deleting a session would make it "new" again.
        mark.remember(ids: relevant.map(\.id))
        // `now` only when there is nothing at all to anchor on, which can only be the
        // seeding pass of an empty account — the mark has to leave that pass seeded, or
        // every wake for ever would be a first poll.
        let newest = relevant.compactMap(\.startDate).max()
        mark.lastStartDate = [mark.lastStartDate, newest].compactMap { $0 }.max() ?? now

        return Decision(notices: fresh.map(notice(for:)), mark: mark, seeding: seeding)
    }

    /// The library's dedupe key (plan §3.3, `SessionIngestor.duplicate`) asked of an
    /// activity summary instead of a parsed FIT: the intervals.icu id when the session
    /// carries one, otherwise start within ±60 s and a duration that fits.
    ///
    /// The duration half is one-sided, and deliberately so: intervals.icu reports **moving**
    /// time while the library stores **elapsed** time, so a session with a beach break in it
    /// is genuinely shorter on icu's side. A two-sided ±60 s would call that a different
    /// session and announce a recording the rider already has.
    public static func isInLibrary(_ activity: IcuActivity, library: [KnownSession],
                                   toleranceS: TimeInterval = 60) -> Bool {
        if library.contains(where: { $0.icuActivityId == activity.id }) { return true }
        guard let start = activity.startDate else { return false }
        return library.contains { known in
            guard abs(known.startDate.timeIntervalSince(start)) <= toleranceS else { return false }
            guard let moving = activity.movingTimeS else { return true }
            return Double(moving) <= known.durationS + toleranceS
        }
    }

    /// What the banner says. Only what the activity summary already carries — the FIT is
    /// not downloaded to write a notification.
    ///
    /// Duration and distance are formatted the way the KEY METRICS block formats them
    /// (`KeyMetrics.hoursMinutes` / `KeyMetrics.km`), because the rider reads the same two
    /// numbers again ten seconds later at the top of the session, and a notification that
    /// said "1:57 h · 23.0 km" over a page that says something else is a bug he can see.
    public static func notice(for activity: IcuActivity) -> NewActivityNotice {
        var facts: [String] = []
        if let seconds = activity.movingTimeS, seconds > 0 {
            facts.append(KeyMetrics.hoursMinutes(Double(seconds)) + " h")
        }
        if let meters = activity.distanceM, meters > 0 {
            facts.append(KeyMetrics.km(meters / 1000))
        }
        let name = (activity.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return NewActivityNotice(
            activityId: activity.id,
            title: "New session",
            subtitle: name.isEmpty ? nil : name,
            // Nothing measured yet is not a failure — an activity can be listed seconds
            // after the upload starts, with the summary still empty.
            body: facts.isEmpty ? "Tap to import and analyze"
                                : facts.joined(separator: " · ") + " — tap to analyze")
    }
}

/// Whether to offer the feature above, out loud, once.
///
/// The toggle lives four sections down a settings sheet and starts off, which is the right
/// default — a launch that opens with a permission prompt before the rider has seen a
/// single session is a prompt he says no to — but it is also why nobody has the feature.
/// So the app asks, at the first moment the question can be answered honestly, and then
/// never again whatever the answer was.
///
/// Pure, because this is the sort of path that is walked once per install by hand and then
/// never tested again: "asked twice" and "asked before there was a key" are both bugs that
/// only a fresh device would show.
public enum NewActivityPrompt {

    /// - Parameters:
    ///   - hasKey: an intervals.icu key is stored. Without one there is nothing to poll,
    ///     so the offer would be for a feature that cannot work yet — which is also why
    ///     the Settings toggle itself is disabled until the key is there.
    ///   - isEnabled: the toggle is already on. A rider who found it himself is not asked
    ///     to turn on what he turned on.
    ///   - hasAsked: the offer has been made before. Once is the whole contract: a "not
    ///     now" that comes back next launch is a "no" that was not listened to.
    ///   - isPresenting: something else is on screen — the "whose session is this?" sheet,
    ///     Settings, Help, an error alert. That is a *deferral*, not a refusal: the caller
    ///     writes `hasAsked` down only when the alert actually goes up, so the next clear
    ///     screen asks again.
    public static func shouldAsk(hasKey: Bool, isEnabled: Bool, hasAsked: Bool,
                                 isPresenting: Bool = false) -> Bool {
        hasKey && !isEnabled && !hasAsked && !isPresenting
    }
}
