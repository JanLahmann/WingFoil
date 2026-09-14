import Foundation

/// Injection seam so the client is testable without a network — the same shape
/// `IcuTransport` has, kept separate rather than shared because the two services have
/// nothing in common but HTTP and a name that said otherwise would suggest they did.
public protocol StravaTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct StravaURLSessionTransport: StravaTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw StravaClient.Error.transport("no HTTP response")
        }
        return (data, http)
    }
}

/// Strava's v3 REST API, read side only.
///
/// **Read only, and that is a decision rather than a stage.** CleanJibe lists activities and
/// downloads their streams; it writes nothing to anybody's Strava account. Write-back — a
/// CleanJibe block in the activity description — is a separate, opt-in feature with its own
/// consent and its own issue (#5), and nothing in this file is a step towards doing it
/// quietly.
///
/// **Rate limits.** Strava allows 200 read requests per fifteen minutes and 2000 per day, per
/// application, and answers a breach with 429. A sync of *n* new activities costs one list
/// request plus one streams request each, so the budget is real but generous for a personal
/// library. Two things keep it that way: known activities are never fetched again, and a
/// 429 is surfaced as `Error.rateLimited` with Strava's own `Retry-After` where it sent one
/// — a cause the rider can act on ("come back in a few minutes"), not a stack trace.
public struct StravaClient: Sendable {

    public enum Error: Swift.Error, CustomStringConvertible, Equatable {
        case notConfigured
        case notConnected
        case unauthorized
        /// **Strava will not connect another rider.** An unreviewed Strava API application
        /// is allowed ten connected athletes and 2 000 read requests a day (200 per fifteen
        /// minutes); the eleventh person to tap Connect is refused, and the refusal has
        /// nothing to do with his account. Its own case because it is the one failure here that no amount of
        /// retrying, reconnecting or re-reading the help will fix — the fix is Strava
        /// approving the application, and the rider deserves to be told that rather than
        /// left staring at "Bad Request".
        case athleteLimit
        /// Strava asked us to wait. `retryAfterS` is its own `Retry-After` header when it
        /// sent one, and nil when it did not — which is most of the time.
        case rateLimited(retryAfterS: Int?)
        case http(status: Int, body: String)
        case transport(String)
        case decoding(String)
        /// The activity exists but Strava has no streams for it — a manual entry, or a
        /// recording it is still processing. Not an error the rider caused.
        case noStreams

        public var description: String {
            switch self {
            case .notConfigured: "this build has no Strava application configured"
            case .notConnected: "no Strava account is connected"
            case .unauthorized: "Strava rejected the connection — connect it again"
            case .athleteLimit:
                "Strava lets a new app connect a limited number of riders, and CleanJibe is "
                    + "full — Menu → Support & ideas is the way to say so, and Strava is "
                    + "asked for more"
            case .rateLimited(let after):
                if let after {
                    "Strava asked us to wait about \(max(1, after / 60)) more minute"
                        + (after >= 120 ? "s" : "")
                } else {
                    "Strava asked us to wait — try again in a few minutes"
                }
            // The status, never the body. A response body can echo the request — including
            // a token — straight back, and this string is what the alert shows the rider;
            // the body stays in the payload for whoever is reading a log.
            case .http(let s, _): "Strava answered with an error (HTTP \(s))"
            case .transport(let m): "network error: \(m)"
            case .decoding(let m): "unexpected response: \(m)"
            case .noStreams: "Strava has no GPS recording for that activity"
            }
        }
    }

    public static let defaultBaseURL = URL(string: "https://www.strava.com/api/v3")!
    static let userAgent = "CleanJibe-iOS/0.1 (personal use)"

    /// The streams CleanJibe asks for, in Strava's own spelling.
    ///
    /// `velocity_smooth` is requested and then **deliberately not used** (see
    /// `StravaImport`): it is a smoothed, derived channel, so treating it as a speed
    /// measurement would be a claim the file cannot support, and carrying it beside our own
    /// positional derivation would put two disagreeing answers in the same column. It stays
    /// in the request because it costs nothing in a response we are already fetching and
    /// because a fixture that mirrors the real payload is worth more than a tidy one.
    public static let streamKeys = "time,latlng,altitude,heartrate,velocity_smooth"

    /// How many activities to ask for at a time. Strava's maximum is 200 and its default is
    /// 30; a personal watersport library two years deep fits in a couple of pages.
    public static let pageSize = 100
    /// Never walk past this many pages in one listing. A rider with ten years of daily runs
    /// would otherwise spend the whole rate-limit budget on pages of bike rides.
    public static let maxPages = 10

    public let accessToken: String
    public let baseURL: URL
    let transport: any StravaTransport

    public init(accessToken: String, baseURL: URL = StravaClient.defaultBaseURL,
                transport: any StravaTransport = StravaURLSessionTransport()) {
        self.accessToken = accessToken
        self.baseURL = baseURL
        self.transport = transport
    }

    // MARK: - Endpoints

    /// `GET /athlete/activities`, paged until Strava runs out or `maxPages` is reached.
    ///
    /// `after` is a Unix instant and Strava returns activities *newer* than it, newest
    /// first — so a two-year window is one parameter rather than a client-side filter over
    /// a decade of rides.
    public func activities(after: Date, before: Date? = nil) async throws -> [StravaActivity] {
        var all: [StravaActivity] = []
        for page in 1...Self.maxPages {
            var components = URLComponents(
                url: baseURL.appendingPathComponent("athlete/activities"),
                resolvingAgainstBaseURL: false)!
            var items = [
                URLQueryItem(name: "after", value: String(Int(after.timeIntervalSince1970))),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(Self.pageSize)),
            ]
            if let before {
                items.append(URLQueryItem(name: "before",
                                          value: String(Int(before.timeIntervalSince1970))))
            }
            components.queryItems = items
            let data = try await get(components.url!)
            let batch: [StravaActivity]
            do {
                batch = try JSONDecoder().decode([StravaActivity].self, from: data)
            } catch {
                throw Error.decoding("\(error)")
            }
            all.append(contentsOf: batch)
            if batch.count < Self.pageSize { break }
        }
        return all
    }

    /// `GET /activities/{id}/streams?key_by_type=true` — the recording itself, as parallel
    /// arrays on one clock.
    public func streams(activityID: String) async throws -> StravaStreams {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("activities/\(activityID)/streams"),
            resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "keys", value: Self.streamKeys),
            URLQueryItem(name: "key_by_type", value: "true"),
        ]
        let data = try await get(components.url!)
        do {
            return try JSONDecoder().decode(StravaStreams.self, from: data)
        } catch {
            throw Error.decoding("\(error)")
        }
    }

    // MARK: - Plumbing

    private func get(_ url: URL) async throws -> Data {
        guard !accessToken.isEmpty else { throw Error.notConnected }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 120
        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403: throw Error.unauthorized
        case 404: throw Error.noStreams
        case 429:
            let header = response.value(forHTTPHeaderField: "Retry-After")
            throw Error.rateLimited(retryAfterS: header.flatMap(Int.init))
        default: throw Error.http(status: response.statusCode,
                                  body: String(data: data, encoding: .utf8) ?? "")
        }
    }
}
