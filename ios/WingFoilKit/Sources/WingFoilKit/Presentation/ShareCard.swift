import Foundation

/// Everything printed on a shareable session card, resolved once so the SwiftUI view that
/// renders it is pure layout — and so the *content* can be tested without a renderer.
///
/// Every stat is a display string, including the em-dash placeholders: a card is an image,
/// so "—" has to be decided here rather than by an optional binding at draw time.
public struct ShareCardStats: Sendable, Equatable {

    /// One headline number with its label, in the order the card lays them out.
    public struct Stat: Sendable, Equatable, Identifiable {
        public let key: String
        public let label: String
        public let value: String
        /// Shown under the value when there is something worth saying.
        public let caption: String?

        public var id: String { key }

        public init(key: String, label: String, value: String, caption: String? = nil) {
            self.key = key
            self.label = label
            self.value = value
            self.caption = caption
        }
    }

    /// Aspect of the exported image.
    public enum Shape: String, CaseIterable, Sendable, Identifiable {
        /// 1080 × 1350 — the tall format feeds and stories prefer.
        case portrait
        /// 1080 × 1080.
        case square
        /// 1920 × 1080 — the wide format a chat preview, a forum post or a desktop
        /// screen shows in full instead of cropping to a letterbox.
        case landscape

        public var id: String { rawValue }

        public var size: (width: Double, height: Double) {
            switch self {
            case .portrait: (1080, 1350)
            case .square: (1080, 1080)
            case .landscape: (1920, 1080)
            }
        }

        public var label: String {
            switch self {
            case .portrait: "Portrait"
            case .square: "Square"
            case .landscape: "Landscape"
            }
        }

        /// True when the card is wider than it is tall, and the track therefore belongs
        /// *beside* the stats rather than above them. The renderer asks the shape rather
        /// than testing for a case, so a fourth aspect lands in the right layout for free.
        public var isWide: Bool { size.width > size.height }
    }

    public let title: String
    public let dateLine: String
    public let stats: [Stat]
    /// "9 flew · 9 touch · 12 fell" — nil when no turn was classified.
    public let turnLine: String?
    /// Set when the session's records cannot be certified, so the card cannot be read as
    /// a speed claim it has no right to make.
    public let disclaimer: String?

    public init(title: String, dateLine: String, stats: [Stat], turnLine: String?,
                disclaimer: String?) {
        self.title = title
        self.dateLine = dateLine
        self.stats = stats
        self.turnLine = turnLine
        self.disclaimer = disclaimer
    }

    // MARK: - Building

    /// Builds the card content from the stored summary row.
    ///
    /// `title` is the caller's (the app derives a readable name from the spot or the
    /// original filename, which is presentation the kit has no business owning).
    public static func make(row: SessionRow, title: String,
                            timeZone: TimeZone = .current) -> ShareCardStats {
        // Exactly four, always — the card lays them out as a 2 × 2 block at a fixed size,
        // and a variable count would either orphan a cell or push the footer off the
        // bottom of the exported image. The turn tally goes on its own line instead.
        let stats: [Stat] = [
            Stat(key: "foilPct", label: "Foil time", value: percent(row.foilPct),
                 caption: row.foilTimeS.map(duration)),
            Stat(key: "flights", label: "Flights", value: row.flightCount.map(String.init) ?? "—",
                 caption: row.durationS > 0 ? duration(row.durationS) + " out" : nil),
            Stat(key: "longestFlight", label: "Longest",
                 value: row.longestFlightS.map(duration) ?? "—",
                 caption: row.longestFlightM.map { meters($0) }),
            Stat(key: "best2s", label: "Best 2 s", value: knots(row.best2sKn),
                 caption: row.distanceKm.map { String(format: "%.1f km", $0) }),
        ]

        return ShareCardStats(
            title: title,
            dateLine: dateLine(row.startDate, timeZone: timeZone),
            stats: stats,
            turnLine: turnLine(row),
            disclaimer: row.sourceClass == "c"
                ? "Speeds from a degraded source — uncertified" : nil)
    }

    /// "30 jibes · 9 flew · 9 touch · 12 fell" over the counted turns. The jibe count is
    /// prefixed when there is one, because "9 flew" on its own does not say out of how many.
    static func turnLine(_ row: SessionRow) -> String? {
        let flew = row.turnsFlewThrough ?? 0
        let touch = row.turnsTouchdown ?? 0
        let fell = row.turnsFellIn ?? 0
        guard flew + touch + fell > 0 else { return nil }
        let outcomes = "\(flew) flew · \(touch) touch · \(fell) fell"
        guard let jibes = row.jibes, jibes > 0 else { return outcomes }
        return "\(jibes) jibes · " + outcomes
    }

    static func dateLine(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    // MARK: - Formatting
    //
    // Deliberately local rather than reusing the app's `Fmt`: the card is rendered into a
    // fixed-size image, so it must not pick up a locale's decimal comma or a 24-hour clock
    // and reflow. Everything here is POSIX-stable.

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f%%", value)
    }

    static func knots(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f kn", value)
    }

    static func meters(_ value: Double) -> String {
        value >= 1000 ? String(format: "%.2f km", value / 1000)
                      : String(format: "%.0f m", value)
    }

    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        if h > 0 { return "\(h) h \(m) m" }
        if m > 0 { return "\(m) m" }
        return "\(s) s"
    }
}
