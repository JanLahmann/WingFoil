import Foundation

/// Where the time axis of a session chart puts its labels.
///
/// Swift Charts' `.automatic(desiredCount:)` divides the domain into *n* equal parts and
/// labels the cuts, which on a session clock produces the axis `app-ui-review.md` §1.5
/// measured: `0:00 · 33:20 · 66:40 · 100:00` — 2000-second intervals, arithmetically
/// correct and unreadable. Nobody thinks in 33 minutes 20 seconds. The web's speed strip
/// already did the right thing (`0 10 20 30 40 50 60 70 80` minutes) and this is that rule,
/// written once so the speed chart and the HR-cost chart cannot drift apart.
///
/// **The rule.** Pick the smallest step from a ladder of units a rider would actually name
/// — 5/10/15/30 s, 1/2/5/10/15/30 min, 1/2/3/6 h — that yields no more than the requested
/// number of labels, then label its multiples inside the window. The labels are therefore
/// *round times*, and they stay round as the chart is pinched: zooming changes which rung
/// of the ladder is in use, never the roundness of what is written on it.
///
/// Two consequences worth stating, because both are deliberate:
///
/// * **The domain's own ends are not labelled.** A window from 7:13 to 41:02 gets
///   `10:00 · 20:00 · 30:00 · 40:00`, not its own edges. An axis exists to let the eye
///   convert a position into a time, and a tick at 7:13 helps with that far less than one
///   at 10:00 — the window's extent is what the zoom's own range bar is for.
/// * **A window containing no round time at all falls back to its own ends.** Zoomed past
///   the finest rung — a two-second window between two five-second marks — the ladder has
///   nothing to offer, and an axis with no labels is worse than one labelled with the two
///   times it spans. A window containing exactly *one* round time keeps that one label
///   rather than taking the fallback: one round number beats two ragged ones.
public enum TimeAxisTicks {

    /// The ladder, in seconds. Every rung divides the one above it or is a unit a clock
    /// face names, which is what stops a step like 45 s or 20 min — both arithmetically
    /// fine and both read as arbitrary next to their neighbours.
    public static let steps: [Double] = [
        5, 10, 15, 30,                                    // seconds
        60, 2 * 60, 5 * 60, 10 * 60, 15 * 60, 30 * 60,    // minutes
        3600, 2 * 3600, 3 * 3600, 6 * 3600,               // hours
    ]

    /// Label positions for `range`, at most `desiredCount` of them.
    ///
    /// - Parameters:
    ///   - range: the visible window, in session-clock seconds. An empty or reversed range
    ///     yields no ticks rather than a division by zero.
    ///   - desiredCount: the most labels the axis has room for. Values below 2 are treated
    ///     as 2 — one label is not an axis.
    public static func values(for range: ClosedRange<Double>, desiredCount: Int = 5) -> [Double] {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return [] }
        let wanted = max(2, desiredCount)

        guard let step = steps.first(where: { span / $0 <= Double(wanted - 1) }) else {
            // Longer than the coarsest rung (a > 24 h recording): fall back to whole hours
            // scaled up, which keeps the labels on the hour rather than on nothing.
            let hours = (span / (Double(wanted - 1) * 3600)).rounded(.up)
            return multiples(of: max(1, hours) * 3600, in: range)
        }
        // A window zoomed in between two 5 s marks contains no round time at all; only
        // then does the axis fall back to labelling its own edges.
        let ticks = multiples(of: step, in: range)
        return ticks.isEmpty ? [range.lowerBound, range.upperBound] : ticks
    }

    /// Every multiple of `step` that lies inside the range, inclusive of both ends.
    static func multiples(of step: Double, in range: ClosedRange<Double>) -> [Double] {
        guard step > 0 else { return [] }
        let first = (range.lowerBound / step).rounded(.up)
        let last = (range.upperBound / step).rounded(.down)
        guard last >= first else { return [] }
        // A long session at a fine step is a bug in the caller, not a reason to build a
        // hundred thousand doubles: the ladder above cannot produce one, and this is the
        // guard that says so out loud if anything ever calls `multiples` directly.
        guard last - first < 1000 else { return [] }
        return stride(from: first, through: last, by: 1).map { $0 * step }
    }
}
