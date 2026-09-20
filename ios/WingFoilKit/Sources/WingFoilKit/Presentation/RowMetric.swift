import Foundation

/// **The three numbers a library row carries, and the words that say what they are.**
///
/// The row read as code (Jan, Beta 75; pattern H in docs/review-checklist.md): *37 % · 3 ·
/// 13.25 kn* under three bare glyphs. A figure, a turning arrow and a speedometer are a
/// guess each, and the middle one was guessed wrong by the rider who asked for it — the
/// arrow drew the **flight** count and reads as jibes. A number a reader has to decode is a
/// number the row is not carrying.
///
/// So every metric here owns three things: the word it is called by, the glyph beside it,
/// and how its value is spelled. The word goes on the row under the number, which is what
/// the watch does with the same three facts, and it is the same word on the session page
/// and in the Settings picker — one wording per metric (docs/presentation.md).
///
/// **And the three are the rider's choice.** A row is the same three numbers a hundred times
/// down a scroll, and which three answer "was that a good afternoon" is a fact about the
/// rider, not about the app: one is chasing a speed, the next is counting clean jibes. The
/// default triple is the one the list has always drawn, with the middle cell corrected to the
/// jibes it always looked like.
public enum RowMetric: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Share of the session spent on the foil.
    case foilShare
    /// Flights: how many times he got up.
    case flights
    /// Counted jibes. 0 where the wind axis named none — see `turns` for that library.
    case jibes
    /// Jibes flown all the way through with the speed carried (`docs/algorithms.md`).
    case cleanJibes
    /// Every counted maneuver, for a rider whose sessions rarely resolve a wind axis.
    case turns
    case best2s
    case best10s
    case distance
    case duration
    /// The longest run of maneuvers that stayed out of the water.
    case dryStreak
    /// **Every fall of the session**, in a turn or in a straight line — `wetExits`, the
    /// flight-end channel WPH divides, and not the turn ladder's `turnsFellIn`.
    ///
    /// Offered on the row because that is where the question is asked (20 September 2026:
    /// a tester fell three times, and every count he could find was about turns). The turn
    /// ladder's fell-in count is deliberately *not* offerable here: it is a share of the
    /// jibes and only reads right beside the other two rungs, which a row cell has no room
    /// for (docs/algorithms.md, "Wet is every fall, not every fallen jibe").
    case falls

    public var id: String { rawValue }

    /// What the number is called, on the row and in the picker. Short on purpose: it sits
    /// under a value in caption type, beside two others, on a phone.
    public var label: String {
        switch self {
        case .foilShare: "foil"
        case .flights: "flights"
        case .jibes: "jibes"
        case .cleanJibes: "clean"
        case .turns: "turns"
        case .best2s: "best 2 s"
        case .best10s: "best 10 s"
        case .distance: "distance"
        case .duration: "time"
        case .dryStreak: "dry streak"
        case .falls: MetricGlossary.entry("fellIn").term.lowercased()
        }
    }

    /// The SF Symbol beside it. Never alone: the word under it is what makes it readable,
    /// and the glyph is what makes the row scannable once the word has been read once.
    public var icon: String {
        switch self {
        case .foilShare: "figure.wave"
        case .flights: "arrow.up.forward"
        case .jibes: "arrow.triangle.turn.up.right.diamond"
        case .cleanJibes: "checkmark.seal"
        case .turns: "arrow.triangle.2.circlepath"
        case .best2s, .best10s: "speedometer"
        case .distance: "point.topleft.down.to.point.bottomright.curvepath"
        case .duration: "clock"
        case .dryStreak: "flame"
        case .falls: "drop.fill"
        }
    }

    /// The value, spelled the way every other surface spells it. "—" where the row has no
    /// answer: a session the engine has not read yet reports an absence, never a zero.
    public func format(_ row: SessionRow) -> String {
        switch self {
        case .foilShare: Self.percent(row.foilPct)
        case .flights: Self.count(row.flightCount)
        case .jibes: Self.count(row.jibes)
        case .cleanJibes: Self.count(row.jibesSuccessful)
        case .turns: Self.count(row.turnsCounted)
        case .best2s: KeyMetrics.knots(row.best2sKn)
        case .best10s: KeyMetrics.knots(row.best10sKn)
        case .distance: Self.km(row.distanceKm)
        case .duration: KeyMetrics.duration(row.rateSeconds)
        case .dryStreak: Self.count(row.longestDryStreak)
        case .falls: Self.count(row.wetExits)
        }
    }

    // MARK: - The rider's three

    /// What the list draws until he says otherwise: how much of it he flew, how many jibes,
    /// how fast. The middle cell is the one the glyph always promised.
    public static let defaultTriple: [RowMetric] = [.foilShare, .jibes, .best2s]

    /// How many cells a row has. Three is what the width carries with a word under each.
    public static let slots = 3

    /// The stored form: three raw values, comma separated. A string rather than three keys
    /// so the choice is one value that round-trips as one.
    public static func stored(_ triple: [RowMetric]) -> String {
        triple.prefix(slots).map(\.rawValue).joined(separator: ",")
    }

    /// The stored form read back, padded and trimmed to three. Anything unreadable — no
    /// choice yet, a metric a later build dropped, a half-written value — falls back to the
    /// default in that slot rather than leaving the row a cell short.
    public static func triple(stored: String?) -> [RowMetric] {
        let parts = (stored ?? "").split(separator: ",").map(String.init)
        return (0..<slots).map { slot in
            guard slot < parts.count, let metric = RowMetric(rawValue: parts[slot]) else {
                return defaultTriple[slot]
            }
            return metric
        }
    }

    // MARK: - Formatting

    /// POSIX-stable, like `KeyMetrics`: the row and the session page print one string.
    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: abs(value) < 10 ? "%.1f %%" : "%.0f %%", value)
    }

    static func km(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f km", value)
    }

    static func count(_ value: Int?) -> String {
        guard let value else { return "—" }
        return String(value)
    }
}
