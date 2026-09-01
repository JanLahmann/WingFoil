import Foundation
import GRDB
import ZIPFoundation

/// One file that holds the whole library: the database, every archived recording, and a
/// note saying what version wrote it.
///
/// **Why this exists at all.** The library lives in Application Support, so an iPhone
/// migration and an iCloud device backup already carry it — that is the ordinary path and
/// nothing here replaces it. What neither covers is a *fresh* start: a phone set up as new,
/// an app deleted and reinstalled, a second device that is not a migration. The FITs could
/// be re-synced from intervals.icu with some pain; the metadata could not. `customTitle`,
/// `shareNote`, who rode it, which wing it was on, and which sessions were deliberately
/// deleted exist nowhere else in the world.
///
/// **Zip layout** (`LibraryBackupLayout`):
/// ```
/// manifest.json                       ← first entry, so a reader can validate cheaply
/// library.sqlite                      ← a VACUUMed snapshot, never the live file
/// Sessions/<uuid>/original.fit|.gpx   ← the immutable recording
/// Sessions/<uuid>/analysis.json       ← the derived cache, carried for completeness
/// ```
///
/// **The database is snapshotted with `VACUUM INTO`, not copied.** A naive
/// `FileManager.copyItem` of a live SQLite file is the classic way to produce a backup that
/// restores as a corrupt or half-a-transaction-old database: the `-wal` and `-shm`
/// sidecars hold committed pages the main file has not absorbed yet, and copying the three
/// of them is not atomic either. `VACUUM INTO` runs on GRDB's own serialized writer
/// connection (`DatabaseWriter.vacuum(into:)`), inside SQLite's read transaction, so it
/// sees one consistent snapshot with every committed page in it — WAL content included —
/// and writes a single file with no sidecars and no free pages. It is what `DatabasePool
/// .backup(to:)` would give us plus the compaction, and unlike a manual
/// `PRAGMA wal_checkpoint(TRUNCATE)` followed by a copy it cannot race a writer that
/// commits between the checkpoint and the copy.
public enum LibraryBackupLayout {
    public static let manifestPath = "manifest.json"
    public static let databasePath = "library.sqlite"
    public static let sessionsPrefix = "Sessions"

    /// Where one session's file lives inside the zip.
    public static func sessionPath(id: String, file: String) -> String {
        "\(sessionsPrefix)/\(id)/\(file)"
    }

    /// The session id a `Sessions/<id>/<file>` path belongs to, or nil for anything else.
    public static func sessionId(ofPath path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == sessionsPrefix, !parts[1].isEmpty,
              !parts[2].isEmpty else { return nil }
        return String(parts[1])
    }
}

/// What a backup says about itself. Read before a single byte of it is trusted.
///
/// `schemaVersion` is the gate that matters: a zip written by a *newer* build can hold
/// columns and tables this one has never heard of, and there is no honest way to merge
/// those — so a future schema is refused by name rather than silently half-imported.
/// The other direction is fine and is the whole point: an older backup is migrated
/// forward by the ordinary `AppDatabase.migrator` before anything is read out of it.
public struct LibraryBackupManifest: Codable, Sendable, Equatable {

    /// The container format — bumped only when the *layout* changes, which is a different
    /// question from whether the database schema did.
    public static let currentFormat = 1

    public var format: Int
    /// `AppDatabase.schemaVersion` at the time of writing.
    public var schemaVersion: Int
    public var engineVersion: String
    /// `CFBundleShortVersionString (CFBundleVersion)`, or nil outside an app bundle.
    public var appVersion: String?
    public var createdAt: Date
    public var sessionCount: Int
    /// Sessions whose recording actually made it into the zip. Lower than `sessionCount`
    /// when a provisional row (the watch's BLE card) has no recording yet.
    public var recordingCount: Int
    public var gearCount: Int
    public var spotCount: Int
    public var tombstoneCount: Int
    /// Uncompressed bytes of the `Sessions/` tree, for the "how big is this" line.
    public var archiveBytes: Int64

    public init(format: Int = LibraryBackupManifest.currentFormat,
                schemaVersion: Int, engineVersion: String, appVersion: String?,
                createdAt: Date, sessionCount: Int, recordingCount: Int, gearCount: Int,
                spotCount: Int, tombstoneCount: Int, archiveBytes: Int64) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.engineVersion = engineVersion
        self.appVersion = appVersion
        self.createdAt = createdAt
        self.sessionCount = sessionCount
        self.recordingCount = recordingCount
        self.gearCount = gearCount
        self.spotCount = spotCount
        self.tombstoneCount = tombstoneCount
        self.archiveBytes = archiveBytes
    }

    /// Whether this build can read the backup at all — and, when it cannot, why.
    ///
    /// Pure so the refusal wording is asserted by the tests rather than discovered by the
    /// one rider who ever hits it.
    public func compatibility(
        format supportedFormat: Int = LibraryBackupManifest.currentFormat,
        schema supportedSchema: Int = AppDatabase.schemaVersion) -> LibraryBackupCompatibility {
        if format > supportedFormat {
            return .tooNew(reason: "This backup was written in a newer format (\(format)) "
                           + "than this version of CleanJibe can read (\(supportedFormat)). "
                           + "Update the app and try again.")
        }
        if schemaVersion > supportedSchema {
            return .tooNew(reason: "This backup comes from a newer version of CleanJibe — "
                           + "its library is at version \(schemaVersion) and this app "
                           + "understands up to \(supportedSchema). Update the app and try "
                           + "again. Nothing has been changed.")
        }
        return .readable
    }

    /// A JSON encoder/decoder pair with one date strategy, spelled once. ISO-8601 rather
    /// than a floating-point interval, because a manifest is the one file in the zip a
    /// human might open.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum LibraryBackupCompatibility: Sendable, Equatable {
    case readable
    case tooNew(reason: String)

    public var isReadable: Bool { self == .readable }

    public var refusal: String? {
        if case .tooNew(let reason) = self { return reason }
        return nil
    }
}

/// How big the backup is going to be, and whether that is worth saying out loud first.
public struct LibraryBackupSize: Sendable, Equatable {

    /// Above this the app says the number before it starts, rather than after. 200 MB is
    /// roughly where a file stops being something a rider drops into iCloud Drive without
    /// thinking about it — and it is a threshold only accelerometer sessions reach.
    public static let largeBytes: Int64 = 200 * 1024 * 1024

    public var sessionCount: Int
    /// How many of those carry the 100 Hz wrist accelerometer stream. It is ~95 % of a FIT
    /// that has one (`FitShareFilter`'s own measurement), so this is the number that
    /// explains the size.
    public var accelSessionCount: Int
    public var archiveBytes: Int64
    public var databaseBytes: Int64

    public init(sessionCount: Int = 0, accelSessionCount: Int = 0,
                archiveBytes: Int64 = 0, databaseBytes: Int64 = 0) {
        self.sessionCount = sessionCount
        self.accelSessionCount = accelSessionCount
        self.archiveBytes = archiveBytes
        self.databaseBytes = databaseBytes
    }

    /// An **upper bound**: the zip deflates, so the file on disk is normally smaller.
    public var totalBytes: Int64 { archiveBytes + databaseBytes }

    public var isLarge: Bool { totalBytes >= Self.largeBytes }

    /// The sentence shown before the backup starts, or nil when there is nothing to warn
    /// about. Named after what dominates the size rather than after the size itself:
    /// "this is big" is not actionable, "the accelerometer is 95 % of it" is.
    public var warning: String? {
        guard isLarge else { return nil }
        guard accelSessionCount > 0 else {
            return "This backup will be around \(Self.approximate(totalBytes)). Pick a "
                + "destination with room for it — iCloud Drive counts against your storage."
        }
        return "This backup will be around \(Self.approximate(totalBytes)). "
            + "\(accelSessionCount) of your \(sessionCount) sessions carry the 100 Hz "
            + "accelerometer stream, which is about 95 % of each of those recordings — "
            + "that is nearly all of the size. Pick a destination with room for it; "
            + "iCloud Drive counts against your storage."
    }

    /// "1.4 GB" / "230 MB" — deliberately coarse, because the number is an estimate.
    static func approximate(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = bytes >= 1_000_000_000 ? [.useGB] : [.useMB]
        return formatter.string(fromByteCount: bytes)
    }
}

/// Writes the library out as one zip. Read-only against the library: nothing here mutates
/// a row, drops a cache or touches an archived recording.
public struct LibraryBackupWriter: Sendable {

    public var database: AppDatabase
    public var archive: SessionArchive
    /// The live database file, for the size estimate only. nil for an in-memory library.
    public var databaseURL: URL?
    /// `CFBundleShortVersionString (CFBundleVersion)`, supplied by the app — the kit has
    /// no business reading `Bundle.main`, which in a test is the test runner.
    public var appVersion: String?

    public init(database: AppDatabase, archive: SessionArchive,
                databaseURL: URL? = nil, appVersion: String? = nil) {
        self.database = database
        self.archive = archive
        self.databaseURL = databaseURL
        self.appVersion = appVersion
    }

    /// The filename offered to the share sheet: `cleanjibe-library-2026-09-01.zip`.
    ///
    /// Dated, not numbered, because a rider ends up with several of these in a folder and
    /// the only question he will ever ask of them is which one is the newest.
    public static func suggestedFilename(date: Date = Date(),
                                         timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle.dateTime.year().month(.twoDigits).day(.twoDigits)
        style.timeZone = timeZone
        let stamp = date.formatted(style.locale(Locale(identifier: "en_US_POSIX")))
            .replacingOccurrences(of: "/", with: "-")
        return "cleanjibe-library-\(stamp).zip"
    }

    /// What the backup is going to cost, before it is made. Cheap: one directory walk and
    /// two counts, no compression and no database copy.
    public func estimate() async throws -> LibraryBackupSize {
        let counts = try await database.writer.read { db -> (Int, Int) in
            let sessions = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM session") ?? 0
            let accel = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM session WHERE hasAccel = 1") ?? 0
            return (sessions, accel)
        }
        var databaseBytes: Int64 = 0
        if let databaseURL,
           let size = try? databaseURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            databaseBytes = Int64(size)
        }
        return LibraryBackupSize(sessionCount: counts.0, accelSessionCount: counts.1,
                                 archiveBytes: archive.diskUsageBytes(),
                                 databaseBytes: databaseBytes)
    }

    /// Streams the whole library into a zip at `url`, which must not exist yet.
    ///
    /// `progress` is called with (sessions packed, sessions to pack) before each session,
    /// so the UI counts rather than guesses. Cancellation is honoured between sessions:
    /// a cancelled write removes the half-finished file rather than leaving a zip that
    /// looks complete and is not.
    @discardableResult
    public func write(to url: URL,
                      progress: (@Sendable (Int, Int) -> Void)? = nil) async throws
    -> LibraryBackupManifest {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        try? fileManager.removeItem(at: url)

        // The snapshot, taken first: it is the one part that has to be consistent with
        // itself, and taking it before the (much slower) file walk keeps the window in
        // which a concurrent import could land between the two as small as it can be.
        // A session imported during the walk is simply not in this backup — which is the
        // honest outcome, and the restore path deduplicates it anyway.
        let staging = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-backup-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        let snapshot = staging.appendingPathComponent(LibraryBackupLayout.databasePath)
        try await database.writer.vacuum(into: snapshot.path)

        let inventory = try await self.inventory()
        // The whole file list, and its size, **before** the first byte is written. That
        // ordering is not tidiness: the manifest has to be complete when it goes in, and
        // ZIPFoundation's `remove` — the only way to replace an entry — rewrites the entire
        // archive into a temporary file. On a season of accelerometer recordings that is a
        // second pass over several gigabytes to correct two integers. A directory walk is
        // milliseconds; the rewrite is minutes and twice the free disk.
        let plan = Self.plan(for: inventory.sessionIds, in: archive)
        let manifest = LibraryBackupManifest(
            schemaVersion: AppDatabase.schemaVersion,
            engineVersion: AnalysisEngine.version,
            appVersion: appVersion,
            // Truncated to the second, because that is all ISO-8601 carries: a manifest
            // that did not equal itself after a round trip would be a trap for every
            // caller that compares one.
            createdAt: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)),
            sessionCount: inventory.sessionIds.count,
            recordingCount: plan.filter(\.hasRecording).count,
            gearCount: inventory.gearCount,
            spotCount: inventory.spotCount,
            tombstoneCount: inventory.tombstoneCount,
            archiveBytes: plan.reduce(0) { $0 + $1.bytes })

        do {
            let zip = try Archive(url: url, accessMode: .create, pathEncoding: nil)
            // The manifest goes in first so a reader can validate a 2 GB file by touching
            // its front. (ZIP's directory is at the back, so this is a courtesy rather
            // than a guarantee — but it costs nothing.)
            try Self.add(data: try LibraryBackupManifest.encoder().encode(manifest),
                         path: LibraryBackupLayout.manifestPath, to: zip)
            try zip.addEntry(with: LibraryBackupLayout.databasePath, fileURL: snapshot,
                             compressionMethod: .deflate)

            for (index, session) in plan.enumerated() {
                try Task.checkCancellation()
                progress?(index, plan.count)
                for file in session.files {
                    try zip.addEntry(
                        with: LibraryBackupLayout.sessionPath(id: session.id,
                                                              file: file.lastPathComponent),
                        fileURL: file, compressionMethod: .deflate)
                }
            }
            progress?(plan.count, plan.count)
        } catch {
            try? fileManager.removeItem(at: url)
            throw error
        }
        return manifest
    }

    /// One session's files, in the order they go into the zip.
    private struct PackedSession: Sendable {
        var id: String
        var files: [URL]
        var bytes: Int64
        /// False for a provisional row (the watch's card): a directory with an
        /// `analysis.json` and no recording, or no directory at all.
        var hasRecording: Bool
    }

    private static func plan(for ids: [String], in archive: SessionArchive) -> [PackedSession] {
        let fileManager = FileManager.default
        return ids.compactMap { id -> PackedSession? in
            let contents = (try? fileManager.contentsOfDirectory(
                at: archive.directory(for: id),
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])) ?? []
            var files: [URL] = []
            var bytes: Int64 = 0
            for file in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values?.isRegularFile == true else { continue }
                files.append(file)
                bytes += Int64(values?.fileSize ?? 0)
            }
            guard !files.isEmpty else { return nil }
            return PackedSession(
                id: id, files: files, bytes: bytes,
                hasRecording: files.contains { $0.lastPathComponent.hasPrefix("original.") })
        }
    }

    private struct Inventory: Sendable {
        var sessionIds: [String]
        var gearCount: Int
        var spotCount: Int
        var tombstoneCount: Int
    }

    /// Session ids come from the **database**, not from the archive directory listing: a
    /// directory with no row is debris (an interrupted delete), and a backup that carried
    /// it would restore a session the rider cannot see.
    private func inventory() async throws -> Inventory {
        try await database.writer.read { db in
            Inventory(
                sessionIds: try String.fetchAll(
                    db, sql: "SELECT id FROM session ORDER BY startDate"),
                gearCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM gear") ?? 0,
                spotCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM spot") ?? 0,
                tombstoneCount: try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM deleted_session") ?? 0)
        }
    }

    private static func add(data: Data, path: String, to zip: Archive) throws {
        try zip.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                         compressionMethod: .deflate) { position, size in
            let start = Int(position)
            return data.subdata(in: start ..< min(start + size, data.count))
        }
    }
}
