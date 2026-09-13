import Foundation

/// **One lexicon per discipline** (docs/presentation.md "Discipline lexicon").
///
/// A windsurfer on a fin does not fly and has no foil to lose. Every word in this table is a
/// word the engine has no opinion about — the numbers, the verdicts and the layer names are
/// identical, and only their spelling changes — so the swap lives here, in presentation, and
/// nowhere near the analyzer.
///
/// **The wingfoil column is byte-identical to what the app has always said.** Not "the same
/// wording": the same strings. `.wingfoil` is the default of every parameter that takes a
/// lexicon, so a surface that has not been taught about disciplines prints exactly what it
/// printed before.
///
/// Deliberately *not* translated: the turn vocabulary. A jibe is a jibe, a tack is a tack,
/// *flew through*, *clean*, *dry* and *wrist under* mean the same thing on either rig — and
/// "clean jibe" is the one phrase this product is named after (docs/presentation.md, the
/// clean-jibe spelling contract). The web's copy is `web/js/lexicon.js`.
public struct DisciplineLexicon: Sendable, Equatable {

    public let discipline: Discipline

    public init(_ discipline: Discipline) { self.discipline = discipline }

    /// Is this the published, validated vocabulary?
    public var isExperimental: Bool { discipline.isWindsurf }

    /// Does this discipline have a pump channel at all? Where it does not, every
    /// pump-related surface is **absent, not zero** — a windsurfer did not pump nought
    /// times, the question was not asked of him.
    public var pumping: Bool { discipline.pumping }

    // MARK: - The table

    /// The verb, lower case: "flying" / "planing".
    public var flying: String { discipline.isWindsurf ? "planing" : "flying" }

    /// The duration card's title: "Foil time" / "Planing time".
    public var foilTime: String { discipline.isWindsurf ? "Planing time" : "Foil time" }

    /// The same, mid-sentence — the caption under the share: "foil time" / "planing time".
    public var foilTimeLower: String {
        discipline.isWindsurf ? "planing time" : "foil time"
    }

    /// The share card's title: "On foil" / "Planing".
    public var onFoil: String { discipline.isWindsurf ? "Planing" : "On foil" }

    /// The same in a caption voice: "on foil" / "planing".
    public var onFoilLower: String { discipline.isWindsurf ? "planing" : "on foil" }

    /// One flight start: "Takeoff" / "Planing start".
    public var takeoff: String { discipline.isWindsurf ? "Planing start" : "Takeoff" }

    /// Mid-sentence: "takeoff" / "planing start".
    public var takeoffLower: String {
        discipline.isWindsurf ? "planing start" : "takeoff"
    }

    /// The section tab and the map: "Takeoffs" / "Planing starts".
    public var takeoffs: String { discipline.isWindsurf ? "Planing starts" : "Takeoffs" }

    /// The outcome ladder, in a sentence: "lost the foil" / "stopped planing".
    public var lostTheFoil: String {
        discipline.isWindsurf ? "stopped planing" : "lost the foil"
    }

    /// The one word this table adds to Jan's list, because `TurnAnalytics.outcomeText`
    /// needs it: "off the foil" / "off the plane". A windsurfer's own phrase for the same
    /// second — the board dropped off the plane — rather than a foil he was not riding.
    public var offTheFoil: String {
        discipline.isWindsurf ? "off the plane" : "off the foil"
    }

    /// The chip beside the discipline badge, or nil for the default. One string, said the
    /// same way on the session page and in the library row.
    public var chip: String? { discipline.isWindsurf ? "windsurf · experimental" : nil }

    /// The footnote under the "Analyse as" row, and the sentence the help topic opens with.
    /// The whole disclaimer in one breath: what works, what is off, what is a guess, and the
    /// ask.
    public static let experimentalNote =
        "Experimental — windsurf analysis is untested; jibes and tacks work, pumping is off, "
        + "planing thresholds are provisional. Tell us what you see."
}

public extension Discipline {
    /// This discipline's words. The one door — no surface constructs a lexicon by hand.
    var lexicon: DisciplineLexicon { DisciplineLexicon(self) }
}
