import Foundation
import GRDB

// MARK: - Analysis-derived children

/// One flight of one session (`SessionAnalysis.flights`). Deleted and re-inserted
/// wholesale whenever the session is re-analyzed.
public struct FlightRow: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "flight"

    public var sessionId: String
    public var idx: Int
    public var startTs: Double
    public var endTs: Double
    public var durationS: Double
    public var distM: Double
    public var maxKn: Double
    public var takeoffPumps: Int?

    public init(sessionId: String, idx: Int, record: FlightRecord) {
        self.sessionId = sessionId
        self.idx = idx
        startTs = record.startTs
        endTs = record.endTs
        durationS = record.endTs - record.startTs
        distM = record.distM
        maxKn = record.maxKn
        takeoffPumps = record.takeoffPumps
    }
}

/// One detected turn. Course changes (`bear_away`/`round_up`) are stored too — they are
/// real events and the Trends screen counts them out, not away.
public struct TurnRow: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "turn"

    public var sessionId: String
    public var idx: Int
    public var ts: Double
    public var endTs: Double
    public var type: String
    public var counted: Bool
    public var entryKn: Double
    public var minKn: Double
    public var score: Double
    public var success: Bool
    public var side: String
    public var direction: String
    public var netDeg: Double
    public var outcome: String
    public var borderline: Bool

    public init(sessionId: String, idx: Int, record: TurnRecord) {
        self.sessionId = sessionId
        self.idx = idx
        ts = record.ts
        endTs = record.endTs
        type = record.type
        counted = record.counted
        entryKn = record.entryKn
        minKn = record.minKn
        score = record.score
        success = record.success
        side = record.side
        direction = record.direction
        netDeg = record.netDeg
        outcome = record.outcome
        borderline = record.borderline
    }
}

/// One takeoff (every one in the archive is a successful attempt — the engine only emits
/// a `Takeoff` for a flight that happened; failed efforts live in the session summary's
/// `failedAttempts`, which has no per-event geometry to store).
public struct TakeoffAttemptRow: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "takeoff_attempt"

    public var sessionId: String
    public var idx: Int
    public var ts: Double
    public var runStartTs: Double
    public var pumps: Int?
    public var success: Bool
    public var timeToFoilS: Double
    public var entryKn: Double
    public var free: Bool
    public var truncated: Bool

    public init(sessionId: String, idx: Int, record: TakeoffRecord) {
        self.sessionId = sessionId
        self.idx = idx
        ts = record.startTs
        runStartTs = record.runStartTs
        pumps = record.pumps
        success = record.success
        timeToFoilS = record.timeToFoilS
        entryKn = record.entryKn
        free = record.free
        truncated = record.truncated
    }
}

/// The GP3S record kinds, in the order the Records screen shows them.
public enum RecordKind: String, CaseIterable, Sendable, Codable {
    case best2s, best10s, best5x10s, best100m, best250m, best500m, bestNm, bestHour, alpha500

    public var label: String {
        switch self {
        case .best2s: "2 s"
        case .best10s: "10 s"
        case .best5x10s: "5 × 10 s"
        case .best100m: "100 m"
        case .best250m: "250 m"
        case .best500m: "500 m"
        case .bestNm: "1 NM"
        case .bestHour: "1 h"
        case .alpha500: "Alpha 500"
        }
    }

    public func value(in records: GP3SRecords) -> Double? {
        switch self {
        case .best2s: records.best2sKn
        case .best10s: records.best10sKn
        case .best5x10s: records.best5x10sKn
        case .best100m: records.best100mKn
        case .best250m: records.best250mKn
        case .best500m: records.best500mKn
        case .bestNm: records.bestNmKn
        case .bestHour: records.bestHourKn
        case .alpha500: records.alpha500Kn
        }
    }
}

/// One session's best effort for one record kind — the PB *history*, not just the PB.
/// The all-time record is `max(valueKn)`; the sparkline is the whole series.
public struct RecordEffortRow: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "record_effort"

    public var sessionId: String
    public var kind: String
    public var valueKn: Double
    public var achievedAt: Date
    public var windowStartTs: Double?
    public var windowDurS: Double?
    public var sourceClass: String

    public init(sessionId: String, kind: RecordKind, valueKn: Double, achievedAt: Date,
                window: RecordWindow?, sourceClass: String) {
        self.sessionId = sessionId
        self.kind = kind.rawValue
        self.valueKn = valueKn
        self.achievedAt = achievedAt
        windowStartTs = window?.startTs
        windowDurS = window?.durS
        self.sourceClass = sourceClass
    }

    public var recordKind: RecordKind? { RecordKind(rawValue: kind) }
}

// MARK: - Library entities

/// A place, produced by `SpotClusterer` from session start coordinates and renamable.
public struct SpotRow: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "spot"

    public var id: String
    public var name: String
    public var lat: Double
    public var lon: Double
    public var radiusM: Double
    /// Still carrying a machine-made name; the auto-namer only ever touches these.
    public var autoNamed: Bool
    public var createdAt: Date

    public init(id: String = UUID().uuidString, name: String, lat: Double, lon: Double,
                radiusM: Double = SpotClusterer.defaultRadiusM, autoNamed: Bool = true,
                createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.lat = lat
        self.lon = lon
        self.radiusM = radiusM
        self.autoNamed = autoNamed
        self.createdAt = createdAt
    }
}

public enum GearKind: String, CaseIterable, Sendable, Codable, Identifiable {
    case wing, board, foil

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .wing: "Wing"
        case .board: "Board"
        case .foil: "Foil"
        }
    }

    public var symbol: String {
        switch self {
        case .wing: "wind"
        case .board: "surfboard"
        case .foil: "airplane"
        }
    }
}

public struct GearRow: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "gear"

    public var id: String
    public var name: String
    public var kind: String
    public var notes: String?
    /// Retired kit stays in the library (its sessions still reference it) but drops out
    /// of the pickers.
    public var active: Bool
    public var createdAt: Date

    public init(id: String = UUID().uuidString, name: String, kind: GearKind,
                notes: String? = nil, active: Bool = true, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.kind = kind.rawValue
        self.notes = notes
        self.active = active
        self.createdAt = createdAt
    }

    public var gearKind: GearKind? { GearKind(rawValue: kind) }
}

/// A session ↔ gear link. The primary key is (sessionId, kind), so assigning a wing
/// replaces the previous wing instead of accumulating.
public struct SessionGearRow: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "session_gear"

    public var sessionId: String
    public var gearId: String
    public var kind: String

    public init(sessionId: String, gearId: String, kind: GearKind) {
        self.sessionId = sessionId
        self.gearId = gearId
        self.kind = kind.rawValue
    }
}

/// One import run — what the rider picked, and what came of it. Written for every
/// container import (a GDPR ZIP is one row, however many FITs it holds).
public struct ImportLogRow: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "import_log"

    public var id: String
    public var startedAt: Date
    public var finishedAt: Date?
    public var source: String
    public var container: String?
    public var found: Int
    public var imported: Int
    public var duplicates: Int
    public var skipped: Int
    public var failed: Int
    public var detail: String?

    public init(id: String = UUID().uuidString, startedAt: Date = Date(), source: ImportSource,
                container: String?) {
        self.id = id
        self.startedAt = startedAt
        self.source = source.rawValue
        self.container = container
        found = 0
        imported = 0
        duplicates = 0
        skipped = 0
        failed = 0
    }

    public mutating func absorb(_ summary: ImportSummary) {
        imported = summary.imported
        duplicates = summary.duplicates
        skipped = summary.skipped
        failed = summary.failed.count
        found = summary.found
        detail = summary.failed.isEmpty ? nil : summary.failed.prefix(20).joined(separator: "\n")
    }
}

// MARK: - Derivation

/// Turns one `SessionAnalysis` into the rows of the child tables. Pure — the ingestor
/// wraps it in a transaction, the migration test calls it directly.
public enum SessionDerivation {

    public static func flights(_ analysis: SessionAnalysis, sessionId: String) -> [FlightRow] {
        analysis.flights.enumerated().map { FlightRow(sessionId: sessionId, idx: $0.offset,
                                                      record: $0.element) }
    }

    public static func turns(_ analysis: SessionAnalysis, sessionId: String) -> [TurnRow] {
        analysis.turns.enumerated().map { TurnRow(sessionId: sessionId, idx: $0.offset,
                                                  record: $0.element) }
    }

    public static func takeoffs(_ analysis: SessionAnalysis, sessionId: String) -> [TakeoffAttemptRow] {
        analysis.takeoffs.enumerated().map { TakeoffAttemptRow(sessionId: sessionId, idx: $0.offset,
                                                               record: $0.element) }
    }

    /// One effort per achieved record kind. `achievedAt` is wall-clock (session start
    /// plus the window offset) so efforts from different sessions sort against each other;
    /// a kind with no qualifying window produces no row at all — "absent", never 0 kn.
    public static func efforts(_ analysis: SessionAnalysis, session: SessionRow) -> [RecordEffortRow] {
        RecordKind.allCases.compactMap { kind in
            guard let value = kind.value(in: analysis.records), value >= 0.05 else { return nil }
            let window = analysis.records.windows[kind.rawValue]
            let at = session.startDate.addingTimeInterval(window?.startTs ?? 0)
            return RecordEffortRow(sessionId: session.id, kind: kind, valueKn: value,
                                   achievedAt: at, window: window,
                                   sourceClass: session.sourceClass)
        }
    }

    /// Replaces every derived child row of one session.
    public static func write(_ analysis: SessionAnalysis, session: SessionRow, db: Database) throws {
        for table in ["flight", "turn", "takeoff_attempt", "record_effort"] {
            try db.execute(sql: "DELETE FROM \(table) WHERE sessionId = ?", arguments: [session.id])
        }
        for row in flights(analysis, sessionId: session.id) { try row.insert(db) }
        for row in turns(analysis, sessionId: session.id) { try row.insert(db) }
        for row in takeoffs(analysis, sessionId: session.id) { try row.insert(db) }
        for row in efforts(analysis, session: session) { try row.insert(db) }
    }
}
