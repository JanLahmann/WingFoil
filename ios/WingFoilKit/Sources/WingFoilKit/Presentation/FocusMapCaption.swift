import Foundation

/// **The line under the Turns and Takeoffs maps, counted from what the map draws.**
///
/// Jan, 30 Sep 2026, on build 119: the Turns tab filtered to tacks on a session with none
/// said *"Nothing to mark. Widen the filters."* under a map full of wrist-under diamonds.
/// The caption counted the page's filtered pins; the map also draws the layers the page's
/// filter does not touch. The wrist-under diamonds are unfiltered on purpose — an episode
/// belongs to the afternoon, not to the subset the page is asking about
/// (docs/presentation/layers-map-colour-type.md, "Wrist under") — so the caption is what
/// moves: it now reads every layer the map actually draws.
///
/// Three cases, in this order:
/// 1. the page's own marks are drawn: how many, and what a tap does;
/// 2. the filter kept marks but the layer chips hide all of them: say so, because
///    "widen the filters" would send the rider to the wrong control;
/// 3. the filter kept nothing: name the other marks that are still drawn, or say there is
///    nothing to mark.
public enum FocusMapCaption {

    /// The Turns map. `drawn` is the turn pins on the map (filter and layer chips both
    /// applied), `kept` the turns the filter kept, `wristUnder` and `courseChanges` the
    /// session-wide marks the map draws beside them (0 when their chip is off).
    public static func turns(drawn: Int, kept: Int, wristUnder: Int,
                             courseChanges: Int) -> String {
        if drawn > 0 {
            return String(drawn) + (drawn == 1 ? " turn" : " turns")
                + " marked · tap a row below to open it."
        }
        if kept > 0 { return "The layers below hide every turn in this filter." }
        return others(wristUnder: wristUnder, courseChanges: courseChanges)
            ?? "Nothing to mark. Widen the filters."
    }

    /// The Takeoffs map. `noun` is the filter's own ("failed attempts", "planing starts").
    public static func takeoffs(drawn: Int, kept: Int, noun: String,
                                wristUnder: Int) -> String {
        if drawn > 0 {
            return String(drawn) + " " + noun
                + " marked · tap a pin or a row to point at one."
        }
        if kept > 0 { return "The layers below hide every mark in this filter." }
        return others(wristUnder: wristUnder, courseChanges: 0)
            ?? "Nothing to mark. Widen the filter."
    }

    /// What is still on the map when the filter kept nothing, one sentence a layer.
    static func others(wristUnder: Int, courseChanges: Int) -> String? {
        var lines: [String] = []
        if wristUnder > 0 { lines.append("The diamonds mark each time your wrist went under.") }
        if courseChanges > 0 { lines.append("The grey dots are course changes.") }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }
}
