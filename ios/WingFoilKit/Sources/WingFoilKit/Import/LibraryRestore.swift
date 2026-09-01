import Foundation
import GRDB
import ZIPFoundation

/// Reads a `LibraryBackupWriter` zip back into a live library — **additively**. Nothing
/// here deletes a session, a spot, a piece of kit or a tombstone; the worst a restore can
/// do is add rows the rider already had, and it does not do that either.
///
/// **The database in the zip is never copied over the live one.** That would be a restore
/// in the sense that a bulldozer is a renovation: the rider's newer sessions, his newer
/// names, and the sessions he deleted *after* the backup was taken would all go. Instead
/// the snapshot is opened *beside* the live library, migrated forward by the ordinary
/// `AppDatabase.migrator` if it is older, and read as a source of facts. Every session in
/// it goes back in through `SessionIngestor.ingest` — the same door an intervals.icu sync,
/// a GDPR ZIP and an AirDropped FIT use, with the same ±60 s dedupe key — so a restored
/// session is analysed by this build's engine and cannot arrive as a duplicate.
///
/// ## The merge rules
///
/// | What | Session already in the library | Session not in the library |
/// | --- | --- | --- |
/// | The recording | untouched — the live archive keeps its own bytes | re-ingested from the zip |
/// | Derived columns (flights, records, wind…) | untouched — this build's analysis wins | computed fresh by the ingest |
/// | `customTitle`, `shareNote` | filled **only if empty** | taken from the backup |
/// | `rider` | filled **only if empty** (nil = "mine", so a name is only ever added) | taken from the backup |
/// | `icuActivityId`, `originalFilename` | filled only if empty | taken from the backup |
/// | `startUtcOffsetS` / source | filled only if empty | taken from the backup, or re-read from the recording |
/// | `importSource` | **union** — "icu" + "gdpr+file" = "file+gdpr+icu" | the backup's, whole |
/// | Gear links | empty slots only — a live wing is never replaced | the backup's combo, replacing the ingest's "same as last time" guess |
/// | `isExample`, `isProvisional` | untouched | as the ingest decides |
///
/// Beside the sessions: **gear** merges by natural key (kind + name, case-insensitive), so
/// two backups of the same library do not produce two "Duotone Unit 5 m"; a name that
/// matches reuses the live row and never overwrites its notes or its retired flag.
/// **Spots** only carry over the one thing the clusterer cannot rebuild — a name the rider
/// typed — and only onto a live spot that is still auto-named and within the backup spot's
/// own radius. **Tombstones** are unioned by id.
///
/// ## What restore deliberately refuses to do
///
/// - **It does not resurrect a session the rider has deleted since.** A live tombstone is a
///   newer, explicit instruction, and "restore my backup" is not a request to overrule it.
///   Those sessions are counted and reported; Settings → Deleted sessions is the way back.
/// - **It does not restore a session with no recording in the zip.** A provisional row (the
///   watch's BLE card, its FIT not synced yet) has nothing to re-ingest, and inventing a
///   row from summary columns would be exactly the blind copy this whole type avoids.
/// - **It does not restore the import log.** That is a diary of what happened on a phone,
///   not a fact about the library; the restore writes its own entry instead.
/// - **It does not reuse the archived `analysis.json`,** even where its `engineVersion`
///   matches the running one and reusing it would genuinely save the analysis. Doing so
///   means a second way into the library beside `SessionIngestor.ingest`, and one door that
///   is always right beats two doors that agree today. The file is still packed: it makes
///   the zip a faithful copy of the archive (a rider can unpack it by hand), and it leaves
///   the shortcut available to a later build that wants to take it. Until then a restore
///   costs one analysis per session, which is the same price the very first import paid.
///
/// ## Idempotency
///
/// Restoring the same zip twice is a no-op by construction, not by a flag: the second pass
/// finds every session through the dedupe key, finds every metadata field already filled,
/// finds every piece of kit by its natural key, and finds every tombstone id present. It
/// is asserted in `LibraryBackupTests.restoringTheSameBackupTwiceChangesNothing`.
public struct LibraryRestore: Sendable {

    public enum Failure: Swift.Error, CustomStringConvertible, Equatable {
        /// Not a zip, or a zip this build cannot open.
        case notReadable
        /// A zip, but not one of ours.
        case noManifest
        case unreadableManifest(String)
        /// The manifest is fine and says this build is too old. Carries the sentence the
        /// rider sees, built by `LibraryBackupManifest.compatibility`.
        case refused(String)
        case noDatabase

        public var description: String {
            switch self {
            case .notReadable:
                "That file could not be opened as a backup — it is not a readable zip."
            case .noManifest:
                "That zip is not a CleanJibe library backup: it carries no manifest.json."
            case .unreadableManifest(let detail):
                "That backup's manifest could not be read (\(detail))."
            case .refused(let reason):
                reason
            case .noDatabase:
                "That backup carries no library database, so there is nothing to restore."
            }
        }
    }

    /// Count-based progress: sessions are the only unit a rider can reason about.
    public struct RestoreProgress: Sendable, Equatable {
        public var done: Int
        public var total: Int
        /// The session being worked on, for a one-line label.
        public var current: String?

        public init(done: Int = 0, total: Int = 0, current: String? = nil) {
            self.done = done
            self.total = total
            self.current = current
        }
    }

    /// What the restore did — every row of it a number the UI is allowed to say out loud.
    public struct Summary: Sendable, Equatable {
        public var sessionsInBackup = 0
        /// Sessions that were not in the library and are now.
        public var imported = 0
        /// Sessions the library already had. Their analysis was left alone.
        public var alreadyPresent = 0
        /// Sessions (present or restored) that gained at least one metadata field.
        public var metadataFilled = 0
        /// Skipped because the rider deleted them after the backup was taken.
        public var skippedDeleted = 0
        /// Skipped because the zip holds no recording for them (a provisional watch card).
        public var skippedWithoutRecording = 0
        public var gearAdded = 0
        public var gearMatched = 0
        public var spotsNamed = 0
        public var tombstonesAdded = 0
        public var failed: [String] = []
        /// True when the rider stopped it. Everything already restored stays restored —
        /// there is no half-session, because the unit of work is one whole session.
        public var cancelled = false

        public init() {}

        public var isEmpty: Bool {
            imported == 0 && metadataFilled == 0 && gearAdded == 0 && spotsNamed == 0
                && tombstonesAdded == 0
        }

        public var shortDescription: String {
            var parts: [String] = ["\(imported) session\(imported == 1 ? "" : "s") restored"]
            if alreadyPresent > 0 { parts.append("\(alreadyPresent) already here") }
            if metadataFilled > 0 { parts.append("\(metadataFilled) with details filled in") }
            if gearAdded > 0 { parts.append("\(gearAdded) gear item\(gearAdded == 1 ? "" : "s")") }
            if spotsNamed > 0 { parts.append("\(spotsNamed) spot name\(spotsNamed == 1 ? "" : "s")") }
            if skippedDeleted > 0 { parts.append("\(skippedDeleted) left deleted") }
            if skippedWithoutRecording > 0 {
                parts.append("\(skippedWithoutRecording) without a recording")
            }
            if !failed.isEmpty { parts.append("\(failed.count) failed") }
            if cancelled { parts.append("stopped") }
            return parts.joined(separator: ", ")
        }
    }

    public var ingestor: SessionIngestor

    public init(ingestor: SessionIngestor) {
        self.ingestor = ingestor
    }

    private var library: LibraryStore { ingestor.library }

    // MARK: - Looking before leaping

    /// Reads and validates the manifest without touching the library. This is what the
    /// confirmation sheet shows, and what turns a future-schema backup into one clear
    /// sentence instead of a half-finished import.
    public static func inspect(_ url: URL) throws -> LibraryBackupManifest {
        guard let zip = try? Archive(url: url, accessMode: .read, pathEncoding: nil) else {
            throw Failure.notReadable
        }
        let manifest = try Self.manifest(in: zip)
        if let refusal = manifest.compatibility().refusal { throw Failure.refused(refusal) }
        return manifest
    }

    static func manifest(in zip: Archive) throws -> LibraryBackupManifest {
        guard let entry = zip[LibraryBackupLayout.manifestPath] else { throw Failure.noManifest }
        var buffer = Data()
        _ = try? zip.extract(entry, skipCRC32: true) { buffer.append($0) }
        guard !buffer.isEmpty else { throw Failure.noManifest }
        do {
            return try LibraryBackupManifest.decoder()
                .decode(LibraryBackupManifest.self, from: buffer)
        } catch {
            throw Failure.unreadableManifest("\(error)")
        }
    }

    // MARK: - The restore

    /// Merges the backup at `url` into the live library and reports what it did.
    ///
    /// Cancellation is checked between sessions, so stopping never leaves a session half
    /// imported: `Task.isCancelled` ends the loop, the tail work (spots, tombstones) is
    /// skipped, and the summary says it was stopped.
    public func restore(from url: URL,
                        progress: (@Sendable (RestoreProgress) -> Void)? = nil) async throws
    -> Summary {
        guard let zip = try? Archive(url: url, accessMode: .read, pathEncoding: nil) else {
            throw Failure.notReadable
        }
        let manifest = try Self.manifest(in: zip)
        if let refusal = manifest.compatibility().refusal { throw Failure.refused(refusal) }
        guard let databaseEntry = zip[LibraryBackupLayout.databasePath] else {
            throw Failure.noDatabase
        }

        let staging = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let snapshot = staging.appendingPathComponent(LibraryBackupLayout.databasePath)
        _ = try zip.extract(databaseEntry, to: snapshot, skipCRC32: true)

        // Opened through the ordinary bootstrap, which migrates an older snapshot forward
        // to this build's schema before a single row is read. That is the whole of the
        // backwards-compatibility story: a v6 backup becomes a v9 database in a temporary
        // file, and everything below is written against today's columns.
        let backup = try AppDatabase(DatabaseQueue(path: snapshot.path))
        let content = try await Self.read(backup)

        var summary = Summary()
        summary.sessionsInBackup = content.sessions.count

        var record = ImportLogRow(source: .file, container: url.lastPathComponent)
        let opened = record
        try? await ingestor.database.writer.write { db in try opened.insert(db) }

        // Kit first: a session's gear link is worthless until the gear it points at exists.
        let gearMap = try await mergeGear(content.gear, into: &summary)

        // The live tombstones as they are *now*, read once. A session the rider deleted
        // since the backup stays deleted, and reading the list once means the tombstones
        // this restore itself adds cannot block the sessions this restore itself brings in.
        let stones = try await library.tombstones()

        for (index, backupRow) in content.sessions.enumerated() {
            if Task.isCancelled {
                summary.cancelled = true
                break
            }
            progress?(RestoreProgress(done: index, total: content.sessions.count,
                                      current: backupRow.customTitle ?? backupRow.originalFilename))
            do {
                try await restoreOne(backupRow, zip: zip, stones: stones, gearMap: gearMap,
                                     links: content.links[backupRow.id] ?? [],
                                     into: &summary)
            } catch {
                summary.failed.append("\(backupRow.originalFilename ?? backupRow.id): \(error)")
            }
        }
        progress?(RestoreProgress(done: content.sessions.count, total: content.sessions.count))

        if !summary.cancelled {
            // Spots after the sessions, because the spots a name can land on are the ones
            // the clusterer just made while ingesting them.
            try await mergeSpots(content.spots, into: &summary)
            try await mergeTombstones(content.tombstones, into: &summary)
        }

        record.finishedAt = Date()
        record.found = summary.sessionsInBackup
        record.imported = summary.imported
        record.duplicates = summary.alreadyPresent
        record.skipped = summary.skippedDeleted + summary.skippedWithoutRecording
        record.failed = summary.failed.count
        record.detail = summary.failed.isEmpty ? nil
            : summary.failed.prefix(20).joined(separator: "\n")
        let finished = record
        try? await ingestor.database.writer.write { db in try finished.update(db) }
        return summary
    }

    // MARK: - One session

    private func restoreOne(_ backupRow: SessionRow, zip: Archive,
                            stones: [SessionTombstoneRow], gearMap: [String: String],
                            links: [SessionGearRow], into summary: inout Summary) async throws {
        let live = try await ingestor.duplicate(startDate: backupRow.startDate,
                                                durationS: backupRow.durationS,
                                                icuActivityId: backupRow.icuActivityId)
        var target: SessionRow
        var isFresh = false

        if let live {
            target = live
            summary.alreadyPresent += 1
        } else {
            if Self.tombstone(blocking: backupRow, in: stones,
                              toleranceS: ingestor.dedupeToleranceS) != nil {
                summary.skippedDeleted += 1
                return
            }
            guard let data = Self.recording(for: backupRow.id, in: zip) else {
                summary.skippedWithoutRecording += 1
                return
            }
            let outcome = try await ingestor.ingest(
                fitData: data, filename: backupRow.originalFilename,
                source: Self.primarySource(backupRow.importSource),
                icuActivityId: backupRow.icuActivityId,
                rider: backupRow.rider,
                utcOffsetS: backupRow.startUtcOffsetS,
                requireWatersport: false)
            switch outcome {
            case .imported(let row):
                target = row
                isFresh = true
                summary.imported += 1
            case .duplicate(let row):
                target = row
                summary.alreadyPresent += 1
            case .skipped(let reason):
                summary.failed.append("\(backupRow.originalFilename ?? backupRow.id): \(reason)")
                return
            }
        }

        if let patched = Self.merged(live: target, backup: backupRow) {
            let stored = patched
            try await ingestor.database.writer.write { db in try stored.update(db) }
            summary.metadataFilled += 1
        }
        try await applyGear(links, to: target.id, gearMap: gearMap, replacing: isFresh)
    }

    /// **The** metadata merge rule, in one function so it can be read and tested as one.
    /// Returns nil when nothing would change — which is what makes a second restore of the
    /// same zip write nothing at all.
    static func merged(live: SessionRow, backup: SessionRow) -> SessionRow? {
        var out = live
        // Two columns nothing in the app derives, and the two the rider would most miss.
        if out.customTitle == nil { out.customTitle = backup.customTitle }
        if out.shareNote == nil { out.shareNote = backup.shareNote }
        // nil means "mine", so filling can only ever *add* an attribution — which is the
        // safe direction: the failure mode this column exists to prevent is somebody
        // else's speed in the reader's personal bests.
        if out.rider == nil { out.rider = backup.rider }
        if out.icuActivityId == nil { out.icuActivityId = backup.icuActivityId }
        if out.originalFilename == nil { out.originalFilename = backup.originalFilename }
        if out.startUtcOffsetS == nil {
            out.startUtcOffsetS = backup.startUtcOffsetS
            out.startUtcOffsetSource = backup.startUtcOffsetSource
        } else if out.startUtcOffsetSource == nil,
                  out.startUtcOffsetS == backup.startUtcOffsetS {
            // Same rule `backfillStartUtcOffsets` uses: a provenance may only be attached
            // to the number it actually describes.
            out.startUtcOffsetSource = backup.startUtcOffsetSource
        }
        out.importSource = mergedSources(live.importSource, backup.importSource)
        return out == live ? nil : out
    }

    /// `"icu"` ∪ `"file+gdpr"` → `"file+gdpr+icu"`. Same shape as
    /// `SessionIngestor.merge(sources:adding:)`, for two strings instead of a string and
    /// a case — a session that arrived four ways still reads as one stable value.
    static func mergedSources(_ live: String?, _ backup: String?) -> String? {
        var set = Set((live ?? "").split(separator: "+").map(String.init))
        set.formUnion((backup ?? "").split(separator: "+").map(String.init))
        set.remove("")
        return set.isEmpty ? nil : set.sorted().joined(separator: "+")
    }

    /// Which `ImportSource` to hand the ingest. It decides exactly one thing —
    /// `SessionRow.isExample` — because the *whole* provenance string is reapplied by
    /// `merged` immediately afterwards. So the example is recognised by name and everything
    /// else falls back to the first source the backup names.
    static func primarySource(_ stored: String?) -> ImportSource {
        let tokens = (stored ?? "").split(separator: "+").map(String.init)
        if tokens.contains(ImportSource.example.rawValue) { return .example }
        for token in tokens {
            if let source = ImportSource(rawValue: token) { return source }
        }
        return .file
    }

    /// The tombstone that says this backed-up session is one the rider threw away *after*
    /// the backup was taken, or nil.
    ///
    /// The library's own dedupe key, symmetric on both sides — unlike
    /// `SessionTombstones.blocks`, which compares against intervals.icu's **moving** time
    /// and is therefore deliberately one-sided. Here both numbers are elapsed time written
    /// by the same code, so a two-sided window is the right one.
    static func tombstone(blocking row: SessionRow, in stones: [SessionTombstoneRow],
                          toleranceS: TimeInterval = 60) -> SessionTombstoneRow? {
        if let id = row.icuActivityId,
           let byId = stones.first(where: { $0.icuActivityId == id }) { return byId }
        return stones.first { stone in
            abs(stone.startDate.timeIntervalSince(row.startDate)) <= toleranceS
                && abs(stone.durationS - row.durationS) <= toleranceS
        }
    }

    /// The archived recording for one backed-up session, FIT or GPX, or nil when the zip
    /// carries none (a provisional row).
    static func recording(for id: String, in zip: Archive) -> Data? {
        for format in TrackFormat.allCases {
            let path = LibraryBackupLayout.sessionPath(
                id: id, file: "original.\(format.fileExtension)")
            guard let entry = zip[path] else { continue }
            var buffer = Data()
            buffer.reserveCapacity(Int(entry.uncompressedSize))
            _ = try? zip.extract(entry, skipCRC32: true) { buffer.append($0) }
            if !buffer.isEmpty { return buffer }
        }
        return nil
    }

    // MARK: - Gear

    /// Merges the backup's kit into the live table and returns backup-id → live-id.
    ///
    /// The natural key is **kind + name, case- and whitespace-insensitive**, not the uuid:
    /// a rider who restores onto a phone where he has already typed "Armstrong HA 925" in
    /// must end up with one foil, not two that look identical in every picker.
    private func mergeGear(_ backupGear: [GearRow],
                           into summary: inout Summary) async throws -> [String: String] {
        guard !backupGear.isEmpty else { return [:] }
        let liveGear = try await library.gear(includeRetired: true)
        var byKey: [String: String] = [:]
        var takenIds = Set(liveGear.map(\.id))
        for gear in liveGear { byKey[Self.gearKey(gear)] = gear.id }

        var map: [String: String] = [:]
        var inserts: [GearRow] = []
        for gear in backupGear {
            let key = Self.gearKey(gear)
            if let existing = byKey[key] {
                map[gear.id] = existing
                summary.gearMatched += 1
                continue
            }
            var row = gear
            // Keeping the backup's own id where it is free makes a second restore land on
            // the same rows; a collision with a *different* piece of kit is a uuid clash,
            // so it is handled rather than assumed away.
            if takenIds.contains(row.id) { row.id = UUID().uuidString }
            takenIds.insert(row.id)
            byKey[key] = row.id
            map[gear.id] = row.id
            inserts.append(row)
            summary.gearAdded += 1
        }
        if !inserts.isEmpty {
            let rows = inserts
            try await ingestor.database.writer.write { db in
                for row in rows { try row.insert(db) }
            }
        }
        return map
    }

    static func gearKey(_ gear: GearRow) -> String {
        "\(gear.kind)|\(gear.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    /// `replacing` is true only for a session this restore just created. Its links at that
    /// moment are not the rider's choice but the ingest's "same combo as last time" guess
    /// (`LibraryStore.applyDefaultGear`), and the backup knows better. On a session that
    /// was already in the library the opposite holds: an empty slot is filled, an occupied
    /// one is left exactly as the rider set it.
    private func applyGear(_ links: [SessionGearRow], to sessionId: String,
                           gearMap: [String: String], replacing: Bool) async throws {
        let mapped = links.compactMap { link -> SessionGearRow? in
            guard let gearId = gearMap[link.gearId],
                  let kind = GearKind(rawValue: link.kind) else { return nil }
            return SessionGearRow(sessionId: sessionId, gearId: gearId, kind: kind)
        }
        guard !mapped.isEmpty else { return }
        try await ingestor.database.writer.write { db in
            if replacing {
                try db.execute(sql: "DELETE FROM session_gear WHERE sessionId = ?",
                               arguments: [sessionId])
            }
            let taken = Set(try String.fetchAll(
                db, sql: "SELECT kind FROM session_gear WHERE sessionId = ?",
                arguments: [sessionId]))
            for link in mapped where !taken.contains(link.kind) { try link.insert(db) }
        }
    }

    // MARK: - Spots

    /// Carries over the one thing about a spot that cannot be recomputed: a name the rider
    /// typed.
    ///
    /// Auto-named spots are ignored entirely — "Spot 3" carries no information and the
    /// local clusterer has already made its own. A rider-named spot with no live spot near
    /// it is ignored too: there would be no sessions at it, and an empty place in the spot
    /// list is a puzzle rather than a memory. A live spot the rider has *already* named
    /// wins, because that is the newer decision.
    private func mergeSpots(_ backupSpots: [SpotRow], into summary: inout Summary) async throws {
        let named = backupSpots.filter { !$0.autoNamed }
        guard !named.isEmpty else { return }
        summary.spotsNamed += try await ingestor.database.writer.write { db -> Int in
            var live = try SpotRow.fetchAll(db)
            var renamed = 0
            for spot in named {
                var best: (index: Int, distance: Double)?
                for (index, candidate) in live.enumerated() where candidate.autoNamed {
                    let d = SpotClusterer.distance(lat1: spot.lat, lon1: spot.lon,
                                                   lat2: candidate.lat, lon2: candidate.lon)
                    if d <= spot.radiusM, d < (best?.distance ?? .infinity) {
                        best = (index, d)
                    }
                }
                guard let best else { continue }
                var target = live[best.index]
                target.name = spot.name
                target.autoNamed = false
                try target.update(db)
                live[best.index] = target
                renamed += 1
            }
            return renamed
        }
    }

    // MARK: - Tombstones

    /// Union by id, minus anything that would bury a session that is standing right there.
    ///
    /// The second condition matters on a merge into a *populated* library: the rider
    /// deleted a session on the old phone, re-imported it on the new one, and the backup
    /// still remembers the deletion. Writing that tombstone would make the next
    /// intervals.icu sync treat a session he can see as one he threw away.
    private func mergeTombstones(_ stones: [SessionTombstoneRow],
                                 into summary: inout Summary) async throws {
        guard !stones.isEmpty else { return }
        let tolerance = ingestor.dedupeToleranceS
        let added = try await ingestor.database.writer.write { db -> Int in
            let known = Set(try String.fetchAll(db, sql: "SELECT id FROM deleted_session"))
            var count = 0
            for stone in stones where !known.contains(stone.id) {
                let lower = stone.startDate.addingTimeInterval(-tolerance)
                let upper = stone.startDate.addingTimeInterval(tolerance)
                let alive = try SessionRow
                    .filter(Column("startDate") >= lower && Column("startDate") <= upper)
                    .fetchAll(db)
                    .contains { abs($0.durationS - stone.durationS) <= tolerance }
                guard !alive else { continue }
                try stone.insert(db)
                count += 1
            }
            return count
        }
        summary.tombstonesAdded += added
    }

    // MARK: - Reading the snapshot

    private struct Content: Sendable {
        var sessions: [SessionRow]
        var links: [String: [SessionGearRow]]
        var gear: [GearRow]
        var spots: [SpotRow]
        var tombstones: [SessionTombstoneRow]
    }

    private static func read(_ backup: AppDatabase) async throws -> Content {
        try await backup.writer.read { db in
            let links = try SessionGearRow.fetchAll(db)
            return Content(
                sessions: try SessionRow.order(Column("startDate")).fetchAll(db),
                links: Dictionary(grouping: links, by: \.sessionId),
                gear: try GearRow.fetchAll(db),
                spots: try SpotRow.fetchAll(db),
                tombstones: try SessionTombstoneRow.fetchAll(db))
        }
    }
}
