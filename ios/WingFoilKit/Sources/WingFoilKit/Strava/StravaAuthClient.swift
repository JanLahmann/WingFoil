import Foundation

/// The half of OAuth that is an HTTP request: exchanging the authorization code for a pair
/// of tokens, and trading a refresh token for a fresh access token.
///
/// The half that is a *browser* — `ASWebAuthenticationSession`, which needs UIKit and a
/// window — stays in the app layer, as does the keychain. Everything that can be decided
/// without either is decided here, where the test suite can watch it happen through a stub
/// transport.
public struct StravaAuthClient: Sendable {

    public let config: StravaConfig
    let transport: any StravaTransport

    public init(config: StravaConfig,
                transport: any StravaTransport = StravaURLSessionTransport()) {
        self.config = config
        self.transport = transport
    }

    /// Code → tokens. Called once, on the way back from the consent screen.
    public func exchange(code: String, scope: String?) async throws -> StravaTokens {
        let response = try await token(grant: .authorizationCode(code))
        return StravaTokens(accessToken: response.accessToken,
                            refreshToken: response.refreshToken ?? "",
                            expiresAt: response.expiresAt,
                            athleteId: response.athlete?.id.map(String.init),
                            athleteName: response.athlete?.displayName,
                            scope: scope)
    }

    /// Tokens → fresher tokens, **only when they need it**.
    ///
    /// The check is here rather than at every call site so that "do I need to refresh" has
    /// exactly one answer in the app: a caller asks for a usable token and gets one, and a
    /// connection that is still good costs no request out of a budget of a hundred.
    public func refreshIfNeeded(_ tokens: StravaTokens,
                                now: Date = Date()) async throws -> StravaTokens {
        guard tokens.needsRefresh(now: now) else { return tokens }
        guard !tokens.refreshToken.isEmpty else { throw StravaClient.Error.unauthorized }
        let response = try await token(grant: .refresh(tokens.refreshToken))
        return tokens.refreshed(with: response)
    }

    /// Hands the tokens back to Strava so the rider's "My Apps" page stops listing us.
    ///
    /// Best-effort by design: the app forgets the connection whatever this returns, because
    /// a Disconnect button that leaves the connection standing when the network is down is
    /// a button that lies.
    public func deauthorize(_ tokens: StravaTokens) async throws {
        var request = URLRequest(url: StravaOAuth.deauthorizeURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(StravaClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        _ = try await transport.send(request)
    }

    // MARK: - Plumbing

    private func token(grant: StravaOAuth.Grant) async throws -> StravaTokenResponse {
        guard config.isConfigured else { throw StravaClient.Error.notConfigured }
        var request = URLRequest(url: StravaOAuth.tokenURL)
        request.httpMethod = "POST"
        request.httpBody = StravaOAuth.tokenBody(config: config, grant: grant)
        request.setValue("application/x-www-form-urlencoded",
                         forHTTPHeaderField: "Content-Type")
        request.setValue(StravaClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 60
        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 200..<300:
            do {
                return try JSONDecoder().decode(StravaTokenResponse.self, from: data)
            } catch {
                throw StravaClient.Error.decoding("\(error)")
            }
        case 400, 401:
            // Strava answers a dead refresh token with 400, not 401. Both mean the same
            // thing to the rider — the connection is gone and has to be made again — and
            // saying "HTTP 400" instead would send him looking for a network problem.
            //
            // The exception is the application running out of athlete slots, which also
            // arrives as a 400 and means something completely different: not "reconnect",
            // but "this cannot work yet, and not because of you".
            let body = String(data: data, encoding: .utf8) ?? ""
            throw StravaOAuth.namesAthleteLimit(body)
                ? StravaClient.Error.athleteLimit
                : StravaClient.Error.unauthorized
        case 429:
            throw StravaClient.Error.rateLimited(
                retryAfterS: response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init))
        default:
            throw StravaClient.Error.http(status: response.statusCode,
                                          body: String(data: data, encoding: .utf8) ?? "")
        }
    }
}
