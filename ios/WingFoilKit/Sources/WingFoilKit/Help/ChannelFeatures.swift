import Foundation

/// **What is in this build, and what is in the next one** — the rider-facing half of
/// docs/channels.md.
///
/// That file is the single source for which feature sits in which channel; this is the same
/// list in the rider's words, written *from* it and never the other way round. Its
/// machine-readable twin is `docs/copy/channels.json`, and `CopyContractTests` fails until
/// the two agree — which is what keeps the website's "what is coming" list, the App Store
/// copy and these rows from drifting apart the way they did on 14 September 2026.
///
/// Two app surfaces read it (`BetaSectionView.swift`):
///
/// * **Settings → Beta** — beta and dev only. What the tester has that the App Store build
///   does not, so a report can say "the video export" rather than "the thing that makes a
///   film".
/// * **"Coming in a future release"** — every channel. What is being tried before it
///   arrives here. In the release it carries the TestFlight link, because there the answer
///   to "can I have it" is one tap; in the beta it is the same list with no link, plus the
///   dev doors under it.
///
/// It lives in the kit rather than in the app for the ordinary reason: it is copy, the test
/// suite reads it, and the app target cannot be seen from a kit test.
public enum ChannelFeatures {

    /// **"Coming in a future release"** — one name, used by the Settings row, the page
    /// title, docs/presentation.md and the website's own section heading.
    ///
    /// Two renamings in two days, both from what a rider actually reads. It said *"Curious
    /// about what is coming"* until 14 September 2026 — an App Store app that opens by
    /// being curious about itself reads as an apology — and then *"What is being tested"*
    /// until 15 September, which describes the *room* rather than the reader's question.
    /// What he is asking is when he gets these things, so the row answers that.
    public static let sectionTitle = "Coming in a future release"

    /// The beta doors, one sentence each, in the order docs/channels.md lists them: getting
    /// a session in, the library, sharing, the watches.
    ///
    /// **This list is docs/channels.md's beta rows and nothing else.** A row that is not in
    /// that table is a promise nobody made; the Garmin export ZIP left this list on
    /// 14 September 2026 when it became a release feature, and the release's own Import
    /// screen has offered it all along ("FIT or ZIP…").
    public static let beta: [String] = [
        ".gpx and .tcx files, so a session exported from a Polar, a Suunto or a COROS "
            + "opens straight from Files.",
        "Apple Health, both ways: what Apple's Workout app recorded is read in, and your "
            + "sessions are written back as workouts.",
        "The CleanJibe Apple Watch app, which records on your wrist with live numbers and "
            + "hands the session to the phone.",
        "Home-screen widgets and the watch complication.",
        "The session video: your afternoon as a film rather than a card.",
        "Grouping the library by month, year or spot, and filtering it.",
    ]

    /// The dev doors. Unproven by construction — a handful of hand-picked testers — and
    /// listed so a rider can ask for one rather than discover it does not exist.
    ///
    /// **Beta and dev only.** None of these is promised to anybody on the App Store: the
    /// release build lists what is being tested one channel up, and nothing beyond it.
    public static let dev: [String] = [
        "The Garmin link: a summary card from your watch the moment you stop, the map of "
            + "your spot and the wind direction sent back to it",
        "Windsurf, foil and fin, with thresholds of its own",
        "The tuning page: every analysis threshold on a slider, tried against your own "
            + "sessions",
        "iPad",
    ]
}
