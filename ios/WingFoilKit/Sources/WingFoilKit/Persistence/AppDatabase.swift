import Foundation
import GRDB

/// GRDB database bootstrap. Schema v1 held just the session index; **v2** (phase 4) adds
/// the denormalized per-session summary columns every aggregate screen reads, the child
/// tables derived from `SessionAnalysis` (`flight`, `turn`, `takeoff_attempt`), the PB
/// history (`record_effort`), and the library-side entities `gear`/`session_gear`,
/// `spot` and `import_log`.
///
/// The original FITs live outside the DB as immutable files under `Sessions/<uuid>/`;
/// every column here is derived and may be dropped and recomputed at any time. The v2
/// migration therefore clears `engineVersion` on every existing row: that is exactly the
/// "stored engine version != current" condition that triggers lazy re-analysis
/// (plan §3.3), so a v1 library re-derives itself — child tables included — on first use.
public struct AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    public static func onDisk(at url: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try AppDatabase(DatabaseQueue(path: url.path))
    }

    /// Every migration this build knows, oldest first — the migration test asserts a v1
    /// database moves through all of them.
    public static let migrationNames = ["v1", "v2", "v3", "v4", "v5", "v6", "v7"]

    /// Public so a caller (and the migration test) can migrate a writer only part of the
    /// way — `migrator.migrate(writer, upTo: "v1")` reproduces a shipped v1 library.
    public static var migrator: DatabaseMigrator {
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

        migrator.registerMigration("v2") { db in
            try Self.createV2Entities(db)
            try Self.extendSessionToV2(db)
            try Self.createV2Children(db)
            // Force lazy re-analysis of everything imported under v1 so the new columns
            // and the child tables get filled from the archived FITs.
            try db.execute(sql: "UPDATE session SET engineVersion = NULL")
        }

        // v3: the bundled example session (`ExampleSession`). One flag, because "this row
        // is not the rider's data" is a fact about provenance that every aggregate has to
        // honour — Records and Trends filter on it in `LibraryStore.clause`. No
        // re-analysis is triggered: nothing derived changes, only who the row belongs to.
        migrator.registerMigration("v3") { db in
            try db.alter(table: "session") { t in
                t.add(column: "isExample", .boolean).notNull().defaults(to: false)
            }
        }

        // v4: the companion card (phase 5). A session the watch told us about over BLE
        // exists in the library minutes after the rider leaves the water, an hour before
        // its FIT syncs — so it needs a row, and the row needs to say that its numbers
        // came from the watch's own arithmetic rather than from this app's engine.
        // Same shape as `isExample` and for the same reason: provenance is a fact about
        // the row that every aggregate has to honour, so it is one column in one place
        // (`LibraryStore.clause`) rather than a rule six call sites must remember.
        // No re-analysis is triggered — there is nothing to re-analyse until the FIT
        // lands, and when it does `SessionIngestor.ingest` upgrades the row in place.
        migrator.registerMigration("v4") { db in
            try db.alter(table: "session") { t in
                t.add(column: "isProvisional", .boolean).notNull().defaults(to: false)
            }
        }

        // v5: whose session this is. A rider can now hand a scrubbed FIT to a friend
        // (`FitShareFilter`), and the app is registered as a handler for `.fit`, so a
        // session that is *somebody else's* can land in the library by tapping an
        // attachment. Without a column saying so, that friend's afternoon would silently
        // become the reader's personal best.
        //
        // NULL means "mine", which is what every existing row is and what the icu sync and
        // the GDPR backfill keep writing — a nullable column rather than a flag plus a
        // name, so "is this mine" and "whose is it" are one question with one answer. Same
        // mechanism as `isExample`/`isProvisional`: `LibraryStore.clause` excludes it from
        // every aggregate in one place. No re-analysis is triggered; nothing derived
        // changes, only who the row belongs to.
        migrator.registerMigration("v5") { db in
            try db.alter(table: "session") { t in
                t.add(column: "rider", .text)
            }
            try db.create(index: "session_rider", on: "session", columns: ["rider"])
        }

        // v6: sessions the rider deleted, so they stay deleted.
        //
        // Deleting a synced session used to be a wish rather than an instruction: the row
        // went, and the next intervals.icu sync saw an activity that was no longer in the
        // library and dutifully downloaded it again. This table is the memory that closes
        // that loop — four facts about a session that used to be here, read by exactly one
        // code path (`IcuSyncService`) and by the Settings row that offers them all back.
        //
        // Not a column on `session`, because a deleted session is *gone*: its FIT is out of
        // the archive and its derived rows have cascaded away. A flag would mean every query
        // in the app grew a condition it must never forget. See `SessionTombstoneRow`.
        migrator.registerMigration("v6") { db in
            try db.create(table: "deleted_session") { t in
                // The deleted row's own uuid — deleting the same session twice is then
                // impossible rather than merely unlikely.
                t.column("id", .text).primaryKey()
                t.column("icuActivityId", .text).indexed()
                // The library's own dedupe key (plan §3.3), for a session that never carried
                // an intervals.icu id but is on intervals.icu all the same.
                t.column("startDate", .datetime).notNull().indexed()
                t.column("durationS", .double).notNull()
                t.column("title", .text)
                t.column("deletedAt", .datetime).notNull()
            }
        }

        // v7: what time it was where the session happened.
        //
        // `startDate` is an instant, and every clock the app printed was that instant
        // formatted in the *reader's* current zone. That is correct only while the reader
        // and the recording share one — a coincidence that ends at every DST boundary
        // (on 25 October 2026 every session in the library would shift by an hour, and
        // stay shifted) and on the first session ridden abroad. A session's time is a fact
        // about the session, so it is stored with the session.
        //
        // Seconds rather than a zone name: what the FIT can tell us is an *offset*
        // (`activity.local_timestamp - activity.timestamp`), not an IANA identifier, and
        // storing a name we had to guess would be inventing a fact. NULL means "no source
        // could say", and `SessionRow.displayZone` falls back to the device's zone there —
        // the old behaviour, kept deliberately for the one case that has no better answer.
        //
        // No re-analysis is triggered: nothing derived changes. Existing rows are backfilled
        // from their archived `original.fit` by `backfillStartUtcOffsets(archive:)`, which
        // re-reads the recording rather than guessing — the app calls it once after opening
        // the database.
        migrator.registerMigration("v7") { db in
            try db.alter(table: "session") { t in
                t.add(column: "startUtcOffsetS", .integer)
            }
        }
        return migrator
    }

    /// Fill `startUtcOffsetS` on every row that has none, from the session's own archived
    /// recording. Returns how many rows were filled.
    ///
    /// Idempotent and cheap to call at every launch: it only looks at NULL rows, and a row
    /// whose FIT cannot answer (no `activity` message, no GPS fix, no archived original —
    /// an intervals.icu-metadata-only row, say) stays NULL and is simply looked at again
    /// next time. That is the right trade: re-reading a handful of files beats writing a
    /// guess into the column that says "this is the offset the session was recorded at".
    ///
    /// It re-reads rather than guessing because the archive *has* the answer:
    /// `SessionArchive` keeps `original.fit` for every imported session, and its `activity`
    /// message carries the offset the watch was wearing. Backfilling from the device's
    /// current zone would have written today's guess into history — and written it as fact.
    @discardableResult
    public func backfillStartUtcOffsets(archive: SessionArchive) async throws -> Int {
        let ids = try await writer.read { db in
            try String.fetchAll(db, sql: """
                SELECT id FROM session WHERE startUtcOffsetS IS NULL ORDER BY startDate DESC
                """)
        }
        guard !ids.isEmpty else { return 0 }

        var found: [String: Int] = [:]
        for id in ids {
            guard let data = try? archive.originalData(for: id),
                  let track = try? TrackParser.parse(data: data),
                  let offset = track.startUtcOffsetS else { continue }
            found[id] = offset
        }
        guard !found.isEmpty else { return 0 }

        let resolved = found
        return try await writer.write { db in
            for (id, offset) in resolved {
                try db.execute(sql: "UPDATE session SET startUtcOffsetS = ? WHERE id = ?",
                               arguments: [offset, id])
            }
            return resolved.count
        }
    }

    // MARK: - v2 pieces

    /// Entities that exist independently of any analysis: places, kit, import history.
    private static func createV2Entities(_ db: Database) throws {
        try db.create(table: "spot") { t in
            t.column("id", .text).primaryKey()
            t.column("name", .text).notNull()
            t.column("lat", .double).notNull()
            t.column("lon", .double).notNull()
            /// Cluster radius in metres (the auto-clusterer's, so a spot can be widened).
            t.column("radiusM", .double).notNull()
            /// False once the rider renames it — auto-naming never overwrites that.
            t.column("autoNamed", .boolean).notNull().defaults(to: true)
            t.column("createdAt", .datetime).notNull()
        }

        try db.create(table: "gear") { t in
            t.column("id", .text).primaryKey()
            t.column("name", .text).notNull()
            /// wing | board | foil — a session carries at most one of each.
            t.column("kind", .text).notNull().indexed()
            t.column("notes", .text)
            t.column("active", .boolean).notNull().defaults(to: true)
            t.column("createdAt", .datetime).notNull()
        }

        try db.create(table: "session_gear") { t in
            t.column("sessionId", .text).notNull()
                .references("session", onDelete: .cascade)
            t.column("gearId", .text).notNull()
                .references("gear", onDelete: .cascade)
            /// Denormalized from `gear.kind` so replacing "the wing of this session" is
            /// one delete, and so the one-per-kind rule is a primary key, not a query.
            t.column("kind", .text).notNull()
            t.primaryKey(["sessionId", "kind"])
        }
        try db.create(index: "session_gear_gear", on: "session_gear", columns: ["gearId"])

        try db.create(table: "import_log") { t in
            t.column("id", .text).primaryKey()
            t.column("startedAt", .datetime).notNull().indexed()
            t.column("finishedAt", .datetime)
            /// ImportSource raw value.
            t.column("source", .text).notNull()
            /// The container the rider picked (`export.zip`), or the single filename.
            t.column("container", .text)
            t.column("found", .integer).notNull().defaults(to: 0)
            t.column("imported", .integer).notNull().defaults(to: 0)
            t.column("duplicates", .integer).notNull().defaults(to: 0)
            t.column("skipped", .integer).notNull().defaults(to: 0)
            t.column("failed", .integer).notNull().defaults(to: 0)
            /// Free-text tail of the failures, for the Import screen.
            t.column("detail", .text)
        }
    }

    /// Everything Trends/Records need without re-reading `analysis.json` for 200 sessions.
    private static func extendSessionToV2(_ db: Database) throws {
        try db.alter(table: "session") { t in
            t.add(column: "foilTimeS", .double)
            t.add(column: "longestFlightM", .double)
            // GP3S set (best2s/best5x10s already exist in v1)
            t.add(column: "best10sKn", .double)
            t.add(column: "best100mKn", .double)
            t.add(column: "best250mKn", .double)
            t.add(column: "best500mKn", .double)
            t.add(column: "bestNmKn", .double)
            t.add(column: "bestHourKn", .double)
            t.add(column: "alpha500Kn", .double)
            // Turn counts by type + outcome
            t.add(column: "tacks", .integer)
            t.add(column: "tacksSuccessful", .integer)
            t.add(column: "tacksFlewThrough", .integer)
            t.add(column: "jibes", .integer)
            t.add(column: "jibesSuccessful", .integer)
            t.add(column: "jibesFlewThrough", .integer)
            t.add(column: "turnsCounted", .integer)
            t.add(column: "turnsSuccessful", .integer)
            t.add(column: "turnSuccessPct", .double)
            t.add(column: "turnsUnclassified", .integer)
            t.add(column: "turnsRejected", .integer)
            t.add(column: "turnsPort", .integer)
            t.add(column: "turnsStarboard", .integer)
            t.add(column: "turnsFlewThrough", .integer)
            t.add(column: "turnsTouchdown", .integer)
            t.add(column: "turnsFellIn", .integer)
            // Takeoff / pump
            t.add(column: "takeoffAttempts", .integer)
            t.add(column: "takeoffSuccesses", .integer)
            t.add(column: "avgPumpsToTakeoff", .double)
            t.add(column: "totalPumpStrokes", .integer)
            // Wind (windDirDeg already exists in v1)
            t.add(column: "windAxisDeg", .double)
            t.add(column: "windConfidence", .double)
            t.add(column: "windSource", .text)
            // Place
            t.add(column: "startLat", .double)
            t.add(column: "startLon", .double)
            t.add(column: "spotId", .text)
            // Capabilities that make a metric "unknown" rather than zero
            t.add(column: "hasAccel", .boolean)
            t.add(column: "hasHR", .boolean)
        }
        try db.create(index: "session_spot", on: "session", columns: ["spotId"])
    }

    /// Per-session detail derived from `SessionAnalysis`. Natural composite keys
    /// (`sessionId` + index) keep re-derivation idempotent: delete by session, re-insert.
    private static func createV2Children(_ db: Database) throws {
        try db.create(table: "flight") { t in
            t.column("sessionId", .text).notNull().references("session", onDelete: .cascade)
            t.column("idx", .integer).notNull()
            t.column("startTs", .double).notNull()
            t.column("endTs", .double).notNull()
            t.column("durationS", .double).notNull()
            t.column("distM", .double).notNull()
            t.column("maxKn", .double).notNull()
            t.column("takeoffPumps", .integer)
            t.primaryKey(["sessionId", "idx"])
        }

        try db.create(table: "turn") { t in
            t.column("sessionId", .text).notNull().references("session", onDelete: .cascade)
            t.column("idx", .integer).notNull()
            t.column("ts", .double).notNull()
            t.column("endTs", .double).notNull()
            /// jibe | tack | turn | bear_away | round_up
            t.column("type", .text).notNull()
            t.column("counted", .boolean).notNull()
            t.column("entryKn", .double).notNull()
            t.column("minKn", .double).notNull()
            t.column("score", .double).notNull()
            t.column("success", .boolean).notNull()
            /// Wind side: port | starboard | unknown
            t.column("side", .text).notNull()
            /// Rotation direction: port | starboard
            t.column("direction", .text).notNull()
            t.column("netDeg", .double).notNull()
            /// flew_through | touchdown | fell_in
            t.column("outcome", .text).notNull()
            t.column("borderline", .boolean).notNull()
            t.primaryKey(["sessionId", "idx"])
        }

        try db.create(table: "takeoff_attempt") { t in
            t.column("sessionId", .text).notNull().references("session", onDelete: .cascade)
            t.column("idx", .integer).notNull()
            t.column("ts", .double).notNull()
            t.column("runStartTs", .double).notNull()
            /// nil without an accel stream, or when the run is truncated — never 0.
            t.column("pumps", .integer)
            t.column("success", .boolean).notNull()
            t.column("timeToFoilS", .double).notNull()
            t.column("entryKn", .double).notNull()
            /// Got up without pumping at all.
            t.column("free", .boolean).notNull()
            t.column("truncated", .boolean).notNull()
            t.primaryKey(["sessionId", "idx"])
        }

        try db.create(table: "record_effort") { t in
            t.column("sessionId", .text).notNull().references("session", onDelete: .cascade)
            /// GP3S window key: best2s | best10s | best5x10s | best100m | … | alpha500
            t.column("kind", .text).notNull()
            t.column("valueKn", .double).notNull()
            /// Wall-clock time of the effort (session start + window start) — the x axis
            /// of the PB sparkline, and what makes efforts orderable across sessions.
            t.column("achievedAt", .datetime).notNull()
            /// Window provenance, so a record row can jump to the effort on the map.
            t.column("windowStartTs", .double)
            t.column("windowDurS", .double)
            /// Denormalized so "all-time PB across source classes" needs no join.
            t.column("sourceClass", .text).notNull()
            t.primaryKey(["sessionId", "kind"])
        }
        try db.create(index: "record_effort_kind", on: "record_effort",
                      columns: ["kind", "valueKn"])
    }
}

/// Row model for the session index table. v1 columns first, then everything schema v2
/// added; all of it derived from `SessionAnalysis` except the place/gear links.
public struct SessionRow: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
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

    // MARK: schema v2
    public var foilTimeS: Double?
    public var longestFlightM: Double?
    public var best10sKn: Double?
    public var best100mKn: Double?
    public var best250mKn: Double?
    public var best500mKn: Double?
    public var bestNmKn: Double?
    public var bestHourKn: Double?
    public var alpha500Kn: Double?
    public var tacks: Int?
    public var tacksSuccessful: Int?
    public var tacksFlewThrough: Int?
    public var jibes: Int?
    public var jibesSuccessful: Int?
    public var jibesFlewThrough: Int?
    public var turnsCounted: Int?
    public var turnsSuccessful: Int?
    public var turnSuccessPct: Double?
    public var turnsUnclassified: Int?
    public var turnsRejected: Int?
    public var turnsPort: Int?
    public var turnsStarboard: Int?
    public var turnsFlewThrough: Int?
    public var turnsTouchdown: Int?
    public var turnsFellIn: Int?
    public var takeoffAttempts: Int?
    public var takeoffSuccesses: Int?
    public var avgPumpsToTakeoff: Double?
    public var totalPumpStrokes: Int?
    public var windAxisDeg: Double?
    public var windConfidence: Double?
    public var windSource: String?
    public var startLat: Double?
    public var startLon: Double?
    public var spotId: String?
    public var hasAccel: Bool?
    public var hasHR: Bool?

    // MARK: schema v3
    /// True only for the FIT bundled with the app (`ExampleSession`). Such a row is shown
    /// in the library — badged, openable, deletable — but is excluded from every aggregate
    /// that claims to describe the rider: Records, Trends, the gear rollups and the
    /// home-screen widget. It is somebody else's session on loan.
    public var isExample = false

    // MARK: schema v4
    /// True for a row built from the watch's BLE card while its FIT has not arrived yet
    /// (`CompanionSummary`). Such a row is real — the rider did that session — and it
    /// stays in the library for ever if the FIT never syncs, badged so nobody mistakes
    /// the watch's numbers for analysed ones. It is excluded from the aggregates until
    /// the FIT lands, at which point `SessionIngestor` fills the same row with real
    /// analysis, clears this flag, and the session rejoins Records and Trends.
    public var isProvisional = false

    // MARK: schema v5
    /// Whose session this is: nil for the rider's own, a friend's name for one that
    /// arrived as a shared FIT.
    ///
    /// A named session is shown in full — the library lists it, the detail page analyses
    /// it exactly like any other — and excluded from every number that claims to describe
    /// *the reader*: records, trends, the week histogram, the gear rollups, the widget.
    /// The exclusion is one condition in `LibraryStore.clause`, for the same reason
    /// `isExample` is: a rule six call sites have to remember is a rule that will be
    /// forgotten, and the failure mode here is someone else's speed in your PB list.
    public var rider: String?

    // MARK: schema v7
    /// The UTC offset **in seconds** that was in force where and when this session was
    /// ridden — the watch's own, out of the FIT's `activity` message
    /// (`RawTrack.startUtcOffsetS`), or intervals.icu's `timezone`, or, failing both, a
    /// coarse guess from the first GPS longitude.
    ///
    /// nil means no source could say. `displayZone` falls back to the device's zone there,
    /// which is the behaviour every session had before this column existed.
    public var startUtcOffsetS: Int?

    /// **The** zone every clock and calendar date this session is drawn in.
    ///
    /// One accessor, deliberately, and the reason the presentation types no longer default
    /// their `timeZone:` parameters to `.current`: a default is a decision made silently at
    /// every call site, and the silent decision here was wrong at all of them. With the
    /// defaults gone the compiler names every place a session's time is printed, and each
    /// one has to answer the question out loud — with this, or with `.current` and a
    /// comment saying why.
    ///
    /// `.current` remains right for a genuinely-*now* surface: Settings' "Last sync", the
    /// trend range pickers, the week buckets a rider scans against this week. Those are
    /// about the reader's calendar, not about any session's.
    public var displayZone: TimeZone {
        startUtcOffsetS.flatMap { TimeZone(secondsFromGMT: $0) } ?? .current
    }

    /// Whether `displayZone` is the session's own answer or the device's stand-in — so a
    /// surface that wants to say "times on your own clock" can know to say it.
    public var hasKnownZone: Bool { startUtcOffsetS != nil }

    public init(id: String = UUID().uuidString, startDate: Date, durationS: Double, sourceClass: String) {
        self.id = id
        self.startDate = startDate
        self.durationS = durationS
        self.sourceClass = sourceClass
    }

    /// Share of jibes that never left the foil (`flew_through`) — the Trends series and
    /// the per-gear aggregate. nil when no jibe was classified, which is *not* 0 %.
    public var jibeFlewThroughPct: Double? {
        guard let jibes, jibes > 0 else { return nil }
        return Double(jibesFlewThrough ?? 0) / Double(jibes) * 100
    }

    /// Port share of the counted turns, 50 % = symmetric. nil without sided turns.
    public var portSharePct: Double? {
        let sided = (turnsPort ?? 0) + (turnsStarboard ?? 0)
        guard sided > 0 else { return nil }
        return Double(turnsPort ?? 0) / Double(sided) * 100
    }

    /// Absolute rider-facing asymmetry: 0 = balanced, 50 = one side only.
    public var asymmetryPct: Double? {
        portSharePct.map { abs($0 - 50) }
    }

    /// Fills every derived column from a fresh analysis. The inverse operation is
    /// `SessionDerivation.childRows`, which fills the child tables from the same input.
    public mutating func apply(_ analysis: SessionAnalysis) {
        engineVersion = analysis.engineVersion
        let s = analysis.summary
        distanceKm = s.distanceKm
        foilPct = s.foilPct
        foilTimeS = s.foilTimeS
        flightCount = s.flightCount
        longestFlightS = s.longestFlightS
        longestFlightM = s.longestFlightM

        let r = analysis.records
        best2sKn = r.best2sKn
        best10sKn = r.best10sKn
        best5x10sKn = r.best5x10sKn
        best100mKn = r.best100mKn
        best250mKn = r.best250mKn
        best500mKn = r.best500mKn
        bestNmKn = r.bestNmKn
        bestHourKn = r.bestHourKn
        alpha500Kn = r.alpha500Kn

        let t = s.turns
        tacks = t.tacks
        tacksSuccessful = t.tacksSuccessful
        tacksFlewThrough = t.tackOutcomes.flewThrough
        jibes = t.jibes
        jibesSuccessful = t.jibesSuccessful
        jibesFlewThrough = t.jibeOutcomes.flewThrough
        turnsCounted = t.turnsCounted
        turnsSuccessful = t.turnsSuccessful
        turnSuccessPct = t.successPct
        turnsUnclassified = t.unclassified
        turnsRejected = t.rejected
        turnsPort = t.port
        turnsStarboard = t.starboard
        turnsFlewThrough = t.outcomes.flewThrough
        turnsTouchdown = t.outcomes.touchdown
        turnsFellIn = t.outcomes.fellIn

        let k = s.takeoff
        takeoffAttempts = k.takeoffAttempts
        takeoffSuccesses = k.takeoffSuccesses
        avgPumpsToTakeoff = k.avgPumpsToTakeoff
        totalPumpStrokes = k.totalPumpStrokes

        windDirDeg = analysis.wind?.dirDeg
        windAxisDeg = analysis.wind?.axisDeg
        windConfidence = analysis.wind?.confidence
        windSource = analysis.wind?.source

        hasAccel = analysis.capabilities.hasAccel
        hasHR = analysis.capabilities.hasHR
    }
}
