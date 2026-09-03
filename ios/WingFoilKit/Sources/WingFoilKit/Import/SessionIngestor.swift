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
    ///
    /// "Watch" unqualified means **Garmin** throughout this app, which predates the Apple
    /// Watch recorder by four phases; `appleWatch` below is the other one, deliberately
    /// spelled out.
    case watch
    /// A `.cjw` container handed over by the CleanJibe watchOS app
    /// (docs/watch-session-schema.md). Distinct from `.watch` because the two are not the
    /// same event: that one is a Garmin summary card with no recording behind it, this one
    /// is a complete recording that arrived without ever touching an account, a cable or
    /// anybody's cloud.
    ///
    /// Read by `SessionDisplay.sourceClassNote` (a watch session is class (b) but *does*
    /// have an accelerometer, so the standard class-(b) sentence would understate it) and by
    /// `SessionStore.writeNewSessionsToHealth` (the watch already filed this workout with
    /// Health itself, live, with the ring credit the phone's after-the-fact stub cannot give).
    case appleWatch = "applewatch"
    /// A workout recorded with **Apple's own Workout app** and read back out of Health
    /// (docs/decisions.md ADR-017). The third source with "watch" somewhere in its story and
    /// the third that means something different by it: `.watch` is a Garmin BLE summary card,
    /// `.appleWatch` is a recording the CleanJibe watch app handed over directly, and this one
    /// is a recording made by somebody else's app that we were allowed to read.
    ///
    /// It is the reason `SessionStore.writeNewSessionsToHealth` has a second exclusion: these
    /// workouts are *already in* Health — writing our own stub back would put two overlapping
    /// `.surfingSports` workouts on the same afternoon, and the rider would have imported a
    /// session in order to be shown it twice.
    case appleHealth = "applehealth"

    /// Whether a merged `session.importSource` names this source.
    ///
    /// The column is a `+`-joined set (`"applewatch+icu"` once a sync has seen the same
    /// session), so membership is a split-and-search rather than a comparison — and
    /// emphatically not a substring test, which would have `.watch` matching `"applewatch"`
    /// and quietly conflating a Garmin BLE card with an Apple Watch recording.
    public func isNamed(in importSource: String?) -> Bool {
        guard let importSource else { return false }
        return importSource.split(separator: "+").contains(Substring(rawValue))
    }
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

/// Recording bytes (FIT or GPX) → analysis → archive + `session` row + the schema-v2
/// child tables. Dedupe key per plan §3.3: start within ±60 s **and** duration within
/// ±60 s (the same session reaches us from intervals.icu, a GDPR bulk ZIP and AirDrop
/// with slightly different rounding).
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

    /// Ingests one recording — a FIT, or since engine 0.9.0 a GPX (`TrackParser` decides
    /// from the bytes). `requireWatersport` gates bulk imports (ZIP walking); a file the
    /// user picked by hand is always accepted, which is also the only way a GPX gets in:
    /// it carries no sport and no discipline, so nothing about it can pass a sport gate.
    ///
    /// `rider` is whose session this is — nil for the app owner's own, a friend's name for
    /// a FIT they shared. Only the hand-picked paths ever pass a name: an intervals.icu
    /// sync and a Garmin GDPR backfill are the rider's own account by construction, and a
    /// prompt on either would be asking a question that cannot have a second answer.
    ///
    /// `utcOffsetS` is what the *caller* knows about the session's timezone — intervals.icu
    /// states one per activity, and it is an exact answer where our own fallback is a
    /// guess. It is consulted only when the FIT itself cannot say (see
    /// `resolveUtcOffset`); a hand-picked file passes nil and simply has one fewer rung.
    @discardableResult
    public func ingest(fitData: Data, filename: String?, source: ImportSource,
                       icuActivityId: String? = nil,
                       rider: String? = nil,
                       utcOffsetS: Int? = nil,
                       requireWatersport: Bool = false) async throws -> IngestOutcome {
        // FIT or GPX, decided by the bytes (engine 0.9.0). Everything below this line is
        // written against `RawTrack` + `SourceCapabilities` and never asks which.
        let track = try TrackParser.parse(data: fitData)
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
        // What clock this session's times are drawn on, and how well we know it — see
        // `resolveUtcOffset`. It survives a provisional-row upgrade the same way the id
        // does: the FIT is a better source than anything the BLE card could imply, so it
        // overwrites rather than defers, and only an answer of "nothing" leaves the
        // existing value standing — the two fields together, so a kept offset never ends up
        // wearing this file's provenance.
        let resolved = Self.resolveUtcOffset(track: track, fallback: utcOffsetS)
        row.startUtcOffsetS = resolved.offset ?? existing?.startUtcOffsetS
        row.startUtcOffsetSource = resolved.offset == nil
            ? existing?.startUtcOffsetSource : resolved.source.rawValue
        // The card's "watch" tag survives the upgrade: the row really did reach the
        // library over BLE first, and that is worth being able to see afterwards.
        row.importSource = Self.merge(sources: existing?.importSource, adding: source)
        row.icuActivityId = icuActivityId ?? existing?.icuActivityId
        row.isExample = source == .example
        // A blank name means "mine": the prompt's text field can be left empty after the
        // rider has tapped "a friend's", and an empty string in the column would exclude
        // the session from every aggregate while showing an empty badge.
        row.rider = Self.riderName(rider) ?? existing?.rider
        // What the *rider* called it, and what he wanted said about it (schema v9). Carried
        // across the provisional-row upgrade for the same reason the gear and the id are:
        // the watch's card can sit in the library for an hour before the FIT syncs, that is
        // long enough to name the session, and a name that vanished when the recording
        // arrived would look exactly like the app losing it. Nothing here derives them —
        // they are the one pair of columns no import ever writes.
        row.customTitle = existing?.customTitle
        row.shareNote = existing?.shareNote
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
        if case .track = ZipWalker.classify(data) { gate = false } else { gate = true }
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

    /// Would a recording of this shape land on a session the library already holds?
    ///
    /// THE dedupe rule, asked *before* the bytes exist. The Apple Health import is the caller:
    /// its list can say "already imported" beside a workout without fetching and mapping the
    /// route first, which for a season of workouts is the difference between a list and a
    /// wait. It answers with the same `duplicate` the ingest path uses rather than with a
    /// second copy of the ±60 s rule, because two rules would eventually disagree and the
    /// screen would promise one thing while the import did another.
    ///
    /// It is a *preview*, not the decision: what a workout's route actually spans is a little
    /// shorter than what Health calls its duration, so a borderline answer here can differ
    /// from the one the ingest reaches. That is safe in the direction that matters — the
    /// ingest still dedupes — and the screen says "already imported" rather than promising it.
    public func holdsSession(startDate: Date, durationS: Double) async throws -> Bool {
        try await duplicate(startDate: startDate, durationS: durationS) != nil
    }

    public func icuActivityIds() async throws -> Set<String> {
        let ids = try await database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT icuActivityId FROM session WHERE icuActivityId IS NOT NULL")
        }
        return Set(ids)
    }

    /// Removes a session and remembers that it was removed.
    ///
    /// **The tombstone is the point** (`SessionTombstoneRow`). Without it the next
    /// intervals.icu sync sees an activity that is no longer in the library, concludes it is
    /// new, and downloads it again — which is deletion as a suggestion rather than as an
    /// instruction.
    ///
    /// **Everything gets one except the example**, and the exception is not laziness about
    /// provenance. The tombstone is *only ever consulted by the intervals.icu sync* (see
    /// `IcuSyncService.sync`), so it never stands between a rider and a file he picks by
    /// hand — and it therefore costs nothing on a session that only ever arrived by hand.
    /// What it does buy is the case that is otherwise silently broken: a session imported
    /// from a Garmin GDPR ZIP carries no intervals.icu id, but *is* on intervals.icu, so
    /// deleting it and syncing would import it straight back under an id the library has
    /// never seen. Tombstoning by the dedupe key as well as by the id is what catches that,
    /// and it can only catch it if the tombstone was written.
    ///
    /// The bundled example is left out because it is not the rider's session and cannot come
    /// back from intervals.icu anyway: it comes back from a button that says so
    /// (`importExample`), and counting it in "Previously deleted: 1" would be offering to
    /// restore something no sync was ever going to restore.
    ///
    /// `title` is what the library row was called — the archive directory goes with the row,
    /// so a name that is not written down now cannot be recovered later.
    public func delete(_ row: SessionRow, title: String? = nil) async throws {
        let id = row.id
        let stone = row.isExample ? nil : SessionTombstoneRow(row, title: title)
        _ = try await database.writer.write { db -> Void in
            try SessionRow.deleteOne(db, key: id)
            try stone?.insert(db)
        }
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
    /// Which clock this session's times are drawn on, best source first:
    ///
    /// 1. **The FIT's own `activity` message** — `local_timestamp - timestamp`, the offset
    ///    the watch was wearing at save time. Exact, DST included, present on every file in
    ///    the corpus.
    /// 2. **What the caller was told** — intervals.icu's `timezone` for the activity,
    ///    resolved at the session's own instant. Also exact; second only because it is
    ///    about the athlete's account rather than about this recording.
    /// 3. **A coarse guess from the first GPS fix** — `round(lon / 15°)` hours. Solar, not
    ///    civil: an hour out under DST, up to two inside a wide zone, blind to the
    ///    half-hour zones. It is here for sources that carry position and nothing else,
    ///    where "within an hour or two" beats an Italian afternoon shown as a Californian
    ///    morning.
    /// 4. **Nothing.** nil is stored, and `SessionRow.displayZone` falls back to the
    ///    device's zone — flagged by `hasKnownZone`, so a surface can say so rather than
    ///    passing the guess off as the session's.
    ///
    /// Since engine 0.9.1 it returns **which rung answered** alongside the number, because
    /// rungs 1–2 and rung 3 are the same `Int` and different facts: only an exact answer
    /// licenses a surface to state the session's clock, and rung 3's guess is an hour out
    /// under DST. "Nothing" is `.device` rather than a silence — a stored row can then tell
    /// a session that asked and got nowhere from one written before the question existed.
    static func resolveUtcOffset(track: RawTrack,
                                 fallback: Int?) -> (offset: Int?, source: UtcOffsetSource) {
        if let exact = track.startUtcOffsetS {
            return (exact, track.startUtcOffsetSource ?? .activity)
        }
        if let fallback { return (fallback, .icu) }
        guard let lon = track.samples.first(where: { $0.lon != nil })?.lon,
              let guess = FitSessionParser.coarseUtcOffsetS(lon) else { return (nil, .device) }
        return (guess, .longitude)
    }

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
