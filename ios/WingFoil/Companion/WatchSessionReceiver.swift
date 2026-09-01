import Foundation
import OSLog
import WatchConnectivity
import WingFoilKit

/// File-scope rather than static members on the class below. Both are reached from
/// `nonisolated` `WCSessionDelegate` callbacks, and anything declared inside a `@MainActor`
/// type inherits that isolation — so a `static let log` cannot be read from a delegate, and a
/// `static func inbox()` cannot be called from one. `Logger` is `Sendable` and `inboxURL` is a
/// pure path computation, so neither needs the main actor for safety; they only had it by
/// accident of where they were written.
private let log = Logger(subsystem: "de.lahmann.wingfoil", category: "watchlink")

/// Where received containers wait to be imported. Application Support rather than Caches: the
/// system may evict Caches under pressure, and this holds the only copy of a session between
/// the transfer completing and the import running.
private func watchInboxURL() throws -> URL {
    let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                           in: .userDomainMask,
                                           appropriateFor: nil, create: true)
    let url = base.appendingPathComponent("WatchInbox", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Receives `.cjw` session containers from the CleanJibe watch app.
///
/// **The delegate callback copies and gets out of the way.** WatchConnectivity hands over a
/// file in a temporary location that it deletes the moment the delegate returns, and it can
/// deliver one while the app is not running at all — iOS launches the app in the background
/// to take it. So the callback does exactly one thing that cannot be deferred: it copies the
/// bytes into an inbox directory the app owns. The import happens afterwards, on the main
/// actor, and may happen on the next launch instead if this one is killed first.
///
/// That is why the inbox is a directory on disk rather than an in-memory queue. A rider who
/// stops recording with his phone in a drybag, walks up the beach, and opens the app two
/// hours later gets his session — the file arrived while the app was asleep, and the sweep at
/// launch finds it.
///
/// This is a *different* link from `ConnectIQCompanionLink`, which talks to a Garmin watch
/// through Garmin Connect Mobile and carries a summary card with no recording behind it.
/// Both can be live at once on one phone; they share nothing but the word "watch".
@MainActor
final class WatchSessionReceiver: NSObject {

    static let shared = WatchSessionReceiver()

    /// Fires after a file lands, so a foregrounded app imports it immediately rather than at
    /// the next launch.
    var onArrival: (@MainActor () -> Void)?

    private override init() {
        super.init()
    }

    static func pending() -> [URL] {
        guard let inbox = try? watchInboxURL(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: inbox, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == TrackFormat.watch.fileExtension }.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
    }

    func activate() {
        guard WCSession.isSupported() else {
            log.info("WatchConnectivity is unavailable — no Apple Watch on this phone")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }
}

extension WatchSessionReceiver: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: (any Error)?) {
        if let error {
            log.error("WCSession activation failed: \(error.localizedDescription)")
            return
        }
        log.info("WCSession active (paired watch app installed: \(session.isWatchAppInstalled))")
        // A file may already have been delivered while the app was not running.
        Task { @MainActor in self.onArrival?() }
    }

    /// Reactivation after a watch switch. Without both of these the session is dead once the
    /// rider pairs a different watch, and nothing says so.
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // Synchronous and before returning: `file.fileURL` is gone the moment this method
        // exits, and there is no second delivery.
        do {
            let inbox = try watchInboxURL()
            // Named for the transfer, not for the session, so two containers that describe
            // the same afternoon still both land — the library's dedupe decides what to do
            // with them, and it is much better at that than a filename is.
            let name = file.fileURL.lastPathComponent
            let destination = inbox.appendingPathComponent(
                name.isEmpty ? "\(UUID().uuidString).cjw" : name)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: file.fileURL, to: destination)
            log.info("received watch session \(name) (\(file.metadata?.description ?? "no metadata"))")
        } catch {
            log.error("could not take delivery of a watch session: \(error.localizedDescription)")
            return
        }
        Task { @MainActor in self.onArrival?() }
    }
}
