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
    /// personal app, so this is the supported way to get your own FITs onto the phone.
    public static let rationale =
        "WingFoil reads your sessions through intervals.icu. Garmin has no open API for a "
        + "personal app, so intervals.icu is the bridge: it receives every activity from "
        + "Garmin Connect automatically and hands WingFoil the original recording. It is "
        + "free, it takes about five minutes to set up, and you only do it once."

    /// The same point in one breath, for the setup card — where the four steps below it
    /// are what the reader is actually there for.
    public static let rationaleShort =
        "Garmin has no open API for a personal app, so intervals.icu is the bridge: free, "
        + "automatic once connected, and set up only once."

    public static let steps: [IcuSetupStep] = [
        IcuSetupStep(
            number: 1,
            title: "Create a free intervals.icu account",
            detail: "Open intervals.icu and sign up — it is free, and you can use the "
                + "Google, Strava or e-mail account you already have.",
            link: HelpLink(title: "Open intervals.icu", url: intervalsURL)),

        IcuSetupStep(
            number: 2,
            title: "Connect Garmin in intervals.icu",
            detail: "In intervals.icu go to Settings and connect your Garmin account under "
                + "the device connections. Your existing Garmin activities are back-filled "
                + "once the connection is made — with a long history that can take a few "
                + "minutes — and every session you record from then on arrives on its own "
                + "as soon as your watch syncs.",
            link: HelpLink(title: "Open intervals.icu settings", url: intervalsURL)),

        IcuSetupStep(
            number: 3,
            title: "Generate your personal API key",
            detail: "Still in intervals.icu: Settings → Developer Settings → API Key. "
                + "Copy the key. Developer settings are free for every intervals.icu user — "
                + "no subscription is needed.",
            link: HelpLink(title: "Open intervals.icu settings", url: intervalsURL)),

        IcuSetupStep(
            number: 4,
            title: "Paste the key into WingFoil",
            detail: "Paste it into the field below (in the app it also lives under "
                + "Settings → intervals.icu) and tap Save & check. WingFoil verifies the "
                + "key straight away and says how many activities it can see.",
            action: .openIcuSettings),
    ]

    /// Where the key lives and where it goes. Shown under the field as well as in Help —
    /// a secret you are asked to paste deserves an answer before you have to ask.
    public static let privacyNote =
        "Your API key is stored in this iPhone's Keychain. It is never copied to iCloud, "
        + "never sent to any WingFoil server — there isn't one — and never written to a "
        + "log. The only place it is ever sent is intervals.icu itself, over HTTPS, to ask "
        + "for your own activities. Clear the field in Settings to remove it, or regenerate "
        + "it in intervals.icu, which makes the old one useless."

    /// What goes wrong, and what to do about it. Also the body of the troubleshooting topic.
    public static let troubleshooting: [HelpTopic.Item] = [
        .init(term: "\"intervals.icu rejected the API key\"",
              detail: "A 401 means the key is wrong or was regenerated after you pasted it. "
                  + "Copy it again from intervals.icu → Settings → Developer Settings and "
                  + "paste it fresh — a stray space at either end is enough to break it."),
        .init(term: "The sync succeeds but the list stays empty",
              detail: "Either Garmin is not connected in intervals.icu yet (Settings → "
                  + "device connections — the back-fill takes a few minutes), or none of "
                  + "your activities is a watersport yet. WingFoil only pulls Windsurf, "
                  + "Kitesurf, Sail, Surfing and SUP activities, plus anything whose name "
                  + "mentions wing, foil, surf, kite or SUP."),
        .init(term: "\"Could not reach intervals.icu\"",
              detail: "A network problem rather than a key problem: nothing was lost and "
                  + "nothing was half-imported. Check your connection and sync again."),
        .init(term: "Older sessions are missing",
              detail: "The sync looks two years back and skips anything already in the "
                  + "library. For a longer history use Import → Garmin export ZIP, which "
                  + "reads the original FIT of every activity you ever uploaded."),
    ]
}
