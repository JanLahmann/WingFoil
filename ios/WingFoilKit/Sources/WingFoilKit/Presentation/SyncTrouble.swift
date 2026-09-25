import Foundation

/// **A sync that fails on a flaky network never interrupts the rider** (fb/quiet-sync,
/// 25 Sep 2026).
///
/// The shape behind the report: the app opened on the beach, Strava's automatic pickup ran
/// into a dead connection, and a modal "Something went wrong · Strava could not be reached"
/// stood between the rider and yesterday's session. Nothing he could do about it, nothing
/// lost, and it would have worked ten minutes later.
///
/// So every automatic source now reports into one place, and this file decides three things
/// about each failure, all pure so the tests can pin them:
///
/// 1. **What kind it is** (`SyncFailureKind.classify`). *Transient* — no network, a timeout,
///    DNS, a server hiccup — is retried quietly. *Actionable* — the account was revoked, the
///    key rejected, a rate limit hit — needs the rider, and says what to do.
/// 2. **When to try again** (`SyncRetryPolicy`). A short backoff while the app is open. The
///    ordinary schedule (launch, foreground, a pull) is untouched and still runs.
/// 3. **When to say anything** (`SyncTrouble.isShown`). A transient failure is silent until it
///    has happened `SyncRetryPolicy.quietFailures` times in a row; an actionable one is shown
///    at once, inline, with its fix. Never as a modal on launch: that rule is the app's, and
///    the store enforces it (`SessionStore.reportSync`).
public enum SyncSource: String, CaseIterable, Codable, Sendable {
    case strava
    case intervals
    case health
    case iCloud
    case watch

    /// The source an import door belongs to, for the doors that run by themselves. A file
    /// the rider picked has no source here: he is holding it, so its failure is his to see.
    public init?(importSource: ImportSource) {
        switch importSource {
        case .appleHealth: self = .health
        case .appleWatch, .watch, .watchDirect: self = .watch
        case .strava: self = .strava
        case .icu: self = .intervals
        case .file, .gdpr, .airdrop, .fixtures, .example: return nil
        }
    }

    /// The name as a rider says it, first letter as written by its owner.
    public var name: String {
        switch self {
        case .strava: "Strava"
        case .intervals: "intervals.icu"
        case .health: "Apple Health"
        case .iCloud: "iCloud Drive"
        case .watch: "Your watch"
        }
    }
}

/// What went wrong, reduced to what the app and the rider do about it.
public enum SyncFailureKind: Codable, Equatable, Sendable {
    /// The request never got through, or the other end had a moment. Retried quietly.
    case transient
    /// The other end asked us to wait. Retried after its own `Retry-After` when it sent one.
    case rateLimited(retryAfterS: Int?)
    /// Strava no longer accepts the stored connection. The fix is connecting again.
    case reconnect
    /// intervals.icu refuses the key, or there is none. The fix is pasting it again.
    case keyRejected
    /// Strava's cap on connected riders. Nothing the rider can retry his way out of.
    case stravaFull
    /// Anything else: a recording that would not read, a database that would not write.
    /// `detail` is a short diagnostic, never a response body.
    case other(detail: String?)

    /// Worth trying again without asking the rider.
    public var isRetryable: Bool {
        switch self {
        case .transient, .rateLimited: true
        case .reconnect, .keyRejected, .stravaFull, .other: false
        }
    }

    /// Needs the rider to do something, so it is shown at the first failure.
    public var isActionable: Bool {
        switch self {
        case .rateLimited, .reconnect, .keyRejected, .stravaFull: true
        case .transient, .other: false
        }
    }

    /// Total by construction: an error this does not recognise is `.other`, never a crash and
    /// never a silent success.
    public static func classify(_ error: any Error) -> SyncFailureKind {
        switch error {
        case let strava as StravaClient.Error:
            switch strava {
            case .transport: return .transient
            case .unauthorized, .notConnected: return .reconnect
            case .athleteLimit: return .stravaFull
            case .rateLimited(let after): return .rateLimited(retryAfterS: after)
            case .http(let status, _): return classify(httpStatus: status, auth: .reconnect)
            case .notConfigured, .decoding, .noStreams:
                return .other(detail: strava.description)
            }
        case let icu as IcuClient.Error:
            switch icu {
            case .transport: return .transient
            case .unauthorized, .missingKey: return .keyRejected
            case .http(let status, _): return classify(httpStatus: status, auth: .keyRejected)
            case .decoding: return .other(detail: icu.description)
            }
        case let url as URLError:
            return transientURLCodes.contains(url.code)
                ? .transient : .other(detail: url.localizedDescription)
        default:
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain,
               transientURLCodes.contains(URLError.Code(rawValue: ns.code)) {
                return .transient
            }
            if ns.domain == NSPOSIXErrorDomain, transientPOSIXCodes.contains(ns.code) {
                return .transient
            }
            return .other(detail: ns.localizedDescription)
        }
    }

    /// A status code on its own. `auth` is what a 401/403 means for this source.
    static func classify(httpStatus status: Int, auth: SyncFailureKind) -> SyncFailureKind {
        switch status {
        case 401, 403: auth
        case 429: .rateLimited(retryAfterS: nil)
        case 408, 500...599: .transient
        default: .other(detail: "HTTP \(status)")
        }
    }

    /// The URL loading failures that mean "the network, not the request". A captive portal
    /// shows up as a failed TLS handshake, which is the beach café's Wi-Fi, so it is here too.
    static let transientURLCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
        .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff,
        .callIsActive, .cannotLoadFromNetwork, .backgroundSessionWasDisconnected,
        .secureConnectionFailed, .cancelled,
    ]

    /// ENETDOWN, ENETUNREACH, ECONNABORTED, ECONNRESET, ETIMEDOUT, EHOSTDOWN, EHOSTUNREACH.
    static let transientPOSIXCodes: Set<Int> = [50, 51, 53, 54, 60, 64, 65]
}

/// When the next quiet try runs. The app's own schedule (launch, foreground, a pull) is not
/// this: these are the extra tries in between, while the app is open.
public enum SyncRetryPolicy {
    /// A transient failure stays silent until it has happened this many times in a row.
    public static let quietFailures = 3
    /// The waits after the first, second and third failure in a row. After that the next try
    /// is the ordinary one, at the next launch or foreground.
    public static let delaysS: [TimeInterval] = [30, 120, 600]
    /// A `Retry-After` longer than this is not waited out in-process.
    public static let longestWaitS: TimeInterval = 900

    /// Seconds until the next quiet try after `failures` in a row, or nil for none.
    public static func delay(afterFailures failures: Int, kind: SyncFailureKind) -> TimeInterval? {
        switch kind {
        case .transient:
            guard failures >= 1, failures <= delaysS.count else { return nil }
            return delaysS[failures - 1]
        case .rateLimited(let after):
            guard failures <= delaysS.count else { return nil }
            let wait = after.map(TimeInterval.init) ?? delaysS[min(failures, delaysS.count) - 1]
            return wait <= longestWaitS ? max(wait, 1) : nil
        case .reconnect, .keyRejected, .stravaFull, .other:
            return nil
        }
    }
}

/// One source's run of failures, from the first to the last try.
public struct SyncTrouble: Codable, Equatable, Sendable {
    public var kind: SyncFailureKind
    /// Failures in a row. Reset by a success, which removes the whole value.
    public var failures: Int
    public var lastTry: Date
    /// The rider asked for this try himself, so the result is his to see at once.
    public var riderAsked: Bool

    public init(kind: SyncFailureKind, failures: Int = 1, lastTry: Date, riderAsked: Bool = false) {
        self.kind = kind
        self.failures = failures
        self.lastTry = lastTry
        self.riderAsked = riderAsked
    }

    /// Whether the rider sees it at all. Silent is the default for a network blip.
    public var isShown: Bool {
        riderAsked || kind.isActionable || failures >= SyncRetryPolicy.quietFailures
            || !kind.isRetryable
    }

    /// The short cause, for Settings: "Last try failed: no connection".
    public var cause: String {
        switch kind {
        case .transient: "no connection"
        case .rateLimited: "Strava asked us to wait"
        case .reconnect: "Strava needs you to connect again"
        case .keyRejected: "intervals.icu did not accept the key"
        case .stravaFull: "Strava is full for new riders"
        case .other(let detail): detail ?? "it did not finish"
        }
    }

    /// Settings, under the source's own section.
    public var settingsLine: String { "Last try failed: " + cause }
}

/// Every source's trouble, in one value the store keeps and persists.
public struct SyncTroubles: Codable, Equatable, Sendable {
    public private(set) var bySource: [SyncSource: SyncTrouble] = [:]

    public init() {}

    public subscript(source: SyncSource) -> SyncTrouble? { bySource[source] }

    /// A failure. Returns the trouble as it now stands, so the caller can ask for its delay.
    @discardableResult
    public mutating func recordFailure(_ kind: SyncFailureKind, from source: SyncSource,
                                       at now: Date, riderAsked: Bool) -> SyncTrouble {
        var trouble = bySource[source]
            ?? SyncTrouble(kind: kind, failures: 0, lastTry: now)
        trouble.kind = kind
        trouble.failures += 1
        trouble.lastTry = now
        trouble.riderAsked = riderAsked
        bySource[source] = trouble
        return trouble
    }

    /// A try that worked. The whole run is forgotten, because the line it would show is
    /// no longer true.
    public mutating func recordSuccess(from source: SyncSource) {
        bySource[source] = nil
    }

    /// What the library's footer says, one line per source that has something to say, in a
    /// fixed order so the lines do not swap places between two looks.
    public var footerLines: [String] {
        SyncSource.allCases.compactMap { source in
            guard let trouble = bySource[source], trouble.isShown else { return nil }
            return Self.footerLine(source, trouble.kind)
        }
    }

    /// Register 3, the footer's own: "63 sessions · pull to sync intervals.icu".
    static func footerLine(_ source: SyncSource, _ kind: SyncFailureKind) -> String {
        switch kind {
        // intervals.icu has no quiet pickup of its own to wait for: a pull is the next try.
        case .transient where source == .intervals: "intervals.icu not reached · pull to try again"
        case .transient: "\(source.name) not reached · trying again later"
        case .rateLimited: "\(source.name) asked us to wait · trying again later"
        case .reconnect: "Strava needs you to connect again · Settings → Strava"
        case .keyRejected: "intervals.icu did not accept the key · Settings → intervals.icu"
        case .stravaFull: "Strava is full for new riders · Settings → Strava"
        case .other:
            switch source {
            case .health: "A workout from Apple Health would not read"
            case .watch: "A session from your watch did not come in"
            case .strava, .intervals, .iCloud: "\(source.name) did not finish"
            }
        }
    }
}
