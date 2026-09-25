import Foundation
import WingFoilKit

/// **The beta's counters, from the app's side** — one call per door, and nothing at all in
/// the release build.
///
/// The shape of the numbers, the wording of the report and the rule for when to ask live in
/// the kit (`UsageCounters`), where the test suite reads them. What lives here is the two
/// things a package cannot have: `UserDefaults`, and the call sites.
///
/// **Why a free function and not an injected service.** The call sites are twenty
/// one-liners scattered across views and the store, and every one of them is on a path that
/// already does real work — an import, a render, a mail. A counter that had to be reached
/// through the environment would be a counter that half those places quietly could not
/// reach, and the ones that could would pay an observation dependency for the privilege.
/// `Usage.record(.shareCard)` costs one dictionary write and one defaults write, on the
/// main actor, next to work measured in seconds.
///
/// **Outside `BETA` every function here is an empty body.** Not a flag checked at runtime:
/// the release binary contains no counter, no key and no blob, and a `usage.counters.v1`
/// left in defaults by a beta on the same phone is never read — the same rule the tuning
/// overrides and the windsurf switch already keep (docs/channels.md).
enum Usage {

    #if BETA

    /// One use that worked, start to finish: a page opened, a setting changed, a file
    /// written. `detail` is a short variant code, never free text.
    static func record(_ feature: UsageCounters.Feature, times: Int = 1,
                       detail: String? = nil) {
        mutate { $0.record(feature, times: times, detail: detail) }
    }

    /// One use that went wrong, start to finish. `reason` is a short code with nothing
    /// personal in it; for an `Error`, use the overload below.
    static func failed(_ feature: UsageCounters.Feature, reason: String) {
        mutate { $0.failed(feature, reason: reason) }
    }

    static func failed(_ feature: UsageCounters.Feature, error: any Error) {
        failed(feature, reason: UsageCounters.reason(for: error))
    }

    /// A try whose answer comes later (`finished`): a map on its way to the watch.
    static func started(_ feature: UsageCounters.Feature) {
        mutate { $0.attempt(feature) }
    }

    /// The answer to an earlier `started`: nil worked, a reason failed.
    static func finished(_ feature: UsageCounters.Feature, failure: String? = nil,
                         detail: String? = nil) {
        mutate {
            if let failure {
                $0.failed(feature, reason: failure, attempt: false)
            } else {
                $0.succeeded(feature, detail: detail)
            }
        }
    }

    /// An import run through one door. One tally per run, not per session: a sync that
    /// found nothing new still worked. A run with a file that would not read is a failure.
    /// The sessions it brought move the ask along, because "every fifth session imported"
    /// is a promise about riding, not about tapping.
    static func recordImport(_ source: ImportSource, automatic: Bool = false,
                             imported: Int, failed: Int) {
        guard let feature = feature(for: source, automatic: automatic) else { return }
        mutate {
            if failed > 0 {
                $0.failed(feature, reason: String(failed) + " would not read")
            } else {
                $0.record(feature)
            }
            if imported > 0 { $0.sessionsSinceAsk += imported }
        }
    }

    /// A failure the rider was shown, in the words he was shown it in.
    static func failure(_ message: String) {
        mutate { $0.recordFailure(message) }
    }

    /// The doors the report names. The Garmin summary card is not among them: it is counted,
    /// in full, by the `Library` block of the mail that carries this one.
    private static func feature(for source: ImportSource,
                                automatic: Bool) -> UsageCounters.Feature? {
        switch source {
        case .icu: automatic ? .icuBackground : .importIcu
        case .file: .importFile
        case .strava: .importStrava
        case .appleHealth: automatic ? .healthAutoImport : .importHealth
        case .airdrop: .importShareSheet
        case .gdpr: .importZip
        case .appleWatch: .appleWatchRecording
        case .watchDirect: .watchTransfer
        default: nil
        }
    }

    // MARK: - Reading

    static var counters: UsageCounters {
        lock.lock()
        defer { lock.unlock() }
        return loaded()
    }

    /// Whether the library should offer the card at the top of the list.
    ///
    /// Never under the simulator screenshot hooks, for the same reason the splash is never
    /// built under them (`Splash.isWanted`): `UI_IMPORT_FIXTURES` walks a season through
    /// the import door in one go, which is exactly the condition the ask waits for, and a
    /// card at the top of the list would change every existing shot.
    static var askIsDue: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment.keys.contains(where: { $0.hasPrefix("UI_") }) {
            return false
        }
        #endif
        return counters.askIsDue()
    }

    /// The rider answered — he opened the mail (`snooze: false`) or said Not now.
    static func askAnswered(snooze: Bool) {
        mutate { $0.askAnswered(snooze: snooze) }
    }

    // MARK: - Storage

    /// `UserDefaults` is its own synchronisation, but a read-modify-write across two calls
    /// is not: two doors counted from different tasks in the same instant would otherwise
    /// lose one of them. The lock is uncontended in every real case — these are main-actor
    /// call sites — and costs nothing when it is.
    nonisolated(unsafe) private static let lock = NSLock()

    private static func mutate(_ change: (inout UsageCounters) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var counters = loaded()
        change(&counters)
        guard let data = try? counters.jsonData() else { return }
        UserDefaults.standard.set(data, forKey: UsageCounters.defaultsKey)
    }

    /// Call with the lock held. A blob that cannot be decoded at all — hand-edited, or
    /// truncated by a crash mid-write — starts again rather than taking the feature down
    /// with it; nothing here is data the rider can lose anything by losing.
    private static func loaded() -> UsageCounters {
        UserDefaults.standard.data(forKey: UsageCounters.defaultsKey)
            .flatMap(UsageCounters.decode)
            ?? UsageCounters(firstLaunch: Date())
    }

    #else

    /// The release channel. Every call site above compiles to nothing.
    static func record(_ feature: UsageCounters.Feature, times: Int = 1,
                       detail: String? = nil) {}
    static func failed(_ feature: UsageCounters.Feature, reason: String) {}
    static func failed(_ feature: UsageCounters.Feature, error: any Error) {}
    static func started(_ feature: UsageCounters.Feature) {}
    static func finished(_ feature: UsageCounters.Feature, failure: String? = nil,
                         detail: String? = nil) {}
    static func recordImport(_ source: ImportSource, automatic: Bool = false,
                             imported: Int, failed: Int) {}
    static func failure(_ message: String) {}

    #endif
}
