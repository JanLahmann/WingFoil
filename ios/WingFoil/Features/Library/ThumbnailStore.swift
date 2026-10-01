import Foundation
import Observation
import UIKit
import WingFoilKit

/// One session's drawing data for its library row: the outline + sparkline, and the map
/// pictures under it by style.
///
/// **Its own observable**, so the outline landing for one session redraws that session's
/// row and no other. The store used to publish one dictionary that every row read; each
/// thumbnail that arrived during a first scroll then re-evaluated every row on screen, ten
/// rows' worth of layout for one row's picture, and a fling down a cold list arrived in
/// bursts of that (Jan, dev 126: "hakelig when scrolling for the first time").
@MainActor
@Observable
final class ThumbnailEntry {
    var thumbnail: TrackThumbnail? {
        didSet { art = nil }
    }
    var backdrops: [MapStyleChoice: UIImage] = [:]
    /// The outline and sparkline as finished bitmaps (`TrackTileArt`), in the inks they were
    /// drawn in. Nil until drawn, and dropped with the thumbnail it was drawn from.
    var art: TileArt?
}

/// Supplies the library rows with their track thumbnails.
///
/// A thumbnail costs a FIT re-parse, which is far too expensive to do while a list
/// scrolls, so this is a two-level cache: in-memory entries the rows read synchronously,
/// backed by a `thumbnail.json` next to each session's archive. A session is parsed
/// **once, ever** — after that both levels hit.
///
/// **The library is warmed before it is scrolled** (`warm(_:backdrop:scale:)`, called by
/// the list whenever the library is loaded): every cached outline is read off the main
/// actor in one pass and published at once, and the sessions that have none — a fresh
/// import, every session after a re-analysis — are built in the background, newest first,
/// so the rider's first scroll meets rows that are already drawn. A row that appears before
/// its outline is ready still asks for it (`request(_:)`), and goes to the front of the
/// queue; it draws the placeholder in the same box until then, so nothing moves.
@MainActor
@Observable
final class ThumbnailStore {

    /// Parses in flight at once. Two keeps a scroll responsive on the oldest supported
    /// phone without letting a fling down a long library queue up fifty FIT parses.
    private static let maxConcurrent = 2
    /// Map snapshots in flight at once, for the same reason: each one is a MapKit render
    /// and a network round trip, and a fling used to start one for every row it passed.
    private static let maxConcurrentBackdrops = 2

    /// Read by the rows through `entry(_:)`, never observed as a whole.
    @ObservationIgnored private var entries: [String: ThumbnailEntry] = [:]
    /// Sessions whose thumbnail could not be built (archive gone, no positions and no
    /// speed). Remembered so a scroll does not retry them on every appearance.
    @ObservationIgnored private var unavailable: Set<String> = []
    @ObservationIgnored private var running: Set<String> = []
    @ObservationIgnored private var queue: [SessionRow] = []
    /// Bumped by every wipe, so a build that started for the old library lands nowhere.
    @ObservationIgnored private var generation = 0

    /// `var`, for one caller: "Start over" hands the cache a new library. The struct it
    /// holds carries an `AppDatabase`, which carries the GRDB pool — so a stale copy here
    /// would keep the very file the wipe just deleted open (`SessionStore.startOver`).
    @ObservationIgnored private var ingestor: SessionIngestor

    init(ingestor: SessionIngestor) {
        self.ingestor = ingestor
    }

    /// The one session's entry, made on first ask. Making it is not a change anybody
    /// observes, so a row may ask from inside its body.
    func entry(_ id: String) -> ThumbnailEntry {
        if let entry = entries[id] { return entry }
        let entry = ThumbnailEntry()
        entries[id] = entry
        return entry
    }

    func thumbnail(for id: String) -> TrackThumbnail? { entry(id).thumbnail }

    // MARK: - The tile, as pictures

    /// The inks and scale the list is drawn in, as of the last warming pass. Observed: a
    /// change of appearance redraws every row once, in the fallback, until its new picture
    /// lands.
    private(set) var inks: TileInks?

    /// The row's finished tile, when there is one in the current inks.
    func art(for id: String) -> TileArt? {
        guard let art = entry(id).art, art.inks == inks else { return nil }
        return art
    }

    /// Draws the tiles of these sessions off the main actor, in one pass, and publishes them
    /// together.
    private func drawArt(_ items: [(id: String, thumbnail: TrackThumbnail)]) {
        guard let inks, !items.isEmpty else { return }
        let generation = self.generation
        Task {
            let drawn = await Task.detached(priority: .utility) {
                items.map { ($0.id, $0.thumbnail, TrackTileArt.make($0.thumbnail, inks: inks)) }
            }.value
            guard generation == self.generation, inks == self.inks else { return }
            for (id, thumbnail, art) in drawn where entry(id).thumbnail == thumbnail {
                entry(id).art = art
            }
        }
    }

    /// Every outline in memory without a picture in the current inks.
    private func undrawn() -> [(id: String, thumbnail: TrackThumbnail)] {
        entries.compactMap { id, entry in
            guard let thumbnail = entry.thumbnail, entry.art?.inks != inks else { return nil }
            return (id, thumbnail)
        }
    }

    // MARK: - Warming the library

    /// Fills the memory cache for these rows before anybody scrolls to them: one pass over
    /// the disk off the main actor, published in one go, then a background build for every
    /// session the disk did not have, in list order. With `backdrop` set, the cached map
    /// pictures are read the same way — decoded off the main actor too — and the missing
    /// ones are queued behind the outlines they line up with. Cheap to call again: a
    /// session already in memory costs nothing.
    func warm(_ rows: [SessionRow], inks: TileInks, backdrop: MapStyleChoice?,
              scale: CGFloat) {
        if inks != self.inks {
            self.inks = inks
            drawArt(undrawn())
        }
        let generation = self.generation
        let ingestor = self.ingestor
        let missing = rows.filter {
            entries[$0.id]?.thumbnail == nil && !unavailable.contains($0.id)
                && !running.contains($0.id)
        }
        let pictures = backdrop.map { style in
            rows.filter { entries[$0.id]?.backdrops[style] == nil
                && !backdropsUnavailable.contains(backdropKey($0.id, style)) }
        } ?? []
        guard !missing.isEmpty || !pictures.isEmpty else { return }
        Task {
            if !missing.isEmpty {
                let ids = missing.map(\.id)
                let found = await Task.detached(priority: .utility) {
                    ids.compactMap { id in ingestor.archive.thumbnail(for: id).map { (id, $0) } }
                }.value
                guard generation == self.generation else { return }
                var landed: [(id: String, thumbnail: TrackThumbnail)] = []
                for (id, thumbnail) in found where entry(id).thumbnail == nil {
                    entry(id).thumbnail = thumbnail
                    landed.append((id, thumbnail))
                }
                drawArt(landed)
                // What the disk did not have is built now, not when it scrolls into view.
                for row in missing where entry(row.id).thumbnail == nil { enqueue(row) }
                pump()
            }
            if let style = backdrop, !pictures.isEmpty {
                await warmBackdrops(pictures, style: style, scale: scale,
                                    generation: generation)
            }
        }
    }

    private func warmBackdrops(_ rows: [SessionRow], style: MapStyleChoice, scale: CGFloat,
                               generation: Int) async {
        let ids = rows.map(\.id)
        let found = await Task.detached(priority: .utility) {
            ids.compactMap { id in ListMapBackdrop.read(id: id, style: style).map { (id, $0) } }
        }.value
        guard generation == self.generation else { return }
        for (id, image) in found where entry(id).backdrops[style] == nil {
            entry(id).backdrops[style] = image
        }
        // The rest are snapshotted in the background as their outlines arrive.
        for row in rows where entry(row.id).backdrops[style] == nil {
            requestBackdrop(row, style: style, scale: scale, front: false)
        }
    }

    // MARK: - The optional map under the outline

    @ObservationIgnored private var backdropsRunning: Set<String> = []
    @ObservationIgnored private var backdropQueue: [(key: String, row: SessionRow,
                                                     style: MapStyleChoice, scale: CGFloat)] = []
    /// Sessions whose picture MapKit could not or would not make — no bounds, no network.
    /// Remembered so a scroll does not ask again on every appearance.
    @ObservationIgnored private var backdropsUnavailable: Set<String> = []
    /// Rows that asked for a picture before their outline existed: asked again when it does.
    @ObservationIgnored private var backdropsAwaitingOutline:
        [String: (row: SessionRow, style: MapStyleChoice, scale: CGFloat, front: Bool)] = [:]

    private func backdropKey(_ id: String, _ style: MapStyleChoice) -> String {
        id + "-" + style.rawValue
    }

    /// Once per launch: the pictures cached before the appearance was pinned are deleted.
    @ObservationIgnored private var sweptUnpinnedBackdrops = false

    /// The map behind one row's track, or nil while there is not one yet. Never waits.
    func backdrop(for id: String, style: MapStyleChoice) -> UIImage? {
        entry(id).backdrops[style]
    }

    /// Queues a snapshot for a row. Cheap and idempotent — a row calls it on every
    /// appearance, and an on-screen row goes to the front of the queue.
    func requestBackdrop(_ row: SessionRow, style: MapStyleChoice, scale: CGFloat,
                         front: Bool = true) {
        let key = backdropKey(row.id, style)
        guard entry(row.id).backdrops[style] == nil, !backdropsRunning.contains(key),
              !backdropsUnavailable.contains(key) else { return }
        guard entry(row.id).thumbnail != nil else {
            // After the outline, never instead of it: the snapshot is drawn to the box the
            // outline was fitted into.
            backdropsAwaitingOutline[row.id] = (row, style, scale, front)
            return
        }
        if let index = backdropQueue.firstIndex(where: { $0.key == key }) {
            guard front else { return }
            backdropQueue.remove(at: index)
        }
        let item = (key: key, row: row, style: style, scale: scale)
        if front { backdropQueue.insert(item, at: 0) } else { backdropQueue.append(item) }
        pumpBackdrops()
    }

    private func pumpBackdrops() {
        while backdropsRunning.count < Self.maxConcurrentBackdrops, !backdropQueue.isEmpty {
            let item = backdropQueue.removeFirst()
            guard let thumbnail = entry(item.row.id).thumbnail,
                  entry(item.row.id).backdrops[item.style] == nil else { continue }
            backdropsRunning.insert(item.key)
            let generation = self.generation
            Task {
                await buildBackdrop(key: item.key, id: item.row.id, thumbnail: thumbnail,
                                    style: item.style, scale: item.scale,
                                    generation: generation)
            }
        }
    }

    private func buildBackdrop(key: String, id: String, thumbnail: TrackThumbnail,
                               style: MapStyleChoice, scale: CGFloat,
                               generation: Int) async {
        defer {
            backdropsRunning.remove(key)
            pumpBackdrops()
        }
        if !sweptUnpinnedBackdrops {
            sweptUnpinnedBackdrops = true
            Task.detached(priority: .utility) { ListMapBackdrop.sweepUnpinned() }
        }
        // The disk first: a hit costs a file read and no network at all.
        if let cached = await Task.detached(priority: .utility, operation: {
            ListMapBackdrop.read(id: id, style: style)
        }).value {
            if generation == self.generation { entry(id).backdrops[style] = cached }
            return
        }
        guard let image = await ListMapBackdrop.snapshot(for: thumbnail, style: style,
                                                         scale: scale) else {
            backdropsUnavailable.insert(key)
            return
        }
        guard generation == self.generation else { return }
        entry(id).backdrops[style] = image
        let stored = image
        Task.detached(priority: .utility) {
            ListMapBackdrop.write(stored, id: id, style: style)
        }
    }

    // MARK: - The outline

    /// Queues a build if this session has no thumbnail yet. Cheap and idempotent — a row
    /// can call it on every appearance — and a row on screen jumps the warming queue.
    func request(_ row: SessionRow) {
        guard entry(row.id).thumbnail == nil, !unavailable.contains(row.id),
              !running.contains(row.id) else { return }
        if let index = queue.firstIndex(where: { $0.id == row.id }) {
            queue.remove(at: index)
        }
        queue.insert(row, at: 0)
        pump()
    }

    private func enqueue(_ row: SessionRow) {
        guard !running.contains(row.id), !queue.contains(where: { $0.id == row.id })
        else { return }
        queue.append(row)
    }

    /// Drops a session's thumbnail from both levels — used when it is deleted, and when a
    /// re-analysis changes which parts of the track were flown.
    func invalidate(_ id: String) {
        if let entry = entries[id] {
            entry.thumbnail = nil
            entry.backdrops = [:]
        }
        unavailable.remove(id)
        for style in MapStyleChoice.allCases {
            backdropsUnavailable.remove(backdropKey(id, style))
            try? FileManager.default.removeItem(
                at: ListMapBackdrop.fileURL(id: id, style: style))
        }
        ingestor.archive.dropThumbnail(for: id)
    }

    func invalidateAll() {
        forgetEverything()
    }

#if BETA || DEBUG
    /// Points the cache at a different library and forgets everything it knew about the old
    /// one — both levels, the failures, and whatever was queued. Only "Start over" calls it.
    func retarget(to ingestor: SessionIngestor) {
        self.ingestor = ingestor
        forgetEverything()
        ListMapBackdrop.clear()
    }
#endif

    /// The entries are emptied rather than dropped: a row on screen is observing its own.
    private func forgetEverything() {
        generation += 1
        for entry in entries.values {
            entry.thumbnail = nil
            entry.backdrops = [:]
        }
        unavailable.removeAll()
        queue.removeAll()
        backdropQueue.removeAll()
        backdropsUnavailable.removeAll()
        backdropsAwaitingOutline.removeAll()
    }

    private func pump() {
        while running.count < Self.maxConcurrent, !queue.isEmpty {
            let row = queue.removeFirst()
            running.insert(row.id)
            let generation = self.generation
            Task { await build(row, generation: generation) }
        }
    }

    private func build(_ row: SessionRow, generation: Int) async {
        defer {
            running.remove(row.id)
            pump()
        }
        let ingestor = self.ingestor

        // The disk cache first: a hit costs a JSON read and no parse at all.
        if let cached = await Task.detached(priority: .utility, operation: {
            ingestor.archive.thumbnail(for: row.id)
        }).value {
            land(cached, for: row.id, generation: generation)
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

        guard generation == self.generation else { return }
        if let built {
            land(built, for: row.id, generation: generation)
        } else {
            unavailable.insert(row.id)
        }
    }

    private func land(_ thumbnail: TrackThumbnail, for id: String, generation: Int) {
        guard generation == self.generation else { return }
        entry(id).thumbnail = thumbnail
        drawArt([(id, thumbnail)])
        // A picture asked for before its outline existed is asked for again now.
        if let waiting = backdropsAwaitingOutline.removeValue(forKey: id) {
            requestBackdrop(waiting.row, style: waiting.style, scale: waiting.scale,
                            front: waiting.front)
        }
    }
}
