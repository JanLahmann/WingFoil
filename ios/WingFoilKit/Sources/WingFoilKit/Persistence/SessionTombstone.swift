import Foundation
import GRDB

/// A session the rider deleted, remembered so the next sync does not hand it back.
///
/// **Why a row and not a flag on the session.** A deleted session is *gone* — its FIT is
/// removed from the archive, its derived rows cascade away, its records stop counting. A
/// "deleted" column would mean every query in the app grew a condition it must never forget,
/// which is exactly the failure mode `LibraryStore.clause` exists to avoid. What is left
/// behind here is not a session: it is four facts about one that used to be, and they are
/// only ever read by the one code path that could bring it back.
///
/// **The identity is doubled on purpose.** `icuActivityId` is the exact answer when the
/// session carried one, and `startDate`/`durationS` is the library's own dedupe key (plan
/// §3.3) for when it did not. Both are needed: a session that reached the library through a
/// Garmin GDPR ZIP has no intervals.icu id, and it is *still* on intervals.icu — so deleting
/// it and syncing would import it back under a fresh id, which the id half alone would never
/// catch. See `SessionTombstones.blocks`.
public struct SessionTombstoneRow: Codable, FetchableRecord, PersistableRecord, Sendable,
                                   Equatable, Identifiable {
    public static let databaseTableName = "deleted_session"

    /// The deleted session's own uuid. Keeping it as the primary key means deleting the same
    /// session twice is impossible by construction, and gives the re-add prompt something
    /// stable to name when it clears a tombstone.
    public var id: String
    /// The intervals.icu activity this session came from, when it came from one.
    public var icuActivityId: String?
    public var startDate: Date
    public var durationS: Double
    /// What the library row was called, so Settings can say more than a count if it ever
    /// wants to. Stored rather than re-derived: the filename it came from is gone with the
    /// archive directory.
    public var title: String?
    public var deletedAt: Date

    public init(id: String, icuActivityId: String? = nil, startDate: Date, durationS: Double,
                title: String? = nil, deletedAt: Date = Date()) {
        self.id = id
        self.icuActivityId = icuActivityId
        self.startDate = startDate
        self.durationS = durationS
        self.title = title
        self.deletedAt = deletedAt
    }

    /// The tombstone of one library row.
    public init(_ row: SessionRow, title: String? = nil, deletedAt: Date = Date()) {
        self.init(id: row.id, icuActivityId: row.icuActivityId, startDate: row.startDate,
                  durationS: row.durationS, title: title, deletedAt: deletedAt)
    }

    /// A tombstone seen as "something already accounted for", which is what the background
    /// poller needs it to be: an activity the rider deleted is not news, and announcing it
    /// would be the resurrection happening in the notification tray instead of the library.
    public var asKnownSession: NewActivityWatch.KnownSession {
        NewActivityWatch.KnownSession(icuActivityId: icuActivityId, startDate: startDate,
                                      durationS: durationS)
    }
}

/// The two decisions that make deletion stick: *does this incoming activity match something
/// the rider threw away*, and *is he asking for it back*.
///
/// Pure, and deliberately so. Both are the sort of rule that is exercised once by hand on a
/// real account and then never again — "the session came back anyway" and "the app nagged me
/// on every pull" are both bugs that only a rider with a deleted session and a finger on the
/// refresh gesture would ever find.
public enum SessionTombstones {

    /// How close together two manual syncs have to be for the second one to count as "I meant
    /// that", and therefore to be worth a question.
    ///
    /// **Ten seconds**, measured from the end of the previous sync to the *start* of this one.
    /// That is barely longer than it takes to watch a pull-to-refresh spinner finish and pull
    /// again — which is precisely the gesture being detected, and nothing else is. A minute
    /// would already cover "I looked at the list, thought about it, and pulled again", and two
    /// would cover a rider who put the phone down; both of those are ordinary syncs that must
    /// not be interrupted by a question about something he deleted on purpose.
    ///
    /// The same window damps a refusal: after "Keep deleted" the offer stays down for this
    /// long, so declining is not immediately followed by being asked again on the very next
    /// pull — which, since that pull is by construction inside the window, is exactly what
    /// would otherwise happen.
    public static let reAddWindowS: TimeInterval = 10

    /// The tombstone this activity would resurrect, or nil when it is not one of the deleted.
    ///
    /// The rule is the library's own dedupe key (`SessionIngestor.duplicate`) asked of an
    /// activity summary instead of a parsed FIT, and it is the same rule
    /// `NewActivityWatch.isInLibrary` already asks — including the one-sided duration
    /// comparison, and for the same reason: intervals.icu reports **moving** time while the
    /// library stored **elapsed** time, so a session with a beach break in it is genuinely
    /// shorter on icu's side and a two-sided ±60 s would call it a different session.
    ///
    /// Asked of the activity *summary*, before the FIT is downloaded: a deleted session should
    /// cost nothing at all to skip, not a download and a parse.
    public static func blocks(_ activity: IcuActivity, tombstones: [SessionTombstoneRow],
                              toleranceS: TimeInterval = 60) -> SessionTombstoneRow? {
        if let byId = tombstones.first(where: { $0.icuActivityId == activity.id }) {
            return byId
        }
        guard let start = activity.startDate else { return nil }
        return tombstones.first { stone in
            guard abs(stone.startDate.timeIntervalSince(start)) <= toleranceS else { return false }
            guard let moving = activity.movingTimeS else { return true }
            return Double(moving) <= stone.durationS + toleranceS
        }
    }

    /// Whether a manual sync should stop and ask "did you mean to get these back?".
    ///
    /// - Parameters:
    ///   - blocked: how many incoming activities this sync skipped because of a tombstone.
    ///     Zero is the ordinary case and the ordinary case says nothing.
    ///   - previousManualSyncAt: when the rider last pulled to sync, *before* this one. nil on
    ///     the first sync of an install, which can never be a second attempt at anything.
    ///   - declinedAt: when he last said "Keep deleted", if he has.
    ///
    /// Only manual syncs may reach this. A background wake is not a rider asking twice — it is
    /// iOS deciding it is a good moment — and a notification that offered to undo a deletion
    /// nobody was thinking about would be the app arguing with its owner.
    ///
    /// `now` should be the moment the *second* sync began, not the moment it finished: a sync
    /// on a slow connection can itself take longer than the window, and "I pulled again the
    /// instant the last one stopped" is the thing being measured.
    public static func shouldOfferReAdd(blocked: Int,
                                        previousManualSyncAt: Date?,
                                        declinedAt: Date? = nil,
                                        now: Date = Date(),
                                        windowS: TimeInterval = reAddWindowS) -> Bool {
        guard blocked > 0, let previous = previousManualSyncAt else { return false }
        let sinceLastSync = now.timeIntervalSince(previous)
        guard sinceLastSync >= 0, sinceLastSync <= windowS else { return false }
        if let declinedAt, now.timeIntervalSince(declinedAt) <= windowS { return false }
        return true
    }

    /// "Re-add 2 previously deleted sessions?" — one sentence, correctly pluralised, because
    /// the sheet that carries it is the only place the rider ever sees this feature work.
    public static func reAddQuestion(count: Int) -> String {
        "Re-add \(count) previously deleted session\(count == 1 ? "" : "s")?"
    }

    // MARK: - What the sheet offers

    /// The blocked sessions, arranged the way a rider has to pick through them.
    ///
    /// **Why a picker and not a yes/no.** "Re-add 6 previously deleted sessions?" is an
    /// all-or-nothing question about six different afternoons, and the rider who pulled twice
    /// was almost certainly looking for *one* of them — the one he deleted by mistake, this
    /// morning, with a swipe that went further than he meant. Answering yes brings back five
    /// he threw away on purpose, and answering no leaves him where he started.
    public struct ReAddCandidates: Sendable, Equatable {
        /// Newest session first — the library's own order, so the sheet reads like the list
        /// the rider just swiped in.
        public var stones: [SessionTombstoneRow]
        /// The day of the most recent deleted session, offered as a one-tap subset. nil when
        /// the shortcut would be pointless: a list that is all one day already *is* the
        /// shortcut, and a short list is faster to tick than to reason about.
        public var recentDay: Date?
        /// The ids that shortcut selects.
        public var recentDayIds: [String]

        public var count: Int { stones.count }

        /// Whether it is worth offering "select all" as a control rather than expecting three
        /// taps. Below this the toggles are the whole interface.
        public var offersSelectAll: Bool { stones.count > 1 }
    }

    /// The smallest list that is worth narrowing by day. Three rows fit on a compact sheet
    /// with room to think; a shortcut over three rows is a second way to do something that is
    /// already one tap each.
    public static let dayShortcutThreshold = 4

    /// Arranges the blocked tombstones for the sheet: newest first, with the most recent
    /// session-day picked out when there is enough spread to make that a useful subset.
    ///
    /// Grouped by the **session's own day**, not by when it was deleted: a rider who cleared
    /// out a bad week in one sitting deleted them all within a minute of each other, so
    /// deletion time would put every one of them in the same bucket and answer nothing. What
    /// he remembers is "the Tuesday session".
    public static func candidates(_ stones: [SessionTombstoneRow],
                                  calendar: Calendar = Calendar(identifier: .gregorian),
                                  threshold: Int = dayShortcutThreshold) -> ReAddCandidates {
        let sorted = stones.sorted { $0.startDate > $1.startDate }
        guard sorted.count >= threshold, let newest = sorted.first else {
            return ReAddCandidates(stones: sorted, recentDay: nil, recentDayIds: [])
        }
        let day = calendar.startOfDay(for: newest.startDate)
        let sameDay = sorted.filter { calendar.isDate($0.startDate, inSameDayAs: newest.startDate) }
        // All on one day: the shortcut would select the whole list, which "Select all"
        // already does and says more plainly.
        guard sameDay.count < sorted.count else {
            return ReAddCandidates(stones: sorted, recentDay: nil, recentDayIds: [])
        }
        return ReAddCandidates(stones: sorted, recentDay: day, recentDayIds: sameDay.map(\.id))
    }
}
