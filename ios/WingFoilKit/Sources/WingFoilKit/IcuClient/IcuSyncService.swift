import Foundation

public struct IcuSyncSummary: Sendable, Equatable {
    /// Activities returned by intervals.icu in the window.
    public var listed = 0
    /// …of those, the watersport ones.
    public var watersports = 0
    /// …already in the library by intervals.icu id (never downloaded again).
    public var alreadyKnown = 0
    public var imported = 0
    public var duplicates = 0
    public var failed: [String] = []
    /// Tombstones (`SessionTombstoneRow`) this sync matched and therefore did *not* import —
    /// the sessions the rider deleted. Ids rather than a count, because "re-add" has to know
    /// which tombstones to forget, and the tombstone's own id is the only thing that survives
    /// both halves of the matching rule.
    public var blockedTombstoneIds: [String] = []

    public init() {}

    /// How many previously-deleted sessions this sync silently left alone.
    public var tombstoned: Int { blockedTombstoneIds.count }

    public var shortDescription: String {
        var parts = ["\(imported) new"]
        if duplicates > 0 { parts.append("\(duplicates) duplicate\(duplicates == 1 ? "" : "s")") }
        if alreadyKnown > 0 { parts.append("\(alreadyKnown) known") }
        // Said out loud rather than merely done: a rider who deleted a session and then
        // wondered why the count did not move deserves to be told that the app is obeying
        // him, not failing.
        if tombstoned > 0 { parts.append("\(tombstoned) previously deleted") }
        if !failed.isEmpty { parts.append("\(failed.count) failed") }
        return "\(watersports) watersport session\(watersports == 1 ? "" : "s"): "
            + parts.joined(separator: ", ")
    }
}

/// Pulls original FITs from intervals.icu into the library: list → watersport filter →
/// skip known ids → download `/file` → unwrap → ingest (dedupe applies on top).
public struct IcuSyncService: Sendable {

    public let client: IcuClient
    public let ingestor: SessionIngestor

    public init(client: IcuClient, ingestor: SessionIngestor) {
        self.client = client
        self.ingestor = ingestor
    }

    public func sync(oldest: Date, newest: Date = Date(),
                     progress: (@Sendable (String) -> Void)? = nil) async throws -> IcuSyncSummary {
        var log = ImportLogRow(source: .icu, container: "intervals.icu")
        let opened = log
        try? await ingestor.database.writer.write { db in try opened.insert(db) }
        var summary = IcuSyncSummary()
        progress?("Fetching activity list…")
        let all = try await client.activities(oldest: oldest, newest: newest)
        summary.listed = all.count
        let watersports = all.filter(IcuClient.isWatersport)
        summary.watersports = watersports.count

        let known = try await ingestor.icuActivityIds()
        // Read once for the whole run: the matcher is pure and the list is a handful of rows.
        let tombstones = try await ingestor.library.tombstones()
        for (index, activity) in watersports.enumerated() {
            if known.contains(activity.id) {
                summary.alreadyKnown += 1
                continue
            }
            // A session the rider deleted is skipped **silently and before the download** —
            // the whole cost of obeying a deletion should be one comparison, not a FIT off
            // the network and a parse. Whether the rider is offered them back is not decided
            // here: this call has no idea whether it is a pull-to-refresh or a background
            // wake, and the difference between those two is the entire gate
            // (`SessionTombstones.shouldOfferReAdd`). All it does is report what it skipped.
            if let stone = SessionTombstones.blocks(activity, tombstones: tombstones) {
                summary.blockedTombstoneIds.append(stone.id)
                continue
            }
            let label = activity.name ?? activity.id
            progress?("Downloading \(index + 1)/\(watersports.count): \(label)")
            do {
                let fit = try await client.originalFit(activityID: activity.id)
                switch try await ingestor.ingest(fitData: fit, filename: Self.filename(for: activity),
                                                 source: .icu, icuActivityId: activity.id) {
                case .imported: summary.imported += 1
                case .duplicate: summary.duplicates += 1
                case .skipped: break            // no sport gate on hand-picked icu activities
                }
            } catch {
                summary.failed.append("\(label): \(error)")
            }
        }
        log.found = summary.watersports
        log.imported = summary.imported
        log.duplicates = summary.duplicates
        // Activities already carrying our intervals.icu id were never re-downloaded.
        log.skipped = summary.alreadyKnown
        log.failed = summary.failed.count
        log.detail = summary.failed.isEmpty ? nil : summary.failed.prefix(20).joined(separator: "\n")
        log.finishedAt = Date()
        // A sync that threw leaves its row open (`finishedAt` nil) — that is the record.
        let finished = log
        try? await ingestor.database.writer.write { db in try finished.update(db) }
        progress?(summary.shortDescription)
        return summary
    }

    /// One activity, downloaded and ingested through the same path `sync` uses — the
    /// background poller's prefetch (`ActivityNotifier`), which has already listed the
    /// activities itself and only wants this one FIT while iOS is still granting it time.
    ///
    /// No `import_log` row: a wake that fetches one file is not an import the rider started,
    /// and a log full of unattended single-file entries would bury the ones he did.
    ///
    /// A deleted session is refused here too, and this is the half that matters most: an
    /// **automatic** sync must never resurrect one, because there is nobody watching to
    /// notice that it did. It is reported as `.skipped` rather than thrown — the rider
    /// deleting a session is not an error, and the poller's tally already knows what to do
    /// with a file it did not import.
    @discardableResult
    public func fetchOne(_ activity: IcuActivity) async throws -> IngestOutcome {
        let tombstones = try await ingestor.library.tombstones()
        if SessionTombstones.blocks(activity, tombstones: tombstones) != nil {
            return .skipped(reason: "previously deleted")
        }
        let fit = try await client.originalFit(activityID: activity.id)
        return try await ingestor.ingest(fitData: fit, filename: Self.filename(for: activity),
                                         source: .icu, icuActivityId: activity.id,
                                         utcOffsetS: activity.utcOffsetS)
    }

    /// Default window: two years back. A personal library is small, so a full re-list is
    /// cheap against the 5 k requests/day limit, and known ids are never re-downloaded.
    public static func defaultOldest() -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .year, value: -2, to: Date()) ?? Date()
    }

    /// `<id>_<name-slug>_icu.fit` — same shape as `fixtures/README.md`, so the library
    /// shows the activity name instead of a bare intervals.icu id.
    static func filename(for activity: IcuActivity) -> String {
        let lowered = (activity.name ?? "session").lowercased()
        var slug = ""
        var lastWasDash = true
        for character in lowered {
            if character.isLetter || character.isNumber {
                slug.append(character)
                lastWasDash = false
            } else if !lastWasDash {
                slug.append("-")
                lastWasDash = true
            }
        }
        slug = String(slug.prefix(40))
        while slug.hasSuffix("-") { slug.removeLast() }
        return "\(activity.id)_\(slug.isEmpty ? "session" : slug)_icu.fit"
    }
}
