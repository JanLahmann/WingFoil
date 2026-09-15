import Foundation

/// **What Records and Trends say to a rider whose only session is the example.**
///
/// The one-tap happy path — install, *Try the example session*, an analysed session in
/// front of you — ended on two screens that blamed a filter the rider never set. Records
/// said *"No qualifying speed window under this filter"* with no filter applied, and Trends
/// said *"Widen the range or clear the spot and gear filters"* on a library that held one
/// row, whose range and filters could not have helped: the example is excluded from both by
/// `LibraryStore.clause` (`isExample = 0`), deliberately, because it is not the rider's
/// riding and a personal best is a claim about a person.
///
/// That exclusion was written down for Apple's reviewer (`ios/store/appstore.md`) and for
/// nobody else. These are the same fact in the rider's words, with the step that changes
/// it — which is the only thing either screen can usefully offer, since no control on
/// either screen can.
///
/// Three rules, the same three `NotASessionNote` keeps:
///
/// * **It never blames a control the rider did not touch.** The filter message stays, for
///   the case where a filter *is* set; this is the other case, and it is not a filter.
/// * **It says why, not just what.** "On loan, not ridden" is the whole reason, and it is
///   also the reason the rider would give himself.
/// * **It ends on the next step**, which is a session of his own, by either door.
public enum ExampleOnlyNote {

    /// The Records screen's title. Not "No records yet": there is nothing wrong, and the
    /// records are not missing — they have not been earned yet, which is a promise rather
    /// than a fault.
    public static let recordsTitle = "Your records start with your first session"

    /// The Records screen's line.
    public static let records =
        "The example session is on loan, not ridden, so it is kept out of your personal "
        + "records on purpose. Import a .fit file, or connect intervals.icu in Settings, "
        + "and your own bests appear here."

    /// The Trends screen's title. The range picker is innocent, so the title does not
    /// mention a range.
    public static let trendsTitle = "Your trends start with your first session"

    /// The Trends screen's line. Same reason, same two doors, different promise: trends
    /// need more than one session before they are a line rather than a dot.
    public static let trends =
        "The example session is on loan, not ridden, so it is kept out of your trends on "
        + "purpose. Import a .fit file, or connect intervals.icu in Settings, and the "
        + "charts fill as you ride."
}
