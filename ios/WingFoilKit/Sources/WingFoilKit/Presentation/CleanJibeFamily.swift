import Foundation

/// **The CleanJibe family** — the apps on one engine, and which one the rider is holding.
///
/// A rider meets one of them first and has no way of knowing the others exist. It was a
/// menu row and a screen of its own until 25 September 2026, and is now a section of
/// *What CleanJibe does* on both shells: the question it answers is the second half of
/// that page's, and the screen on its own was too short to earn a door (Jan, F4).
///
/// It is copy, so it lives here rather than in either app, and both shells read it:
/// `docs/copy/app-shell.json` carries it for the browser and
/// `web/tools/verify_app_shell.py` holds the two sides together, the way it already holds
/// the tabs, the menu rows and the session sub-tabs.
///
/// **Register 1** (docs/voice.md): short imperatives, one thought a sentence, no dashes.
/// Under 120 words the whole section, because a rider reading it wants the shape of the
/// product and not its history.
///
/// **No install link leaves it.** Every app named here is reached from a store the rider
/// is already in, or from the page he is already on. The one link is the beta's, on the
/// Apple Watch app, in the channel that is not in the beta yet.
///
/// **The direct Garmin link is not named.** It is a dev door (docs/channels.md), and text
/// that lists doors takes the channel that asks (docs/review-checklist.md, pattern D). The
/// route every rider actually has is intervals.icu, so that is the route this says.
public enum CleanJibeFamily {

    /// The section's title on *What CleanJibe does*, where the family has lived since
    /// 25 September 2026 (Jan: "merge it in if it fits" — it fits).
    public static let title = "The CleanJibe family"

    /// One sentence, before the apps. No number since the Apple Watch app joined: a count
    /// in the headline is one more thing to go stale.
    public static let intro = "CleanJibe is a family of apps on one analysis engine."

    /// Which of the apps the rider is reading this on. Each shell answers for itself, so
    /// the sentence is written once and the answer is not.
    public static let here = "You are using this one now."

    /// The badge on an app that is in the beta. The Apple Watch app is "in beta"
    /// everywhere it is named (Jan, 24 September 2026).
    public static let betaBadge = "Beta"

    /// The link that replaced the travel notes: how a session gets from the watch into the
    /// app is Getting started's job, and a second telling here drifted from it.
    public static let howSessionsGetIn = "How your sessions get in"

    /// One of the apps.
    public struct App: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let line: String
        /// In the beta, not yet in the App Store release (docs/channels.md).
        public let beta: Bool

        public init(id: String, title: String, line: String, beta: Bool = false) {
            self.id = id
            self.title = title
            self.line = line
            self.beta = beta
        }
    }

    /// The apps, watch first, then the two that read a session, then the beta one.
    ///
    /// **Honest about each.** The Garmin app analyses on the wrist; the Apple Watch app only
    /// records, and the phone does the analysis; the browser has most of the analysis but
    /// not all of it (F4, 25 September 2026).
    public static let apps: [App] = [
        App(id: "garmin", title: "Garmin watch app",
            line: "It records on your wrist, with live numbers and a summary when you save."),
        App(id: "iphone", title: "iPhone app",
            line: "It reads every session from Garmin, Strava and other watches, judges "
                + "every turn and keeps your library."),
        App(id: "browser", title: "Browser app",
            line: "Most of the same analysis in a browser tab. Drop a file in or import from "
                + "intervals.icu, with no account."),
        App(id: "appleWatch", title: "Apple Watch app",
            line: "It records your session on the wrist. The analysis happens on the iPhone.",
            beta: true),
    ]
}
