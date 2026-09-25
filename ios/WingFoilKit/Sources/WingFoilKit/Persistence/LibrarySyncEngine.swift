import Foundation
import GRDB

/// **The pass itself**: read the folder, merge it into this library, write this library back
/// (ADR-026, issue #7).
///
/// Three properties hold it together, and every one of them is a test in
/// `LibrarySyncTests`:
///
/// * **Nothing is imported around the front door.** A recording arrives through
///   `SessionIngestor.ingest`, which means the ±60 s dedupe rule, the discipline ladder, the
///   spot clusterer and the default gear all run exactly as they do for a file dropped on
///   the app. A session the phone already holds under another uuid is recognised as the
///   duplicate it is.
/// * **A deletion outranks an arrival.** Tombstones are merged first and consulted before
///   anything is read, so a session deleted on one phone cannot be brought back by the
///   other's copy of the same recording — nor by the same file dropped in again later.
/// * **The analysis never travels.** Each device analyses what it receives, under its own
///   engine version. `analysis.json` is not in the folder and is not written to it.
public struct LibrarySyncEngine: Sendable {

    public var ingestor: SessionIngestor
    public var container: LibrarySyncContainer
    /// The same ±60 s the library's own dedupe uses. One rule, one number.
    public var toleranceS: TimeInterval = 60

    public init(ingestor: SessionIngestor, container: LibrarySyncContainer) {
        self.ingestor = ingestor
        self.container = container
    }

    private var library: LibraryStore { ingestor.library }

    // MARK: - What a pass did

    public struct Report: Sendable, Equatable {
        /// Recordings copied into the folder.
        public var uploaded = 0
        /// Recordings read out of it and ingested here.
        public var downloaded = 0
        /// Sessions whose meta changed on one side or the other.
        public var merged = 0
        /// Arrivals the ±60 s rule recognised as sessions this phone already holds.
        public var duplicates = 0
        /// Arrivals a tombstone refused.
        public var blocked = 0
        /// Sessions deleted here because the other device deleted them.
        public var deletedHere = 0
        /// Folders whose recording has not finished downloading yet. Not an error: the next
        /// pass picks them up.
        public var waiting = 0
        public var failed: [String] = []

        public init() {}

        public var isEmpty: Bool {
            uploaded == 0 && downloaded == 0 && merged == 0 && deletedHere == 0
        }

        /// One line for the status row. Register 3, and it names only what happened.
        public var shortDescription: String {
            var parts: [String] = []
            if downloaded > 0 { parts.append("\(downloaded) in") }
            if uploaded > 0 { parts.append("\(uploaded) out") }
            if merged > 0 { parts.append("\(merged) updated") }
            if deletedHere > 0 { parts.append("\(deletedHere) removed") }
            if waiting > 0 { parts.append("\(waiting) still arriving") }
            return parts.isEmpty ? "Nothing to sync" : parts.joined(separator: ", ")
        }
    }

    /// What a pass **would** do, without doing any of it — the status line's numbers, and
    /// the dev build's way of looking at a container before trusting it.
    public struct Plan: Sendable, Equatable {
        public var localSessions = 0
        /// The sessions the folder holds, counted the way the library counts them: one per
        /// afternoon, and none the rider deleted. This is the number Settings shows, so it
        /// has to be comparable with Storage's session count.
        ///
        /// It used to be the number of *folders*, and a deleted session keeps its folder:
        /// `meta.json` stays behind so a device that has not synced since can read the
        /// deletion (`removeOriginal`). On Jan's dev build that read "69 sessions" beside a
        /// library of 63, the six being sessions he had deleted since the switch went on.
        public var containerSessions = 0
        /// Every session folder, deleted or doubled ones included — the raw `ls | wc -l`.
        public var containerFolders = 0
        /// Folders of sessions deleted on one device or the other. They stay deleted.
        public var containerDeleted = 0
        /// Extra folders for an afternoon another folder already holds. Zero unless the
        /// ±60 s lookup in `push` was bypassed; a pull folds them into one session.
        public var containerDuplicates = 0
        /// Here and not there.
        public var toUpload: [String] = []
        /// There and not here.
        public var toDownload: [String] = []
        /// Deleted there, still here.
        public var toDeleteHere: [String] = []
        /// There, but the recording has not downloaded yet.
        public var waiting: [String] = []
        public var tombstones = 0

        public init() {}

        /// The one number the Settings line shows beside the session count.
        public var pending: Int {
            toUpload.count + toDownload.count + toDeleteHere.count + waiting.count
        }
    }

    // MARK: - Dry run

    public func plan() async throws -> Plan {
        var plan = Plan()
        let locals = try await syncableSessions()
        let stones = container.tombstones().merged(with: SyncedTombstones(
            stones: try await library.tombstones().map(SyncedTombstone.init)))
        let folders = index()
        plan.tombstones = stones.stones.count
        plan.localSessions = locals.count
        plan.containerFolders = folders.count

        var afternoons: [SyncedSessionMeta] = []
        for (id, meta) in folders.sorted(by: { $0.key < $1.key }) {
            let here = locals.first { matches(meta, $0) }
            if meta.isDeleted || stones.blocking(id: id, startDate: meta.startDate,
                                                 durationS: meta.durationS,
                                                 toleranceS: toleranceS) != nil {
                plan.containerDeleted += 1
                if here != nil { plan.toDeleteHere.append(id) }
                continue
            }
            // A second folder for an afternoon already counted is one session, and a pull
            // lands it as the duplicate it is — so it is neither counted nor pending.
            if afternoons.contains(where: { sameAfternoon($0, meta) }) {
                plan.containerDuplicates += 1
                continue
            }
            afternoons.append(meta)
            if here != nil { continue }
            if container.originalURL(for: id) == nil {
                plan.waiting.append(id)
            } else {
                plan.toDownload.append(id)
            }
        }

        for row in locals where folders.values.first(where: { matches($0, row) }) == nil {
            plan.toUpload.append(row.id)
        }
        plan.containerSessions = afternoons.count
        plan.toDownload.sort()
        plan.toDeleteHere.sort()
        plan.waiting.sort()
        plan.toUpload.sort()
        return plan
    }

    // MARK: - The pass

    /// Pull, then push. In that order on purpose: a deletion that arrived from the other
    /// device has to be applied here *before* this device writes its own list back, or the
    /// push would put the session it has not deleted yet straight back in the folder.
    @discardableResult
    public func sync(now: Date = Date()) async throws -> Report {
        try container.prepare()
        var report = try await pull(now: now)
        let pushed = try await push(now: now)
        report.uploaded += pushed.uploaded
        report.merged += pushed.merged
        report.failed.append(contentsOf: pushed.failed)
        return report
    }

    // MARK: Pull

    /// Everything the folder knows that this library does not.
    public func pull(now: Date = Date()) async throws -> Report {
        var report = Report()
        try container.prepare()

        // 1. Tombstones first, and both ways, so the rest of the pass can simply ask.
        let stones = try await mergeTombstones()

        // 2. The deletions this device has not applied yet.
        for row in try await syncableSessions() {
            guard stones.blocking(id: row.id, startDate: row.startDate,
                                  durationS: row.durationS,
                                  toleranceS: toleranceS) != nil else { continue }
            try await ingestor.delete(row, title: row.customTitle)
            report.deletedHere += 1
        }

        // 3. What arrived.
        for (id, meta) in index() {
            if meta.isDeleted { continue }
            if stones.blocking(id: id, startDate: meta.startDate, durationS: meta.durationS,
                               toleranceS: toleranceS) != nil {
                report.blocked += 1
                continue
            }
            do {
                guard let landed = try await land(meta, report: &report) else { continue }
                if try await apply(meta, to: landed, now: now) { report.merged += 1 }
            } catch {
                report.failed.append("\(id): \(error)")
            }
        }
        return report
    }

    /// The session this folder describes, as a row in *this* library — ingested if it is
    /// new, recognised if it is not, nil while its recording is still downloading.
    ///
    /// **The uuids are not expected to match.** A session ingested on the other phone got
    /// its id there, and a recording that reached both phones separately has two. The folder
    /// is keyed by whichever device wrote it first; here it is found by the library's own
    /// ±60 s dedupe key, the same way a backup's restore finds the row a zip describes
    /// (ADR-015). Nothing renumbers a row that already exists.
    private func land(_ meta: SyncedSessionMeta,
                      report: inout Report) async throws -> SessionRow? {
        if let existing = try await ingestor.session(id: meta.id) { return existing }
        if let known = try await duplicate(of: meta) {
            report.duplicates += 1
            return known
        }
        guard let url = container.originalURL(for: meta.id),
              let data = container.data(at: url) else {
            report.waiting += 1
            return nil
        }
        // THE front door: dedupe, discipline ladder, spot clusterer, default gear.
        switch try await ingestor.ingest(fitData: data, filename: url.lastPathComponent,
                                         source: .file) {
        case .imported(let row):
            report.downloaded += 1
            return row
        case .duplicate(let row):
            report.duplicates += 1
            return row
        case .skipped(let reason):
            report.failed.append("\(meta.id): \(reason)")
            return nil
        }
    }

    // MARK: Push

    /// Everything this library knows that the folder does not.
    ///
    /// A session is written back **into the folder it is already in**, found by the dedupe
    /// key rather than by uuid. Without that, a session that arrived here from the other
    /// phone would be written out again under this device's own id, and one afternoon would
    /// stand in iCloud Drive twice — growing a third copy on the next device and a fourth
    /// after that.
    public func push(now: Date = Date()) async throws -> Report {
        var report = Report()
        try container.prepare()
        let stones = try await mergeTombstones()
        let folders = index()

        for row in try await syncableSessions() {
            // Deleted on the other device and not yet applied here: the next pull removes
            // it, and pushing it now would be this device arguing with that.
            if stones.blocking(id: row.id, startDate: row.startDate, durationS: row.durationS,
                               toleranceS: toleranceS) != nil { continue }
            let folderID = folders.first { matches($0.value, row) }?.key ?? row.id
            do {
                if container.originalURL(for: folderID) == nil,
                   let data = try? ingestor.archive.originalData(for: row.id) {
                    try container.writeOriginal(data, id: folderID)
                    report.uploaded += 1
                }
                // Stamped against what this device last agreed with the folder, never
                // against the folder's current copy: the other phone's edit is not this
                // one's, and measuring against it would report every arrival as a change.
                let previous = folders[folderID]
                let mine = try await meta(for: row, id: folderID,
                                          previous: baseline(for: row), now: now)
                let written = previous.map { $0.merged(with: mine) } ?? mine
                if written != previous {
                    try container.writeMeta(written)
                    report.merged += 1
                }
                setBaseline(written, for: row.id)
            } catch {
                report.failed.append("\(row.id): \(error)")
            }
        }
        return report
    }

    // MARK: - Tombstones, both ways

    /// The union of what each side threw away, written back to both.
    @discardableResult
    public func mergeTombstones() async throws -> SyncedTombstones {
        let mine = SyncedTombstones(stones: try await library.tombstones().map(SyncedTombstone.init))
        let theirs = container.tombstones()
        let merged = theirs.merged(with: mine)
        if merged != theirs { try container.writeTombstones(merged) }
        // A tombstone the folder knows and this library does not is written down here too,
        // so that the rider's own re-add offer can name it and so a later import of the same
        // recording from any other door is refused by the ordinary rule.
        //
        // **Except where the session is still standing here.** That row is deleted a moment
        // later by the pull, and `SessionIngestor.delete` writes the tombstone this library
        // can actually use — under this device's own uuid. Writing the incoming one as well
        // would leave two stones for one afternoon and "Previously deleted: 2" for a rider
        // who deleted one session.
        let locals = try await syncableSessions()
        let incoming = merged.stones.filter { stone in
            // Already written down here, under this uuid or under the one this device gave
            // the same afternoon. The ±60 s half is what makes the guard hold after the
            // delete below has run: `SessionIngestor.delete` wrote its own stone, and the
            // folder's is the same deletion seen from the other phone.
            if mine.blocking(id: stone.id, startDate: stone.startDate,
                             durationS: stone.durationS, toleranceS: toleranceS) != nil {
                return false
            }
            // Still standing here: the pull deletes it in a moment and that writes the
            // stone this library can use. Two stones for one afternoon would read as
            // "Previously deleted: 2" to a rider who deleted one session.
            return !locals.contains { row in
                abs(row.startDate.timeIntervalSince(stone.startDate)) <= toleranceS
                    && abs(row.durationS - stone.durationS) <= toleranceS
            }
        }
        if !incoming.isEmpty {
            let rows = incoming.map(\.asRow)
            try await ingestor.database.writer.write { db in
                for row in rows where try SessionTombstoneRow.fetchOne(db, key: row.id) == nil {
                    try row.insert(db)
                }
            }
        }
        // The bytes of a deleted session have no reason to sit in iCloud Drive. Asked of the
        // folder rather than of the tombstone, because the two carry different uuids for the
        // same afternoon as often as not.
        for (id, meta) in index() where stones(merged, blocks: id, meta) {
            container.removeOriginal(for: id)
        }
        return merged
    }

    private func stones(_ all: SyncedTombstones, blocks id: String,
                        _ meta: SyncedSessionMeta) -> Bool {
        all.blocking(id: id, startDate: meta.startDate, durationS: meta.durationS,
                     toleranceS: toleranceS) != nil
    }

    // MARK: - One session, both ways

    /// What this library would write about a session, stamped against what the folder
    /// already says.
    ///
    /// **The clock is the sync's, not the edit's.** The library has no per-field
    /// `updatedAt` column and is not about to grow six, so a field is stamped `now` the
    /// first time a pass sees it differ from the folder's copy, and keeps the folder's stamp
    /// while it agrees. The consequence is the honest one and is written down in ADR-026: an
    /// edit made offline is dated when it reaches the folder, so a rider who edits on the
    /// beach and syncs in the evening loses to a device that edited the same field at noon
    /// and synced at noon. Per field, and only where both devices touched the same field.
    ///
    /// `id` is the **folder's** id, which is this row's uuid only when this device is the
    /// one that put the session there.
    public func meta(for row: SessionRow, id: String? = nil, previous: SyncedSessionMeta?,
                     now: Date = Date()) async throws -> SyncedSessionMeta {
        let folderID = id ?? previous?.id ?? row.id
        let base = previous ?? SyncedSessionMeta(id: folderID, startDate: row.startDate,
                                                 durationS: row.durationS)
        var meta = SyncedSessionMeta(id: folderID, startDate: base.startDate,
                                     durationS: base.durationS)
        meta.customTitle = Self.stamp(row.customTitle, was: base.customTitle, now: now)
        meta.shareNote = Self.stamp(row.shareNote, was: base.shareNote, now: now)
        meta.rider = Self.stamp(row.rider, was: base.rider, now: now)
        meta.disciplineOverride = Self.stamp(row.disciplineOverride, was: base.disciplineOverride,
                                             now: now)
        meta.spotName = Self.stamp(try await spotName(of: row), was: base.spotName, now: now)
        let gear = try await library.gearOfSession(row.id)
        var names: [String: String] = [:]
        for (kind, item) in gear { names[kind.rawValue] = item.name }
        meta.gear = Self.stamp(names.isEmpty ? nil : names, was: base.gear, now: now)
        meta.deleted = base.deleted
        return meta
    }

    static func stamp<Value: Codable & Sendable & Equatable>(
        _ value: Value?, was previous: SyncedField<Value>, now: Date) -> SyncedField<Value> {
        value == previous.value ? previous : SyncedField(value, at: now)
    }

    /// Writes the merged meta onto the local row. Returns whether anything moved.
    @discardableResult
    public func apply(_ meta: SyncedSessionMeta, to row: SessionRow,
                      now: Date = Date()) async throws -> Bool {
        let mine = try await self.meta(for: row, id: meta.id, previous: baseline(for: row),
                                       now: now)
        let merged = meta.merged(with: mine)
        var changed = false

        if merged.customTitle.value != row.customTitle {
            try await library.renameSession(id: row.id, to: merged.customTitle.value)
            changed = true
        }
        if merged.shareNote.value != row.shareNote {
            try await library.setShareNote(id: row.id, to: merged.shareNote.value)
            changed = true
        }
        if merged.rider.value != row.rider {
            let rider = merged.rider.value
            let id = row.id
            try await ingestor.database.writer.write { db in
                try db.execute(sql: "UPDATE session SET rider = ? WHERE id = ?",
                               arguments: [rider, id])
            }
            changed = true
        }
        if merged.disciplineOverride.value != row.disciplineOverride,
           let discipline = Discipline(rawValue: merged.disciplineOverride.value ?? "") {
            try await ingestor.setDiscipline(discipline, for: row)
            changed = true
        }
        if let name = merged.spotName.value, name != (try await spotName(of: row)),
           let spotId = row.spotId {
            try await library.renameSpot(id: spotId, to: name)
            changed = true
        }
        if let wanted = merged.gear.value {
            let held = try await library.gearOfSession(row.id)
            for (kind, name) in wanted {
                guard let kind = GearKind(rawValue: kind) else { continue }
                guard held[kind]?.name != name else { continue }
                let item = try await gear(named: name, kind: kind)
                try await library.assignGear(sessionId: row.id, kind: kind, gearId: item.id)
                changed = true
            }
        }
        if merged != meta { try container.writeMeta(merged) }
        setBaseline(merged, for: row.id)
        return changed
    }

    // MARK: - The baseline

    /// What this device last agreed with the folder about one session, kept beside the
    /// recording it belongs to (`Sessions/<uuid>/sync.json` in Application Support).
    ///
    /// **It is what tells a value apart from an edit.** A row whose title is empty is either
    /// a session nobody has named or a title the rider just cleared, and the library cannot
    /// say which — it has one column and no clock. Against the last agreed copy it is
    /// obvious: equal means nothing happened here, different means this device changed it.
    /// Without the baseline a freshly arrived session would "clear" every field the other
    /// phone had filled in, one pass after receiving them.
    ///
    /// Local, per device, and disposable: losing it costs one pass in which this device's
    /// values look freshly typed. It is not synced, for the same reason the analysis is not.
    func baseline(for row: SessionRow) -> SyncedSessionMeta? {
        guard let data = try? Data(contentsOf: baselineURL(row.id)) else { return nil }
        return try? SyncedSessionMeta.decoder().decode(SyncedSessionMeta.self, from: data)
    }

    func setBaseline(_ meta: SyncedSessionMeta, for id: String) {
        guard let data = try? SyncedSessionMeta.encoder().encode(meta) else { return }
        try? FileManager.default.createDirectory(at: ingestor.archive.directory(for: id),
                                                 withIntermediateDirectories: true)
        try? data.write(to: baselineURL(id), options: .atomic)
    }

    private func baselineURL(_ id: String) -> URL {
        ingestor.archive.directory(for: id).appendingPathComponent("sync.json")
    }

    // MARK: - Internals

    /// Every readable folder in the container, by its id.
    ///
    /// A folder whose `meta.json` has not arrived yet is not in here: the meta is what says
    /// which session the folder holds, and a recording without one cannot be matched against
    /// this library without parsing it. The next pass finds it.
    func index() -> [String: SyncedSessionMeta] {
        var found: [String: SyncedSessionMeta] = [:]
        for id in container.sessionIDs() {
            guard let meta = container.meta(for: id), meta.isReadable else { continue }
            found[id] = meta
        }
        return found
    }

    /// Whether a folder and a library row are the same afternoon — the library's own ±60 s
    /// dedupe key, asked of a meta instead of a recording, plus the uuid for the ordinary
    /// case where this device wrote the folder itself.
    func matches(_ meta: SyncedSessionMeta, _ row: SessionRow) -> Bool {
        if meta.id == row.id { return true }
        return abs(meta.startDate.timeIntervalSince(row.startDate)) <= toleranceS
            && abs(meta.durationS - row.durationS) <= toleranceS
    }

    /// Whether two folders describe the same afternoon — the same ±60 s key, folder to folder.
    func sameAfternoon(_ a: SyncedSessionMeta, _ b: SyncedSessionMeta) -> Bool {
        if a.id == b.id { return true }
        return abs(a.startDate.timeIntervalSince(b.startDate)) <= toleranceS
            && abs(a.durationS - b.durationS) <= toleranceS
    }

    /// The sessions this library offers the folder: the rider's own, with a recording.
    ///
    /// The bundled example is left out for the same reason the backup leaves it out of the
    /// tombstones — it is not the rider's session, both devices already have it, and syncing
    /// it would copy the same demo FIT into iCloud Drive for ever. A provisional row (the
    /// watch's card, no FIT yet) has nothing to send.
    private func syncableSessions() async throws -> [SessionRow] {
        try await ingestor.allSessions().filter { !$0.isExample && !$0.isProvisional }
    }

    private func duplicate(of meta: SyncedSessionMeta) async throws -> SessionRow? {
        try await ingestor.duplicate(startDate: meta.startDate, durationS: meta.durationS)
    }

    private func spotName(of row: SessionRow) async throws -> String? {
        guard let spotId = row.spotId else { return nil }
        return try await ingestor.database.writer.read { db in
            try SpotRow.fetchOne(db, key: spotId)?.name
        }
    }

    /// The gear row with this name and kind, created if this device has never seen it.
    /// Names, not ids: the other phone made its own rows and its ids name nothing here.
    private func gear(named name: String, kind: GearKind) async throws -> GearRow {
        let existing = try await library.gear(kind: kind, includeRetired: true)
        if let hit = existing.first(where: { $0.name == name }) { return hit }
        return try await library.saveGear(GearRow(name: name, kind: kind))
    }
}
