import Foundation
import GRDB

/// Where a session entered the library. Stored in `session.importSource`; a session that
/// arrives twice keeps every source it was seen from (`"file+icu"`).
public enum ImportSource: String, Sendable, CaseIterable {
    case icu
    case file
    case gdpr
    case airdrop
    case fixtures
    /// The FIT bundled with the app (`ExampleSession`). The only source that sets
    /// `SessionRow.isExample`, and the only one a later real import can override.
    case example
    /// The watch's BLE card (phase 5, `CompanionSummary`). The only source that carries
    /// no FIT, so the only one that can leave a row `isProvisional`.
    case watch
}

public enum IngestOutcome: Sendable {
    case imported(SessionRow)
    /// Already in the library (dedupe key matched); the row carries the merged note.
    case duplicate(SessionRow)
    /// Bulk import only: a FIT that is not a watersport session.
    case skipped(reason: String)
}

public struct ImportSummary: Sendable, Equatable {
    /// FITs discovered in the container (imported + duplicates + skipped + failed).
    public var found = 0
    public var imported = 0
    public var duplicates = 0
    public var skipped = 0
    public var failed: [String] = []
    /// Name of the file currently being processed — live progress for the UI.
    public var current: String?

    public init() {}

    public var isEmpty: Bool { imported == 0 && duplicates == 0 && skipped == 0 && failed.isEmpty }

    public var processed: Int { imported + duplicates + skipped + failed.count }

    public var shortDescription: String {
        var parts: [String] = ["\(imported) imported"]
        if duplicates > 0 { parts.append("\(duplicates) duplicate\(duplicates == 1 ? "" : "s")") }
        if skipped > 0 { parts.append("\(skipped) skipped") }
        if !failed.isEmpty { parts.append("\(failed.count) failed") }
        return parts.joined(separator: ", ")
    }

    /// Merges another container's tally into this one (multi-file picks, live progress).
    public mutating func absorb(_ other: ImportSummary) {
        found += other.found
        imported += other.imported
        duplicates += other.duplicates
        skipped += other.skipped
        failed.append(contentsOf: other.failed)
    }
}

/// FIT bytes → analysis → archive + `session` row + the schema-v2 child tables. Dedupe
/// key per plan §3.3: start within ±60 s **and** duration within ±60 s (the same session
/// reaches us from intervals.icu, a GDPR bulk ZIP and AirDrop with slightly different
/// rounding).
public struct SessionIngestor: Sendable {

    /// Sports we accept during bulk (ZIP) import. Everything else needs our developer
    /// fields to qualify — Jan's CIQ recordings land as `walking`.
    public static let watersportSports: Set<String> = [
        "windsurfing", "kitesurfing", "sailing", "surfing", "stand_up_paddleboarding",
        "43", "44",
    ]

    public var database: AppDatabase
    public var archive: SessionArchive
    public var filterConfig = FilterConfig()
    public var flightConfig = FlightConfig()
    public var recordsConfig = RecordsConfig()
    /// Carries the rider's declared `defaultTurnType` into the wind estimator
    /// (docs/algorithms.md "Default turn type"). The only engine parameter the app exposes.
    public var windConfig = WindConfig()
    public var dedupeToleranceS: TimeInterval = 60
    public var spotRadiusM: Double = SpotClusterer.defaultRadiusM

    public init(database: AppDatabase, archive: SessionArchive) {
        self.database = database
        self.archive = archive
    }

    public var library: LibraryStore { LibraryStore(database: database) }

    // MARK: - Ingest

    /// Ingests one FIT. `requireWatersport` gates bulk imports (ZIP walking); a file the
    /// user picked by hand is always accepted.
    ///
    /// `rider` is whose session this is — nil for the app owner's own, a friend's name for
    /// a FIT they shared. Only the hand-picked paths ever pass a name: an intervals.icu
    /// sync and a Garmin GDPR backfill are the rider's own account by construction, and a
    /// prompt on either would be asking a question that cannot have a second answer.
    @discardableResult
    public func ingest(fitData: Data, filename: String?, source: ImportSource,
                       icuActivityId: String? = nil,
                       rider: String? = nil,
                       requireWatersport: Bool = false) async throws -> IngestOutcome {
        let track = try FitSessionParser.parse(data: fitData)
        let caps = track.capabilities
        if requireWatersport, !Self.isWatersport(caps) {
            return .skipped(reason: caps.sport ?? "unknown sport")
        }
        guard let startDate = track.startDate, let first = track.samples.first,
              let last = track.samples.last else {
            throw FitSessionParser.ParseError.noRecords
        }
        let duration = last.t - first.t

        let existing = try await duplicate(startDate: startDate, durationS: duration,
                                          icuActivityId: icuActivityId)
        if let existing, !existing.isProvisional {
            let merged = try await note(existing, source: source, icuActivityId: icuActivityId)
            return .duplicate(merged)
        }

        // A provisional row is the watch's card holding this session's place until the FIT
        // syncs (phase 5). This IS that FIT, so it takes over the SAME row — same id, real
        // analysis, flag cleared — instead of appearing beside it. Replacing rather than
        // inserting keeps the gear the rider already picked, keeps anything holding the id
        // valid, and means the library never shows one session twice.
        let analysis = analyze(track)
        let id = existing?.id ?? UUID().uuidString
        try archive.storeOriginal(fitData, id: id)
        do {
            try archive.writeAnalysis(analysis, id: id)
        } catch {
            // Analysis JSON is a cache — a write failure must not lose the session.
        }

        var row = SessionRow(id: id, startDate: startDate, durationS: duration,
                             sourceClass: caps.sourceClass)
        row.sport = caps.sport
        row.discipline = caps.discipline
        row.originalFilename = filename
        // The card's "watch" tag survives the upgrade: the row really did reach the
        // library over BLE first, and that is worth being able to see afterwards.
        row.importSource = Self.merge(sources: existing?.importSource, adding: source)
        row.icuActivityId = icuActivityId ?? existing?.icuActivityId
        row.isExample = source == .example
        // A blank name means "mine": the prompt's text field can be left empty after the
        // rider has tapped "a friend's", and an empty string in the column would exclude
        // the session from every aggregate while showing an empty badge.
        row.rider = Self.riderName(rider) ?? existing?.rider
        if let fix = track.samples.first(where: { $0.lat != nil && $0.lon != nil }) {
            row.startLat = fix.lat
            row.startLon = fix.lon
        }
        row.apply(analysis)

        let inserted = row
        row.spotId = try await database.writer.write { db -> String? in
            // `save`, not `insert`: on the provisional path the row already exists and
            // this call is the moment the card's numbers are overwritten by real ones.
            try inserted.save(db)
            try SessionDerivation.write(analysis, session: inserted, db: db)
            guard let lat = inserted.startLat, let lon = inserted.startLon else { return nil }
            return try SpotClusterer.assign(sessionId: inserted.id, lat: lat, lon: lon, db: db,
                                            radiusM: spotRadiusM)
        }
        // Fresh sessions inherit the combo the rider last used (editable per session) —
        // except the example, which was not ridden on the rider's kit.
        if !row.isExample {
            _ = try? await library.applyDefaultGear(sessionId: row.id)
        }
        return .imported(row)
    }

    /// The name as it goes in the column, or nil for "mine".
    ///
    /// Whitespace-trimmed and empty-to-nil, because the prompt's text field can be left
    /// blank after tapping "a friend's": an empty string would exclude the session from
    /// every aggregate while showing a badge with nothing in it — the worst of both.
    public static func riderName(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func isWatersport(_ caps: SourceCapabilities) -> Bool {
        if caps.discipline != nil || caps.hasDevFields { return true }
        guard let sport = caps.sport?.lowercased() else { return false }
        return watersportSports.contains(sport)
    }

    /// Bulk entry point: streams nested ZIPs/gzip and ingests every qualifying FIT, one
    /// member at a time. Writes an `import_log` row for the run and reports progress
    /// after every file so the UI can show "n found / imported / duplicates / skipped".
    @discardableResult
    public func ingestContainer(data: Data, name: String, source: ImportSource,
                                rider: String? = nil,
                                progress: (@Sendable (ImportSummary) -> Void)? = nil)
    async -> ImportSummary {
        var log = ImportLogRow(source: source, container: name)
        let opened = log
        try? await database.writer.write { db in try opened.insert(db) }

        // A hand-picked single FIT keeps its sport whatever it is; anything unpacked from
        // a real container is gated on sport, so a GDPR export of runs stays out.
        let gate: Bool
        if case .fit = ZipWalker.classify(data) { gate = false } else { gate = true }
        let box = SummaryBox()
        let walk = await ZipWalker.walk(data: data, name: name) { fit in
            let short = (fit.name as NSString).lastPathComponent
            await box.begin(short)
            progress?(await box.snapshot)
            do {
                switch try await ingest(fitData: fit.data, filename: short, source: source,
                                        rider: rider, requireWatersport: gate) {
                case .imported: await box.count(\.imported)
                case .duplicate: await box.count(\.duplicates)
                case .skipped: await box.count(\.skipped)
                }
            } catch {
                await box.fail("\(short): \(error)")
            }
            progress?(await box.snapshot)
        }

        var summary = await box.snapshot
        summary.found = walk.fitCount
        summary.current = nil
        if walk.unreadable > 0 { summary.failed.append("\(walk.unreadable) unreadable") }
        if walk.fitCount == 0 && summary.failed.isEmpty {
            summary.failed.append("\(name): no FIT found")
        }

        log.absorb(summary)
        log.finishedAt = Date()
        let finished = log
        try? await database.writer.write { db in try finished.update(db) }
        progress?(summary)
        return summary
    }

    /// Mutable tally shared with the streaming walker's sink.
    private actor SummaryBox {
        private var summary = ImportSummary()

        var snapshot: ImportSummary { summary }

        func begin(_ name: String) { summary.current = name }
        func count(_ key: WritableKeyPath<ImportSummary, Int>) { summary[keyPath: key] += 1 }
        func fail(_ message: String) { summary.failed.append(message) }
    }

    // MARK: - Analysis access (lazy re-analysis)

    private func analyze(_ track: RawTrack) -> SessionAnalysis {
        SessionSummarizer.analyze(track, filterConfig: filterConfig, flightConfig: flightConfig,
                                  recordsConfig: recordsConfig, windConfig: windConfig)
    }

    /// Cached `analysis.json`, recomputed from the archived FIT when missing or stale.
    public func analysis(for row: SessionRow) async throws -> SessionAnalysis {
        if let cached = archive.analysis(for: row.id), row.engineVersion == cached.engineVersion {
            return cached
        }
        return try await reanalyze(row)
    }

    @discardableResult
    public func reanalyze(_ row: SessionRow) async throws -> SessionAnalysis {
        let track = try archive.rawTrack(for: row.id)
        let analysis = analyze(track)
        try? archive.writeAnalysis(analysis, id: row.id)
        var updated = row
        if updated.startLat == nil,
           let fix = track.samples.first(where: { $0.lat != nil && $0.lon != nil }) {
            updated.startLat = fix.lat
            updated.startLon = fix.lon
        }
        updated.apply(analysis)
        let stored = updated
        try await database.writer.write { db in
            try stored.update(db)
            try SessionDerivation.write(analysis, session: stored, db: db)
            if stored.spotId == nil, let lat = stored.startLat, let lon = stored.startLon {
                try SpotClusterer.assign(sessionId: stored.id, lat: lat, lon: lon, db: db,
                                         radiusM: spotRadiusM)
            }
        }
        return analysis
    }

    /// Re-derives every session whose stored engine version is not the current one
    /// (plan §3.3, lazy re-analysis on an engine bump). The aggregate screens call this
    /// before they read, because a stale row would silently skew a whole trend line.
    /// Returns the number of sessions rebuilt.
    @discardableResult
    public func reanalyzeStale(progress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> Int {
        let stale = try await database.writer.read { db in
            // Provisional rows are excluded because there is nothing to re-derive from:
            // a card carries no track, so re-analysis would fail on every pass for ever
            // and the app would announce "re-derived 1 session" at every single launch.
            try SessionRow.filter(sql: """
                isProvisional = 0 AND (engineVersion IS NULL OR engineVersion <> ?)
                """, arguments: [AnalysisEngine.version])
                .order(Column("startDate")).fetchAll(db)
        }
        guard !stale.isEmpty else { return 0 }
        for (index, row) in stale.enumerated() {
            progress?(index + 1, stale.count)
            _ = try? await reanalyze(row)
        }
        return stale.count
    }

    public func rawTrack(for row: SessionRow) throws -> RawTrack {
        try archive.rawTrack(for: row.id)
    }

    /// `"file"` + `.icu` → `"file+icu"`. Sorted and de-duplicated, so a session that
    /// arrived four ways still reads as one stable string.
    static func merge(sources existing: String?, adding source: ImportSource) -> String {
        var sources = Set((existing ?? "").split(separator: "+").map(String.init))
        sources.remove("")
        sources.insert(source.rawValue)
        return sources.sorted().joined(separator: "+")
    }

    // MARK: - Queries

    public func allSessions() async throws -> [SessionRow] {
        try await database.writer.read { db in
            try SessionRow.order(Column("startDate").desc).fetchAll(db)
        }
    }

    public func session(id: String) async throws -> SessionRow? {
        try await database.writer.read { db in try SessionRow.fetchOne(db, key: id) }
    }

    public func icuActivityIds() async throws -> Set<String> {
        let ids = try await database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT icuActivityId FROM session WHERE icuActivityId IS NOT NULL")
        }
        return Set(ids)
    }

    public func delete(_ row: SessionRow) async throws {
        let id = row.id
        _ = try await database.writer.write { db in try SessionRow.deleteOne(db, key: id) }
        archive.delete(id: id)
    }

    /// Drops every cached analysis; the next open recomputes and rewrites the summary row.
    public func dropAllAnalyses() {
        archive.dropAllAnalyses()
    }

    // MARK: - Internals

    /// THE dedupe rule: start within ±60 s **and** duration within ±60 s (plan §3.3).
    ///
    /// Internal rather than private because the watch's BLE card goes through this exact
    /// call (`ingest(card:)`). A card and its FIT describe the same minutes of the same
    /// afternoon, so if the two ever used different rules the rider would see the session
    /// twice — and neither side can tell a duplicate from two back-to-back sessions.
    func duplicate(startDate: Date, durationS: Double,
                   icuActivityId: String? = nil) async throws -> SessionRow? {
        let tolerance = dedupeToleranceS
        let lower = startDate.addingTimeInterval(-tolerance)
        let upper = startDate.addingTimeInterval(tolerance)
        return try await database.writer.read { db in
            if let icuActivityId,
               let hit = try SessionRow
                .filter(Column("icuActivityId") == icuActivityId).fetchOne(db) {
                return hit
            }
            let candidates = try SessionRow
                .filter(Column("startDate") >= lower && Column("startDate") <= upper)
                .fetchAll(db)
            return candidates.first { abs($0.durationS - durationS) <= tolerance }
        }
    }

    /// Records that an existing session was seen again from another source.
    ///
    /// The example session is a *real* recording, so a rider who owns it will eventually
    /// import it for real and land on the ±60 s dedupe key. When that happens the real
    /// import wins: the row stops being an example and rejoins Records and Trends. The
    /// reverse never happens — loading the example over an already-real row leaves the
    /// flag off, so nobody's own session is demoted by tapping a button.
    func note(_ row: SessionRow, source: ImportSource,
              icuActivityId: String?) async throws -> SessionRow {
        var updated = row
        updated.importSource = Self.merge(sources: row.importSource, adding: source)
        if updated.icuActivityId == nil { updated.icuActivityId = icuActivityId }
        if source != .example { updated.isExample = false }
        guard updated.importSource != row.importSource
                || updated.icuActivityId != row.icuActivityId
                || updated.isExample != row.isExample
        else { return row }
        let stored = updated
        try await database.writer.write { db in try stored.update(db) }
        return updated
    }
}
