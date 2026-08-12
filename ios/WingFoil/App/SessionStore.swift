import Foundation
import Observation
import WingFoilKit

/// The app's single source of truth: the GRDB session index plus the immutable FIT
/// archive (plan §3.1). Everything analytical lives in WingFoilKit — this type only
/// orchestrates, keeps the UI state, and hops heavy work off the main actor.
@MainActor
@Observable
final class SessionStore {

    struct StorageStats: Sendable, Equatable {
        var sessionCount = 0
        var archiveBytes: Int64 = 0
        var databaseBytes: Int64 = 0

        var totalBytes: Int64 { archiveBytes + databaseBytes }
    }

    private(set) var sessions: [SessionRow] = []
    private(set) var isBusy = false
    private(set) var status: String?
    private(set) var storage = StorageStats()
    /// Set when a background job failed; the UI shows it as a dismissible banner.
    var errorMessage: String?

    /// Live counters of a running bulk import (nil when nothing is importing).
    private(set) var importProgress: ImportSummary?
    /// Places and kit, cached for the pickers and the aggregate screens.
    private(set) var spots: [SpotAggregate] = []
    private(set) var gearAggregates: [GearAggregate] = []
    /// Bumped whenever the derived tables change, so aggregate screens can re-query.
    private(set) var libraryGeneration = 0

    /// All-time records that were beaten by the most recent import. Consumed (and cleared)
    /// by the Records screen, which is where the celebration belongs.
    private(set) var celebration: [NewPersonalBest] = []

    let ingestor: SessionIngestor
    /// Lazy track thumbnails for the library rows.
    let thumbnails: ThumbnailStore
    private let databaseURL: URL?

    /// Aggregate reads (records, trends, gear, spots) all go through here.
    var library: LibraryStore { ingestor.library }

    // MARK: - Setup

    init() {
        var url: URL?
        var problem: String?
        var database: AppDatabase?
        do {
            let dbURL = try AppPaths.databaseURL()
            url = dbURL
            database = try AppDatabase.onDisk(at: dbURL)
        } catch {
            problem = "Could not open the library database (\(error)). Running in memory."
        }
        if database == nil {
            guard let memory = try? AppDatabase.inMemory() else {
                preconditionFailure("SQLite unavailable — cannot start")
            }
            database = memory
        }
        let archiveRoot = (try? AppPaths.sessionsRoot())
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Sessions")
        databaseURL = url
        let ingestor = SessionIngestor(database: database!,
                                       archive: SessionArchive(root: archiveRoot))
        self.ingestor = ingestor
        thumbnails = ThumbnailStore(ingestor: ingestor)
        errorMessage = problem
    }

    // MARK: - Library

    func load() async {
        do {
            sessions = try await ingestor.allSessions()
            spots = try await library.spots()
            gearAggregates = try await library.gearAggregates()
            libraryGeneration += 1
            await refreshStorage()
            await publishWidgetSnapshot()
            // Seed the baseline once, so the first import after installing does not
            // "beat" an empty library nine times over.
            if storedPersonalBests == nil { await refreshPersonalBests(celebrate: false) }
        } catch {
            errorMessage = "Could not read the library: \(error)"
        }
    }

    // MARK: - Personal bests

    private static let pbSnapshotKey = "personalBestSnapshot.v1"

    private var storedPersonalBests: PersonalBestSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: Self.pbSnapshotKey) else { return nil }
        return try? JSONDecoder().decode(PersonalBestSnapshot.self, from: data)
    }

    private func storePersonalBests(_ snapshot: PersonalBestSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.pbSnapshotKey)
    }

    /// Re-reads the all-time records and, when asked, reports what the import just beat.
    ///
    /// `celebrate` is false everywhere except right after an import: the snapshot has to be
    /// kept current as sessions are deleted or re-analyzed too, and a *drop* in a record is
    /// obviously not a personal best.
    private func refreshPersonalBests(celebrate: Bool) async {
        guard let records = try? await library.records() else { return }
        let previous = storedPersonalBests
        if celebrate, let previous {
            let found = PersonalBestDetector.improvements(previous: previous, current: records)
            if !found.isEmpty { celebration = found }
        }
        storePersonalBests(PersonalBestSnapshot(records: records))
    }

    /// Called by the Records screen once it has shown the burst.
    func clearCelebration() { celebration = [] }

    // MARK: - Widgets

    /// Publishes the home-screen widget snapshot. Best effort by design: without the app
    /// group entitlement it lands in the app's own container instead, and the widget shows
    /// its placeholder (see `WidgetSnapshotStore`).
    private func publishWidgetSnapshot() async {
        let rows = sessions
        let snapshot = WidgetSnapshot.make(sessions: rows) { SessionDisplay.title($0) }
        await Task.detached(priority: .utility) {
            WidgetSnapshotStore.write(snapshot)
            WidgetRefresher.reloadTimelines()
        }.value
    }

    /// Brings every summary row up to the current engine (plan §3.3 lazy re-analysis).
    /// The aggregate screens depend on it: one stale row silently bends a whole trend
    /// line, and after a schema migration *every* row is stale.
    func refreshDerived() async {
        guard !isBusy else { return }
        let ingestor = self.ingestor
        let stale = (try? await ingestor.reanalyzeStale()) ?? 0
        guard stale > 0 else { return }
        status = "Re-derived \(stale) session\(stale == 1 ? "" : "s") "
            + "for engine \(AnalysisEngine.version)"
        await load()
        await nameSpots()
    }

    /// Fills in `Spot N` placeholders from the reverse geocoder. Best effort by design:
    /// offline or throttled, the placeholders simply stay (and stay renamable).
    func nameSpots() async {
        guard spots.contains(where: { $0.spot.autoNamed }) else { return }
        let library = self.library
        try? await library.nameAutoSpots(using: SpotNamer.shared.resolver)
        spots = (try? await library.spots()) ?? spots
    }

    func renameSpot(_ spot: SpotRow, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? await library.renameSpot(id: spot.id, to: trimmed)
        await load()
    }

    func reclusterSpots() async {
        do {
            try await library.recluster()
            await load()
            status = "Re-clustered into \(spots.count) spot\(spots.count == 1 ? "" : "s")"
        } catch {
            errorMessage = "Could not re-cluster spots: \(error)"
        }
    }

    func spot(id: String?) -> SpotRow? {
        guard let id else { return nil }
        return spots.first { $0.spot.id == id }?.spot
    }

    // MARK: - Gear

    func saveGear(_ gear: GearRow) async {
        do {
            try await library.saveGear(gear)
            await load()
        } catch {
            errorMessage = "Could not save gear: \(error)"
        }
    }

    func deleteGear(_ gear: GearRow) async {
        try? await library.deleteGear(id: gear.id)
        await load()
    }

    func assignGear(sessionID: String, kind: GearKind, gearID: String?) async {
        try? await library.assignGear(sessionId: sessionID, kind: kind, gearId: gearID)
        libraryGeneration += 1
        gearAggregates = (try? await library.gearAggregates()) ?? gearAggregates
    }

    func session(id: String) -> SessionRow? {
        sessions.first { $0.id == id }
    }

    func delete(_ row: SessionRow) async {
        do {
            try await ingestor.delete(row)
            thumbnails.invalidate(row.id)
            await load()
            await refreshPersonalBests(celebrate: false)
        } catch {
            errorMessage = "Delete failed: \(error)"
        }
    }

    func refreshStorage() async {
        let ingestor = self.ingestor
        let dbURL = databaseURL
        let count = sessions.count
        storage = await Task.detached(priority: .utility) {
            var stats = StorageStats()
            stats.sessionCount = count
            stats.archiveBytes = ingestor.archive.diskUsageBytes()
            if let dbURL,
               let size = try? dbURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                stats.databaseBytes = Int64(size)
            }
            return stats
        }.value
    }

    // MARK: - Session detail

    /// Map/chart geometry for one session. Re-parses the archived FIT (samples are never
    /// stored in the DB) and re-analyzes lazily when `analysis.json` is missing or stale.
    func detail(for row: SessionRow) async throws -> SessionDetail {
        let ingestor = self.ingestor
        let detail = try await Task.detached(priority: .userInitiated) {
            let analysis = try await ingestor.analysis(for: row)
            let track = try ingestor.rawTrack(for: row)
            return SessionDetail(row: row, analysis: analysis, track: track)
        }.value
        if row.engineVersion != detail.analysis.engineVersion {
            await load()                       // lazy re-analysis rewrote the summary row
        }
        return detail
    }

    // MARK: - Import

    /// Reads security-scoped picker URLs and imports them. `source` is only the tag the
    /// import log carries: a hand-picked FIT and a GDPR bulk export take the same path.
    func importFiles(urls: [URL], source: ImportSource) async {
        guard !urls.isEmpty else { return }
        var payloads: [(name: String, data: Data)] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                payloads.append((url.lastPathComponent, data))
            } else {
                errorMessage = "Could not read \(url.lastPathComponent)"
            }
        }
        await runImport(payloads, source: source)
    }

    func importPicked(urls: [URL]) async {
        await importFiles(urls: urls, source: .file)
    }

    #if DEBUG
    /// Simulator-only convenience: pull Jan's corpus straight off the host filesystem so
    /// the library is populated without an intervals.icu round-trip.
    static let fixturesPath = "/Users/majl/GitHub/WingFoil/fixtures/sessions"

    var fixturesAvailable: Bool {
        #if targetEnvironment(simulator)
        FileManager.default.fileExists(atPath: Self.fixturesPath)
        #else
        false
        #endif
    }

    func importFixtures() async {
        #if targetEnvironment(simulator)
        let root = URL(fileURLWithPath: Self.fixturesPath)
        let urls = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "fit" } ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !urls.isEmpty else {
            errorMessage = "No fixtures at \(Self.fixturesPath)"
            return
        }
        let payloads = urls.compactMap { url in
            (try? Data(contentsOf: url)).map { (url.lastPathComponent, $0) }
        }
        await runImport(payloads, source: .fixtures)
        #endif
    }
    #endif

    /// Files picker for the Garmin GDPR "Export Your Data" ZIP — the same code path as a
    /// hand-picked FIT, just tagged as a bulk backfill so the import log says so.
    func importBulk(urls: [URL]) async {
        await importFiles(urls: urls, source: .gdpr)
    }

    private func runImport(_ payloads: [(name: String, data: Data)], source: ImportSource) async {
        guard !payloads.isEmpty, !isBusy else { return }
        isBusy = true
        status = "Importing \(payloads.count) file\(payloads.count == 1 ? "" : "s")…"
        importProgress = ImportSummary()
        defer {
            isBusy = false
            importProgress = nil
        }

        let ingestor = self.ingestor
        let sendablePayloads = payloads.map { DiscoveredFit(name: $0.name, data: $0.data) }
        let relay = ProgressRelay { [weak self] snapshot in
            Task { @MainActor in self?.importProgress = snapshot }
        }
        let summary = await Task.detached(priority: .userInitiated) {
            var total = ImportSummary()
            for payload in sendablePayloads {
                let base = total
                let one = await ingestor.ingestContainer(
                    data: payload.data, name: payload.name, source: source,
                    progress: { partial in
                        var merged = base
                        merged.absorb(partial)
                        relay.send(merged)
                    })
                total.absorb(one)
            }
            return total
        }.value

        status = summary.shortDescription
        if !summary.failed.isEmpty { errorMessage = summary.failed.joined(separator: "\n") }
        await load()
        await refreshPersonalBests(celebrate: true)
        await writeNewSessionsToHealth()
    }

    /// Bridges the ingestor's `@Sendable` progress closure back to the main actor.
    private final class ProgressRelay: @unchecked Sendable {
        private let sink: @Sendable (ImportSummary) -> Void

        init(_ sink: @escaping @Sendable (ImportSummary) -> Void) { self.sink = sink }

        func send(_ summary: ImportSummary) { sink(summary) }
    }

    // MARK: - Apple Health (opt-in, write-only)

    /// Off by default (plan phase 4: "optional Apple Health write"). Nothing is ever read
    /// back from HealthKit — Garmin's own sync already owns that direction.
    var healthWriteEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "healthWriteEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "healthWriteEnabled")
            if newValue { Task { await enableHealthWriting() } }
        }
    }

    private func enableHealthWriting() async {
        guard await HealthWriter.shared.requestAuthorization() else {
            errorMessage = "Apple Health did not grant permission to add workouts."
            UserDefaults.standard.set(false, forKey: "healthWriteEnabled")
            return
        }
        await writeNewSessionsToHealth()
    }

    /// Writes every session that has not been exported yet. Ids of exported sessions live
    /// in UserDefaults, so a Health deletion is not silently "re-synced" on every launch.
    func writeNewSessionsToHealth() async {
        guard healthWriteEnabled else { return }
        var exported = Set(UserDefaults.standard.stringArray(forKey: "healthExported") ?? [])
        let pending = sessions.filter { !exported.contains($0.id) }
        guard !pending.isEmpty else { return }
        var written = 0
        for row in pending {
            if await HealthWriter.shared.write(row) {
                exported.insert(row.id)
                written += 1
            }
        }
        UserDefaults.standard.set(Array(exported), forKey: "healthExported")
        if written > 0 {
            status = "Added \(written) workout\(written == 1 ? "" : "s") to Apple Health"
        }
    }

    // MARK: - intervals.icu

    func syncFromIntervals() async {
        guard !isBusy else { return }
        let key = apiKey
        guard !key.isEmpty else {
            status = "Add your intervals.icu API key in Settings"
            return
        }
        isBusy = true
        status = "Contacting intervals.icu…"
        defer { isBusy = false }

        let ingestor = self.ingestor
        let oldest = IcuSyncService.defaultOldest()
        do {
            let summary = try await Task.detached(priority: .userInitiated) {
                let service = IcuSyncService(client: IcuClient(apiKey: key), ingestor: ingestor)
                return try await service.sync(oldest: oldest)
            }.value
            status = summary.shortDescription
            if !summary.failed.isEmpty { errorMessage = summary.failed.joined(separator: "\n") }
            lastSyncDate = Date()
        } catch {
            status = nil
            errorMessage = "intervals.icu sync failed: \(error)"
        }
        await load()
    }

    // MARK: - Analysis maintenance

    /// Drops every cached `analysis.json`; each session recomputes (and rewrites its
    /// summary row) the next time it is opened. Same path an engine-version bump takes.
    func rerunAnalysis() async {
        guard !isBusy else { return }
        isBusy = true
        status = "Clearing cached analyses…"
        defer { isBusy = false }
        let ingestor = self.ingestor
        let rows = sessions
        await Task.detached(priority: .userInitiated) {
            ingestor.dropAllAnalyses()
            for row in rows { _ = try? await ingestor.reanalyze(row) }
        }.value
        status = "Re-analyzed \(rows.count) session\(rows.count == 1 ? "" : "s") "
            + "with engine \(AnalysisEngine.version)"
        // Which parts of a track were flown can change with the engine, so the cached
        // outlines are stale by construction.
        for row in rows { thumbnails.invalidate(row.id) }
        await load()
        await refreshPersonalBests(celebrate: false)
    }

    // MARK: - Credentials

    /// Keychain-backed, mirrored into observable state so SwiftUI tracks changes. In DEBUG
    /// a scheme environment variable wins, so the simulator can sync without typing
    /// (never a file outside the sandbox).
    private(set) var apiKey = SessionStore.loadApiKey()

    var apiKeyIsInjected: Bool {
        #if DEBUG
        !(ProcessInfo.processInfo.environment["ICU_API_KEY"] ?? "").isEmpty
        #else
        false
        #endif
    }

    func setApiKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.remove(Keychain.icuApiKey)
            status = "API key removed"
        } else if Keychain.set(trimmed, for: Keychain.icuApiKey) {
            status = "API key saved to the keychain"
        } else {
            errorMessage = "Could not write the API key to the keychain"
        }
        apiKey = Self.loadApiKey()
    }

    private static func loadApiKey() -> String {
        #if DEBUG
        if let injected = ProcessInfo.processInfo.environment["ICU_API_KEY"], !injected.isEmpty {
            return injected
        }
        #endif
        return Keychain.string(for: Keychain.icuApiKey) ?? ""
    }

    var lastSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: "lastIcuSync") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastIcuSync") }
    }
}
