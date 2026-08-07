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

    let ingestor: SessionIngestor
    private let databaseURL: URL?

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
        ingestor = SessionIngestor(database: database!, archive: SessionArchive(root: archiveRoot))
        errorMessage = problem
    }

    // MARK: - Library

    func load() async {
        do {
            sessions = try await ingestor.allSessions()
            await refreshStorage()
        } catch {
            errorMessage = "Could not read the library: \(error)"
        }
    }

    func session(id: String) -> SessionRow? {
        sessions.first { $0.id == id }
    }

    func delete(_ row: SessionRow) async {
        do {
            try await ingestor.delete(row)
            await load()
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

    func importPicked(urls: [URL]) async {
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
        await runImport(payloads, source: .file)
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

    private func runImport(_ payloads: [(name: String, data: Data)], source: ImportSource) async {
        guard !payloads.isEmpty, !isBusy else { return }
        isBusy = true
        status = "Importing \(payloads.count) file\(payloads.count == 1 ? "" : "s")…"
        defer { isBusy = false }

        let ingestor = self.ingestor
        let sendablePayloads = payloads.map { DiscoveredFit(name: $0.name, data: $0.data) }
        let summary = await Task.detached(priority: .userInitiated) {
            var total = ImportSummary()
            for payload in sendablePayloads {
                let one = await ingestor.ingestContainer(data: payload.data, name: payload.name,
                                                         source: source)
                total.imported += one.imported
                total.duplicates += one.duplicates
                total.skipped += one.skipped
                total.failed.append(contentsOf: one.failed)
            }
            return total
        }.value

        status = summary.shortDescription
        if !summary.failed.isEmpty { errorMessage = summary.failed.joined(separator: "\n") }
        await load()
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
        await load()
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
