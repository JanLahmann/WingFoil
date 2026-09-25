import Foundation

/// One numbered step of the intervals.icu setup.
public struct IcuSetupStep: Sendable, Equatable, Identifiable {
    public let number: Int
    public let title: String
    public let detail: String
    /// An external page the step sends you to (intervals.icu itself).
    public let link: HelpLink?
    /// An in-app destination the step offers as a button.
    public let action: HelpAction?

    public var id: Int { number }

    public init(number: Int, title: String, detail: String,
                link: HelpLink? = nil, action: HelpAction? = nil) {
        self.number = number
        self.title = title
        self.detail = detail
        self.link = link
        self.action = action
    }
}

/// The intervals.icu onboarding, written once as data.
///
/// Two places show these steps — the Help topic and the empty-library setup card — and a
/// first-run instruction that is right in one place and stale in the other is worse than
/// no instruction at all. The wording therefore lives here, in the kit, where the test
/// suite can assert it is actually written and the numbering is sound.
public enum IcuSetupGuide {

    public static let intervalsURL = URL(string: "https://intervals.icu")!

    /// Why the detour through intervals.icu exists at all — Garmin has no open API for a
    /// personal app, so this is the *automatic* way to get your own FITs onto the phone.
    ///
    /// It used to open "CleanJibe reads your sessions through intervals.icu", which is not
    /// true: a shared `.fit` and a Garmin export ZIP both work, and a rider who does not
    /// want a third-party account read that sentence as a wall. The alternatives are named
    /// here rather than left to a troubleshooting item at the bottom of a different topic.
    public static let rationale =
        "The easiest way in is intervals.icu. Garmin has no open API, so intervals.icu "
        + "receives your activities and hands CleanJibe the original recording. You can "
        + "also open a .fit by hand, from Files, Mail or a Garmin export ZIP."

    /// The same point in one breath, for the setup card — where the four steps below it
    /// are what the reader is actually there for.
    ///
    /// **It is the Settings caption, not a second wording of it.** The sentence's home is
    /// `docs/guide/getting-started.json` → `settings.intervalsIcu`, which the generator
    /// writes into `GettingStartedGuide.settingsIcu`; the setup card and the caption above
    /// the key field then say the same thing letter for letter (pattern F,
    /// `docs/copy/check_duplicates.py`).
    public static let rationaleShort = GettingStartedGuide.settingsIcu

    /// The label on the button the last step tells the reader to tap, and the label the
    /// button itself carries (`IcuKeyEntry`). Two literals is how a walkthrough ends up
    /// naming a button that was renamed — so it is written once, here, and
    /// `docs/copy/icu-setup.json` carries it to cleanjibe.org/start, which told riders to
    /// "use the check button" until 15 September 2026.
    public static let saveButton = "Save & check"

    public static let steps: [IcuSetupStep] = [
        IcuSetupStep(
            number: 1,
            title: "Create a free intervals.icu account",
            detail: "Open intervals.icu and sign up. It is free, and the Google, Strava or "
                + "e-mail account you already have will do.",
            link: HelpLink(title: "Open intervals.icu", url: intervalsURL)),

        IcuSetupStep(
            number: 2,
            title: "Connect Garmin in intervals.icu",
            detail: "In intervals.icu, Settings → device connections: connect your Garmin "
                + "account. Your history back-fills in a few minutes, and every new session "
                + "arrives on its own.",
            link: HelpLink(title: "Open intervals.icu settings", url: intervalsURL)),

        IcuSetupStep(
            number: 3,
            title: "Generate your personal API key",
            detail: "Still in intervals.icu: Settings → Developer Settings → API Key. "
                + "Copy it. Developer settings are free for every user. No subscription is "
                + "needed.",
            link: HelpLink(title: "Open intervals.icu settings", url: intervalsURL)),

        IcuSetupStep(
            number: 4,
            title: "Paste the key into CleanJibe",
            detail: "Paste it into the field below. In the app that field is "
                + "Settings → intervals.icu. Tap " + saveButton
                + ". CleanJibe verifies it and says how many activities it can see.",
            action: .openIcuSettings),
    ]

    /// Where the key lives and where it goes. Shown under the field as well as in Help —
    /// a secret you are asked to paste deserves an answer before you have to ask.
    public static let privacyNote =
        "Your API key is stored in this iPhone's Keychain. It is never copied to iCloud and "
        + "never written to a log. There is no CleanJibe server to send it to. It goes to "
        + "intervals.icu itself, encrypted, and nowhere else."

    /// What goes wrong, and what to do about it. Also the body of the troubleshooting topic.
    public static let troubleshooting: [HelpTopic.Item] = [
        .init(term: "\"intervals.icu rejected the API key\"",
              detail: "The key is wrong, or you made a new one after pasting it. Copy it "
                  + "again from intervals.icu, Settings → Developer Settings. A stray space "
                  + "at either end breaks it."),
        .init(term: "The sync succeeds but the list stays empty",
              detail: "Either Garmin is not connected in intervals.icu yet, or none of your "
                  + "activities is a watersport. CleanJibe takes Windsurf, Kitesurf, Sail, "
                  + "Surfing, SUP and anything named wing or foil."),
        .init(term: "\"Could not reach intervals.icu\"",
              detail: "The connection dropped, and your key is fine. Nothing was lost or "
                  + "half-imported. Check your connection and sync again."),
        .init(term: "Older sessions are missing",
              detail: "The sync looks two years back and skips what the library already "
                  + "holds. For more, use Import → FIT or ZIP… with the Garmin export ZIP."),
    ]
}
