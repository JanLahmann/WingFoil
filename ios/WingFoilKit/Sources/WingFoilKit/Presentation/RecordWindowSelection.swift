import Foundation

/// Which GP3S window is currently glowing on the map and shading the chart.
///
/// The engine already computed a window (`records.windows`) for every record it could
/// produce, so "show me where the best 10 s happened" is a *selection*, not a calculation.
/// This type is the selection rule, kept out of the view because it has three edges worth
/// a test: the default, the tap-again-to-go-back, and the records that have no window at
/// all.
///
/// **Deliberately transient.** The choice is not persisted the way the legend chips are: a
/// rider who once looked at their best 1 NM does not want every future session to open on
/// it. Each session detail starts on the default and forgets.
public enum RecordWindowSelection {

    /// What every session opens on. The 2 s peak is the number riders quote at each other,
    /// so it is the one the map answers with until asked otherwise.
    public static let defaultKey = RecordKind.best2s.rawValue

    /// The order the record rows are laid out in, shortest window first, with the two
    /// composite records (5 × 10 s and the alpha) beside the plain window they are built
    /// from.
    ///
    /// **`bestHour` joined the other eight on 21 September 2026.** It was left out while it
    /// was unreachable: an hour-long window covers most of a two-hour afternoon, and the
    /// argument was that a glow over most of the track says nothing. It says what the record
    /// is. The hour the engine picked started somewhere, ended somewhere, and the rider was
    /// riding for the rest of the session without it — that is a fact about the afternoon,
    /// and hiding it made the ninth row the one row in the table that did not answer a tap.
    /// The corpus got its first best hour with engine 0.23.0 (`2026-08-03-1440`, 6.746 kn,
    /// an hour out of 7 135 s) and Smart Recording sessions produce them regularly.
    public static let catalogue: [RecordKind] = [
        .best2s, .best10s, .best5x10s, .best100m, .best250m, .best500m, .bestNm, .bestHour,
        .alpha500,
    ]

    /// The selection a freshly opened session starts with: the default when the session
    /// produced it, otherwise nothing rather than an arbitrary substitute — a map that
    /// silently highlighted the best 1 NM because there was no 2 s would be lying about
    /// what the rider asked for.
    public static func initial(available: Set<String>) -> String? {
        available.contains(defaultKey) ? defaultKey : nil
    }

    /// The new selection after a record card is tapped.
    ///
    /// Tapping the card that is already selected goes **back to the default**, not to
    /// nothing: the glow is the map's way of saying "here is your best run", and the way
    /// out of a non-default choice should return the page to the state it opened in. Only
    /// re-tapping the default itself clears the glow entirely.
    ///
    /// A record with no window is not tappable, so a tap on one leaves the selection
    /// exactly as it was — the view disables the card, and this makes that harmless even
    /// if it ever forgets to.
    public static func tapped(_ key: String, current: String?,
                              available: Set<String>) -> String? {
        guard available.contains(key) else { return current }
        guard key == current else { return key }
        guard key != defaultKey else { return nil }
        return initial(available: available)
    }
}
