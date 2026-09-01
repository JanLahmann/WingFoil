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
    /// How many sessions the rider has deleted and the sync is therefore refusing to bring
    /// back. Zero on almost every install; the Settings section that offers them back only
    /// exists when it is not.
    private(set) var deletedSessionCount = 0
    /// Places and kit, cached for the pickers and the aggregate screens.
    private(set) var spots: [SpotAggregate] = []
    private(set) var gearAggregates: [GearAggregate] = []
    /// Bumped whenever the derived tables change, so aggregate screens can re-query.
    private(set) var libraryGeneration = 0
    /// False until the first successful read of the session index. "No sessions" and "not
    /// read yet" look identical in `sessions`, and exactly one first-run decision turns on
    /// telling them apart — see `showWelcomeIfNeeded`.
    private(set) var hasLoadedLibrary = false

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

    /// What the maps are drawn **on** (`MapStyleChoice`). One setting for the whole app, like
    /// the legend chips and for the same reason — "I want to see the water" is a statement
    /// about the rider — and it reaches all four map surfaces: the inline map, the full-screen
    /// map, the Turns tab's map and the cinema replay. Persisted on every change.
    var mapStyle: MapStyleChoice = SessionStore.initialMapStyle() {
        didSet {
            guard mapStyle != oldValue else { return }
            MapStyleStore.save(mapStyle, to: .standard)
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

    /// How long the last clip was asked to be (`ReplayClipLength`). Remembered because the
    /// second clip of an afternoon is nearly always the same shape as the first, and because
    /// a rider who has decided that 10 s is what his friends actually watch should not have
    /// to re-decide it on every session.
    ///
    /// 25 s is the default: long enough to hold a jibe or two at a speed that still reads,
    /// short enough to be watched to the end in a chat.
    var replayClipLength: ReplayClipLength = SessionStore.storedReplayClipLength {
        didSet {
            guard replayClipLength != oldValue else { return }
            UserDefaults.standard.set(replayClipLength.rawValue, forKey: Self.replayLengthKey)
        }
    }

    static let replayLengthKey = "replayClipLength.v1"

    private static var storedReplayClipLength: ReplayClipLength {
        UserDefaults.standard.string(forKey: replayLengthKey)
            .flatMap(ReplayClipLength.init(rawValue:)) ?? .s25
    }

    /// What shape the last clip was recorded in (`ReplayFraming`). Remembered for the same
    /// reason the length is: a rider who posts to one place is posting to it again.
    ///
    /// **Full screen is the default**, and deliberately the conservative one: it is the only
    /// framing that needs no export, it is what every clip made before the picker existed
    /// looks like, and it is what a failed crop falls back to.
    var replayFraming: ReplayFraming = SessionStore.storedReplayFraming {
        didSet {
            guard replayFraming != oldValue else { return }
            UserDefaults.standard.set(replayFraming.rawValue, forKey: Self.replayFramingKey)
        }
    }

    static let replayFramingKey = "replayFraming.v1"

    private static var storedReplayFraming: ReplayFraming {
        UserDefaults.standard.string(forKey: replayFramingKey)
            .flatMap(ReplayFraming.init(rawValue:)) ?? .fullScreen
    }

    /// The last track a clip was recorded with (`ReplayMusicTrack`), or nil for none.
    ///
    /// Remembered unlike the other two: the sheet does **not** open on it. Music is a louder
    /// decision than a length — a clip that quietly arrived with a song under it because the
    /// last one had one is the kind of surprise that gets found out in somebody else's chat —
    /// so the sheet opens silent and offers the remembered track by name instead.
    ///
    /// Setting it sweeps every other copy out of the container (`ReplayMusicStore.keepOnly`),
    /// which is what keeps a rider who has tried six songs from carrying six of them around.
    var replayMusic: ReplayMusicTrack? = SessionStore.storedReplayMusic {
        didSet {
            guard replayMusic != oldValue else { return }
            ReplayMusicStore.keepOnly(replayMusic)
            let data = replayMusic.flatMap { try? JSONEncoder().encode($0) }
            UserDefaults.standard.set(data, forKey: Self.replayMusicKey)
        }
    }

    static let replayMusicKey = "replayMusic.v1"

    private static var storedReplayMusic: ReplayMusicTrack? {
        guard let data = UserDefaults.standard.data(forKey: replayMusicKey) else { return nil }
        return try? JSONDecoder().decode(ReplayMusicTrack.self, from: data)
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
            deletedSessionCount = try await library.tombstoneCount()
            spots = try await library.spots()
            gearAggregates = try await library.gearAggregates()
            hasLoadedLibrary = true
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
        // Schema v7's column arrives empty, and the answer is in each session's archived
        // recording rather than anywhere we could infer it — so it is re-read, once, from
        // the FITs. Silent and best-effort: a row this cannot fill keeps the old
        // device-zone behaviour and is simply asked again next launch.
        _ = try? await ingestor.database.backfillStartUtcOffsets(archive: ingestor.archive)
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

    // MARK: - Naming a session

    /// Renames a session, or — with a blank string — gives it its derived name back.
    ///
    /// A reload rather than a targeted patch, for the same reason `renameSpot` does one: the
    /// name is on eleven surfaces, several of them (the widget snapshot, the library list,
    /// the records screen) built from the whole array, and a rename is a once-a-session
    /// action nobody is going to notice paying a query for.
    func renameSession(_ row: SessionRow, to title: String?) async {
        guard SessionNaming.customTitle(title) != row.customTitle else { return }
        do {
            try await library.renameSession(id: row.id, to: title)
            await load()
        } catch {
            errorMessage = "Could not rename this session: \(error)"
        }
    }

    /// Sets or clears the caption the share card and the clip's opening frame carry.
    ///
    /// Same reload, and deliberately so even though no *list* shows the note: the composer
    /// reads its draft back off the row when it is reopened, and a stale array there would
    /// mean the rider's own caption disappearing the second time he opens the sheet.
    func setShareNote(_ row: SessionRow, to note: String?) async {
        guard SessionNaming.note(note) != row.shareNote else { return }
        do {
            try await library.setShareNote(id: row.id, to: note)
            await load()
        } catch {
            errorMessage = "Could not save this caption: \(error)"
        }
    }

    /// Deletes a session, and — through `SessionIngestor.delete` — records that it was
    /// deleted, so the next intervals.icu sync leaves it alone.
    ///
    /// The title is handed down because only the app knows how to make one
    /// (`SessionDisplay.title` reads the archived filename, and the archive goes with the
    /// row): after this returns there is nothing left to derive a name from.
    func delete(_ row: SessionRow) async {
        do {
            try await ingestor.delete(row, title: SessionDisplay.title(row))
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
        /// The archived recording is a GPX. `FitShareFilter` scrubs FIT messages, and there
        /// is nothing for it to walk here — so the file is not offered rather than handed
        /// on unscrubbed, which is the one recovery that would be worse than refusing.
        case notAFit

        var description: String {
            switch self {
            case .notAWalkableFIT:
                "the archived file is not a plain FIT this app can rewrite safely"
            case .notAFit:
                "this session was imported from a GPX, and only FIT recordings can be "
                    + "scrubbed for sharing"
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
    ///
    /// `title` is the caller's, and defaults to the session's own. The composer passes the
    /// name currently in its title field instead: the rider is renaming the session in the
    /// same sheet the file leaves from, and a scrubbed FIT that arrived under the *previous*
    /// name would be the one place the rename visibly did not take.
    /// `FitShareFilter.filename` reduces whatever it is given to a filesystem-safe slug, so a
    /// title full of slashes, emoji or Cyrillic cannot reach a filename.
    func shareableFIT(for row: SessionRow, title: String? = nil,
                      includeAccelerometer: Bool) async throws -> (url: URL, bytes: Int) {
        let archive = ingestor.archive
        // The session's own zone, not the phone's: a file named after the afternoon it
        // records must not change its name because the rider flew home.
        let name = FitShareFilter.filename(date: row.startDate,
                                           title: title ?? SessionDisplay.title(row),
                                           timeZone: row.displayZone)
        return try await Task.detached(priority: .userInitiated) {
            let original = try archive.originalData(for: row.id)
            guard TrackParser.format(original) == .fit else { throw ShareError.notAFit }
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
    ///
    /// Returns the id of the row the example landed on, so a caller that means "and show it
    /// to me" (the welcome screen) does not have to go looking for it afterwards. That
    /// search would also be wrong: on a rider who already owns this recording the dedupe
    /// resolves in favour of *his* import, which is no longer flagged as the example.
    @discardableResult
    func loadExampleSession() async -> String? {
        guard !isBusy else { return nil }
        isBusy = true
        status = "Loading the example session…"
        defer { isBusy = false }

        let ingestor = self.ingestor
        do {
            let outcome = try await Task.detached(priority: .userInitiated) {
                try await ingestor.importExample()
            }.value
            var landed: String?
            switch outcome {
            case .imported(let row):
                landed = row.id
                status = "Example session loaded — open it to look around"
            case .duplicate(let row):
                // The example is a real recording, so the rider may already own it.
                landed = row.id
                status = row.isExample
                    ? "The example session is already in your library"
                    : "You already have this session — your own import kept"
            case .skipped:
                status = nil
            }
            await load()
            return landed
        } catch {
            errorMessage = "Could not load the example session: \(error)"
            return nil
        }
    }

    /// The welcome screen's primary button: load the example *and* land on it.
    ///
    /// Going straight into the session detail is the whole point — the replay, the
    /// commentary and the share card are what the screen just promised, and a rider left
    /// staring at a one-row list has been shown a library, not a session. The push itself
    /// goes through `pendingSessionID`, the same route a tapped notification takes, so
    /// there is one way into a session from outside the list rather than two.
    func loadExampleSessionAndOpen() async {
        guard let id = await loadExampleSession() else { return }
        pendingSessionID = id
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

    /// The same trick for the two library-backup jobs, which report different shapes.
    private final class Relay<Value>: @unchecked Sendable {
        private let sink: @Sendable (Value) -> Void

        init(_ sink: @escaping @Sendable (Value) -> Void) { self.sink = sink }

        func send(_ value: Value) { sink(value) }
    }

    // MARK: - Library backup & restore
    //
    // The one thing an iPhone migration does not cover (`LibraryBackup`). Both directions
    // are long jobs over a file the rider chose, so both are held as tasks the UI can
    // cancel, and both refuse to start while anything else is using the library.

    struct BackupProgress: Sendable, Equatable {
        var packed = 0
        var total = 0
    }

    /// A finished backup, waiting for the rider to say where it goes.
    ///
    /// It lives in `tmp/` and is offered through the share sheet, which is what lets him
    /// pick iCloud Drive — the natural destination and the one this app must never write to
    /// on its own, because "the app put a 3 GB file in your iCloud" is not a surprise
    /// anybody enjoys.
    struct BackupFile: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let manifest: LibraryBackupManifest
        let bytes: Int64

        var filename: String { url.lastPathComponent }
    }

    /// A picked backup that has been read far enough to say what it is, waiting for a yes.
    struct RestoreOffer: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let manifest: LibraryBackupManifest
    }

    /// How big the next backup would be. nil until Settings asks for it.
    private(set) var backupEstimate: LibraryBackupSize?
    private(set) var backupProgress: BackupProgress?
    private(set) var backupFile: BackupFile?
    private(set) var restoreProgress: LibraryRestore.RestoreProgress?
    var restoreOffer: RestoreOffer?

    private var backupWork: Task<LibraryBackupManifest, Error>?
    private var restoreWork: Task<LibraryRestore.Summary, Error>?

    /// `CFBundleShortVersionString (CFBundleVersion)` — written into the manifest so a
    /// backup can say which build made it. Read here rather than in the kit, whose
    /// `Bundle.main` in a test is the test runner.
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    private var backupWriter: LibraryBackupWriter {
        LibraryBackupWriter(database: ingestor.database, archive: ingestor.archive,
                            databaseURL: databaseURL, appVersion: Self.appVersion)
    }

    /// Cheap enough to run every time Settings appears: one directory walk and two counts.
    func refreshBackupEstimate() async {
        backupEstimate = try? await backupWriter.estimate()
    }

    /// Writes the whole library to a zip in `tmp/`, ready for the share sheet.
    func makeBackup() {
        guard !isBusy, backupWork == nil else { return }
        Task { await runBackup() }
    }

    private func runBackup() async {
        isBusy = true
        status = "Packing your library…"
        backupFile = nil
        let total = backupEstimate?.sessionCount ?? sessions.count
        backupProgress = BackupProgress(packed: 0, total: total)
        defer {
            isBusy = false
            backupProgress = nil
            backupWork = nil
        }

        // Its own directory under tmp/, wiped first: a previous backup still sitting there
        // is a file iOS may reap at any moment and a name collision the moment it does not.
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LibraryBackup", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        let url = directory.appendingPathComponent(LibraryBackupWriter.suggestedFilename())

        let writer = backupWriter
        let relay = Relay<BackupProgress> { [weak self] progress in
            Task { @MainActor in self?.backupProgress = progress }
        }
        let work = Task.detached(priority: .userInitiated) {
            try await writer.write(to: url) { packed, total in
                relay.send(BackupProgress(packed: packed, total: total))
            }
        }
        backupWork = work
        do {
            let manifest = try await work.value
            let bytes = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            backupFile = BackupFile(url: url, manifest: manifest, bytes: bytes)
            status = "Backup ready — \(Fmt.bytes(bytes))"
        } catch is CancellationError {
            status = "Backup stopped"
        } catch {
            errorMessage = "Could not write the backup: \(error)"
        }
    }

    func cancelBackup() { backupWork?.cancel() }

    /// Drops the finished file once the rider has sent it somewhere (or decided not to).
    func discardBackup() {
        if let url = backupFile?.url {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        backupFile = nil
    }

    // MARK: Restore

    /// Reads the picked zip's manifest and nothing else, so the confirmation sheet can say
    /// what it is — and so a backup from a newer build is refused *before* anything starts.
    func offerRestore(urls: [URL]) async {
        guard let url = urls.first, !isBusy else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            restoreOffer = RestoreOffer(url: url, manifest: try LibraryRestore.inspect(url))
        } catch {
            errorMessage = Self.restoreMessage(error)
        }
    }

    /// "Restore" on the confirmation sheet.
    func confirmRestore() {
        guard let offer = restoreOffer, !isBusy else { return }
        restoreOffer = nil
        Task { await runRestore(offer) }
    }

    func cancelRestore() { restoreWork?.cancel() }

    private func runRestore(_ offer: RestoreOffer) async {
        isBusy = true
        status = "Restoring your library…"
        restoreProgress = LibraryRestore.RestoreProgress(done: 0,
                                                         total: offer.manifest.sessionCount)
        defer {
            isBusy = false
            restoreProgress = nil
            restoreWork = nil
        }

        let ingestor = self.ingestor
        let url = offer.url
        let relay = Relay<LibraryRestore.RestoreProgress> { [weak self] progress in
            Task { @MainActor in self?.restoreProgress = progress }
        }
        // Detached and held, because cancellation has to reach *this* task: a detached
        // child does not inherit its parent's cancellation, and "Stop" has to mean stop.
        let work = Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return try await LibraryRestore(ingestor: ingestor)
                .restore(from: url) { relay.send($0) }
        }
        restoreWork = work
        do {
            let summary = try await work.value
            status = summary.shortDescription
            if !summary.failed.isEmpty {
                errorMessage = summary.failed.prefix(5).joined(separator: "\n")
            }
        } catch is CancellationError {
            status = "Restore stopped — the sessions already restored are in your library"
        } catch {
            errorMessage = Self.restoreMessage(error)
        }
        await load()
        // Restored sessions are the rider's own history, not new achievements: a backup
        // must not fire nine personal-best celebrations for records he set last summer.
        await refreshPersonalBests(celebrate: false)
        await writeNewSessionsToHealth()
    }

    /// `LibraryRestore.Failure` already carries a sentence written for a rider; anything
    /// else is a surprise and says so in its own words.
    private static func restoreMessage(_ error: any Error) -> String {
        (error as? LibraryRestore.Failure)?.description
            ?? "Could not read that backup: \(error)"
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

    private static func initialMapStyle() -> MapStyleChoice {
        let stored = MapStyleStore.load(from: .standard)
        #if DEBUG && targetEnvironment(simulator)
        // Screenshot hook, same family as `UI_HIDE_LAYERS`: `simctl` cannot open a menu, so
        // `UI_MAP_STYLE=satellite` starts the app on that ground. Applied *after* the load and
        // never written back — the override stages a screenshot, it does not edit the setting.
        if let raw = ProcessInfo.processInfo.environment["UI_MAP_STYLE"],
           let wanted = MapStyleChoice(rawValue: raw) { return wanted }
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
        // Read *before* this sync overwrites it: "when did he last pull?" is the whole of the
        // re-add gate, and `lastSyncDate` is already exactly that fact — this method is the
        // only thing that writes it, and only pull-to-refresh, "Sync now" and the empty
        // library's own button reach this method. The background poller never does.
        let previousSync = lastSyncDate
        let startedAt = Date()
        defer { isBusy = false }

        let ingestor = self.ingestor
        let oldest = IcuSyncService.defaultOldest()
        do {
            let summary = try await Task.detached(priority: .userInitiated) {
                let service = IcuSyncService(client: IcuClient(apiKey: key), ingestor: ingestor)
                return try await service.sync(oldest: oldest)
            }.value
            status = summary.shortDescription
            await offerReAddIfAsked(summary, previousSync: previousSync, startedAt: startedAt)
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

    // MARK: - Deleted sessions, and asking for them back

    /// The offer that is up: the sessions this sync skipped, ready to be picked through.
    /// `RootView` presents it as a sheet, next to the other two questions the app owns.
    ///
    /// It carries the tombstones themselves rather than a count, because the answer is a
    /// *selection*: the rider who pulled twice was almost certainly after one particular
    /// afternoon, and an all-or-nothing question about six of them has no right answer. It is
    /// also exactly the sessions this sync skipped and no others — "everything ever deleted"
    /// is the Settings escape hatch, and a much larger promise.
    struct ReAddOffer: Identifiable, Equatable {
        let id = UUID()
        let candidates: SessionTombstones.ReAddCandidates

        var count: Int { candidates.count }
    }

    private(set) var pendingReAdd: ReAddOffer?

    /// When the rider last said "Keep deleted". Persisted rather than held in memory: the
    /// damper exists so that a refusal is not immediately followed by the same question, and
    /// the app being relaunched between two pulls does not make the second one less annoying.
    private static let reAddDeclinedKey = "reAddDeclinedAt.v1"

    private var reAddDeclinedAt: Date? {
        get { UserDefaults.standard.object(forKey: Self.reAddDeclinedKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.reAddDeclinedKey) }
    }

    /// The gate Jan asked for: *pull twice, straight away, and we will ask*.
    ///
    /// Deleting a session is an instruction, so a sync that finds one and silently obeys is
    /// the correct behaviour and the common case. But "I pulled and nothing came, so I pulled
    /// again" is also a real thing to be confused about, and a second pull ten seconds after
    /// the first one finished is a gesture nobody makes by accident. The decision itself is a
    /// pure predicate in the kit (`SessionTombstones.shouldOfferReAdd`), which is where it can
    /// be tested; the arranging of the list into something pickable is
    /// `SessionTombstones.candidates`, for the same reason.
    ///
    /// `startedAt` and not `Date()`: the window is measured to the moment this sync *began*,
    /// so a slow connection cannot swallow the gesture by taking longer than the window.
    private func offerReAddIfAsked(_ summary: IcuSyncSummary, previousSync: Date?,
                                   startedAt: Date) async {
        guard SessionTombstones.shouldOfferReAdd(blocked: summary.tombstoned,
                                                 previousManualSyncAt: previousSync,
                                                 declinedAt: reAddDeclinedAt,
                                                 now: startedAt)
        else { return }
        let blocked = Set(summary.blockedTombstoneIds)
        guard let stones = try? await library.tombstones() else { return }
        let matched = stones.filter { blocked.contains($0.id) }
        guard !matched.isEmpty else { return }
        pendingReAdd = ReAddOffer(candidates: SessionTombstones.candidates(matched))
    }

    /// "Restore selected" — forget those tombstones and sync again, which is the only way the
    /// sessions can actually come back: their FITs went with the archive directories, so
    /// intervals.icu is the only place left holding them.
    ///
    /// The ones that were *not* selected keep their tombstones, which is the whole point of
    /// the picker: leaving a session out of the selection is a second, deliberate "yes, that
    /// one really is deleted".
    func acceptReAdd(ids: [String]) async {
        pendingReAdd = nil
        guard !ids.isEmpty else { return }
        do {
            try await library.forgetTombstones(ids: ids)
        } catch {
            errorMessage = "Could not restore those sessions: \(error)"
            return
        }
        await syncFromIntervals()
    }

    /// "Keep deleted", and the same call the alert's own dismissal makes. The tombstones stay;
    /// the offer stays down for `reAddWindowS`, so the very next pull — which is inside the
    /// window by construction — does not ask the same question again.
    func declineReAdd() {
        pendingReAdd = nil
        reAddDeclinedAt = Date()
    }

    /// The quiet escape hatch, from Settings: forget every tombstone and sync.
    ///
    /// It exists so that nobody is permanently stuck. The gate above only fires on a
    /// deliberate double-pull within two minutes, and a rider who deleted a session in March
    /// and wants it back in August will never trip it — this is how he gets there instead.
    func restoreAllDeletedSessions() async {
        guard !isBusy else { return }
        do {
            try await library.forgetAllTombstones()
        } catch {
            errorMessage = "Could not restore the deleted sessions: \(error)"
            return
        }
        reAddDeclinedAt = nil
        deletedSessionCount = 0
        await syncFromIntervals()
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
    ///
    /// The welcome screen counts, and it is the one that would otherwise collide hardest:
    /// it is up for the whole of a first launch, which is exactly when the notification
    /// offer has nothing to wait for. (It cannot in fact fire behind the welcome today —
    /// the offer needs a key and the welcome only appears without one — but that is two
    /// rules agreeing by accident, and the accident is one setup shortcut away from
    /// ending.)
    private var isPresentingSomething: Bool {
        isPresentingSheet || pendingImport != nil || errorMessage != nil || isCheckingKey
            || isShowingWelcome || pendingReAdd != nil
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
                + "Turn them on in Settings → Notifications → CleanJibe and try again."
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

    // MARK: - The welcome screen

    /// Written the moment the welcome actually goes up (or the moment we notice it is not
    /// owed at all), never when it is merely due — same discipline as the notification
    /// offer's `promptedKey`, and for the same reason: a rider who swiped the app away
    /// mid-screen has still been welcomed.
    static let welcomeShownKey = "welcomeShown.v1"

    /// True while `WelcomeView` is up. `RootView` presents it; whether it is owed at all is
    /// `WelcomePrompt`, in the kit.
    private(set) var isShowingWelcome = false

    #if DEBUG && targetEnvironment(simulator)
    /// Whether `UI_WELCOME` has already staged its one screen this launch.
    private var didStageWelcome = false
    #endif

    /// Asked at every moment the answer can change — launch, foreground, a sheet that just
    /// closed — and answered by the pure predicate, which says yes at most once per install
    /// and never on an install that plainly has a history.
    func showWelcomeIfNeeded() {
        // Nothing may be decided from a library that has not been read: an empty `sessions`
        // at launch means "still loading" for the first fraction of a second, and greeting
        // a rider with three seasons in the database because the query had not come back
        // yet is the one failure this screen must not have. A read that *failed* leaves
        // this false as well — then the app has an error banner to show, not a welcome.
        guard hasLoadedLibrary else { return }
        #if DEBUG && targetEnvironment(simulator)
        // Screenshot hook, same family as `UI_TAB` / `UI_LOAD_EXAMPLE`: `UI_WELCOME=1`
        // raises the screen whatever the flag and the library say, because a machine that
        // has ever run the app has spent the one launch that shows it. It stages the
        // *same* screen by the same route — nothing is drawn here that a first run could
        // not produce — and, like the other staging hooks, it never writes the flag: the
        // override photographs the state, it does not spend it.
        //
        // Once per launch, though, and that part is load-bearing rather than tidy: this
        // method is re-asked on every library change, and "raise it again" would put the
        // screen straight back up over the session its own example button just opened.
        if ProcessInfo.processInfo.environment["UI_WELCOME"] == "1", !didStageWelcome {
            didStageWelcome = true
            isShowingWelcome = true
            return
        }
        #endif
        let hasSeen = UserDefaults.standard.bool(forKey: Self.welcomeShownKey)
        // The upgrade path: an install that was already in use when this screen shipped is
        // marked as welcomed on sight, so emptying the library years later cannot make the
        // app introduce itself to its oldest user.
        if WelcomePrompt.shouldMarkSeenSilently(hasSeen: hasSeen,
                                                sessionCount: sessions.count,
                                                hasKey: !apiKey.isEmpty) {
            UserDefaults.standard.set(true, forKey: Self.welcomeShownKey)
            return
        }
        guard WelcomePrompt.shouldShow(hasSeen: hasSeen,
                                       sessionCount: sessions.count,
                                       hasKey: !apiKey.isEmpty,
                                       isPresenting: isPresentingSomething)
        else { return }
        UserDefaults.standard.set(true, forKey: Self.welcomeShownKey)
        isShowingWelcome = true
    }

    /// "What CleanJibe does", from Settings. Deliberately does **not** touch the flag: this
    /// is a rider asking to read the screen again, which is not the same event as the app
    /// deciding to show it, and re-arming the first run would mean the next launch greeted
    /// him unasked.
    ///
    /// It only *requests* the screen; `RootView` raises it once nothing else is up, which
    /// is what lets the Settings sheet it was tapped in get out of the way first.
    func replayWelcome() {
        wantsWelcomeReplay = true
        raiseRequestedWelcome()
    }

    /// Set between "show me that again" and the clear screen that can honour it.
    private var wantsWelcomeReplay = false

    /// The deferred half of `replayWelcome`, re-asked on the same hooks as everything else.
    ///
    /// The wait is the same 400-ish ms the Help sheet's "Open CleanJibe Settings" takes, for
    /// the same reason: a sheet's `isPresented` flips to false when its dismissal *starts*,
    /// and a presentation raised into the middle of that animation is one UIKit drops on
    /// the floor without a word. The flag is spent before the sleep, so the hooks firing
    /// again during it cannot queue a second screen.
    func raiseRequestedWelcome() {
        guard wantsWelcomeReplay, !isShowingWelcome, !isPresentingSomething else { return }
        wantsWelcomeReplay = false
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            isShowingWelcome = true
        }
    }

    /// Every way off the screen — all three buttons, and the cover's own dismissal.
    func dismissWelcome() {
        isShowingWelcome = false
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
                    "healthWriteEnabled", defaultTurnTypeKey, welcomeShownKey,
                    reAddDeclinedKey, replayLengthKey, replayFramingKey, replayMusicKey,
                    ActivityNotifier.enabledKey, ActivityNotifier.markKey,
                    ActivityNotifier.pendingImportKey, ActivityNotifier.promptedKey,
                    MapLayerVisibilityStore.defaultsKey, MapStyleStore.defaultsKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        let fm = FileManager.default
        for url in [try? AppPaths.databaseURL(), try? AppPaths.sessionsRoot()] {
            if let url { try? fm.removeItem(at: url) }
        }
        // The copy of whatever song the last clip was made with — a fresh install has none.
        ReplayMusicStore.keepOnly(nil)
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
