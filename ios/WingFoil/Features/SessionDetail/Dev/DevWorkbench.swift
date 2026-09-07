import Foundation
import Observation
import WingFoilKit

// **Dev build only** — the whole file compiles only under the `TUNING` condition, which only
// the "WingFoil Dev" scheme sets (ios/project.yml, `Dev Debug` / `Dev Release`). Nothing here
// exists in the app external testers get: no trace, no evidence table, no labels, no diff, and
// no second analysis running in the background of a session page.
#if TUNING

/// **The workbench's session-scoped cache** — the two expensive things every dev tool on a
/// session page needs, built once and kept until the analysis moves under them.
///
/// Two things, and both are expensive enough that they cannot be computed in a `body`:
///
/// - **The rebuilt channels** (`TurnWorkbench.Context`): the cleaned track, the three outcome
///   channels, the accelerometer band and the stored flight ends. The trace and the evidence
///   table read a few dozen samples each, but building the arrays walks the whole recording.
/// - **The published-default analysis**: the *same session*, analysed a second time with the
///   tuning taken off, so "what would the defaults have said" can be answered without
///   re-deriving the library. It is only built where something is actually tuned — on an
///   untuned install the two runs are the same run, and the page says so instead of doing the
///   work twice.
///
/// **Invalidation is the analysis' own version string.** `SessionAnalysis.engineVersion` already
/// carries the tuning fingerprint (`TuningStamp`), which is the key the archive, the ingestor
/// and `SessionStore.detail(for:)` all compare on — so a moved slider changes the key here for
/// exactly the same reason it makes the library stale, and there is no second mechanism to keep
/// in step.
///
/// A singleton rather than an injected environment object, deliberately: it is reached from a
/// sheet over a tab over the library and from Settings → Tuning → Labels, and threading a
/// dev-only object through four view hierarchies would put `#if TUNING` in files that have no
/// other reason to know this feature exists.
@MainActor
@Observable
final class DevWorkbench {

    static let shared = DevWorkbench()

    /// Session id plus the analysis' stamped version — see the note on invalidation.
    struct Key: Hashable {
        var sessionID: String
        var engineVersion: String
    }

    /// One session's rebuilt channels and its default-tuning twin.
    struct Entry {
        var context: TurnWorkbench.Context
        /// The same session on the published defaults. nil where nothing is tuned (the tuned
        /// run *is* the default run) and nil while it is still being built.
        var base: SessionAnalysis?
        /// True once both halves have been attempted, so a view can tell "still working" from
        /// "there is nothing to compare with".
        var complete: Bool
    }

    private(set) var entries: [Key: Entry] = [:]
    /// The build in flight for a key, held so a **second** caller waits for it rather than
    /// walking away empty. The turn sheet is a `TabView` that materialises the pages either
    /// side of the one on screen, so three views ask for the same session within a frame of
    /// each other; a plain "already running, do nothing" guard left two of them with no
    /// context and no reason to ask again, and the panel sat on its spinner for ever.
    private var running: [Key: Task<Entry?, Never>] = [:]

    private init() {}

    func key(for detail: SessionDetail) -> Key {
        Key(sessionID: detail.row.id, engineVersion: detail.analysis.engineVersion)
    }

    func entry(for detail: SessionDetail) -> Entry? { entries[key(for: detail)] }

    func context(for detail: SessionDetail) -> TurnWorkbench.Context? {
        entries[key(for: detail)]?.context
    }

    /// The published-default analysis for this session, or nil where there is nothing to
    /// compare with — either because nothing is tuned, or because it is still building.
    func baseAnalysis(for detail: SessionDetail) -> SessionAnalysis? {
        entries[key(for: detail)]?.base
    }

    /// Builds both halves for one session, once. Safe to call from every `.task` on the page:
    /// the first caller does the work and every later one waits on the same task.
    func load(detail: SessionDetail, store: SessionStore) async {
        let key = self.key(for: detail)
        if entries[key] != nil { return }
        if let inFlight = running[key] {
            // The value, not just the wait: whichever caller resumes first publishes it, so a
            // later one never sees an empty cache a moment after the work finished.
            if let built = await inFlight.value, entries[key] == nil { entries[key] = built }
            return
        }

        let ingestor = store.ingestor
        let row = detail.row
        let analysis = detail.analysis
        let windDirDeg = detail.windDirDeg
        // Both halves off one parse of the archive: the recording is the expensive read, and
        // the default analysis and the rebuilt channels want the same bytes.
        let work = Task.detached(priority: .userInitiated) { () -> Entry? in
            guard let track = try? ingestor.rawTrack(for: row) else { return nil }
            let context = TurnWorkbench.context(analysis: analysis, track: track,
                                                windDirDeg: windDirDeg)
            // The rider's non-tunable settings stay — `defaultTurnType` is his declaration
            // about how he sails, not a threshold — so "default" here means exactly "the
            // published thresholds", which is what the card claims.
            let base = ingestor.tuning.isEmpty
                ? nil
                : SessionSummarizer.analyze(track,
                                            filterConfig: ingestor.filterConfig,
                                            flightConfig: FlightConfig(),
                                            recordsConfig: ingestor.recordsConfig,
                                            turnConfig: TurnConfig(),
                                            windConfig: ingestor.windConfig,
                                            flightEndConfig: FlightEndConfig())
            return Entry(context: context, base: base, complete: true)
        }
        running[key] = work
        let built = await work.value
        running[key] = nil
        guard let built else { return }
        entries[key] = built
    }

    /// Drops everything. The tuning page calls it on the way out, so a session opened after a
    /// slider moved never shows a comparison built against the previous setting — belt to the
    /// version key's braces, and cheap.
    func invalidateAll() {
        entries.removeAll()
    }
}

#endif
