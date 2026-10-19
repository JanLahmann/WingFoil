#if BETA
import Foundation
import UIKit
import WingFoilKit

/// **The beta's anonymous counts, sent** — a screen opened, a counted feature that worked —
/// to umami, the same cookie-free counter cleanjibe.org uses (Jan, 18 Oct 2026;
/// docs/analytics.md, ADR-039).
///
/// **Beta and dev only.** The whole file is behind `#if BETA`, so the App Store binary has no
/// sender, no endpoint and no network call to umami: `strings` on it finds no
/// `cloud.umami.is` (docs/testing.md, "Three channels"; `tools/check_release.py`). Moving it
/// to the release is a decision of its own, with a privacy label to change
/// (ios/store/appstore.md).
///
/// **What it is not.** No identifier of any kind is made, kept or sent: no install id, no
/// vendor id, no cookie (the session is ephemeral, with no cookie store), nothing in
/// `UserDefaults`. No retry and no queue: an event that cannot go now is dropped, so the
/// offline afternoon on the beach is simply not counted. Nothing waits for it, nothing
/// throws, nothing is logged. What travels is `UmamiEvent`'s body, whose guard is
/// track.js's, and the properties come from closed sets the call sites name.
///
/// Never from the simulator and never under a screenshot or test hook: a development run
/// must not put a single count into the dashboard.
enum Analytics {

    /// A top-level screen appeared.
    static func screen(_ screen: UmamiEvent.Screen) {
        guard isWanted else { return }
        Task { @MainActor in
            Sender.shared.current = screen
            Sender.shared.send { .pageview(screen, context: $0) }
        }
    }

    /// A feature the usage counters counted as working (`Usage.record`, `Usage.finished`).
    static func counted(_ feature: UsageCounters.Feature, times: Int, detail: String?) {
        guard isWanted, times > 0 else { return }
        Task { @MainActor in
            let on = Sender.shared.current
            Sender.shared.send {
                .counted(feature, times: times, detail: detail, on: on, context: $0)
            }
        }
    }

    /// An import run that brought sessions in (`Usage.recordImport`).
    static func imported(_ source: ImportSource, automatic: Bool, sessions: Int) {
        guard isWanted, sessions > 0 else { return }
        Task { @MainActor in
            let on = Sender.shared.current
            Sender.shared.send {
                .imported(source, automatic: automatic, sessions: sessions, on: on, context: $0)
            }
        }
    }

    /// Not the simulator, not a UI test, not a screenshot hook.
    private static let isWanted: Bool = {
        #if targetEnvironment(simulator)
        return false
        #else
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil { return false }
        if environment.keys.contains(where: { $0.hasPrefix("UI_") }) { return false }
        return true
        #endif
    }()

    // MARK: - The one sender

    @MainActor
    private final class Sender {
        static let shared = Sender()

        /// The screen the next event happened on. In memory only, gone with the process.
        var current: UmamiEvent.Screen = .library

        /// The collector. The only place in the app that names it.
        private static let endpoint = URL(string: "https://cloud.umami.is/api/send")!

        /// Ephemeral, with no cookie store, no cache and no waiting for a network that is not
        /// there: a request that cannot go now fails at once and is forgotten.
        private let session: URLSession = {
            let config = URLSessionConfiguration.ephemeral
            config.urlCache = nil
            config.httpCookieStorage = nil
            config.httpShouldSetCookies = false
            config.httpCookieAcceptPolicy = .never
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 15
            config.waitsForConnectivity = false
            return URLSession(configuration: config)
        }()

        /// **A browser's user agent, on purpose.** umami drops a request whose agent reads
        /// as a bot, and CFNetwork's default one does. This is Mobile Safari's shape with the
        /// phone's own iOS version in it, which is all a browser on the same phone would say.
        private let userAgent: String = {
            let version = UIDevice.current.systemVersion
            let parts = version.split(separator: ".")
            let major = parts.first.map(String.init) ?? "26"
            let minor = parts.count > 1 ? String(parts[1]) : "0"
            return "Mozilla/5.0 (iPhone; CPU iPhone OS "
                + version.replacingOccurrences(of: ".", with: "_")
                + " like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/"
                + major + "." + minor + " Mobile/15E148 Safari/604.1"
        }()

        /// The language and the screen in points, read once. A phone does not change either
        /// while the app runs often enough to matter to a count.
        private lazy var context: UmamiEvent.Context = {
            let language = Locale.preferredLanguages.first ?? "en"
            let bounds = UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.screen.bounds }
                .first ?? .zero
            let width = Int(min(bounds.width, bounds.height))
            let height = Int(max(bounds.width, bounds.height))
            return UmamiEvent.Context(language: language, width: width, height: height)
        }()

        /// Fire and forget. The answer is never read: a failure of any kind is silence. A
        /// nil event is one the kit declined to make, and nothing is sent for it.
        func send(_ make: (UmamiEvent.Context) -> UmamiEvent?) {
            guard let event = make(context) else { return }
            var request = URLRequest(url: Self.endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.httpBody = event.body()
            let session = session
            Task.detached(priority: .utility) {
                _ = try? await session.data(for: request)
            }
        }
    }
}
#endif
