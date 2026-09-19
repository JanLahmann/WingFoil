// The direct transfer is a DEV channel door (docs/channels.md, docs/transfer-format.md §5):
// the release and beta binaries carry no inbox, no page assembler and no `.cjr` on their
// share sheets. Gating the whole file is what makes that true of the binary rather than only
// of the UI. The kit's `DirectStream`, `DirectPage` and `DirectStreamParser` compile in every
// channel and are tested there; it is this receiver that is dev-only.
#if DEV
import Foundation
import OSLog
import WingFoilKit

/// File-scope for the same reason `WatchSessionReceiver`'s are: both are reached from code
/// that is not on the main actor, and anything declared inside a `@MainActor` type inherits
/// that isolation. `Logger` is `Sendable` and the two path helpers are pure path arithmetic.
private let log = Logger(subsystem: "de.lahmann.wingfoil", category: "directtransfer")

/// Where the watch's pages wait. Application Support rather than Caches: the system may evict
/// Caches under pressure, and between the last page arriving and the import running this
/// holds the only copy of a session on the phone.
private func garminInboxURL() throws -> URL {
    let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                           in: .userDomainMask,
                                           appropriateFor: nil, create: true)
    let url = base.appendingPathComponent("GarminInbox", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// What the last direct transfer was — the three facts Settings → Garmin watch shows.
struct DirectTransferReceipt: Codable, Sendable, Equatable {
    /// The session's own start, off the stream header. Not when it arrived.
    var sessionStart: Date
    var pages: Int
    /// How long the transfer took, first page to last. The probe measured about two seconds
    /// a page, so a two-hour session is about half a minute.
    var seconds: Double
    /// True for a stream that was assembled after a day of silence rather than completed.
    var cutShort: Bool
}

/// **The receiving half of the direct transfer** (docs/transfer-format.md §3 and §5).
///
/// The watch sends a session as pages of at most 8 000 bytes, exactly one in flight, the next
/// one from `onComplete`. This writes each page to disk, answers `cjrAck` at once, and when
/// the stream is whole concatenates the pages into a `<sid>.cjr` that goes through
/// `SessionIngestor` like any other recording.
///
/// **Why the pages are files and not an array.** A page that is only in memory is a page lost
/// to a crash, a memory warning or the rider switching apps, and the watch has already freed
/// it — the ACK said so. The directory is also what makes the 24-hour rule possible: a
/// transfer interrupted on the beach is still on the phone that evening, and the sweep at the
/// next launch finds it. It is the same arrangement `WatchSessionReceiver` uses for the Apple
/// Watch's `.cjw`, for the same reasons.
///
/// **What it never does is decide.** It does not parse the stream, it does not know what a
/// session is and it does not touch the library. It produces a file and raises `onArrival`;
/// `SessionStore` imports.
@MainActor
final class DirectTransferInbox {

    static let shared = DirectTransferInbox()

    /// A stream with no page for this long is assembled as far as it goes and imported.
    /// A day, because the rider who packed up with the transfer half done opens the app that
    /// evening or the next morning, and until he does the watch may still finish it.
    static let idleTimeout: TimeInterval = 24 * 60 * 60

    /// `["cjrAck": [sid, st, p]]` onto the radio. Set by `ConnectIQCompanionLink`, which owns
    /// the SDK. Integers rather than a built dictionary so nothing un-`Sendable` crosses.
    var acknowledge: ((_ session: Int, _ stream: Int, _ page: Int) -> Void)?
    /// `["cjrNeed": [sid, st, [p, …]]]`, the same way.
    var requestPages: ((_ session: Int, _ stream: Int, _ pages: [Int]) -> Void)?

    /// Raised when a `<sid>.cjr` is ready, so a foregrounded app imports it at once rather
    /// than at the next launch.
    var onArrival: (@MainActor () -> Void)?

    /// The last completed transfer, for the Settings row. Kept in defaults so the row
    /// survives a relaunch — "it says ready" and "something has actually come through" are
    /// different facts, and this is the second one.
    private(set) var lastReceipt: DirectTransferReceipt? = DirectTransferInbox.loadReceipt()

    /// Pages refused by `DirectPage`, counted rather than surfaced. A dropped page costs the
    /// rider nothing — the watch resends what it was not acknowledged for — but a number that
    /// only goes up is the first thing to look at when the transfer "does not work".
    private(set) var rejectedPages = 0

    /// When the first page of a stream arrived this launch, so the receipt can say how long
    /// the transfer took. Keyed by session start.
    private var startedAt: [Int: Date] = [:]
    /// The need list last sent per stream, so a completed stream is told once and a stream
    /// with a gap is not told the same thing on every page.
    private var lastNeed: [String: [Int]] = [:]

    private init() {}

    // MARK: - Arrival

    /// One page off the link. Everything here is idempotent: the watch resends a page it was
    /// not acknowledged for, and a page it already sent is acknowledged again rather than
    /// written twice.
    func accept(_ page: DirectPage) {
        do {
            let directory = try Self.streamURL(session: page.sessionStartEpochS,
                                               stream: page.stream)
            let file = directory.appendingPathComponent("p\(page.index).bin")
            let already = FileManager.default.fileExists(atPath: file.path)
            if !already {
                try page.bytes.write(to: file, options: .atomic)
                startedAt[page.sessionStartEpochS] = startedAt[page.sessionStartEpochS] ?? Date()
            }
            // The ACK goes out whether the page was new or a repeat, and before anything
            // else: an unacknowledged page is a page the watch will send again, and the
            // radio is the slow part.
            acknowledge?(page.sessionStartEpochS, page.stream, page.index)
            guard !already else { return }

            var state = Self.state(in: directory)
            if page.isLast {
                state.isLast = true
                state.pageCount = max(state.pageCount, max(page.pageCount, page.index + 1))
            } else if page.pageCount > 0 {
                state.pageCount = max(state.pageCount, page.pageCount)
            }
            try Self.write(state, in: directory)
            try finishIfWhole(session: page.sessionStartEpochS, stream: page.stream,
                              directory: directory, state: state)
        } catch {
            log.error("could not take delivery of a direct page: \(error.localizedDescription)")
        }
    }

    /// A page the link could not decode. Counted, never shown.
    func reject() { rejectedPages += 1 }

    // MARK: - Completion

    /// The need list, and then the assembly.
    ///
    /// `cjrNeed` goes out **every time the last page has arrived** — with the pages that are
    /// missing, or with an empty list, which is the watch's signal that the stream is whole
    /// and its buffers can be freed. Sending it only for gaps would leave a watch that lost
    /// nothing holding a session's pages until it was next restarted.
    private func finishIfWhole(session: Int, stream: Int, directory: URL,
                               state: DirectStreamState) throws {
        guard state.isLast, state.pageCount > 0 else { return }
        let missing = (0..<state.pageCount).filter {
            !FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("p\($0).bin").path)
        }
        let key = "\(session)/\(stream)"
        if lastNeed[key] != missing {
            lastNeed[key] = missing
            requestPages?(session, stream, Array(missing.prefix(DirectPage.maxNeed)))
        }
        guard missing.isEmpty else { return }
        try assemble(session: session, stream: stream, directory: directory,
                     pages: Array(0..<state.pageCount), cutShort: false)
        lastNeed[key] = nil
    }

    /// Concatenates the pages, in order and with nothing added, into `<sid>.cjr` — then
    /// deletes them. The archive of a stream is exactly that concatenation
    /// (docs/transfer-format.md §1).
    private func assemble(session: Int, stream: Int, directory: URL, pages: [Int],
                          cutShort: Bool) throws {
        guard stream == DirectStream.recordStream else {
            // Stream 1 is dev3's wrist magnitudes and has no parser yet. Its pages are left
            // where they are rather than concatenated into a file nothing can read.
            log.info("direct stream \(stream) is not the record stream — left in the inbox")
            return
        }
        var archive = Data()
        for index in pages {
            let file = directory.appendingPathComponent("p\(index).bin")
            guard let data = try? Data(contentsOf: file) else { break }
            archive.append(data)
        }
        guard !archive.isEmpty else { return }

        let inbox = try garminInboxURL()
        let destination = inbox.appendingPathComponent("\(session).\(TrackFormat.direct.fileExtension)")
        try archive.write(to: destination, options: .atomic)
        // The pages go only after the file they became is on disk. This stream's directory
        // and not the session's: dev3's wrist stream is a sibling of it and is not this
        // one's to delete. The session's own directory follows once it is empty.
        try? FileManager.default.removeItem(at: directory)
        let sessionDirectory = directory.deletingLastPathComponent()
        if (try? FileManager.default.contentsOfDirectory(at: sessionDirectory,
                                                        includingPropertiesForKeys: nil))?
            .isEmpty == true {
            try? FileManager.default.removeItem(at: sessionDirectory)
        }

        let receipt = DirectTransferReceipt(
            sessionStart: Date(timeIntervalSince1970: Double(session)),
            pages: pages.count,
            seconds: Date().timeIntervalSince(startedAt[session] ?? Date()),
            cutShort: cutShort)
        lastReceipt = receipt
        Self.save(receipt)
        startedAt[session] = nil
        log.info("direct session \(session) assembled from \(pages.count) pages, \(archive.count) bytes")
        onArrival?()
    }

    // MARK: - The sweep

    /// Assembled streams waiting to be imported, oldest first. The peer of
    /// `WatchSessionReceiver.pending()`, and read at launch for the same reason: a stream may
    /// have completed while the app was killed before it could import.
    static func pending() -> [URL] {
        guard let inbox = try? garminInboxURL(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: inbox, includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.pathExtension == TrackFormat.direct.fileExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// **A stream that never completed.** After a day without a page it is assembled as far
    /// as it goes — up to the first gap, so what is imported still decodes — and marked cut
    /// short on the receipt. The alternative is a directory of pages that is never a session,
    /// and an afternoon the rider rode that the app quietly decided not to show him.
    func sweepStaleStreams(now: Date = Date()) {
        guard let inbox = try? garminInboxURL(),
              let sessions = try? FileManager.default.contentsOfDirectory(
                at: inbox, includingPropertiesForKeys: nil) else { return }
        for sessionDirectory in sessions where sessionDirectory.hasDirectoryPath {
            guard let session = Int(sessionDirectory.lastPathComponent) else { continue }
            guard let streams = try? FileManager.default.contentsOfDirectory(
                at: sessionDirectory, includingPropertiesForKeys: nil) else { continue }
            for streamDirectory in streams where streamDirectory.hasDirectoryPath {
                guard let stream = Int(streamDirectory.lastPathComponent) else { continue }
                let state = Self.state(in: streamDirectory)
                guard let touched = Self.newestChange(in: streamDirectory),
                      now.timeIntervalSince(touched) > Self.idleTimeout else { continue }
                // Everything from page 0 up to the first hole. A page is only decodable
                // after the pages before it, so stopping at the gap is what keeps the
                // archive readable rather than half a track with a jump in it.
                var pages: [Int] = []
                var index = 0
                while FileManager.default.fileExists(
                    atPath: streamDirectory.appendingPathComponent("p\(index).bin").path) {
                    pages.append(index)
                    index += 1
                }
                guard !pages.isEmpty else { continue }
                let whole = state.isLast && state.pageCount == pages.count
                log.info("direct stream \(session)/\(stream) went quiet — importing \(pages.count) pages")
                try? assemble(session: session, stream: stream, directory: streamDirectory,
                              pages: pages, cutShort: !whole)
            }
        }
    }

    // MARK: - On disk

    /// What a stream has told us about itself: how many pages it has, and whether the last
    /// one has arrived. Kept beside the pages rather than in memory so the answer survives
    /// the app being killed between two pages.
    struct DirectStreamState: Codable, Sendable, Equatable {
        var pageCount = 0
        var isLast = false
    }

    private static func streamURL(session: Int, stream: Int) throws -> URL {
        let url = try garminInboxURL()
            .appendingPathComponent("\(session)", isDirectory: true)
            .appendingPathComponent("\(stream)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func stateURL(in directory: URL) -> URL {
        directory.appendingPathComponent("stream.json")
    }

    static func state(in directory: URL) -> DirectStreamState {
        guard let data = try? Data(contentsOf: stateURL(in: directory)),
              let state = try? JSONDecoder().decode(DirectStreamState.self, from: data) else {
            return DirectStreamState()
        }
        return state
    }

    static func write(_ state: DirectStreamState, in directory: URL) throws {
        try JSONEncoder().encode(state).write(to: stateURL(in: directory), options: .atomic)
    }

    private static func newestChange(in directory: URL) -> Date? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return nil }
        return files.compactMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
        }.max()
    }

    // MARK: - The receipt

    private static let receiptKey = "lastDirectTransfer.v1"

    private static func loadReceipt() -> DirectTransferReceipt? {
        guard let data = UserDefaults.standard.data(forKey: receiptKey) else { return nil }
        return try? JSONDecoder().decode(DirectTransferReceipt.self, from: data)
    }

    private static func save(_ receipt: DirectTransferReceipt) {
        guard let data = try? JSONEncoder().encode(receipt) else { return }
        UserDefaults.standard.set(data, forKey: receiptKey)
    }
}

#endif
