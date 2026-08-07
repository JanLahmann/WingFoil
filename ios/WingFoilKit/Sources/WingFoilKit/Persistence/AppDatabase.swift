import Foundation
import GRDB

/// GRDB database bootstrap. Schema v1 holds just the session index; flights/turns/attempts
/// tables land with the analysis engine (plan §3.3). Original FITs live outside the DB as
/// immutable files under `Sessions/<uuid>/`.
public struct AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try migrator.migrate(writer)
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    public static func onDisk(at url: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try AppDatabase(DatabaseQueue(path: url.path))
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "session") { t in
                t.column("id", .text).primaryKey()          // uuid, matches archive dir name
                t.column("startDate", .datetime).notNull().indexed()
                t.column("durationS", .double).notNull()
                t.column("sport", .text)
                t.column("discipline", .text).indexed()
                t.column("sourceClass", .text).notNull()    // a | b | c
                t.column("originalFilename", .text)
                t.column("importSource", .text)             // icu | file | gdpr | airdrop
                t.column("icuActivityId", .text).indexed()
                t.column("engineVersion", .text)
                // denormalized summary for list/query; authoritative values in analysis.json
                t.column("distanceKm", .double)
                t.column("foilPct", .double)
                t.column("flightCount", .integer)
                t.column("longestFlightS", .double)
                t.column("best2sKn", .double)
                t.column("best5x10sKn", .double)
                t.column("windDirDeg", .double)
            }
            try db.create(index: "session_dedupe", on: "session", columns: ["startDate", "durationS"])
        }
        return migrator
    }
}

/// Row model for the session index table.
public struct SessionRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "session"

    public var id: String
    public var startDate: Date
    public var durationS: Double
    public var sport: String?
    public var discipline: String?
    public var sourceClass: String
    public var originalFilename: String?
    public var importSource: String?
    public var icuActivityId: String?
    public var engineVersion: String?
    public var distanceKm: Double?
    public var foilPct: Double?
    public var flightCount: Int?
    public var longestFlightS: Double?
    public var best2sKn: Double?
    public var best5x10sKn: Double?
    public var windDirDeg: Double?

    public init(id: String = UUID().uuidString, startDate: Date, durationS: Double, sourceClass: String) {
        self.id = id
        self.startDate = startDate
        self.durationS = durationS
        self.sourceClass = sourceClass
    }
}
