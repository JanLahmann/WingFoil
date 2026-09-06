import Foundation

/// The four subjects a session view is divided into, and the rule for which one owns a
/// given anchor.
///
/// The session page was one column of roughly 3 800 pt — a little over four full phone
/// screens — with five unrelated subjects stacked in it and no way to reach the fifth except
/// by scrolling through the other four (`docs/app-ui-review.md` §3.1). It is a switcher now,
/// and this is the model half of that switcher: the cases, their words, and the mapping from
/// a section anchor to the tab it lives on. The views are layout over this.
///
/// **The split is between the figures and the cards, and that is not a matter of taste.**
/// `docs/presentation.md` "Scrub and zoom" mandates one playhead — the chart's scrub
/// position and the map's dot are the same timestamp, and moving either moves both — and
/// "Pairing" adds that tapping a flown stretch of track focuses the chart on that flight. Map
/// and chart are one instrument. A tab set that gives Map a page of its own breaks the
/// visible half of that link: you tap a segment, and the chart it focused is somewhere else.
/// So `ride` carries both figures and everything that annotates them, permanently.
///
/// **Re-cut 6 Sep 2026 (Jan).** The four were `Map · Speed | Turns | Takeoffs | Effort`, and
/// two of those names were describing the wrong thing:
///
/// * **Takeoffs and Effort were one subject split by sensor.** The takeoff tiles counted
///   attempts off the accelerometer and the HR card priced the same attempts off the heart
///   rate — "how many did I have to pump for" and "what did the pumping cost" are the same
///   question asked twice, and the app was answering them on two tabs. The word gave it
///   away: "effort" was already the map legend's name for the GP3S record window, so the tab
///   called Effort was competing for a word the map had spent. The HR card moved under the
///   takeoff tiles and lost the redundant half of its title.
/// * **The session's own facts had nowhere to live.** The recording's provenance, the wind
///   the analysis assumed and the watch-vs-phone divergences were a footer under every tab
///   and a disclosure inside a warning banner — three facts about the *record* filed as
///   furniture. `log` is where they are, with the gear card that was already the same kind
///   of fact.
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
    case ride
    /// The turn cards, with the filtered tally/map/list folded in underneath them — it was
    /// a pushed page two taps and ~2 400 pt deep (§2.1).
    case turns
    /// Every attempt to get up: the takeoff and pumping tiles, the attempt map and list, and
    /// what the pumping cost in heartbeats.
    case takeoffs
    /// The session's own facts: the kit it was ridden on, the wind the analysis assumed,
    /// where the recording came from, and where the watch and the phone disagree.
    case log

    public var id: String { rawValue }

    /// The switcher's words. One short noun each, which is what lets four segments fit
    /// across a 390 pt phone without truncating.
    ///
    /// "Ride" replaced "Map · Speed" when the fourth tab became "Log": the middle dot was
    /// load-bearing while the name was a list of two figures, and it is dead weight beside
    /// three one-word siblings. The tab is the ride — where it went and how fast — and the
    /// two figures on it are how it says so.
    public var label: String {
        switch self {
        case .ride: "Ride"
        case .turns: "Turns"
        case .takeoffs: "Takeoffs"
        case .log: "Log"
        }
    }

    /// The scroll anchors each section contains, in the order they appear on it.
    ///
    /// These are the ids the views attach with `.id(_:)` and the names the screenshot hooks
    /// (`UI_SCROLL_TO=<anchor>`, `docs/testing.md`) already use. They are listed here rather
    /// than left implicit in the view tree so that `section(owning:)` below cannot fall out
    /// of step with them — a hook that scrolls to an anchor on an unselected tab reaches
    /// nothing at all, silently, and produces a screenshot of the wrong screen.
    ///
    /// **Every anchor that existed before the re-cut still resolves**; two of them changed
    /// tab rather than name. `hr` is on Takeoffs now (the HR card sits under the takeoff
    /// tiles) and `gear` is on Log. A deep link that predates the change lands on the right
    /// card on the right tab, which is the whole reason the mapping is data.
    public var anchors: [String] {
        switch self {
        case .ride: ["chart", "replay", "Foil", "summary"]
        case .turns: ["turns", "filters", "tally", "turnsMap", "turnList"]
        case .takeoffs: ["takeoff", "takeoffFilters", "takeoffsMap", "takeoffList", "hr"]
        case .log: ["gear", "wind", "recording", "divergence"]
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

    /// **The one routing rule**: what a jump to `anchor` has to do to the switcher first.
    ///
    /// A scroll to an anchor on an unselected tab reaches nothing — the tab's subtree does
    /// not exist yet — so every deep link, every screenshot hook and the divergence banner's
    /// "show me" tap ask this first. nil means "do not touch the switcher", and it is the
    /// answer in the two cases that matter as much as the redirect: the anchor is already on
    /// the selected tab, or it is on no tab at all (`key`, above the switcher, on all four).
    /// Returning the current tab instead would make a jump to the key metrics look like a
    /// section change to anything watching the selection.
    public static func tabChange(for anchor: String, current: SessionSection)
        -> SessionSection? {
        guard let home = section(owning: anchor), home != current else { return nil }
        return home
    }
}
