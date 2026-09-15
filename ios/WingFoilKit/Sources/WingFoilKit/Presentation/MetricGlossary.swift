import Foundation

/// One entry of the glossary: the metric's name, and the one line that says what it is.
///
/// The same shape as `WelcomeHighlight` — a term and a sentence — with a stable `id` on it,
/// because this list is read by name from `docs/copy/glossary.json` and the terms themselves
/// are allowed to be reworded.
public struct MetricGlossaryEntry: Sendable, Equatable, Identifiable {
    /// A slug that never changes, so the web can pin a row even when its wording moves.
    public let id: String
    /// What the rider sees on the session page: "Foil %", "CPH".
    public let term: String
    /// One sentence. The index line, not the reference page.
    public let line: String

    public init(id: String, term: String, line: String) {
        self.id = id
        self.term = term
        self.line = line
    }
}

/// **The eight words the product is made of**, each in one line.
///
/// There were three copies of this glossary on 15 September 2026: `web/learn`'s definition
/// list, the welcome screen's four highlights, and the summaries of the matching `HelpCatalog`
/// topics. They had already drifted — the dry streak counted jibes "carried in a row" on the
/// phone and jibes you "stayed out of the water" on the web, and only one of those is a word
/// this product is allowed to use (CLAUDE.md). So the one-liners live here, once, and
/// `docs/copy/glossary.json` carries them to the website.
///
/// **What is *not* here.** The long explanations — the 12 / 8 km/h foil gates, the 70 % score,
/// the outcome ladder — stay in `HelpCatalog`, which is a reference work behind a `?` and has
/// no equivalent on the site. These eight are the index lines: enough to read a session page
/// with, short enough that nobody skips them.
public enum MetricGlossary {

    public static let entries: [MetricGlossaryEntry] = [
        MetricGlossaryEntry(
            id: "foilShare",
            term: "Foil %",
            line: "How much of the session was spent flying rather than merely moving."),

        MetricGlossaryEntry(
            id: "flights",
            term: "Flights & touchdowns",
            line: "One takeoff starts a flight; a touchdown or a swim ends it. "
                + "Both are counted."),

        MetricGlossaryEntry(
            id: "turnVerdicts",
            term: "Turn verdicts",
            line: "Every turn gets one: flew through, touched down, or fell in."),

        MetricGlossaryEntry(
            id: "dryStreak",
            term: "Dry streak",
            line: "How many jibes in a row you stayed out of the water — and the best run "
                + "of the day."),

        MetricGlossaryEntry(
            id: "jph",
            term: "JPH",
            line: "Dry jibes per hour. Falling in more often cannot raise it."),

        // The clean-jibe line, and the only place in the glossary the rule is stated. The
        // quiet tail is the third requirement (engine 0.17.0, docs/algorithms.md) and was
        // missing from the phone's own wording for three weeks.
        MetricGlossaryEntry(
            id: "cph",
            term: "CPH",
            line: "Clean jibes per hour: you flew through it, you held your speed, and the "
                + "ten seconds after it stayed quiet."),

        MetricGlossaryEntry(
            id: "wph",
            term: "WPH",
            line: "Swims per hour. The number nobody wants, kept honest anyway."),

        MetricGlossaryEntry(
            id: "speedRecords",
            term: "Speed records",
            line: "Your fastest 2 seconds, 10 seconds, 500 m and nautical mile — the same "
                + "windows the speedsurfing world uses."),
    ]

    /// One entry by id. Traps on a misspelling rather than returning a silent nil: every
    /// caller is a literal in this repository, and a glossary line that quietly vanishes
    /// from a screen is exactly the bug this type exists to stop.
    public static func entry(_ id: String) -> MetricGlossaryEntry {
        guard let found = entries.first(where: { $0.id == id }) else {
            preconditionFailure("no glossary entry \"\(id)\"")
        }
        return found
    }
}
