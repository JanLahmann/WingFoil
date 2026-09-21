import Foundation

/// The rider's units, on the wrist.
///
/// **Knots or km/h, and the phone decides** (Settings → Units, 20 September 2026). The
/// GP3S record vocabulary the app is built on is stated in knots and that is still the
/// default, but a rider who has asked the phone for km/h has asked the whole product for
/// km/h — a watch that kept knots would be the one screen of his that disagreed with his
/// library, which is exactly the complaint the setting exists to answer.
///
/// The choice arrives over WatchConnectivity as an application context
/// (`SessionTransfer`), is stored under the phone's own key, and is read back at launch so
/// a watch out of range still prints what the rider last chose. The engine is untouched:
/// `speed(_:)` takes metres per second, as it always has, and converts on its way to the
/// glass.
enum WatchFormat {

    /// Mirrors `Units.mpsToKn` in WingFoilKit.
    static let mpsToKn = 1.9438445
    /// Mirrors `SpeedUnit.kmhPerKnot`.
    static let kmhPerKnot = 1.852

    /// Mirrors `SpeedUnit` in WingFoilKit — shared by value over the link rather than by
    /// source, because the watch app compiles none of the kit (project.yml says why).
    enum Unit: String {
        case knots
        case kmh

        /// The word after the number: `kn` · `km/h`. The one place either is spelled on the
        /// wrist, which is what keeps `RecordingView` and `SummaryView` honest.
        var suffix: String {
            switch self {
            case .knots: "kn"
            case .kmh: "km/h"
            }
        }
    }

    /// The same defaults key the phone stores its choice under (`SpeedUnitStore`), so the
    /// two sides cannot drift apart in spelling.
    static let defaultsKey = "speedUnit.v1"

    /// A lock around the one mutable value, which is `Speed`'s own arrangement in the kit:
    /// the unit is written by a WatchConnectivity callback and read by every view, so it
    /// cannot be a bare global under strict concurrency.
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var value = UserDefaults.standard.string(forKey: WatchFormat.defaultsKey)
            .flatMap(Unit.init(rawValue:)) ?? .knots

        var unit: Unit {
            get { lock.lock(); defer { lock.unlock() }; return value }
            set { lock.lock(); value = newValue; lock.unlock() }
        }
    }

    private static let box = Box()

    /// What this watch is printing speeds in. Knots until the phone says otherwise, and
    /// knots again if a future build sends a unit this one has never heard of.
    static var unit: Unit {
        get { box.unit }
        set { box.unit = newValue }
    }

    /// Stores and applies a unit the phone sent. Unknown values are ignored rather than
    /// defaulted over: the rider's last known choice is a better answer than a reset.
    static func apply(_ raw: String?) {
        guard let raw, let next = Unit(rawValue: raw) else { return }
        unit = next
        UserDefaults.standard.set(raw, forKey: defaultsKey)
    }

    /// The word after the number, once, for the label beside the giant reading.
    static var speedUnitWord: String { unit.suffix }

    /// The giant number. Two decimals below 10, one above — a wingfoiler cares about the
    /// difference between 8.4 and 8.6 while getting up, and about nothing smaller than a
    /// tenth once flying, and six characters is all that fits at this size. The magnitude
    /// switch is read in the unit on the glass, so km/h crosses it where km/h should.
    static func speed(_ mps: Double) -> String {
        let value = mps * mpsToKn * (unit == .kmh ? kmhPerKnot : 1)
        guard value.isFinite, value > 0 else { return "0.0" }
        return value < 10 ? String(format: "%.2f", value) : String(format: "%.1f", value)
    }

    /// `1:04:22` past an hour, `4:22` below it. Leading zeros dropped: the elapsed clock is
    /// glanced at with a wing in one hand.
    static func duration(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Metres under a kilometre, kilometres above. Matches `KeyMetrics.km`'s one decimal.
    static func distance(_ metres: Double) -> String {
        metres < 1000 ? "\(Int(metres)) m" : String(format: "%.1f km", metres / 1000)
    }

    static func heartRate(_ bpm: Double?) -> String {
        guard let bpm, bpm > 0 else { return "--" }
        return "\(Int(bpm.rounded()))"
    }
}
