import Foundation
import GRDB
import Testing
@testable import WingFoilKit

/// The decision half of the "new Garmin session" notification: which activities are new,
/// what the mark becomes, and what the banner says. No `BGTaskScheduler`, no notification
/// centre, no network — every rule that can be got wrong lives in these functions.
@Suite struct NewActivityWatchTests {

    private let now = Date(timeIntervalSince1970: 1_790_000_000)   // 2026-09-21 ish

    /// Local wall-clock string in the shape intervals.icu returns, for a date offset from
    /// `now`. Goes back through `IcuActivity.startDate`, so the round trip is the one the
    /// production code makes.
    private func stamp(daysAgo: Double) -> String {
        let date = now.addingTimeInterval(-daysAgo * 86_400)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.string(from: date)
    }

    private func activity(_ id: String, daysAgo: Double, name: String = "Windsurfen",
                          type: String? = "Windsurf", movingTimeS: Int? = 7020,
                          distanceM: Double? = 23_000) -> IcuActivity {
        IcuActivity(id: id, name: name, type: type, startDateLocal: stamp(daysAgo: daysAgo),
                    movingTimeS: movingTimeS, distanceM: distanceM)
    }

    private func known(_ activity: IcuActivity, icuActivityId: String? = nil,
                       durationS: Double = 7200) -> NewActivityWatch.KnownSession {
        NewActivityWatch.KnownSession(icuActivityId: icuActivityId,
                                      startDate: activity.startDate!, durationS: durationS)
    }

    // MARK: - Seeding

    /// The trap this feature could most easily fall into: the rider flips the toggle and
    /// the phone announces two years of windsurfing. The first poll writes the history
    /// down as seen and says nothing.
    @Test func firstPollAnnouncesNothingAndSeedsTheMark() {
        let listed = [activity("i1", daysAgo: 0.2), activity("i2", daysAgo: 2)]
        let decision = NewActivityWatch.evaluate(activities: listed, library: [],
                                                 mark: NewActivityMark(), now: now)
        #expect(decision.seeding)
        #expect(decision.notices.isEmpty)
        #expect(Set(decision.mark.announcedIds) == ["i1", "i2"])
        #expect(decision.mark.isSeeded)
        #expect(decision.mark.lastStartDate == listed[0].startDate)
    }

    /// …and an empty account still seeds, or every wake for ever would be a first poll.
    @Test func firstPollWithNoActivitiesStillSeeds() {
        let decision = NewActivityWatch.evaluate(activities: [], library: [],
                                                 mark: NewActivityMark(), now: now)
        #expect(decision.mark.lastStartDate == now)
        #expect(decision.mark.isSeeded)
    }

    // MARK: - What is new

    @Test func announcesOnlyTheUnseenWatersportActivities() {
        let seeded = NewActivityMark(lastStartDate: now.addingTimeInterval(-3 * 86_400),
                                     announcedIds: ["old"])
        let listed = [
            activity("old", daysAgo: 3),
            activity("new", daysAgo: 0.1),
            activity("ride", daysAgo: 0.2, name: "Morning Ride", type: "Ride"),
            // Filed as Walk by Garmin, rescued by the name — the CIQ recordings.
            activity("ciq", daysAgo: 0.3, name: "Wingfoiling", type: "Walk"),
        ]
        let decision = NewActivityWatch.evaluate(activities: listed, library: [],
                                                 mark: seeded, now: now)
        #expect(!decision.seeding)
        #expect(decision.notices.map(\.activityId) == ["ciq", "new"])   // oldest first
        #expect(!decision.mark.announcedIds.contains("ride"))
        #expect(decision.mark.announcedIds.contains("new"))
    }

    /// A session the rider already imported by hand between two wakes is not news.
    @Test func skipsActivitiesAlreadyInTheLibrary() {
        let seeded = NewActivityMark(lastStartDate: now.addingTimeInterval(-3 * 86_400))
        let imported = activity("i9", daysAgo: 0.5)
        let decision = NewActivityWatch.evaluate(
            activities: [imported], library: [known(imported, icuActivityId: "i9")],
            mark: seeded, now: now)
        #expect(decision.notices.isEmpty)
        // Still remembered: deleting it later must not make it "new" again.
        #expect(decision.mark.announcedIds == ["i9"])
    }

    /// The same activity twice in a row — the poll window overlaps every wake, so this is
    /// the common case, not an edge one.
    @Test func announcesEachActivityExactlyOnce() {
        var mark = NewActivityMark(lastStartDate: now.addingTimeInterval(-3 * 86_400))
        let listed = [activity("i1", daysAgo: 0.5)]
        let first = NewActivityWatch.evaluate(activities: listed, library: [], mark: mark, now: now)
        #expect(first.notices.count == 1)
        mark = first.mark
        let second = NewActivityWatch.evaluate(activities: listed, library: [], mark: mark, now: now)
        #expect(second.notices.isEmpty)
    }

    /// An activity uploaded late is dated when it was *ridden*, so it sorts below the
    /// high-water mark. The id memory, not the date, is what decides.
    @Test func announcesAnActivityUploadedAfterANewerOne() {
        let mark = NewActivityMark(lastStartDate: now.addingTimeInterval(-0.2 * 86_400),
                                   announcedIds: ["today"])
        let late = activity("yesterday", daysAgo: 1)
        let decision = NewActivityWatch.evaluate(activities: [activity("today", daysAgo: 0.2), late],
                                                 library: [], mark: mark, now: now)
        #expect(decision.notices.map(\.activityId) == ["yesterday"])
    }

    @Test func capsTheBurstAtTheNewestThree() {
        let mark = NewActivityMark(lastStartDate: now.addingTimeInterval(-9 * 86_400))
        let listed = (1...6).map { activity("i\($0)", daysAgo: Double(7 - $0)) }
        let decision = NewActivityWatch.evaluate(activities: listed, library: [],
                                                 mark: mark, now: now)
        #expect(decision.notices.map(\.activityId) == ["i4", "i5", "i6"])
        // The two that were not announced are still written down as seen: a burst is
        // capped once, not deferred to the next wake for ever.
        #expect(decision.mark.announcedIds.count == 6)
    }

    // MARK: - The library dedupe key

    /// intervals.icu reports moving time, the library stores elapsed time. A session with
    /// a beach break in it is genuinely shorter on icu's side, and a two-sided ±60 s would
    /// call it a different session and announce a recording the rider already has.
    @Test func dedupeKeyToleratesMovingTimeShorterThanElapsed() {
        let paused = activity("i1", daysAgo: 1, movingTimeS: 5400)
        let library = [known(paused, durationS: 7200)]                    // 30 min of breaks
        #expect(NewActivityWatch.isInLibrary(paused, library: library))
    }

    @Test func dedupeKeyMatchesOnStartJitterAndSeparatesRealSessions() {
        let listed = activity("i1", daysAgo: 1, movingTimeS: 7000)
        let jittered = NewActivityWatch.KnownSession(
            icuActivityId: nil, startDate: listed.startDate!.addingTimeInterval(45),
            durationS: 7020)
        #expect(NewActivityWatch.isInLibrary(listed, library: [jittered]))

        let anotherAfternoon = NewActivityWatch.KnownSession(
            icuActivityId: nil, startDate: listed.startDate!.addingTimeInterval(3 * 3600),
            durationS: 7020)
        #expect(!NewActivityWatch.isInLibrary(listed, library: [anotherAfternoon]))

        // Same start, but far longer on icu's side than the stored row: not the same ride.
        let stub = NewActivityWatch.KnownSession(
            icuActivityId: nil, startDate: listed.startDate!, durationS: 300)
        #expect(!NewActivityWatch.isInLibrary(listed, library: [stub]))
    }

    @Test func dedupeKeyPrefersTheActivityId() {
        let listed = activity("i42", daysAgo: 1)
        let unrelatedDate = NewActivityWatch.KnownSession(
            icuActivityId: "i42", startDate: .distantPast, durationS: 1)
        #expect(NewActivityWatch.isInLibrary(listed, library: [unrelatedDate]))
    }

    // MARK: - The window

    @Test func windowNeverNarrowerThanTheLookbackNorWiderThanTheCeiling() {
        let day = 86_400.0
        // Fresh install: the plain lookback.
        #expect(NewActivityWatch.windowStart(mark: NewActivityMark(), now: now)
                == now.addingTimeInterval(-Double(NewActivityWatch.lookbackDays) * day))
        // Rode this morning: still four days back, so a missed wake costs nothing.
        let recent = NewActivityMark(lastStartDate: now.addingTimeInterval(-3600))
        #expect(NewActivityWatch.windowStart(mark: recent, now: now)
                == now.addingTimeInterval(-Double(NewActivityWatch.lookbackDays) * day))
        // Away for a fortnight: one call covers it.
        let stale = NewActivityMark(lastStartDate: now.addingTimeInterval(-14 * day))
        #expect(NewActivityWatch.windowStart(mark: stale, now: now)
                == now.addingTimeInterval(-14 * day))
        // Away for a winter: clamped, because the response is what pays for it.
        let ancient = NewActivityMark(lastStartDate: now.addingTimeInterval(-400 * day))
        #expect(NewActivityWatch.windowStart(mark: ancient, now: now)
                == now.addingTimeInterval(-Double(NewActivityWatch.windowCeilingDays) * day))
    }

    // MARK: - The mark itself

    @Test func markEvictsTheOldestIdsAtTheCap() {
        var mark = NewActivityMark()
        mark.remember(ids: (0..<(NewActivityMark.announcedLimit + 10)).map { "i\($0)" })
        #expect(mark.announcedIds.count == NewActivityMark.announcedLimit)
        #expect(mark.announcedIds.first == "i10")
        #expect(mark.announcedIds.last == "i\(NewActivityMark.announcedLimit + 9)")
    }

    @Test func markIgnoresIdsItAlreadyHas() {
        var mark = NewActivityMark(announcedIds: ["a", "b"])
        mark.remember(ids: ["b", "c", "b"])
        #expect(mark.announcedIds == ["a", "b", "c"])
    }

    @Test func markSurvivesAJSONRoundTrip() throws {
        let mark = NewActivityMark(lastStartDate: now, announcedIds: ["i1", "i2"])
        let decoded = try JSONDecoder().decode(NewActivityMark.self,
                                               from: try JSONEncoder().encode(mark))
        #expect(decoded == mark)
    }

    // MARK: - What the banner says

    /// The two numbers the KEY METRICS block opens with, formatted its way, because the
    /// rider reads them again ten seconds later at the top of the session.
    @Test func noticeReadsLikeTheKeyMetricsBlock() {
        let notice = NewActivityWatch.notice(
            for: activity("i1", daysAgo: 0.1, name: "Nago-Torbole Windsurfen",
                          movingTimeS: 7020, distanceM: 23_000))
        #expect(notice.title == "New session")
        #expect(notice.subtitle == "Nago-Torbole Windsurfen")
        #expect(notice.body == "1:57 h · 23.0 km — tap to analyze")
        #expect(notice.activityId == "i1")
    }

    @Test func noticeDegradesWithTheSummaryItIsGiven() {
        let bare = NewActivityWatch.notice(
            for: IcuActivity(id: "i2", name: "   ", type: "Windsurf"))
        #expect(bare.subtitle == nil)
        #expect(bare.body == "Tap to import and analyze")

        let distanceOnly = NewActivityWatch.notice(
            for: IcuActivity(id: "i3", name: "Session", type: "Windsurf", distanceM: 4200))
        #expect(distanceOnly.body == "4.2 km — tap to analyze")
    }
}

/// The one-time offer that gets the feature above discovered at all. Four booleans, so the
/// interesting part is which combinations must stay silent: every one of them is a way of
/// asking a rider something he has already answered.
@Suite struct NewActivityPromptTests {

    @Test func aConfiguredRiderWhoHasNotBeenAskedIsAsked() {
        #expect(NewActivityPrompt.shouldAsk(hasKey: true, isEnabled: false, hasAsked: false))
    }

    @Test func theOfferIsNeverMadeTwiceAndNeverToSomeoneWhoAlreadySaidYes() {
        // "Not now" (or an app swiped away with the alert up) is written down as asked.
        #expect(!NewActivityPrompt.shouldAsk(hasKey: true, isEnabled: false, hasAsked: true))
        // Found the Settings toggle himself: there is nothing to offer.
        #expect(!NewActivityPrompt.shouldAsk(hasKey: true, isEnabled: true, hasAsked: false))
        #expect(!NewActivityPrompt.shouldAsk(hasKey: true, isEnabled: true, hasAsked: true))
    }

    @Test func setupHasToBeFinishedFirst() {
        // No key, nothing to poll — the same reason the Settings toggle is disabled there.
        for enabled in [false, true] {
            for asked in [false, true] {
                #expect(!NewActivityPrompt.shouldAsk(hasKey: false, isEnabled: enabled,
                                                     hasAsked: asked))
            }
        }
    }

    @Test func aBusyScreenDefersTheOfferRatherThanSpendingIt() {
        // The only "no" that is not final: nothing is written down, and the same call on
        // the next clear screen says yes.
        #expect(!NewActivityPrompt.shouldAsk(hasKey: true, isEnabled: false, hasAsked: false,
                                             isPresenting: true))
        #expect(NewActivityPrompt.shouldAsk(hasKey: true, isEnabled: false, hasAsked: false,
                                            isPresenting: false))
    }
}

/// The other half of a background wake: one activity, downloaded and ingested while iOS is
/// still granting time. Same client, same ingestor, same dedupe key as the manual sync —
/// this proves the shortcut really is the same path and not a second one.
@Suite struct IcuFetchOneTests {

    private struct StubTransport: IcuTransport {
        let body: Data

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            (body, HTTPURLResponse(url: request.url!, statusCode: 200,
                                   httpVersion: nil, headerFields: nil)!)
        }
    }

    @Test func fetchesAndIngestsOneActivityAndThenDedupes() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-fetchone-\(UUID().uuidString)/Sessions",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let ingestor = SessionIngestor(database: try AppDatabase.inMemory(),
                                       archive: SessionArchive(root: root))
        let client = IcuClient(apiKey: "k",
                               transport: StubTransport(body: try ExampleSession.data()))
        let service = IcuSyncService(client: client, ingestor: ingestor)
        let activity = IcuActivity(id: "i86544321", name: "Nago-Torbole Windsurfen",
                                   type: "Windsurf")

        guard case .imported(let row) = try await service.fetchOne(activity) else {
            Issue.record("expected a fresh import"); return
        }
        #expect(row.icuActivityId == "i86544321")
        #expect(row.importSource == "icu")
        #expect(row.originalFilename == "i86544321_nago-torbole-windsurfen_icu.fit")

        // The notification path and the manual sync must not be able to import twice.
        guard case .duplicate = try await service.fetchOne(activity) else {
            Issue.record("a second fetch of the same activity must dedupe"); return
        }
        // …and no import_log row: an unattended prefetch is not an import the rider began.
        #expect(try await ingestor.library.importLog().isEmpty)
    }
}
