import AuthenticationServices
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

    /// **The status line under the session list — a toast, and toasts go away.**
    ///
    /// One line at the foot of the library that says what the app is doing or has just
    /// done: "Importing 3 files…", "Re-clustered into 4 spots", "Backup ready — 65,9 MB".
    /// Forty-odd places write it and, until build 58, **nothing cleared it**: the last
    /// sentence any job happened to leave behind sat on the bottom of the Sessions list
    /// until another job replaced it. Jan found "Backup ready — 65,9 MB" still there a
    /// quarter of an hour later, which turns a report of something finishing into a claim
    /// about the present.
    ///
    /// So the property arms its own dismissal. Writing a new message resets it; `nil` is
    /// still the immediate way to take one down by hand.
    ///
    /// Two rules the timer keeps:
    ///
    /// * **A message about work in progress outlives the work.** `isBusy` holds the line —
    ///   the clear is re-armed rather than fired — so "Packing your library…" is on screen
    ///   for as long as the packing is, and the lingering starts when it stops.
    /// * **Only the message that armed the timer may be cleared by it.** Every write bumps
    ///   a generation, and a timer whose generation is stale returns without touching
    ///   anything, so a slow job's old toast can never wipe the new one out from under it.
    private(set) var status: String? {
        didSet {
            guard status != oldValue else { return }
            statusGeneration &+= 1
            guard status != nil else { return }
            armStatusClear(generation: statusGeneration)
        }
    }

    /// How long a finished message stays on the screen. Long enough to read a sentence with
    /// a number in it, short enough that it is plainly a report of a moment rather than a
    /// standing statement about the library.
    static let statusLinger: Duration = .seconds(6)

    private var statusGeneration = 0

    private func armStatusClear(generation: Int) {
        Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(for: Self.statusLinger)
                guard let self, self.statusGeneration == generation,
                      self.status != nil else { return }
                // Still working: this is a progress line, not a leftover. Wait it out.
                guard !self.isBusy else { continue }
                self.status = nil
                return
            }
        }
    }

    /// Takes the status line down now — what a screen calls when the thing the line was
    /// about is no longer what the rider is looking at.
    func clearStatus() { status = nil }

    private(set) var storage = StorageStats()
    /// Set when a background job failed; the UI shows it as a dismissible banner.
    /// Every rider-facing failure in the app is shown through this one property, which is
    /// what makes it the one place the beta's failure list can be filled from
    /// (`UsageCounters`). Nothing is recorded outside the beta channel, and what is
    /// recorded is exactly the sentence that was on the screen.
    var errorMessage: String? {
        didSet {
            if let errorMessage, errorMessage != oldValue { Usage.failure(errorMessage) }
        }
    }

    /// **What each automatic source last ran into, if it is still failing** (`SyncTrouble`).
    ///
    /// The other half of `errorMessage`: a sync the rider did not start never raises the
    /// modal. It lands here instead, and the library's footer and each source's Settings
    /// section read it. Persisted, so "Last try failed" is still true after a relaunch.
    private(set) var syncTroubles = SessionStore.storedSyncTroubles() {
        didSet {
            guard syncTroubles != oldValue,
                  let data = try? JSONEncoder().encode(syncTroubles) else { return }
            UserDefaults.standard.set(data, forKey: Self.syncTroublesKey)
        }
    }

    static let syncTroublesKey = "syncTroubles.v1"

    private static func storedSyncTroubles() -> SyncTroubles {
        guard let data = UserDefaults.standard.data(forKey: syncTroublesKey),
              let troubles = try? JSONDecoder().decode(SyncTroubles.self, from: data)
        else { return SyncTroubles() }
        return troubles
    }

    /// One pending quiet retry per source; a newer failure replaces the older wait.
    private var quietRetries: [SyncSource: Task<Void, Never>] = [:]

    /// A source's failure, recorded and — when it is worth it — retried after a backoff.
    ///
    /// Returns the kind so the caller can decide the one thing left to decide: whether the
    /// rider is standing in front of *this exact action* and so may be shown the modal. A
    /// transient failure never is, whoever asked (`SyncFailureKind.transient`).
    @discardableResult
    func reportSync(_ kind: SyncFailureKind, from source: SyncSource, riderAsked: Bool,
                    retry: (@MainActor () async -> Void)? = nil) -> SyncFailureKind {
        let trouble = syncTroubles.recordFailure(kind, from: source, at: Date(),
                                                 riderAsked: riderAsked)
        quietRetries[source]?.cancel()
        quietRetries[source] = nil
        if let retry,
           let delay = SyncRetryPolicy.delay(afterFailures: trouble.failures, kind: kind) {
            quietRetries[source] = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.quietRetries[source] = nil
                await retry()
            }
        }
        return kind
    }

    @discardableResult
    func reportSync(_ error: any Error, from source: SyncSource, riderAsked: Bool,
                    retry: (@MainActor () async -> Void)? = nil) -> SyncFailureKind {
        reportSync(SyncFailureKind.classify(error), from: source, riderAsked: riderAsked,
                   retry: retry)
    }

    /// The quiet retries themselves: each the automatic entry point of its source, so a
    /// retry is exactly the try the app would have made by itself.
    private var quietIntervalsRetry: @MainActor () async -> Void {
        { [weak self] in await self?.syncFromIntervals(riderAsked: false) }
    }

    private var quietStravaRetry: @MainActor () async -> Void {
        { [weak self] in await self?.checkStravaForNewActivities() }
    }

    #if DEV
    private var quietICloudRetry: @MainActor () async -> Void {
        { [weak self] in self?.syncLibraryNow(riderAsked: false) }
    }
    #endif

    /// A try that worked, or a source the rider switched off: the line it would show is no
    /// longer true, and neither is any retry still waiting.
    func clearSyncTrouble(_ source: SyncSource) {
        syncTroubles.recordSuccess(from: source)
        quietRetries[source]?.cancel()
        quietRetries[source] = nil
    }

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

    /// Clean-jibe records beaten by the same import (engine 0.10.0) — most clean jibes in a
    /// session, and best CPH. A separate list because they are not speeds and have no row in
    /// the knots table, but the same moment: the Records screen fires one burst for both.
    private(set) var cleanJibeCelebration: [NewCleanJibeBest] = []

    /// What the Records screen watches to know a celebration arrived, whichever kind it is.
    var celebrationCount: Int { celebration.count + cleanJibeCelebration.count }

    /// Which map/chart overlay categories the legend chips are showing, **per map**
    /// (`MapLayerScope`: the ride track, the Turns map, the Takeoffs map).
    ///
    /// One setting per map for the whole app rather than one per session: "I never want to
    /// see course changes" is a statement about the rider, not about a particular ride. Per
    /// *map* rather than one set for all three because the maps answer different questions —
    /// hiding "fell in" on Turns, where the page is a verdict on maneuvers, must not blank
    /// the falls on the ride map, which is a picture of the afternoon. Each scope is
    /// persisted under its own key on every change, so a relaunch comes back the way each
    /// map was left.
    private var mapLayersByScope: [MapLayerScope: MapLayerVisibility]
        = SessionStore.initialMapLayers() {
        didSet {
            for scope in MapLayerScope.allCases
            where mapLayersByScope[scope] != oldValue[scope] {
                MapLayerVisibilityStore.save(mapLayers(for: scope), scope: scope,
                                             to: .standard)
            }
        }
    }

    /// The set one map is drawing with. The single keyed accessor every legend, map and
    /// chart reads through.
    func mapLayers(for scope: MapLayerScope) -> MapLayerVisibility {
        mapLayersByScope[scope] ?? scope.defaultVisibility
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

    /// **Whether a library row draws its track over a map** (item 6 of the 18 Sep 2026
    /// round). Off by default: the plain outline is the shape at a glance, and a hundred map
    /// tiles behind a scrolling list is a cost a rider opts into rather than inherits. The
    /// ground is `mapStyle`, the same choice every map in the app is drawn on.
    var listMapBackdrop: Bool = SessionStore.storedListMapBackdrop {
        didSet {
            guard listMapBackdrop != oldValue else { return }
            UserDefaults.standard.set(listMapBackdrop, forKey: Self.listMapBackdropKey)
        }
    }

    static let listMapBackdropKey = "listMapBackdrop"

    private static var storedListMapBackdrop: Bool {
        UserDefaults.standard.bool(forKey: listMapBackdropKey)
    }

    /// **The three numbers every library row carries** (Jan, Beta 75). Which three is a
    /// fact about the rider — one is chasing a speed, the next is counting clean jibes —
    /// so it is his to set (Settings → Session list → Row shows). What each one is called,
    /// what it is drawn with and how it is spelled is the kit's (`RowMetric`).
    ///
    /// Always three, whatever is in the defaults: `RowMetric.triple(stored:)` fills a slot
    /// it cannot read from the default rather than leaving the row a cell short.
    var rowMetrics: [RowMetric] = SessionStore.storedRowMetrics {
        didSet {
            guard rowMetrics != oldValue else { return }
            UserDefaults.standard.set(RowMetric.stored(rowMetrics), forKey: Self.rowMetricsKey)
        }
    }

    static let rowMetricsKey = "sessionRowMetrics"

    /// **Knots or km/h, for every speed the phone shows** (Settings → Units, 20 September
    /// 2026). Stored by `SpeedUnitStore` and applied to the kit's one formatter, which is
    /// what the library rows, the session page, the records, the trends captions and the
    /// share card all print through (`Speed`).
    ///
    /// Writing it here is what redraws the app: every view reading a formatted speed is
    /// already observing this store.
    var speedUnit: SpeedUnit = SpeedUnitStore.load(from: .standard) {
        didSet {
            guard speedUnit != oldValue else { return }
            SpeedUnitStore.save(speedUnit, to: .standard)
            Speed.unit = speedUnit
            // The two surfaces that are not this process and therefore cannot observe the
            // store: the home-screen widgets read a published snapshot, and the watch app
            // reads what the phone last told it. Both are speeds a rider sees, so both
            // follow the picker (docs/presentation/labels.md, "Units").
            Task { await publishWidgetSnapshot() }
            WatchSessionReceiver.shared.pushSpeedUnit(speedUnit)
        }
    }

    /// **Whether a record from a track with no measured speed counts** (Settings → Speed
    /// records, 22 September 2026). Stored by `SpeedRecordPolicyStore` and handed to the
    /// one rule every all-time surface reads (`SpeedRecordRule`).
    ///
    /// Writing it here is what redraws the app: the Records screen keys its query on this
    /// value (`RecordsView.reloadKey`), so the table is re-read from the same `record_effort`
    /// rows under the new rule. Nothing is re-imported and no stored digest moves — the
    /// decision is taken at query time, which is the only place it can be taken without
    /// going stale.
    var speedRecordPolicy: SpeedRecordPolicy = SpeedRecordPolicyStore.load(from: .standard) {
        didSet {
            guard speedRecordPolicy != oldValue else { return }
            SpeedRecordPolicyStore.save(speedRecordPolicy, to: .standard)
            Task {
                // **Re-take the personal-best snapshot, silently.** The stored snapshot is
                // what the *next* import is compared against, and it was taken under the
                // old policy. Switching to "Include unverified" would otherwise make a
                // record that has stood for months look like a personal best the next time
                // a session lands, and fire the confetti at the one moment it means
                // nothing. `celebrate: false` is exactly this case: the numbers moved
                // because the rider moved a picker, not because he went faster.
                await refreshPersonalBests(celebrate: false)
                // The widget process cannot read the setting, so the phone resolves it and
                // republishes the snapshot — the same reason the unit is published there.
                await publishWidgetSnapshot()
            }
        }
    }

    private static var storedRowMetrics: [RowMetric] {
        RowMetric.triple(stored: UserDefaults.standard.string(forKey: rowMetricsKey))
    }

    /// **The Sessions tab's run, in the order it is drawing it** — what the filter left and
    /// the grouping ordered. The session page reads it so a swipe walks the afternoons in
    /// the order the rider is reading them (`SessionDetailView.order`). Empty until the list
    /// has drawn once, which is the honest answer for a page reached from a notification.
    var visibleSessionIDs: [String] = []

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

    /// `var` because two engine settings are the rider's to move: `defaultTurnType`, and
    /// — on this phone only — the tuning overrides (Settings → Tuning).
    var ingestor: SessionIngestor
    /// Lazy track thumbnails for the library rows.
    let thumbnails: ThumbnailStore
    private let databaseURL: URL?

    /// Aggregate reads (records, trends, gear, spots) all go through here.
    var library: LibraryStore { ingestor.library }

    // MARK: - Setup

    /// **The library on this phone was last used by a newer build** — set when
    /// `AppDatabase` refuses to open it (`LibraryNewerThanApp`), and nil in every ordinary
    /// launch.
    ///
    /// It is a *state*, not an error message: `RootView` puts a full screen in front of
    /// everything while it is set, because every tab behind it would be showing an empty
    /// library that is not empty. See docs/channels.md, "Switching channels" — the case is
    /// an older App Store build put back on a phone a newer beta has already migrated.
    private(set) var libraryNewerThanApp: LibraryNewerThanApp?

    init() {
        // **Before anything renders a speed.** The kit's one formatter is a process-wide
        // setting (`Speed`), and this is the single place the app writes it from the
        // rider's stored choice.
        SpeedUnitStore.apply(from: .standard)
        var url: URL?
        var problem: String?
        var database: AppDatabase?
        var newer: LibraryNewerThanApp?
        do {
            let dbURL = try AppPaths.databaseURL()
            url = dbURL
            database = try AppDatabase.onDisk(at: dbURL)
        } catch let refusal as LibraryNewerThanApp {
            // Deliberately *not* an `errorMessage`: a banner over an apparently empty
            // library invites the rider to import everything again on top of a library
            // that is still there. The screen `RootView` raises is the whole answer, and
            // the file on disk is left exactly as the newer build left it.
            newer = refusal
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
        ingestor.riderDiscipline = Self.storedRiderDiscipline
        // The ingestor's own default is `true`, so this assignment is load-bearing in every
        // channel. DEV reads the switch; release and beta have no switch (docs/channels.md),
        // so every import is wingfoil and written down as confirmed — and a
        // `windsurfEnabled.v1` left in defaults by a dev build on the same phone is never
        // read, exactly as a leftover tuning blob is not.
        #if DEV
        ingestor.windsurfEnabled = Self.storedWindsurfEnabled
        #else
        ingestor.windsurfEnabled = false
        #endif
        #if TUNING
        // Dev build only. In the shipping app this assignment does not exist, so
        // `ingestor.tuning` stays empty, the engine runs on the published defaults, and a
        // `tuningOverrides.v1` left behind by a dev build on the same phone is never read.
        ingestor.tuning = Self.storedTuning
        #endif
        self.ingestor = ingestor
        // The thumbnail cache only ever touches the archive, never the analyzer, so its
        // copy of the ingestor does not need the engine parameter kept in step.
        thumbnails = ThumbnailStore(ingestor: ingestor)
        libraryNewerThanApp = newer
        errorMessage = problem
    }

    /// **Restoring over a library this build cannot read.**
    ///
    /// Called from `confirmRestore` and nowhere else, which is the only point at which the
    /// rider has picked a file, read what is in it and tapped Restore. Up to here the
    /// refusal has changed nothing on disk, and it must not: the rider's way out of this
    /// screen is usually the other button, and reinstalling the newer build has to find its
    /// library where it left it.
    ///
    /// The too-new file is **moved aside, not deleted** — `wingfoil.sqlite.v17.newer` beside
    /// the new one — for the same reason. It costs the storage a rider is about to spend on
    /// a restore anyway, and it is the difference between a mistake and a loss.
    private func adoptFreshLibraryForRestore() {
        guard let newer = libraryNewerThanApp, let url = databaseURL else { return }
        let aside = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".v\(newer.storedVersion).newer")
        do {
            try? FileManager.default.removeItem(at: aside)
            try FileManager.default.moveItem(at: url, to: aside)
            // The journal files belong to the database that was just moved; left behind,
            // SQLite would try to replay them into the fresh one.
            for suffix in ["-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: url.deletingLastPathComponent()
                        .appendingPathComponent(url.lastPathComponent + suffix))
            }
            ingestor.database = try AppDatabase.onDisk(at: url)
            libraryNewerThanApp = nil
        } catch {
            errorMessage = "Could not set the newer library aside: \(error)"
        }
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
            // **Every** path that can mint a spot ends here — an import, a sync, a restore,
            // a delete, a re-cluster — so this is the one place naming has to be hooked to
            // be automatic. Detached from the reload rather than awaited: the geocoder is a
            // network round trip with a 1.2 s spacing between spots, and the library list
            // must not wait for it. It costs one small query when there is nothing to name.
            Task { await self.nameSpots() }
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
        // The rider's Speed records setting, applied at the query and again at the
        // comparison — one rule, asked twice about the same rows, which is what makes the
        // burst and the table agree about what a record is.
        guard let records = try? await library.records(policy: speedRecordPolicy)
        else { return }
        let previous = storedPersonalBests
        // Both axes off the same load: the speed records out of the library's own query,
        // the clean-jibe pair out of the rows `load()` has just refreshed — filtered the
        // way that query filters, because a personal best is a claim about the rider and
        // the in-memory list is the raw table (`LibraryStore.clause`).
        let cleanJibes = PersonalBestDetector.cleanJibeBests(
            sessions.filter { !$0.isExample && !$0.isProvisional && $0.isSession
                              && $0.rider == nil })
        if celebrate, let previous {
            let found = PersonalBestDetector.improvements(previous: previous,
                                                          current: records,
                                                          policy: speedRecordPolicy)
            if !found.isEmpty { celebration = found }
            let clean = PersonalBestDetector.cleanJibeImprovements(previous: previous,
                                                                   current: cleanJibes)
            if !clean.isEmpty { cleanJibeCelebration = clean }
        }
        storePersonalBests(PersonalBestSnapshot(records: records, cleanJibes: cleanJibes))
    }

    /// Called by the Records screen once it has shown the burst.
    func clearCelebration() {
        celebration = []
        cleanJibeCelebration = []
    }

    // MARK: - Widgets

    /// Publishes the home-screen widget snapshot. Best effort by design: without the app
    /// group entitlement it lands in the app's own container instead, and the widget shows
    /// its placeholder (see `WidgetSnapshotStore`).
    private func publishWidgetSnapshot() async {
        // The example is on loan, not ridden, and a friend's session is not the reader's
        // at all: neither may become "your last session" on the home screen, nor count
        // towards this week's foil time. Same rule as `LibraryStore.clause`, restated here
        // because the widget reads the in-memory list rather than going through SQL.
        // A recording that is not a session (engine 0.19.0) is out for a third reason: it
        // put "FOIL 0 % · FLIGHTS 0" on Jan's home screen on 14 September 2026 with the
        // afternoon before it sitting one row down, and it added itself to this week's
        // session count on the way past. `isRidden` already skipped it as "the last
        // session"; this is the same rule applied to the totals beside it.
        let rows = sessions.filter { !$0.isExample && $0.isSession && $0.rider == nil }
        // JPH per session is a query and not a column — the session index denormalizes CPH
        // only — and the widget must print the session page's number, not one of its own.
        let jibesPerHour = (try? await library.jibeRates()) ?? [:]
        let archive = ingestor.archive
        // Settings → Speed records, resolved here: a widget process cannot read the app's
        // defaults, so the phone answers the question and publishes the answer.
        let policy = speedRecordPolicy
        await Task.detached(priority: .utility) {
            let snapshot = WidgetSnapshot.make(
                sessions: rows, jibesPerHour: jibesPerHour, policy: policy,
                titleForRow: { SessionDisplay.title($0) },
                trackForRow: { Self.widgetTrack(for: $0, archive: archive) })
            WidgetSnapshotStore.write(snapshot)
            WidgetRefresher.reloadTimelines()
        }.value
    }

    /// The outline the widget draws behind its numbers, for the one session it names.
    ///
    /// The cached `thumbnail.json` first — which is what the library list has usually
    /// already built, so publishing costs a small JSON read. When it is missing (a fresh
    /// import the rider has not scrolled to yet) it is built and cached here, off the main
    /// actor, exactly the way `ThumbnailStore` builds one: **one** FIT parse, once, for the
    /// newest ridden session, and never again for that session. A session whose archive is
    /// gone returns nil and the widget simply draws no track, which is the right answer
    /// rather than a straight line between two fixes.
    private nonisolated static func widgetTrack(for row: SessionRow,
                                                archive: SessionArchive) -> TrackThumbnail? {
        if let cached = archive.thumbnail(for: row.id) { return cached }
        guard let track = try? archive.rawTrack(for: row.id) else { return nil }
        let analysis = archive.analysis(for: row.id)
        let flights = analysis?.flights ?? []
        let thumbnail = TrackThumbnail.make(track: track, flights: flights,
                                            events: analysis.map(TrackThumbnail.events) ?? [])
        guard !thumbnail.isEmpty else { return nil }
        // Only cache an outline whose colouring is final — `ThumbnailStore`'s rule, for its
        // reason: a track with no flights yet would freeze as a grey session.
        if !flights.isEmpty { try? archive.writeThumbnail(thumbnail, id: row.id) }
        return thumbnail
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

    /// How long to wait before asking the geocoder again after a pass that resolved nothing.
    /// Doubles per attempt, three attempts, then it waits for the next launch, an import or
    /// the rider's own tap. A lookup that failed because the phone is in a van in the Alps
    /// will fail again in one second and may well succeed in half a minute.
    private static let spotNamingRetryDelays: [Duration] = [.seconds(20), .seconds(60),
                                                            .seconds(180)]
    private var spotNamingRetry: Task<Void, Never>?

    /// Fills in `Spot N` placeholders from the reverse geocoder, and **retries when the
    /// network was not there**.
    ///
    /// It runs on every occasion the set of spots can change — launch, the end of an import
    /// or a sync, a re-cluster, lazy re-analysis, and the rider's own "Look up names again"
    /// — because a spot the rider can see wearing a placeholder is a spot nothing was going
    /// to name: before this, naming happened at launch only, so a library synced from
    /// intervals.icu in one sitting showed "Spot 1 … Spot 7" until the app was killed and
    /// reopened. (That is the answer to "why did it not apply on a fresh library".)
    ///
    /// Best effort still: offline or throttled, the placeholders stay, stay renamable, and
    /// are asked again — after a delay, so a phone with no signal is not asked sixty times.
    func nameSpots() async {
        spotNamingRetry?.cancel()
        spotNamingRetry = nil
        await runSpotNaming(attempt: 0)
    }

    private func runSpotNaming(attempt: Int) async {
        let library = self.library
        guard let pending = try? await library.unnamedSpotCount(), pending > 0 else { return }
        let unresolved = (try? await library.nameAutoSpots(using: SpotNamer.shared.resolver)) ?? 0
        spots = (try? await library.spots()) ?? spots
        guard unresolved > 0, attempt < Self.spotNamingRetryDelays.count else { return }
        let delay = Self.spotNamingRetryDelays[attempt]
        spotNamingRetry = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.runSpotNaming(attempt: attempt + 1)
        }
    }

    func renameSpot(_ spot: SpotRow, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await library.renameSpot(id: spot.id, to: trimmed)
            Usage.record(.gearSpots, detail: "spot")
        } catch {
            Usage.failed(.gearSpots, error: error)
        }
        await load()
    }

    func reclusterSpots() async {
        do {
            try await library.recluster()
            await load()
            status = "Re-clustered into \(spots.count) spot\(spots.count == 1 ? "" : "s")"
            // A re-cluster can mint new places, and the ones it mints wear placeholders.
            // Naming them here is what keeps "Re-cluster spots" from being a button that
            // replaces names with numbers.
            await nameSpots()
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
            Usage.record(.gearSpots, detail: "gear")
            await load()
        } catch {
            Usage.failed(.gearSpots, error: error)
            errorMessage = "Could not save gear: \(error)"
        }
    }

    func deleteGear(_ gear: GearRow) async {
        try? await library.deleteGear(id: gear.id)
        await load()
    }

    func assignGear(sessionID: String, kind: GearKind, gearID: String?) async {
        do {
            try await library.assignGear(sessionId: sessionID, kind: kind, gearId: gearID)
            Usage.record(.gearSpots, detail: "assign")
        } catch {
            Usage.failed(.gearSpots, error: error)
        }
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
            Usage.record(.rename)
            await load()
        } catch {
            Usage.failed(.rename, error: error)
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
            Usage.record(.rename)
            await load()
        } catch {
            Usage.failed(.rename, error: error)
            errorMessage = "Could not save this caption: \(error)"
        }
    }

    /// **Analyse this session as another discipline** (docs/algorithms/disciplines.md "Disciplines").
    ///
    /// One session, re-derived on the spot. It takes the same shape as a rename — write, then
    /// `load()` — with one addition: which parts of a track were *flying* can move with the
    /// preset (a fin planes at 20 km/h, a foil flies at 12), so the cached outline is stale
    /// by construction and is dropped the way a re-analysis drops it.
    func setDiscipline(_ discipline: Discipline, for row: SessionRow) async {
        guard discipline != row.analysisDiscipline else { return }
        let ingestor = self.ingestor
        do {
            _ = try await Task.detached(priority: .userInitiated) {
                try await ingestor.setDiscipline(discipline, for: row)
            }.value
            thumbnails.invalidate(row.id)
            Usage.record(.windsurfMode)
            await load()
        } catch {
            Usage.failed(.windsurfMode, error: error)
            errorMessage = "Could not re-analyse this session: \(error)"
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
            Usage.record(.deleteSession)
            thumbnails.invalidate(row.id)
            await load()
            await refreshPersonalBests(celebrate: false)
        } catch {
            Usage.failed(.deleteSession, error: error)
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

    // MARK: - Sending a session to the developer

    /// **The file that rides with the analysis mail** (Share → Send this session to the
    /// developer, `SendToDeveloperSheet`).
    ///
    /// **Scrubbed, the same way a friend's copy is, wherever there is a FIT to scrub**
    /// (22 September 2026). `FitShareFilter` only drops what is personal — the watch's
    /// serial number, the rider profile, a paired accessory's name — and keeps everything
    /// the analysis actually reasons about: developer fields, every lap, the session summary
    /// and (`dropAccel: false`, unlike the friend's default) the accelerometer stream a
    /// pumping question might turn on. A reader being asked to reproduce a number has no
    /// more use for a watch's serial than a friend does, and the rider is told exactly what
    /// stayed and what did not before he sends it (`SessionAnalysisMail.consent`), with
    /// every byte of the mail in front of him first.
    ///
    /// A `.watch` or `.direct` recording — the CleanJibe watch app's own container, or the
    /// Connect IQ direct-transfer stream — is not FIT-shaped and has no scrub of its own to
    /// run, so it archives exactly what it always did; neither carries the watch serial a
    /// plain FIT export does. A session that arrived as positions rather than as a recording
    /// — Strava, Apple Health — archives the track CleanJibe built from them, which is a
    /// GPX, the same way. The mail says which of these is a recording at all
    /// (`isRecording`).
    struct AnalysisAttachment {
        let data: Data
        let filename: String
        let mimeType: String
        /// True for a recording off a watch, false for a track built from positions.
        let isRecording: Bool

        var described: SessionAnalysisMail.Attachment {
            isRecording ? .originalRecording(filename: filename)
                        : .derivedTrack(filename: filename)
        }
    }

    /// Nil when nothing is archived for the row, or when a FIT is not one `FitShareFilter`
    /// can walk safely — fail closed, the same rule `shareableFIT` follows: a file we
    /// cannot promise is scrubbed does not go, and the sheet says so rather than hide it.
    func analysisAttachment(for row: SessionRow) -> AnalysisAttachment? {
        let archive = ingestor.archive
        guard let data = try? archive.originalData(for: row.id) else { return nil }
        let format = TrackParser.format(data) ?? .fit
        let isRecording = format != .gpx && format != .tcx
        // `FitShareFilter` walks a plain FIT stream — the same test `shareableFIT` makes
        // before it will scrub one. A `.watch` or `.direct` recording is a CleanJibe
        // container, not a FIT file, and has no scrub of its own to run; it archives
        // exactly what it always did. Accelerometer kept (`dropAccel: false`), unlike the
        // friend's default: see the note above.
        let sendable: Data
        if format == .fit {
            guard let scrubbed = FitShareFilter.filter(data, dropAccel: false) else {
                return nil
            }
            sendable = scrubbed
        } else {
            sendable = data
        }
        // The session's own zone, like the shared FIT's name: a file named after the
        // afternoon it records must not change its name because the rider flew home.
        let name = FitShareFilter.filename(date: row.startDate,
                                           title: SessionDisplay.title(row),
                                           pathExtension: format.fileExtension,
                                           timeZone: row.displayZone)
        return AnalysisAttachment(
            data: sendable, filename: name,
            // `application/octet-stream` for everything that is not text: no registered
            // type exists for `.fit` or `.cjw`, and a guessed one is how a mail client
            // decides to render a recording as a preview instead of attaching it.
            mimeType: format == .gpx || format == .tcx
                ? "application/xml" : "application/octet-stream",
            isRecording: isRecording)
    }

    // MARK: - Sharing the recording

    enum ShareError: Swift.Error, CustomStringConvertible {
        case notAWalkableFIT
        /// The archived recording is a GPX or a TCX. `FitShareFilter` scrubs FIT messages,
        /// and there is nothing for it to walk here — so the file is not offered rather than
        /// handed on unscrubbed, which is the one recovery that would be worse than refusing.
        case notAFit

        var description: String {
            switch self {
            case .notAWalkableFIT:
                "the archived file is not a plain FIT this app can rewrite safely"
            case .notAFit:
                "this session did not come in as a FIT file, and only a FIT can be scrubbed "
                    + "for sharing"
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
    @discardableResult
    func importFiles(urls: [URL], source: ImportSource, rider: String? = nil) async
    -> ImportSummary {
        guard let payloads = readPayloads(urls) else { return ImportSummary() }
        return await runImport(payloads, source: source, rider: rider)
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
        let name = SessionIngestor.riderName(rider)
        Usage.record(.riderAssign, detail: name == nil ? "mine" : "someone else")
        await runImport(pending.payloads, source: pending.source, rider: name)
    }

    /// Dismissing the prompt imports nothing. There is no safe default for "whose is it"
    /// once the app can be handed a stranger's file.
    func cancelPendingImport() { pendingImport = nil }

    /// **Whose session this is, changed after the import** — the list's swipe action
    /// (F7d). Nil is "mine". A reload rather than a patch, the same as a rename: the rider
    /// decides whether the session is in Records, Trends, the gear totals and the widget,
    /// and every one of those is built from the whole array.
    func setRider(_ row: SessionRow, to rider: String?) async {
        let name = SessionIngestor.riderName(rider)
        guard name != row.rider else { return }
        do {
            try await library.setRider(id: row.id, to: name)
            Usage.record(.riderAssign, detail: name == nil ? "mine" : "someone else")
            await load()
        } catch {
            Usage.failed(.riderAssign, error: error)
            errorMessage = "Could not change whose session this is: \(error)"
        }
    }

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
            } else if quietFailures {
                reportSync(.other(detail: "could not read \(url.lastPathComponent)"),
                           from: .watch, riderAsked: false)
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

    /// True once the bundled example is in the library — the empty library and Help ask,
    /// so neither offers to load something that is already there.
    var hasExampleSession: Bool { sessions.contains { $0.isExample } }

    /// **True on the one-tap first run**: the example is in the library and nothing that
    /// counts is.
    ///
    /// Records and Trends both read it, because both of them are otherwise obliged to
    /// explain an empty screen by naming a filter the rider never set — the example is
    /// excluded from both on purpose (`LibraryStore.clause`, `ExampleOnlyNote`) and no
    /// control on either screen can change that. The predicate is that same clause
    /// restated on the in-memory list, for the third time in this file and for the same
    /// reason: the views read the list, not the SQL.
    var hasOnlyExampleSessions: Bool {
        hasExampleSession && !sessions.contains {
            !$0.isExample && !$0.isProvisional && $0.isSession && $0.rider == nil
        }
    }

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

    @discardableResult
    private func runImport(_ payloads: [DiscoveredFit], source: ImportSource,
                           rider: String? = nil) async -> ImportSummary {
        guard !payloads.isEmpty, !isBusy else { return ImportSummary() }
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
        // A recording that arrived by itself — an Apple Health pickup, the Apple Watch
        // inbox — never raises the modal: nobody is waiting on it. It goes to the footer.
        if quietFailures {
            let from = SyncSource(importSource: source)
            if summary.failed.isEmpty {
                if let from { clearSyncTrouble(from) }
            } else if let from {
                reportSync(.other(detail: "\(summary.failed.count) file"
                                  + (summary.failed.count == 1 ? "" : "s") + " would not read"),
                           from: from, riderAsked: false)
            }
        } else {
            errorMessage = Self.failureAlert(summary.failed)
        }
        // The one counted place every file-shaped door passes through — Files, the share
        // sheet, a Garmin export ZIP, Apple Health, the Apple Watch inbox, the direct
        // transfer — so each is counted once and by name. `quietFailures` is what marks a
        // pickup nobody asked for, which is how the automatic Health import is told apart.
        Usage.recordImport(source, automatic: quietFailures, imported: summary.imported,
                           failed: summary.failed.count)
        await load()
        await refreshPersonalBests(celebrate: true)
        await writeNewSessionsToHealth()
        // An import can promote a new spot into the watch's two slots — a first week at a
        // new lake does exactly that. Cheap when it has not (`automaticPassIsWorthIt`).
        await refreshWatchMapIfNeeded()
        // …and, last, the one question the file could not answer: is this wingfoil?
        // After the import rather than before it, so a two-hundred-file ZIP never stops on
        // its first question (see "Discipline on import" below).
        raiseDisciplineReview()
        return summary
    }

    /// Bridges the ingestor's `@Sendable` progress closure back to the main actor.
    private final class ProgressRelay: @unchecked Sendable {
        private let sink: @Sendable (ImportSummary) -> Void

        init(_ sink: @escaping @Sendable (ImportSummary) -> Void) { self.sink = sink }

        func send(_ summary: ImportSummary) { sink(summary) }
    }

    /// "Is anybody still listening?" — flipped once, on the way out of a job whose progress
    /// arrives on main-actor hops that can outlive it.
    final class LiveFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var open = true

        var isLive: Bool { lock.withLock { open } }
        func close() { lock.withLock { open = false } }
    }

    /// The same trick for the two library-backup jobs, which report different shapes.
    private final class Relay<Value>: @unchecked Sendable {
        private let sink: @Sendable (Value) -> Void

        init(_ sink: @escaping @Sendable (Value) -> Void) { self.sink = sink }

        func send(_ value: Value) { sink(value) }
    }

    // MARK: - Discipline on import
    //
    // **Wingfoil is not a sport anywhere but here.** Garmin, Strava, intervals.icu and Apple
    // Health have no code for it, so the corpus is full of wingfoil afternoons recorded under
    // Garmin's *windsurf* profile (ADR-004) — which is exactly why the sport code is not
    // allowed to decide anything (docs/algorithms/disciplines.md, "Disciplines"). What decides is the
    // recording's own `discipline` field where it has one, and the rider's declared default
    // where it does not; the second of those is a guess, and this section is the app owning up
    // to it. See docs/presentation/labels.md, "Confirming the discipline on import".

    static let windsurfEnabledKey = "windsurfEnabled.v1"

    static var storedWindsurfEnabled: Bool {
        UserDefaults.standard.bool(forKey: windsurfEnabledKey)
    }

    /// **Settings → Analysis → "Windsurf (experimental)"** — the one switch every
    /// windsurf-facing control hangs off, off on a fresh install (Jan, 13 Sep 2026:
    /// *"windsurf should be hidden. Maybe enable with a switch"*).
    ///
    /// With it off this is the wingfoil-only app it was before the preset existed: no "I
    /// mostly ride" row, no "Analyse as" card, no review sheet, no library banner, no `?`, no
    /// windsurf topic on the Help index, and imports that are wingfoil and confirmed.
    ///
    /// **It hides controls and nothing else.** A session somebody already analysed as windsurf
    /// keeps its preset, its numbers, its badge and its amber chip — turning a switch off is
    /// not the rider saying that afternoon was a wingfoil afternoon, so nothing is re-derived
    /// in either direction. Turning it back on does not raise a review either: the sessions
    /// imported while it was off were written down as confirmed, and the rider who wants one
    /// of them read differently has "Analyse as" on the session that matters.
    ///
    /// A stored property rather than a computed read of `UserDefaults`, because this one is
    /// observed: flipping it has to redraw the Settings rows it hides, in place.
    ///
    /// **DEV ONLY** (docs/channels.md). In the release and beta channels there is no switch
    /// to flip, so this is the constant `false` and every windsurf-facing control reads it
    /// exactly as it always did — `DisciplineReview.pending` returns nothing, the banner is
    /// nil, the review sheet never fills, the filter menu has no Discipline section and the
    /// Help index has no windsurf topic. One constant rather than a `#if DEV` in each of the
    /// nine places that ask, and no behaviour to get wrong when the flag moves.
    #if DEV
    private(set) var windsurfEnabled = SessionStore.storedWindsurfEnabled

    func setWindsurfEnabled(_ enabled: Bool) {
        guard enabled != windsurfEnabled else { return }
        windsurfEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.windsurfEnabledKey)
        ingestor.windsurfEnabled = enabled
        Usage.record(.windsurfMode, detail: enabled ? "on" : "off")
        // A sheet raised a moment ago is a question about a feature that is now off.
        if !enabled { disciplineReview = nil }
    }
    #else
    let windsurfEnabled = false

    /// Kept so the simulator's `UI_SHEET=discipline` hook compiles in every channel; it can
    /// only ever be reached from a DEBUG simulator build, and here it does nothing.
    func setWindsurfEnabled(_ enabled: Bool) {}
    #endif

    static let riderDisciplineKey = "riderDiscipline"

    /// **Settings → "I mostly ride"**: the preset an imported session gets when its recording
    /// does not say. Wingfoil by default, which is what the engine already fell back to — so
    /// this setting changes nothing at all on a wingfoiler's phone.
    ///
    /// It applies to *future* imports only. The library is not re-derived, and deliberately
    /// not: the rider declaring a habit is not him saying anything about any particular
    /// afternoon, and silently re-reading two years of sessions off a Settings row would be
    /// the app answering a question nobody asked.
    var riderDiscipline: Discipline {
        get { Self.storedRiderDiscipline }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.riderDisciplineKey)
            ingestor.riderDiscipline = newValue
        }
    }

    static var storedRiderDiscipline: Discipline {
        UserDefaults.standard.string(forKey: riderDisciplineKey)
            .flatMap(Discipline.init(rawValue:)) ?? .wingfoil
    }

    /// The batch the review sheet is up for — `RootView` presents it, beside the other
    /// questions the app owns. The ids are the payload; the rows are re-read from the library
    /// as they change, so a picker moved on one row shows the re-derived session underneath.
    struct DisciplineReviewRequest: Identifiable, Sendable {
        let id = UUID()
        let sessionIDs: [String]
    }

    var disciplineReview: DisciplineReviewRequest?

    static let disciplineDismissedKey = "disciplineReviewDismissed.v1"

    /// The sessions he has already skipped past. They keep their `?` on the library row —
    /// nothing was confirmed — but they stop raising a banner, because a banner that comes
    /// back after being dismissed is not a reminder.
    private var dismissedDisciplineIDs: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: SessionStore.disciplineDismissedKey) ?? [])

    /// Everything nobody has confirmed, newest first.
    var disciplineToReview: [SessionRow] {
        DisciplineReview.pending(in: sessions, dismissed: dismissedDisciplineIDs,
                                 windsurfEnabled: windsurfEnabled)
    }

    /// The library's quiet banner: "3 new sessions analysed as Wingfoil".
    ///
    /// The whole of what an *automatic* pickup gets — a Health auto-import, a Strava poll, an
    /// intervals.icu sync at launch. None of those may throw a sheet in front of a rider who
    /// opened the app to look at yesterday's session, and none of them is urgent: the numbers
    /// are right under one preset and re-derivable under another, for ever.
    var disciplineBanner: String? { DisciplineReview.banner(disciplineToReview) }

    /// Raises the sheet for whatever is outstanding — after a rider-initiated import, and when
    /// he taps the banner. Silent when there is nothing to ask, or when another question the
    /// app owns is already on screen: the two must never stack.
    /// True while an *automatic* pickup is running — a Health auto-import, a Strava poll.
    /// Nothing raises a sheet in here: the rider did not ask for these sessions and may not
    /// even have this screen in his hand, and the banner is waiting for him either way.
    private var isAutomaticPickup = false

    /// Runs an import that the rider did not ask for, with the sheet held back.
    func asAutomaticPickup(_ work: () async -> Void) async {
        isAutomaticPickup = true
        await withQuietFailures(work)
        isAutomaticPickup = false
    }

    /// True while something the rider did not ask for is importing — an automatic pickup,
    /// or a recording the Apple Watch sent. Failures inside go to `syncTroubles`, never to
    /// the modal (`runImport`).
    private var quietFailures = false

    func withQuietFailures(_ work: () async -> Void) async {
        let outer = quietFailures
        quietFailures = true
        await work()
        quietFailures = outer
    }

    func raiseDisciplineReview() {
        guard !isAutomaticPickup, disciplineReview == nil, pendingImport == nil,
              pendingReAdd == nil, !isShowingWelcome, !isAskingAboutNewActivities else { return }
        let pending = disciplineToReview
        guard !pending.isEmpty else { return }
        disciplineReview = DisciplineReviewRequest(sessionIDs: pending.map(\.id))
    }

    /// One row's picker. The same call the session page's "Analyse as" card makes, so a
    /// discipline changed here and one changed there are the same act with the same
    /// consequences — and either way the `?` goes, because he has now looked.
    func setReviewDiscipline(_ discipline: Discipline, for row: SessionRow) async {
        guard discipline != row.analysisDiscipline else {
            await confirmDisciplines([row])
            return
        }
        await setDiscipline(discipline, for: row)
    }

    /// "Apply to all N" — the button that makes a bulk import one decision instead of two
    /// hundred. Sequential rather than concurrent: each one re-derives a session from its
    /// archived recording, and a phone asked to do forty at once is a phone that stutters.
    func applyDisciplineToAllInReview(_ discipline: Discipline) async {
        for id in disciplineReview?.sessionIDs ?? [] {
            guard let row = session(id: id) else { continue }
            await setReviewDiscipline(discipline, for: row)
        }
    }

    /// "Confirm" — he has looked at the list and it is right. Nothing is re-analysed; the only
    /// thing that changes is that the app stops marking these sessions as unasked.
    func confirmDisciplineReview() async {
        let rows = (disciplineReview?.sessionIDs ?? []).compactMap { session(id: $0) }
        disciplineReview = nil
        await confirmDisciplines(rows)
    }

    private func confirmDisciplines(_ rows: [SessionRow]) async {
        guard !rows.isEmpty else { return }
        let ingestor = self.ingestor
        do {
            try await Task.detached(priority: .userInitiated) {
                try await ingestor.confirmDiscipline(for: rows)
            }.value
            await load()
        } catch {
            errorMessage = "Could not save that: \(error)"
        }
    }

    /// "Not now". The guesses stand, the `?` stays on the rows, and the banner goes quiet for
    /// these sessions — the session page can still change any of them, for ever.
    func dismissDisciplineReview() {
        dismissedDisciplineIDs.formUnion(disciplineReview?.sessionIDs ?? [])
        disciplineReview = nil
        // Only ids that are still unconfirmed are worth remembering, so the list cannot grow
        // without bound over the life of a library.
        let live = Set(sessions.filter(\.disciplineGuessed).map(\.id))
        dismissedDisciplineIDs.formIntersection(live)
        UserDefaults.standard.set(Array(dismissedDisciplineIDs),
                                  forKey: Self.disciplineDismissedKey)
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
            Usage.record(.backupMade)
        } catch is CancellationError {
            status = "Backup stopped"
        } catch {
            Usage.failed(.backupMade, error: error)
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
        // The one path that is allowed to touch a library this build refused to open, and
        // only now that the rider has picked a file and confirmed it.
        adoptFreshLibraryForRestore()
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
            if summary.failed.isEmpty {
                Usage.record(.backupRestored)
            } else {
                Usage.failed(.backupRestored,
                             reason: String(summary.failed.count) + " would not restore")
            }
            // Capped like every other bulk failure list, and — unlike the old `prefix(5)` —
            // it says how many it is not showing rather than dropping them silently.
            errorMessage = Self.failureAlert(summary.failed)
        } catch is CancellationError {
            status = "Restore stopped — the sessions already restored are in your library"
        } catch {
            Usage.failed(.backupRestored, error: error)
            errorMessage = Self.restoreMessage(error)
        }
        await load()
        // Restored sessions are the rider's own history, not new achievements: a backup
        // must not fire nine personal-best celebrations for records he set last summer.
        await refreshPersonalBests(celebrate: false)
        await writeNewSessionsToHealth()
    }

    /// The failure list of a bulk import, as one alert a rider can actually read.
    ///
    /// A first sync from an account with a year of Garmin in it can hand back seventy-odd
    /// failures — a modal holding all of them is a wall, and the rider learns nothing from
    /// the sixtieth line that he did not learn from the third. So: the first few by name,
    /// then how many more there were. The full list is in the import log either way.
    static func failureAlert(_ failures: [String], showing: Int = 4) -> String? {
        guard !failures.isEmpty else { return nil }
        let shown = failures.prefix(showing).joined(separator: "\n")
        let rest = failures.count - min(showing, failures.count)
        return rest == 0 ? shown : shown + "\n\n…and \(rest) more."
    }

    /// `LibraryRestore.Failure` already carries a sentence written for a rider; anything
    /// else is a surprise and says so in its own words.
    private static func restoreMessage(_ error: any Error) -> String {
        (error as? LibraryRestore.Failure)?.description
            ?? "Could not read that backup: \(error)"
    }

    // MARK: - iCloud Drive (dev channel only — docs/channels.md, ADR-026)

    #if DEV
    /// **Whether this phone shares its library through iCloud Drive** (issue #7).
    ///
    /// Off on a fresh install and off until the rider asks, because it is the one switch in
    /// Settings that writes the whole library somewhere else. Turning it on starts a pass;
    /// turning it off stops syncing and leaves the folder exactly as it is, so the other
    /// device keeps what it already has.
    var iCloudSyncEnabled: Bool = SessionStore.storedICloudSync {
        didSet {
            guard iCloudSyncEnabled != oldValue else { return }
            UserDefaults.standard.set(iCloudSyncEnabled, forKey: Self.iCloudSyncKey)
            if iCloudSyncEnabled {
                syncLibraryNow()
            } else {
                syncPlan = nil
                clearSyncTrouble(.iCloud)
            }
        }
    }

    static let iCloudSyncKey = "icloudSync.enabled.v1"
    static let iCloudSyncLastKey = "icloudSync.lastSync.v1"

    private static var storedICloudSync: Bool {
        UserDefaults.standard.bool(forKey: iCloudSyncKey)
    }

    /// What a pass would do, refreshed when Settings opens and after every pass. nil until
    /// the folder has been looked at once, which is also the honest answer on a phone that
    /// is not signed in to iCloud.
    private(set) var syncPlan: LibrarySyncEngine.Plan?
    private(set) var syncLastAt: Date? = UserDefaults.standard
        .object(forKey: SessionStore.iCloudSyncLastKey) as? Date
    private(set) var syncRunning = false
    /// Set when the container cannot be reached at all — not signed in, or iCloud Drive off.
    private(set) var syncUnavailable = false

    /// The folder this build syncs through: the ubiquity container, or the path a screenshot
    /// run handed it (`UI_SYNC_CONTAINER`, docs/testing.md).
    nonisolated private static func syncContainer() -> LibrarySyncContainer? {
        if let path = ProcessInfo.processInfo.environment["UI_SYNC_CONTAINER"], !path.isEmpty {
            return LibrarySyncContainer(root: URL(fileURLWithPath: path))
        }
        let id = LibrarySyncLayout.containerIdentifier(bundleID: Bundle.main.bundleIdentifier)
        return LibrarySyncContainer.ubiquitous(identifier: id)
    }

    func refreshSyncPlan() async {
        guard iCloudSyncEnabled, !syncRunning else { return }
        let ingestor = self.ingestor
        let plan = await Task.detached(priority: .utility) { () -> LibrarySyncEngine.Plan? in
            guard let container = SessionStore.syncContainer() else { return nil }
            return try? await LibrarySyncEngine(ingestor: ingestor, container: container).plan()
        }.value
        syncUnavailable = plan == nil
        syncPlan = plan
    }

    func syncLibraryNow(riderAsked: Bool = true) {
        guard iCloudSyncEnabled, !syncRunning, !isBusy else { return }
        Task { await runLibrarySync(riderAsked: riderAsked) }
    }

    /// The pass nobody tapped for: at launch and on every return to the foreground, at most
    /// once per `autoSyncInterval`.
    ///
    /// Until 25 Sep 2026 the only triggers were the switch and "Sync now", so a phone used
    /// every day for four days still read "Last sync 21 Sep". ADR-026 promised a folder that
    /// is simply there on the other device, and a sync that waits for a button is not that.
    /// Quiet on purpose: no alert on failure and no status line unless something moved,
    /// because the rider opened the app to look at a session, not at iCloud.
    func syncLibraryIfDue(now: Date = Date()) async {
        guard iCloudSyncEnabled, !syncRunning, !isBusy else { return }
        if let last = syncLastAt, now.timeIntervalSince(last) < Self.autoSyncInterval { return }
        await runLibrarySync(automatic: true, riderAsked: false)
    }

    /// Five minutes: a quick app switch does not cost a pass, a return from the water does.
    static let autoSyncInterval: TimeInterval = 5 * 60

    /// **Never a modal.** Both ways in are on Settings → iCloud Drive, which shows the
    /// failure in place (`ICloudSyncSection`); a dropped connection is retried quietly.
    private func runLibrarySync(automatic: Bool = false, riderAsked: Bool) async {
        syncRunning = true
        isBusy = true
        if !automatic { status = "Syncing with iCloud Drive…" }
        defer {
            syncRunning = false
            isBusy = false
        }
        let ingestor = self.ingestor
        // Detached: `url(forUbiquityContainerIdentifier:)` blocks while the daemon sets the
        // folder up, and the analysis of everything that arrives runs here too.
        let work = Task.detached(priority: .userInitiated) { () -> LibrarySyncEngine.Report? in
            guard let container = SessionStore.syncContainer() else { return nil }
            return try await LibrarySyncEngine(ingestor: ingestor, container: container).sync()
        }
        do {
            guard let report = try await work.value else {
                Usage.failed(.iCloudSync, reason: "iCloud Drive not available")
                syncUnavailable = true
                if !automatic { status = "iCloud Drive is not available" }
                return
            }
            syncUnavailable = false
            Usage.record(.iCloudSync)
            syncLastAt = Date()
            UserDefaults.standard.set(syncLastAt, forKey: Self.iCloudSyncLastKey)
            if !automatic || !report.isEmpty { status = report.shortDescription }
            clearSyncTrouble(.iCloud)
            if !report.isEmpty {
                await load()
                await refreshDerived()
            }
        } catch {
            if !automatic { status = nil }
            Usage.failed(.iCloudSync, error: error)
            reportSync(error, from: .iCloud, riderAsked: riderAsked,
                       retry: quietICloudRetry)
        }
        await refreshSyncPlan()
    }
    #endif

    // MARK: - Map legend

    /// Tapping a legend chip on one map. Kept on the store rather than in a view's `@State`
    /// because a scope's set is read by more than one view — the ride set by the inline map,
    /// the full-screen map, the cinema clip and the speed chart — and a chip that only
    /// convinced the view it lives in would be a bug.
    func toggleMapLayer(_ layer: MapLayer, in scope: MapLayerScope) {
        var visibility = mapLayers(for: scope)
        visibility.toggle(layer)
        mapLayersByScope[scope] = visibility
    }

    /// "Show all" is scoped too: it resets the map the rider is looking at and leaves the
    /// other two exactly as they were set on the maps they belong to.
    func showAllMapLayers(in scope: MapLayerScope) {
        var visibility = mapLayers(for: scope)
        visibility.showAll(in: scope)
        mapLayersByScope[scope] = visibility
    }

    private static func initialMapLayers() -> [MapLayerScope: MapLayerVisibility] {
        var stored: [MapLayerScope: MapLayerVisibility] = [:]
        for scope in MapLayerScope.allCases {
            stored[scope] = MapLayerVisibilityStore.load(scope: scope, from: .standard)
        }
        #if DEBUG && targetEnvironment(simulator)
        // Screenshot hook, same family as `UI_TAB` / `UI_OPEN_SESSION`: `simctl` cannot tap
        // a chip, so `UI_HIDE_LAYERS=fellIn,courseChange` starts the app with those chips
        // off. It deliberately runs *after* the load and is never written back — the
        // override stages a screenshot, it does not edit the rider's preference. It reaches
        // **every** map that draws the named layer, because it is one launch argument and
        // the shot may be of any of the three.
        if let list = ProcessInfo.processInfo.environment["UI_HIDE_LAYERS"] {
            for token in list.split(separator: ",") {
                guard let layer = MapLayer(rawValue: token.trimmingCharacters(in: .whitespaces))
                else { continue }
                for scope in MapLayerScope.allCases where scope.draws(layer) {
                    stored[scope]?.setVisible(false, for: layer)
                }
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
           let wanted = MapStyleChoice.stored(raw) { return wanted }
        #endif
        return stored
    }

    // MARK: - Analysis settings

    static let defaultTurnTypeKey = "defaultTurnType"

    /// The rider's declared turn habit (docs/algorithms/wind.md "Default turn type"), the one
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

    // MARK: - Tuning (dev build only — Settings → Tuning, this phone only)

    #if TUNING
    static let tuningKey = "tuningOverrides.v1"

    /// The rider's tuning overrides — **one set per discipline** (`TuningOverrideSets`),
    /// persisted under the key the single flat set used to live at. A stored v1 flat map is
    /// read as the wingfoil set and re-encoded in the new shape the first time anything is
    /// saved; the decoder owns that rule, so there is one migration and it is written down in
    /// one place.
    ///
    /// Unlike `defaultTurnType`, moving one of these *does* make stored analyses stale — but
    /// only the ones it is about: the fingerprint rides in the analysis' `engineVersion`
    /// inside that discipline's own stamp (`TuningStamp` within `DisciplineStamp`), so the
    /// ordinary lazy sweep — `reanalyzeStale()` on the next launch, and `analysis(for:)` on
    /// the next session opened — re-derives the sessions of *that* rig and leaves the rest
    /// alone. `reanalyzeTuned()` is the same trip taken now, with a count to watch.
    var tuning: TuningOverrideSets {
        get { Self.storedTuning }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Self.tuningKey)
            }
            ingestor.tuning = newValue
        }
    }

    private static var storedTuning: TuningOverrideSets {
        guard let data = UserDefaults.standard.data(forKey: tuningKey),
              let decoded = try? JSONDecoder().decode(TuningOverrideSets.self, from: data)
        else { return TuningOverrideSets() }
        return decoded
    }

    /// Brings the library up to the thresholds currently set — the lazy sweep, run on demand
    /// because a rider who has just moved a slider wants to see what it did, not to relaunch.
    ///
    /// Deliberately `reanalyzeStale` and not `rerunAnalysis`: a row is stale exactly where the
    /// stamp it carries is not the stamp its own discipline's set now produces, so the sweep
    /// re-derives the sessions the moved slider was about and no others — a fin slider costs a
    /// fin session's re-analysis and leaves a hundred wingfoil afternoons untouched. It is
    /// also correct (and cheap) when nothing changed, which is what makes it safe to call on
    /// leaving the page.
    ///
    /// `discipline` is only the *wording*: which set's count the status line reports. The
    /// sweep itself is the library's own per-row question and takes no argument.
    func reanalyzeTuned(for discipline: Discipline = .wingfoil) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        let ingestor = self.ingestor
        let rows = sessions
        let done = await Task.detached(priority: .userInitiated) {
            (try? await ingestor.reanalyzeStale()) ?? 0
        }.value
        Usage.record(.tuning)
        guard done > 0 else {
            status = "Every session is already on these thresholds"
            return
        }
        // Which parts of a track were flown moves with `foilEntrySpeed`, so the cached
        // outlines are stale for exactly the same reason the summaries were.
        for row in rows { thumbnails.invalidate(row.id) }
        let moved = tuning.changedCount(discipline)
        status = "Re-analysed \(done) session\(done == 1 ? "" : "s") "
            + (moved == 0
               ? "with the published \(discipline.title.lowercased()) thresholds"
               : "with \(moved) tuned \(discipline.title.lowercased()) threshold"
                 + "\(moved == 1 ? "" : "s")")
        await load()
        await refreshPersonalBests(celebrate: false)
    }
    #endif

    // MARK: - Apple Health (writing: opt-in, and only ever our own sessions)
    //
    // BOTH DIRECTIONS ARE BETA (docs/channels.md): unproven, off until switched on, and the
    // release channel carries neither the HealthKit entitlement nor the usage strings that
    // would let it ask. `HealthWriter` and `HealthImporter` — the only two files in the
    // project that say `import HealthKit` on the phone — move with this flag.
    #if BETA

    /// Off by default (plan phase 4: "optional Apple Health write").
    var healthWriteEnabled: Bool {
        get {
            access(keyPath: \.healthWriteEnabled)
            return UserDefaults.standard.bool(forKey: "healthWriteEnabled")
        }
        set {
            withMutation(keyPath: \.healthWriteEnabled) {
                UserDefaults.standard.set(newValue, forKey: "healthWriteEnabled")
            }
            if newValue { Task { await enableHealthWriting() } }
        }
    }

    private func enableHealthWriting() async {
        guard await HealthWriter.shared.requestAuthorization() else {
            Usage.failed(.healthExport, reason: "permission not granted")
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
        //
        // Nor is an Apple Watch recording: the watch already saved that workout to Health
        // itself, live, with the heart-rate samples and the ring credit that an
        // after-the-fact `HKWorkoutBuilder` stub cannot give. Writing it again would put two
        // overlapping `.surfingSports` workouts on the same afternoon, and nothing would
        // collapse them — `HKMetadataKeyExternalUUID` carries the watch's session id on one
        // and the library's row id on the other, so they are not even recognisably the same
        // session. The watch's copy is strictly the better one, so the phone stands down.
        //
        // Nor is a workout that *came out of* Health (ADR-017): it is already there, written
        // by whoever recorded it, and our stub would be the second `.surfingSports` workout on
        // the same afternoon — the rider having imported a session in order to be shown it
        // twice, in the one place where getting it wrong leaves a mark outside this app.
        let pending = sessions.filter {
            !exported.contains($0.id) && $0.rider == nil
                && !ImportSource.appleWatch.isNamed(in: $0.importSource)
                && !ImportSource.appleHealth.isNamed(in: $0.importSource)
        }
        guard !pending.isEmpty else { return }
        var written = 0
        for row in pending {
            if await HealthWriter.shared.write(row) {
                exported.insert(row.id)
                written += 1
            }
        }
        // One tally per pass, like an import: every workout Health took, or the count it
        // refused.
        if written == pending.count {
            Usage.record(.healthExport)
        } else {
            Usage.failed(.healthExport,
                         reason: String(pending.count - written) + " not saved by Health")
        }
        UserDefaults.standard.set(Array(exported), forKey: "healthExported")
        if written > 0 {
            status = "Added \(written) workout\(written == 1 ? "" : "s") to Apple Health"
        }
    }

    // MARK: - Apple Health (reading: Apple's own Workout app)

    /// Which Apple workout types the Health import looks at. Surfing + Water Sports until the
    /// rider says otherwise — an empty set is a legal answer and means "offer me nothing".
    var healthWorkoutTypes: Set<HealthWorkoutType> {
        get {
            guard let raw = UserDefaults.standard.stringArray(forKey: Self.healthTypesKey) else {
                return HealthWorkoutType.defaults
            }
            return Set(raw.compactMap(HealthWorkoutType.init(rawValue:)))
        }
        set {
            UserDefaults.standard.set(newValue.map(\.rawValue).sorted(),
                                      forKey: Self.healthTypesKey)
            healthCandidates = []
        }
    }

    static let healthTypesKey = "healthWorkoutTypes"
    static let healthImportedKey = "healthImportedWorkouts"

    /// Workouts already pulled in, by `HKWorkout.uuid`.
    ///
    /// Belt to the dedupe key's braces, and it earns its keep on the case the key cannot see:
    /// a workout the rider imported and then *deleted* from the library. The tombstone keeps
    /// intervals.icu from bringing it back (`SessionIngestor.delete`) and this keeps the
    /// automatic Health pickup from doing the same, silently, an hour later.
    private var importedHealthWorkouts: Set<UUID> {
        get {
            Set((UserDefaults.standard.stringArray(forKey: Self.healthImportedKey) ?? [])
                .compactMap(UUID.init(uuidString:)))
        }
        set {
            UserDefaults.standard.set(newValue.map(\.uuidString).sorted(),
                                      forKey: Self.healthImportedKey)
        }
    }

    /// What Health is offering right now. Empty until the screen asks, and emptied whenever
    /// the type selection changes — a stale list is a list of the wrong sport.
    private(set) var healthCandidates: [HealthWorkoutCandidate] = []
    private(set) var isReadingHealth = false
    /// Set once the permission sheet has been through, so the Import screen can stop leading
    /// with an explainer the rider has already read.
    var hasAskedHealthPermission: Bool {
        get { UserDefaults.standard.bool(forKey: "healthReadAsked") }
        set { UserDefaults.standard.set(newValue, forKey: "healthReadAsked") }
    }

    /// True once a session has actually arrived this way. The automatic pickup is offered only
    /// after this: a toggle for a source the rider has never used is a question about nothing.
    var hasImportedFromHealth: Bool {
        get { UserDefaults.standard.bool(forKey: "healthDidImport") }
        set { UserDefaults.standard.set(newValue, forKey: "healthDidImport") }
    }

    /// "Import new Health workouts automatically" — off until asked for.
    var healthAutoImport: Bool {
        get {
            access(keyPath: \.healthAutoImport)
            return UserDefaults.standard.bool(forKey: "healthAutoImport")
        }
        set {
            withMutation(keyPath: \.healthAutoImport) {
                UserDefaults.standard.set(newValue, forKey: "healthAutoImport")
            }
            guard newValue else { return clearSyncTrouble(.health) }
            Task {
                await watchHealthForNewWorkouts()
            }
        }
    }

    var isHealthAvailable: Bool { HealthImporter.shared.isAvailable }

    /// The permission prompt. HealthKit never reveals a read denial — that is deliberate on
    /// Apple's part — so this reports only that the sheet went through; whether anything was
    /// granted shows up as workouts, or as their absence.
    @discardableResult
    func requestHealthPermission() async -> Bool {
        hasAskedHealthPermission = true
        return await HealthImporter.shared.requestAuthorization()
    }

    /// Reads the workout list Health will show. Cheap: metadata only, no routes.
    func refreshHealthCandidates() async {
        guard isHealthAvailable else { return }
        isReadingHealth = true
        defer { isReadingHealth = false }
        let found = await HealthImporter.shared.candidates(types: healthWorkoutTypes,
                                                           oldest: IcuSyncService.defaultOldest(),
                                                           imported: importedHealthWorkouts)
        healthCandidates = await markAlreadyImported(found)
    }

    /// Second opinion on "already imported", for the workouts the uuid set does not know
    /// about: the same afternoon may have reached the library from intervals.icu first, and
    /// the rider should be told that before he taps rather than after.
    private func markAlreadyImported(_ list: [HealthWorkoutCandidate])
    async -> [HealthWorkoutCandidate] {
        var out: [HealthWorkoutCandidate] = []
        out.reserveCapacity(list.count)
        for var candidate in list {
            if !candidate.isAlreadyImported,
               let held = try? await ingestor.holdsSession(startDate: candidate.start,
                                                           durationS: candidate.durationS) {
                candidate.isAlreadyImported = held
            }
            out.append(candidate)
        }
        return out
    }

    /// Fetches each workout's route and heart rate, maps them, and sends the bytes through the
    /// ordinary import door — same `SessionIngestor`, same ±60 s dedupe, same archive.
    ///
    /// A workout Health kept no positions for is *skipped with a reason*, not failed: an
    /// indoor session, a watch that never got a fix and a rider who denied location all land
    /// here, and none of them is an error worth an alert.
    func importFromHealth(_ ids: [UUID]) async {
        guard !ids.isEmpty, !isBusy, !isReadingHealth else { return }
        isReadingHealth = true
        status = "Reading \(ids.count) workout\(ids.count == 1 ? "" : "s") from Health…"

        var payloads: [DiscoveredFit] = []
        var routeless = 0
        let version = Self.appVersion
        var read: [UUID] = []
        for id in ids {
            do {
                let made = try await HealthImporter.shared.container(for: id, appVersion: version)
                payloads.append(DiscoveredFit(name: made.name, data: made.data))
                read.append(id)
            } catch {
                routeless += 1
            }
        }
        isReadingHealth = false

        guard !payloads.isEmpty else {
            if routeless > 0 { Usage.failed(.importHealth, reason: "no GPS route") }
            status = routeless > 0
                ? "No GPS route in \(routeless == 1 ? "that workout" : "those workouts")"
                : nil
            return
        }
        let summary = await runImport(payloads, source: .appleHealth)
        // Remembered whatever the outcome: a duplicate is still a workout that has been
        // through here, and re-offering it every time the screen opens would be the app
        // failing to remember its own answer.
        importedHealthWorkouts.formUnion(read)
        if summary.imported > 0 { hasImportedFromHealth = true }
        status = Self.healthImportMessage(summary, routeless: routeless)
        await refreshHealthCandidates()
    }

    /// The banner. Names Apple Health rather than reading "1 imported", because a session that
    /// appeared without the rider touching a file needs to say where it came from.
    static func healthImportMessage(_ summary: ImportSummary, routeless: Int) -> String? {
        var parts: [String] = []
        if summary.imported > 0 {
            parts.append("\(summary.imported) session\(summary.imported == 1 ? "" : "s") "
                         + "imported from Apple Health")
        }
        if summary.duplicates > 0 {
            parts.append("\(summary.duplicates) already in your library")
        }
        if routeless > 0 { parts.append("\(routeless) with no GPS route") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Launch, foreground, and an observer wake: whatever Health has that the library does not.
    ///
    /// Silent by construction on the ordinary pass, where there is nothing new — no status, no
    /// permission prompt, no work beyond one metadata query.
    func checkHealthForNewWorkouts() async {
        guard healthAutoImport, isHealthAvailable, !isBusy, !isReadingHealth else { return }
        let found = await HealthImporter.shared.candidates(types: healthWorkoutTypes,
                                                           oldest: IcuSyncService.defaultOldest(),
                                                           imported: importedHealthWorkouts)
        let fresh = await markAlreadyImported(found).filter { !$0.isAlreadyImported }
        guard !fresh.isEmpty else { return }
        // Nobody asked for these, so nothing about them may land in front of whatever the
        // rider is looking at — the library's banner is where they announce themselves
        // (see "Discipline on import").
        await asAutomaticPickup { await importFromHealth(fresh.map(\.id)) }
    }

    /// Registers the HealthKit observer and sweeps once.
    ///
    /// **The sweep is the reliable half.** Background delivery needs an entitlement the manual
    /// App Store profile does not carry today and, even where it is granted, iOS decides when a
    /// background app runs and may hold a delivery for hours. So this app never waits for one:
    /// the check at launch and at every foreground is what actually gets the session in, and
    /// the observer only shortens the wait when it works.
    func watchHealthForNewWorkouts() async {
        guard healthAutoImport, isHealthAvailable else { return }
        if !isObservingHealth {
            isObservingHealth = true
            await HealthImporter.shared.observeNewWorkouts { [weak self] in
                Task { @MainActor in await self?.checkHealthForNewWorkouts() }
            }
        }
        await checkHealthForNewWorkouts()
    }

    /// One observer per launch. `HKObserverQuery` is cheap but not free, and registering a
    /// second on every foreground would multiply the wake-ups the rider's battery pays for.
    private var isObservingHealth = false

    #else

    /// The release channel's Apple Health surface: nothing, said three ways. `false` rather
    /// than an absent property because the feedback mail reports the pickup state of every
    /// source it knows about, and "off" is the honest answer for a build that has no door.
    var healthAutoImport: Bool { false }
    /// Called from four import paths that are not about Health at all (a sync, a restore, a
    /// background wake, a Strava pull); a no-op beats four `#if BETA` islands inside them.
    func writeNewSessionsToHealth() async {}
    func checkHealthForNewWorkouts() async {}
    func watchHealthForNewWorkouts() async {}

    #endif

    // MARK: - intervals.icu

    /// `riderAsked` is false for the one sync the app starts by itself, the empty library's
    /// first fill at launch. That one never raises the modal and retries quietly.
    func syncFromIntervals(riderAsked: Bool = true) async {
        guard !isBusy else { return }
        reloadApiKeyIfMissing()
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
        // only thing that writes it, and only pull-to-refresh, Import → "Sync
        // intervals.icu", a pull on the list and the empty library's own button
        // reach this method. The background poller never does.
        let previousSync = lastSyncDate
        let startedAt = Date()
        defer { isBusy = false }

        let ingestor = self.ingestor
        let oldest = IcuSyncService.defaultOldest()
        // **The rider is told which file of how many is on the wire.** A first sync from an
        // account with a year of Garmin in it downloads and analyses seventy-odd
        // recordings, which is minutes; a screen that says "Contacting intervals.icu…" for
        // all of them is indistinguishable from a hung app, and gets reported as one. The
        // service already narrates every step — it simply had nobody listening.
        //
        // Relayed rather than captured, exactly like the import and backup progress above:
        // `sync` calls this from whatever thread the download finished on, and `status`
        // belongs to the main actor. A closure that merely *looks* main-actor compiles and
        // then dies in `dispatch_assert_queue` the first time a framework calls it
        // elsewhere, which is how build 16 crashed.
        //
        // `live` closes the door on the way out: the last relayed line is delivered on a
        // main-actor hop, and without it a late hop could land *after* this method has put
        // the summary (or an error's nil) on screen and overwrite it with "Downloading
        // 74/74…".
        let live = LiveFlag()
        let relay = Relay<String> { [weak self] line in
            Task { @MainActor in
                guard live.isLive else { return }
                self?.status = line
            }
        }
        defer { live.close() }
        do {
            let summary = try await Task.detached(priority: .userInitiated) {
                let service = IcuSyncService(client: IcuClient(apiKey: key), ingestor: ingestor)
                return try await service.sync(oldest: oldest) { relay.send($0) }
            }.value
            live.close()                       // no more progress lines past this point
            status = summary.shortDescription
            await offerReAddIfAsked(summary, previousSync: previousSync, startedAt: startedAt)
            // A sync can succeed and still leave the library empty (Garmin not connected
            // in intervals.icu yet). That is a cause the empty library names, not a crash.
            setProblem(IcuDiagnosis.describe(summary))
            clearSyncTrouble(.intervals)
            if riderAsked { errorMessage = Self.failureAlert(summary.failed) }
            Usage.recordImport(.icu, imported: summary.imported,
                               failed: summary.failed.count)
            lastSyncDate = Date()
            lastCheckAt = Date()
        } catch {
            let problem = IcuDiagnosis.describe(error)
            setProblem(problem)
            status = nil
            Usage.failed(.importIcu, error: error)
            let kind = reportSync(error, from: .intervals, riderAsked: riderAsked,
                                  retry: riderAsked ? nil : quietIntervalsRetry)
            // A dropped connection is never a modal, even under the rider's own pull: the
            // spinner stops, the status line says it, the footer keeps it. He pulls again.
            if kind == .transient {
                if riderAsked {
                    status = "Could not reach intervals.icu. Check your connection and pull again."
                }
            } else if riderAsked, !sessions.isEmpty {
                // On an empty library the problem note already carries this cause *and* its
                // fix, in place. A modal on top of it is the same sentence twice.
                errorMessage = problem.alertText
            }
        }
        await load()
        // intervals.icu knows no wingfoil either, so a sync is a batch of guesses like any
        // other. Only the rider's own pull reaches this method — the background poller never
        // does — so this is a question he is standing in front of.
        raiseDisciplineReview()
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
            Usage.record(.restoreDeleted)
        } catch {
            Usage.failed(.restoreDeleted, error: error)
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
            Usage.record(.restoreDeleted)
        } catch {
            Usage.failed(.restoreDeleted, error: error)
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
        get {
            access(keyPath: \.notifyOnNewActivities)
            return UserDefaults.standard.bool(forKey: ActivityNotifier.enabledKey)
        }
        set {
            withMutation(keyPath: \.notifyOnNewActivities) {
                UserDefaults.standard.set(newValue, forKey: ActivityNotifier.enabledKey)
            }
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

    /// **"Has this key ever actually fetched anything?"**
    ///
    /// A key in the keychain is not a working key: `saveAndCheckApiKey` stores it and then
    /// asks intervals.icu, and the one-time offer used to fire on the store. Three answers
    /// count as proof, in the order they become available — the check that just came back
    /// green, a sync that has completed before, and a library that plainly arrived from
    /// somewhere. The last two are what keeps an existing install's offer reachable at
    /// launch, where `keyCheck` is nil because nothing has been asked yet.
    private var keyIsProven: Bool {
        if case .success = keyCheck { return true }
        return lastSyncDate != nil || !sessions.isEmpty
    }

    /// Asked at every plausible moment — launch, foreground, a key that was just proved, a
    /// sheet that just closed — and answered by the pure predicate, which says yes at most
    /// once per install and only once the key exists and has been proved.
    func askAboutNewActivitiesIfNeeded() {
        guard NewActivityPrompt.shouldAsk(
            hasKey: !apiKey.isEmpty,
            isEnabled: notifyOnNewActivities,
            hasAsked: UserDefaults.standard.bool(forKey: ActivityNotifier.promptedKey),
            keyIsProven: keyIsProven,
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
            // Through `withMutation`, so the switch that was just turned on turns itself
            // back off on screen rather than showing on with nothing behind it.
            withMutation(keyPath: \.notifyOnNewActivities) {
                UserDefaults.standard.set(false, forKey: ActivityNotifier.enabledKey)
            }
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

    /// **"The welcome is owed, whatever the rest of this phone looks like."**
    ///
    /// Written by `startOver()` *after* the wipe and read by `showWelcomeIfNeeded()` before
    /// anything else, then cleared the moment the screen goes up. It exists because every
    /// other part of the first-run rule is an argument from absence — no `welcomeShown.v1`,
    /// no sessions — and Start over cannot hand an absence to the next launch: the screen it
    /// raises in-process writes the flag again, a session arriving from anywhere makes the
    /// library look like a history, and `shouldMarkSeenSilently` then marks the screen seen
    /// on sight. That is what Jan saw in build 63: Start over, relaunch, and the app opened
    /// on Sessions. A request is a *positive* fact the wipe itself leaves behind, so nothing
    /// that happens afterwards can talk it out of the screen.
    static let welcomeRequestedKey = "welcomeRequested.v1"

    /// True while `WelcomeView` is up. `RootView` presents it; whether it is owed at all is
    /// `WelcomePrompt`, in the kit.
    private(set) var isShowingWelcome = false

    #if DEBUG && targetEnvironment(simulator)
    /// Whether `UI_WELCOME` has already staged its one screen this launch.
    private var didStageWelcome = false
    #endif

    /// Whether the welcome already went up in this process. Once per launch, not once per
    /// install (Jan's plan of 24 September 2026, section 7): the screen comes back on the
    /// next launch for as long as the library has nothing of the rider's own in it.
    private var didShowWelcomeThisLaunch = false

    /// Asked at every moment the answer can change — launch, foreground, a sheet that just
    /// closed — and answered by the pure predicate: every launch, until there is a real
    /// session or intervals.icu is connected.
    func showWelcomeIfNeeded() {
        // Nothing may be decided from a library that has not been read: an empty `sessions`
        // at launch means "still loading" for the first fraction of a second, and greeting
        // a rider with three seasons in the database because the query had not come back
        // yet is the one failure this screen must not have. A read that *failed* leaves
        // this false as well — then the app has an error banner to show, not a welcome.
        guard hasLoadedLibrary else { return }
        #if DEBUG && targetEnvironment(simulator)
        // Screenshot hook, same family as `UI_TAB` / `UI_LOAD_EXAMPLE`: `UI_WELCOME=1`
        // raises the screen whatever the library and the key say. Once per launch, like
        // the real rule, so the example button's own session is not covered again.
        if ProcessInfo.processInfo.environment["UI_WELCOME"] == "1", !didStageWelcome {
            didStageWelcome = true
            didShowWelcomeThisLaunch = true
            isShowingWelcome = true
            return
        }
        #endif
        // **The request comes first.** Start over writes it down (`welcomeRequestedKey`),
        // and it outranks the library and the key: a phone whose sessions are back —
        // synced, transferred or re-imported — still gets the screen it asked for.
        let requested = UserDefaults.standard.bool(forKey: Self.welcomeRequestedKey)
        // The example is ours, not the rider's, so it does not count as his history.
        let realSessions = sessions.filter { !$0.isExample && $0.isSession }.count
        guard WelcomePrompt.shouldShow(realSessionCount: realSessions,
                                       icuConnected: !apiKey.isEmpty,
                                       shownThisLaunch: didShowWelcomeThisLaunch,
                                       isPresenting: isPresentingSomething,
                                       requested: requested)
        else { return }
        // Still written, for the Beta section's list of what Start over clears and for any
        // older build a phone goes back to; nothing in this build reads it.
        UserDefaults.standard.set(true, forKey: Self.welcomeShownKey)
        // Spent when the screen goes up, and only then — a deferral leaves the request
        // standing, so a Start over the rider walked away from still greets him next launch.
        UserDefaults.standard.removeObject(forKey: Self.welcomeRequestedKey)
        didShowWelcomeThisLaunch = true
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

    /// Every way off the screen — the X, the example, and the cover's own dismissal.
    func dismissWelcome() {
        isShowingWelcome = false
    }

    /// Bumped by *Getting started → Open CleanJibe Settings* when that page was opened from
    /// the welcome: the cover closes, and the Sessions screen, which owns the Settings
    /// sheet, opens it (`LibraryView`).
    private(set) var settingsRequest = 0

    /// Close the welcome and open Settings, where the four intervals.icu steps are.
    func requestSettings() {
        isShowingWelcome = false
        settingsRequest += 1
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

    /// The one bit of `keyCheck` `RootView` watches, so the notification offer is re-asked
    /// the instant a key comes back green rather than one unrelated redraw later.
    var keyCheckSucceeded: Bool {
        if case .success = keyCheck { return true }
        return false
    }
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
        reloadApiKeyIfMissing()
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
            clearSyncTrouble(.intervals)
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
        let failures = await Task.detached(priority: .userInitiated) { () -> Int in
            ingestor.dropAllAnalyses()
            var failures = 0
            for row in rows {
                do { _ = try await ingestor.reanalyze(row) } catch { failures += 1 }
            }
            return failures
        }.value
        if failures == 0 {
            Usage.record(.reanalysis)
        } else {
            Usage.failed(.reanalysis, reason: String(failures) + " would not re-analyse")
        }
        status = "Re-analysed \(rows.count) session\(rows.count == 1 ? "" : "s") "
            + "with engine \(AnalysisEngine.version)"
        // Which parts of a track were flown can change with the engine, so the cached
        // outlines are stale by construction.
        for row in rows { thumbnails.invalidate(row.id) }
        await load()
        await refreshPersonalBests(celebrate: false)
    }

    // MARK: - Companion link (phase 5)
    //
    // DEV ONLY (docs/channels.md). Garmin Connect Mobile owns the Bluetooth link and the
    // link has no real sessions behind it yet, so the release and beta binaries hold no
    // companion object, no ConnectIQ framework and no watch map. The kit's `CompanionLink`
    // protocol is compiled in every channel; only this half of it moves with the flag.
    #if DEV

    /// The watch link. Concrete rather than `any CompanionLink` because the app is also
    /// the only place that does the two things the protocol deliberately leaves out —
    /// sending the rider to Garmin Connect to pick a watch, and reading the answer back
    /// off a URL. Everything else goes through the protocol, which is what keeps the
    /// payload rules testable in WingFoilKit with no framework in sight.
    let companion = ConnectIQCompanionLink()
    private(set) var companionState: CompanionLinkState = .noDevice
    #if DEV
    /// What the last link-probe page looked like when it arrived (docs/direct-transfer.md).
    var lastLinkProbe: String? { linkProbeLine ?? companion.lastProbe }
    var linkProbeLine: String?
    #endif
    /// When the last card arrived. The settings row shows it, because "it says ready" and
    /// "something has actually come through" are different facts.
    ///
    /// **Observed by hand.** `@Observable` tracks stored properties only, so a computed
    /// property over UserDefaults that a view reads calls `access` and `withMutation`
    /// itself, or its row keeps drawing the old value (Jan, dev 106: the Wind from picker).
    /// The same two calls sit on every such property a Settings row shows or binds.
    var lastCardAt: Date? {
        get {
            access(keyPath: \.lastCardAt)
            return UserDefaults.standard.object(forKey: "lastCompanionCard") as? Date
        }
        set {
            withMutation(keyPath: \.lastCardAt) {
                UserDefaults.standard.set(newValue, forKey: "lastCompanionCard")
            }
        }
    }

    /// The watch build tag off the last card (`CompanionSummary.appVersion`,
    /// `APP_MINOR * 256 + FIT schema`), or nil when none has ever arrived.
    ///
    /// Remembered for one reader — the beta feedback mail, which answers "which watch build
    /// produced these numbers" without asking the rider to go and look. The link itself
    /// cannot say: it knows which watch is paired, not what is installed on it, and the card
    /// is the only thing that ever says so out loud.
    var lastCardWatchAppVersion: Int? {
        get { UserDefaults.standard.object(forKey: "lastCompanionCardApp") as? Int }
        set { UserDefaults.standard.set(newValue, forKey: "lastCompanionCardApp") }
    }

    /// The wind the rider last pushed, remembered so the next push starts where the last
    /// one left off (the wind at a spot rarely changes by 180° between sessions).
    ///
    /// **A stored property, not a computed one over UserDefaults** (Jan, dev 106: "Wind
    /// from cannot be set"). `@Observable` tracks stored properties only: the computed
    /// version wrote the pick to the defaults and told no view, so the Picker drew the old
    /// value again and the choice looked refused. Same shape as `replayCommentary`.
    var windToSend: Int = SessionStore.storedWindToSend {
        didSet {
            guard windToSend != oldValue else { return }
            UserDefaults.standard.set(windToSend, forKey: Self.windToSendKey)
        }
    }

    static let windToSendKey = "windToSend"

    private static var storedWindToSend: Int {
        UserDefaults.standard.object(forKey: windToSendKey) as? Int ?? 225
    }

    #endif

    // MARK: - Apple Watch recordings

    /// Starts listening for `.cjw` containers from the CleanJibe watch app and imports
    /// anything already waiting.
    ///
    /// Called once at launch. The receiver may have taken delivery of a file hours ago while
    /// this app was not running — WatchConnectivity launches it in the background to do that
    /// — so the sweep runs unconditionally rather than only on an arrival.
    func watchForAppleWatchSessions() async {
        WatchSessionReceiver.shared.onArrival = { [weak self] in
            Task { await self?.importWatchInbox() }
        }
        WatchSessionReceiver.shared.activate()
        await importWatchInbox()
    }

    /// Imports every container sitting in the watch inbox, then deletes it.
    ///
    /// Deleting only after `importFiles` has returned is deliberate: the file is the only
    /// copy on this device, and the library's own dedupe (±60 s on start and duration) makes
    /// importing the same container twice cost nothing. Losing it costs an afternoon.
    private func importWatchInbox() async {
        let pending = WatchSessionReceiver.pending()
        guard !pending.isEmpty else { return }
        // `.appleWatch`, never `.watch` — that one is the Garmin BLE card, and a row tagged
        // with it would claim a provenance this session does not have.
        await withQuietFailures { _ = await importFiles(urls: pending, source: .appleWatch) }
        for url in pending { try? FileManager.default.removeItem(at: url) }
    }

    #if DEV

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
            lastCardWatchAppVersion = card.appVersion
            clearSyncTrouble(.watch)
            await load()
        } catch {
            // Nobody is waiting on a card: it arrives while the rider looks at something
            // else. The footer says it, and the next card or recording tries again.
            reportSync(.other(detail: "could not store the session card"), from: .watch,
                       riderAsked: false)
        }
    }

    // MARK: The direct transfer

    /// What the last session the watch sent straight over looked like
    /// (docs/transfer-format.md §5). Nil until one has arrived.
    var lastDirectTransfer: DirectTransferReceipt? { DirectTransferInbox.shared.lastReceipt }
    /// The last page the inbox took or refused, as the Settings row shows it.
    var directPageLine: String?
    /// The last answer the phone sent the watch, ack or need list, and whether it left.
    var directAnswerLine: String?

    /// Starts taking delivery of direct transfers and imports anything already waiting.
    ///
    /// Called once at launch, unconditionally, for the same reason the Apple Watch sweep is:
    /// a stream may have completed while this app was killed between two pages, and the file
    /// it became is still on disk. The stale sweep runs in the same pass — a transfer the
    /// rider walked away from is imported a day later as far as it got.
    func watchForDirectTransfers() async {
        DirectTransferInbox.shared.onArrival = { [weak self] in
            Task { await self?.importDirectInbox() }
        }
        DirectTransferInbox.shared.onPage = { [weak self] line in
            self?.directPageLine = line
        }
        companion.onProbe = { [weak self] line in
            self?.linkProbeLine = line
        }
        companion.onDirectAnswer = { [weak self] line in
            self?.directAnswerLine = line
        }
        DirectTransferInbox.shared.sweepStaleStreams()
        await importDirectInbox()
    }

    /// Imports every assembled stream in the inbox, then deletes it.
    ///
    /// Deleting only after `importFiles` returns is deliberate: the file is the only copy on
    /// this device, and the library's own ±60 s dedupe makes importing one twice cost
    /// nothing. Losing it costs an afternoon.
    private func importDirectInbox() async {
        let pending = DirectTransferInbox.pending()
        guard !pending.isEmpty else { return }
        // `.watchDirect`, never `.watch` — that one is the summary card, and a row tagged
        // with it would claim a provenance this session does not have.
        let summary = await importFiles(urls: pending, source: .watchDirect)
        // A stream the import refused is kept, not retried: the first real one
        // (19 September 2026) was dropped as "no FIT found" by a classifier that did not
        // know the format, and deleting it would have cost the session for good — while
        // retrying it at every launch put the same dialog up at every launch. It moves to
        // `refused/`, where a later build can still find it and the feedback mail can name it.
        for url in pending {
            let name = url.lastPathComponent
            if summary.failed.contains(where: { $0.hasPrefix(name) }) {
                DirectTransferInbox.setAside(url)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
        await attachPendingWristStreams()
    }

    /// **The wrist stream, landing after its session.**
    ///
    /// Stream 1 is not a recording and never becomes a row of its own: it is the 25 Hz
    /// magnitudes of the session that crossed before it (docs/transfer-format.md §6,
    /// ADR-031). So it is matched to the row by the same ±60 s start-epoch key the rest of
    /// the direct transfer uses (ADR-013) and handed to `attachWristStream`, which files it
    /// beside the archived original and re-derives — the pump, takeoff, turn-pump and
    /// HR-cost answers that read nil without an accelerometer stop reading nil.
    ///
    /// A stream whose session is not here is **left in the inbox**, not refused: the pages
    /// may simply have outrun the record stream's import, and the next launch tries again.
    private func attachPendingWristStreams() async {
        let waiting = DirectTransferInbox.pendingWrist()
        guard !waiting.isEmpty else { return }
        for (session, url) in waiting {
            guard let data = try? Data(contentsOf: url) else { continue }
            let start = Date(timeIntervalSince1970: Double(session))
            guard let row = try? await ingestor.session(nearStart: start) else { continue }
            do {
                if try await ingestor.attachWristStream(data, to: row) != nil {
                    try? FileManager.default.removeItem(at: url)
                    await load()
                } else {
                    // The row is there and the stream does not belong to it — a FIT took the
                    // afternoon over, or the bytes will not decode. Either way it is never
                    // going to attach, so it goes to `refused/` rather than round again.
                    DirectTransferInbox.setAside(url)
                }
            } catch {
                // Left in the inbox, so the next sweep tries again. No modal: this runs by
                // itself, and the footer carries it.
                reportSync(.other(detail: "could not attach the wrist stream"), from: .watch,
                           riderAsked: false)
            }
        }
    }

    func refreshCompanionState() {
        companion.refresh()
        companionState = companion.state
    }

    /// Hands over to Garmin Connect; the answer comes back through `handleCompanionURL`.
    /// Counted as a try here and as its outcome in `handleCompanionURL`, when Garmin
    /// Connect hands the choice back. A try with no answer is the rider who never returned.
    func chooseWatch() {
        Usage.started(.chooseWatch)
        companion.chooseDevice()
    }

    func forgetWatch() {
        companion.forgetDevice()
        companionState = companion.state
        Usage.record(.chooseWatch, detail: "forget")
    }

    /// True when the URL was Garmin Connect returning the rider's device choice — so the
    /// app entry point knows not to try importing it as a FIT.
    func handleCompanionURL(_ url: URL) -> Bool {
        guard companion.handle(url: url) else { return false }
        companionState = companion.state
        Usage.finished(.chooseWatch, failure: companionState.canSend ? nil : "no watch chosen",
                       detail: "choose")
        status = companionState.headline
        return true
    }

    // MARK: The map snapshot

    /// Which maps the rider asked the watch to hold (`WatchMapChoice`). Empty means
    /// automatic — the two most-ridden spots, which is what every install had before there
    /// was a picker and what a rider who never opens the page keeps having.
    private(set) var watchMapChoice = WatchMapChoice.load(from: .standard)

    /// The picker's one write. Saved on the spot: "which ground goes to my watch" is a
    /// fact about the rider, not about this launch.
    func setWatchMapChoice(_ choice: WatchMapChoice) {
        watchMapChoice = choice
        choice.save(to: .standard)
    }

    /// Where the phone was standing the last time it was asked — never persisted, because
    /// "here" is a fact with a shelf life of an afternoon and a stale one on the next
    /// launch would draw the watch a map of the car park at home.
    private var lastPhoneFix: (lat: Double, lon: Double)?

    /// The one place in the app that asks Core Location anything. One fix, on a tap.
    private let phoneLocation = PhoneLocation()

    /// Whether the phone would answer "where am I" without a prompt. The picker reads it
    /// after a tap to tell "denied" from "no sky yet".
    var phoneLocationIsAuthorized: Bool { phoneLocation.isAuthorized }

    /// Ask the phone where it is, once, prompting if it has never been asked. True when a
    /// fix came back. The picker calls this on the tap that adds "Where I am now", so the
    /// permission sheet appears under the finger that asked for it.
    @discardableResult
    func refreshPhoneFix() async -> Bool {
        guard let fix = await phoneLocation.current() else { return false }
        lastPhoneFix = fix
        return true
    }

    /// The fix a send needs, if the send needs one. `mayPrompt` is the whole difference
    /// between the button and the launch: a manual send may put a permission sheet on the
    /// screen because the rider just pressed something, the automatic pass may never.
    private func refreshPhoneFixIfPicked(mayPrompt: Bool) async {
        guard watchMapChoice.contains(.here) else { return }
        guard mayPrompt || phoneLocation.isAuthorized else { return }
        await refreshPhoneFix()
    }

    /// The maps the watch would get, in order: what the settings row names and what the
    /// sender draws, so the rider can see *which* ground he is about to send.
    var watchMapTargets: [WatchMapTarget] {
        WatchMapChoice.resolve(watchMapChoice, spots: spots, here: lastPhoneFix,
                               limit: WatchMapSender.slots)
    }

    /// The automatic pair as library rows — the headless `UI_SEND_WATCH_MAP` probe's view
    /// of the world, which is about whether MapKit can draw a spot at all and therefore
    /// wants the spots and not the rider's choice.
    var watchMapSpots: [SpotAggregate] { WatchMapSender.targets(from: spots) }

    /// The last send's one line — "sent 2.1 KB · 14:02", "Already on the watch · 14:02", or
    /// the failure. Kept in defaults so the row still says something after a relaunch: the
    /// question it answers ("did that work?") outlives the process that answered it.
    private(set) var watchMapStatus: String? =
        UserDefaults.standard.string(forKey: "watchMap.lastResult")
    /// True while MapKit is drawing. Two snapshots on a cold tile cache take a second or
    /// two, which is long enough that a row with no spinner reads as a dead button.
    private(set) var isSendingWatchMap = false

    /// The manual "Send map to watch" button: renders both spots and pushes them whether or
    /// not this watch already has them, because the rider asked to see it happen.
    func sendMapsToWatch() async {
        await refreshPhoneFixIfPicked(mayPrompt: true)
        await sendMaps(force: true)
    }

    /// The automatic half: at launch and after every import, push only what this watch does
    /// not already have. Silent — no status line, no banner — because the answer is
    /// "nothing to do" almost every time, and a row that announces that on every launch is
    /// a row the rider learns to stop reading.
    func refreshWatchMapIfNeeded() async {
        refreshCompanionState()
        guard companionState.canSend, let deviceKey = companion.deviceKey else { return }
        // Never a prompt on this path: a permission sheet at launch for a feature nobody
        // opened would be the app begging. With "Where I am now" ticked and location
        // already granted the fix is refreshed here; otherwise that pick simply does not
        // resolve and the other map still goes.
        await refreshPhoneFixIfPicked(mayPrompt: false)
        let targets = watchMapTargets
        guard !targets.isEmpty,
              WatchMapSender.automaticPassIsWorthIt(targets: targets, deviceKey: deviceKey,
                                                    in: .standard)
        else { return }
        await sendMaps(force: false, quiet: true)
        // Remembered only when nothing went wrong: a failed render must be retried at the
        // next launch, not written off as "already handled".
        if watchMapFailed == false {
            WatchMapSender.rememberAutomaticPass(targets: targets, deviceKey: deviceKey,
                                                 in: .standard)
        }
    }

    /// Whether the last pass hit anything. Kept apart from `watchMapStatus`, which is a
    /// sentence for a person to read.
    private var watchMapFailed = false

    private func sendMaps(force: Bool, quiet: Bool = false) async {
        guard !isSendingWatchMap else { return }
        isSendingWatchMap = true
        defer { isSendingWatchMap = false }
        if !quiet { status = "Drawing the map…" }
        let report = await WatchMapSender.send(
            targets: watchMapTargets, through: companion, force: force,
            progress: { name in if !quiet { self.status = "Drawing \(name)…" } })
        watchMapFailed = report.failure != nil
        // Delivered means Connect IQ reported the message delivered: `sent` only fills on
        // that answer. The failure sentence names a spot, so the tally keeps a fixed reason.
        if report.failure != nil {
            Usage.failed(.mapToWatch, reason: "not delivered")
        } else if report.didSomething {
            Usage.record(.mapToWatch, detail: quiet ? "automatic" : "by hand")
        }
        // A quiet pass that did nothing leaves the row exactly as it was: only a send or a
        // failure is news.
        guard !quiet || report.didSomething || report.failure != nil else { return }
        let line = report.line(at: Date())
        watchMapStatus = line
        UserDefaults.standard.set(line, forKey: "watchMap.lastResult")
        if let failure = report.failure, !quiet { errorMessage = failure }
        if !quiet { status = line }
        refreshCompanionState()
    }

    /// Manual by decision (docs/decisions.md ADR-013): an automatic push needs this app
    /// awake at the moment a session starts, and a wind axis that lands mid-session
    /// relabels every turn before it. Automatic can come once the link is proven on water.
    func sendWindToWatch(_ degreesFrom: Int) async {
        do {
            try await companion.sendWind(degreesFrom: degreesFrom)
            Usage.record(.windToWatch)
            windToSend = degreesFrom
            status = degreesFrom == CompanionWind.clear
                ? "Wind direction cleared on the watch"
                : "Sent \(degreesFrom)° to the watch"
        } catch let error as CompanionLinkError {
            Usage.failed(.windToWatch, error: error)
            errorMessage = error.riderMessage
        } catch {
            Usage.failed(.windToWatch, error: error)
            errorMessage = "Could not send the wind direction: \(error)"
        }
        refreshCompanionState()
    }

    #else

    /// The release and beta channels have no watch map to push, but the three import paths
    /// that used to offer one call this in the middle of unrelated work — a no-op here is
    /// one line against three `#if DEV` islands in code that has nothing to do with Garmin.
    func refreshWatchMapIfNeeded() async {}

    #endif

    // MARK: - Strava

    /// Which Strava activity types the Import screen offers (`StravaActivityType`).
    ///
    /// Strava has no wingfoil type, so there is nothing to infer: the rider says once what he
    /// files his sessions under, and it is remembered. Defaults are Windsurf, Kitesurf, Surf,
    /// Workout and Stand-up paddling — the five buckets wingfoil sessions actually land in.
    var stravaTypes: Set<StravaActivityType> {
        get {
            guard let stored = UserDefaults.standard.stringArray(forKey: Self.stravaTypesKey)
            else { return StravaActivityType.defaults }
            return Set(stored.compactMap(StravaActivityType.init(rawValue:)))
        }
        set {
            UserDefaults.standard.set(newValue.map(\.rawValue).sorted(),
                                      forKey: Self.stravaTypesKey)
            stravaCandidates = []
        }
    }

    static let stravaTypesKey = "stravaActivityTypes"
    static let stravaImportedKey = "stravaImportedActivities"
    static let stravaAutoKey = "stravaAutoImport"
    static let stravaDidImportKey = "stravaDidImport"

    /// Strava activity ids already pulled in.
    ///
    /// Belt to the ±60 s dedupe key's braces, and it earns its keep on the case the key
    /// cannot see: an activity the rider imported and then *deleted*. The tombstone stops the
    /// sync bringing it back; this stops the app asking Strava about it again on every open.
    private var importedStravaActivities: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.stravaImportedKey) ?? []) }
        set {
            UserDefaults.standard.set(newValue.sorted(), forKey: Self.stravaImportedKey)
        }
    }

    /// What Strava is offering right now. Empty until the screen asks, and emptied whenever
    /// the type selection changes — a stale list is a list of the wrong sport.
    private(set) var stravaCandidates: [StravaCandidate] = []
    private(set) var isReadingStrava = false
    /// The connected athlete's name, when there is a connection. nil is "not connected", and
    /// it is read straight off the stored tokens so the UI and the keychain cannot disagree.
    private(set) var stravaAthlete: String?
    private(set) var isStravaConnected = false
    /// Set when Strava granted a narrower scope than we asked for — the connection works and
    /// lists nothing, which looks exactly like a bug unless the app says what happened.
    private(set) var stravaScopeIsNarrow = false

    /// True once a session has actually arrived this way. The automatic pickup is offered only
    /// after this: a toggle for a source the rider has never used is a question about nothing.
    var hasImportedFromStrava: Bool {
        get { UserDefaults.standard.bool(forKey: Self.stravaDidImportKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.stravaDidImportKey) }
    }

    /// "Import new Strava activities automatically" — off until asked for.
    var stravaAutoImport: Bool {
        get {
            access(keyPath: \.stravaAutoImport)
            return UserDefaults.standard.bool(forKey: Self.stravaAutoKey)
        }
        set {
            withMutation(keyPath: \.stravaAutoImport) {
                UserDefaults.standard.set(newValue, forKey: Self.stravaAutoKey)
            }
            guard newValue else { return clearSyncTrouble(.strava) }
            Task { await checkStravaForNewActivities() }
        }
    }

    /// Whether this build has a Strava API application behind it at all. False is a state the
    /// Import screen explains rather than a failure it hides (`StravaAuth.config`).
    var isStravaConfigured: Bool { StravaAuth.config.isConfigured }

    func refreshStravaConnection() {
        let tokens = StravaAuth.loadTokens()
        isStravaConnected = tokens != nil
        stravaAthlete = tokens?.athleteName
        stravaScopeIsNarrow = tokens.map { !$0.hasActivityReadAll } ?? false
    }

    /// The browser round trip. `anchor` is the window the sheet is presented over, handed
    /// down by the screen that owns it — the store has no window of its own and must not
    /// invent one.
    func connectStrava(anchor: ASPresentationAnchor?) async {
        guard !isReadingStrava else { return }
        isReadingStrava = true
        defer { isReadingStrava = false }
        do {
            let tokens = try await StravaAuth.connect(anchor: anchor)
            refreshStravaConnection()
            status = tokens.athleteName.map { "Connected to Strava as \($0)" }
                ?? "Connected to Strava"
            Usage.record(.stravaConnected)
            clearSyncTrouble(.strava)
            await refreshStravaCandidates()
        } catch StravaAuth.ConnectError.cancelled {
            // Backing out of the consent screen is a decision, not a failure. Nothing is
            // said, because nothing happened.
            refreshStravaConnection()
        } catch {
            refreshStravaConnection()
            Usage.failed(.stravaConnected, error: error)
            // He is waiting on this exact tap, so a cause he can act on is a modal. A dead
            // connection is not: the Strava section says it, in place.
            if reportSync(error, from: .strava, riderAsked: true) != .transient {
                errorMessage = Self.stravaMessage(for: error)
            }
        }
    }

    func disconnectStrava() async {
        await StravaAuth.disconnect()
        clearSyncTrouble(.strava)
        stravaCandidates = []
        refreshStravaConnection()
        status = "Disconnected from Strava"
    }

    /// One request: the activity list, each row already marked "in your library" or not.
    ///
    /// **Never a modal**, whoever asked. The Import screen opens on this call and "Look
    /// again" repeats it, and both show the failure as a line on the screen itself
    /// (`StravaImportView`). `riderAsked` false is the automatic pickup: silent until it has
    /// failed a few times in a row, and retried quietly in between.
    @discardableResult
    func refreshStravaCandidates(riderAsked: Bool = true) async -> Bool {
        guard isStravaConfigured, StravaAuth.loadTokens() != nil else { return false }
        isReadingStrava = true
        defer { isReadingStrava = false }
        let types = stravaTypes
        let known = importedStravaActivities
        let ingestor = self.ingestor
        do {
            let client = try await StravaAuth.client()
            stravaCandidates = try await StravaSyncService(client: client, ingestor: ingestor)
                .candidates(types: types, known: known)
            refreshStravaConnection()
            clearSyncTrouble(.strava)
            return true
        } catch {
            reportSync(error, from: .strava, riderAsked: riderAsked,
                       retry: riderAsked ? nil : quietStravaRetry)
            refreshStravaConnection()
            return false
        }
    }

    /// Fetches each activity's streams, maps them to a GPX and sends the bytes through the
    /// ordinary import door — same `SessionIngestor`, same ±60 s dedupe, same archive.
    func importFromStrava(_ ids: [String]) async {
        guard !ids.isEmpty, !isBusy, !isReadingStrava else { return }
        let wanted = stravaCandidates.filter { ids.contains($0.id) }.map(\.activity)
        guard !wanted.isEmpty else { return }

        isBusy = true
        status = "Reading \(wanted.count) activit\(wanted.count == 1 ? "y" : "ies") from Strava…"
        importProgress = ImportSummary()
        defer {
            isBusy = false
            importProgress = nil
        }

        let ingestor = self.ingestor
        let known = importedStravaActivities
        let producer = "CleanJibe \(Self.appVersion) (Strava import)"
        do {
            let client = try await StravaAuth.client()
            let relay = ProgressRelay { [weak self] snapshot in
                Task { @MainActor in self?.importProgress = snapshot }
            }
            let outcome = await Task.detached(priority: .userInitiated) {
                let service = StravaSyncService(client: client, ingestor: ingestor,
                                                producer: producer)
                return await service.importActivities(wanted, known: known,
                                                      progress: { line in
                    var partial = ImportSummary()
                    partial.current = line
                    relay.send(partial)
                })
            }.value

            importedStravaActivities.formUnion(outcome.importedIds)
            if outcome.summary.imported > 0 { hasImportedFromStrava = true }
            Usage.recordImport(.strava, imported: outcome.summary.imported,
                               failed: outcome.summary.failed.count)
            status = outcome.summary.shortDescription
            // An automatic pickup keeps quiet about the ones that did not come: they are not
            // marked imported, so the next pickup asks Strava for them again.
            if !outcome.summary.failed.isEmpty, !quietFailures {
                errorMessage = outcome.summary.failed.joined(separator: "\n")
            }
            await load()
            await refreshPersonalBests(celebrate: true)
            await writeNewSessionsToHealth()
            await refreshWatchMapIfNeeded()
            await refreshStravaCandidates(riderAsked: !quietFailures)
            raiseDisciplineReview()
        } catch {
            let automatic = quietFailures
            Usage.failed(.importStrava, error: error)
            let kind = reportSync(error, from: .strava, riderAsked: !automatic,
                                  retry: automatic ? quietStravaRetry : nil)
            // Only the rider's own tap on Import may raise the modal, and only for a cause
            // he can act on. A dropped connection is the line on the Strava screen.
            if !automatic, kind != .transient {
                errorMessage = Self.stravaMessage(for: error)
            } else if !automatic {
                status = "Could not reach Strava. Check your connection and try again."
            }
        }
    }

    /// Launch, foreground and the toggle's own kick: whatever Strava has that the library
    /// does not. Silent on the ordinary pass, where there is nothing new.
    func checkStravaForNewActivities() async {
        guard stravaAutoImport, isStravaConfigured, !isBusy, !isReadingStrava,
              StravaAuth.loadTokens() != nil else { return }
        guard await refreshStravaCandidates(riderAsked: false) else { return }
        let fresh = stravaCandidates.filter { !$0.isAlreadyImported }.map(\.id)
        guard !fresh.isEmpty else { return }
        await asAutomaticPickup { await importFromStrava(fresh) }
    }

    /// One sentence per cause. A rate limit and a dead connection need different actions from
    /// the rider, and "the operation could not be completed" asks him to guess which.
    static func stravaMessage(for error: any Error) -> String {
        if let strava = error as? StravaClient.Error { return strava.description }
        if let connect = error as? StravaAuth.ConnectError { return connect.description }
        if let callback = error as? StravaOAuth.CallbackError { return callback.description }
        return "Strava could not be reached: \(error.localizedDescription)"
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

    /// **Reads the keychain again when the key in memory is empty** (Jan, dev 106: the key
    /// field was empty under a "Last sync" three days old).
    ///
    /// `apiKey` is read once, in a property initialiser, and the read cannot tell "no key"
    /// from "the keychain would not answer". It will not answer before the first unlock
    /// after a restart, and iOS can launch the app then: a background refresh or a
    /// prewarmed launch. That process then held "" for its whole life, so the field was
    /// empty, the sync asked for a key and the background check skipped every wake, with
    /// the key still safe in the keychain. One cheap query at each of those moments ends
    /// it. A key the rider removed stays removed, because the keychain then has none.
    func reloadApiKeyIfMissing() {
        guard apiKey.isEmpty else { return }
        let stored = Self.loadApiKey()
        if !stored.isEmpty { apiKey = stored }
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
        get {
            access(keyPath: \.lastSyncDate)
            return UserDefaults.standard.object(forKey: "lastIcuSync") as? Date
        }
        set {
            withMutation(keyPath: \.lastSyncDate) {
                UserDefaults.standard.set(newValue, forKey: "lastIcuSync")
            }
        }
    }

    /// **When intervals.icu was last successfully reached, by any means** — the rider's own
    /// pull, the background wake (`ActivityNotifier.poll`) and the empty library's first
    /// fill at launch alike. `lastSyncDate` cannot be widened to cover those: it is the
    /// re-add gate's cursor (`syncFromIntervals`, above), and the background poller
    /// deliberately never touches it — a poll that moved it would make the re-add gate
    /// think a manual sync had just run. This is purely for the Settings row, so a phone
    /// polled every half hour reads today's date instead of the last day someone opened
    /// the app and pulled to refresh.
    var lastCheckAt: Date? {
        get {
            access(keyPath: \.lastCheckAt)
            return UserDefaults.standard.object(forKey: "icuLastCheck.v1") as? Date
        }
        set {
            withMutation(keyPath: \.lastCheckAt) {
                UserDefaults.standard.set(newValue, forKey: "icuLastCheck.v1")
            }
        }
    }

#if BETA || DEBUG

    // MARK: - Start over

    /// **The wipe could not reopen the library** — set only when `AppDatabase` refuses the
    /// fresh file, which leaves the app running on an in-memory library that would lose
    /// whatever came next. `RootView` puts one screen in front of everything asking for a
    /// relaunch; on every ordinary run this stays false and nothing is asked of the rider.
    private(set) var startOverNeedsRelaunch = false

    /// **Settings → Beta → Start over** (beta and dev only, docs/channels.md), and the
    /// `UI_START_OVER=1` simulator hook.
    ///
    /// Deleting the app is what a tester reaches for and it is not enough: iOS keeps
    /// keychain items across a delete, so the intervals.icu key and the Strava connection
    /// come back with the reinstall and the first run the tester wanted to see never
    /// happens. This is the thing deleting the app *should* do — `StartOver.wipe` is the
    /// whole list, shared with the screenshot hook so there is one wipe and not two.
    ///
    /// **In process, without a relaunch.** The only handle that has to survive the file
    /// going away is the GRDB pool, and the app already knows how to swap one: the same
    /// three lines `adoptFreshLibraryForRestore` uses when a restore lands on a library
    /// this build refused to open. So the pool is parked in memory, the container is wiped,
    /// a new pool is opened on the same path — where the migrator builds an empty schema —
    /// and every property that mirrors a default is read back from the now-empty domain.
    /// `load()` then finds nothing, bumps `libraryGeneration`, and `RootView` asks
    /// `showWelcomeIfNeeded` the same question a genuine first launch asks it.
    func startOver() async {
        // Anything that sets `isBusy` is writing to the library or the archive right now.
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        // 1. Let go of the library. The thumbnail cache holds its own copy of the ingestor
        //    struct — and therefore of the pool — so it is retargeted here rather than
        //    left pointing at a file that is about to be unlinked.
        let scratch = try? AppDatabase.inMemory()
        if let scratch {
            ingestor.database = scratch
            thumbnails.retarget(to: ingestor)
        }

        // 2. The wipe itself: keychain, defaults, container.
        StartOver.wipe()

        // 2b. …and the one thing written *back* immediately: "this phone is owed the
        //     welcome screen". After the wipe, necessarily — the wipe takes the whole
        //     defaults domain with it. Everything else about a first run is an absence the
        //     wipe creates, and an absence is not something Start over can promise the next
        //     launch: the in-process screen spends `welcomeShown.v1` again the moment it
        //     goes up, and one session arriving from a sync, a watch or a re-import makes
        //     the library look like a history, at which point the upgrade heuristic marks
        //     the screen seen on sight and the relaunch opens on Sessions (Jan, build 63).
        //     `showWelcomeIfNeeded` honours this before either rule and clears it when the
        //     screen is actually raised, so the welcome happens exactly once — now if
        //     nothing is in the way, on the next launch otherwise.
        UserDefaults.standard.set(true, forKey: Self.welcomeRequestedKey)

        // 3. A new library on the same path. The migrator writes an empty schema into it,
        //    which is exactly what a first launch opens.
        if let url = databaseURL, let fresh = try? AppDatabase.onDisk(at: url) {
            ingestor.database = fresh
            startOverNeedsRelaunch = false
        } else {
            // Nothing is lost — the wipe happened — but the app is now running on a
            // library that is not on disk, and pretending otherwise would cost the rider
            // the next session he imports. So it says so instead.
            startOverNeedsRelaunch = true
        }
        thumbnails.retarget(to: ingestor)

        // 4. The engine settings the ingestor carries, re-read from the empty domain.
        ingestor.windConfig.defaultTurnType = Self.storedDefaultTurnType
        ingestor.riderDiscipline = Self.storedRiderDiscipline
        #if DEV
        ingestor.windsurfEnabled = Self.storedWindsurfEnabled
        windsurfEnabled = Self.storedWindsurfEnabled
        #endif
        #if TUNING
        ingestor.tuning = Self.storedTuning
        #endif

        // 5. Every observable that mirrors a default or a keychain item. Read back rather
        //    than assigned to a literal, so "what a fresh install has" stays defined in the
        //    one place that already defines it.
        apiKey = Self.loadApiKey()
        keyCheck = nil
        lastSyncProblem = Self.loadProblem()
        mapStyle = Self.initialMapStyle()
        mapLayersByScope = Self.initialMapLayers()
        replayCommentary = Self.storedReplayCommentary
        listMapBackdrop = Self.storedListMapBackdrop
        rowMetrics = Self.storedRowMetrics
        replayClipLength = Self.storedReplayClipLength
        replayFraming = Self.storedReplayFraming
        replayMusic = Self.storedReplayMusic
        // The Garmin link's own two, which only the dev channel has (docs/channels.md).
        #if DEV
        watchMapChoice = WatchMapChoice.load(from: .standard)
        watchMapStatus = nil
        #endif
        stravaCandidates = []
        refreshStravaConnection()

        // 6. And the transient state: a banner, a celebration or a half-answered question
        //    from the library that no longer exists.
        sessions = []
        spots = []
        gearAggregates = []
        deletedSessionCount = 0
        storage = StorageStats()
        celebration = []
        cleanJibeCelebration = []
        importProgress = nil
        pendingImport = nil
        pendingReAdd = nil
        backupFile = nil
        restoreOffer = nil
        errorMessage = nil
        status = nil
        isShowingWelcome = false
        hasLoadedLibrary = false

        // 7. Read the empty library, which is what tells `RootView` to say hello.
        await load()
        showWelcomeIfNeeded()
        // Counted after the wipe, which took the old counters with it: the fresh blob
        // starts by saying this phone was reset, and that the reset reached the welcome.
        Usage.record(.startOver)
    }

#endif

    #if DEBUG
    /// Headless-driving hook (same family as `UI_IMPORT_FIXTURES` / `UI_TAB`): `UI_RESET=1`
    /// puts the app back into its fresh-install state — no key, no sessions, no stored
    /// sync history — so the first-run screens can be screenshotted without uninstalling.
    ///
    /// Simulator only, and it runs *before* the store exists, because the store reads the
    /// keychain in a property initialiser — which is also why this is the static half of
    /// the pair. The wipe is `StartOver.wipe`, the same one Settings → Beta → Start over
    /// runs; the only thing that belongs here and not there is the key it seeds afterwards.
    static func resetIfRequested() {
        #if targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["UI_RESET"] == "1" else { return }
        StartOver.wipe()
        // `UI_ICU_KEY=…` seeds a key through the real keychain path afterwards, which is
        // how the "key stored, sync failed" card gets driven without typing.
        if let seed = ProcessInfo.processInfo.environment["UI_ICU_KEY"], !seed.isEmpty {
            Keychain.set(seed, for: Keychain.icuApiKey)
        }
        #endif
    }
    #endif
}
