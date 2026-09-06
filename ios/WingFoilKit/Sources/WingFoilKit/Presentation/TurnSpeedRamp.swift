import SwiftUI

/// Speed → colour for the turn sheet's breadcrumb, and the legend that says so.
///
/// **Why a ramp of its own, and not the phase pair.** The in-turn line used to be mixed
/// between the off-foil grey and the flying teal by speed: two inks, so the only thing the
/// line could say was "more teal than grey", and a rider reading a jibe cannot put a number
/// on that. Worse, at the fast end the ramp simply stopped — a turn *accelerated* through
/// was drawn exactly like one that merely held its entry speed. Five stops with an anchor in
/// the middle say three things instead of one: where the speed was gone, where it was the
/// speed he came in with, and where he was quicker coming out than going in.
///
/// **The anchor is the whole design.** `position` is not a fraction of the fastest vertex —
/// that would make every turn its own scale, and two jibes side by side incomparable. It is
/// a fraction of *this turn's entry speed*, which is the number the score is a ratio of and
/// the number the rider is asking about:
///
/// | speed | position | stop |
/// |---|---|---|
/// | 0 kn | 0 | `stopped` — the cold end |
/// | half the entry speed | 0.25 | between `stopped` and `slow` |
/// | **the entry speed** | **0.5** | **`entry` — the flying teal** |
/// | 1.3 × entry and up | 1 | `fastest` — the hot end |
///
/// The cap exists because the ramp has to end somewhere and 30 % over the entry speed is
/// already a remarkable turn; past it the line is simply the hot colour rather than a
/// colour nobody can name. Definitions: docs/presentation.md, "Turn detail".
public enum TurnSpeedRamp {

    /// Where the hot end of the ramp sits, as a multiple of the turn's entry speed.
    public static let overspeedCap = 1.3

    /// A turn entered at less than this is not a turn with a reference speed, and the ramp
    /// would divide by a rounding error. Below it every vertex simply reads cold.
    public static let minReferenceKn = 0.5

    /// Where the cold end of the ramp sits, as a fraction of the turn's entry speed.
    ///
    /// Not zero (Jan, 6 Sep 2026: "not nuanced enough"). A jibe is ridden between roughly
    /// two thirds of its entry speed and the entry speed — 8 to 12 kn on a 12 kn entry —
    /// and a ramp that started at 0 kn spent its whole cold half on speeds nobody foils at,
    /// leaving that 8–12 band inside one stop. Anchoring the cold end at half the entry
    /// speed puts the low point of a 66 % jibe a full stop below the entry colour and the
    /// low point of an 81 % jibe visibly above it; below half the entry speed the rider is
    /// off the foil anyway, and the line simply stays cold.
    public static let coldFraction = 0.5
    /// Where `kn` sits on the ramp, 0…1 — see the table above.
    public static func position(kn: Double, entryKn: Double) -> Double {
        guard entryKn >= minReferenceKn, kn > 0 else { return 0 }
        if kn <= entryKn {
            let cold = entryKn * coldFraction
            return 0.5 * min(max((kn - cold) / (entryKn - cold), 0), 1)
        }
        let over = (kn - entryKn) / (entryKn * (overspeedCap - 1))
        return 0.5 + 0.5 * min(over, 1)
    }

    /// The bottom of the legend's bar — the cold end, in knots.
    public static func legendBottomKn(entryKn: Double) -> Double { entryKn * coldFraction }

    /// Which two stops a position falls between, and how far it is from the first.
    ///
    /// Pure and separate from `color` so the arithmetic can be tested without asking a test
    /// what a `Color` is: `blend` is what a renderer mixes by, and an off-by-one here would
    /// show up as a line drawn a whole stop cold.
    public static func stop(at position: Double) -> (lower: Int, upper: Int, blend: Double) {
        let stops = DesignTokens.Speed.rampRGB.count
        let scaled = min(max(position, 0), 1) * Double(stops - 1)
        let lower = min(Int(scaled.rounded(.down)), stops - 2)
        return (lower, lower + 1, scaled - Double(lower))
    }

    /// The ink for a position on the ramp.
    ///
    /// Mixed from the generated components rather than with SwiftUI's own colour blend,
    /// which is newer than this package's oldest platform — and mixing the numbers is what
    /// a ramp means anyway.
    public static func color(at position: Double) -> Color {
        let (lower, upper, blend) = stop(at: position)
        let ramp = DesignTokens.Speed.rampRGB
        let (from, to) = (ramp[lower], ramp[upper])
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * blend }
        return Color(red: mix(from.red, to.red),
                     green: mix(from.green, to.green),
                     blue: mix(from.blue, to.blue))
    }

    /// The ink for a speed, against the turn's entry speed.
    public static func color(kn: Double, entryKn: Double) -> Color {
        color(at: position(kn: kn, entryKn: entryKn))
    }

    /// The top of the legend's bar: the entry speed, or the turn's own maximum where it went
    /// faster than that — never past the ramp's cap, because there is no colour beyond it.
    ///
    /// It is the *drawn* maximum and not the cap itself, so the number under the hot end of
    /// the bar is a speed the rider actually rode. A turn that never beat its entry speed
    /// gets a bar that ends at the entry speed, which is the honest picture: the top half of
    /// the ramp was not used.
    public static func legendTopKn(entryKn: Double, maxKn: Double) -> Double {
        max(entryKn, min(maxKn, entryKn * overspeedCap))
    }
}
