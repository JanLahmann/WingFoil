import Foundation

/// **The CleanJibe family** — the three apps, and how a session gets from one to the next.
///
/// A rider meets one of them first and has no way of knowing the other two exist. The
/// website says so to a stranger; inside the apps nothing did, so a Garmin rider with the
/// watch app never learnt that the same afternoon opens in a tab, and a browser visitor
/// never learnt that the phone keeps a library. It is one menu row on both shells now,
/// under *What CleanJibe does*, which is the question it answers the second half of.
///
/// It is copy, so it lives here rather than in either app, and both shells read it:
/// `docs/copy/app-shell.json` carries it for the browser and
/// `web/tools/verify_app_shell.py` holds the two sides together, the way it already holds
/// the tabs, the menu rows and the session sub-tabs.
///
/// **Register 1** (docs/voice.md): short imperatives, one thought a sentence, no dashes.
/// Under 120 words the whole screen, because a rider opening it wants the shape of the
/// product and not its history.
///
/// **No link leaves it.** Every app named here is reached from a store the rider is
/// already in, or from the page he is already on, and a list of three apps with three
/// install links on it is an advertisement rather than an answer.
///
/// **The direct Garmin link is not named.** It is a dev door (docs/channels.md), and text
/// that lists doors takes the channel that asks (docs/review-checklist.md, pattern D). The
/// route every rider actually has is intervals.icu, so that is the route this says.
public enum CleanJibeFamily {

    /// The screen's title, and the menu row's (`AppMenuRow.family`).
    public static let title = "The CleanJibe family"

    /// One sentence, before the three.
    public static let intro = "CleanJibe is three apps on one analysis engine."

    /// Which of the three the rider is reading this on. Each shell answers for itself, so
    /// the sentence is written once and the answer is not.
    public static let here = "You are using this one now."

    /// One of the three apps.
    public struct App: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let line: String
    }

    /// The three, in the order a session travels through them.
    public static let apps: [App] = [
        App(id: "garmin", title: "Garmin watch app",
            line: "Records on your wrist. Live numbers, and a summary when you save."),
        App(id: "iphone", title: "iPhone app",
            line: "Reads every session, judges every turn, keeps your library."),
        App(id: "browser", title: "Browser app",
            line: "The same analysis in a tab. Drop a file, no account."),
    ]

    /// How a session gets from one of them to the next.
    public static let travel = [
        "A session leaves the watch through intervals.icu and lands on the phone.",
        "The phone and the browser trade sessions as files.",
        "The CleanJibe Apple Watch app records too. It is in the beta.",
    ]
}
