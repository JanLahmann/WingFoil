import Foundation

/// **The unit every speed the phone shows is printed in.**
///
/// Jan, 20 September 2026, forwarding a user's request from a shared card: *speed unit
/// configurable, km/h besides knots*. The browser app has had the switch since the web
/// round the same day (`web/js/appsettings.js`); the phone had knots typed into nine
/// formatters.
///
/// **The engine is untouched.** Records are defined in knots by the speedsurfing world
/// (docs/algorithms.md, "Speed records") and the analysis stays in m/s and knots from end
/// to end. This converts one number on the way to a screen, and never on the way into a
/// record, a golden or a FIT.
public enum SpeedUnit: String, Codable, Sendable, CaseIterable, Identifiable {
    /// The default. The record windows are defined in knots and the watch world reads them.
    case knots
    case kmh

    public var id: String { rawValue }

    /// The word in the picker: "Knots" · "km/h".
    public var label: String {
        switch self {
        case .knots: "Knots"
        case .kmh: "km/h"
        }
    }

    /// The word after the number: "kn" · "km/h".
    public var suffix: String {
        switch self {
        case .knots: "kn"
        case .kmh: "km/h"
        }
    }

    /// km/h per knot. One constant, so no caller multiplies by a number it typed.
    static let kmhPerKnot = 1.852

    /// A speed the engine reported in knots, in this unit.
    public func value(fromKnots kn: Double) -> Double {
        self == .kmh ? kn * Self.kmhPerKnot : kn
    }
}

/// **The one speed formatter on the platform.** Every `kn` a rider reads goes through it.
///
/// It is a global rather than a parameter on nine call sites because the alternative was
/// measured: `KeyMetrics`, `RowMetric`, `ShareCardStats`, `PeriodBlock`, `TurnCoach`,
/// `TurnAnalytics`, `DivergenceCheck`, the app's `Fmt` and five chart axes each formatted
/// their own knots, and threading a preference through all of them means the next one
/// forgets. `SpeedUnitLintTests` asserts there is no second formatter.
///
/// The app sets `unit` once at launch and again whenever the picker moves
/// (`SpeedUnitStore`). Tests and every non-app reader get knots, which is what every
/// golden, every fixture and every pinned string was written in.
public enum Speed {

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var value = SpeedUnit.knots

        var unit: SpeedUnit {
            get { lock.lock(); defer { lock.unlock() }; return value }
            set { lock.lock(); value = newValue; lock.unlock() }
        }
    }

    private static let box = Box()

    /// **A unit for the duration of one task**, which is how a test asks for km/h without
    /// telling every other test that is running beside it. Nothing in the app sets it: the
    /// app writes `unit`, once, from the rider's stored choice.
    @TaskLocal public static var override: SpeedUnit?

    /// What the phone is printing speeds in right now. Knots until the app says otherwise.
    public static var unit: SpeedUnit {
        get { override ?? box.unit }
        set { box.unit = newValue }
    }

    /// The word after the number, for a chart axis or a column head that prints the unit
    /// once instead of on every row.
    public static var suffix: String { unit.suffix }

    /// A knots value in the rider's unit, unformatted — for a chart's y axis, which scales
    /// numbers rather than printing them.
    public static func value(_ kn: Double) -> Double { unit.value(fromKnots: kn) }

    /// `"13.25 kn"` / `"24.54 km/h"`, and `"—"` where the session has no answer.
    ///
    /// Two decimals, which is what the records have always printed. `digits` is for the
    /// one-decimal callers — a turn's entry and minimum, a chart callout.
    public static func format(_ kn: Double?, digits: Int = 2) -> String {
        guard let kn else { return "—" }
        return String(format: "%.\(digits)f %@", value(kn), unit.suffix)
    }

    /// The number alone, in the rider's unit, with no word after it — for a cell that
    /// carries its unit in a separate column.
    public static func number(_ kn: Double?, digits: Int = 2) -> String {
        guard let kn else { return "—" }
        return String(format: "%.\(digits)f", value(kn))
    }
}

/// The one stored copy of the rider's unit, the shape `ShareCardPresetStore` and
/// `MapLayerVisibilityStore` already use.
///
/// An unreadable or unknown stored value falls back to knots: the records are defined in
/// them, and a build that added a third unit must not strand an older app on a blank cell.
public enum SpeedUnitStore {

    public static let defaultsKey = "speedUnit.v1"

    public static func load(from defaults: UserDefaults) -> SpeedUnit {
        defaults.string(forKey: defaultsKey).flatMap(SpeedUnit.init(rawValue:)) ?? .knots
    }

    public static func save(_ unit: SpeedUnit, to defaults: UserDefaults) {
        defaults.set(unit.rawValue, forKey: defaultsKey)
    }

    /// Read the stored choice and apply it, which is the only way `Speed.unit` is ever set
    /// in the app. Called at launch and after the picker moves.
    public static func apply(from defaults: UserDefaults) {
        Speed.unit = load(from: defaults)
    }
}
