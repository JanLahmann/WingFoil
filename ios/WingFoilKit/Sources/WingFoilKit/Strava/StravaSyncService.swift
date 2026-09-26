import Foundation

/// One activity as the Import screen offers it: everything that can be said about it before
/// a single stream has been fetched.
public struct StravaCandidate: Sendable, Equatable, Identifiable {
    public var activity: StravaActivity
    /// The library already holds this afternoon — by Strava id, or by the ±60 s key. The
    /// row says so instead of being silently unimportable, because "nothing happened" and
    /// "it was already here" look identical otherwise.
    public var isAlreadyImported: Bool

    public var id: String { activity.id }

    public init(activity: StravaActivity, isAlreadyImported: Bool = false) {
        self.activity = activity
        self.isAlreadyImported = isAlreadyImported
    }
}

public struct StravaSyncSummary: Sendable, Equatable {
    /// Activities Strava returned in the window.
    public var listed = 0
    /// …of those, the ones matching the rider's type selection and carrying a route.
    public var matching = 0
    /// …already in the library by Strava id (never fetched again).
    public var alreadyKnown = 0
    public var imported = 0
    public var duplicates = 0
    /// Activities Strava had no usable streams for — a manual entry, or a recording it is
    /// still processing. Counted, never failed: neither is an error the rider caused.
    public var withoutStreams = 0
    public var failed: [String] = []
    /// Tombstones this sync matched and therefore did *not* import — the sessions the rider
    /// deleted. Same promise the intervals.icu sync makes, in the same words.
    public var blockedTombstoneIds: [String] = []
    /// True when Strava told us to slow down and the run stopped early. The remaining
    /// activities are still there; nothing was lost, and the rider is told to come back.
    public var rateLimited = false

    public init() {}

    public var tombstoned: Int { blockedTombstoneIds.count }

    public var shortDescription: String {
        var parts = ["\(imported) new"]
        if duplicates > 0 { parts.append("\(duplicates) duplicate\(duplicates == 1 ? "" : "s")") }
        if alreadyKnown > 0 { parts.append("\(alreadyKnown) known") }
        if withoutStreams > 0 { parts.append("\(withoutStreams) with no GPS recording") }
        if tombstoned > 0 { parts.append("\(tombstoned) previously deleted") }
        if !failed.isEmpty { parts.append("\(failed.count) failed") }
        var text = "\(matching) Strava activit\(matching == 1 ? "y" : "ies"): "
            + parts.joined(separator: ", ")
        if rateLimited { text += " — Strava asked us to wait" }
        return text
    }
}

/// Pulls Strava activities into the library: list → type filter → skip known ids → fetch
/// streams → map to a GPX (`StravaImport`) → ingest through the ordinary door.
///
/// **The same door, deliberately.** Nothing here writes to the database: it hands bytes to
/// `SessionIngestor`, which applies the ±60 s dedupe, archives the original and runs the
/// analysis exactly as it does for a file the rider AirDropped. A Strava session is
/// therefore re-analysed on an engine bump like every other, and can be shared, backed up
/// and restored with no special case anywhere downstream.
///
/// **Rate limits are a first-class outcome, not an exception.** Strava allows 200 read
/// requests per fifteen minutes; a 429 stops the run, is reported as `rateLimited`, and leaves
/// everything it had already imported in place. Nothing is retried in a loop — a retry
/// against a quota is how an app turns a five-minute wait into a fifteen-minute one.
public struct StravaSyncService: Sendable {

    public let client: StravaClient
    public let ingestor: SessionIngestor
    /// What goes in the archived GPX's `creator` attribute — the app and its version.
    public let producer: String

    public init(client: StravaClient, ingestor: SessionIngestor,
                producer: String = "CleanJibe (Strava import)") {
        self.client = client
        self.ingestor = ingestor
        self.producer = producer
    }

    /// Default window: two years back, same as the intervals.icu sync. A personal library is
    /// small and known ids are never fetched again, so a full re-list is one request.
    public static func defaultOldest() -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .year, value: -2, to: Date()) ?? Date()
    }

    /// A polite pause between stream fetches.
    ///
    /// Strava's limit is a rolling fifteen-minute window, so the arithmetic that matters is
    /// requests per window rather than requests per second — but a first connection on a
    /// two-year library can genuinely queue thirty downloads, and firing those as fast as
    /// URLSession will carry them is how an application-wide quota gets spent in four
    /// seconds. 300 ms costs a thirty-activity backfill nine seconds and keeps CleanJibe a
    /// well-behaved guest.
    public static let pacingS: Duration = .milliseconds(300)

    // MARK: - Listing

    /// What Strava has that CleanJibe would offer, with each row already marked "in your
    /// library" or not. One request, no streams — this is what the Import screen shows.
    public func candidates(types: Set<StravaActivityType>,
                           known: Set<String>,
                           oldest: Date = StravaSyncService.defaultOldest())
    async throws -> [StravaCandidate] {
        let all = try await client.activities(after: oldest)
        let matching = all.filter { StravaActivityFilter.matches($0, types: types) }
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
        var out: [StravaCandidate] = []
        out.reserveCapacity(matching.count)
        for activity in matching {
            var held = known.contains(activity.id)
            // Second opinion for the activity the id set has never seen: the same afternoon
            // may have reached the library from intervals.icu or a file first, and the rider
            // should be told that before he taps rather than after.
            if !held, let start = activity.startDate, let duration = activity.durationS {
                held = (try? await ingestor.holdsSession(startDate: start,
                                                         durationS: duration)) ?? false
            }
            out.append(StravaCandidate(activity: activity, isAlreadyImported: held))
        }
        return out
    }

    // MARK: - Importing

    /// Fetches, maps and ingests the given activities, writing one `import_log` row for the
    /// run. `known` is the set of Strava ids already in the library — skipped before the
    /// request, because a session that is already here should cost nothing at all.
    public func importActivities(_ activities: [StravaActivity],
                                 known: Set<String> = [],
                                 progress: (@Sendable (String) -> Void)? = nil)
    async -> (summary: StravaSyncSummary, importedIds: [String]) {
        var log = ImportLogRow(source: .strava, container: "Strava")
        let opened = log
        try? await ingestor.database.writer.write { db in try opened.insert(db) }

        var summary = StravaSyncSummary()
        summary.listed = activities.count
        summary.matching = activities.count
        var importedIds: [String] = []
        let tombstones = (try? await ingestor.library.tombstones()) ?? []

        for (index, activity) in activities.enumerated() {
            if known.contains(activity.id) {
                summary.alreadyKnown += 1
                continue
            }
            // A session the rider deleted is skipped **silently and before the fetch**. The
            // automatic-pickup half is why this matters: an unattended import must never
            // resurrect a deletion, because there is nobody watching to notice that it did.
            if let stone = SessionTombstones.blocks(startDate: activity.startDate,
                                                    movingTimeS: activity.movingTimeS
                                                        .map(Double.init),
                                                    tombstones: tombstones) {
                summary.blockedTombstoneIds.append(stone.id)
                continue
            }
            let label = activity.name ?? activity.id
            progress?("Fetching \(index + 1)/\(activities.count): \(label)")
            do {
                if index > 0 { try? await Task.sleep(for: Self.pacingS) }
                let streams = try await client.streams(activityID: activity.id)
                let gpx = try StravaImport.gpx(activity: activity, streams: streams,
                                               producer: producer)
                switch try await ingestor.ingest(fitData: gpx,
                                                 filename: StravaImport.filename(for: activity),
                                                 source: .strava,
                                                 utcOffsetS: activity.resolvedUtcOffsetS) {
                case .imported:
                    summary.imported += 1
                    importedIds.append(activity.id)
                case .duplicate:
                    summary.duplicates += 1
                    // Remembered all the same: a duplicate is an activity that has been
                    // through here, and asking Strava about it again every sync would be the
                    // app failing to remember its own answer.
                    importedIds.append(activity.id)
                case .skipped:
                    break                  // no sport gate on hand-picked Strava activities
                case .replaced:
                    // Unreachable: a Strava copy is positions only and never replaces a
                    // row (`SessionIngestor.yields`). Counted as a duplicate if it ever did.
                    summary.duplicates += 1
                    importedIds.append(activity.id)
                }
            } catch StravaClient.Error.noStreams {
                summary.withoutStreams += 1
                importedIds.append(activity.id)
            } catch StravaImport.ImportError.noPositions, StravaImport.ImportError.noClock {
                summary.withoutStreams += 1
                importedIds.append(activity.id)
            } catch let error as StravaClient.Error {
                if case .rateLimited = error {
                    // Stop the run rather than grind through thirty more 429s. What was
                    // imported stays imported and the rest are still on Strava.
                    summary.rateLimited = true
                    summary.failed.append("\(label): \(error.description)")
                    break
                }
                summary.failed.append("\(label): \(error.description)")
            } catch {
                summary.failed.append("\(label): \(error)")
            }
        }

        log.found = summary.matching
        log.imported = summary.imported
        log.duplicates = summary.duplicates
        log.skipped = summary.alreadyKnown + summary.withoutStreams
        log.failed = summary.failed.count
        log.detail = summary.failed.isEmpty ? nil : summary.failed.prefix(20)
            .joined(separator: "\n")
        log.finishedAt = Date()
        let finished = log
        try? await ingestor.database.writer.write { db in try finished.update(db) }
        progress?(summary.shortDescription)
        return (summary, importedIds)
    }
}
