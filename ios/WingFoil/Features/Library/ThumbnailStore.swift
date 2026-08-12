import Foundation
import Observation
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

    private let ingestor: SessionIngestor

    init(ingestor: SessionIngestor) {
        self.ingestor = ingestor
    }

    func thumbnail(for id: String) -> TrackThumbnail? { cache[id] }

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
        ingestor.archive.dropThumbnail(for: id)
    }

    func invalidateAll() {
        cache.removeAll()
        unavailable.removeAll()
    }

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
            let flights = ingestor.archive.analysis(for: row.id)?.flights ?? []
            let thumbnail = TrackThumbnail.make(track: track, flights: flights)
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
