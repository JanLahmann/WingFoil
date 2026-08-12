import Foundation

/// A sync or key-check failure, translated into something a rider can act on.
///
/// `IcuClient.Error` is written for the log; this is written for the screen. The two are
/// deliberately separate: "intervals.icu HTTP 401: {}" tells you what happened, and only
/// "the key is wrong, regenerate it" tells you what to do. The mapping is pure, so the
/// tests can pin every branch of it.
public struct IcuProblem: Sendable, Equatable, Codable {

    public enum Kind: String, Sendable, Codable, CaseIterable {
        /// Nothing configured yet.
        case noKey
        /// 401/403 — the key is wrong, or was regenerated.
        case unauthorized
        /// The request never reached intervals.icu.
        case network
        /// It answered, with an error of its own.
        case server
        /// It answered fine, and had nothing for us.
        case empty
        /// Anything else, including a response we could not decode.
        case unknown
    }

    public let kind: Kind
    /// Diagnostic crumb for the curious (an HTTP status, a decoder message). Never the key,
    /// and never a response body — a body can echo back whatever was sent.
    public let detail: String?

    public init(kind: Kind, detail: String? = nil) {
        self.kind = kind
        self.detail = detail
    }

    /// Headline — one short phrase, no punctuation.
    public var title: String {
        switch kind {
        case .noKey: "No API key yet"
        case .unauthorized: "intervals.icu rejected the key"
        case .network: "Could not reach intervals.icu"
        case .server: "intervals.icu had a problem"
        case .empty: "Connected, but nothing came back"
        case .unknown: "The sync did not finish"
        }
    }

    /// What happened, in one sentence.
    public var message: String {
        switch kind {
        case .noKey:
            "WingFoil has no intervals.icu key yet, so there is nothing to sync with."
        case .unauthorized:
            "The key is wrong, or it was regenerated in intervals.icu after you pasted it here."
        case .network:
            "The request never got through — no network, or intervals.icu is unreachable "
            + "right now. Nothing was lost and nothing was half-imported."
        case .server:
            "intervals.icu answered with an error"
            + (detail.map { " (\($0))" } ?? "") + ". That is its end, not yours."
        case .empty:
            "intervals.icu accepted the key but has no watersport activities to hand over yet."
        case .unknown:
            "Something unexpected came back" + (detail.map { ": \($0)" } ?? "") + "."
        }
    }

    /// What to do about it.
    public var fix: String {
        switch kind {
        case .noKey:
            "Paste your personal API key: intervals.icu → Settings → Developer Settings."
        case .unauthorized:
            "Copy the key again from intervals.icu → Settings → Developer Settings and "
            + "paste it fresh — a stray space at either end is enough to break it."
        case .network:
            "Check your connection and sync again."
        case .server:
            "This is usually temporary. Try again in a few minutes."
        case .empty:
            "Connect Garmin in intervals.icu (Settings → device connections) — the back-fill "
            + "takes a few minutes. If it is already connected, you may simply have no "
            + "windsurf, wing, kite, surf or SUP activity there yet."
        case .unknown:
            "Try the sync again. If it keeps failing, check the key in Settings."
        }
    }

    /// One string for the error alert, which has room for both halves.
    public var alertText: String { "\(message)\n\n\(fix)" }

    /// The help topic that explains this failure in full.
    public var helpTopic: HelpTopicID { kind == .noKey ? .icuSetup : .icuTroubleshooting }
}

/// What a key check found when it worked.
public struct IcuConnectionReport: Sendable, Equatable {
    /// Activities intervals.icu listed in the checked window.
    public let activities: Int
    /// …of those, the ones WingFoil would actually import.
    public let watersports: Int

    public init(activities: Int, watersports: Int) {
        self.activities = activities
        self.watersports = watersports
    }

    /// The green line under the key field.
    public var message: String {
        guard activities > 0 else {
            return "Connected — the key works, no activities in the last two years"
        }
        let plural = watersports == 1 ? "y" : "ies"
        return watersports > 0
            ? "Connected — \(watersports) watersport activit\(plural) found "
                + "(of \(activities) in the last two years)"
            : "Connected — \(activities) activities found, none of them a watersport yet"
    }

    /// A working key with nothing to fetch is still something to say out loud: the setup
    /// is one step short (Garmin not connected), not finished.
    public var caveat: IcuProblem? {
        watersports == 0 ? IcuProblem(kind: .empty) : nil
    }
}

/// The outcome of "save the key and see whether it works".
public enum IcuKeyCheck: Sendable, Equatable {
    case success(IcuConnectionReport)
    case failure(IcuProblem)
}

public enum IcuDiagnosis {

    /// Maps a thrown error onto a cause. Deliberately total: an unrecognised error becomes
    /// `.unknown` with its description, never a crash and never a silent success.
    public static func describe(_ error: any Error) -> IcuProblem {
        switch error {
        case let icu as IcuClient.Error:
            switch icu {
            case .missingKey:
                return IcuProblem(kind: .noKey)
            case .unauthorized:
                return IcuProblem(kind: .unauthorized)
            case .http(let status, _):
                // The body is dropped on purpose: it is attacker-shaped text at worst and
                // noise at best, and on 401 it can echo the request back.
                return status == 401 || status == 403
                    ? IcuProblem(kind: .unauthorized)
                    : IcuProblem(kind: .server, detail: "HTTP \(status)")
            case .transport(let message):
                return IcuProblem(kind: .network, detail: message)
            case .decoding(let message):
                return IcuProblem(kind: .unknown, detail: message)
            }
        case let url as URLError:
            return IcuProblem(kind: .network, detail: url.localizedDescription)
        default:
            return IcuProblem(kind: .unknown, detail: (error as NSError).localizedDescription)
        }
    }

    /// A sync that threw nothing can still have failed to produce anything. Returns nil
    /// when the sync is genuinely fine.
    public static func describe(_ summary: IcuSyncSummary) -> IcuProblem? {
        if summary.imported == 0, summary.alreadyKnown == 0, summary.duplicates == 0,
           summary.watersports == 0 {
            return IcuProblem(kind: .empty)
        }
        if summary.imported == 0, summary.alreadyKnown == 0, summary.duplicates == 0,
           !summary.failed.isEmpty {
            return IcuProblem(kind: .unknown,
                              detail: "\(summary.failed.count) download"
                                  + (summary.failed.count == 1 ? "" : "s") + " failed")
        }
        return nil
    }

    /// Save-then-verify: one list call, no download. Cheap against the 5 k/day limit and
    /// the only honest way to tell "saved" from "works".
    public static func check(_ client: IcuClient,
                            oldest: Date = IcuSyncService.defaultOldest(),
                            newest: Date = Date()) async -> IcuKeyCheck {
        do {
            let activities = try await client.activities(oldest: oldest, newest: newest)
            return .success(IcuConnectionReport(
                activities: activities.count,
                watersports: activities.filter(IcuClient.isWatersport).count))
        } catch {
            return .failure(describe(error))
        }
    }
}

/// What the empty library should show. Pure, because the first thing a new user sees is
/// exactly the thing no one ever tests by hand twice.
public enum IcuOnboardingState: Sendable, Equatable {
    /// There are sessions — no onboarding needed.
    case ready
    /// Empty library, no key: the full setup card.
    case setup
    /// A key is configured and the last attempt failed (or came back empty).
    case problem(IcuProblem)
    /// A key is configured, nothing has failed, and nothing has arrived yet.
    case waiting
}

public enum IcuOnboarding {

    /// - Parameters:
    ///   - sessionCount: rows in the library.
    ///   - hasKey: a non-empty API key is stored.
    ///   - lastProblem: the mapped cause of the last sync/check, if it failed.
    public static func state(sessionCount: Int, hasKey: Bool,
                             lastProblem: IcuProblem?) -> IcuOnboardingState {
        // A library with sessions in it is never onboarding, however the last sync went:
        // a failed refresh is an error banner, not a first-run wizard.
        guard sessionCount == 0 else { return .ready }
        // No key beats every stored problem — the fix is the same four steps either way.
        guard hasKey else { return .setup }
        if let lastProblem { return .problem(lastProblem) }
        return .waiting
    }
}
