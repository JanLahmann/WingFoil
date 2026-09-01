import Foundation

/// The rider's units, on the wrist.
///
/// **Knots, and not as a preference.** There is no unit setting anywhere in CleanJibe — the
/// phone hardcodes knots (`KeyMetrics.knots`), the Garmin app does, the web analyzer does,
/// and the whole GP3S record vocabulary the app is built on is stated in knots. A watch that
/// offered a choice would be inventing a setting the rest of the product does not have, and
/// the first thing it would break is the rider's ability to compare the number on his wrist
/// with the number in his library.
enum WatchFormat {

    /// Mirrors `Units.mpsToKn` in WingFoilKit.
    static let mpsToKn = 1.9438445

    /// The giant number. Two decimals below 10 kn, one above — a wingfoiler cares about the
    /// difference between 8.4 and 8.6 while getting up, and about nothing smaller than a
    /// tenth once flying, and six characters is all that fits at this size.
    static func speed(_ mps: Double) -> String {
        let knots = mps * mpsToKn
        guard knots.isFinite, knots > 0 else { return "0.0" }
        return knots < 10 ? String(format: "%.2f", knots) : String(format: "%.1f", knots)
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
