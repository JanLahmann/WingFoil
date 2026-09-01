import Foundation
import GRDB
import Testing
@testable import WingFoilKit

/// Deleting a session has to mean it. The two halves are tested apart, because they fail
/// differently: the **matcher** decides whether an incoming activity is one the rider threw
/// away (a silent wrong answer resurrects a session, or hides a real new one), and the
/// **gate** decides whether he is ever asked about it (a wrong answer here is either a nag
/// on every pull or a feature nobody can find). Both are pure; the round trip through GRDB
/// is checked once at the bottom.
@Suite struct TombstoneTests {

    private let start = Date(timeIntervalSince1970: 1_788_091_620)   // 30 Aug 2026, 14:07 CEST

    private func stone(id: String, icu: String? = nil, at offset: TimeInterval = 0,
                       durationS: Double = 645) -> SessionTombstoneRow {
        SessionTombstoneRow(id: id, icuActivityId: icu,
                            startDate: start.addingTimeInterval(offset), durationS: durationS)
    }

    /// The activity as intervals.icu lists it: local wall-clock without a zone, and **moving**
    /// time rather than elapsed.
    private func activity(id: String, at offset: TimeInterval = 0,
                          movingTimeS: Int? = 645) -> IcuActivity {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = .current
        return IcuActivity(id: id, name: "Torbole", type: "Windsurf",
                           startDateLocal: formatter.string(from: start.addingTimeInterval(offset)),
                           movingTimeS: movingTimeS)
    }

    // MARK: - The matcher

    /// The exact answer when there is one: the session carried an intervals.icu id, so the
    /// same id coming back is the same session, whatever the clocks say.
    @Test func theIcuIdIsMatchedFirstAndExactly() {
        let stones = [stone(id: "row-a", icu: "i86544321")]
        #expect(SessionTombstones.blocks(activity(id: "i86544321"), tombstones: stones)?.id
                == "row-a")
        // A different activity at a different time is simply a different session.
        #expect(SessionTombstones.blocks(activity(id: "i99999999", at: 90_000),
                                         tombstones: stones) == nil)
    }

    /// The case the id half cannot see, and the reason every deletion is tombstoned rather
    /// than only the synced ones: a session imported from a Garmin GDPR ZIP has **no**
    /// intervals.icu id, and is on intervals.icu all the same. Deleting it and syncing would
    /// otherwise import it straight back under an id the library has never met.
    @Test func aTombstoneWithNoIcuIdStillCatchesTheSameSession() {
        let stones = [stone(id: "row-gdpr")]
        #expect(SessionTombstones.blocks(activity(id: "i86544321"), tombstones: stones)?.id
                == "row-gdpr")
        // …within the library's own ±60 s dedupe key, and not outside it.
        #expect(SessionTombstones.blocks(activity(id: "x", at: 59), tombstones: stones) != nil)
        #expect(SessionTombstones.blocks(activity(id: "x", at: -59), tombstones: stones) != nil)
        #expect(SessionTombstones.blocks(activity(id: "x", at: 61), tombstones: stones) == nil)
    }

    /// The duration half is one-sided, exactly as `NewActivityWatch.isInLibrary` is: icu
    /// reports moving time and the library stored elapsed time, so a session with a long
    /// beach break in it is genuinely much shorter on icu's side and a two-sided ±60 s would
    /// call it a different session and bring it back.
    @Test func theDurationComparisonIsOneSidedBecauseIcuReportsMovingTime() {
        let stones = [stone(id: "row-a", durationS: 645)]
        #expect(SessionTombstones.blocks(activity(id: "x", movingTimeS: 300),
                                         tombstones: stones) != nil)
        #expect(SessionTombstones.blocks(activity(id: "x", movingTimeS: 704),
                                         tombstones: stones) != nil)
        // Longer than the deleted session by more than the tolerance: a different, longer
        // afternoon that happens to start at the same minute.
        #expect(SessionTombstones.blocks(activity(id: "x", movingTimeS: 706),
                                         tombstones: stones) == nil)
        // An activity intervals.icu has not measured yet is matched on the start alone —
        // "nothing measured" must not read as "zero seconds long".
        #expect(SessionTombstones.blocks(activity(id: "x", movingTimeS: nil),
                                         tombstones: stones) != nil)
    }

    /// An activity with no start date at all can only be matched by id. Degrading rather
    /// than guessing: the alternative is blocking a session on no evidence.
    @Test func anUndatedActivityIsOnlyEverMatchedById() {
        let undated = IcuActivity(id: "i1", startDateLocal: nil)
        #expect(SessionTombstones.blocks(undated, tombstones: [stone(id: "a")]) == nil)
        #expect(SessionTombstones.blocks(undated, tombstones: [stone(id: "a", icu: "i1")]) != nil)
    }

    @Test func anEmptyTombstoneListBlocksNothing() {
        #expect(SessionTombstones.blocks(activity(id: "i1"), tombstones: []) == nil)
    }

    // MARK: - The gate

    /// The whole rule Jan asked for: pull, nothing arrives, pull again *straight away* —
    /// that is when the app asks. One sync on its own never does, however many sessions it
    /// skipped, and neither does a sync a minute later.
    @Test func onlyAnImmediateSecondSyncAsks() {
        let now = Date()
        let window = SessionTombstones.reAddWindowS
        #expect(window == 10)
        #expect(SessionTombstones.shouldOfferReAdd(
            blocked: 2, previousManualSyncAt: now.addingTimeInterval(-3), now: now))
        // The first sync of an install cannot be a second attempt at anything.
        #expect(!SessionTombstones.shouldOfferReAdd(blocked: 2, previousManualSyncAt: nil,
                                                    now: now))
        // Half a minute is already "I looked at the list, thought about it, and pulled
        // again" — an ordinary sync, which must not be interrupted by a question about
        // something the rider deleted on purpose.
        #expect(!SessionTombstones.shouldOfferReAdd(
            blocked: 2, previousManualSyncAt: now.addingTimeInterval(-30), now: now))
        #expect(!SessionTombstones.shouldOfferReAdd(
            blocked: 2, previousManualSyncAt: now.addingTimeInterval(-window - 1), now: now))
        // The boundary itself counts as inside.
        #expect(SessionTombstones.shouldOfferReAdd(
            blocked: 1, previousManualSyncAt: now.addingTimeInterval(-window), now: now))
    }

    /// Nothing skipped, nothing to ask about — which is every sync on every install where
    /// the rider has never deleted anything.
    @Test func aSyncThatSkippedNothingIsSilent() {
        let now = Date()
        #expect(!SessionTombstones.shouldOfferReAdd(
            blocked: 0, previousManualSyncAt: now.addingTimeInterval(-5), now: now))
    }

    /// "Keep deleted" is listened to. Without the damper the very next pull — which is inside
    /// the window by construction, since the pull that asked just set the mark — would ask
    /// the identical question again.
    @Test func aRefusalKeepsTheOfferDownForTheSameWindow() {
        let now = Date()
        let window = SessionTombstones.reAddWindowS
        #expect(!SessionTombstones.shouldOfferReAdd(
            blocked: 3, previousManualSyncAt: now.addingTimeInterval(-2),
            declinedAt: now.addingTimeInterval(-2), now: now))
        // …and it is a damper, not a permanent silence: another deliberate double-pull, once
        // the window has passed, is a rider asking again.
        #expect(SessionTombstones.shouldOfferReAdd(
            blocked: 3, previousManualSyncAt: now.addingTimeInterval(-2),
            declinedAt: now.addingTimeInterval(-window - 1), now: now))
    }

    // MARK: - What the picker offers

    /// Newest session first — the library's own order, so the sheet reads like the list the
    /// rider just swiped in.
    @Test func candidatesComeBackNewestSessionFirst() {
        let stones = [stone(id: "old", at: -172_800), stone(id: "new", at: 3600),
                      stone(id: "mid", at: -86_400)]
        #expect(SessionTombstones.candidates(stones).stones.map(\.id)
                == ["new", "mid", "old"])
    }

    /// The day shortcut earns its place only when it narrows something. A short list is
    /// faster to tick than to reason about, and a list that is all one day *is* what the
    /// shortcut would select — "Select all" says that more plainly.
    @Test func theDayShortcutOnlyAppearsWhenItNarrowsALongList() {
        // Three sessions across three days: short enough that per-row taps are the interface.
        let short = (0..<3).map { stone(id: "s\($0)", at: Double($0) * -86_400) }
        #expect(SessionTombstones.candidates(short).recentDay == nil)

        // Five, all on the same afternoon: the shortcut would select every one of them.
        let sameDay = (0..<5).map { stone(id: "d\($0)", at: Double($0) * 600) }
        #expect(SessionTombstones.candidates(sameDay).recentDay == nil)

        // Five across three days: two on the newest, and that is a useful subset.
        var spread = (0..<3).map { stone(id: "old\($0)", at: Double($0 + 1) * -86_400) }
        spread.append(stone(id: "today-a", at: 0))
        spread.append(stone(id: "today-b", at: 7200))
        let candidates = SessionTombstones.candidates(spread)
        #expect(candidates.recentDay != nil)
        #expect(Set(candidates.recentDayIds) == ["today-a", "today-b"])
        // …and the day is the *session's* day, not the deletion's: a rider who cleared out a
        // bad week in one sitting deleted them all within a minute of each other, so grouping
        // by `deletedAt` would put every one of them in one bucket and answer nothing.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        #expect(candidates.recentDay == calendar.startOfDay(for: start.addingTimeInterval(7200)))
    }

    /// One deleted session needs no bulk controls at all.
    @Test func aSingleCandidateOffersNoShortcuts() {
        let one = SessionTombstones.candidates([stone(id: "only")])
        #expect(!one.offersSelectAll)
        #expect(one.recentDay == nil)
        #expect(one.count == 1)
        #expect(SessionTombstones.candidates([]).stones.isEmpty)
    }

    /// A clock that went backwards (a manual time change, a restored backup) must not read as
    /// "no time has passed".
    @Test func aSyncMarkFromTheFutureDoesNotAsk() {
        let now = Date()
        #expect(!SessionTombstones.shouldOfferReAdd(
            blocked: 1, previousManualSyncAt: now.addingTimeInterval(60), now: now))
    }

    @Test func theQuestionIsPluralisedCorrectly() {
        #expect(SessionTombstones.reAddQuestion(count: 1)
                == "Re-add 1 previously deleted session?")
        #expect(SessionTombstones.reAddQuestion(count: 4)
                == "Re-add 4 previously deleted sessions?")
    }

    // MARK: - The round trip

    /// Deleting really does leave a tombstone, restoring really does remove it, and the
    /// bundled example really is left out of both — it is not the rider's session and cannot
    /// come back from intervals.icu, so counting it in "Previously deleted" would be an offer
    /// to restore something no sync was ever going to restore.
    @Test func deletingWritesATombstoneAndRestoringForgetsIt() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-tombstone-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase.inMemory()
        let ingestor = SessionIngestor(database: database, archive: SessionArchive(root: root))
        let store = LibraryStore(database: database)

        var synced = SessionRow(startDate: start, durationS: 645, sourceClass: "a")
        synced.icuActivityId = "i86544321"
        var example = SessionRow(startDate: start.addingTimeInterval(90_000), durationS: 400,
                                 sourceClass: "a")
        example.isExample = true
        let rows = [synced, example]
        try await database.writer.write { db in for row in rows { try row.insert(db) } }

        try await ingestor.delete(synced, title: "Torbole")
        try await ingestor.delete(example, title: "Example")

        let stones = try await store.tombstones()
        #expect(stones.map(\.id) == [synced.id])
        #expect(stones.first?.icuActivityId == "i86544321")
        #expect(stones.first?.title == "Torbole")
        #expect(try await store.tombstoneCount() == 1)
        // …and it does what it is for: the activity it came from is now blocked.
        #expect(SessionTombstones.blocks(activity(id: "i86544321"), tombstones: stones) != nil)

        try await store.forgetTombstones(ids: [synced.id])
        #expect(try await store.tombstoneCount() == 0)
    }

    /// The Settings escape hatch: everything, in one call, so nobody is permanently stuck.
    @Test func restoringAllForgetsEveryTombstone() async throws {
        let database = try AppDatabase.inMemory()
        let store = LibraryStore(database: database)
        let stones = [stone(id: "a", icu: "i1"), stone(id: "b", at: 90_000)]
        try await database.writer.write { db in for row in stones { try row.insert(db) } }

        #expect(try await store.tombstoneCount() == 2)
        try await store.forgetAllTombstones()
        #expect(try await store.tombstones().isEmpty)
        // Forgetting nothing is not an error — the Settings section is only shown when the
        // count is above zero, but a stale tap must not throw.
        try await store.forgetTombstones(ids: [])
    }

    /// v6 exists, is registered, and a v1 library reaches it.
    @Test func v6AddsTheDeletedSessionTable() throws {
        #expect(AppDatabase.migrationNames
                == ["v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8", "v9"])
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v1")
        #expect(try queue.read { try !$0.tableExists("deleted_session") })
        _ = try AppDatabase(queue)
        try queue.read { db in
            #expect(try db.tableExists("deleted_session"))
            let columns = Set(try db.columns(in: "deleted_session").map(\.name))
            #expect(columns == ["id", "icuActivityId", "startDate", "durationS", "title",
                                "deletedAt"])
        }
    }
}
