import Foundation

/// The four subjects a session view is divided into, and the rule for which one owns a
/// given anchor.
///
/// The session page was one column of roughly 3 800 pt — a little over four full phone
/// screens — with five unrelated subjects stacked in it and no way to reach the fifth except
/// by scrolling through the other four (`docs/app-ui-review.md` §3.1). It is a switcher now,
/// and this is the model half of that switcher: the cases, their words, and the mapping from
/// a section anchor to the tab it lives on. The views are layout over this, and the web app
/// uses the same four ids, because the two are meant to be the same product.
///
/// **The split is between the figures and the cards, and that is not a matter of taste.**
/// `docs/presentation.md` "Scrub and zoom" mandates one playhead — the chart's scrub
/// position and the map's dot are the same timestamp, and moving either moves both — and
/// "Pairing" adds that tapping a flown stretch of track focuses the chart on that flight. Map
/// and chart are one instrument. A tab set that gives Map a page of its own breaks the
/// visible half of that link: you tap a segment, and the chart it focused is somewhere else.
/// So `mapSpeed` carries both figures and everything that annotates them, permanently.
///
/// Two absences that are decisions rather than omissions:
///
/// * **No `overview`.** The key-metrics block is the overview and it sits *above* the
///   switcher on every section — the answer to "was that a good session" should never be a
///   page you can navigate away from (§3.3).
/// * **No `records`.** The record picker exists to highlight a window on the map and the
///   chart, so it belongs with them; a picker on a tab away from the figures highlights
///   something the reader cannot see. This is on the review's "deliberately not recommended"
///   list, and it is the same mistake as putting Map on its own page.
public enum SessionSection: String, CaseIterable, Sendable, Identifiable {
    /// The map, its legend, the speed chart, the shared scrubber, the foil facts and the
    /// speed-record table. The default, and the one that must never be split.
    case mapSpeed
    /// The turn cards, with the filtered tally/map/list folded in underneath them — it was
    /// a pushed page two taps and ~2 400 pt deep (§2.1).
    case turns
    /// Takeoff and pumping, led by the attempts that did not get up.
    case takeoffs
    /// What it cost: heart rate, the fatigue bins, and the kit it was ridden on.
    case effort

    public var id: String { rawValue }

    /// The switcher's words. Short enough for four segments across a 390 pt phone, and the
    /// middle dot in "Map · Speed" is load-bearing: it says these are two figures that
    /// travel together, not a section called "Map".
    public var label: String {
        switch self {
        case .mapSpeed: "Map · Speed"
        case .turns: "Turns"
        case .takeoffs: "Takeoffs"
        case .effort: "Effort"
        }
    }

    /// The scroll anchors each section contains, in the order they appear on it.
    ///
    /// These are the ids the views attach with `.id(_:)` and the names the screenshot hooks
    /// (`UI_SCROLL_TO=<anchor>`, `docs/testing.md`) already use. They are listed here rather
    /// than left implicit in the view tree so that `section(owning:)` below cannot fall out
    /// of step with them — a hook that scrolls to an anchor on an unselected tab reaches
    /// nothing at all, silently, and produces a screenshot of the wrong screen.
    public var anchors: [String] {
        switch self {
        case .mapSpeed: ["chart", "replay", "Foil", "summary"]
        case .turns: ["turns", "filters", "tally", "turnsMap", "turnList"]
        case .takeoffs: ["takeoff"]
        case .effort: ["hr", "gear"]
        }
    }

    /// Which section an anchor lives on, or nil for an anchor that belongs to none of them.
    ///
    /// nil is a real answer and the callers rely on it: `key` is the key-metrics block,
    /// which is above the switcher and therefore on *every* section, so asking to scroll to
    /// it must not change the selected tab.
    public static func section(owning anchor: String) -> SessionSection? {
        allCases.first { $0.anchors.contains(anchor) }
    }
}
