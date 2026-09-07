import Foundation

/// The two filters the turns page applies at the same time, and everything they produce:
/// the rows of the list, the outcome tally above it and the set of turns the map marks.
///
/// This lives in the kit rather than in the view for the reason `HrCostCard` does: the
/// wording is the feature. "Port entry" is not a synonym for "left" — a turn carries both
/// the tack it was **entered on** (`side`) and the direction the board **rotated**
/// (`direction`), and a filter labelled "left" would be read as the second while doing the
/// first. The label and the field it filters are therefore defined together, here, where a
/// test can hold them to each other.
///
/// Definitions: docs/algorithms.md "Turn detection" / "Turn outcome".

// MARK: - Filters

/// Jibes, tacks, or every counted maneuver.
///
/// `both` is not "everything the detector saw": a bear-away or a round-up is a course
/// change, not a maneuver, and the engine already says so with `counted == false`. Those
/// stay out of all three cases, exactly as they stay out of the session summary.
public enum TurnTypeFilter: String, CaseIterable, Sendable, Identifiable, Codable {
    case both
    case jibes
    case tacks

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .both: return "Both"
        case .jibes: return "Jibes"
        case .tacks: return "Tacks"
        }
    }

    /// The engine's `type` values this case accepts. `both` also keeps a plain "turn" —
    /// a maneuver detected without a usable wind axis to name it — because dropping it
    /// would make the tally disagree with the session summary's `turnsCounted`.
    func accepts(type: String) -> Bool {
        switch self {
        case .both: return true
        case .jibes: return type == "jibe"
        case .tacks: return type == "tack"
        }
    }
}

/// Which tack the turn was **entered** on.
///
/// Never labelled "left"/"right". The rider's question is "am I worse coming into a jibe
/// on starboard?", which is about the entry tack; the rotation direction is a different
/// field with the same two words in it, and the two disagree often enough that a loose
/// label would quietly answer the wrong question.
public enum TurnSideFilter: String, CaseIterable, Sendable, Identifiable, Codable {
    case both
    case port
    case starboard

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .both: return "Both"
        case .port: return "Port entry"
        case .starboard: return "Starboard entry"
        }
    }

    /// `both` keeps `"unknown"` too — a turn with no usable wind axis has no entry tack,
    /// and hiding it from the unfiltered view would lose it entirely.
    func accepts(side: String) -> Bool {
        switch self {
        case .both: return true
        case .port: return side == "port"
        case .starboard: return side == "starboard"
        }
    }
}

/// Both segmented controls, applied together (AND).
public struct TurnFilter: Sendable, Equatable, Codable {
    public var type: TurnTypeFilter
    public var side: TurnSideFilter

    public init(type: TurnTypeFilter = .both, side: TurnSideFilter = .both) {
        self.type = type
        self.side = side
    }

    public var isEverything: Bool { type == .both && side == .both }

    /// "Jibes · starboard entry" — what the empty state and the accessibility summary say
    /// the reader is currently looking at.
    public var description: String {
        switch (type, side) {
        case (.both, .both): return "all turns"
        case (.both, _): return "turns entered on \(side == .port ? "port" : "starboard")"
        case (_, .both): return type.label.lowercased()
        default:
            return "\(type.label.lowercased()) entered on "
                + "\(side == .port ? "port" : "starboard")"
        }
    }
}

// MARK: - Rows

/// The three-way outcome ladder, as the list draws it. Same vocabulary as the map dots —
/// green flew through, amber touchdown, red fell in — so a row and a dot can never claim
/// different things about the same turn.
public enum TurnOutcomeKind: String, Sendable, Equatable, CaseIterable {
    case flewThrough
    case touchdown
    case fellIn

    /// From the engine's snake-case `outcome`. Anything that is not a touchdown or a fall
    /// is a flew-through, which is also how the map's `outcomeTone` reads `glide_out`.
    public init(_ raw: String) {
        switch raw {
        case "fell_in": self = .fellIn
        case "touchdown": self = .touchdown
        default: self = .flewThrough
        }
    }

    /// The word in the row, and in the tally's caption.
    public var label: String {
        switch self {
        case .flewThrough: return "flew through"
        case .touchdown: return "touchdown"
        case .fellIn: return "fell in"
        }
    }

    /// The SF Symbol the row and the tally chip both use — a shape as well as a colour,
    /// so the ladder survives a colour-blind reader and a greyscale screenshot.
    public var symbolName: String {
        switch self {
        case .flewThrough: return "checkmark.circle.fill"
        case .touchdown: return "exclamationmark.triangle.fill"
        case .fellIn: return "xmark.circle.fill"
        }
    }

    /// The legend chip this rung answers to.
    public var layer: MapLayer {
        switch self {
        case .flewThrough: return .flewThrough
        case .touchdown: return .touchdown
        case .fellIn: return .fellIn
        }
    }

    /// **The one chip a turn's pin answers to** — the same rule the session map's markers
    /// follow (`EventMarker.layers`), said once so the Turns map cannot drift from it.
    ///
    /// A clean jibe is drawn as a star and answers to `cleanJibe` *alone*: hide "flew
    /// through" and the plain flew-through dots go while the stars stay, hide "clean jibe"
    /// and the stars go while the dots stay (docs/presentation.md, "Clean jibe"). Nothing is
    /// ever drawn twice, and nothing answers to two chips.
    public func layer(clean: Bool) -> MapLayer { clean ? .cleanJibe : layer }
}

/// One row of the turn list, fully resolved: no view formats a number.
public struct TurnListItem: Sendable, Equatable, Identifiable {
    /// Index into `SessionAnalysis.turns` — the identity the map pins share, so tapping a
    /// row and tapping its dot are the same turn.
    public let id: Int
    /// Session-clock seconds, the same base the chart's x axis uses.
    public let ts: Double
    public let endTs: Double
    /// "Jibe" | "Tack" | "Turn".
    public let typeLabel: String
    /// "port" | "starboard" | "unknown" — the raw field, for filtering and tests.
    public let side: String
    /// "port entry" / "starboard entry" / "entry tack unknown".
    public let sideLabel: String
    public let outcome: TurnOutcomeKind
    /// The engine's 0…1 carry-through score.
    public let score: Double
    /// "67" — the score as the row prints it, percent-shaped without the sign.
    public let scoreText: String
    /// Whether this row is a jibe, read off the one label the app ever prints for one.
    /// The row carries no raw `type` — nothing downstream should be re-deciding what a
    /// turn is called — so the question is asked of the label, which `typeLabel` owns.
    public var isJibe: Bool { typeLabel == TurnAnalytics.typeLabel("jibe") }
    /// A **clean jibe**: the engine's own `clean` verdict (engine 0.12.0) — the score
    /// cleared `turnSuccessPct`, the foil was never lost across the scored window, *and*
    /// the turn flew through. A strict subset of `outcome == .flewThrough`, never a
    /// crosswise reading of it, and false on every tack: "clean" is a jibe word.
    public let clean: Bool
    /// A touchdown that only just missed being a fall (or vice versa).
    public let borderline: Bool
    public let submerged: Bool
    public let pumped: Bool
    /// "11.1 → 7.5 kn · stopped 15 s · wrist under".
    public let detail: String

    public init(id: Int, ts: Double, endTs: Double, typeLabel: String, side: String,
                sideLabel: String, outcome: TurnOutcomeKind, score: Double, scoreText: String,
                clean: Bool = false, borderline: Bool, submerged: Bool, pumped: Bool,
                detail: String) {
        self.clean = clean
        self.id = id
        self.ts = ts
        self.endTs = endTs
        self.typeLabel = typeLabel
        self.side = side
        self.sideLabel = sideLabel
        self.outcome = outcome
        self.score = score
        self.scoreText = scoreText
        self.borderline = borderline
        self.submerged = submerged
        self.pumped = pumped
        self.detail = detail
    }

    /// One sentence for VoiceOver: a row of five columns is unreadable read column by
    /// column.
    public var accessibilityText: String {
        var parts = ["\(typeLabel), \(sideLabel)", outcome.label, "score \(scoreText)"]
        if clean { parts.append("clean") }
        if borderline { parts.append("borderline") }
        if submerged { parts.append("wrist under water") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Tally

/// The outcome counts under the current filter, plus the one rate the rider actually asks
/// about.
///
/// **The rate is the flew-through share, and it is labelled as such.** The **clean jibe**
/// count beside it is a *different* number — the engine's per-turn `clean` flag, which
/// since 0.12.0 demands the score against `turnSuccessPct` **and** a `flew_through`
/// outcome. Both are true; they answer different questions ("how did it end" against "did
/// you ride it"), so neither ever borrows the other's name. Clean is now a strict subset
/// of flew-through rather than a verdict that could disagree with it, which is exactly why
/// the two must stay visibly separate: the distinction is "this one is narrower", and a
/// surface that drew them alike would claim every jibe that flew was ridden.
///
/// nil rather than 0 when nothing survives the filter: "you have never tacked" and "you
/// fail every tack" are opposite facts and must not print the same.
public struct TurnOutcomeTally: Sendable, Equatable {
    public let flewThrough: Int
    public let touchdown: Int
    public let fellIn: Int
    /// How many of the filtered turns were **clean** — the engine's per-turn `clean` flag,
    /// read and never re-derived: a counted jibe that carried its speed (score at or above
    /// `turnSuccessPct`, and never below the foil exit speed) *and* flew through. Not one
    /// of the three counts and never drawn on the ladder's inks: it is the stricter verdict
    /// laid over the same set, and since engine 0.12.0 a strict *subset* of `flewThrough`.
    public let clean: Int
    /// How many of the filtered turns were jibes — the denominator the clean line divides
    /// by, and the reason a tacks-only filter has no clean line at all rather than a "0 of
    /// 4" that would read as four botched tacks. A tack is never clean and never dirty.
    public let jibes: Int

    public init(flewThrough: Int = 0, touchdown: Int = 0, fellIn: Int = 0, clean: Int = 0,
                jibes: Int = 0) {
        self.flewThrough = flewThrough
        self.touchdown = touchdown
        self.fellIn = fellIn
        self.clean = clean
        self.jibes = jibes
    }

    public var total: Int { flewThrough + touchdown + fellIn }

    /// Share of the filtered turns that never left the foil.
    public var flewThroughPct: Double? {
        guard total > 0 else { return nil }
        return 100.0 * Double(flewThrough) / Double(total)
    }

    public func count(_ outcome: TurnOutcomeKind) -> Int {
        switch outcome {
        case .flewThrough: return flewThrough
        case .touchdown: return touchdown
        case .fellIn: return fellIn
        }
    }

    /// "9 flew · 9 touch · 12 fell", or the honest empty line.
    public var caption: String {
        guard total > 0 else { return "nothing matches this filter" }
        return "\(flewThrough) flew · \(touchdown) touch · \(fellIn) fell"
    }

    /// "7 of 10 clean" — the strict verdict, in the words the rest of the app uses for it,
    /// over the **jibes** in the filtered set. Empty when the filter leaves no jibe, for
    /// the same reason `flewThroughPct` is nil when it leaves no turn: "you have never done
    /// this" is not "you fail at it", and a tack has no clean reading to report.
    public var cleanCaption: String {
        guard jibes > 0 else { return "" }
        return "\(clean) of \(jibes) clean"
    }
}

// MARK: - The one place the filter is applied

public enum TurnAnalytics {

    /// Whether one turn survives the filter.
    ///
    /// The `counted` gate is first and unconditional. A bear-away is a course change the
    /// detector saw and deliberately rejected; it is excluded from the session summary, from
    /// the map's outcome dots and from here, so no view can accidentally start counting it.
    public static func matches(_ turn: TurnRecord, _ filter: TurnFilter) -> Bool {
        turn.counted && filter.type.accepts(type: turn.type)
            && filter.side.accepts(side: turn.side)
    }

    /// The rows for a filter, in time order (the engine already emits turns in time order).
    public static func items(_ turns: [TurnRecord],
                             filter: TurnFilter = TurnFilter()) -> [TurnListItem] {
        turns.enumerated().compactMap { index, turn in
            guard matches(turn, filter) else { return nil }
            return item(turn, id: index)
        }
    }

    /// One row from one turn. `id` is the turn's index in the analysis, not its position in
    /// the filtered list — filtering must not renumber the session.
    public static func item(_ turn: TurnRecord, id: Int) -> TurnListItem {
        TurnListItem(id: id, ts: turn.ts, endTs: turn.endTs,
                     typeLabel: typeLabel(turn.type), side: turn.side,
                     sideLabel: sideLabel(turn.side),
                     outcome: TurnOutcomeKind(turn.outcome),
                     score: turn.score, scoreText: scoreText(turn.score),
                     clean: turn.clean,
                     borderline: turn.borderline, submerged: turn.submerged,
                     pumped: turn.pumped, detail: detail(turn))
    }

    /// The outcome counts over already-filtered rows.
    public static func tally(_ items: [TurnListItem]) -> TurnOutcomeTally {
        var flew = 0, touch = 0, fell = 0, clean = 0, jibes = 0
        for item in items {
            switch item.outcome {
            case .flewThrough: flew += 1
            case .touchdown: touch += 1
            case .fellIn: fell += 1
            }
            if item.clean { clean += 1 }
            if item.isJibe { jibes += 1 }
        }
        return TurnOutcomeTally(flewThrough: flew, touchdown: touch, fellIn: fell,
                                clean: clean, jibes: jibes)
    }

    /// Filter and tally in one step — what the header uses.
    public static func tally(_ turns: [TurnRecord], filter: TurnFilter) -> TurnOutcomeTally {
        tally(items(turns, filter: filter))
    }

    /// How many turns a filter *could* show, so a segmented option that would empty the
    /// page can say so before it is tapped.
    public static func count(_ turns: [TurnRecord], filter: TurnFilter) -> Int {
        turns.reduce(0) { $0 + (matches($1, filter) ? 1 : 0) }
    }

    // MARK: - Wording

    public static func typeLabel(_ type: String) -> String {
        switch type {
        case "jibe": return "Jibe"
        case "tack": return "Tack"
        case "bear_away": return "Bear-away"
        case "round_up": return "Round-up"
        default: return "Turn"
        }
    }

    /// The entry tack, always spelled out as an *entry*. Never "left" or "right".
    public static func sideLabel(_ side: String) -> String {
        switch side {
        case "port": return "port entry"
        case "starboard": return "starboard entry"
        default: return "entry tack unknown"
        }
    }

    /// 0.6703 → "67". Percent-shaped because the score is read as "how much of the turn he
    /// carried", and a bare 0.67 invites the reader to compare it with a speed.
    public static func scoreText(_ score: Double) -> String {
        String(format: "%.0f", (score * 100).rounded())
    }

    // MARK: - How much pumping a turn cost

    /// The strokes the rider put in to get out of one turn, or nil where the analysis does
    /// not know.
    ///
    /// The engine already answers this: a pump episode whose outcome is `recovery` carries
    /// the index of the turn whose outcome window owns it (`PumpEpisodeRecord.turnIndex`,
    /// engine 0.3.0), and more than one episode may be claimed by one turn — a rider who
    /// pumps, sinks and pumps again pumped twice out of the same jibe — so they sum.
    ///
    /// nil rather than 0 when nothing is claimed, because the two are different statements:
    /// "he pumped and the analysis counted no strokes" is a claim, and "this build's
    /// analysis has no episodes at all" (a document written before 0.3.0, or a source with
    /// no accelerometer) is an absence. A chip may print the first and must not print the
    /// second — see the formatter rule "a missing value is absent, never 0".
    public static func pumpStrokes(for turnIndex: Int,
                                   in episodes: [PumpEpisodeRecord]) -> Int? {
        let claimed = episodes.filter { $0.turnIndex == turnIndex }
        guard !claimed.isEmpty else { return nil }
        let strokes = claimed.reduce(0) { $0 + $1.strokes }
        return strokes > 0 ? strokes : nil
    }

    /// The same question with the fallback the presentation needs: where no episode names
    /// this turn, the ones that *overlap the window the turn's outcome was judged on*
    /// (`ts ... endTs + outcomeWindowS`) are the pumping the rider did out of it.
    ///
    /// The fallback exists because `turnIndex` is written by the classifier and the
    /// `pumped` flag is written by the turn detector, and a stored analysis can carry the
    /// second without the first. It is deliberately second: an episode the engine actually
    /// assigned beats one that merely happens to overlap.
    public static func pumpStrokes(for turnIndex: Int, turn: TurnRecord,
                                   in episodes: [PumpEpisodeRecord]) -> Int? {
        if let claimed = pumpStrokes(for: turnIndex, in: episodes) { return claimed }
        let from = turn.ts
        let to = turn.endTs + turn.outcomeWindowS
        let overlapping = episodes.filter { $0.endTs >= from && $0.startTs <= to }
        guard !overlapping.isEmpty else { return nil }
        let strokes = overlapping.reduce(0) { $0 + $1.strokes }
        return strokes > 0 ? strokes : nil
    }

    /// "7 strokes", and "1 stroke" — the chip and the coach line print the same words.
    public static func strokesText(_ strokes: Int) -> String {
        "\(strokes) stroke\(strokes == 1 ? "" : "s")"
    }

    /// **Why this jibe has no star** — the chip beside the outcome (engine 0.17.0).
    ///
    /// nil for every turn that is clean, for every turn that is not a jibe, and for every
    /// jibe the score or the outcome already refused: those the page states in words of its
    /// own ("touched down", "held 61 % of entry speed"), and a second sentence saying the
    /// same thing is noise. What is left is the two refusals nothing else shows.
    ///
    /// `ends` gives the touchdown its **time** — "touched down 6 s after" — by finding the
    /// end the engine's own rule would have found: the first touchdown or fall inside the
    /// quiet tail. The engine stores the reason and not the instant, and re-deriving the
    /// instant from the same document is the same fallback the pump chip already makes for
    /// its stroke count. Nothing found ⇒ the plainer wording, never a fabricated number.
    public static func notCleanText(_ turn: TurnRecord, ends: [FlightEndRecord] = [],
                                    quietS: Double? = nil) -> String? {
        guard let reason = turn.cleanBlockedBy.flatMap(CleanBlock.init(rawValue:)) else {
            return nil
        }
        switch reason {
        case .quietFlightEnd:
            guard let seconds = secondsToLoss(turn, ends: ends, quietS: quietS) else {
                return "not clean · touched down after"
            }
            return "not clean · touched down \(seconds) s after"
        case .quietOffFoil: return "not clean · off the foil after"
        case .quietSubmerged: return "not clean · wrist under after"
        case .axisAfter:
            guard let after = turn.axisAfterDeg, after.isFinite else {
                return "not clean · short of the axis"
            }
            return String(format: "not clean · carried %.0f° past the axis", after)
        }
    }

    /// **Why this turn is a touchdown or a fall** — the line under the chips (engine 0.18.0).
    ///
    /// Jan, 7 Sep 2026: *"Can we add a short comment for the user why a jibe is a touchdown or
    /// a fall?"* The page had the numbers — `stoppedS`, `offFoilS`, a wrist-under chip — and
    /// left the rider to assemble the verdict out of them. The engine now writes down which
    /// rung of the ladder decided (`outcomeReason`), and this is the one place that rung
    /// becomes words. `web/js/viz.js` holds the same function for the site and
    /// `verify_presentation.py` holds the two to each other, so a rider reading the same jibe
    /// on the phone and on the web is told the same thing.
    ///
    /// nil for a fly-through — nothing happened, and "flew through" is already on the chip —
    /// and nil for a document written before 0.18.0, which carries no reason: a sentence
    /// reconstructed from `stoppedS` alone would be a guess about a ladder that may not have
    /// been climbed that way.
    ///
    /// `foilExitSpeedKmh` is the analysis' own config echo, converted to knots for the one
    /// wording that names a speed. Without it that wording drops the number rather than
    /// printing a default the run may not have used.
    public static func outcomeText(_ turn: TurnRecord,
                                   foilExitSpeedKmh: Double? = nil) -> String? {
        guard let reason = turn.outcomeReason.flatMap(OutcomeReason.init(rawValue:)) else {
            return nil
        }
        switch reason {
        case .stop:
            let stopped = "stopped \(seconds(turn.stoppedS)) s"
            if TurnOutcomeKind(turn.outcome) == .fellIn { return "fell in · \(stopped)" }
            return "touchdown · \(stopped)" + (turn.borderline ? ", borderline" : "")
        case .offFoil:
            // "no stop" rather than "stopped 0 s": the rider did not stop, and a rounded zero
            // reads as a measurement of one.
            let stop = turn.stoppedS.rounded() >= 1
                ? "stopped \(seconds(turn.stoppedS)) s" : "no stop"
            return "touchdown · off the foil \(seconds(turn.offFoilS)) s, " + stop
        case .submerged:
            return "fell in · wrist under"
        case .pumpedMarginal:
            guard let kmh = foilExitSpeedKmh, kmh.isFinite else {
                return "touchdown · pumped out below min foil speed, no sample off the foil"
            }
            return String(format: "touchdown · pumped out below %.1f kn, "
                          + "no sample off the foil", kmh * kmhToKn)
        }
    }

    /// Whole seconds, **half away from zero** — `.rounded()` here, `Math.round` in
    /// `web/js/viz.js`, `floor(v + 0.5)` in `verify_presentation.py`. Spelled out rather
    /// than left to each language's default formatter, because `%.0f` rounds 4.5 to 4
    /// (banker's) while `toFixed(0)` rounds it to 5, and a stop of exactly 4.5 s is an
    /// ordinary reading at 1 Hz.
    static func seconds(_ value: Double) -> String { String(Int(value.rounded())) }

    /// km/h to knots, for the one sentence that names a config speed in the rider's unit.
    static let kmhToKn = 1.0 / 1.852

    /// Whole seconds from the sweep's end to the flight end that cost the jibe its star.
    static func secondsToLoss(_ turn: TurnRecord, ends: [FlightEndRecord],
                              quietS: Double?) -> Int? {
        let tail = turn.endTs + (quietS ?? 0)
        let loss = ends
            .filter { !$0.truncated && ($0.outcome == "touchdown" || $0.outcome == "fell_in") }
            .filter { $0.ts >= turn.endTs && $0.ts <= tail }
            .map(\.ts)
            .min()
        guard let loss else { return nil }
        return max(Int((loss - turn.endTs).rounded()), 0)
    }

    /// The same second line the map callout carries, so the two never diverge.
    public static func detail(_ turn: TurnRecord) -> String {
        var text = String(format: "%.1f → %.1f kn", turn.entryKn, turn.minKn)
        if turn.stoppedS > 0 { text += String(format: " · stopped %.0f s", turn.stoppedS) }
        if turn.submerged { text += " · wrist under" }
        if turn.pumped { text += " · pumped out" }
        return text
    }
}

// MARK: - Trends

/// The flew-through share split by the tack the turn was entered on — one session's
/// contribution to the two Trends series.
///
/// **Not the clean-jibe rate**, despite the `…SuccessPct` property names it has carried
/// since before the metric had a name: these count `flewThrough`, the outcome, not the
/// engine's `success` flag. The chart's title says "flew through" for that reason.
///
/// Built from the per-turn rows rather than from the session summary because the summary
/// counts port and starboard turns but not their *outcomes* (docs: `TurnSummary`), and
/// extending the engine to carry them would move a golden. The per-turn detail is already
/// in the `turn` table for exactly this kind of question.
public struct TurnSideSplit: Sendable, Equatable {
    public var portCounted: Int
    public var portFlewThrough: Int
    public var starboardCounted: Int
    public var starboardFlewThrough: Int

    public init(portCounted: Int = 0, portFlewThrough: Int = 0,
                starboardCounted: Int = 0, starboardFlewThrough: Int = 0) {
        self.portCounted = portCounted
        self.portFlewThrough = portFlewThrough
        self.starboardCounted = starboardCounted
        self.starboardFlewThrough = starboardFlewThrough
    }

    /// nil, not 0, when the session entered no turn on that tack — a missing point in the
    /// series, which is what "he did not jibe that way today" honestly looks like.
    public var portSuccessPct: Double? {
        guard portCounted > 0 else { return nil }
        return 100.0 * Double(portFlewThrough) / Double(portCounted)
    }

    public var starboardSuccessPct: Double? {
        guard starboardCounted > 0 else { return nil }
        return 100.0 * Double(starboardFlewThrough) / Double(starboardCounted)
    }

    public var isEmpty: Bool { portCounted == 0 && starboardCounted == 0 }

    /// Signed gap in percentage points, port minus starboard. nil unless *both* sides were
    /// ridden — a difference needs two numbers.
    public var gapPct: Double? {
        guard let port = portSuccessPct, let starboard = starboardSuccessPct else { return nil }
        return port - starboard
    }

    public mutating func add(side: String, flewThrough: Bool) {
        switch side {
        case "port":
            portCounted += 1
            if flewThrough { portFlewThrough += 1 }
        case "starboard":
            starboardCounted += 1
            if flewThrough { starboardFlewThrough += 1 }
        default:
            break                       // no usable wind axis ⇒ no entry tack to attribute
        }
    }

    /// From an analysis (the session-detail path). Uncounted turns are skipped, same as
    /// everywhere else.
    public static func make(_ turns: [TurnRecord]) -> TurnSideSplit {
        var split = TurnSideSplit()
        for turn in turns where turn.counted {
            split.add(side: turn.side,
                      flewThrough: TurnOutcomeKind(turn.outcome) == .flewThrough)
        }
        return split
    }
}
