import Foundation
import Testing
@testable import WingFoilKit

/// **The watch's recording wins, whichever door opened first** — at the level of the
/// intervals.icu *sync*, not just the ingestor (F-6, docs/algorithms/imports.md "Which copy
/// the library keeps").
///
/// Jan, 1 Oct 2026: intervals.icu is connected in his dev app, and still his 4 Sep 07:58
/// session is the Strava copy. The ingestor has replaced a positions-only row with the FIT of
/// the same afternoon since 26 Sep; the sync never got that far. A Strava row that an earlier
/// sync had met as a plain duplicate — before F-6 a FIT arriving after Strava's copy merged
/// its provenance and nothing else — carries the intervals.icu id on it, and the sync skips
/// every id the library already holds *before the download*. So the FIT was never fetched
/// again, and the Strava copy stayed for good.
///
/// Played on the 13 June 2026 fixture (record span 10 338 s, fix span 7 742 s, the F-5 pair),
/// with the activity summary as intervals.icu lists it: its own name and type, the UTC start
/// beside a zone-less local one, and a moving time shorter than the elapsed span.
struct IcuAfterStravaTests {

    /// Serves one activity list and the FIT behind it, and counts the downloads.
    /// The activity and its file can change between pulls, as an upload replaced on
    /// intervals.icu does.
    final class OneAfternoon: IcuTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var _list: Data
        private var _fit: Data
        private var _downloads = 0
        var downloads: Int { lock.withLock { _downloads } }

        init(activity: IcuActivity, fit: Data) throws {
            _list = try JSONEncoder().encode([activity])
            _fit = fit
        }

        /// What intervals.icu lists and serves from the next request on.
        func replace(activity: IcuActivity, fit: Data) throws {
            let list = try JSONEncoder().encode([activity])
            lock.withLock { _list = list; _fit = fit }
        }

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let url = request.url!
            let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                     headerFields: nil)!
            if url.path.hasSuffix("/activities") { return (lock.withLock { _list }, ok) }
            return lock.withLock {
                _downloads += 1
                return (_fit, ok)
            }
        }
    }

    private static let icuID = "i183166245"

    /// The afternoon as intervals.icu lists it: the FIT's own first record in UTC, the wall
    /// clock two hours ahead with no zone, and a moving time well short of the span.
    private static func activity(for fit: Data) throws -> IcuActivity {
        let track = try FitSessionParser.parse(data: fit)
        let start = try #require(track.startDate)
        let utc = ISO8601DateFormatter()
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = TimeZone(identifier: "Europe/Rome")
        local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return IcuActivity(id: icuID, name: "Nago Torbole Windsurfen", type: "Windsurf",
                           startDateLocal: local.string(from: start),
                           startDateUtc: utc.string(from: start), timezone: "Europe/Rome",
                           movingTimeS: 5618)
    }

    private func makeIngestor() throws -> (SessionIngestor, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("icu-after-strava-\(UUID().uuidString)/Sessions",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (SessionIngestor(database: try AppDatabase.inMemory(),
                                archive: SessionArchive(root: root)), root)
    }

    private func sync(_ ingestor: SessionIngestor, _ transport: OneAfternoon) async throws
            -> IcuSyncSummary {
        let service = IcuSyncService(client: IcuClient(apiKey: "k", transport: transport),
                                     ingestor: ingestor)
        return try await service.sync(oldest: Date(timeIntervalSince1970: 1_750_000_000))
    }

    private func importStrava(_ ingestor: SessionIngestor,
                              _ copy: (gpx: Data, activity: StravaActivity, fitSpanS: Double,
                                       fixSpanS: Double)) async throws -> SessionRow {
        guard case .imported(let row) = try await ingestor.ingest(
            fitData: copy.gpx, filename: StravaImport.filename(for: copy.activity),
            source: .strava, utcOffsetS: 7200) else {
            Issue.record("expected the Strava copy to import")
            throw CancellationError()
        }
        #expect(row.sourceClass == "c")
        return row
    }

    private func expectTheFit(_ ingestor: SessionIngestor, id: String? = nil) async throws {
        let rows = try await ingestor.allSessions()
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        if let id { #expect(row.id == id) }
        #expect(row.sourceClass != "c", "the library keeps the watch's recording")
        #expect(row.icuActivityId == Self.icuID)
        #expect(ingestor.archive.originalFormat(for: row.id) == .fit)
    }

    /// Strava first, then the sync: the FIT is downloaded and takes the Strava row's place.
    @Test func stravaFirstThenTheSyncKeepsTheFit() async throws {
        let (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let (_, fit, copy) = try StravaImportTests.thirteenJune()
        let strava = try await importStrava(ingestor, copy)
        let transport = try OneAfternoon(activity: Self.activity(for: fit), fit: fit)

        let summary = try await sync(ingestor, transport)
        #expect(summary.replaced.map(\.id) == [strava.id])
        #expect(transport.downloads == 1)
        try await expectTheFit(ingestor, id: strava.id)

        // A re-sync downloads nothing: the id is now held by the recording it names.
        let again = try await sync(ingestor, transport)
        #expect(again.alreadyKnown == 1 && again.replaced.isEmpty)
        #expect(transport.downloads == 1)
        try await expectTheFit(ingestor, id: strava.id)
    }

    /// The other order: the sync first, Strava's copy after. It merges its provenance.
    @Test func theSyncFirstThenStravaKeepsTheFit() async throws {
        let (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let (_, fit, copy) = try StravaImportTests.thirteenJune()
        let transport = try OneAfternoon(activity: Self.activity(for: fit), fit: fit)
        let summary = try await sync(ingestor, transport)
        #expect(summary.imported == 1)
        guard case .duplicate(let row) = try await ingestor.ingest(
            fitData: copy.gpx, filename: StravaImport.filename(for: copy.activity),
            source: .strava, utcOffsetS: 7200) else {
            Issue.record("expected Strava's copy to land on the FIT's row")
            return
        }
        #expect(row.importSource == "icu+strava")
        try await expectTheFit(ingestor)
    }

    /// **The library that never healed.** A Strava row carrying the intervals.icu id — what a
    /// sync before 26 Sep left behind when it met the FIT as a duplicate — is not "already
    /// known": the id names a recording the row does not hold. The next sync downloads the
    /// FIT and replaces the row, keeping its id; the one after that downloads nothing.
    @Test func aStravaRowCarryingTheIcuIdHealsOnTheNextSync() async throws {
        let (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let (_, fit, copy) = try StravaImportTests.thirteenJune()
        let strava = try await importStrava(ingestor, copy)
        let stamped = try await ingestor.note(strava, source: .icu, icuActivityId: Self.icuID)
        #expect(stamped.icuActivityId == Self.icuID && stamped.sourceClass == "c")

        let transport = try OneAfternoon(activity: Self.activity(for: fit), fit: fit)
        let summary = try await sync(ingestor, transport)
        #expect(summary.alreadyKnown == 0)
        #expect(summary.replaced.map(\.id) == [strava.id])
        try await expectTheFit(ingestor, id: strava.id)

        let again = try await sync(ingestor, transport)
        #expect(again.alreadyKnown == 1)
        #expect(transport.downloads == 1)
    }

    /// The id a row holds stays "known" when the row's recording IS intervals.icu's own, even
    /// a positions-only one (a Polar or Suunto upload): no download on every pull.
    @Test func anIcuRecordingWithoutSpeedIsStillKnown() async throws {
        let (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let (_, fit, copy) = try StravaImportTests.thirteenJune()
        let activity = try Self.activity(for: fit)
        guard case .imported(let row) = try await ingestor.ingest(
            fitData: copy.gpx, filename: IcuSyncService.filename(for: activity),
            source: .icu, icuActivityId: Self.icuID) else {
            Issue.record("expected a fresh import")
            return
        }
        #expect(row.sourceClass == "c")
        let transport = try OneAfternoon(activity: activity, fit: copy.gpx)
        let summary = try await sync(ingestor, transport)
        #expect(summary.alreadyKnown == 1)
        #expect(transport.downloads == 0)
    }

    // MARK: - The background poller heals too, and a positions-only source is asked once

    private func service(_ ingestor: SessionIngestor, _ transport: OneAfternoon) -> IcuSyncService {
        IcuSyncService(client: IcuClient(apiKey: "k", transport: transport), ingestor: ingestor)
    }

    /// What the poller would heal on this wake, asked exactly as `ActivityNotifier` asks it.
    private func backgroundHeals(_ ingestor: SessionIngestor, _ activity: IcuActivity) async throws
            -> [String] {
        let library = try await ingestor.allSessions().map(NewActivityWatch.KnownSession.init)
        let checked = try await ingestor.icuPositionsOnlyAtSource()
        return NewActivityWatch.heals(activities: [activity], library: library,
                                      checked: checked).map(\.id)
    }

    /// **The background poll heals the stamped Strava row** (Jan, 1 Oct 2026: "yes"). The
    /// poller does not announce the afternoon — the library has it — but it fetches the FIT
    /// and the FIT replaces the row in place, the rider's name kept. The next wake fetches
    /// nothing.
    @Test func theBackgroundPollHealsTheStampedStravaRow() async throws {
        let (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let (_, fit, copy) = try StravaImportTests.thirteenJune()
        let strava = try await importStrava(ingestor, copy)
        _ = try await ingestor.note(strava, source: .icu, icuActivityId: Self.icuID)
        try await ingestor.library.renameSession(id: strava.id, to: "Van day")
        let activity = try Self.activity(for: fit)

        let library = try await ingestor.allSessions().map(NewActivityWatch.KnownSession.init)
        let decision = NewActivityWatch.evaluate(
            activities: [activity], library: library,
            mark: NewActivityMark(lastStartDate: Date(), announcedIds: []))
        #expect(decision.notices.isEmpty, "not new: the library holds the afternoon")
        #expect(try await backgroundHeals(ingestor, activity) == [Self.icuID])

        let transport = try OneAfternoon(activity: activity, fit: fit)
        guard case .replaced(let row, _) = try await service(ingestor, transport)
            .fetchOne(activity) else {
            Issue.record("expected the FIT to replace the Strava copy")
            return
        }
        #expect(row.id == strava.id)
        try await expectTheFit(ingestor, id: strava.id)
        #expect(try await ingestor.session(id: strava.id)?.customTitle == "Van day")
        #expect(try await backgroundHeals(ingestor, activity).isEmpty)
    }

    /// A Strava copy that never met the FIT carries no id; the poller matches it by its
    /// start, as `isInLibrary` does, and heals it the same way.
    @Test func theBackgroundPollHealsAnUnstampedStravaCopy() async throws {
        let (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let (_, fit, copy) = try StravaImportTests.thirteenJune()
        let strava = try await importStrava(ingestor, copy)
        #expect(strava.icuActivityId == nil)
        let activity = try Self.activity(for: fit)
        #expect(try await backgroundHeals(ingestor, activity) == [Self.icuID])

        let transport = try OneAfternoon(activity: activity, fit: fit)
        guard case .replaced = try await service(ingestor, transport).fetchOne(activity) else {
            Issue.record("expected the FIT to replace the Strava copy")
            return
        }
        try await expectTheFit(ingestor, id: strava.id)
        #expect(try await backgroundHeals(ingestor, activity).isEmpty)
    }

    /// **A positions-only file at intervals.icu is fetched once** (Jan, 1 Oct 2026: "no, we
    /// should avoid that"). The upload behind the activity is itself a GPX: it cannot replace
    /// the Strava copy, so the first pull remembers the outcome and no pull after it, manual
    /// or background, downloads it again.
    @Test func aPositionsOnlyIcuFileIsFetchedOnceAcrossPulls() async throws {
        let (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let (_, fit, copy) = try StravaImportTests.thirteenJune()
        let strava = try await importStrava(ingestor, copy)
        _ = try await ingestor.note(strava, source: .icu, icuActivityId: Self.icuID)
        var activity = try Self.activity(for: fit)
        activity.fileType = "gpx"
        activity.icuSyncDate = "2026-06-13T18:40:00Z"
        let transport = try OneAfternoon(activity: activity, fit: copy.gpx)

        let first = try await sync(ingestor, transport)
        #expect(first.duplicates == 1 && first.replaced.isEmpty)
        #expect(transport.downloads == 1)
        for _ in 0..<3 {
            let again = try await sync(ingestor, transport)
            #expect(again.alreadyKnown == 1)
        }
        #expect(try await backgroundHeals(ingestor, activity).isEmpty)
        #expect(transport.downloads == 1)
        let row = try #require(try await ingestor.allSessions().first)
        #expect(row.id == strava.id && row.sourceClass == "c")
    }

    /// …and checked again once intervals.icu says the activity changed: the rider replaced
    /// the GPX with the watch's FIT, the activity's file type and sync date move, and the
    /// next pull fetches it and heals the row.
    @Test func anIcuActivityUpdatedLaterIsCheckedAgain() async throws {
        let (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let (_, fit, copy) = try StravaImportTests.thirteenJune()
        let strava = try await importStrava(ingestor, copy)
        _ = try await ingestor.note(strava, source: .icu, icuActivityId: Self.icuID)
        var activity = try Self.activity(for: fit)
        activity.fileType = "gpx"
        activity.icuSyncDate = "2026-06-13T18:40:00Z"
        let transport = try OneAfternoon(activity: activity, fit: copy.gpx)
        _ = try await sync(ingestor, transport)
        #expect(transport.downloads == 1)

        activity.fileType = "fit"
        activity.icuSyncDate = "2026-06-14T09:12:00Z"
        try transport.replace(activity: activity, fit: fit)
        #expect(try await backgroundHeals(ingestor, activity) == [Self.icuID])
        let healed = try await sync(ingestor, transport)
        #expect(healed.replaced.map(\.id) == [strava.id])
        #expect(transport.downloads == 2)
        try await expectTheFit(ingestor, id: strava.id)

        _ = try await sync(ingestor, transport)
        #expect(transport.downloads == 2)
    }
}
