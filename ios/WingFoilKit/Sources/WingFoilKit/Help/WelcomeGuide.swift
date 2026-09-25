import Foundation

/// One line of the welcome screen's vocabulary: the word, and what it means here.
public struct WelcomeHighlight: Sendable, Equatable, Identifiable {
    public let term: String
    public let detail: String

    public var id: String { term }

    public init(term: String, detail: String) {
        self.term = term
        self.detail = detail
    }
}

/// What the app says about itself the first time it is opened.
///
/// A first run used to open on the intervals.icu setup card — four steps, a key field, and
/// no answer at all to the question the rider actually has, which is *what does this thing
/// do*. The card is still the setup path; this is the sentence in front of it.
///
/// The wording lives in the kit for the same reason `IcuSetupGuide`'s does: it is the copy
/// nobody reads twice, so nothing but a test will ever notice it has gone stale or empty.
/// It is deliberately the same vocabulary the homepage (web/index.html) and the Help
/// catalogue use — foil %, flights and touchdowns, jibe outcomes, dry streaks, records —
/// because a rider who read one of them should not have to learn a second set of words.
public enum WelcomeGuide {

    /// The one line at the top: the tagline (Jan, 23 September 2026), the one fragment the
    /// voice allows under the wordmark. It said "Every flight, every jibe, every swim." until
    /// 25 September 2026; the start screen and every page of the site already said this.
    public static let headline = Branding.tagline

    /// **The one sentence that says what CleanJibe is**, and the one this project has
    /// hand-copied most often: the homepage's opening, the App Store description's first
    /// line, the Connect IQ listing, and the library's empty state all say it.
    ///
    /// Four copies of one sentence, written once on 2 September 2026 and pasted onwards, is
    /// exactly the shape of drift that `docs/copy/phrases.json` now pins: this is the
    /// authored text and the JSON its twin (`CopyContractTests`), and the website is held to
    /// it from the other side. The store voice may put its own paragraph around it; the
    /// sentence itself is one sentence everywhere.
    public static let promise =
        "Did you fly through that jibe? CleanJibe reads your session off the watch. It tells "
        + "you your time on the foil, every flight, your speed records, and a verdict on "
        + "every turn. Flew through, touchdown, or fell in."

    /// One tight paragraph of what the app actually does, in the order the rider meets it:
    /// detection first (nothing else is possible without it), then the counts, then the
    /// verdicts, then the records, then the replay.
    public static let lede =
        "CleanJibe shows your time on the foil, every flight and every touchdown. Each jibe "
        + "gets a verdict: flew through, touched down, or fell in. You see your dry streak "
        + "and your fastest seconds. The replay comes with a commentary."

    /// The vocabulary, four lines of it. Enough that the words on the session page are
    /// already familiar; short enough that nobody skips the screen to escape it.
    ///
    /// **Selected from `MetricGlossary`, never retyped.** The eight glossary lines are the
    /// app's and the website's shared one-liners; the welcome screen shows the four a
    /// first-time reader needs before he has seen a session, and the other four
    /// (turn verdicts, JPH, CPH, WPH) are rates he meets later. The verdicts themselves are
    /// in the `lede` above, which is why the streak line can be the short one.
    ///
    /// The dry streak used to read "how many you *carried* in a row", which is engine
    /// vocabulary the rider is never shown (CLAUDE.md); the glossary's line is the web's,
    /// and says the same thing in the words the product uses.
    public static let highlights: [WelcomeHighlight] = [
        "foilShare",
        "flights",
        "dryStreak",
        // "GP3S" and "alpha 500" are GPS-speedsurfing terms, and this is the fourth line of
        // the first screen a wingfoiler ever sees. The windows are named instead; the
        // Records topic can teach the vocabulary later, to somebody who asked for it.
        "speedRecords",
    ].map {
        let entry = MetricGlossary.entry($0)
        return WelcomeHighlight(term: entry.term, detail: entry.line)
    }

    // MARK: - The page, top to bottom

    /// The three marks the track drawing carries, named under it. The same words and the
    /// same order as the turn ladder everywhere else: flew through, touchdown, fell in.
    public static let legend: [WelcomeLegendItem] = [
        WelcomeLegendItem(mark: .flew, label: "Flew through"),
        WelcomeLegendItem(mark: .touchdown, label: "Touchdown"),
        WelcomeLegendItem(mark: .fellIn, label: "Fell in"),
    ]

    /// The demo. First, and the prominent one: one tap fills every screen with a real
    /// session, before the rider has set anything up.
    public static let tryExampleTitle = "Try the example session"
    /// One line under it (Jan, 24 September 2026). "Already analysed" and "you connect
    /// nothing first" are gone: the first is how every session arrives, the second answered
    /// a question nobody asked.
    public static let tryExampleDetail = "A real 10-minute session on Lake Garda."

    /// Under the small share card. Tapping the card opens the example session, which is
    /// where the rider can make one of his own.
    public static let shareCardCaption = "Every session gives you a card like this to share."

    /// The title over the four glossary lines.
    public static let measuresTitle = "What CleanJibe measures"

    /// The page's one way on, near the bottom: it opens Getting started. The X closes the
    /// screen; there is no "Later" any more (Jan, 24 September 2026), because the X already
    /// says it.
    public static let getStartedTitle = "Get started"

    /// The footer's second sentence, after `FeedbackInvitation.community`. The app draws
    /// "Join the beta" and "Support & ideas" as links onto the Beta page and the mail.
    public static let footerRelease = "Join the beta or send ideas via Menu → Support & ideas."
    /// The same in the beta and the dev build, where the reader is in the beta already.
    public static let footerBeta = "Send ideas via Menu → Support & ideas."
}

/// One mark of the track drawing, and its name.
public struct WelcomeLegendItem: Sendable, Equatable, Identifiable {
    public enum Mark: String, Sendable {
        case flew, touchdown, fellIn
    }
    public let mark: Mark
    public let label: String
    public var id: String { mark.rawValue }

    public init(mark: Mark, label: String) {
        self.mark = mark
        self.label = label
    }
}

/// Whether to say hello.
///
/// **The rule since 25 September 2026** (Jan's plan of 24 September, section 7): the screen
/// comes up on every launch until the rider has something of his own to look at — a real
/// session, or intervals.icu connected so that one is on its way. The example session does
/// not count: it is ours, not his. There is no "don't show this again" switch, because the
/// two facts above switch it off by themselves.
///
/// It replaces the show-once flag (`welcomeShown.v1`), which had two failures of its own:
/// a rider who closed the screen on day one never saw it again while his library stayed
/// empty, and the upgrade heuristic had to guess about installs nobody had said anything
/// about. Two facts about the library and the key need no guess.
///
/// **A key counts as connected.** iOS keeps the keychain across an app delete, so a
/// reinstall with a key goes straight to the list — and that list fills from
/// intervals.icu on the first pull, which is the right first screen for that rider.
///
/// Pure for the reason every first-run rule in this project is pure: the cases are
/// reachable only on a fresh device, which is exactly the code that rots unwatched.
public enum WelcomePrompt {

    /// - Parameters:
    ///   - realSessionCount: rows in the library that are the rider's own — the example
    ///     session is not counted.
    ///   - icuConnected: an intervals.icu key is stored.
    ///   - shownThisLaunch: the screen already went up in this process. Once per launch:
    ///     the question is re-asked on every library change, and "raise it again" would put
    ///     the screen straight back over the example its own button just opened.
    ///   - isPresenting: something else is on screen — an import asking whose session it
    ///     is, an error, Settings. A *deferral*, not a refusal: the next clear moment asks
    ///     again. Same etiquette as `NewActivityPrompt`.
    ///   - requested: **somebody asked for this screen and has not had it yet** — today
    ///     Settings → Beta → *Start over* (`SessionStore.startOver`). A request outranks
    ///     the library and the key; only `isPresenting` may defer it.
    public static func shouldShow(realSessionCount: Int, icuConnected: Bool,
                                  shownThisLaunch: Bool,
                                  isPresenting: Bool = false,
                                  requested: Bool = false) -> Bool {
        guard !isPresenting else { return false }
        if requested { return true }
        return !shownThisLaunch && realSessionCount == 0 && !icuConnected
    }
}
