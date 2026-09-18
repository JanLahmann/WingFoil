import Foundation
import Observation
import UIKit
import WingFoilKit

/// Supplies the library rows with their track thumbnails.
///
/// A thumbnail costs a FIT re-parse, which is far too expensive to do while a list
/// scrolls, so this is a two-level cache: an in-memory dictionary the rows read
/// synchronously, backed by a `thumbnail.json` next to each session's archive. A session
/// is parsed **once, ever** — after that both levels hit and a cold launch only reads a
/// few kilobytes of JSON per visible row.
///
/// Rows ask for what they need as they appear (`request(_:)`); nothing is precomputed for
/// a library the rider never scrolls to.
@MainActor
@Observable
final class ThumbnailStore {

    /// Parses in flight at once. Two keeps a scroll responsive on the oldest supported
    /// phone without letting a fling down a long library queue up fifty FIT parses.
    private static let maxConcurrent = 2

    private(set) var cache: [String: TrackThumbnail] = [:]
    /// Sessions whose thumbnail could not be built (archive gone, no positions and no
    /// speed). Remembered so a scroll does not retry them on every appearance.
    private var unavailable: Set<String> = []
    private var running: Set<String> = []
    private var queue: [SessionRow] = []

    /// `var`, for one caller: "Start over" hands the cache a new library. The struct it
    /// holds carries an `AppDatabase`, which carries the GRDB pool — so a stale copy here
    /// would keep the very file the wipe just deleted open (`SessionStore.startOver`).
    private var ingestor: SessionIngestor

    init(ingestor: SessionIngestor) {
        self.ingestor = ingestor
    }

    func thumbnail(for id: String) -> TrackThumbnail? { cache[id] }

    // MARK: - The optional map under the outline

    /// Built snapshots, by session and style. The same two levels the outline has and for
    /// the same reason: a row reads this synchronously while it draws.
    private var backdrops: [String: UIImage] = [:]
    private var backdropsRunning: Set<String> = []
    /// Sessions whose picture MapKit could not or would not make — no bounds, no network.
    /// Remembered so a scroll does not ask again on every appearance.
    private var backdropsUnavailable: Set<String> = []

    private func backdropKey(_ id: String, _ style: MapStyleChoice) -> String {
        id + "-" + style.rawValue
    }

    /// The map behind one row's track, or nil while there is not one yet. Never waits.
    func backdrop(for id: String, style: MapStyleChoice) -> UIImage? {
        backdrops[backdropKey(id, style)]
    }

    /// Queues a snapshot for a row that is on screen. Cheap and idempotent — a row calls it
    /// on every appearance — and a no-op until the outline it has to line up with exists.
    func requestBackdrop(_ row: SessionRow, style: MapStyleChoice, scale: CGFloat) {
        let key = backdropKey(row.id, style)
        guard backdrops[key] == nil, !backdropsRunning.contains(key),
              !backdropsUnavailable.contains(key), let thumbnail = cache[row.id]
        else { return }
        backdropsRunning.insert(key)
        Task { await buildBackdrop(key: key, id: row.id, thumbnail: thumbnail,
                                   style: style, scale: scale) }
    }

    private func buildBackdrop(key: String, id: String, thumbnail: TrackThumbnail,
                               style: MapStyleChoice, scale: CGFloat) async {
        defer { backdropsRunning.remove(key) }
        // The disk first: a hit costs a file read and no network at all.
        if let cached = await Task.detached(priority: .utility, operation: {
            ListMapBackdrop.read(id: id, style: style)
        }).value {
            backdrops[key] = cached
            return
        }
        guard let image = await ListMapBackdrop.snapshot(for: thumbnail, style: style,
                                                         scale: scale) else {
            backdropsUnavailable.insert(key)
            return
        }
        backdrops[key] = image
        let stored = image
        Task.detached(priority: .utility) {
            ListMapBackdrop.write(stored, id: id, style: style)
        }
    }

    /// Queues a build if this session has no thumbnail yet. Cheap and idempotent — a row
    /// can call it on every appearance.
    func request(_ row: SessionRow) {
        guard cache[row.id] == nil, !unavailable.contains(row.id),
              !running.contains(row.id), !queue.contains(where: { $0.id == row.id })
        else { return }
        queue.append(row)
        pump()
    }

    /// Drops a session's thumbnail from both levels — used when it is deleted, and when a
    /// re-analysis changes which parts of the track were flown.
    func invalidate(_ id: String) {
        cache[id] = nil
        unavailable.remove(id)
        for style in MapStyleChoice.allCases {
            let key = backdropKey(id, style)
            backdrops[key] = nil
            backdropsUnavailable.remove(key)
            try? FileManager.default.removeItem(
                at: ListMapBackdrop.fileURL(id: id, style: style))
        }
        ingestor.archive.dropThumbnail(for: id)
    }

    func invalidateAll() {
        cache.removeAll()
        unavailable.removeAll()
        backdrops.removeAll()
        backdropsUnavailable.removeAll()
    }

#if BETA || DEBUG
    /// Points the cache at a different library and forgets everything it knew about the old
    /// one — both levels, the failures, and whatever was queued. Only "Start over" calls it.
    func retarget(to ingestor: SessionIngestor) {
        self.ingestor = ingestor
        cache.removeAll()
        unavailable.removeAll()
        queue.removeAll()
        backdrops.removeAll()
        backdropsUnavailable.removeAll()
        ListMapBackdrop.clear()
    }
#endif

    private func pump() {
        while running.count < Self.maxConcurrent, !queue.isEmpty {
            let row = queue.removeFirst()
            running.insert(row.id)
            Task { await build(row) }
        }
    }

    private func build(_ row: SessionRow) async {
        defer {
            running.remove(row.id)
            pump()
        }
        let ingestor = self.ingestor

        // The disk cache first: a hit costs a JSON read and no parse at all.
        if let cached = await Task.detached(priority: .utility, operation: {
            ingestor.archive.thumbnail(for: row.id)
        }).value {
            cache[row.id] = cached
            return
        }

        let built = await Task.detached(priority: .utility) { () -> TrackThumbnail? in
            guard let track = try? ingestor.archive.rawTrack(for: row.id) else { return nil }
            // Use the cached analysis when there is one; a missing one is not worth a full
            // re-analysis *here* — the thumbnail would just draw the whole track as
            // off-foil, and opening the session rebuilds it properly anyway.
            let analysis = ingestor.archive.analysis(for: row.id)
            let flights = analysis?.flights ?? []
            // The marks are the share card's — the 62 × 44 row never draws them — but they
            // are cached with the outline so a card built from the list (no session open,
            // no analysis in memory) is the same picture as one built from the detail.
            let thumbnail = TrackThumbnail.make(
                track: track, flights: flights,
                events: analysis.map(TrackThumbnail.events) ?? [])
            guard !thumbnail.isEmpty else { return nil }
            // Only cache a thumbnail whose colouring is final. Without an analysis the
            // track has no flights yet, and writing that would freeze a grey outline for
            // a session that is simply not analyzed yet.
            if !flights.isEmpty { try? ingestor.archive.writeThumbnail(thumbnail, id: row.id) }
            return thumbnail
        }.value

        if let built {
            cache[row.id] = built
        } else {
            unavailable.insert(row.id)
        }
    }
}
