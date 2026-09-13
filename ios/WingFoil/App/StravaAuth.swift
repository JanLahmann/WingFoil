import AuthenticationServices
import Foundation
import UIKit
import WingFoilKit

/// The Strava connection, as the app owns it: where the credentials come from, where the
/// tokens are kept, and the browser round trip that turns a tap into a pair of them.
///
/// Everything that can be decided without a browser or a keychain lives in the kit
/// (`StravaOAuth`, `StravaAuthClient`, `StravaTokens`) where the test suite can watch it.
/// What is left here is the three things a unit test cannot have: `Info.plist`,
/// `ASWebAuthenticationSession`, and the Keychain.
enum StravaAuth {

    // MARK: - Configuration

    /// The API application's credentials, read from `Info.plist` and fed there by an
    /// **untracked** `ios/Strava.xcconfig` (see `ios/Strava.example.xcconfig`).
    ///
    /// A build without them is a perfectly good build. The client id is not a secret — it
    /// travels in every authorize URL — but the secret is, and a repository that is public
    /// must not be able to leak one by accident. So the keys are read, never defaulted to a
    /// literal, and `isConfigured` being false is a state the Import screen knows how to
    /// explain rather than a crash.
    static var config: StravaConfig {
        let bundle = Bundle.main
        func string(_ key: String) -> String {
            (bundle.object(forInfoDictionaryKey: key) as? String) ?? ""
        }
        return StravaConfig(clientId: string("STRAVA_CLIENT_ID"),
                            clientSecret: string("STRAVA_CLIENT_SECRET"),
                            redirectURI: string("STRAVA_REDIRECT_URI"))
    }

    // MARK: - Stored tokens

    static func loadTokens() -> StravaTokens? {
        guard let raw = Keychain.string(for: Keychain.stravaTokens),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StravaTokens.self, from: data)
    }

    @discardableResult
    static func store(_ tokens: StravaTokens) -> Bool {
        guard let data = try? JSONEncoder().encode(tokens),
              let text = String(data: data, encoding: .utf8) else { return false }
        return Keychain.set(text, for: Keychain.stravaTokens)
    }

    static func forgetTokens() {
        Keychain.remove(Keychain.stravaTokens)
    }

    // MARK: - The round trip

    enum ConnectError: Error, CustomStringConvertible {
        case notConfigured
        case cancelled
        case browser(String)

        var description: String {
            switch self {
            case .notConfigured:
                "This build has no Strava application configured"
            case .cancelled:
                "Connecting to Strava was cancelled"
            case .browser(let message):
                message
            }
        }
    }

    /// Opens Strava's consent screen and comes back with a stored, usable token pair.
    ///
    /// **Two hops, not one.** Strava validates the redirect against the API application's
    /// single Authorization Callback Domain — `cleanjibe.org` — and refuses a custom scheme
    /// outright, so it sends the rider to `https://cleanjibe.org/strava/callback`, a dozen
    /// lines of static HTML on our own site whose only job is to forward the `code` and
    /// `state` to `cleanjibe://strava`. That is the URL `ASWebAuthenticationSession` is
    /// waiting for, and the browser sheet closes on it without the rider seeing the page for
    /// more than an instant.
    @MainActor
    static func connect(anchor: ASPresentationAnchor?) async throws -> StravaTokens {
        let config = config
        guard config.isConfigured else { throw ConnectError.notConfigured }
        guard let scheme = config.callbackScheme else { throw ConnectError.notConfigured }

        // Not a nonce in the cryptographic sense and not pretending to be one: its job is to
        // prove that the callback belongs to *this* request, which a UUID does.
        let state = UUID().uuidString
        let url = StravaOAuth.authorizeRequest(config: config, state: state)
        let callback = try await present(url: url, scheme: scheme, anchor: anchor)
        let parsed = try StravaOAuth.parseCallback(callback, expecting: state)
        let tokens = try await StravaAuthClient(config: config)
            .exchange(code: parsed.code, scope: parsed.scope)
        store(tokens)
        return tokens
    }

    /// Hands the tokens back to Strava and forgets them locally.
    ///
    /// The local half happens whatever the remote half does: a Disconnect button that leaves
    /// the connection standing because the network was down is a button that lies.
    static func disconnect() async {
        if let tokens = loadTokens() {
            try? await StravaAuthClient(config: config).deauthorize(tokens)
        }
        forgetTokens()
    }

    /// A client with a live access token, refreshing first if the stored one is near its end
    /// and writing back whatever came out of the refresh.
    static func client() async throws -> StravaClient {
        guard let stored = loadTokens() else { throw StravaClient.Error.notConnected }
        let fresh = try await StravaAuthClient(config: config).refreshIfNeeded(stored)
        if fresh != stored { store(fresh) }
        return StravaClient(accessToken: fresh.accessToken)
    }

    // MARK: - ASWebAuthenticationSession

    /// **The completion handler is deliberately `@Sendable`.**
    ///
    /// `ASWebAuthenticationSessionCompletionHandler` carries no `NS_SWIFT_SENDABLE` in the
    /// SDK header, so a closure written inside a `@MainActor` function inherits the main
    /// actor — and the Swift 6 runtime kills the process the moment AuthenticationServices
    /// calls it from anywhere else (`swift_task_checkIsolated` → `dispatch_assert_queue`).
    /// That is exactly the crash build 16 shipped with `BGTaskScheduler`'s `launchHandler`
    /// (see `ActivityNotifier.register`); the compiler is silent about both. So the closure is
    /// `@Sendable`, it touches nothing isolated, and it carries only the continuation.
    @MainActor
    private static func present(url: URL, scheme: String,
                                anchor: ASPresentationAnchor?) async throws -> URL {
        let provider = AnchorProvider(anchor: anchor)
        return try await withCheckedThrowingContinuation { continuation in
            let handler: @Sendable (URL?, (any Error)?) -> Void = { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: ConnectError.cancelled)
                } else {
                    continuation.resume(throwing: ConnectError.browser(
                        error?.localizedDescription ?? "Strava did not answer"))
                }
            }
            let session = ASWebAuthenticationSession(url: url,
                                                     callback: .customScheme(scheme),
                                                     completionHandler: handler)
            session.presentationContextProvider = provider
            // Deliberately NOT ephemeral: a rider already signed in to Strava in Safari
            // should approve with one tap rather than typing a password into a sheet.
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                continuation.resume(throwing: ConnectError.browser(
                    "Could not open Strava — no window to show it in"))
            }
            // The session must outlive this function or iOS tears the sheet down at once.
            provider.session = session
        }
    }

    /// Holds the window the sheet is presented over, and the session itself for as long as
    /// it is on screen.
    @MainActor
    private final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        let anchor: ASPresentationAnchor?
        var session: ASWebAuthenticationSession?

        init(anchor: ASPresentationAnchor?) {
            self.anchor = anchor
        }

        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            if let anchor { return anchor }
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.first?.keyWindow ?? ASPresentationAnchor()
        }
    }
}

/// The window the Strava consent sheet is presented over. Asked for by the screen that
/// starts the connect — Import or Settings — rather than inside the store, because a window
/// is a property of a screen and not of the library. One helper for both, so the two
/// screens cannot pick different windows.
enum StravaConsent {
    @MainActor
    static func anchor() -> ASPresentationAnchor? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.keyWindow
    }
}
