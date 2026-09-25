import Foundation

/// **Words on a small figure that must not print over each other.**
///
/// Two rules, both about labels that live on one axis of a chart a few hundred points wide:
///
/// * `rows` — captions along the top edge of a strip ("in 12.4", "low 6.1", "out 5.7",
///   "axis"). A caption that would land within `gap` of one already placed on its row steps
///   up to the next row, never down: the bottom edge belongs to the time axis' own numbers,
///   and "out 5.7" dropped there printed straight through the "5" of *5 s* (Jan, 25 Sep 2026).
/// * `thinned` — tick values on an axis, given most important first. A tick that would
///   land within `gap` of one already kept is left out, so "18 · 5 · 0 · −5 · −18" on a
///   rate axis spanning ±60 becomes "18 · 0 · −18" rather than a smear.
///
/// Both are greedy and in the order given, which is the point: the caller says what matters
/// most by where it puts it.
public enum LabelSpacing {

    /// The row each caption goes on, 0 being the one nearest the plot.
    ///
    /// - Parameters:
    ///   - positions: where each caption is centred, in the axis' own units, in the order
    ///     they are placed.
    ///   - gap: how close two captions on one row may be, in the same units.
    public static func rows(_ positions: [Double], gap: Double) -> [Int] {
        var placed: [[Double]] = []
        return positions.map { x in
            var row = 0
            while row < placed.count, placed[row].contains(where: { abs($0 - x) < gap }) {
                row += 1
            }
            if row == placed.count { placed.append([]) }
            placed[row].append(x)
            return row
        }
    }

    /// The ticks that fit, in the order given, each at least `gap` from every one kept
    /// before it.
    public static func thinned(_ ticks: [Double], gap: Double) -> [Double] {
        var kept: [Double] = []
        for tick in ticks where !kept.contains(where: { abs($0 - tick) < gap }) {
            kept.append(tick)
        }
        return kept
    }
}
