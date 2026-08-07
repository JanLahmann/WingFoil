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

    public init() {}

    public var shortDescription: String {
        var parts = ["\(imported) new"]
        if duplicates > 0 { parts.append("\(duplicates) duplicate\(duplicates == 1 ? "" : "s")") }
        if alreadyKnown > 0 { parts.append("\(alreadyKnown) known") }
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
        var summary = IcuSyncSummary()
        progress?("Fetching activity list…")
        let all = try await client.activities(oldest: oldest, newest: newest)
        summary.listed = all.count
        let watersports = all.filter(IcuClient.isWatersport)
        summary.watersports = watersports.count

        let known = try await ingestor.icuActivityIds()
        for (index, activity) in watersports.enumerated() {
            if known.contains(activity.id) {
                summary.alreadyKnown += 1
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
        progress?(summary.shortDescription)
        return summary
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
