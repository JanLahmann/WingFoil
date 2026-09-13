import Foundation

/// The activity types CleanJibe offers to pull from Strava.
///
/// **Strava has no wingfoil type.** It has had none for as long as the API has existed, so
/// every rider on it has already picked something else — and which something else is a
/// matter of local habit rather than of fact: some file the afternoon under Windsurf, some
/// under Kitesurf because that is what the board looks like, some under Surfing, and a
/// great many under the catch-all Workout because it is the type that asks no questions.
/// There is no inference available here that would be better than asking, so the rider
/// picks the set once (Import → Strava) and it is remembered.
///
/// The four defaults are the four that actually hold wingfoil sessions in the wild. `sail`
/// and `standUpPaddling` are off by default rather than absent: for most people those two
/// buckets hold boats and flat-water paddling, and a default that imports somebody's
/// dinghy racing is worse than one they have to switch on.
public enum StravaActivityType: String, Sendable, CaseIterable, Identifiable, Codable {
    case windsurf = "Windsurf"
    case kitesurf = "Kitesurf"
    case surfing = "Surfing"
    case workout = "Workout"
    case sail = "Sail"
    case standUpPaddling = "StandUpPaddling"

    public var id: String { rawValue }

    /// What the rider sees — Strava's own words for these.
    public var label: String {
        switch self {
        case .windsurf: "Windsurf"
        case .kitesurf: "Kitesurf"
        case .surfing: "Surf"
        case .workout: "Workout"
        case .sail: "Sail"
        case .standUpPaddling: "Stand-up paddling"
        }
    }

    public static let defaults: Set<StravaActivityType> = [.windsurf, .kitesurf, .surfing,
                                                           .workout]
}

/// One entry of `GET /api/v3/athlete/activities` (Strava's `SummaryActivity`).
///
/// Only the fields CleanJibe needs are decoded and every one of them is optional, because
/// Strava adds columns freely and a new one must never break a sync. Same tolerance rule
/// `IcuActivity` keeps, for the same reason.
public struct StravaActivity: Sendable, Codable, Identifiable, Equatable {
    /// Strava's numeric id, carried as a string — it is an identifier, never arithmetic,
    /// and the library stores identifiers as text.
    public var id: String
    public var name: String?
    /// `sport_type`, the current field. `type` is the deprecated one it replaced and is
    /// read as a fallback only (see the decoder).
    public var sportType: String?
    /// UTC instant — Strava's `start_date`, always `…Z`.
    public var startDateUtc: String?
    /// The rider's own wall clock — `start_date_local`, with no zone on it. Display only,
    /// never made into an instant.
    public var startDateLocal: String?
    /// Strava's `timezone`, spelled `"(GMT+01:00) Europe/Berlin"`.
    public var timezone: String?
    /// Strava's `utc_offset`, in seconds. The exact answer to "what clock was he on", and
    /// the reason a Strava session gets rung 1 of the offset ladder rather than the
    /// longitude guess (docs/algorithms.md "Session time").
    public var utcOffsetS: Int?
    public var elapsedTimeS: Int?
    public var movingTimeS: Int?
    public var distanceM: Double?
    /// `start_latlng` — empty (or absent) on an activity Strava has no GPS for, which is
    /// the one thing that makes an activity useless here: no positions, no analysis.
    public var startLatLng: [Double]?
    /// Strava's `manual`: the rider typed the activity in and there is no recording behind
    /// it at all, so there are no streams to ask for.
    public var isManual: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, timezone, distance
        case sportType = "sport_type"
        case type
        case startDateUtc = "start_date"
        case startDateLocal = "start_date_local"
        case utcOffset = "utc_offset"
        case elapsedTime = "elapsed_time"
        case movingTime = "moving_time"
        case startLatLng = "start_latlng"
        case manual
    }

    public init(id: String, name: String? = nil, sportType: String? = nil,
                startDateUtc: String? = nil, startDateLocal: String? = nil,
                timezone: String? = nil, utcOffsetS: Int? = nil,
                elapsedTimeS: Int? = nil, movingTimeS: Int? = nil,
                distanceM: Double? = nil, startLatLng: [Double]? = nil,
                isManual: Bool? = nil) {
        self.id = id
        self.name = name
        self.sportType = sportType
        self.startDateUtc = startDateUtc
        self.startDateLocal = startDateLocal
        self.timezone = timezone
        self.utcOffsetS = utcOffsetS
        self.elapsedTimeS = elapsedTimeS
        self.movingTimeS = movingTimeS
        self.distanceM = distanceM
        self.startLatLng = startLatLng
        self.isManual = isManual
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let n = try? c.decode(Int64.self, forKey: .id) {
            id = String(n)
        } else {
            id = try c.decode(String.self, forKey: .id)
        }
        name = try c.decodeIfPresent(String.self, forKey: .name)
        // `sport_type` since 2022; `type` is the field it replaced and is still sent.
        sportType = try c.decodeIfPresent(String.self, forKey: .sportType)
            ?? c.decodeIfPresent(String.self, forKey: .type)
        startDateUtc = try c.decodeIfPresent(String.self, forKey: .startDateUtc)
        startDateLocal = try c.decodeIfPresent(String.self, forKey: .startDateLocal)
        timezone = try c.decodeIfPresent(String.self, forKey: .timezone)
        // Strava writes it as a float (`7200.0`).
        utcOffsetS = (try c.decodeIfPresent(Double.self, forKey: .utcOffset)).map { Int($0) }
        elapsedTimeS = try c.decodeIfPresent(Int.self, forKey: .elapsedTime)
        movingTimeS = try c.decodeIfPresent(Int.self, forKey: .movingTime)
        distanceM = try c.decodeIfPresent(Double.self, forKey: .distance)
        startLatLng = try c.decodeIfPresent([Double].self, forKey: .startLatLng)
        isManual = try c.decodeIfPresent(Bool.self, forKey: .manual)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(sportType, forKey: .sportType)
        try c.encodeIfPresent(startDateUtc, forKey: .startDateUtc)
        try c.encodeIfPresent(startDateLocal, forKey: .startDateLocal)
        try c.encodeIfPresent(timezone, forKey: .timezone)
        try c.encodeIfPresent(utcOffsetS.map(Double.init), forKey: .utcOffset)
        try c.encodeIfPresent(elapsedTimeS, forKey: .elapsedTime)
        try c.encodeIfPresent(movingTimeS, forKey: .movingTime)
        try c.encodeIfPresent(distanceM, forKey: .distance)
        try c.encodeIfPresent(startLatLng, forKey: .startLatLng)
        try c.encodeIfPresent(isManual, forKey: .manual)
    }

    // MARK: - Derived

    /// **When this activity happened**, as a real instant.
    ///
    /// From `start_date`, which Strava always writes in UTC. `start_date_local` is decoded
    /// and shown, never turned into a moment: it is a wall clock with no zone on it, and
    /// parsing one in the phone's zone is how a session ends up an hour out — which, since
    /// this is half the library's dedupe key, does not make a session look slightly wrong
    /// but makes it look like a *different* session. Same rule, and the same scar, as
    /// `IcuActivity.startDate`.
    public var startDate: Date? {
        guard let raw = startDateUtc else { return nil }
        return StravaActivity.parseUtc(raw)
    }

    /// The rider's zone name, dug out of Strava's `"(GMT+01:00) Europe/Berlin"`.
    public var displayZone: TimeZone? {
        guard let timezone else { return nil }
        let name = timezone.split(separator: " ").last.map(String.init) ?? timezone
        return TimeZone(identifier: name)
    }

    /// The UTC offset to draw this session's clock on: Strava's own `utc_offset` first,
    /// then the zone name resolved at this session's instant.
    public var resolvedUtcOffsetS: Int? {
        if let utcOffsetS { return utcOffsetS }
        guard let zone = displayZone, let date = startDate else { return nil }
        return zone.secondsFromGMT(for: date)
    }

    /// What the library will call this session's length before the streams arrive — the
    /// half of the dedupe key that is not the start time.
    public var durationS: Double? {
        elapsedTimeS.map(Double.init) ?? movingTimeS.map(Double.init)
    }

    /// Does Strava hold a GPS recording for this activity at all?
    ///
    /// A manual entry ("I rode for two hours") has no streams, and an activity with no
    /// `start_latlng` was recorded without a fix — an indoor workout, a watch that never
    /// locked. Both are refused here rather than after a wasted request against a rate
    /// limit of a hundred.
    public var hasRoute: Bool {
        if isManual == true { return false }
        guard let point = startLatLng, point.count >= 2 else { return false }
        return !(point[0] == 0 && point[1] == 0)
    }

    /// `"2026-08-06T05:57:21Z"` → an instant.
    static func parseUtc(_ raw: String) -> Date? {
        let text = String(raw.prefix(19))
        guard text.count == 19 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: text)
    }
}

/// Which of an athlete's activities CleanJibe will offer to import.
///
/// Two rules, ORed, and both of them are about not silently importing somebody's bike ride:
///
/// * the **type** is one the rider switched on, or
/// * the **name** says what it was — the rescue that catches the rider who files everything
///   under Workout and writes "Wingfoil Torbole" in the title. Same keyword set the
///   intervals.icu sync uses (`IcuClient.nameKeywords`), so the two doors agree about what
///   a watersport is called.
///
/// …and then, in both cases, the activity must actually have a recording behind it. That is
/// not a preference: without positions there is nothing to analyse.
public enum StravaActivityFilter {

    /// Name keywords that rescue an activity filed under a type nobody selected.
    public static let nameKeywords = ["wing", "foil", "windsurf", "kite", "surf", "sup"]

    public static func matches(_ activity: StravaActivity,
                               types: Set<StravaActivityType>) -> Bool {
        guard activity.hasRoute else { return false }
        if let raw = activity.sportType, let type = StravaActivityType(rawValue: raw),
           types.contains(type) {
            return true
        }
        let name = (activity.name ?? "").lowercased()
        return nameKeywords.contains { name.contains($0) }
    }
}
