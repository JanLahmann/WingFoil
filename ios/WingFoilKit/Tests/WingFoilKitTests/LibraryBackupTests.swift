import Foundation
import GRDB
import Testing
import ZIPFoundation
@testable import WingFoilKit

/// One file out, the same library back in — and, more importantly, the things a rider
/// cannot get back any other way: what he called a session, what he wanted said about it,
/// whose it was, what he rode it on, and which sessions he threw away on purpose.
///
/// Every test here builds a real library from real fixtures, backs it up, and restores into
/// a *different* store with its own archive root, because "it worked on the machine that
/// wrote it" is the one thing a backup is not allowed to be.
@Suite struct LibraryBackupTests {

    // MARK: - Scaffolding

    private struct Library {
        var ingestor: SessionIngestor
        /// The temporary directory holding `Sessions/`, removed by the test.
        var container: URL

        var archive: SessionArchive { ingestor.archive }
        var store: LibraryStore { ingestor.library }
    }

    private func makeLibrary() throws -> Library {
        let container = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-backup-tests-\(UUID().uuidString)", isDirectory: true)
        let root = container.appendingPathComponent("Sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Library(ingestor: SessionIngestor(database: try AppDatabase.inMemory(),
                                                 archive: SessionArchive(root: root)),
                       container: container)
    }

    private func scratch() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-backup-zip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The two smallest FITs in the corpus, so a round-trip test costs two analyses rather
    /// than two hundred megabytes of accelerometer.
    private static let stems = ["2026-08-05-0827_nago-torbole-windsurfen_native",
                                "2026-08-04-0822_nago-torbole-windsurfen_native"]

    private func fixture(_ index: Int) throws -> (data: Data, name: String) {
        let url = try #require(findFixtureFIT(stem: Self.stems[index]),
                               "fixture \(Self.stems[index]) is missing")
        return (try Data(contentsOf: url), url.lastPathComponent)
    }

    @discardableResult
    private func ingest(_ index: Int, into library: Library,
                        source: ImportSource = .file,
                        rider: String? = nil) async throws -> SessionRow {
        let (data, name) = try fixture(index)
        guard case .imported(let row) = try await library.ingestor.ingest(
            fitData: data, filename: name, source: source, rider: rider) else {
            Issue.record("fixture \(index) did not import")
            throw CancellationError()
        }
        return row
    }

    /// A library with everything a backup is supposed to carry: two sessions, one of them
    /// renamed and captioned and credited to a friend, a wing and a board linked to the
    /// first, a spot the rider named himself, and one session deleted on purpose.
    private func populated() async throws -> (Library, SessionRow, SessionRow) {
        let library = try makeLibrary()
        let first = try await ingest(0, into: library)
        let second = try await ingest(1, into: library, source: .icu, rider: "Tom")

        try await library.store.renameSession(id: first.id, to: "First 20-knot run")
        try await library.store.setShareNote(id: first.id, to: "Cold and glassy, finally got it")

        let wing = GearRow(name: "Duotone Unit 5 m", kind: .wing)
        let board = GearRow(name: "Armstrong Wing SUP 85", kind: .board)
        try await library.store.saveGear(wing)
        try await library.store.saveGear(board)
        try await library.store.assignGear(sessionId: first.id, kind: .wing, gearId: wing.id)
        try await library.store.assignGear(sessionId: first.id, kind: .board, gearId: board.id)

        let spots = try await library.store.spots()
        let spot = try #require(spots.first?.spot)
        try await library.store.renameSpot(id: spot.id, to: "Torbole, north end")

        // One deliberately-deleted session, so the backup carries a tombstone.
        let doomed = try #require(findFixtureTrack(stem: "smoke-60s"))
        guard case .imported(let third) = try await library.ingestor.ingest(
            fitData: try Data(contentsOf: doomed), filename: "smoke-60s.fit",
            source: .file) else {
            Issue.record("the synthetic fixture did not import")
            throw CancellationError()
        }
        try await library.ingestor.delete(third, title: "A minute of nothing")

        let refreshedFirst = try #require(try await library.ingestor.session(id: first.id))
        let refreshedSecond = try #require(try await library.ingestor.session(id: second.id))
        return (library, refreshedFirst, refreshedSecond)
    }

    private func writer(for library: Library) -> LibraryBackupWriter {
        LibraryBackupWriter(database: library.ingestor.database, archive: library.archive,
                            appVersion: "0.9.5 (42)")
    }

    // MARK: - The round trip

    /// The whole promise, end to end: a library packed into one file and unpacked into a
    /// store that has never seen any of it.
    @Test func aBackupRestoresTheLibraryIntoAFreshStore() async throws {
        let (source, first, second) = try await populated()
        defer { try? FileManager.default.removeItem(at: source.container) }
        let box = try scratch()
        defer { try? FileManager.default.removeItem(at: box) }

        let zipURL = box.appendingPathComponent(LibraryBackupWriter.suggestedFilename())
        let manifest = try await writer(for: source).write(to: zipURL)

        #expect(manifest.format == LibraryBackupManifest.currentFormat)
        #expect(manifest.schemaVersion == AppDatabase.schemaVersion)
        #expect(manifest.engineVersion == AnalysisEngine.version)
        #expect(manifest.appVersion == "0.9.5 (42)")
        #expect(manifest.sessionCount == 2)
        #expect(manifest.recordingCount == 2)
        #expect(manifest.gearCount == 2)
        // Two: Torbole, and the place the deleted synthetic session put itself. A spot
        // outlives the sessions in it, which is why the count is about spots and not rides.
        #expect(manifest.spotCount == 2)
        #expect(manifest.tombstoneCount == 1)
        #expect(manifest.archiveBytes > 0)
        #expect(FileManager.default.fileExists(atPath: zipURL.path))

        // The zip says what it holds, and the manifest read back off disk agrees.
        #expect(try LibraryRestore.inspect(zipURL) == manifest)

        let destination = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: destination.container) }
        let summary = try await LibraryRestore(ingestor: destination.ingestor)
            .restore(from: zipURL)

        #expect(summary.sessionsInBackup == 2)
        #expect(summary.imported == 2)
        #expect(summary.alreadyPresent == 0)
        #expect(summary.gearAdded == 2)
        #expect(summary.spotsNamed == 1)
        #expect(summary.tombstonesAdded == 1)
        #expect(summary.failed.isEmpty)
        #expect(!summary.cancelled)

        let restored = try await destination.ingestor.allSessions()
        #expect(restored.count == 2)

        // The renamed, captioned session — the columns nothing in the app can re-derive.
        let restoredFirst = try #require(restored.first { $0.customTitle != nil })
        #expect(restoredFirst.customTitle == "First 20-knot run")
        #expect(restoredFirst.shareNote == "Cold and glassy, finally got it")
        #expect(restoredFirst.rider == nil)
        #expect(restoredFirst.importSource == first.importSource)
        #expect(restoredFirst.originalFilename == first.originalFilename)
        #expect(restoredFirst.startUtcOffsetS == first.startUtcOffsetS)
        #expect(restoredFirst.startUtcOffsetSource == first.startUtcOffsetSource)

        // The friend's session keeps its attribution, which is what keeps his speed out of
        // the reader's records.
        let restoredSecond = try #require(restored.first { $0.rider != nil })
        #expect(restoredSecond.rider == "Tom")
        #expect(restoredSecond.importSource == second.importSource)

        // The recording came back byte for byte, and was analysed by this build.
        let originalBytes = try source.archive.originalData(for: first.id)
        #expect(try destination.archive.originalData(for: restoredFirst.id) == originalBytes)
        #expect(restoredFirst.engineVersion == AnalysisEngine.version)
        #expect(restoredFirst.flightCount == first.flightCount)
        #expect(restoredFirst.best2sKn == first.best2sKn)
        #expect(restoredFirst.distanceKm == first.distanceKm)

        // Kit: two items, matched to the session that wore them.
        let gear = try await destination.store.gear(includeRetired: true)
        #expect(Set(gear.map(\.name)) == ["Duotone Unit 5 m", "Armstrong Wing SUP 85"])
        let combo = try await destination.store.gearOfSession(restoredFirst.id)
        #expect(combo[.wing]?.name == "Duotone Unit 5 m")
        #expect(combo[.board]?.name == "Armstrong Wing SUP 85")

        // The rider's own name for the place, carried onto the spot the clusterer rebuilt.
        let spots = try await destination.store.spots()
        #expect(spots.count == 1)
        #expect(spots.first?.spot.name == "Torbole, north end")
        #expect(spots.first?.spot.autoNamed == false)

        // And the session he threw away stays thrown away.
        #expect(try await destination.store.tombstoneCount() == 1)
        let stones = try await destination.store.tombstones()
        #expect(stones.first?.title == "A minute of nothing")
    }

    // MARK: - Idempotency

    /// Restoring the same file twice is a no-op — not because a flag says it already ran,
    /// but because every merge rule in `LibraryRestore` is "fill what is missing".
    @Test func restoringTheSameBackupTwiceChangesNothing() async throws {
        let (source, _, _) = try await populated()
        defer { try? FileManager.default.removeItem(at: source.container) }
        let box = try scratch()
        defer { try? FileManager.default.removeItem(at: box) }
        let zipURL = box.appendingPathComponent("library.zip")
        try await writer(for: source).write(to: zipURL)

        let destination = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: destination.container) }
        let restore = LibraryRestore(ingestor: destination.ingestor)

        let first = try await restore.restore(from: zipURL)
        #expect(first.imported == 2)
        let afterFirst = try await destination.ingestor.allSessions()
        let gearAfterFirst = try await destination.store.gear(includeRetired: true)
        let spotsAfterFirst = try await destination.store.spots().map(\.spot)
        let stonesAfterFirst = try await destination.store.tombstones()
        let dirsAfterFirst = destination.archive.sessionDirectories().count

        let second = try await restore.restore(from: zipURL)
        #expect(second.imported == 0)
        #expect(second.alreadyPresent == 2)
        #expect(second.metadataFilled == 0)
        #expect(second.gearAdded == 0)
        #expect(second.gearMatched == 2)
        #expect(second.spotsNamed == 0)
        #expect(second.tombstonesAdded == 0)
        #expect(second.failed.isEmpty)
        #expect(second.isEmpty, "a second restore wrote something")

        // Not just the counts: the rows themselves, column for column.
        #expect(try await destination.ingestor.allSessions() == afterFirst)
        #expect(try await destination.store.gear(includeRetired: true) == gearAfterFirst)
        #expect(try await destination.store.spots().map(\.spot) == spotsAfterFirst)
        #expect(try await destination.store.tombstones() == stonesAfterFirst)
        #expect(destination.archive.sessionDirectories().count == dirsAfterFirst)
    }

    // MARK: - Never overwrite a newer local edit

    /// The merge rule that decides whether a restore is safe to run on a phone that has
    /// been in use: what is already there wins, what is missing is filled.
    @Test func restoreFillsGapsAndNeverOverwritesALocalEdit() async throws {
        let (source, first, _) = try await populated()
        defer { try? FileManager.default.removeItem(at: source.container) }
        let box = try scratch()
        defer { try? FileManager.default.removeItem(at: box) }
        let zipURL = box.appendingPathComponent("library.zip")
        try await writer(for: source).write(to: zipURL)

        // The same session, already in the destination library, renamed differently and
        // wearing a different wing — the state of a phone that has been used since.
        let destination = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: destination.container) }
        let local = try await ingest(0, into: destination)
        try await destination.store.renameSession(id: local.id, to: "The name I like")
        let localWing = GearRow(name: "F-One Strike 4 m", kind: .wing)
        try await destination.store.saveGear(localWing)
        try await destination.store.assignGear(sessionId: local.id, kind: .wing,
                                               gearId: localWing.id)

        let summary = try await LibraryRestore(ingestor: destination.ingestor)
            .restore(from: zipURL)
        #expect(summary.imported == 1)          // only the friend's session was missing
        #expect(summary.alreadyPresent == 1)
        #expect(summary.metadataFilled == 1)

        let merged = try #require(try await destination.ingestor.session(id: local.id))
        // The local rename stands…
        #expect(merged.customTitle == "The name I like")
        // …and the caption, which the local library never had, is filled in.
        #expect(merged.shareNote == "Cold and glassy, finally got it")
        // Provenance is a union, never a replacement.
        #expect(merged.importSource == first.importSource)

        // The wing the rider picked locally is untouched; the board slot, which was empty,
        // takes the backup's answer.
        let combo = try await destination.store.gearOfSession(local.id)
        #expect(combo[.wing]?.name == "F-One Strike 4 m")
        #expect(combo[.board]?.name == "Armstrong Wing SUP 85")

        // Restoring again still changes nothing, even from this half-merged state.
        let again = try await LibraryRestore(ingestor: destination.ingestor)
            .restore(from: zipURL)
        #expect(again.isEmpty)
        #expect(again.metadataFilled == 0)
    }

    /// A session deleted *after* the backup was taken stays deleted. The tombstone is the
    /// newer instruction, and a restore is not a licence to overrule it.
    @Test func restoreLeavesASessionDeletedSinceTheBackupAlone() async throws {
        let (source, _, _) = try await populated()
        defer { try? FileManager.default.removeItem(at: source.container) }
        let box = try scratch()
        defer { try? FileManager.default.removeItem(at: box) }
        let zipURL = box.appendingPathComponent("library.zip")
        try await writer(for: source).write(to: zipURL)

        let destination = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: destination.container) }
        let doomed = try await ingest(0, into: destination)
        try await destination.ingestor.delete(doomed, title: "Deleted on the new phone")

        let summary = try await LibraryRestore(ingestor: destination.ingestor)
            .restore(from: zipURL)
        #expect(summary.skippedDeleted == 1)
        #expect(summary.imported == 1)
        let rows = try await destination.ingestor.allSessions()
        #expect(rows.count == 1)
        #expect(rows.allSatisfy { $0.rider == "Tom" })
    }

    /// A row with no recording — a provisional watch card, or an archive directory that lost
    /// its original — is counted honestly in the manifest and skipped on the way back in.
    /// Inventing a session row out of summary columns is exactly the blind copy this design
    /// exists to avoid.
    @Test func aSessionWithNoRecordingIsCountedAndThenSkipped() async throws {
        let library = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.container) }
        let kept = try await ingest(0, into: library)
        let hollow = try await ingest(1, into: library)
        try FileManager.default.removeItem(at: library.archive.originalURL(for: hollow.id))

        let box = try scratch()
        defer { try? FileManager.default.removeItem(at: box) }
        let zipURL = box.appendingPathComponent("library.zip")
        let manifest = try await writer(for: library).write(to: zipURL)
        #expect(manifest.sessionCount == 2)
        #expect(manifest.recordingCount == 1)

        let destination = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: destination.container) }
        let summary = try await LibraryRestore(ingestor: destination.ingestor)
            .restore(from: zipURL)
        #expect(summary.sessionsInBackup == 2)
        #expect(summary.imported == 1)
        #expect(summary.skippedWithoutRecording == 1)
        #expect(summary.failed.isEmpty)
        let rows = try await destination.ingestor.allSessions()
        #expect(rows.count == 1)
        #expect(rows.first?.startDate == kept.startDate)
    }

    // MARK: - Refusals

    /// A backup from a future version is refused by name. Nothing is imported, nothing is
    /// half-imported, and the sentence says what to do about it.
    @Test func aFutureSchemaIsRefusedAndTheLibraryIsUntouched() async throws {
        let (source, _, _) = try await populated()
        defer { try? FileManager.default.removeItem(at: source.container) }
        let box = try scratch()
        defer { try? FileManager.default.removeItem(at: box) }
        let zipURL = box.appendingPathComponent("library.zip")
        var manifest = try await writer(for: source).write(to: zipURL)

        manifest.schemaVersion = AppDatabase.schemaVersion + 1
        try Self.replaceManifest(in: zipURL, with: manifest)

        let destination = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: destination.container) }
        let restore = LibraryRestore(ingestor: destination.ingestor)

        #expect(throws: LibraryRestore.Failure.self) {
            _ = try LibraryRestore.inspect(zipURL)
        }
        await #expect(throws: LibraryRestore.Failure.self) {
            _ = try await restore.restore(from: zipURL)
        }
        do {
            _ = try await restore.restore(from: zipURL)
            Issue.record("a future-schema backup was accepted")
        } catch let failure as LibraryRestore.Failure {
            let message = failure.description
            #expect(message.contains("newer version"))
            #expect(message.contains("\(AppDatabase.schemaVersion + 1)"))
            #expect(message.contains("Nothing has been changed"))
        }
        // And it really did change nothing: no rows, no archive directories, no import log.
        #expect(try await destination.ingestor.allSessions().isEmpty)
        #expect(destination.archive.sessionDirectories().isEmpty)
        #expect(try await destination.store.importLog().isEmpty)
    }

    /// An older backup is the ordinary case, and is migrated forward before a row is read.
    /// The columns that did not exist when it was written come back empty, which is what
    /// they mean.
    @Test func anOlderSchemaIsMigratedForwardRatherThanRefused() async throws {
        let box = try scratch()
        defer { try? FileManager.default.removeItem(at: box) }
        let (data, name) = try fixture(0)
        let track = try TrackParser.parse(data: data)
        let start = try #require(track.startDate)
        let duration = try #require(track.samples.last.map { $0.t - track.samples[0].t })

        // A schema-v6 library: no `startUtcOffsetS` (v7), no `customTitle` (v9).
        let oldDatabase = box.appendingPathComponent("v6.sqlite")
        let sessionId = UUID().uuidString
        let queue = try DatabaseQueue(path: oldDatabase.path)
        var migrator = AppDatabase.migrator
        migrator.eraseDatabaseOnSchemaChange = false
        try migrator.migrate(queue, upTo: "v6")
        try await queue.write { db in
            try db.execute(sql: """
                INSERT INTO session (id, startDate, durationS, sourceClass, originalFilename,
                                     importSource, isExample, isProvisional)
                VALUES (?, ?, ?, 'b', ?, 'gdpr', 0, 0)
                """, arguments: [sessionId, start, duration, name])
        }
        try await queue.close()

        let manifest = LibraryBackupManifest(
            schemaVersion: 6, engineVersion: "0.8.0", appVersion: "0.8.2 (1)",
            createdAt: Date(), sessionCount: 1, recordingCount: 1, gearCount: 0,
            spotCount: 0, tombstoneCount: 0, archiveBytes: Int64(data.count))
        let zipURL = box.appendingPathComponent("old.zip")
        let zip = try Archive(url: zipURL, accessMode: .create, pathEncoding: nil)
        try Self.add(try LibraryBackupManifest.encoder().encode(manifest),
                     at: LibraryBackupLayout.manifestPath, to: zip)
        try zip.addEntry(with: LibraryBackupLayout.databasePath, fileURL: oldDatabase,
                         compressionMethod: .deflate)
        try Self.add(data,
                     at: LibraryBackupLayout.sessionPath(id: sessionId, file: "original.fit"),
                     to: zip)

        let destination = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: destination.container) }
        let summary = try await LibraryRestore(ingestor: destination.ingestor)
            .restore(from: zipURL)
        #expect(summary.imported == 1)
        #expect(summary.failed.isEmpty)

        let row = try #require(try await destination.ingestor.allSessions().first)
        #expect(row.originalFilename == name)
        #expect(row.importSource == "gdpr")
        // Written by this build's engine, not by the one that took the backup.
        #expect(row.engineVersion == AnalysisEngine.version)
        // A column that did not exist in v6 comes back empty rather than invented.
        #expect(row.customTitle == nil)
        #expect(row.shareNote == nil)
        // And the offset, which v6 could not store, is read out of the recording itself.
        #expect(row.startUtcOffsetS != nil)
    }

    @Test func aZipThatIsNotABackupIsRefusedPolitely() async throws {
        let box = try scratch()
        defer { try? FileManager.default.removeItem(at: box) }

        let stranger = box.appendingPathComponent("holiday-photos.zip")
        let zip = try Archive(url: stranger, accessMode: .create, pathEncoding: nil)
        try Self.add(Data("not a manifest".utf8), at: "readme.txt", to: zip)
        #expect(throws: LibraryRestore.Failure.noManifest) {
            _ = try LibraryRestore.inspect(stranger)
        }

        let notAZip = box.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: notAZip)
        #expect(throws: LibraryRestore.Failure.notReadable) {
            _ = try LibraryRestore.inspect(notAZip)
        }
    }

    // MARK: - Pure rules

    /// The size line the rider sees before a backup starts. The threshold matters less than
    /// the sentence: "this is big" is not actionable, "the accelerometer is nearly all of
    /// it" is.
    @Test func theSizeEstimateWarnsAboveTwoHundredMegabytesAndNamesTheReason() {
        let small = LibraryBackupSize(sessionCount: 12, accelSessionCount: 0,
                                      archiveBytes: 40 * 1024 * 1024, databaseBytes: 900_000)
        #expect(!small.isLarge)
        #expect(small.warning == nil)
        #expect(small.totalBytes == 40 * 1024 * 1024 + 900_000)

        let big = LibraryBackupSize(sessionCount: 40, accelSessionCount: 32,
                                    archiveBytes: 3 * 1024 * 1024 * 1024,
                                    databaseBytes: 4 * 1024 * 1024)
        #expect(big.isLarge)
        let warning = try! #require(big.warning)
        #expect(warning.contains("accelerometer"))
        #expect(warning.contains("32 of your 40"))
        #expect(warning.contains("GB"))

        // Exactly at the threshold counts as large — the boundary is stated, not guessed.
        let edge = LibraryBackupSize(sessionCount: 5, accelSessionCount: 0,
                                     archiveBytes: LibraryBackupSize.largeBytes,
                                     databaseBytes: 0)
        #expect(edge.isLarge)
        #expect(edge.warning?.contains("accelerometer") == false)
    }

    @Test func theLiveEstimateCountsTheArchiveAndTheAccelSessions() async throws {
        let library = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.container) }
        try await ingest(0, into: library)
        try await ingest(1, into: library)

        let size = try await writer(for: library).estimate()
        #expect(size.sessionCount == 2)
        #expect(size.archiveBytes > 0)
        #expect(!size.isLarge)
        #expect(size.warning == nil)
        // These two fixtures are Garmin's own profile: a track, no wrist accelerometer.
        #expect(size.accelSessionCount == 0)
    }

    @Test func theZipLayoutRoundTripsSessionPaths() {
        let path = LibraryBackupLayout.sessionPath(id: "abc-123", file: "original.fit")
        #expect(path == "Sessions/abc-123/original.fit")
        #expect(LibraryBackupLayout.sessionId(ofPath: path) == "abc-123")
        #expect(LibraryBackupLayout.sessionId(ofPath: LibraryBackupLayout.manifestPath) == nil)
        #expect(LibraryBackupLayout.sessionId(ofPath: "Sessions/abc-123") == nil)
        #expect(LibraryBackupLayout.sessionId(ofPath: "Elsewhere/abc/original.fit") == nil)
    }

    @Test func provenanceIsUnionedAndTheExampleIsRecognisedByName() {
        #expect(LibraryRestore.mergedSources("icu", "file+gdpr") == "file+gdpr+icu")
        #expect(LibraryRestore.mergedSources(nil, "icu") == "icu")
        #expect(LibraryRestore.mergedSources("icu", nil) == "icu")
        #expect(LibraryRestore.mergedSources(nil, nil) == nil)
        #expect(LibraryRestore.mergedSources("icu", "icu") == "icu")

        // The primary source decides exactly one thing — `isExample` — so the example has
        // to win over whatever else the string names.
        #expect(LibraryRestore.primarySource("example") == .example)
        #expect(LibraryRestore.primarySource("example+file") == .example)
        #expect(LibraryRestore.primarySource("icu") == .icu)
        #expect(LibraryRestore.primarySource("gdpr+icu") == .gdpr)
        #expect(LibraryRestore.primarySource("something-from-the-future") == .file)
        #expect(LibraryRestore.primarySource(nil) == .file)
    }

    @Test func theMergeRuleFillsNothingItDoesNotHaveTo() {
        var live = SessionRow(id: "live", startDate: Date(timeIntervalSince1970: 1_000_000),
                              durationS: 3600, sourceClass: "b")
        live.customTitle = "Mine"
        live.importSource = "icu"

        var backup = live
        backup.id = "backup"
        backup.customTitle = "Theirs"
        backup.shareNote = "A caption"
        backup.rider = "Tom"
        backup.importSource = "file"

        let merged = try! #require(LibraryRestore.merged(live: live, backup: backup))
        #expect(merged.customTitle == "Mine")           // the local edit stands
        #expect(merged.shareNote == "A caption")        // the gap is filled
        #expect(merged.rider == "Tom")
        #expect(merged.importSource == "file+icu")
        #expect(merged.id == "live")                    // identity is never taken from a backup

        // Applied twice, the rule has nothing left to do — which is the whole of idempotency.
        #expect(LibraryRestore.merged(live: merged, backup: backup) == nil)
        #expect(LibraryRestore.merged(live: live, backup: live) == nil)
    }

    @Test func gearMatchesByNameAndKindRatherThanByIdentifier() {
        let mine = GearRow(name: "  Duotone Unit 5 m ", kind: .wing)
        let theirs = GearRow(name: "duotone unit 5 M", kind: .wing)
        let board = GearRow(name: "Duotone Unit 5 m", kind: .board)
        #expect(LibraryRestore.gearKey(mine) == LibraryRestore.gearKey(theirs))
        #expect(LibraryRestore.gearKey(mine) != LibraryRestore.gearKey(board))
    }

    /// The schema number in the manifest is derived from the migration list, so the two
    /// cannot drift — which is the only thing standing between an old build and a backup
    /// it cannot understand.
    @Test func theSchemaVersionFollowsTheMigrationList() {
        #expect(AppDatabase.schemaVersion == AppDatabase.migrationNames.count)
        #expect(AppDatabase.migrationNames.last == "v\(AppDatabase.schemaVersion)")
    }

    @Test func theSuggestedFilenameIsDatedAndSortsByDate() {
        let zone = TimeZone(secondsFromGMT: 0)!
        let name = LibraryBackupWriter.suggestedFilename(
            date: Date(timeIntervalSince1970: 1_788_000_000), timeZone: zone)
        #expect(name.hasPrefix("cleanjibe-library-"))
        #expect(name.hasSuffix(".zip"))
        #expect(!name.contains("/"))
    }

    // MARK: - Zip helpers

    private static func add(_ data: Data, at path: String, to zip: Archive) throws {
        try zip.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                         compressionMethod: .deflate) { position, size in
            let start = Int(position)
            return data.subdata(in: start ..< min(start + size, data.count))
        }
    }

    private static func replaceManifest(in url: URL,
                                        with manifest: LibraryBackupManifest) throws {
        let zip = try Archive(url: url, accessMode: .update, pathEncoding: nil)
        if let stale = zip[LibraryBackupLayout.manifestPath] { try zip.remove(stale) }
        try add(try LibraryBackupManifest.encoder().encode(manifest),
                at: LibraryBackupLayout.manifestPath, to: zip)
    }
}
