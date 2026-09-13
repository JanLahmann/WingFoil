import Foundation

/// What Strava's OAuth exchange hands back, and what CleanJibe keeps in the keychain.
///
/// Strava's access token lives about six hours; the refresh token is the long-lived one and
/// is what a connection actually *is*. Both are stored together as one JSON blob under one
/// keychain account, because a half-stored pair is a connection that cannot be repaired and
/// cannot be explained.
///
/// **The refresh token can change.** Strava may return a new one with every refresh, so the
/// rule is "write back whatever came out", never "keep the one we had" — `refreshed(with:)`
/// is where that is enforced, and it is the one piece of this file that has bitten every
/// app that got it wrong.
public struct StravaTokens: Sendable, Codable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    /// Absolute expiry of `accessToken` — Strava's `expires_at`, a Unix instant.
    public var expiresAt: Date
    /// The athlete Strava says these tokens belong to. Display only; nothing is keyed on it.
    public var athleteId: String?
    public var athleteName: String?
    /// The scopes Strava actually granted, as it echoed them back on the callback. Kept
    /// because a rider can untick `activity:read_all` on Strava's own consent screen, and
    /// the resulting connection works but lists nothing — which looks exactly like a bug
    /// unless the app can say what happened.
    public var scope: String?

    public init(accessToken: String, refreshToken: String, expiresAt: Date,
                athleteId: String? = nil, athleteName: String? = nil, scope: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.athleteId = athleteId
        self.athleteName = athleteName
        self.scope = scope
    }

    /// The scope that lets CleanJibe read every activity, including the ones the rider has
    /// marked "Only you". Without it a private session is invisible and the rider is never
    /// told why, so this is the scope the app asks for and the one it checks it got.
    public static let requiredScope = "activity:read_all"

    /// Did Strava grant what we asked for? A connection missing this reads as connected and
    /// lists nothing, which is the worst failure an integration can have.
    public var hasActivityReadAll: Bool {
        guard let scope else { return true }         // Strava said nothing; assume it did
        return scope.split(separator: ",").contains { $0 == Self.requiredScope }
    }

    /// **Is the access token too old to use?**
    ///
    /// With a deliberate margin: a token that expires in twenty seconds is a token that will
    /// expire *during* a sync of forty activities, and a mid-sync 401 costs a request from a
    /// budget of a hundred to learn something arithmetic could have told us. Five minutes is
    /// far longer than any single call and far shorter than the six-hour life.
    public static let refreshMarginS: TimeInterval = 300

    public func needsRefresh(now: Date = Date()) -> Bool {
        expiresAt.timeIntervalSince(now) <= Self.refreshMarginS
    }

    /// The pair after a refresh: everything from the response, and the old refresh token
    /// only where the response did not carry one.
    public func refreshed(with response: StravaTokenResponse) -> StravaTokens {
        StravaTokens(accessToken: response.accessToken,
                     refreshToken: response.refreshToken ?? refreshToken,
                     expiresAt: response.expiresAt,
                     athleteId: response.athlete?.id.map(String.init) ?? athleteId,
                     athleteName: response.athlete?.displayName ?? athleteName,
                     // A refresh response carries no scope; the grant has not changed.
                     scope: scope)
    }
}

/// `POST /oauth/token`, for both grants — the authorization code and the refresh.
public struct StravaTokenResponse: Sendable, Codable, Equatable {
    public var accessToken: String
    /// Absent on some refresh responses, which is exactly why `StravaTokens.refreshed`
    /// exists rather than a plain assignment.
    public var refreshToken: String?
    public var expiresAt: Date
    public var athlete: Athlete?

    public struct Athlete: Sendable, Codable, Equatable {
        public var id: Int64?
        public var firstname: String?
        public var lastname: String?

        public var displayName: String? {
            let parts = [firstname, lastname].compactMap { $0 }
                .filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }

        public init(id: Int64? = nil, firstname: String? = nil, lastname: String? = nil) {
            self.id = id
            self.firstname = firstname
            self.lastname = lastname
        }
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case athlete
    }

    public init(accessToken: String, refreshToken: String?, expiresAt: Date,
                athlete: Athlete? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.athlete = athlete
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try c.decode(String.self, forKey: .accessToken)
        refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken)
        expiresAt = Date(timeIntervalSince1970: try c.decode(Double.self, forKey: .expiresAt))
        athlete = try c.decodeIfPresent(Athlete.self, forKey: .athlete)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(accessToken, forKey: .accessToken)
        try c.encodeIfPresent(refreshToken, forKey: .refreshToken)
        try c.encode(expiresAt.timeIntervalSince1970, forKey: .expiresAt)
        try c.encodeIfPresent(athlete, forKey: .athlete)
    }
}

/// The client id and secret of a Strava API application, plus where Strava is told to send
/// the rider back.
///
/// **These are configuration, not code.** They come from the app's `Info.plist`
/// (`STRAVA_CLIENT_ID` / `STRAVA_CLIENT_SECRET`), which is fed by an untracked
/// `ios/Strava.xcconfig` — see `ios/Strava.example.xcconfig`. A build without them is a
/// perfectly good build: `isConfigured` is false, and the Strava row on the Import screen
/// says what is missing instead of failing halfway through an OAuth round trip.
public struct StravaConfig: Sendable, Equatable {
    public var clientId: String
    public var clientSecret: String
    /// Where Strava sends the rider back to.
    ///
    /// **An https URL on our own site, not a custom scheme.** Strava validates the redirect
    /// against the API application's single "Authorization Callback Domain" — ours is
    /// `cleanjibe.org` — and refuses anything whose host is not it, custom schemes included.
    /// So the round trip has one hop more than it looks like it should: Strava redirects to
    /// `https://cleanjibe.org/strava/callback`, and that page (a dozen lines of static HTML
    /// in `web/strava/callback/`) immediately forwards the `code` and `state` to
    /// `cleanjibe://strava`, which is where `ASWebAuthenticationSession` is waiting.
    public var redirectURI: String
    /// The custom-scheme URL the callback page bounces to — and therefore the scheme
    /// `ASWebAuthenticationSession` must be told to wait on. Declared in `project.yml`'s
    /// `CFBundleURLTypes`; nothing else in the app answers on it.
    public var appCallbackURI: String

    public static let defaultRedirectURI = "https://cleanjibe.org/strava/callback"
    public static let defaultAppCallbackURI = "cleanjibe://strava"

    public init(clientId: String, clientSecret: String,
                redirectURI: String = StravaConfig.defaultRedirectURI,
                appCallbackURI: String = StravaConfig.defaultAppCallbackURI) {
        self.clientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.clientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let redirect = redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
        self.redirectURI = redirect.isEmpty ? StravaConfig.defaultRedirectURI : redirect
        let app = appCallbackURI.trimmingCharacters(in: .whitespacesAndNewlines)
        self.appCallbackURI = app.isEmpty ? StravaConfig.defaultAppCallbackURI : app
    }

    public var isConfigured: Bool { !clientId.isEmpty && !clientSecret.isEmpty }

    /// The scheme `ASWebAuthenticationSession` waits on, taken from the app callback itself
    /// so the two can never drift apart.
    public var callbackScheme: String? {
        URL(string: appCallbackURI)?.scheme
    }
}

/// The two URLs of Strava's OAuth dance, built rather than pasted.
///
/// Pure string work on purpose: the app layer owns `ASWebAuthenticationSession` and the
/// keychain, and everything that can be decided without either is decided here, where the
/// test suite can look at it.
public enum StravaOAuth {

    public static let authorizeURL = URL(string: "https://www.strava.com/oauth/mobile/authorize")!
    public static let tokenURL = URL(string: "https://www.strava.com/oauth/token")!
    public static let deauthorizeURL = URL(string: "https://www.strava.com/oauth/deauthorize")!

    /// Where to send the rider to say yes.
    ///
    /// `/oauth/mobile/authorize` rather than `/oauth/authorize`: it is the endpoint Strava
    /// documents for apps, and it is the one that hands off to the installed Strava app
    /// when there is one, so the rider approves while already signed in instead of typing a
    /// password into a web view.
    ///
    /// `approval_prompt=auto` means a rider who has approved CleanJibe before is not asked
    /// again — except when the granted scope has changed, which is the one case where being
    /// asked again is the point.
    public static func authorizeRequest(config: StravaConfig, state: String) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: StravaTokens.requiredScope),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    /// What came back on the callback URL: the code, the scope Strava actually granted, and
    /// the `state` we sent — which is checked, not merely carried, because a callback whose
    /// state does not match ours is not our callback.
    public struct Callback: Sendable, Equatable {
        public var code: String
        public var scope: String?
        public var state: String?

        public init(code: String, scope: String? = nil, state: String? = nil) {
            self.code = code
            self.scope = scope
            self.state = state
        }
    }

    public enum CallbackError: Error, CustomStringConvertible, Equatable {
        case denied
        /// Strava refused the connection because the API application has used up its
        /// allowance of connected athletes — see `StravaClient.Error.athleteLimit`.
        case athleteLimit
        case malformed
        case stateMismatch

        public var description: String {
            switch self {
            case .denied: "Strava was not given permission"
            case .athleteLimit: StravaClient.Error.athleteLimit.description
            case .malformed: "Strava sent back something unreadable"
            case .stateMismatch: "that reply did not belong to this request"
            }
        }
    }

    /// Does this failure text mean "the application is full", rather than "the rider said
    /// no"?
    ///
    /// Matched on words rather than on a code because Strava spells it several ways across
    /// the consent page and the token endpoint (`athlete_limit`, "reached its athlete
    /// limit", a `field: "athlete limit"` in the errors array) and has never documented one
    /// of them. A miss costs the rider a less specific sentence, never a wrong action.
    public static func namesAthleteLimit(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("athlete") && lowered.contains("limit")
    }

    public static func parseCallback(_ url: URL, expecting state: String) throws -> Callback {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw CallbackError.malformed
        }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        // Strava says no by sending `error=access_denied`, which is a rider decision and
        // not a failure — the caller shows it as one sentence, never as an error alert.
        // An application that has run out of athlete slots comes back the same way and is
        // *not* a rider decision, which is why the two are told apart here.
        if let error = value("error") {
            throw namesAthleteLimit(error) ? CallbackError.athleteLimit : CallbackError.denied
        }
        guard let code = value("code"), !code.isEmpty else { throw CallbackError.malformed }
        guard value("state") == state else { throw CallbackError.stateMismatch }
        return Callback(code: code, scope: value("scope"), state: value("state"))
    }

    /// The form body of a token request. Both grants, one place — the only difference
    /// between them is two fields, and spelling them twice is how they drift.
    public static func tokenBody(config: StravaConfig, grant: Grant) -> Data {
        var fields: [(String, String)] = [
            ("client_id", config.clientId),
            ("client_secret", config.clientSecret),
        ]
        switch grant {
        case .authorizationCode(let code):
            fields.append(("code", code))
            fields.append(("grant_type", "authorization_code"))
        case .refresh(let token):
            fields.append(("refresh_token", token))
            fields.append(("grant_type", "refresh_token"))
        }
        let encoded = fields.map { "\(form($0.0))=\(form($0.1))" }.joined(separator: "&")
        return Data(encoded.utf8)
    }

    public enum Grant: Sendable, Equatable {
        case authorizationCode(String)
        case refresh(String)
    }

    /// `application/x-www-form-urlencoded`, which is not `addingPercentEncoding` with the
    /// query set: a `+` in a client secret would survive that and arrive as a space.
    static func form(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
