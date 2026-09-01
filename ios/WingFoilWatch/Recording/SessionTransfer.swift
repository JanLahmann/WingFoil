import Foundation
import OSLog
import WatchConnectivity

/// File-scope rather than a static member: the `WCSessionDelegate` callbacks below are
/// `nonisolated`, and a `static let` inside a `@MainActor` type inherits that isolation, so
/// logging from a delegate would not compile. `Logger` is `Sendable`, so a global `let` is
/// exactly as safe and reads the same at the call site.
private let log = Logger(subsystem: "de.lahmann.wingfoil.watch", category: "transfer")

/// Hands a finished `.cjw` container to the phone.
///
/// **`transferFile` and nothing else.** WatchConnectivity already solves the hard problem
/// here: a queued file transfer survives the watch going out of range, the phone being off,
/// both apps being killed, and the watch being put on the charger overnight. It is persisted
/// by the system and retried until it lands. Every retry scheme this app could write would be
/// a worse version of that one running on top of it — and it would be the version that loses
/// a session when the rider's phone is in a drybag on the beach, which is exactly when it is
/// needed.
///
/// So the contract is: assemble the file, hand it over, and let go. The recorder does not
/// wait for delivery to show the summary, and the file is not deleted until the system says
/// it arrived.
@MainActor
@Observable
final class SessionTransfer: NSObject {

    static let shared = SessionTransfer()

    /// Transfers the system is still holding. Shown on the start screen so a rider who has
    /// not opened the phone in a week can see that nothing has been lost.
    private(set) var pendingCount = 0
    private(set) var isReachable = false
    private(set) var lastError: String?

    private override init() {
        super.init()
    }

    /// Called once at launch. Activation is asynchronous and everything below tolerates being
    /// called before it completes — `transferFile` queues against an activating session.
    func activate() {
        guard WCSession.isSupported() else {
            log.error("WatchConnectivity is not supported on this device")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        refresh()
    }

    /// Queues one session file. Returns false only when WatchConnectivity is unavailable
    /// altogether, which on a paired watch does not happen.
    @discardableResult
    func send(_ url: URL, meta: WatchSessionMeta) -> Bool {
        guard WCSession.isSupported() else {
            lastError = "This watch cannot talk to the phone."
            return false
        }
        // The system's own queue survives launches, so on a cold start most of the outbox is
        // already in flight. Handing the same file over again would send the session twice —
        // harmless, because the phone dedupes on start time and duration, but it would spend
        // the rider's battery to make work the library then throws away.
        if WCSession.default.outstandingFileTransfers.contains(where: { $0.file.fileURL == url }) {
            log.info("\(url.lastPathComponent) is already queued; leaving it alone")
            return true
        }
        // Metadata rides along so the phone can log and de-duplicate without opening the
        // file. It must stay small and plist-legal — this is not the place for the session.
        let metadata: [String: Any] = [
            "kind": "cleanjibe.watch.session",
            "schema": meta.schema,
            "sessionId": meta.sessionId,
            "startEpoch": meta.startEpoch,
            "durationS": meta.durationS,
        ]
        WCSession.default.transferFile(url, metadata: metadata)
        refresh()
        log.info("queued \(url.lastPathComponent) for transfer to the phone")
        return true
    }

    func refresh() {
        guard WCSession.isSupported() else { return }
        pendingCount = WCSession.default.outstandingFileTransfers.count
        isReachable = WCSession.default.isReachable
    }
}

extension SessionTransfer: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: (any Error)?) {
        if let error {
            log.error("WCSession activation failed: \(error.localizedDescription)")
        }
        Task { @MainActor in self.refresh() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer,
                             error: (any Error)?) {
        let name = fileTransfer.file.fileURL.lastPathComponent
        if let error {
            // The system has already given up on this one. Keep the file: the next launch
            // sweeps the directory and re-queues anything still sitting there.
            log.error("transfer of \(name) failed: \(error.localizedDescription)")
            Task { @MainActor in
                self.lastError = error.localizedDescription
                self.refresh()
            }
            return
        }
        log.info("delivered \(name) to the phone")
        // Delivered, so the watch's copy has done its job. The phone owns the session now.
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        Task { @MainActor in
            self.lastError = nil
            self.refresh()
        }
    }
}
