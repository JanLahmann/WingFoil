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

/// **Where a term actually shows**, concretely enough that a rider comparing two screens
/// can be pointed at both.
///
/// `MetricSurface` says which checker may *demand* the word. This says where the word is
/// printed, which is the question the 20 September 2026 round was opened by: a tester read
/// "turn success 29 %" in Garmin Connect, "93 % flew through" on the website and
/// "success 44 %" on the phone, and had no way to learn that those are three different
/// measurements. A term that names its places answers that in one line.
public enum MetricPlace: String, Sendable, Equatable, CaseIterable {
    /// A label on a watch page (`garmin/source/ui`, a MIP cell — see `short`).
    case watchPage
    /// A FIT developer field. `MetricGlossaryEntry.fit` names which (docs/fit-schema.md).
    case fitField
    /// The row Garmin Connect lists under *Connect IQ* on the activity page
    /// (`garmin/resources/fitcontributions/fit_contributions.xml`).
    case connectField
    /// A cell of a library row (`RowMetric`).
    case phoneRow
    /// The session page — the key-metrics block or one of the stat cards.
    case phonePage
    /// The share card (`ShareCardStats`).
    case card
    /// cleanjibe.org and the browser app.
    case web
    /// The help catalogue, in the app and on /help/.
    case help

    /// The rider's name for the place, for the one line the help topic prints.
    public var word: String {
        switch self {
        case .watchPage: "the watch"
        case .fitField: "the FIT"
        case .connectField: "Garmin Connect"
        case .phoneRow: "the library row"
        case .phonePage: "the session page"
        case .card: "the share card"
        case .web: "the website"
        case .help: "this page"
        }
    }
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
    /// **Where it shows**, concretely. Read by `docs/copy/glossary.json` and by the help
    /// topic *What the numbers mean*, so a rider comparing two screens is told which
    /// screens print this word.
    public let places: [MetricPlace]
    /// **Every spelling a surface is allowed to print for this term**, the term itself
    /// included — the row says `foil`, the tile says `On foil`, and both are this word.
    ///
    /// It is what `GlossaryLintTests` checks a rider-facing label against. A label that is
    /// not here and not a pure unit or date is a metric with a second name, which is the
    /// defect this whole file exists to stop (docs/review-checklist.md, pattern L).
    public let labels: [String]
    /// The FIT developer field this term is written into, or `""`. Names the field, not
    /// the id: docs/fit-schema.md owns the ids.
    public let fit: String

    public init(id: String, term: String, short: String, expansion: String = "",
                line: String, sentence: String, surfaces: [MetricSurface],
                places: [MetricPlace] = [], labels: [String] = [], fit: String = "") {
        self.id = id
        self.term = term
        self.short = short
        self.expansion = expansion
        self.line = line
        self.sentence = sentence
        self.surfaces = surfaces
        self.places = places
        self.labels = labels.isEmpty ? [term] : labels
        self.fit = fit
    }

    /// `"CPH · clean jibes per hour"` — the label a rates row prints, built from the two
    /// halves rather than from a literal. The term alone where there is nothing to expand.
    public var labelled: String {
        expansion.isEmpty ? term : "\(term) · \(expansion)"
    }
}

/// **The nineteen words the product is made of**, each in one line.
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
/// no equivalent on the site. These nineteen are the index lines: enough to read a session page
/// with, short enough that nobody skips them.
///
/// **Eight were added on 20 September 2026** — the verdict words. The reason is under the
/// MARK at the end of the list: three surfaces printed three different numbers about one
/// rider's turns, and not one of them named the measurement it was.
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
        // (docs/presentation/labels.md, "Label table") decided `On foil` for the share and
        // `Foil time` for the duration, and the session card, the trends row, the web tile
        // and the share card all print it. "Foil %" survived here alone — that is, in the
        // shared source, and therefore on the welcome screen, which is the one place a
        // stranger learns the word. It is also seven characters, which is the watch's cell.
        MetricGlossaryEntry(
            id: "foilShare",
            term: "On foil",
            short: "on foil",
            line: "How much of your session you spent flying rather than just moving.",
            sentence: "how much of it you spent on the foil",
            surfaces: [.ios, .watch, .web, .appstore, .ciq],
            places: [.watchPage, .fitField, .connectField, .phoneRow, .phonePage,
                     .card, .web, .help],
            labels: ["On foil", "foil", "Foil time", "foil time"],
            fit: "foil_pct"),

        MetricGlossaryEntry(
            id: "flights",
            term: "Flights & touchdowns",
            short: "flights",
            line: "One takeoff starts a flight. A touchdown or a fall ends it. "
                + "Both are counted.",
            sentence: "how long each flight lasted",
            surfaces: [.ios, .watch, .web, .appstore, .ciq],
            places: [.watchPage, .fitField, .connectField, .phoneRow, .phonePage,
                     .web, .help],
            labels: ["Flights & touchdowns", "Flights", "flights", "Longest flight",
                     "longest flight"],
            fit: "flight_count"),

        // A list of **nouns**, so the middle one is a noun: `touchdown`, not "touched
        // down" (docs/presentation/labels.md, "Label table"). The participle is right inside a
        // sentence — `WelcomeGuide.lede` and both store descriptions use it there, and so
        // does this row's own `sentence` — and wrong in a row of three labels.
        MetricGlossaryEntry(
            id: "turnVerdicts",
            term: "Turn verdicts",
            short: "verdict",
            line: "Every turn gets one: flew through, touchdown, or fell in.",
            sentence: "whether you flew through it, touched down, or fell in",
            surfaces: [.ios, .watch, .web, .appstore, .ciq],
            places: [.watchPage, .fitField, .phonePage, .card, .web, .help],
            labels: ["Turn verdicts", "flew · touchdown · fell"],
            fit: "turn_marker"),

        MetricGlossaryEntry(
            id: "dryStreak",
            term: "Dry streak",
            short: "dry",
            line: "How many jibes in a row you stayed out of the water, and the best "
                + "run of the day.",
            sentence: "your longest run of jibes without falling in",
            surfaces: [.ios, .watch, .web, .appstore],
            places: [.watchPage, .phoneRow, .phonePage, .card, .web, .help],
            labels: ["Dry streak", "dry streak", "best streaks"]),

        MetricGlossaryEntry(
            id: "jph",
            term: "JPH",
            short: "JPH",
            expansion: "dry jibes per hour",
            line: "Dry jibes per hour. Falling in more often cannot raise it.",
            sentence: "your dry jibes per hour",
            surfaces: [.ios, .web],
            places: [.phonePage, .card, .web, .help],
            labels: ["JPH", "JPH · dry jibes per hour"]),

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
            surfaces: [.ios, .watch, .web, .appstore, .ciq],
            places: [.watchPage, .phonePage, .card, .web, .help],
            labels: ["CPH", "CPH · clean jibes per hour"]),

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
            surfaces: [.ios, .web],
            places: [.phonePage, .card, .web, .help],
            labels: ["TPH", "TPH · turns per hour"]),

        MetricGlossaryEntry(
            id: "wph",
            term: "WPH",
            short: "WPH",
            expansion: "swims per hour",
            line: "Swims per hour. Nobody wants it high, and it counts every fall.",
            sentence: "your swims per hour",
            surfaces: [.ios, .web],
            places: [.phonePage, .card, .web, .help],
            labels: ["WPH", "WPH · swims per hour"]),

        MetricGlossaryEntry(
            id: "speedRecords",
            term: "Speed records",
            short: "best",
            line: "Your fastest 2 seconds, 10 seconds, 500 m and nautical mile. The "
                + "speedsurfing world uses the same windows.",
            sentence: "your speed records",
            surfaces: [.ios, .watch, .web, .appstore, .ciq],
            places: [.watchPage, .fitField, .connectField, .phoneRow, .phonePage,
                     .card, .web, .help],
            labels: ["Speed records", "max 2 s", "avg speed",
                     windowLabel("best2s"), windowLabel("best10s"),
                     windowLabel("best100m"), windowLabel("best250m"),
                     windowLabel("best500m"), windowLabel("bestNm"),
                     "best 2 s", "best 10 s", "best 100 m", "best 250 m", "best 500 m",
                     "best 1 NM"],
            fit: "best_2s"),

        // The two windows the eight-line glossary named nowhere. Both are printed on the
        // phone's key-metrics block, on the web's tiles and on the share card; neither is
        // computed on the watch (docs/algorithms/records.md, "Speed records"), so neither is
        // demanded of it.
        MetricGlossaryEntry(
            id: "best5x10s",
            term: windowLabel("best5x10s"),
            short: "5×10 s",
            line: "The mean of your best five separate 10-second runs. They may not "
                + "overlap, so one lucky reach cannot carry it.",
            sentence: "your best five ten-second runs",
            surfaces: [.ios, .web],
            places: [.phonePage, .web, .help],
            labels: [windowLabel("best5x10s"), "5×10 s"]),

        MetricGlossaryEntry(
            id: "alpha500",
            term: windowLabel("alpha500"),
            short: "alpha",
            line: "Your fastest 500 m that ends within 50 m of where it started. It "
                + "contains a jibe, so it measures the turn as well as the speed.",
            sentence: "your fastest 500 m that comes back to where it started",
            surfaces: [.ios, .web],
            places: [.phonePage, .web, .help],
            labels: [windowLabel("alpha500"), "alpha 500"]),

        // MARK: - The verdict words (20 September 2026)
        //
        // **Why eight more.** A tester read three numbers about the same afternoon's turns:
        // Garmin Connect said *Turn success 29 %*, the website said *93 % flew through*,
        // the phone said *44 %*. All three were correct and all three measured something
        // else, and no surface said which. The four words docs/algorithms.md already keeps
        // apart — flew through, the score verdict, clean, dry — had no row of their own
        // here, so the two that collided could not be told apart by a reader and could not
        // be linted apart by a test.
        //
        // The score verdict is **"Speed kept"** on every rider surface. It may not be
        // called "success" or "carried" (CLAUDE.md), and *turn success* was both of those
        // at once: the engine's word, printed in Garmin Connect, beside a phone that used
        // "success" for a different measurement again — how often he got up.

        MetricGlossaryEntry(
            id: "flewThrough",
            term: "Flew through",
            short: "flew",
            line: "The turn kept the foil, from the sweep until you were flying again.",
            sentence: "whether you flew through it",
            surfaces: [.ios, .watch, .web],
            places: [.watchPage, .fitField, .phonePage, .card, .web, .help],
            labels: ["Flew through", "flew through", "flew"],
            fit: "turn_marker"),

        MetricGlossaryEntry(
            id: "clean",
            term: "Clean",
            short: "clean",
            line: "A jibe that flew through, held 70 % of its entry speed, and stayed "
                + "quiet for 10 s.",
            sentence: "which of your jibes were clean",
            surfaces: [.ios, .watch, .web],
            places: [.watchPage, .fitField, .phoneRow, .phonePage, .card, .web, .help],
            labels: ["Clean", "clean", "Clean jibes", "clean jibes"],
            fit: "clean_jibes"),

        // **The one the watch calls "turn success" today.** A speed verdict over every
        // counted turn. Not the outcome, and not the takeoff rate the phone called a
        // success rate until this round. docs/fit-schema.md field 34 carries the label
        // change this term asks of the watch.
        MetricGlossaryEntry(
            id: "speedKept",
            term: "Speed kept",
            short: "speed",
            line: "The share of counted turns that held 70 % of their entry speed and "
                + "never dropped off the foil.",
            sentence: "how many of your turns held their speed",
            surfaces: [.ios, .watch, .web],
            places: [.watchPage, .fitField, .connectField, .help],
            labels: ["Speed kept", "speed kept"],
            fit: "turn_success_pct"),

        MetricGlossaryEntry(
            id: "dry",
            term: "Dry",
            short: "dry",
            line: "You did not fall in. A touchdown still counts as dry.",
            sentence: "the jibes you did not swim out of",
            surfaces: [.ios, .web],
            places: [.phonePage, .web, .help],
            labels: ["Dry", "dry"]),

        MetricGlossaryEntry(
            id: "touchdown",
            term: "Touchdown",
            short: "touch",
            line: "The foil went in and you kept going. Dry, and not clean.",
            sentence: "where you touched down",
            surfaces: [.ios, .watch, .web],
            places: [.watchPage, .fitField, .phonePage, .card, .web, .help],
            labels: ["Touchdown", "touchdown", "Touchdowns", "touchdowns"],
            fit: "turn_marker"),

        // **Every fall, not every fallen jibe.** The row, the card and the session page
        // print this number, and two of them printed the turn ladder's falls until
        // 20 September 2026, which leaves out every swim in a straight line. A tester fell
        // three times and read a 0 (docs/algorithms/rates.md, "Wet is every fall, not every
        // fallen jibe").
        MetricGlossaryEntry(
            id: "fellIn",
            term: "Fell in",
            short: "fell in",
            line: "Every time you ended up in the water, in a turn or in a straight line.",
            sentence: "every time you fell in",
            surfaces: [.ios, .watch, .web],
            places: [.watchPage, .fitField, .phoneRow, .phonePage, .card, .web, .help],
            labels: ["Fell in", "fell in", "fell", "Falls", "falls"],
            fit: "turn_marker"),

        MetricGlossaryEntry(
            id: "takeoffs",
            term: "Takeoffs",
            short: "up",
            line: "How many times you got up on the foil. One takeoff starts every flight.",
            sentence: "how often you got up",
            surfaces: [.ios, .watch, .web],
            places: [.watchPage, .fitField, .phonePage, .web, .help],
            labels: ["Takeoffs", "takeoffs", "Got up", "got up", "Planing starts"],
            fit: "takeoff_pack"),

        // Beside `takeoffs`, never instead of it. The watch counted 15 tries on the
        // afternoon the phone counted 9 flights, and a surface that names one of the two
        // numbers reads as a contradiction of the other.
        MetricGlossaryEntry(
            id: "takeoffAttempts",
            term: "Attempts",
            short: "tries",
            line: "Every pumping burst, whether you got up or not. Attempts are takeoffs "
                + "plus failed attempts.",
            sentence: "how often you pumped, including the times you did not get up",
            surfaces: [.ios, .watch, .web],
            places: [.watchPage, .fitField, .phonePage, .web, .help],
            labels: ["Attempts", "attempts", "Takeoff attempts", "Failed attempts",
                     "failed attempts"],
            fit: "takeoff_pack"),
    ]

    /// **Every spelling any surface may print, lowercased.** `GlossaryLintTests`' ground
    /// truth: a rider-facing metric label that is not in here is a metric with a second
    /// name (docs/review-checklist.md, pattern L).
    public static var allLabels: Set<String> {
        Set(entries.flatMap { entry in
            (entry.labels + [entry.term, entry.labelled]).map {
                $0.lowercased().trimmingCharacters(in: .whitespaces)
            }
        })
    }

    /// The entry a label belongs to, or nil where no term claims it.
    public static func entry(forLabel label: String) -> MetricGlossaryEntry? {
        let want = label.lowercased().trimmingCharacters(in: .whitespaces)
        return entries.first { entry in
            (entry.labels + [entry.term, entry.labelled])
                .contains { $0.lowercased().trimmingCharacters(in: .whitespaces) == want }
        }
    }

    /// **The other surface a rider might be holding**, in four words, for the help item.
    ///
    /// Not the whole of `places`: the phone, the card and the site are where he is reading
    /// this, and a definition list that repeats them nineteen times says nothing and costs
    /// a help item its word budget. What is worth saying is the surface that is *not* in
    /// his hand — the watch, and the row Garmin Connect prints, which is where the three
    /// numbers of 20 September 2026 disagreed. `places` keeps the full list for
    /// `docs/copy/glossary.json`, and the site renders it there.
    public static func alsoOn(_ entry: MetricGlossaryEntry) -> String {
        let watch = entry.places.contains(.watchPage) || entry.places.contains(.fitField)
        let connect = entry.places.contains(.connectField)
        switch (watch, connect) {
        case (true, true): return "Also on the watch and in Garmin Connect."
        case (true, false): return "Also on the watch."
        case (false, true): return "Also in Garmin Connect."
        case (false, false): return ""
        }
    }

    /// **"Where it shows"**, as the full line — `docs/copy/glossary.json`'s `places`
    /// rendered for a doc or a report. Built from `places` rather than typed, so a term
    /// that reaches a new screen says so on every surface at once.
    public static func places(_ entry: MetricGlossaryEntry) -> String {
        var words = entry.places.map(\.word)
        if !entry.fit.isEmpty, entry.places.contains(.fitField) {
            words = words.map {
                $0 == MetricPlace.fitField.word ? "the FIT field " + entry.fit : $0
            }
        }
        guard !words.isEmpty else { return "" }
        if words.count == 1 { return words[0] + "." }
        return words.dropLast().joined(separator: ", ") + " and " + words[words.count - 1] + "."
    }

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
