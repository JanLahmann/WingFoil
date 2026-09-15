import Foundation

/// Where a glossary term is allowed to be demanded.
///
/// The same mechanism `channels.json` uses for rows and `getting-started.json` uses for
/// routes: it says which checker may insist on this word. `wph` has no watch
/// implementation and `alpha500` is not a number the watch computes, so a watch scan that
/// demanded either would be demanding a metric that is not there.
public enum MetricSurface: String, Sendable, Equatable, CaseIterable {
    /// The iPhone app — the session page, the key-metrics block, the share card.
    case ios
    /// The Garmin watch app: a MIP cell, a recording page, the post-save summary.
    case watch
    /// cleanjibe.org and the browser analyzer.
    case web
    /// `ios/store/appstore.md`.
    case appstore
    /// `garmin/store/listing.md`.
    case ciq
}

/// One entry of the glossary: the metric's name, and the one line that says what it is.
///
/// **Six fields and a scope, because four surfaces and two stores read this row.** It used
/// to be `{ id, term, line }`, which is enough for two of them — the phone's welcome screen
/// and `web/learn`'s definition list. It is not enough for the watch, whose cell is about
/// seven characters wide, and it is not enough for the two store descriptions, which are
/// prose and will never print a label like "On foil": they print the clause *"how much of
/// it you spent on the foil"*, hand-copied into four files until now.
///
/// * `term` is **the label** — the iPhone card, the web tile, the `/learn` `<dt>`.
/// * `short` is the same word at the watch's width. The budget is a field rather than an
///   exemption, so an over-long watch label fails a test instead of failing a rider.
/// * `expansion` is what the phone and the web already append after " · ": `KeyMetrics`
///   built `"CPH · clean jibes per hour"` out of two halves that existed nowhere as data.
/// * `sentence` is the store voice's clause for the same thing.
/// * `surfaces` says who may demand the word.
public struct MetricGlossaryEntry: Sendable, Equatable, Identifiable {
    /// A slug that never changes, so the web can pin a row even when its wording moves.
    public let id: String
    /// What the rider sees on the session page and the web tile: "On foil", "CPH".
    public let term: String
    /// The same word at the watch's width — **at most seven characters** wherever
    /// `surfaces` contains `.watch`, which `CopyContractTests` asserts.
    public let short: String
    /// What follows the term after " · " where a rate is printed in full:
    /// "clean jibes per hour". Empty where the term is already the whole of it.
    public let expansion: String
    /// One sentence. The index line, not the reference page.
    public let line: String
    /// The clause the store prose uses instead of the label, in the store's own voice.
    public let sentence: String
    /// Which surfaces say this word at all.
    public let surfaces: [MetricSurface]

    public init(id: String, term: String, short: String, expansion: String = "",
                line: String, sentence: String, surfaces: [MetricSurface]) {
        self.id = id
        self.term = term
        self.short = short
        self.expansion = expansion
        self.line = line
        self.sentence = sentence
        self.surfaces = surfaces
    }

    /// `"CPH · clean jibes per hour"` — the label a rates row prints, built from the two
    /// halves rather than from a literal. The term alone where there is nothing to expand.
    public var labelled: String {
        expansion.isEmpty ? term : "\(term) · \(expansion)"
    }
}

/// **The eleven words the product is made of**, each in one line.
///
/// There were three copies of this glossary on 15 September 2026: `web/learn`'s definition
/// list, the welcome screen's four highlights, and the summaries of the matching `HelpCatalog`
/// topics. They had already drifted — the dry streak counted jibes "carried in a row" on the
/// phone and jibes you "stayed out of the water" on the web, and only one of those is a word
/// this product is allowed to use (CLAUDE.md). So the one-liners live here, once, and
/// `docs/copy/glossary.json` carries them to the website.
///
/// **Three entries were added on 15 September 2026**, each a label the app prints on every
/// session and no surface defined: `tph` (CLAUDE.md — *rates are additive: keep JPH and TPH
/// beside CPH* — the number was additive, the glossary was not), and `best5x10s` and
/// `alpha500`, printed on the phone, the web and the share card and explained on none.
///
/// **What is *not* here.** The long explanations — the 12 / 8 km/h foil gates, the 70 % score,
/// the outcome ladder — stay in `HelpCatalog`, which is a reference work behind a `?` and has
/// no equivalent on the site. These eleven are the index lines: enough to read a session page
/// with, short enough that nobody skips them.
public enum MetricGlossary {

    /// A record window's label, from the design tokens rather than retyped: `design/tokens.json`
    /// owns the eight window names, and the picker, the tiles and the share card all draw
    /// them from there. A glossary that spelled one of them itself would be a ninth copy.
    static func windowLabel(_ id: String) -> String {
        guard let found = DesignTokens.RecordWindows.catalogue.first(where: { $0.id == id })
        else { preconditionFailure("no record window \"" + id + "\"") }
        return found.label
    }

    public static let entries: [MetricGlossaryEntry] = [
        // **"On foil", not "Foil %"** (15 Sep 2026). The label table
        // (docs/presentation.md, "Label table") decided `On foil` for the share and
        // `Foil time` for the duration, and the session card, the trends row, the web tile
        // and the share card all print it. "Foil %" survived here alone — that is, in the
        // shared source, and therefore on the welcome screen, which is the one place a
        // stranger learns the word. It is also seven characters, which is the watch's cell.
        MetricGlossaryEntry(
            id: "foilShare",
            term: "On foil",
            short: "on foil",
            line: "How much of the session was spent flying rather than merely moving.",
            sentence: "how much of it you spent on the foil",
            surfaces: [.ios, .watch, .web, .appstore, .ciq]),

        MetricGlossaryEntry(
            id: "flights",
            term: "Flights & touchdowns",
            short: "flights",
            line: "One takeoff starts a flight. A touchdown or a swim ends it. "
                + "Both are counted.",
            sentence: "how long each flight lasted",
            surfaces: [.ios, .watch, .web, .appstore, .ciq]),

        // A list of **nouns**, so the middle one is a noun: `touchdown`, not "touched
        // down" (docs/presentation.md, "Label table"). The participle is right inside a
        // sentence — `WelcomeGuide.lede` and both store descriptions use it there, and so
        // does this row's own `sentence` — and wrong in a row of three labels.
        MetricGlossaryEntry(
            id: "turnVerdicts",
            term: "Turn verdicts",
            short: "verdict",
            line: "Every turn gets one: flew through, touchdown, or fell in.",
            sentence: "whether you flew through it, touched down, or fell in",
            surfaces: [.ios, .watch, .web, .appstore, .ciq]),

        MetricGlossaryEntry(
            id: "dryStreak",
            term: "Dry streak",
            short: "dry",
            line: "How many jibes in a row you stayed out of the water, and the best "
                + "run of the day.",
            sentence: "your longest run of jibes without falling in",
            surfaces: [.ios, .watch, .web, .appstore]),

        MetricGlossaryEntry(
            id: "jph",
            term: "JPH",
            short: "JPH",
            expansion: "dry jibes per hour",
            line: "Dry jibes per hour. Falling in more often cannot raise it.",
            sentence: "your dry jibes per hour",
            surfaces: [.ios, .web]),

        // The clean-jibe line, and the only place in the glossary the rule is stated. The
        // quiet tail is the third requirement (engine 0.17.0, docs/algorithms.md) and was
        // missing from the phone's own wording for three weeks.
        MetricGlossaryEntry(
            id: "cph",
            term: "CPH",
            short: "CPH",
            expansion: "clean jibes per hour",
            line: "Clean jibes per hour. Clean: flew through, held your speed, and "
                + "10 quiet seconds after.",
            sentence: "your clean jibes per hour",
            surfaces: [.ios, .watch, .web, .appstore, .ciq]),

        // **Beside JPH and CPH, never instead of them** (CLAUDE.md: rates are additive).
        // The phone and the web have printed "TPH · turns per hour" on every session whose
        // wind axis named no jibes since engine 0.7.0, and until 15 September 2026 neither
        // the welcome screen nor /learn could say what it was.
        MetricGlossaryEntry(
            id: "tph",
            term: "TPH",
            short: "TPH",
            expansion: "turns per hour",
            line: "Turns per hour, every counted turn and not only the jibes. It stands "
                + "in for JPH on a session whose wind axis named no jibes.",
            sentence: "your turns per hour",
            surfaces: [.ios, .web]),

        MetricGlossaryEntry(
            id: "wph",
            term: "WPH",
            short: "WPH",
            expansion: "swims per hour",
            line: "Swims per hour. The number nobody wants, kept honest anyway.",
            sentence: "your swims per hour",
            surfaces: [.ios, .web]),

        MetricGlossaryEntry(
            id: "speedRecords",
            term: "Speed records",
            short: "best",
            line: "Your fastest 2 seconds, 10 seconds, 500 m and nautical mile. The "
                + "speedsurfing world uses the same windows.",
            sentence: "your speed records",
            surfaces: [.ios, .watch, .web, .appstore, .ciq]),

        // The two windows the eight-line glossary named nowhere. Both are printed on the
        // phone's key-metrics block, on the web's tiles and on the share card; neither is
        // computed on the watch (docs/algorithms.md, "Speed records"), so neither is
        // demanded of it.
        MetricGlossaryEntry(
            id: "best5x10s",
            term: windowLabel("best5x10s"),
            short: "5×10 s",
            line: "The mean of your best five separate 10-second runs. They may not "
                + "overlap, so one lucky reach cannot carry it.",
            sentence: "your best five ten-second runs",
            surfaces: [.ios, .web]),

        MetricGlossaryEntry(
            id: "alpha500",
            term: windowLabel("alpha500"),
            short: "alpha",
            line: "Your fastest 500 m that ends within 50 m of where it started. It "
                + "contains a jibe, so it measures the turn as well as the speed.",
            sentence: "your fastest 500 m that comes back to where it started",
            surfaces: [.ios, .web]),
    ]

    /// One entry by id. Traps on a misspelling rather than returning a silent nil: every
    /// caller is a literal in this repository, and a glossary line that quietly vanishes
    /// from a screen is exactly the bug this type exists to stop.
    public static func entry(_ id: String) -> MetricGlossaryEntry {
        guard let found = entries.first(where: { $0.id == id }) else {
            preconditionFailure("no glossary entry \"" + id + "\"")
        }
        return found
    }
}
