import Foundation
import Testing
@testable import WingFoilKit

/// The Strava connection itself: the OAuth round trip, the token refresh, the rate limit and
/// the listing — all of it against a stub transport, because a test that needs the network is
/// a test that fails on a train.
struct StravaClientTests {

    // MARK: - Stub transport

    /// Answers each request from a queue of canned replies and records what it was asked.
    final class Stub: StravaTransport, @unchecked Sendable {
        struct Reply {
            var status: Int
            var body: Data
            var headers: [String: String] = [:]
        }

        private var replies: [Reply]
        private(set) var requests: [URLRequest] = []

        init(_ replies: [Reply]) { self.replies = replies }

        convenience init(status: Int = 200, json: String, headers: [String: String] = [:]) {
            self.init([Reply(status: status, body: Data(json.utf8), headers: headers)])
        }

        /// Every caller in this suite drives it from one task, so the queue needs no lock —
        /// the `@unchecked` is about crossing an isolation boundary, not about contention.
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            requests.append(request)
            let reply = replies.isEmpty ? Reply(status: 200, body: Data("[]".utf8))
                                        : replies.removeFirst()
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                           httpVersion: nil, headerFields: reply.headers)!
            return (reply.body, response)
        }
    }

    static let config = StravaConfig(clientId: "279015", clientSecret: "s3cr3t+value")

    // MARK: - The authorize step

    @Test func theAuthorizeURLAsksForTheScopeThatSeesPrivateSessions() throws {
        let url = StravaOAuth.authorizeRequest(config: Self.config, state: "abc123")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        #expect(url.host == "www.strava.com")
        // The mobile endpoint, which hands off to the installed Strava app when there is one.
        #expect(url.path == "/oauth/mobile/authorize")
        #expect(value("client_id") == "279015")
        #expect(value("response_type") == "code")
        #expect(value("scope") == "activity:read_all")
        #expect(value("state") == "abc123")
        // An https redirect on our own site, because Strava validates the redirect against
        // the application's single callback domain and refuses a custom scheme outright.
        #expect(value("redirect_uri") == "https://cleanjibe.org/strava/callback")
    }

    /// The callback the *app* sees is the one the static page bounced to, and the scheme
    /// `ASWebAuthenticationSession` waits on comes from that URL rather than from the https
    /// redirect — so the two halves of the round trip can never drift apart.
    @Test func theAppWaitsOnTheSchemeTheCallbackPageBouncesTo() {
        #expect(Self.config.appCallbackURI == "cleanjibe://strava")
        #expect(Self.config.callbackScheme == "cleanjibe")
        #expect(Self.config.isConfigured)
        #expect(!StravaConfig(clientId: "", clientSecret: "x").isConfigured)
        #expect(!StravaConfig(clientId: "x", clientSecret: " ").isConfigured)
    }

    @Test func theCallbackIsReadAndItsStateIsChecked() throws {
        let ok = URL(string: "cleanjibe://strava?state=abc&code=7f2&scope=read,activity:read_all")!
        let parsed = try StravaOAuth.parseCallback(ok, expecting: "abc")
        #expect(parsed.code == "7f2")
        #expect(parsed.scope == "read,activity:read_all")

        // A reply that is not ours is not a reply.
        #expect(throws: StravaOAuth.CallbackError.stateMismatch) {
            try StravaOAuth.parseCallback(ok, expecting: "different")
        }
        // The rider said no — a decision, not a failure.
        #expect(throws: StravaOAuth.CallbackError.denied) {
            try StravaOAuth.parseCallback(
                URL(string: "cleanjibe://strava?state=abc&error=access_denied")!,
                expecting: "abc")
        }
        // …and the application being full is told apart from the rider saying no, because
        // the two need completely different sentences.
        #expect(throws: StravaOAuth.CallbackError.athleteLimit) {
            try StravaOAuth.parseCallback(
                URL(string: "cleanjibe://strava?state=abc&error=athlete_limit_reached")!,
                expecting: "abc")
        }
        #expect(throws: StravaOAuth.CallbackError.malformed) {
            try StravaOAuth.parseCallback(URL(string: "cleanjibe://strava?state=abc")!,
                                          expecting: "abc")
        }
    }

    /// A `+` in a client secret is a real character and must not arrive as a space, which is
    /// exactly what the query-allowed character set would do to it.
    @Test func theTokenBodyIsFormEncodedRatherThanQueryEncoded() {
        let body = String(decoding: StravaOAuth.tokenBody(config: Self.config,
                                                          grant: .authorizationCode("a+b")),
                          as: UTF8.self)
        #expect(body.contains("client_secret=s3cr3t%2Bvalue"))
        #expect(body.contains("code=a%2Bb"))
        #expect(body.contains("grant_type=authorization_code"))

        let refresh = String(decoding: StravaOAuth.tokenBody(config: Self.config,
                                                             grant: .refresh("r1")),
                             as: UTF8.self)
        #expect(refresh.contains("grant_type=refresh_token"))
        #expect(refresh.contains("refresh_token=r1"))
        #expect(!refresh.contains("code="))
    }

    // MARK: - Tokens

    @Test func exchangingTheCodeKeepsWhatStravaGranted() async throws {
        let stub = Stub(json: """
            {"token_type": "Bearer", "expires_at": 1756020000, "expires_in": 21600,
             "refresh_token": "r-one", "access_token": "a-one",
             "athlete": {"id": 606193, "firstname": "Jan", "lastname": "Lahmann"}}
            """)
        let tokens = try await StravaAuthClient(config: Self.config, transport: stub)
            .exchange(code: "7f2", scope: "read,activity:read_all")

        #expect(tokens.accessToken == "a-one")
        #expect(tokens.refreshToken == "r-one")
        #expect(tokens.expiresAt == Date(timeIntervalSince1970: 1_756_020_000))
        #expect(tokens.athleteId == "606193")
        #expect(tokens.athleteName == "Jan Lahmann")
        #expect(tokens.hasActivityReadAll)
        #expect(stub.requests.first?.httpMethod == "POST")
    }

    /// A rider can untick the private-activities box on Strava's own consent screen. The
    /// connection then works and lists nothing, which looks exactly like a bug unless the app
    /// can see what happened.
    @Test func aNarrowedScopeIsVisibleRatherThanSilent() {
        let full = StravaTokens(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture,
                                scope: "read,activity:read_all")
        let narrow = StravaTokens(accessToken: "a", refreshToken: "r",
                                  expiresAt: .distantFuture, scope: "read,activity:read")
        #expect(full.hasActivityReadAll)
        #expect(!narrow.hasActivityReadAll)
        // Strava said nothing at all: assume it granted what we asked for rather than
        // accusing a working connection of being broken.
        #expect(StravaTokens(accessToken: "a", refreshToken: "r",
                             expiresAt: .distantFuture).hasActivityReadAll)
    }

    /// The refresh margin, asserted rather than described: a token that dies during a sync
    /// costs a request out of a budget of a hundred to discover something arithmetic already
    /// knew.
    @Test func refreshIsDecidedWithAMarginRatherThanAtTheLastSecond() {
        let now = Date(timeIntervalSince1970: 1_756_000_000)
        func expiring(in seconds: TimeInterval) -> StravaTokens {
            StravaTokens(accessToken: "a", refreshToken: "r",
                         expiresAt: now.addingTimeInterval(seconds))
        }
        #expect(expiring(in: 6 * 3600).needsRefresh(now: now) == false)
        #expect(expiring(in: 301).needsRefresh(now: now) == false)
        #expect(expiring(in: 300).needsRefresh(now: now))
        #expect(expiring(in: 20).needsRefresh(now: now))
        #expect(expiring(in: -1).needsRefresh(now: now))
    }

    /// **Strava may hand back a new refresh token on any refresh**, and the app that keeps
    /// the old one is the app whose connection dies a week later for no visible reason.
    @Test func aRefreshWritesBackWhateverCameOutOfIt() async throws {
        let stub = Stub(json: """
            {"token_type": "Bearer", "expires_at": 1756100000, "expires_in": 21600,
             "refresh_token": "r-two", "access_token": "a-two"}
            """)
        let stale = StravaTokens(accessToken: "a-one", refreshToken: "r-one",
                                 expiresAt: Date(timeIntervalSince1970: 1_756_000_000),
                                 athleteId: "606193", athleteName: "Jan Lahmann",
                                 scope: "read,activity:read_all")
        let fresh = try await StravaAuthClient(config: Self.config, transport: stub)
            .refreshIfNeeded(stale, now: Date(timeIntervalSince1970: 1_756_000_000))

        #expect(fresh.accessToken == "a-two")
        #expect(fresh.refreshToken == "r-two")
        #expect(fresh.expiresAt == Date(timeIntervalSince1970: 1_756_100_000))
        // Everything the refresh did not speak about survives it.
        #expect(fresh.athleteId == "606193")
        #expect(fresh.athleteName == "Jan Lahmann")
        #expect(fresh.scope == "read,activity:read_all")
        #expect(stub.requests.count == 1)
    }

    /// …and a response that carries no `refresh_token` keeps the one we had, rather than
    /// storing an empty string and losing the connection outright.
    @Test func aRefreshResponseWithoutANewTokenKeepsTheOldOne() {
        let tokens = StravaTokens(accessToken: "a-one", refreshToken: "r-one",
                                  expiresAt: Date(timeIntervalSince1970: 1))
        let response = StravaTokenResponse(accessToken: "a-two", refreshToken: nil,
                                           expiresAt: Date(timeIntervalSince1970: 2))
        #expect(tokens.refreshed(with: response).refreshToken == "r-one")
    }

    /// A connection that is still good costs no request at all.
    @Test func aLiveTokenIsNotRefreshed() async throws {
        let stub = Stub([])
        let live = StravaTokens(accessToken: "a", refreshToken: "r",
                                expiresAt: Date(timeIntervalSince1970: 1_756_100_000))
        let same = try await StravaAuthClient(config: Self.config, transport: stub)
            .refreshIfNeeded(live, now: Date(timeIntervalSince1970: 1_756_000_000))
        #expect(same == live)
        #expect(stub.requests.isEmpty)
    }

    /// A dead refresh token comes back as 400, not 401 — and means "connect it again", not
    /// "the network is down".
    @Test func aDeadRefreshTokenReadsAsAConnectionToRemake() async {
        let stub = Stub(status: 400,
                        json: #"{"message":"Bad Request","errors":[{"field":"refresh_token"}]}"#)
        let stale = StravaTokens(accessToken: "a", refreshToken: "r",
                                 expiresAt: Date(timeIntervalSince1970: 1))
        await #expect(throws: StravaClient.Error.unauthorized) {
            try await StravaAuthClient(config: Self.config, transport: stub)
                .refreshIfNeeded(stale, now: Date(timeIntervalSince1970: 1_756_000_000))
        }
    }

    /// **The athlete ceiling.** An unreviewed Strava application may connect ten athletes;
    /// the eleventh is refused, and the refusal is nothing the rider can fix by trying again.
    @Test func theAthleteLimitIsItsOwnAnswerRatherThanAGenericRejection() async {
        let stub = Stub(status: 400, json: """
            {"message":"Bad Request","errors":[{"resource":"Application",
             "field":"athlete limit","code":"exceeded"}]}
            """)
        await #expect(throws: StravaClient.Error.athleteLimit) {
            try await StravaAuthClient(config: Self.config, transport: stub)
                .exchange(code: "7f2", scope: nil)
        }
        #expect(StravaOAuth.namesAthleteLimit("This app has reached its athlete limit"))
        #expect(!StravaOAuth.namesAthleteLimit("Rate Limit Exceeded"))
    }

    @Test func aBuildWithNoCredentialsRefusesBeforeItAsksStravaAnything() async {
        let stub = Stub([])
        let bare = StravaConfig(clientId: "", clientSecret: "")
        await #expect(throws: StravaClient.Error.notConfigured) {
            try await StravaAuthClient(config: bare, transport: stub)
                .exchange(code: "x", scope: nil)
        }
        #expect(stub.requests.isEmpty)
    }

    // MARK: - Listing

    @Test func theListingPagesAndCarriesTheBearerToken() async throws {
        func page(_ ids: [Int], name: String = "Wingfoil") -> Stub.Reply {
            let rows = ids.map {
                """
                {"id": \($0), "name": "\(name)", "sport_type": "Windsurf",
                 "start_date": "2026-08-24T02:26:40Z", "utc_offset": 7200.0,
                 "elapsed_time": 1800, "moving_time": 1740,
                 "start_latlng": [45.87, 10.87], "manual": false}
                """
            }
            return Stub.Reply(status: 200, body: Data("[\(rows.joined(separator: ","))]".utf8))
        }
        // A full page means "ask for another"; a short one means "that was the last".
        let full = Array(1...StravaClient.pageSize)
        let stub = Stub([page(full), page([9001, 9002])])
        let client = StravaClient(accessToken: "a-one", transport: stub)
        let activities = try await client.activities(
            after: Date(timeIntervalSince1970: 1_700_000_000))

        #expect(activities.count == StravaClient.pageSize + 2)
        #expect(stub.requests.count == 2)
        #expect(stub.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer a-one")
        let second = try #require(stub.requests[1].url)
        let query = try #require(URLComponents(url: second,
                                               resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.contains(URLQueryItem(name: "page", value: "2")))
        #expect(query.contains(URLQueryItem(name: "after", value: "1700000000")))
    }

    @Test func theStreamsRequestAsksForEveryChannelByType() async throws {
        let stub = Stub(json: #"{"time":{"data":[0,1]},"latlng":{"data":[[45.8,10.8],[45.8,10.81]]}}"#)
        let streams = try await StravaClient(accessToken: "a", transport: stub)
            .streams(activityID: "14123456789")
        #expect(streams.time?.data == [0, 1])

        let url = try #require(stub.requests.first?.url)
        #expect(url.path == "/api/v3/activities/14123456789/streams")
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems)
        #expect(query.contains(URLQueryItem(name: "key_by_type", value: "true")))
        #expect(query.contains(URLQueryItem(name: "keys", value: StravaClient.streamKeys)))
        // `velocity_smooth` is asked for and then deliberately unused — see `StravaImport`.
        #expect(StravaClient.streamKeys.contains("velocity_smooth"))
    }

    /// 100 requests per 15 minutes. A breach is a cause with a sentence, not a stack trace —
    /// and never a retry loop, which is how a five-minute wait becomes a fifteen-minute one.
    @Test func aRateLimitIsReportedAsSomethingToWaitOut() async throws {
        let stub = Stub([Stub.Reply(status: 429, body: Data("Rate Limit Exceeded".utf8),
                                    headers: ["Retry-After": "420"])])
        let client = StravaClient(accessToken: "a", transport: stub)
        do {
            _ = try await client.streams(activityID: "1")
            Issue.record("expected a rate-limit error")
        } catch let error as StravaClient.Error {
            #expect(error == .rateLimited(retryAfterS: 420))
            #expect(error.description.contains("Strava asked us to wait"))
        }
        #expect(stub.requests.count == 1)          // asked once, and not again
    }

    @Test func missingStreamsAndAStaleTokenAreDistinctCauses() async {
        await #expect(throws: StravaClient.Error.noStreams) {
            try await StravaClient(accessToken: "a",
                                   transport: Stub(status: 404, json: "{}"))
                .streams(activityID: "1")
        }
        await #expect(throws: StravaClient.Error.unauthorized) {
            try await StravaClient(accessToken: "a",
                                   transport: Stub(status: 401, json: "{}"))
                .streams(activityID: "1")
        }
        await #expect(throws: StravaClient.Error.notConnected) {
            try await StravaClient(accessToken: "", transport: Stub([]))
                .streams(activityID: "1")
        }
    }
}
