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
}

public enum IngestOutcome: Sendable {
    case imported(SessionRow)
    /// Already in the library (dedupe key matched); the row carries the merged note.
    case duplicate(SessionRow)
    /// Bulk import only: a FIT that is not a watersport session.
    case skipped(reason: String)
}

public struct ImportSummary: Sendable, Equatable {
    public var imported = 0
    public var duplicates = 0
    public var skipped = 0
    public var failed: [String] = []

    public init() {}

    public var isEmpty: Bool { imported == 0 && duplicates == 0 && skipped == 0 && failed.isEmpty }

    public var shortDescription: String {
        var parts: [String] = ["\(imported) imported"]
        if duplicates > 0 { parts.append("\(duplicates) duplicate\(duplicates == 1 ? "" : "s")") }
        if skipped > 0 { parts.append("\(skipped) skipped") }
        if !failed.isEmpty { parts.append("\(failed.count) failed") }
        return parts.joined(separator: ", ")
    }
}

/// FIT bytes → analysis → archive + `session` row. Dedupe key per plan §3.3:
/// start within ±60 s **and** duration within ±60 s (the same session reaches us from
/// intervals.icu, a GDPR bulk ZIP and AirDrop with slightly different rounding).
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
    public var dedupeToleranceS: TimeInterval = 60

    public init(database: AppDatabase, archive: SessionArchive) {
        self.database = database
        self.archive = archive
    }

    // MARK: - Ingest

    /// Ingests one FIT. `requireWatersport` gates bulk imports (ZIP walking); a file the
    /// user picked by hand is always accepted.
    @discardableResult
    public func ingest(fitData: Data, filename: String?, source: ImportSource,
                       icuActivityId: String? = nil,
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

        if let existing = try await duplicate(startDate: startDate, durationS: duration,
                                              icuActivityId: icuActivityId) {
            let merged = try await note(existing, source: source, icuActivityId: icuActivityId)
            return .duplicate(merged)
        }

        let analysis = SessionSummarizer.analyze(track, filterConfig: filterConfig,
                                                 flightConfig: flightConfig,
                                                 recordsConfig: recordsConfig)
        let id = UUID().uuidString
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
        row.importSource = source.rawValue
        row.icuActivityId = icuActivityId
        apply(analysis, to: &row)

        let stored = row
        try await database.writer.write { db in try stored.insert(db) }
        return .imported(row)
    }

    public static func isWatersport(_ caps: SourceCapabilities) -> Bool {
        if caps.discipline != nil || caps.hasDevFields { return true }
        guard let sport = caps.sport?.lowercased() else { return false }
        return watersportSports.contains(sport)
    }

    /// Bulk entry point: walks nested ZIPs/gzip and ingests every qualifying FIT.
    public func ingestContainer(data: Data, name: String, source: ImportSource) async -> ImportSummary {
        let walk = ZipWalker.walk(data: data, name: name)
        var summary = ImportSummary()
        summary.failed.append(contentsOf: walk.unreadable > 0 ? ["\(walk.unreadable) unreadable"] : [])
        // Single hand-picked FIT: no sport gate. Anything unpacked from a container is gated.
        let gate = !(walk.fits.count == 1 && walk.archives == 0)
        for fit in walk.fits {
            do {
                switch try await ingest(fitData: fit.data,
                                        filename: (fit.name as NSString).lastPathComponent,
                                        source: source, requireWatersport: gate) {
                case .imported: summary.imported += 1
                case .duplicate: summary.duplicates += 1
                case .skipped: summary.skipped += 1
                }
            } catch {
                summary.failed.append("\((fit.name as NSString).lastPathComponent): \(error)")
            }
        }
        if walk.fits.isEmpty && summary.failed.isEmpty {
            summary.failed.append("\(name): no FIT found")
        }
        return summary
    }

    // MARK: - Analysis access (lazy re-analysis)

    /// Cached `analysis.json`, recomputed from the archived FIT when missing or stale.
    public func analysis(for row: SessionRow) async throws -> SessionAnalysis {
        if let cached = archive.analysis(for: row.id) { return cached }
        return try await reanalyze(row)
    }

    @discardableResult
    public func reanalyze(_ row: SessionRow) async throws -> SessionAnalysis {
        let track = try archive.rawTrack(for: row.id)
        let analysis = SessionSummarizer.analyze(track, filterConfig: filterConfig,
                                                 flightConfig: flightConfig,
                                                 recordsConfig: recordsConfig)
        try? archive.writeAnalysis(analysis, id: row.id)
        var updated = row
        apply(analysis, to: &updated)
        let stored = updated
        try await database.writer.write { db in try stored.update(db) }
        return analysis
    }

    public func rawTrack(for row: SessionRow) throws -> RawTrack {
        try archive.rawTrack(for: row.id)
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

    private func duplicate(startDate: Date, durationS: Double,
                           icuActivityId: String?) async throws -> SessionRow? {
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
    private func note(_ row: SessionRow, source: ImportSource,
                      icuActivityId: String?) async throws -> SessionRow {
        var updated = row
        var sources = Set((row.importSource ?? "").split(separator: "+").map(String.init))
        sources.insert(source.rawValue)
        updated.importSource = sources.sorted().joined(separator: "+")
        if updated.icuActivityId == nil { updated.icuActivityId = icuActivityId }
        guard updated.importSource != row.importSource || updated.icuActivityId != row.icuActivityId
        else { return row }
        let stored = updated
        try await database.writer.write { db in try stored.update(db) }
        return updated
    }

    private func apply(_ analysis: SessionAnalysis, to row: inout SessionRow) {
        row.engineVersion = analysis.engineVersion
        row.distanceKm = analysis.summary.distanceKm
        row.foilPct = analysis.summary.foilPct
        row.flightCount = analysis.summary.flightCount
        row.longestFlightS = analysis.summary.longestFlightS
        row.best2sKn = analysis.records.best2sKn
        row.best5x10sKn = analysis.records.best5x10sKn
        row.windDirDeg = analysis.wind?.dirDeg
    }
}
