import Foundation

/// **The Beta page** — what the beta is, what is in it now, how to join, how to tell us.
///
/// New on 25 September 2026 (Jan's plan of 24 September, section 5). It is reached from
/// three places: the menu's last row, the footer of *What CleanJibe does*, and the Apple
/// Watch app's card in the family section. The words are here, in the kit, so the voice
/// lint reads them and the website's twin can be held to them.
///
/// **Gated by the channel the app hands in** (docs/channels.md). The release build asks
/// the rider to join and carries the public TestFlight link; the beta and the dev build say
/// "You are in the beta" and carry no join step, because the link would point the reader at
/// the build he is holding.
///
/// **What is in it** is `ChannelFeatures.beta`, the one list docs/channels.md is written
/// into. This page does not keep a second one.
public enum BetaGuide {

    /// The release's title, and the menu row's everywhere a rider is not in the beta yet.
    public static let joinTitle = "Join the beta"
    /// The beta's and the dev build's title.
    public static let insideTitle = "You are in the beta"

    public static func title(for channel: HelpChannel) -> String {
        channel == .release ? joinTitle : insideTitle
    }

    /// What the beta is, in the release.
    public static let whatItIs =
        "The beta is the next CleanJibe, a few weeks early. New features are ridden there "
        + "first, by riders who want them sooner."

    /// The same paragraph in the beta and the dev build.
    public static let insideLede =
        "Thanks for riding it. Everything on the list below is in your build already."

    public static let inItNowTitle = "In the beta right now"

    public static let howToJoinTitle = "How to join"
    public static let howToJoin = [
        "Tap Open TestFlight. Apple's TestFlight app then installs the beta in place of this "
            + "app.",
        "Your sessions, spots and gear stay where they are. You can go back to the App Store "
            + "version whenever you like.",
    ]
    public static let joinButton = "Open TestFlight"

    public static let feedbackTitle = "How to give feedback"
    public static let feedback = [
        "Menu → Support & ideas writes a mail to us. Say what you liked, what read wrong and "
            + "what you want next.",
        "In the beta, TestFlight's own feedback works too. Take a screenshot and tap Share "
            + "Beta Feedback.",
    ]
    public static let feedbackButton = "Send us your ideas"
}
