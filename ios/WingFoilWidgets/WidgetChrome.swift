import SwiftUI

/// The brand palette again — the extension is a separate target and cannot see the app's
/// `Brand`, and a widget is small enough that duplicating five colours beats adding a
/// shared file for them.
enum WidgetPalette {
    static let navy = Color(red: 0.039, green: 0.118, blue: 0.188)
    static let green = Color(red: 0.180, green: 0.902, blue: 0.659)
    static let paper = Color(red: 0.957, green: 0.980, blue: 1.000)

    static let background = LinearGradient(
        colors: [Color(red: 0.047, green: 0.157, blue: 0.243), navy],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// **The formatting rules the widget needs, copied — with the kit rule each one mirrors.**
///
/// The extension deliberately does not link `WingFoilKit` (ADR-011), so it cannot call
/// `Fmt` or `KeyMetrics`. That is a good trade for a process that decodes a few hundred
/// bytes of JSON, and a bad one for a rider who reads `47%` on his home screen and `47 %`
/// on the session page a tap later — so every rule below is the kit's, spelled out, named,
/// and pinned by the doc comment to the function it must not drift from
/// (docs/presentation/labels.md, "Label table" and "Formatter rules").
enum WidgetFormat {

    /// A share, under the one percent rule — one decimal below 10 %, none at or above it,
    /// always a space before the sign. Mirrors `Fmt.pct` / `PeriodBlock.percent`.
    static func pct(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: abs(value) < 10 ? "%.1f %%" : "%.0f %%", value)
    }

    /// Mirrors `SpeedUnit` in WingFoilKit. The extension links none of the kit, so the two
    /// words are spelled here and the *choice* travels in the snapshot
    /// (`WidgetSnapshot.speedUnit`, Settings → Units).
    enum SpeedUnit: String {
        case knots
        case kmh

        var suffix: String {
            switch self {
            case .knots: "kn"
            case .kmh: "km/h"
            }
        }

        /// Mirrors `SpeedUnit.kmhPerKnot`.
        var perKnot: Double { self == .kmh ? 1.852 : 1 }
    }

    /// What this render is printing speeds in. Set from the entry's snapshot before a view
    /// draws (`SnapshotSource`); knots for a blob written before the setting existed, which
    /// is what that blob meant.
    nonisolated(unsafe) static var speedUnit: SpeedUnit = .knots

    /// A speed, two decimals, **in the rider's unit** — the snapshot carries knots and this
    /// converts on the way to the glass, exactly as `Speed.format` does in the app. Mirrors
    /// `KeyMetrics.knots` (`13.47 kn` · `24.94 km/h`).
    ///
    /// **Every rider-facing caller passes `unit: true` since 21 September 2026.** The tiles
    /// used to print a bare `13.47` on the argument that "BEST 2 S" carried the unit — it
    /// never did, and once the same tile can also read `24.94` a number with no word after
    /// it is a number nobody can check. The value line already scales itself down to fit
    /// (`WidgetStat`), so the word costs a point of type and no truncation.
    static func knots(_ value: Double?, unit: Bool = false) -> String {
        guard let value else { return "—" }
        let converted = value * speedUnit.perKnot
        return unit ? String(format: "%.2f %@", converted, speedUnit.suffix)
                    : String(format: "%.2f", converted)
    }

    /// A per-hour rate, one decimal. Mirrors `KeyMetrics.rate` — the JPH, TPH, CPH and WPH
    /// spelling on the key-metrics block.
    static func rate(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f", value)
    }

    /// A session or flight clock: `1:57 h` past an hour, `10:45 min` under one. Mirrors
    /// `KeyMetrics.duration`, which is the platform's one session-duration formatter.
    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total >= 3600 {
            let minutes = Int((Double(total) / 60).rounded())
            return String(format: "%d:%02d h", minutes / 60, minutes % 60)
        }
        return String(format: "%d:%02d min", total / 60, total % 60)
    }

    /// Hours out, one decimal — the period block's `hours on the water` spelling.
    static func hours(_ value: Double) -> String { String(format: "%.1f h", value) }

    /// Minutes on the foil as a duration: `47 m`, then `3 h 34 m`. Mirrors `Fmt.duration`'s
    /// h/m form, which is what the app prints for a *foil time*.
    static func foilTime(_ minutes: Double) -> String {
        let total = max(0, Int(minutes.rounded()))
        if total < 60 { return "\(total) m" }
        return "\(total / 60) h \(total % 60) m"
    }

    /// "14 Sep", and "14 Sep 2024" once the year is not the one the widget is drawn in.
    ///
    /// Mirrors `Fmt.shortDate` (`30 Aug 2026`), minus the year where it is this year's —
    /// a widget has one line and the year on it is noise eleven months of twelve. **The
    /// reader's own zone**, deliberately: the snapshot carries no session offsets, and a
    /// date on a home screen is a date on the reader's calendar.
    static func shortDate(_ date: Date, relativeTo today: Date = Date()) -> String {
        let calendar = Calendar.current
        var style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        if calendar.component(.year, from: date) != calendar.component(.year, from: today) {
            style = style.year()
        }
        return date.formatted(style)
    }

    /// "A year ago this week", "Two years ago this week" — words up to five, digits past it.
    static func yearsAgo(_ years: Int) -> String {
        let words = [1: "A year", 2: "Two years", 3: "Three years", 4: "Four years",
                     5: "Five years"]
        return (words[years] ?? "\(years) years") + " ago this week"
    }

    /// "12 days", "1 day", "today".
    static func days(_ count: Int) -> String {
        switch count {
        case 0: "today"
        case 1: "1 day"
        default: "\(count) days"
        }
    }
}

/// The session's track, stroked as one thin line.
///
/// The vertices arrive already normalized into a unit square with the aspect preserved
/// (`WidgetSnapshot.Track`), so there is no projection here and there must not be: the
/// outline has to be the same shape the list row, the map and the share card draw, and a
/// second projection is a second shape. All this does is fit the box the track actually
/// occupies into the rect it is given.
struct TrackOutline: Shape {
    let track: WidgetSnapshot.Track

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !track.isEmpty else { return path }
        // One scale for both axes — the aspect is already right, and stretching it to the
        // widget's rectangle would draw a different afternoon.
        let scale = min(rect.width / track.boxWidth, rect.height / track.boxHeight)
        let originX = rect.midX - track.boxWidth * scale / 2
        let originY = rect.midY - track.boxHeight * scale / 2
        for index in 0..<track.count {
            let point = track.point(index)
            let placed = CGPoint(x: originX + (point.x - track.minX) * scale,
                                 y: originY + (point.y - track.minY) * scale)
            if index == 0 { path.move(to: placed) } else { path.addLine(to: placed) }
        }
        return path
    }
}

/// One label-over-number tile, the shape every widget here puts its numbers in.
struct WidgetStat: View {
    let label: String
    let value: String
    var big = false
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(WidgetPalette.green)
            Text(value)
                .font(.system(size: big ? 22 : 16, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetPalette.paper)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.system(size: 8))
                    .foregroundStyle(WidgetPalette.paper.opacity(0.55))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Empty either because there is nothing yet, or because the shared container is not
/// reachable. The second case is a setup fact and is worth saying out loud.
struct EmptyStateView: View {
    let unreachable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "water.waves")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(WidgetPalette.green)
            Text(unreachable ? "Open CleanJibe to finish setting up the widget."
                             : "No sessions yet.")
                .font(.system(size: 11))
                .foregroundStyle(WidgetPalette.paper.opacity(0.75))
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
