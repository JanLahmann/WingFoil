import Foundation

/// **What VoiceOver says for a figure the screen draws as colour and number** (release
/// round C, 25 Sep 2026).
///
/// A tally drawn "42 · 3 · 5" in the ladder's three inks is three bare numbers to a reader
/// who hears it, so every count is spoken with its word — "42 flew through, 3 touchdowns,
/// 5 fell in" — in the rider's vocabulary, never the engine's ("carried", "success").
/// A chart is one sentence: what it is, how many points, the latest value and the range,
/// instead of a mark-by-mark walk through sixty dates.
///
/// Spoken text only. Nothing here reaches a label the rider reads on screen, and the
/// visible wording stays where it is (docs/voice.md).
public enum SpokenFigures {

    /// "1 touchdown", "3 touchdowns". The words that do not inflect ("flew through",
    /// "fell in") pass the same word twice.
    public static func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        String(n) + " " + (n == 1 ? singular : plural)
    }

    /// The outcome ladder, each number with its word: "42 flew through, 3 touchdowns,
    /// 5 fell in".
    public static func tally(flewThrough: Int, touchdown: Int, fellIn: Int) -> String {
        [count(flewThrough, "flew through", "flew through"),
         count(touchdown, "touchdown", "touchdowns"),
         count(fellIn, "fell in", "fell in")].joined(separator: ", ")
    }

    /// One turn pin on a map: "Jibe at 14:03, flew through, clean".
    public static func turnPin(type: String, clock: String, outcome: TurnOutcomeKind,
                               clean: Bool) -> String {
        var parts = [type + " at " + clock, outcome.label]
        if clean { parts.append("clean") }
        return parts.joined(separator: ", ")
    }

    /// A trend chart as one sentence: "On foil, 12 sessions, latest 64 %, lowest 40 %,
    /// highest 72 %". `format` prints a value with its unit, the way the chart's header does.
    /// An empty series says so rather than reading nothing.
    public static func series(title: String, values: [Double],
                              format: (Double) -> String) -> String {
        guard let last = values.last, let low = values.min(), let high = values.max() else {
            return title + ", no sessions in this range"
        }
        var parts = [title, count(values.count, "session", "sessions"), "latest " + format(last)]
        if values.count > 1 {
            parts.append("lowest " + format(low))
            parts.append("highest " + format(high))
        }
        return parts.joined(separator: ", ")
    }
}
