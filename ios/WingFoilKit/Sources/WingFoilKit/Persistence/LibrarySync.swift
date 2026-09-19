import Foundation
import GRDB

/// **One library, two phones** (issue #7, ADR-026): a folder in iCloud Drive that holds the
/// recordings and the handful of facts nothing else can bring back, and a merge that reads
/// it into whichever device opened it last.
///
/// This file is the *rules* — the layout, the per-field clock, the conflict verdict and the
/// tombstone gate. `LibrarySyncEngine` below is the part that touches the library.
///
/// **Layout in the container**
/// ```
/// Sessions/<uuid>/original.fit|.gpx|.tcx   ← the recording as it was ingested
/// Sessions/<uuid>/meta.json                ← what the rider changed, one clock per field
/// tombstones.json                          ← the sessions deleted on purpose
/// ```
///
/// **What is not there, on purpose.** No `analysis.json`, no database. The analysis is a
/// cache the engine rebuilds in a second and invalidates on its own version, so carrying it
/// would sync a derived file that the receiving device is going to throw away — and would
/// put two engine versions in one folder, which is the one way a rider could read a number
/// this build did not compute. Each device re-analyses what it receives.
public enum LibrarySyncLayout {
    public static let sessionsPrefix = "Sessions"
    public static let metaFile = "meta.json"
    public static let tombstonesFile = "tombstones.json"

    /// The container this channel writes to. Dev is a second app with a second library
    /// (`de.lahmann.wingfoil.dev`), so it gets a second container — a dev build merging into
    /// the App Store build's folder would be a test phone writing into the rider's own
    /// library, which is exactly the accident a separate bundle id exists to prevent.
    public static let releaseContainer = "iCloud.de.lahmann.wingfoil"
    public static let devContainer = "iCloud.de.lahmann.wingfoil.dev"

    /// The ubiquity container identifier for a bundle id, spelled the way the entitlements
    /// are: `iCloud.` + the app's own id, so the dev suffix carries through by itself.
    public static func containerIdentifier(bundleID: String?) -> String {
        guard let bundleID, !bundleID.isEmpty else { return releaseContainer }
        return "iCloud.\(bundleID)"
    }
}

// MARK: - One field, one clock

/// A value the rider set, and when this library last saw it change.
///
/// **Why per field and not per session.** The two devices are edited for different reasons:
/// one names a session on the beach, the other assigns the wing that evening. A row-level
/// "newest wins" would throw one of those away every time, and the loser is invisible —
/// nobody notices a caption that quietly reverted. Per field, both survive.
public struct SyncedField<Value: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    /// nil is a value: "the rider cleared this", which has to be able to win a merge just
    /// as a new string does.
    public var value: Value?
    public var updatedAt: Date

    public init(_ value: Value?, at updatedAt: Date) {
        self.value = value
        self.updatedAt = updatedAt
    }

    /// Never written, never seen — the stamp a field carries before anything has touched it,
    /// so that any real edit on any device beats it.
    public static var unset: SyncedField<Value> { SyncedField(nil, at: .distantPast) }

    /// Last writer wins, and a tie keeps what is already here.
    ///
    /// The tie rule matters more than it looks: two devices that write the same second must
    /// not be able to swap values depending on which one ran the merge, so the incoming side
    /// has to be *strictly* newer to take over. Equal stamps with equal values are the
    /// ordinary case anyway — the same fact, re-exported.
    public func merged(with other: SyncedField<Value>) -> SyncedField<Value> {
        other.updatedAt > updatedAt ? other : self
    }
}

// MARK: - What travels with a session

/// `Sessions/<uuid>/meta.json` — everything about a session that is not in the recording.
///
/// The recording beside it is immutable and needs no clock: bytes that never change cannot
/// conflict. Every field here can, so every field here is stamped.
public struct SyncedSessionMeta: Codable, Sendable, Equatable {

    /// Bumped only when the *shape* of this file changes. A meta written by a newer format
    /// is left alone rather than half-read (`isReadable`).
    public static let currentFormat = 1

    public var format: Int
    public var id: String
    /// The dedupe key (`SessionIngestor.duplicate`), carried so the receiving device can
    /// recognise a session it already holds under a different uuid — an afternoon that
    /// reached the two phones through intervals.icu and through AirDrop has two ids and is
    /// one session.
    public var startDate: Date
    public var durationS: Double

    public var customTitle: SyncedField<String>
    public var shareNote: SyncedField<String>
    public var rider: SyncedField<String>
    public var disciplineOverride: SyncedField<String>
    public var spotName: SyncedField<String>
    /// Gear by kind — `"wing"`, `"board"`, `"foil"` — held by **name**, not by row id. Gear
    /// rows are created per device and their ids would name nothing on the other phone.
    public var gear: SyncedField<[String: String]>
    /// The tombstone, as a field, so that deleting on one device and renaming on the other
    /// is settled by the same clock as any other pair of edits.
    public var deleted: SyncedField<Bool>

    public init(id: String, startDate: Date, durationS: Double,
                format: Int = SyncedSessionMeta.currentFormat,
                customTitle: SyncedField<String> = .unset,
                shareNote: SyncedField<String> = .unset,
                rider: SyncedField<String> = .unset,
                disciplineOverride: SyncedField<String> = .unset,
                spotName: SyncedField<String> = .unset,
                gear: SyncedField<[String: String]> = .unset,
                deleted: SyncedField<Bool> = .unset) {
        self.format = format
        self.id = id
        self.startDate = startDate
        self.durationS = durationS
        self.customTitle = customTitle
        self.shareNote = shareNote
        self.rider = rider
        self.disciplineOverride = disciplineOverride
        self.spotName = spotName
        self.gear = gear
        self.deleted = deleted
    }

    public var isReadable: Bool { format <= Self.currentFormat }

    /// True once this session has been deleted somewhere and not brought back since.
    public var isDeleted: Bool { deleted.value == true }

    /// **The conflict rule, in one place.** Field by field, the later stamp wins; the
    /// identity comes from whichever side is newer overall, because a start date and a
    /// duration are read off the recording and are the same fact on both.
    public func merged(with other: SyncedSessionMeta) -> SyncedSessionMeta {
        var result = self
        result.customTitle = customTitle.merged(with: other.customTitle)
        result.shareNote = shareNote.merged(with: other.shareNote)
        result.rider = rider.merged(with: other.rider)
        result.disciplineOverride = disciplineOverride.merged(with: other.disciplineOverride)
        result.spotName = spotName.merged(with: other.spotName)
        result.gear = gear.merged(with: other.gear)
        result.deleted = deleted.merged(with: other.deleted)
        return result
    }

    /// The newest stamp on the file, which is what "changed since I last looked" means.
    public var updatedAt: Date {
        [customTitle.updatedAt, shareNote.updatedAt, rider.updatedAt,
         disciplineOverride.updatedAt, spotName.updatedAt, gear.updatedAt,
         deleted.updatedAt].max() ?? .distantPast
    }

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

/// One line of `tombstones.json`.
///
/// The same four facts `SessionTombstoneRow` keeps, and for the same reason: an id is the
/// exact answer where there is one, and the ±60 s dedupe key is the answer where there is
/// not. A session that reached the second phone from a Garmin ZIP carries no intervals.icu
/// id and is still the session that was deleted on the first.
public struct SyncedTombstone: Codable, Sendable, Equatable {
    public var id: String
    public var icuActivityId: String?
    public var startDate: Date
    public var durationS: Double
    public var title: String?
    public var deletedAt: Date

    public init(id: String, icuActivityId: String? = nil, startDate: Date, durationS: Double,
                title: String? = nil, deletedAt: Date) {
        self.id = id
        self.icuActivityId = icuActivityId
        self.startDate = startDate
        self.durationS = durationS
        self.title = title
        self.deletedAt = deletedAt
    }

    public init(_ row: SessionTombstoneRow) {
        self.init(id: row.id, icuActivityId: row.icuActivityId, startDate: row.startDate,
                  durationS: row.durationS, title: row.title, deletedAt: row.deletedAt)
    }

    public var asRow: SessionTombstoneRow {
        SessionTombstoneRow(id: id, icuActivityId: icuActivityId, startDate: startDate,
                            durationS: durationS, title: title, deletedAt: deletedAt)
    }
}

/// The root index of what was thrown away.
///
/// It duplicates the `deleted` field of every `meta.json`, on purpose. A folder can be
/// removed — by the rider in the Files app, by a device that ran out of room — and the
/// deletion has to survive that, because a tombstone the container forgot is a session that
/// comes back on the next phone that syncs.
public struct SyncedTombstones: Codable, Sendable, Equatable {
    public var format: Int
    public var stones: [SyncedTombstone]

    public init(format: Int = SyncedSessionMeta.currentFormat,
                stones: [SyncedTombstone] = []) {
        self.format = format
        self.stones = stones
    }

    /// The tombstone that blocks this recording, or nil.
    ///
    /// The same two-sided ±60 s rule the ingest path uses, asked here rather than there
    /// because a blocked session should cost nothing — not a copy out of the container and
    /// not an analysis.
    public func blocking(id: String, startDate: Date, durationS: Double,
                         toleranceS: TimeInterval = 60) -> SyncedTombstone? {
        if let byId = stones.first(where: { $0.id == id }) { return byId }
        return stones.first {
            abs($0.startDate.timeIntervalSince(startDate)) <= toleranceS
                && abs($0.durationS - durationS) <= toleranceS
        }
    }

    /// Newest deletion of each session, both sides merged. A tombstone is never dropped by
    /// a merge: only the rider's own "re-add" clears one, and that clears it locally.
    public func merged(with other: SyncedTombstones) -> SyncedTombstones {
        var byId: [String: SyncedTombstone] = [:]
        for stone in stones + other.stones {
            if let held = byId[stone.id], held.deletedAt >= stone.deletedAt { continue }
            byId[stone.id] = stone
        }
        return SyncedTombstones(stones: byId.values.sorted { $0.deletedAt > $1.deletedAt })
    }
}

// MARK: - The folder

/// The container as a **directory**, and nothing more.
///
/// Deliberately blind to iCloud: it is handed a URL, and a temp directory is as good a URL
/// as a ubiquity container. That is what makes the layout testable, and what makes
/// `UI_SYNC_CONTAINER` a one-line hook rather than a mock (docs/testing.md, "Two devices,
/// one library").
///
/// Every read and write goes through `NSFileCoordinator`, because the other writer here is
/// not another thread — it is `bird`, downloading a file the other phone uploaded, and a
/// half-written `meta.json` read mid-download is a merge against garbage.
public struct LibrarySyncContainer: Sendable {

    public enum Error: Swift.Error, CustomStringConvertible {
        case unavailable
        case coordination(String)

        public var description: String {
            switch self {
            case .unavailable: "iCloud Drive is not available on this device"
            case .coordination(let why): "could not read the iCloud Drive folder: \(why)"
            }
        }
    }

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// The live ubiquity container, or nil when the rider is not signed in to iCloud.
    ///
    /// `url(forUbiquityContainerIdentifier:)` blocks on first call while the daemon sets the
    /// folder up, which is why nothing on the main actor may ask for it.
    public static func ubiquitous(identifier: String) -> LibrarySyncContainer? {
        guard let url = FileManager.default.url(forUbiquityContainerIdentifier: identifier) else {
            return nil
        }
        return LibrarySyncContainer(root: url.appendingPathComponent("Documents",
                                                                     isDirectory: true))
    }

    public var sessionsRoot: URL {
        root.appendingPathComponent(LibrarySyncLayout.sessionsPrefix, isDirectory: true)
    }

    public var tombstonesURL: URL {
        root.appendingPathComponent(LibrarySyncLayout.tombstonesFile)
    }

    public func directory(for id: String) -> URL {
        sessionsRoot.appendingPathComponent(id, isDirectory: true)
    }

    public func metaURL(for id: String) -> URL {
        directory(for: id).appendingPathComponent(LibrarySyncLayout.metaFile)
    }

    public func prepare() throws {
        try FileManager.default.createDirectory(at: sessionsRoot,
                                                withIntermediateDirectories: true)
    }

    /// Every session folder in the container, whether or not its recording has finished
    /// downloading.
    public func sessionIDs() -> [String] {
        let found = (try? FileManager.default.contentsOfDirectory(
            at: sessionsRoot, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return found
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .map(\.lastPathComponent)
            .sorted()
    }

    /// The recording in this session's folder, or nil when only the meta has arrived.
    ///
    /// iCloud hands a file that has not been downloaded yet as `.original.fit.icloud`, so a
    /// name check alone would report a recording that cannot be read. The placeholder is
    /// asked to download and reported as absent for this pass; the next sync finds it.
    public func originalURL(for id: String) -> URL? {
        let dir = directory(for: id)
        let entries = (try? FileManager.default.contentsOfDirectory(at: dir,
                                                                    includingPropertiesForKeys: nil))
            ?? []
        for url in entries where url.lastPathComponent.hasPrefix("original.")
        && url.pathExtension != "icloud" {
            return url
        }
        for url in entries where url.lastPathComponent.hasSuffix(".icloud") {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
        return nil
    }

    public func writeOriginal(_ data: Data, id: String) throws {
        let dir = directory(for: id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let format = TrackParser.format(data)
        let target = dir.appendingPathComponent("original.\(format.fileExtension)")
        try coordinatedWrite(to: target) { try data.write(to: $0, options: .atomic) }
    }

    public func meta(for id: String) -> SyncedSessionMeta? {
        guard let data = coordinatedRead(metaURL(for: id)) else { return nil }
        return try? SyncedSessionMeta.decoder().decode(SyncedSessionMeta.self, from: data)
    }

    public func writeMeta(_ meta: SyncedSessionMeta) throws {
        let dir = directory(for: meta.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try SyncedSessionMeta.encoder().encode(meta)
        try coordinatedWrite(to: metaURL(for: meta.id)) { try data.write(to: $0, options: .atomic) }
    }

    public func tombstones() -> SyncedTombstones {
        guard let data = coordinatedRead(tombstonesURL),
              let decoded = try? SyncedSessionMeta.decoder().decode(SyncedTombstones.self,
                                                                    from: data) else {
            return SyncedTombstones()
        }
        return decoded
    }

    public func writeTombstones(_ stones: SyncedTombstones) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try SyncedSessionMeta.encoder().encode(stones)
        try coordinatedWrite(to: tombstonesURL) { try data.write(to: $0, options: .atomic) }
    }

    /// Drops a deleted session's bytes but keeps its folder's memory in `tombstones.json`.
    /// The `meta.json` stays: it carries the `deleted` field's clock, and a device that has
    /// not synced since needs to read it.
    public func removeOriginal(for id: String) {
        let dir = directory(for: id)
        let entries = (try? FileManager.default.contentsOfDirectory(at: dir,
                                                                    includingPropertiesForKeys: nil))
            ?? []
        for url in entries where url.lastPathComponent.hasPrefix("original.") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    public func data(at url: URL) -> Data? { coordinatedRead(url) }

    // MARK: File coordination

    private func coordinatedRead(_ url: URL) -> Data? {
        var result: Data?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) {
            result = try? Data(contentsOf: $0)
        }
        return result
    }

    private func coordinatedWrite(to url: URL, _ body: (URL) throws -> Void) throws {
        var thrown: Swift.Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing,
                                       error: &coordinationError) { target in
            do { try body(target) } catch { thrown = error }
        }
        if let coordinationError { throw Error.coordination(coordinationError.localizedDescription) }
        if let thrown { throw thrown }
    }
}
