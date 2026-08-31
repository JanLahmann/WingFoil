import Foundation
import GRDB
import Testing
@testable import WingFoilKit

/// **The test that would have caught it.**
///
/// Until engine 0.8.2 no session carried a timezone. Every clock either app printed was the
/// recording's UTC instant formatted in the *reader's* current zone, and the whole suite
/// agreed with it — because the suite ran on a machine set to CEST, which is what the
/// fixtures were recorded in. The bug was invisible for exactly one reason: the test
/// environment shared the sessions' clock.
///
/// So this suite takes that away. It forces the process into **UTC**, ingests the bundled
/// example through the real ingest path, and asserts the session still reads `14:07` — the
/// time on the watch at Torbole, and the time in the filename. On the old code every
/// assertion here says `12:07`.
///
/// It also pins the resolution ladder itself (`SessionIngestor.resolveUtcOffsetS`) and the
/// v7 backfill, because those are the two places a session can quietly lose its zone.
@Suite(.serialized) struct SessionTimeZoneTests {

    /// Runs `body` with the process's **default** zone set to `identifier`, then puts it
    /// back.
    ///
    /// `NSTimeZone.default` and not `setenv("TZ", …)`: `TZ` is read once, at process start,
    /// so a test binary that has already formatted a date cannot use it. What
    /// `NSTimeZone.default` does move is every `DateFormatter` and `Date.FormatStyle` that
    /// was not given a zone of its own — which is *exactly* the mechanism this bug rode in
    /// on. Each of the formatters below was such a formatter until 0.8.2, and each one is
    /// now given `row.displayZone` explicitly; this puts the old implicit answer nine hours
    /// away from the right one, so any formatter that has been missed says so out loud.
    ///
    /// (`TimeZone.current` is read from the system on this platform and does not follow the
    /// default, so `TZ=UTC swift test` is the stronger form of this test and is what CI
    /// runs — docs/testing.md. These assertions hold either way, which is the point.)
    ///
    /// `.serialized` on the suite, because this mutates process-wide state and a parallel
    /// test formatting a date at the wrong moment would fail for a reason that has nothing
    /// to do with it.
    private func inZone<T>(_ identifier: String, _ body: () throws -> T) rethrows -> T {
        let saved = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: identifier)!
        defer { NSTimeZone.default = saved }
        return try body()
    }

    private struct Harness {
        var ingestor: SessionIngestor
        var database: AppDatabase
        var archive: SessionArchive
        var root: URL
    }

    private func makeHarness() throws -> Harness {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-tz-\(UUID().uuidString)/Sessions",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let database = try AppDatabase.inMemory()
        let archive = SessionArchive(root: root)
        return Harness(ingestor: SessionIngestor(database: database, archive: archive),
                       database: database, archive: archive, root: root)
    }

    private func cleanup(_ harness: Harness) {
        try? FileManager.default.removeItem(at: harness.root.deletingLastPathComponent())
    }

    // MARK: - The whole path, on a UTC machine

    /// Ingest the shipped example on a UTC machine; every surface still says 14:07.
    ///
    /// The example is the 30 Aug 2026 Torbole session — `activity.local_timestamp` two
    /// hours ahead of `activity.timestamp`, so 12:07:30 UTC is 14:07:30 on the water. The
    /// filename says `1407`, the help text says an early-afternoon Ora, and a reader in
    /// London opening the app must be told the same thing.
    @Test func aSessionReadsOnItsOwnClockFromAnywhere() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }

        let row = try await Self.ingestExample(harness.ingestor)

        try inZone("UTC") {
            // The premise: a reader whose own clock is NOT the session's. Every formatter
            // below that forgot to ask for a zone gets this one.
            let implicit = DateFormatter()
            implicit.locale = Locale(identifier: "en_US_POSIX")
            implicit.dateFormat = "HH:mm"
            #expect(implicit.timeZone.secondsFromGMT() == 0,
                    "the point of this test is a reader who does NOT share the session's zone")
            // …and that reader would have been shown 12:07 by the code this replaces.
            #expect(implicit.string(from: row.startDate) == "12:07")

            // 1. The stored fact: the watch's own offset, in seconds.
            #expect(row.startUtcOffsetS == 7200)
            #expect(row.hasKnownZone)
            #expect(row.displayZone.secondsFromGMT() == 7200)
            // …and the instant underneath it is untouched — 12:07:30 UTC.
            let utc = DateFormatter()
            utc.locale = Locale(identifier: "en_US_POSIX")
            utc.timeZone = TimeZone(secondsFromGMT: 0)
            utc.dateFormat = "yyyy-MM-dd HH:mm:ss"
            #expect(utc.string(from: row.startDate) == "2026-08-30 12:07:30")

            // 2. The replay's opening bookend — the line the clip speaks on its first frame.
            #expect(ReplayCommentary.hourMinute(row.startDate, timeZone: row.displayZone)
                    == "14:07")
            #expect(ReplayCommentary.startLine(place: "Torbole", startedAt: row.startDate,
                                               timeZone: row.displayZone)
                    == "Torbole, 14:07 — session start")

            // 3. The clip's title card, which is that line laid out rather than spoken.
            let card = ReplayTitleCard.make(place: "Torbole", startedAt: row.startDate,
                                            timeZone: row.displayZone)
            #expect(card.dateLine == "30 August 2026 · 14:07")

            // 4. The share card's date line, and the message that travels with it.
            #expect(ShareCardStats.dateLine(row.startDate, timeZone: row.displayZone)
                    == "30 August 2026")
            #expect(ShareText.cardMessage(place: "Torbole", startedAt: row.startDate,
                                          timeZone: row.displayZone)
                    .hasPrefix("Torbole, 30 August 2026 — "))

            // 5. The filename a shared FIT arrives under.
            #expect(FitShareFilter.filename(date: row.startDate, title: "Torbole",
                                            timeZone: row.displayZone)
                    == "2026-08-30-torbole.fit")
        }
    }

    /// The same session, read from Los Angeles. Nothing moves.
    ///
    /// The date is the half that matters here: 12:07 UTC is 05:07 on 30 August in
    /// California, so a naive render is merely early — but a session ridden at 01:00 CEST
    /// would be published under the *previous day*. Pinning both zones proves the string
    /// depends on the session and not on the reader at all.
    @Test func theSameSessionReadsIdenticallyFromEveryZone() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }
        let row = try await Self.ingestExample(harness.ingestor)

        for zone in ["UTC", "America/Los_Angeles", "Pacific/Auckland", "Europe/Berlin"] {
            try inZone(zone) {
                #expect(ReplayTitleCard.make(place: "Torbole", startedAt: row.startDate,
                                             timeZone: row.displayZone).dateLine
                        == "30 August 2026 · 14:07",
                        "the session's clock moved when the reader's did (\(zone))")
            }
        }
    }

    // MARK: - The ladder

    /// Source 1 wins: the FIT's `activity` message, on every fixture in the corpus.
    @Test func everyFixtureCarriesItsOwnOffset() throws {
        var seen = 0
        for url in allFixtureFITs() where url.path.contains("/sessions/") {
            let track = try FitSessionParser.parse(url: url)
            #expect(track.startUtcOffsetS == 7200,
                    "\(url.lastPathComponent) lost its recorded offset")
            seen += 1
        }
        #expect(seen >= 10, "the corpus shrank; this assertion is no longer worth much")
    }

    /// Sources 2, 3 and 4, in order — what happens when the file cannot say.
    @Test func theLadderFallsThroughInOrder() throws {
        var bare = RawTrack()
        bare.samples = [RecordSample(t: 0, timestamp: Date())]

        // 4: nothing at all. nil, not 0 — "we do not know" is not "this was UTC".
        #expect(SessionIngestor.resolveUtcOffsetS(track: bare, fallback: nil) == nil)

        // 2: what the caller was told (intervals.icu's `timezone`) beats no answer.
        #expect(SessionIngestor.resolveUtcOffsetS(track: bare, fallback: 3600) == 3600)

        // 3: a GPS fix alone gives the coarse solar guess — Torbole is 10.87° E.
        var positioned = bare
        positioned.samples[0].lat = 45.87
        positioned.samples[0].lon = 10.87
        #expect(SessionIngestor.resolveUtcOffsetS(track: positioned, fallback: nil) == 3600)
        // …and is still beaten by anything exact.
        #expect(SessionIngestor.resolveUtcOffsetS(track: positioned, fallback: 7200) == 7200)

        // 1: the file's own answer beats both.
        var recorded = positioned
        recorded.startUtcOffsetS = 7200
        #expect(SessionIngestor.resolveUtcOffsetS(track: recorded, fallback: -28800) == 7200)
    }

    // MARK: - The v7 backfill

    /// A row that predates the column is filled from its own archived recording, not from
    /// whatever zone the phone happens to be in when the app is next opened.
    @Test func theBackfillReadsTheArchivedFitRatherThanGuessing() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness) }
        let row = try await Self.ingestExample(harness.ingestor)

        // Put the row back the way a pre-v7 library left it.
        try await harness.database.writer.write { db in
            try db.execute(sql: "UPDATE session SET startUtcOffsetS = NULL")
        }
        let before = try await harness.database.writer.read { db in
            try SessionRow.fetchOne(db, key: row.id)
        }
        #expect(before?.startUtcOffsetS == nil)

        // Backfill on a machine nine hours away from the session — the offset must come
        // from the FIT, so the answer is +7200 and not the phone's.
        let task = inZone("America/Los_Angeles") {
            Task { try await harness.database.backfillStartUtcOffsets(archive: harness.archive) }
        }
        #expect(try await task.value == 1)

        let after = try await harness.database.writer.read { db in
            try SessionRow.fetchOne(db, key: row.id)
        }
        #expect(after?.startUtcOffsetS == 7200)

        // Idempotent: a second pass has nothing left to do.
        let again = try await harness.database.backfillStartUtcOffsets(archive: harness.archive)
        #expect(again == 0)
    }

    // MARK: - intervals.icu

    /// `IcuActivity.startDate` is an instant, and it comes from `start_date`.
    ///
    /// It used to be built from `start_date_local` — a wall clock with no zone — parsed in
    /// the phone's zone, so the same activity produced a *different instant* on a phone in
    /// a different country. That value is the library's ±60 s dedupe key and the new-activity
    /// watch's identity check, so an hour of error there does not look like a slightly wrong
    /// time: it looks like a second session, and the afternoon imports and notifies twice.
    @Test func icuActivityUsesTheRealInstantAndKeepsTheLocalOneForDisplay() throws {
        let activity = IcuActivity(id: "i1", name: "Wingfoil", type: "Windsurf",
                                   startDateLocal: "2026-08-30T14:07:30",
                                   startDateUtc: "2026-08-30T12:07:30",
                                   timezone: "Europe/Rome",
                                   movingTimeS: 645, distanceM: 2600)
        for zone in ["UTC", "America/Los_Angeles", "Europe/Berlin"] {
            try inZone(zone) {
                let utc = DateFormatter()
                utc.locale = Locale(identifier: "en_US_POSIX")
                utc.timeZone = TimeZone(secondsFromGMT: 0)
                utc.dateFormat = "yyyy-MM-dd HH:mm:ss"
                let instant = try #require(activity.startDate)
                #expect(utc.string(from: instant) == "2026-08-30 12:07:30",
                        "the instant moved with the reader's clock (\(zone))")
                #expect(activity.utcOffsetS == 7200)
            }
        }
        // The zoneless local string is kept — it is what the athlete saw — but it is words,
        // never a moment.
        #expect(activity.startDateLocal == "2026-08-30T14:07:30")
    }

    /// No `timezone` field: the offset is still recoverable, as the arithmetic between the
    /// two timestamps intervals.icu did send.
    @Test func icuOffsetFallsBackToTheDifferenceBetweenTheTwoTimestamps() throws {
        let activity = IcuActivity(id: "i2", startDateLocal: "2026-08-30T14:07:30",
                                   startDateUtc: "2026-08-30T12:07:30")
        #expect(activity.utcOffsetS == 7200)
    }

    private static func ingestExample(_ ingestor: SessionIngestor) async throws -> SessionRow {
        let outcome = try await ingestor.ingest(fitData: try ExampleSession.data(),
                                                filename: ExampleSession.filename,
                                                source: .example)
        guard case .imported(let row) = outcome else {
            throw ExampleSession.Failure.missingFromBundle
        }
        return row
    }
}
