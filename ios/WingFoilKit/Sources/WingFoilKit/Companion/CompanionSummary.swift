import Foundation

/// The watch's session card, decoded (phase 5, `garmin/source/comm/PhoneLink.mc`).
///
/// WHAT THIS IS. Seconds after the rider presses Save, the watch transmits ~200 bytes of
/// integers over the BLE link — the twenty numbers the session list wants to draw *now*,
/// an hour before Garmin Connect gets round to syncing the FIT. This type is that payload
/// after it has survived validation. It is a **notification, never a source of truth**:
/// when the FIT lands, everything here is recomputed from the recording and thrown away.
///
/// WHY IT VALIDATES SO HARD. This is untrusted input. It crosses a process boundary (the
/// Garmin Connect Mobile app hands it to us), it is typed `Any` on arrival, and the watch
/// on the other end may be running a build older or newer than this app. So: nothing is
/// force-unwrapped, nothing traps, every value is range-checked against what a wingfoil
/// session can physically be, and a payload that fails any check is rejected whole. A
/// rejected card costs the rider a few minutes of impatience; a card believed on faith
/// puts a session with a 1970 date or a 4000-knot record into the library for ever.
///
/// WHY THE SCHEMA VERSION IS READ BY KEY. Monkey C's `Dictionary.keys()` is hash order and
/// the link hands the payload over unordered anyway, so "the first entry" means nothing on
/// either side. The version is found by its key, before any other key is interpreted, and
/// an unknown version is refused rather than guessed at — an old app paired with a new
/// watch shows nothing, which is recoverable, instead of wrong numbers, which is not.
public struct CompanionSummary: Sendable, Equatable {

    /// The only payload schema this build can read. Bump on the watch AND here together;
    /// the watch's `PhoneLink.SCHEMA` is the other half of this constant.
    public static let schemaVersion = 1

    // MARK: Identity (the dedupe key)

    /// FIT `session.start_time`, to the second. Sampled on the watch at the instant
    /// `ActivityRecording.Session.start()` is called, which is what the FIT stamps.
    public let startDate: Date
    /// FIT `session.total_elapsed_time`: wall clock from start to save, **including**
    /// paused time. Not timer time — see the watch header, the two differ after a pause.
    public let durationS: Double

    // MARK: The card

    public let foilTimeS: Double
    /// 0…100, already clamped by the watch.
    public let foilPct: Double
    public let flightCount: Int
    public let longestFlightS: Double
    public let longestFlightM: Double
    public let distanceM: Double
    public let best2sKn: Double
    public let best10sKn: Double
    public let turnCount: Int
    public let tacks: Int
    public let jibes: Int
    public let flewThrough: Int
    public let touchdowns: Int
    public let fellIn: Int
    public let takeoffAttempts: Int
    public let takeoffSuccesses: Int
    /// Degrees the wind blows FROM, or nil when the rider never set it (the watch sends
    /// -1 for "unset", and an unset axis means turns were never split into tacks/jibes).
    public let windDirDeg: Double?
    /// Watch build tag: `APP_MINOR * 256 + FIT schema version`. Diagnostic only — kept so
    /// a rider reporting odd numbers can be asked which watch build produced them.
    public let appVersion: Int

    // MARK: - Wire keys

    /// Two characters each, matching `PhoneLink.KEY_*` one for one. The version tag is the
    /// single-character key, reserved that shape on the watch so a reader can pick it out.
    enum Key {
        static let version = "v"
        static let start = "st"
        static let duration = "du"
        static let foilTime = "ft"
        static let foilPct = "fp"
        static let flights = "fc"
        static let longestS = "ls"
        static let longestM = "lm"
        static let distanceM = "ds"
        static let best2s = "b2"
        static let best10s = "bt"
        static let turns = "tn"
        static let tacks = "tk"
        static let jibes = "jb"
        static let flew = "of"
        static let touchdown = "ot"
        static let fell = "ox"
        static let takeoffAttempts = "ka"
        static let takeoffSuccesses = "ks"
        static let wind = "wd"
        static let appVersion = "av"
    }

    // MARK: - Decoding

    /// Decodes a payload as it arrives from the link: an untyped dictionary of untyped
    /// values. Throws on anything it cannot vouch for; never traps.
    ///
    /// `Any` rather than a typed dictionary because that is genuinely what the SDK hands
    /// over — `[AnyHashable: Any]`, `NSDictionary`, or (from a confused sender) a string,
    /// an array or nothing at all. Narrowing happens here, once, at the boundary.
    public init(payload: Any?) throws {
        guard let dictionary = Self.entries(payload) else {
            throw CompanionDecodeError.notADictionary
        }

        // The version first and by key, before a single other value is looked at.
        guard let rawVersion = dictionary[Key.version] else {
            throw CompanionDecodeError.missingSchemaVersion
        }
        guard let version = Self.integer(rawVersion) else {
            throw CompanionDecodeError.notAnInteger(key: Key.version)
        }
        guard version == Self.schemaVersion else {
            throw CompanionDecodeError.unsupportedSchemaVersion(version)
        }

        // Ranges are "what a wingfoil session can physically be", generous on purpose:
        // the job is to catch a corrupt or hostile payload, not to second-guess a rider
        // who did something remarkable. A 24-hour ceiling on every duration, a 10 000 km
        // ceiling on distance, ~194 kn (100 m/s) on the speeds.
        let start = try Self.value(dictionary, Key.start, in: Self.plausibleEpoch)
        let duration = try Self.value(dictionary, Key.duration, in: 1...Self.maxDurationS)

        startDate = Date(timeIntervalSince1970: Double(start))
        durationS = Double(duration)

        // Foil time is timer time and the duration is elapsed time, so foil time cannot
        // exceed it by more than rounding — but the watch itself clamps rather than
        // trusts that arithmetic, so this only range-checks and does not cross-check.
        foilTimeS = Double(try Self.value(dictionary, Key.foilTime, in: 0...Self.maxDurationS))
        foilPct = Double(try Self.value(dictionary, Key.foilPct, in: 0...100))
        flightCount = try Self.value(dictionary, Key.flights, in: 0...Self.maxCount)
        longestFlightS = Double(try Self.value(dictionary, Key.longestS, in: 0...Self.maxDurationS))
        longestFlightM = Double(try Self.value(dictionary, Key.longestM, in: 0...Self.maxDistanceM))
        distanceM = Double(try Self.value(dictionary, Key.distanceM, in: 0...Self.maxDistanceM))

        // Speeds arrive in cm/s: the watch multiplies m/s by 100 and truncates, so that
        // the link never has to carry a float and the phone never has to guess whether
        // 12.0 meant 12 or 12.04.
        best2sKn = Double(try Self.value(dictionary, Key.best2s, in: 0...Self.maxSpeedCmS))
            / 100 * Units.mpsToKn
        best10sKn = Double(try Self.value(dictionary, Key.best10s, in: 0...Self.maxSpeedCmS))
            / 100 * Units.mpsToKn

        turnCount = try Self.value(dictionary, Key.turns, in: 0...Self.maxCount)
        tacks = try Self.value(dictionary, Key.tacks, in: 0...Self.maxCount)
        jibes = try Self.value(dictionary, Key.jibes, in: 0...Self.maxCount)
        flewThrough = try Self.value(dictionary, Key.flew, in: 0...Self.maxCount)
        touchdowns = try Self.value(dictionary, Key.touchdown, in: 0...Self.maxCount)
        fellIn = try Self.value(dictionary, Key.fell, in: 0...Self.maxCount)
        takeoffAttempts = try Self.value(dictionary, Key.takeoffAttempts, in: 0...Self.maxCount)
        takeoffSuccesses = try Self.value(dictionary, Key.takeoffSuccesses, in: 0...Self.maxCount)

        // -1 is the watch's "the rider never set a wind direction" (WingFoilCore.Config).
        let wind = try Self.value(dictionary, Key.wind, in: -1...359)
        windDirDeg = wind < 0 ? nil : Double(wind)

        appVersion = try Self.value(dictionary, Key.appVersion, in: 0...65535)
    }

    // MARK: - Reconciliation

    /// Start time + duration, the pair the FIT means by `start_time` / `total_elapsed_time`.
    ///
    /// There is exactly one dedupe rule in this app and it lives in `SessionIngestor`
    /// (start within ±60 s **and** duration within ±60 s). The card goes through that rule
    /// rather than carrying one of its own: a second mechanism that agreed with the first
    /// 99 % of the time would show the rider the same session twice, silently, because
    /// nothing on either side can tell a duplicate from two back-to-back sessions.
    public var dedupeKey: (startDate: Date, durationS: Double) { (startDate, durationS) }

    // MARK: - Limits

    /// 2010-01-01 … 2100-01-01. A watch whose clock never got a GPS fix stamps 1989 or
    /// 1970; that is not a session, it is a session with no date, and it would sort to the
    /// bottom of the library for ever.
    static let plausibleEpoch = 1_262_304_000...4_102_444_800
    static let maxDurationS = 86_400
    static let maxDistanceM = 10_000_000
    /// 100 m/s in cm/s ≈ 194 kn. The world sailing speed record is 65.
    static let maxSpeedCmS = 10_000
    static let maxCount = 100_000

    // MARK: - Untyped access

    /// Flattens whatever the link handed us into `[String: Any]`, or nil if it was not a
    /// dictionary at all. `AnyHashable` keys because an ObjC `NSDictionary` bridges that
    /// way; non-string keys are simply not ours and are dropped.
    private static func entries(_ payload: Any?) -> [String: Any]? {
        guard let payload else { return nil }
        if let typed = payload as? [String: Any] { return typed }
        guard let loose = payload as? [AnyHashable: Any] else { return nil }
        var out: [String: Any] = [:]
        for (key, value) in loose {
            if let key = key.base as? String { out[key] = value }
        }
        return out
    }

    /// Reads one key: present, integral, and inside `range` — or the whole card is refused.
    private static func value(_ dictionary: [String: Any], _ key: String,
                              in range: ClosedRange<Int>) throws -> Int {
        guard let raw = dictionary[key] else { throw CompanionDecodeError.missingKey(key) }
        guard let number = integer(raw) else {
            throw CompanionDecodeError.notAnInteger(key: key)
        }
        guard range.contains(number) else {
            throw CompanionDecodeError.outOfRange(key: key, value: number)
        }
        return number
    }

    /// The one place a wire value becomes an `Int`.
    ///
    /// Every value on this link is a Monkey C `Lang.Number`, which reaches us as an
    /// `NSNumber`. The width cases exist because nothing guarantees which one the bridge
    /// picks; the float case accepts only an exactly-integral double, so a payload that
    /// went through a JSON round-trip somewhere still reads, but 3.7 does not become 3.
    ///
    /// Booleans are rejected first and deliberately: `NSNumber` bridging is happy to read
    /// `true` as 1, and a card that claims one flight because a sender wrote a flag is
    /// worse than a card that is refused.
    static func integer(_ raw: Any?) -> Int? {
        guard let raw else { return nil }
        if let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return nil
        }
        switch raw {
        case let value as Int: return value
        case let value as Int64: return Int(exactly: value)
        case let value as Int32: return Int(value)
        case let value as Int16: return Int(value)
        case let value as Int8: return Int(value)
        case let value as UInt: return Int(exactly: value)
        case let value as UInt64: return Int(exactly: value)
        case let value as UInt32: return Int(exactly: value)
        case let value as Double: return Int(exactly: value)
        case let value as NSNumber: return Int(exactly: value.doubleValue)
        default: return nil
        }
    }
}

/// Why a card was refused. Every case is a fact about the payload, not about the rider —
/// these are logged and counted, never shown as an alert: a dropped card is invisible by
/// design, because the FIT is still coming and it is the one that matters.
public enum CompanionDecodeError: Error, Equatable, Sendable {
    case notADictionary
    case missingSchemaVersion
    case unsupportedSchemaVersion(Int)
    case missingKey(String)
    case notAnInteger(key: String)
    case outOfRange(key: String, value: Int)
}
