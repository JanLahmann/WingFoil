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

    /// Which map/chart overlay categories the legend chips are showing. One setting for
    /// the whole app rather than one per session: "I never want to see course changes" is
    /// a statement about the rider, not about a particular ride. Persisted on every
    /// change, so a relaunch comes back the way the map was left.
    var mapLayers: MapLayerVisibility = SessionStore.initialMapLayers() {
        didSet {
            guard mapLayers != oldValue else { return }
            MapLayerVisibilityStore.save(mapLayers, to: .standard)
        }
    }

    /// Whether the replay talks while it plays (`ReplayCommentary`). One setting for the
    /// whole app, like the legend chips and for the same reason: "I don't want a running
    /// commentary" is a statement about the rider, not about a particular ride.
    ///
    /// Default **on** — the feature is invisible until it speaks, and a rider who never
    /// finds it cannot decide he dislikes it — which is why it is stored as an object and
    /// not read with `bool(forKey:)`: that returns `false` both for "switched off" and for
    /// "never touched", and those are opposite answers here.
    var replayCommentary: Bool = SessionStore.storedReplayCommentary {
        didSet {
            guard replayCommentary != oldValue else { return }
            UserDefaults.standard.set(replayCommentary, forKey: Self.replayCommentaryKey)
        }
    }

    static let replayCommentaryKey = "replayCommentary"

    private static var storedReplayCommentary: Bool {
        UserDefaults.standard.object(forKey: replayCommentaryKey) as? Bool ?? true
    }

    /// `var` because one engine parameter is the rider's to set: `defaultTurnType`.
    var ingestor: SessionIngestor
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
        var ingestor = SessionIngestor(database: database!,
                                       archive: SessionArchive(root: archiveRoot))
        ingestor.windConfig.defaultTurnType = Self.storedDefaultTurnType
        self.ingestor = ingestor
        // The thumbnail cache only ever touches the archive, never the analyzer, so its
        // copy of the ingestor does not need the engine parameter kept in step.
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
        // The example is on loan, not ridden, and a friend's session is not the reader's
        // at all: neither may become "your last session" on the home screen, nor count
        // towards this week's foil time. Same rule as `LibraryStore.clause`, restated here
        // because the widget reads the in-memory list rather than going through SQL.
        let rows = sessions.filter { !$0.isExample && $0.rider == nil }
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

    // MARK: - Sharing the recording

    enum ShareError: Swift.Error, CustomStringConvertible {
        case notAWalkableFIT

        var description: String {
            switch self {
            case .notAWalkableFIT:
                "the archived file is not a plain FIT this app can rewrite safely"
            }
        }
    }

    /// The session's own recording, scrubbed of everything personal (`FitShareFilter`) and
    /// written to a temp file the share sheet can hand on.
    ///
    /// A *file*, not bytes in memory, because that is the only thing `ShareLink` can give a
    /// receiving app a filename for — and the filename is what a stranger sees in Files and
    /// in a mail attachment. It lands in a directory of its own under `tmp/`, which iOS is
    /// free to reap the moment the sheet is gone; nothing here is state the app keeps.
    ///
    /// Fails rather than falls back: a file we could not walk is a file we cannot promise
    /// is scrubbed, and sharing the original instead would be exactly the wrong recovery.
    func shareableFIT(for row: SessionRow,
                      includeAccelerometer: Bool) async throws -> (url: URL, bytes: Int) {
        let archive = ingestor.archive
        let name = FitShareFilter.filename(date: row.startDate,
                                           title: SessionDisplay.title(row))
        return try await Task.detached(priority: .userInitiated) {
            let original = try archive.originalData(for: row.id)
            guard let scrubbed = FitShareFilter.filter(original,
                                                       dropAccel: !includeAccelerometer)
            else { throw ShareError.notAWalkableFIT }
            let dir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("Share/\(row.id)", isDirectory: true)
            try? FileManager.default.removeItem(at: dir)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(name)
            try scrubbed.write(to: url, options: .atomic)
            return (url, scrubbed.count)
        }.value
    }

    // MARK: - Import

    /// Files waiting for the rider to say whose session they are.
    ///
    /// Held in memory rather than imported and corrected afterwards: attribution decides
    /// whether the session may touch Records, Trends and Apple Health, and a session that
    /// was briefly counted and then withdrawn would already have fired a personal-best
    /// celebration for somebody else's speed.
    struct PendingImport: Identifiable, Sendable {
        let id = UUID()
        let payloads: [DiscoveredFit]
        let source: ImportSource

        var filenames: [String] { payloads.map(\.name) }
    }

    /// Set while the "whose session is this?" prompt is up; `RootView` presents it.
    var pendingImport: PendingImport?

    /// Reads security-scoped picker URLs and imports them. `source` is only the tag the
    /// import log carries: a hand-picked FIT and a GDPR bulk export take the same path.
    func importFiles(urls: [URL], source: ImportSource, rider: String? = nil) async {
        guard let payloads = readPayloads(urls) else { return }
        await runImport(payloads, source: source, rider: rider)
    }

    /// A hand-picked file, or one tapped in another app — the two paths that can carry
    /// somebody else's recording, and the only two that ask.
    ///
    /// Everything else is the rider's own by construction: an intervals.icu sync reads
    /// *his* account, a GDPR export is *his* Garmin history, and the bundled example has
    /// its own flag. Asking there would be a question with one possible answer.
    func importPicked(urls: [URL]) async {
        guard let payloads = readPayloads(urls), !payloads.isEmpty else { return }
        pendingImport = PendingImport(payloads: payloads, source: .file)
    }

    /// The prompt's answer: nil (or blank) = mine, a name = a friend's.
    func confirmPendingImport(rider: String?) async {
        guard let pending = pendingImport else { return }
        pendingImport = nil
        await runImport(pending.payloads, source: pending.source,
                        rider: SessionIngestor.riderName(rider))
    }

    /// Dismissing the prompt imports nothing. There is no safe default for "whose is it"
    /// once the app can be handed a stranger's file.
    func cancelPendingImport() { pendingImport = nil }

    /// Friends already in the library, offered by the prompt so a second file from the
    /// same person lands on the same spelling as the first.
    func knownRiders() async -> [String] {
        (try? await library.riders()) ?? []
    }

    private func readPayloads(_ urls: [URL]) -> [DiscoveredFit]? {
        guard !urls.isEmpty else { return nil }
        var payloads: [DiscoveredFit] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                payloads.append(DiscoveredFit(name: url.lastPathComponent, data: data))
            } else {
                errorMessage = "Could not read \(url.lastPathComponent)"
            }
        }
        return payloads
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
            (try? Data(contentsOf: url)).map {
                DiscoveredFit(name: url.lastPathComponent, data: $0)
            }
        }
        await runImport(payloads, source: .fixtures)
        #endif
    }
    #endif

    // MARK: - Example session

    /// True once the bundled example is in the library — the setup card and Help both ask,
    /// so neither offers to load something that is already there.
    var hasExampleSession: Bool { sessions.contains { $0.isExample } }

    /// Imports the FIT bundled with the app (`ExampleSession`) through the ordinary path.
    ///
    /// Deliberately *not* `runImport`: an example must not celebrate a personal best and
    /// must not be pushed to Apple Health, because it is not the rider's session. Both of
    /// those are also true structurally — `library.records()` filters examples out — but a
    /// second import path that cannot reach them is cheaper than remembering why.
    func loadExampleSession() async {
        guard !isBusy else { return }
        isBusy = true
        status = "Loading the example session…"
        defer { isBusy = false }

        let ingestor = self.ingestor
        do {
            let outcome = try await Task.detached(priority: .userInitiated) {
                try await ingestor.importExample()
            }.value
            switch outcome {
            case .imported:
                status = "Example session loaded — open it to look around"
            case .duplicate(let row):
                // The example is a real recording, so the rider may already own it.
                status = row.isExample
                    ? "The example session is already in your library"
                    : "You already have this session — your own import kept"
            case .skipped:
                status = nil
            }
            await load()
        } catch {
            errorMessage = "Could not load the example session: \(error)"
        }
    }

    /// Files picker for the Garmin GDPR "Export Your Data" ZIP — the same code path as a
    /// hand-picked FIT, just tagged as a bulk backfill so the import log says so.
    func importBulk(urls: [URL]) async {
        await importFiles(urls: urls, source: .gdpr)
    }

    private func runImport(_ payloads: [DiscoveredFit], source: ImportSource,
                           rider: String? = nil) async {
        guard !payloads.isEmpty, !isBusy else { return }
        isBusy = true
        status = "Importing \(payloads.count) file\(payloads.count == 1 ? "" : "s")…"
        importProgress = ImportSummary()
        defer {
            isBusy = false
            importProgress = nil
        }

        let ingestor = self.ingestor
        let sendablePayloads = payloads
        let relay = ProgressRelay { [weak self] snapshot in
            Task { @MainActor in self?.importProgress = snapshot }
        }
        let summary = await Task.detached(priority: .userInitiated) {
            var total = ImportSummary()
            for payload in sendablePayloads {
                let base = total
                let one = await ingestor.ingestContainer(
                    data: payload.data, name: payload.name, source: source, rider: rider,
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

    // MARK: - Map legend

    /// Tapping a legend chip. Kept on the store rather than in a view's `@State` because
    /// the inline map, the full-screen map and the speed chart are three views of the same
    /// answer — a chip that only convinced the view it lives in would be a bug.
    func toggleMapLayer(_ layer: MapLayer) { mapLayers.toggle(layer) }

    func showAllMapLayers() { mapLayers.showAll() }

    private static func initialMapLayers() -> MapLayerVisibility {
        var stored = MapLayerVisibilityStore.load(from: .standard)
        #if DEBUG && targetEnvironment(simulator)
        // Screenshot hook, same family as `UI_TAB` / `UI_OPEN_SESSION`: `simctl` cannot tap
        // a chip, so `UI_HIDE_LAYERS=fellIn,courseChange` starts the app with those chips
        // off. It deliberately runs *after* the load and is never written back — the
        // override stages a screenshot, it does not edit the rider's preference.
        if let list = ProcessInfo.processInfo.environment["UI_HIDE_LAYERS"] {
            for token in list.split(separator: ",") {
                guard let layer = MapLayer(rawValue: token.trimmingCharacters(in: .whitespaces))
                else { continue }
                stored.setVisible(false, for: layer)
            }
        }
        #endif
        return stored
    }

    // MARK: - Analysis settings

    static let defaultTurnTypeKey = "defaultTurnType"

    /// The rider's declared turn habit (docs/algorithms.md "Default turn type"), the one
    /// engine parameter the app exposes. It is evidence for the wind's 180° ambiguity only,
    /// and only where the no-go cone cannot settle it — so on most sessions changing it
    /// changes nothing, which is the intended behaviour, not a broken setting.
    ///
    /// Stored analyses carry the *current* engine version, so they are not stale by version
    /// when this moves; it takes an explicit re-analysis to apply it to the existing library
    /// (`rerunAnalysis`). New imports pick it up straight away.
    var defaultTurnType: DefaultTurnType {
        get { Self.storedDefaultTurnType }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.defaultTurnTypeKey)
            ingestor.windConfig.defaultTurnType = newValue
        }
    }

    private static var storedDefaultTurnType: DefaultTurnType {
        UserDefaults.standard.string(forKey: defaultTurnTypeKey)
            .flatMap(DefaultTurnType.init(rawValue:)) ?? WindConfig().defaultTurnType
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
        // A friend's session is not a workout the reader did. Health is the one place
        // where getting that wrong leaves a mark outside this app.
        let pending = sessions.filter { !exported.contains($0.id) && $0.rider == nil }
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
            setProblem(IcuProblem(kind: .noKey))
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
            // A sync can succeed and still leave the library empty (Garmin not connected
            // in intervals.icu yet). That is a cause the setup card can name, not a crash.
            setProblem(IcuDiagnosis.describe(summary))
            if !summary.failed.isEmpty { errorMessage = summary.failed.joined(separator: "\n") }
            lastSyncDate = Date()
        } catch {
            let problem = IcuDiagnosis.describe(error)
            setProblem(problem)
            status = nil
            // On an empty library the setup card already carries this cause *and* its fix,
            // in place. A modal on top of it is the same sentence twice.
            if !sessions.isEmpty { errorMessage = problem.alertText }
        }
        await load()
    }

    // MARK: - New-session notifications

    /// Off by default. Turning it on is what asks iOS for permission and what starts the
    /// background refresh task; turning it off cancels both (`ActivityNotifier`).
    var notifyOnNewActivities: Bool {
        get { UserDefaults.standard.bool(forKey: ActivityNotifier.enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: ActivityNotifier.enabledKey)
            if newValue {
                Task { await enableActivityNotifications() }
            } else {
                ActivityNotifier.shared.disable()
            }
        }
    }

    // MARK: - The one-time offer

    /// True while the "shall I tell you when a session lands?" alert is up. `RootView`
    /// presents it; the decision to raise it is `NewActivityPrompt`, in the kit.
    private(set) var isAskingAboutNewActivities = false

    /// Set by whichever screen currently owns a sheet, so the offer can wait for a clear
    /// screen. Reported rather than guessed: the sheets are `LibraryView`'s state, and the
    /// alert is presented two levels above it.
    var isPresentingSheet = false

    /// Anything the rider is already reading or answering. The offer is a suggestion, and
    /// a suggestion that lands on top of a question is a nuisance — `isCheckingKey`
    /// included, so the offer arrives *after* "Connected" rather than over the spinner.
    private var isPresentingSomething: Bool {
        isPresentingSheet || pendingImport != nil || errorMessage != nil || isCheckingKey
    }

    /// Asked at every plausible moment — launch, foreground, a key that was just proved, a
    /// sheet that just closed — and answered by the pure predicate, which says yes at most
    /// once per install and only once the key exists.
    func askAboutNewActivitiesIfNeeded() {
        guard NewActivityPrompt.shouldAsk(
            hasKey: !apiKey.isEmpty,
            isEnabled: notifyOnNewActivities,
            hasAsked: UserDefaults.standard.bool(forKey: ActivityNotifier.promptedKey),
            isPresenting: isPresentingSomething)
        else { return }
        // Written down as the alert goes up rather than as it is answered: a question the
        // rider walked away from — app swiped away, phone locked — was still asked, and
        // asking it again on every launch until he taps something is exactly the nagging
        // this feature must not become.
        UserDefaults.standard.set(true, forKey: ActivityNotifier.promptedKey)
        isAskingAboutNewActivities = true
    }

    /// "Enable" — deliberately nothing but the toggle the Settings screen writes to, so the
    /// permission request, the fresh mark and the first background request all happen on
    /// the one code path. A second enable path would be a second thing to keep correct.
    func acceptNewActivityNotifications() {
        isAskingAboutNewActivities = false
        notifyOnNewActivities = true
    }

    /// "Not now", and the same call the alert's own dismissal makes. The offer is spent
    /// (the flag was written when it appeared); the Settings toggle is the way in from here.
    func declineNewActivityNotifications() {
        isAskingAboutNewActivities = false
    }

    private func enableActivityNotifications() async {
        guard await ActivityNotifier.shared.requestAuthorization() else {
            UserDefaults.standard.set(false, forKey: ActivityNotifier.enabledKey)
            errorMessage = "iOS did not grant permission to send notifications. "
                + "Turn them on in Settings → Notifications → WingFoil and try again."
            return
        }
        ActivityNotifier.shared.enable()
        status = "You will be told when a new session appears on intervals.icu"
    }

    /// Set by a notification tap; the library pushes this session and clears it.
    var pendingSessionID: String?

    /// The tap's destination. The background wake usually imported the session already, in
    /// which case this is a `load` and a push; when it did not — no time, no network, a
    /// FIT Garmin had not finished uploading — the ordinary sync runs first, which is the
    /// same path the Import screen's button takes.
    func openSession(icuActivityId: String) async {
        await load()
        if let row = sessions.first(where: { $0.icuActivityId == icuActivityId }) {
            pendingSessionID = row.id
            return
        }
        await syncFromIntervals()
        if let row = sessions.first(where: { $0.icuActivityId == icuActivityId }) {
            pendingSessionID = row.id
        } else {
            status = "That session is not on intervals.icu yet — pull to sync"
        }
    }

    /// Picks up what a background wake imported while the app was away. Cheap and silent:
    /// on the ordinary foreground, where nothing happened, it does nothing at all.
    func absorbBackgroundImports() async {
        guard ActivityNotifier.consumePendingImport() else { return }
        await load()
        await refreshPersonalBests(celebrate: false)
        await writeNewSessionsToHealth()
    }

    // MARK: - Onboarding

    /// What an empty library should offer: the four-step setup, the cause of the last
    /// failure, or nothing at all. The decision itself is a pure function in the kit.
    var onboardingState: IcuOnboardingState {
        IcuOnboarding.state(sessionCount: sessions.count,
                            hasKey: !apiKey.isEmpty,
                            lastProblem: lastSyncProblem)
    }

    /// The mapped cause of the last sync or key check, kept across launches so the setup
    /// card can still say *why* nothing arrived.
    private(set) var lastSyncProblem: IcuProblem? = SessionStore.loadProblem()

    /// Result of the last "save & check" — the inline line under the key field.
    private(set) var keyCheck: IcuKeyCheck?
    private(set) var isCheckingKey = false

    private static let problemKey = "lastIcuProblem.v1"

    private static func loadProblem() -> IcuProblem? {
        guard let data = UserDefaults.standard.data(forKey: problemKey) else { return nil }
        return try? JSONDecoder().decode(IcuProblem.self, from: data)
    }

    private func setProblem(_ problem: IcuProblem?) {
        lastSyncProblem = problem
        if let problem, let data = try? JSONEncoder().encode(problem) {
            UserDefaults.standard.set(data, forKey: Self.problemKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.problemKey)
        }
    }

    /// Saves the key and immediately proves whether it works, because "saved" and "works"
    /// are different facts and only one of them is worth telling the rider.
    func saveAndCheckApiKey(_ key: String) async {
        setApiKey(key)
        await checkApiKey()
    }

    /// One list call, no downloads. The key itself never leaves the keychain wrapper and
    /// is never logged — only the *outcome* is ever put on screen.
    func checkApiKey() async {
        let key = apiKey
        guard !key.isEmpty else {
            keyCheck = .failure(IcuProblem(kind: .noKey))
            setProblem(nil)                    // no key is a missing step, not a failure
            return
        }
        guard !isCheckingKey else { return }
        isCheckingKey = true
        status = "Checking the key with intervals.icu…"
        let result = await Task.detached(priority: .userInitiated) {
            await IcuDiagnosis.check(IcuClient(apiKey: key))
        }.value
        isCheckingKey = false
        keyCheck = result
        switch result {
        case .success(let report):
            status = report.message
            setProblem(report.caveat)
            // The key works and there is something to fetch: do it now rather than making
            // the first-run user discover pull-to-refresh.
            if report.watersports > 0, sessions.isEmpty { await syncFromIntervals() }
        case .failure(let problem):
            status = nil
            setProblem(problem)
        }
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

    // MARK: - Companion link (phase 5)

    /// The watch link. Concrete rather than `any CompanionLink` because the app is also
    /// the only place that does the two things the protocol deliberately leaves out —
    /// sending the rider to Garmin Connect to pick a watch, and reading the answer back
    /// off a URL. Everything else goes through the protocol, which is what keeps the
    /// payload rules testable in WingFoilKit with no framework in sight.
    let companion = ConnectIQCompanionLink()
    private(set) var companionState: CompanionLinkState = .noDevice
    /// When the last card arrived. The settings row shows it, because "it says ready" and
    /// "something has actually come through" are different facts.
    var lastCardAt: Date? {
        get { UserDefaults.standard.object(forKey: "lastCompanionCard") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastCompanionCard") }
    }

    /// The wind the rider last pushed, remembered so the next push starts where the last
    /// one left off (the wind at a spot rarely changes by 180° between sessions).
    var windToSend: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: "windToSend") as? Int
            return stored ?? 225
        }
        set { UserDefaults.standard.set(newValue, forKey: "windToSend") }
    }

    /// Runs for the life of the app: one `for await` over every card the watch sends.
    /// Cards are already validated when they get here — an invalid one never leaves the
    /// adapter — so the only thing that can fail is the database.
    func watchForCompanionCards() async {
        refreshCompanionState()
        for await card in companion.summaries() {
            await receive(card)
        }
    }

    private func receive(_ card: CompanionSummary) async {
        do {
            switch try await ingestor.ingest(card: card) {
            case .provisional:
                status = "Session received from your watch — the recording follows later"
            case .refreshed:
                status = "Updated from your watch"
            case .alreadyAnalysed:
                // The FIT beat the card. Nothing changed that is worth a line of status.
                break
            }
            lastCardAt = Date()
            await load()
        } catch {
            errorMessage = "Could not store the session your watch sent: \(error)"
        }
    }

    func refreshCompanionState() {
        companion.refresh()
        companionState = companion.state
    }

    /// Hands over to Garmin Connect; the answer comes back through `handleCompanionURL`.
    func chooseWatch() {
        companion.chooseDevice()
    }

    func forgetWatch() {
        companion.forgetDevice()
        companionState = companion.state
    }

    /// True when the URL was Garmin Connect returning the rider's device choice — so the
    /// app entry point knows not to try importing it as a FIT.
    func handleCompanionURL(_ url: URL) -> Bool {
        guard companion.handle(url: url) else { return false }
        companionState = companion.state
        status = companionState.headline
        return true
    }

    /// Manual by decision (docs/decisions.md ADR-013): an automatic push needs this app
    /// awake at the moment a session starts, and a wind axis that lands mid-session
    /// relabels every turn before it. Automatic can come once the link is proven on water.
    func sendWindToWatch(_ degreesFrom: Int) async {
        do {
            try await companion.sendWind(degreesFrom: degreesFrom)
            windToSend = degreesFrom
            status = degreesFrom == CompanionWind.clear
                ? "Wind direction cleared on the watch"
                : "Sent \(degreesFrom)° to the watch"
        } catch let error as CompanionLinkError {
            errorMessage = error.riderMessage
        } catch {
            errorMessage = "Could not send the wind direction: \(error)"
        }
        refreshCompanionState()
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
        keyCheck = nil                          // a new key has not been proven yet
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

    #if DEBUG
    /// Headless-driving hook (same family as `UI_IMPORT_FIXTURES` / `UI_TAB`): `UI_RESET=1`
    /// puts the app back into its fresh-install state — no key, no sessions, no stored
    /// sync history — so the first-run screens can be screenshotted without uninstalling.
    ///
    /// Simulator only, and it runs *before* the store exists, because the store reads the
    /// keychain in a property initialiser.
    static func resetIfRequested() {
        #if targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["UI_RESET"] == "1" else { return }
        Keychain.remove(Keychain.icuApiKey)
        for key in ["lastIcuSync", problemKey, pbSnapshotKey, "healthExported",
                    "healthWriteEnabled", defaultTurnTypeKey,
                    ActivityNotifier.enabledKey, ActivityNotifier.markKey,
                    ActivityNotifier.pendingImportKey, ActivityNotifier.promptedKey,
                    MapLayerVisibilityStore.defaultsKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        let fm = FileManager.default
        for url in [try? AppPaths.databaseURL(), try? AppPaths.sessionsRoot()] {
            if let url { try? fm.removeItem(at: url) }
        }
        // `UI_ICU_KEY=…` seeds a key through the real keychain path afterwards, which is
        // how the "key stored, sync failed" card gets driven without typing.
        if let seed = ProcessInfo.processInfo.environment["UI_ICU_KEY"], !seed.isEmpty {
            Keychain.set(seed, for: Keychain.icuApiKey)
        }
        // GRDB's WAL and shared memory outlive the main file; a stale WAL would restore
        // the very rows this hook exists to remove.
        if let db = try? AppPaths.databaseURL() {
            for suffix in ["-wal", "-shm"] {
                try? fm.removeItem(at: URL(fileURLWithPath: db.path + suffix))
            }
        }
        #endif
    }
    #endif
}
