import Foundation

/// **The aggregate block a period is described by** — one list, one order, both platforms.
///
/// A month, a season, a trip and a range the rider typed are four ways of naming a *set of
/// afternoons*, and the whole point of the feature is that they are all answered by the same
/// fifteen numbers in the same sequence. The analyzer says it in `PERIOD_BLOCK`
/// (`web/lab_bundle/library.py`), Python is the reference implementation, and the two are
/// pinned against one shared file — `fixtures/periods/periods.expected.json` — because two
/// hand-written test suites agreeing today is not two implementations that cannot drift.
///
/// Every entry is a **display string**, resolved here, for the same reason `ShareCardStats`
/// resolves the session card's: a period card is a PNG in somebody else's chat thread, so
/// every rounding and every absence has to be decided in a function a test can call rather
/// than by an optional binding at draw time.
///
/// **An entry the period cannot supply is omitted, never printed as a dash or a zero.** That
/// is the block's half of the project's "absent is never 0" rule, and it is also what lets a
/// card preset be a strict subset: a preset can only ever drop an entry, because anything the
/// block did not produce was never there to keep.
public enum PeriodBlock {

    /// One line of the block. `key` is the contract with `library.PERIOD_BLOCK`.
    public struct Entry: Sendable, Equatable, Identifiable, Codable {
        public let key: String
        public let label: String
        public let value: String

        public var id: String { key }

        public init(key: String, label: String, value: String) {
            self.key = key
            self.label = label
            self.value = value
        }
    }

    /// The catalogue, in the one order both platforms show it in. `label` is the word printed
    /// under the number, in the key-metrics block's own lowercase voice.
    public enum Key {
        public static let sessions = "sessions"
        public static let hours = "hours"
        public static let distance = "distance"
        public static let flights = "flights"
        public static let foilPct = "foilPct"
        public static let cleanJibes = "cleanJibes"
        public static let cph = "cph"
        public static let turns = "turns"
        public static let cleanJibeRate = "cleanJibeRate"
        public static let wph = "wph"
        public static let best2s = "best2s"
        public static let best10s = "best10s"
        public static let longestFlight = "longestFlight"
        public static let longestDryStreak = "longestDryStreak"
        public static let spots = "spots"
    }

    /// The catalogue's order, spelled once so a test can assert it against the analyzer's.
    public static let order: [String] = [
        Key.sessions, Key.hours, Key.distance, Key.flights, Key.foilPct, Key.cleanJibes,
        Key.cph, Key.turns, Key.cleanJibeRate, Key.wph, Key.best2s, Key.best10s,
        Key.longestFlight, Key.longestDryStreak, Key.spots,
    ]

    /// What the period card's `lean` preset keeps — the five a rider quotes about a holiday.
    /// Keys rather than a rebuilt list, the same rule `ShareCardStats.Preset.leanKeys` follows.
    public static let leanKeys: [String] = [
        Key.sessions, Key.hours, Key.cleanJibes, Key.cph, Key.best2s,
    ]

    /// Every number the block prints, before it is a string.
    ///
    /// nil is *absent*, and it survives as absent all the way to the card: a period whose
    /// rows all predate a field has no answer, where a period in which the rider genuinely
    /// did none of something has a measured zero and prints it.
    public struct Facts: Sendable, Equatable {
        public var sessions: Int = 0
        public var hours: Double?
        public var distanceKm: Double?
        public var flights: Int?
        public var foilPct: Double?
        public var cleanJibes: Int?
        public var cph: Double?
        public var turns: Int?
        public var cleanJibeRatePct: Double?
        public var wph: Double?
        public var best2sKn: Double?
        public var best10sKn: Double?
        public var longestFlightS: Double?
        public var longestDryStreak: Int?
        public var spots: Int = 0

        public init() {}
    }

    /// The facts as the block, in catalogue order, absences dropped.
    ///
    /// The formatters are `KeyMetrics`' own — `duration`, `km`, `knots`, `rate` — deliberately
    /// and not a second set: a duration on a period card has to read the way a duration reads
    /// on a session card, and a rate to one decimal there and two here would be two answers
    /// about one rider.
    public static func entries(_ f: Facts) -> [Entry] {
        var out: [Entry] = []
        func add(_ key: String, _ label: String, _ value: String?) {
            guard let value else { return }
            out.append(Entry(key: key, label: label, value: value))
        }
        add(Key.sessions, "sessions", count(f.sessions))
        add(Key.hours, "hours on the water", f.hours.map { String(format: "%.1f h", $0) })
        add(Key.distance, "distance", f.distanceKm.map(KeyMetrics.km))
        add(Key.flights, "flights", f.flights.map(count))
        add(Key.foilPct, "on foil", f.foilPct.map(percent))
        add(Key.cleanJibes, "clean jibes", f.cleanJibes.map(count))
        add(Key.cph, "CPH · clean jibes per hour", f.cph.map(KeyMetrics.rate))
        add(Key.turns, "turns", f.turns.map(count))
        add(Key.cleanJibeRate, "clean-jibe rate", f.cleanJibeRatePct.map(percent))
        add(Key.wph, "WPH · swims per hour", f.wph.map(KeyMetrics.rate))
        add(Key.best2s, "best 2 s", f.best2sKn.map { KeyMetrics.knots($0) })
        add(Key.best10s, "best 10 s", f.best10sKn.map { KeyMetrics.knots($0) })
        add(Key.longestFlight, "longest flight", f.longestFlightS.map(KeyMetrics.duration))
        add(Key.longestDryStreak, "longest dry streak", f.longestDryStreak.map(count))
        add(Key.spots, "spots visited", count(f.spots))
        return out
    }

    static func count(_ value: Int) -> String { String(value) }

    /// `59.7 %`, with the space the rest of both apps prints — `library._f_pct`'s twin.
    static func percent(_ value: Double) -> String { String(format: "%.1f %%", value) }
}
