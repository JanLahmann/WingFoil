import Foundation
import MetricKit
import OSLog
import WingFoilKit

private let log = Logger(subsystem: "de.lahmann.wingfoil", category: "diagnostics")

/// **The crashes and hangs iOS already knows about, kept where the feedback mail can reach
/// them.**
///
/// The app has no crash reporter and no server to send one to, so a failure in the field
/// reaches nobody: TestFlight's beta feedback carries a screenshot and the tester's sentence
/// but not the crash log, and an App Store rider has no route at all. `MXMetricManager` is
/// the one signal that keeps the no-servers stance — iOS collects the diagnostics itself and
/// hands them to the app a day or so later, on device, with no SDK in between.
///
/// **What this half does: subscribe, reduce, keep ten.** The payload is reduced to four
/// fields by `CrashLog`, which lives in the kit where the test suite reads it; what is left
/// here is the subscription, the file and the lock. Every channel subscribes, the App Store
/// one included, because that is the channel whose riders have no other route.
///
/// **Nothing is sent by this type.** The digests sit in a file in the app's own container
/// until a rider opens a feedback mail, and he reads every line of the block before he taps
/// Send. "Start over" wipes them with the rest of Application Support.
final class CrashDiagnostics: NSObject, @unchecked Sendable, MXMetricManagerSubscriber {

    static let shared = CrashDiagnostics()

    /// Where the kept digests live. Application Support rather than Caches, for the reason
    /// the watch inbox is there too: the system may evict Caches, and a crash report the
    /// phone quietly forgot before the rider got round to writing his mail is worth nothing.
    private let file: URL?

    /// The payload callback arrives on a queue of MetricKit's choosing and the mail is
    /// composed on the main actor. Both touch one small file, so both take the lock.
    private let lock = NSLock()

    init(directory: URL? = nil) {
        if let directory {
            file = directory.appendingPathComponent("crashes.json")
        } else {
            file = Self.defaultFile()
        }
        super.init()
    }

    private static func defaultFile() -> URL? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                      in: .userDomainMask,
                                                      appropriateFor: nil, create: true)
        else { return nil }
        let directory = base.appendingPathComponent("Diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        return directory.appendingPathComponent("crashes.json")
    }

    /// Called once, at launch. iOS delivers what it has accumulated on its own schedule
    /// afterwards — usually once a day, and immediately on a debug build under Xcode's
    /// Debug → Simulate MetricKit Payloads.
    func subscribe() {
        MXMetricManager.shared.add(self)
    }

    /// What the feedback mail prints, newest first.
    func kept() -> [CrashDigest] {
        lock.lock()
        defer { lock.unlock() }
        guard let file, let data = try? Data(contentsOf: file) else { return [] }
        return CrashLog.decode(data)
    }

    // MARK: - The payload

    /// **Spelled with its selector on purpose.** Every method of
    /// `MXMetricManagerSubscriber` is `@optional`, so a Swift name that is nearly right
    /// compiles without a word and is simply never called — the same trap the watch link
    /// hit from the other side. `didReceiveDiagnosticPayloads:` is the one iOS sends.
    ///
    /// `nonisolated`, and the work is done before returning: the payloads are not
    /// `Sendable`, so they must not be carried into a `Task`, and reducing them is a JSON
    /// parse of a few kilobytes.
    @objc(didReceiveDiagnosticPayloads:)
    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let arrived = payloads.flatMap {
            CrashLog.digests(fromPayloadJSON: $0.jsonRepresentation())
        }
        guard !arrived.isEmpty else { return }
        absorb(arrived)
    }

    /// The kept file, with the new digests merged in and capped at `CrashLog.keepCount`.
    ///
    /// A write that fails is logged and dropped. This is a footnote to a mail; it must
    /// never be the reason anything else does not happen.
    func absorb(_ arrived: [CrashDigest]) {
        lock.lock()
        defer { lock.unlock() }
        guard let file else { return }
        let kept = CrashLog.merge(CrashLog.decode((try? Data(contentsOf: file)) ?? Data()),
                                  with: arrived)
        guard let data = CrashLog.encode(kept) else { return }
        do {
            try data.write(to: file, options: .atomic)
            log.info("kept \(kept.count) diagnostic digests")
        } catch {
            log.error("could not keep the diagnostics: \(error.localizedDescription)")
        }
    }
}
