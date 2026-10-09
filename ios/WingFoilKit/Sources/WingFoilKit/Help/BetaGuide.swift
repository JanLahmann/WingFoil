import Foundation

/// **The Beta page** — what the beta is, what is in it now, how to join, how to tell us.
///
/// New on 25 September 2026 (Jan's plan of 24 September, section 5). It is reached from
/// the menu's last row, the footer of *What CleanJibe does*, the Apple Watch app's card in
/// the family section and, in the beta and the dev build, every *Beta* chip on a feature
/// the App Store build has not got. The words are here, in the kit, so the voice lint
/// reads them and the website's twin can be held to them.
///
/// **Gated by the channel the app hands in** (docs/channels.md). The release build asks
/// the rider to join and carries the public TestFlight link; the beta and the dev build say
/// "You are in the beta", carry no join step, and ask the two questions a tester can
/// answer: how it works, and what we should test next.
///
/// **What is in it** is `ChannelFeatures.beta`, the one list docs/channels.md is written
/// into. This page does not keep a second one.
///
/// **Community driven** (Jan, 30 September 2026): features land in the beta fast and move
/// to the release once testers prove them. `community` is that sentence, written once; the
/// Beta page, the welcome's footer, *Coming in a future release*, the homepage, the web's
/// Beta page and the TestFlight notes all say it from here.
public enum BetaGuide {

    /// The release's title, and the menu row's everywhere a rider is not in the beta yet.
    public static let joinTitle = "Join the beta"
    /// The beta's and the dev build's title.
    public static let insideTitle = "You are in the beta"

    public static func title(for channel: HelpChannel) -> String {
        channel == .release ? joinTitle : insideTitle
    }

    /// **The one sentence of the community message.** Every surface that says what the beta
    /// is for says this, in these words.
    public static let community =
        "CleanJibe is built with its riders. New features land in the beta first, and move "
        + "to the App Store once testers have proven them."

    public static let inItNowTitle = "In the beta right now"

    public static let howToJoinTitle = "How to join"
    /// **Back up first** (rider review I6, Jan 9 Oct 2026). This page used to end on "You
    /// can go back to the App Store version whenever you like", and a tester who did met the
    /// *newer CleanJibe* screen: a beta that has moved the library to a newer schema leaves
    /// an older App Store build unable to open it (`LibraryNewerThanApp`), and a backup the
    /// beta writes at that schema is refused by the same build
    /// (`LibraryBackupManifest.compatibility`). So the step before TestFlight is a backup
    /// made with the App Store version, the one file that build can always restore.
    public static let backupFirst =
        "Back up first, in Settings → Library backup. Save the file in Files or iCloud Drive."
    public static let howToJoin = [
        backupFirst,
        "Tap Open TestFlight. Apple's TestFlight app then installs the beta in place of this "
            + "app.",
        "Your sessions, spots and gear come with you.",
    ]
    public static let joinButton = "Open TestFlight"

    /// **Going back**, on the Beta page in the release and the beta (not dev, a second app
    /// with its own library): the release says it before the rider joins, the beta says it
    /// when he wants out. What the App Store version does with a library the beta has moved
    /// on is the blocking screen's (`leavingTheBeta`), said here in the order a rider meets
    /// it.
    public static let goingBackTitle = "Going back to the App Store version"
    public static let goingBack = [
        "Back up in the beta first, then install CleanJibe from the App Store.",
        "If the beta has updated your library, the App Store version cannot open it yet. "
            + "Open the beta again, or restore a backup made before you joined.",
    ]
    /// The blocking screen's line for a rider who wants the App Store version for good. A
    /// beta backup at a newer schema is refused today and opens in the first App Store
    /// update that has caught up, which is what "a later update" promises and no more.
    public static let leavingTheBeta =
        "Leaving the beta for good? Back up there first. A later App Store update opens "
        + "that backup."
    /// The way to the `libraryBackup` help topic from the Beta page and the blocking screen.
    public static let backupHelpLabel = "How to back up"

    /// The beta's two questions, as the page's two buttons. The first opens the feedback
    /// sheet at the beta features' ticks, the second at the free line for an idea.
    public static let tellHowItWorks = "Tell us how it works"
    public static let whatNext = "What should we test next?"

    /// The chip on every beta feature in the beta and the dev build. A tap opens this page.
    public static let chip = CleanJibeFamily.betaBadge
    public static let chipHint = "Opens the Beta page"

    /// **The last line of What's new**, from here rather than from any one entry, so every
    /// build's notes end on the same ask. The beta asks for the mail; the release names the
    /// way in.
    public static let whatsNewBeta =
        "Tried it? Tell us in Menu → Support & ideas. Every mail shapes the next build."
    public static let whatsNewRelease = "Want new features first? Menu → Join the beta."

    public static func whatsNewClosing(for channel: HelpChannel) -> String {
        channel == .release ? whatsNewRelease : whatsNewBeta
    }
}
