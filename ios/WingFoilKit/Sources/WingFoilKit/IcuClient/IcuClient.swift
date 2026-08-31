import Foundation

/// One entry of `GET /api/v1/athlete/0/activities`. Only the fields we need are decoded;
/// intervals.icu adds columns freely, so decoding stays tolerant.
public struct IcuActivity: Sendable, Codable, Identifiable, Equatable {
    public var id: String
    public var name: String?
    public var type: String?
    /// Local wall clock with **no zone in it** — "2026-08-06T07:57:21". Kept for display;
    /// never used to make an instant (see `startDate`).
    public var startDateLocal: String?
    /// The same moment as a real UTC instant — "2026-08-06T05:57:21Z". This is the field
    /// that identifies the activity in time.
    public var startDateUtc: String?
    /// The zone the athlete was in, e.g. "Europe/Rome". intervals.icu knows it because the
    /// upload told it; it is the exact answer, and it beats every guess we could make.
    public var timezone: String?
    public var movingTimeS: Int?
    public var distanceM: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, type, timezone
        case startDateLocal = "start_date_local"
        case startDateUtc = "start_date"
        case movingTimeS = "moving_time"
        case distanceM = "distance"
    }

    public init(id: String, name: String? = nil, type: String? = nil,
                startDateLocal: String? = nil, startDateUtc: String? = nil,
                timezone: String? = nil,
                movingTimeS: Int? = nil, distanceM: Double? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.startDateLocal = startDateLocal
        self.startDateUtc = startDateUtc
        self.timezone = timezone
        self.movingTimeS = movingTimeS
        self.distanceM = distanceM
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // ids are strings ("i86544321") today, ints historically.
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else {
            id = String(try c.decode(Int.self, forKey: .id))
        }
        name = try c.decodeIfPresent(String.self, forKey: .name)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        startDateLocal = try c.decodeIfPresent(String.self, forKey: .startDateLocal)
        startDateUtc = try c.decodeIfPresent(String.self, forKey: .startDateUtc)
        timezone = try c.decodeIfPresent(String.self, forKey: .timezone)
        movingTimeS = try c.decodeIfPresent(Int.self, forKey: .movingTimeS)
        distanceM = try c.decodeIfPresent(Double.self, forKey: .distanceM)
    }

    /// **When this activity happened** — a real instant, from `start_date`.
    ///
    /// This used to be built out of `start_date_local`, which is a wall clock with no zone
    /// attached, parsed in whatever zone the *phone* was in. On a phone that agreed with
    /// the athlete's zone that produced the right instant by luck; on any other one it
    /// produced an instant an hour or nine out — and this value is the library's dedupe
    /// key (±60 s) and the new-activity watch's identity check. An hour of error there does
    /// not make a session look slightly wrong: it makes it look like a *different session*,
    /// so the same afternoon downloads and notifies twice.
    ///
    /// `start_date_local` is still decoded, and still shown — but as words, never as a
    /// moment. Falls back to it only when `start_date` is absent, which is the old
    /// behaviour and the old risk, and is better than having no instant at all.
    public var startDate: Date? {
        if let raw = startDateUtc, let date = Self.parseUtc(raw) { return date }
        guard let raw = startDateLocal else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = displayZone ?? .current
        return formatter.date(from: String(raw.prefix(19)))
    }

    /// The athlete's own zone for this activity, when intervals.icu named one.
    public var displayZone: TimeZone? {
        timezone.flatMap(TimeZone.init(identifier:))
    }

    /// The zone as a UTC offset in seconds at *this session's* instant — what the library
    /// stores (`SessionRow.startUtcOffsetS`).
    ///
    /// Resolved at the session's own moment rather than as a fixed number, because that is
    /// the only way "Europe/Rome" answers +7200 in August and +3600 in November. When there
    /// is no zone name, the offset between the two timestamps is the same fact stated
    /// arithmetically, and is used instead.
    public var utcOffsetS: Int? {
        if let zone = displayZone, let date = startDate {
            return zone.secondsFromGMT(for: date)
        }
        guard let local = startDateLocal, let utc = startDateUtc,
              let utcDate = Self.parseUtc(utc) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        guard let localAsUtc = formatter.date(from: String(local.prefix(19))) else { return nil }
        return Int(localAsUtc.timeIntervalSince(utcDate).rounded())
    }

    /// `start_date` with or without the trailing `Z`, and with or without fractional
    /// seconds — intervals.icu has spelled it all three ways.
    static func parseUtc(_ raw: String) -> Date? {
        let text = String(raw.prefix(19))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: text)
    }
}

/// Injection seam so the client is testable without a network.
public protocol IcuTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: IcuTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw IcuClient.Error.transport("no HTTP response")
        }
        return (data, http)
    }
}

/// intervals.icu REST client (personal API key, HTTP Basic user `API_KEY`).
/// Mirrors `lab/tools/download_icu.py`.
public struct IcuClient: Sendable {

    public enum Error: Swift.Error, CustomStringConvertible {
        case missingKey
        case unauthorized
        case http(status: Int, body: String)
        case transport(String)
        case decoding(String)

        public var description: String {
            switch self {
            case .missingKey: "no intervals.icu API key configured"
            case .unauthorized: "intervals.icu rejected the API key (401/403)"
            case .http(let s, let b): "intervals.icu HTTP \(s): \(b.prefix(200))"
            case .transport(let m): "network error: \(m)"
            case .decoding(let m): "unexpected response: \(m)"
            }
        }
    }

    /// Activity types that are watersports regardless of the name.
    public static let watersportTypes: Set<String> = [
        "Windsurf", "Kitesurf", "Sail", "Surfing", "StandUpPaddling",
    ]
    /// Name keywords that rescue the CIQ recordings mis-typed as Walk
    /// (same keyword set as `download_icu.py`'s regex).
    public static let nameKeywords = ["wing", "foil", "windsurf", "kite", "surf", "sup"]

    public static let defaultBaseURL = URL(string: "https://intervals.icu/api/v1")!
    static let userAgent = "CleanJibe-iOS/0.1 (personal use)"

    public let apiKey: String
    public let baseURL: URL
    let transport: any IcuTransport

    public init(apiKey: String, baseURL: URL = IcuClient.defaultBaseURL,
                transport: any IcuTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.transport = transport
    }

    public static func isWatersport(_ activity: IcuActivity) -> Bool {
        if let type = activity.type, watersportTypes.contains(type) { return true }
        let name = (activity.name ?? "").lowercased()
        return nameKeywords.contains { name.contains($0) }
    }

    // MARK: - Endpoints

    public func activities(oldest: Date, newest: Date = Date()) async throws -> [IcuActivity] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("athlete/0/activities"),
            resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "oldest", value: Self.day(oldest)),
            URLQueryItem(name: "newest", value: Self.day(newest)),
        ]
        let data = try await get(components.url!)
        do {
            return try JSONDecoder().decode([IcuActivity].self, from: data)
        } catch {
            throw Error.decoding("\(error)")
        }
    }

    /// The original uploaded file, unwrapped to FIT bytes (gzip / ZIP / plain all handled).
    public func originalFit(activityID: String) async throws -> Data {
        let url = baseURL.appendingPathComponent("activity/\(activityID)/file")
        return try IcuPayload.unwrap(try await get(url))
    }

    // MARK: - Plumbing

    private func get(_ url: URL) async throws -> Data {
        guard !apiKey.isEmpty else { throw Error.missingKey }
        var request = URLRequest(url: url)
        request.setValue(Self.basicAuth(key: apiKey), forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 120
        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403: throw Error.unauthorized
        default: throw Error.http(status: response.statusCode,
                                  body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    static func basicAuth(key: String) -> String {
        "Basic " + Data("API_KEY:\(key)".utf8).base64EncodedString()
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
