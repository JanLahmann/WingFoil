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

    /// The one line at the top. The promise, not a feature list.
    public static let headline = "Every flight, every jibe, every swim."

    /// One tight paragraph of what the app actually does, in the order the rider meets it:
    /// detection first (nothing else is possible without it), then the counts, then the
    /// verdicts, then the records, then the replay.
    public static let lede =
        "CleanJibe takes a session recording apart. It works out when the board was really "
        + "up on the foil, counts every flight and every touchdown, gives each jibe a "
        + "verdict — flew through, touched down, fell in — keeps the dry streak running, "
        + "and finds your fastest seconds. Then it plays the whole thing back to you, with "
        + "the track, the numbers and a commentary on what just happened."

    /// The vocabulary, four lines of it. Enough that the words on the session page are
    /// already familiar; short enough that nobody skips the screen to escape it.
    public static let highlights: [WelcomeHighlight] = [
        WelcomeHighlight(
            term: "Foil %",
            detail: "How much of the session was spent flying rather than merely moving."),
        WelcomeHighlight(
            term: "Flights & touchdowns",
            detail: "One takeoff starts a flight; a touchdown or a swim ends it. "
                + "Both are counted."),
        WelcomeHighlight(
            term: "Jibe outcomes & dry streaks",
            detail: "Every turn gets a verdict, and the streak counts how many you carried "
                + "in a row without going in."),
        WelcomeHighlight(
            term: "Speed records",
            detail: "GP3S windows off your own track — best 2 s upwards, plus alpha 500."),
    ]

    // MARK: - The three ways on

    /// The demo. First, and the prominent one: four setup steps are a lot to walk before
    /// you know whether the app is worth it, and one tap fills every screen instead.
    public static let tryExampleTitle = "Try the example session"
    public static let tryExampleDetail =
        "Ten real minutes on Lake Garda, already analysed — the track, the replay, the "
        + "turn outcomes and the share card, with nothing to connect first."

    /// The real path. `IcuSetupCard` takes it from here, so this says only where it goes.
    public static let connectTitle = "Connect your Garmin"
    public static let connectDetail =
        "Four steps through intervals.icu, about five minutes, once — and every session "
        + "after that arrives on its own."

    /// The quiet way out. Not a hidden one: a rider who wants to import a file by hand has
    /// nothing to gain from either button above.
    public static let laterTitle = "Later"
}

/// Whether to say hello, and whether this install has already been said hello to.
///
/// Pure for the reason every first-run rule in this project is pure: it runs once per
/// install and is then unreachable for ever, which is exactly the code that rots unwatched.
/// "Shown twice" and "shown to somebody with three years of sessions" are both bugs that
/// only a fresh device — or this file's tests — would ever reveal.
public enum WelcomePrompt {

    /// True when the install has plainly been used already, whatever the flag says.
    ///
    /// The flag (`welcomeShown.v1`) does not exist on an install that predates the welcome
    /// screen, and shipping an update that greets a rider mid-season with "here is what
    /// this app does" would be worse than never greeting anyone. So the library itself is
    /// the evidence: a session in it, or a key that can fetch one, means the rider has
    /// already been through the front door.
    ///
    /// - Parameters:
    ///   - sessionCount: rows in the library, including the example — someone who loaded
    ///     the example got the welcome's whole point already.
    ///   - hasKey: an intervals.icu key is stored, so setup has at least been attempted.
    public static func isAlreadyWelcomed(sessionCount: Int, hasKey: Bool) -> Bool {
        sessionCount > 0 || hasKey
    }

    /// - Parameters:
    ///   - hasSeen: the flag is written. Once is the whole contract — a welcome screen that
    ///     comes back on the second launch is not a welcome, it is an obstacle.
    ///   - sessionCount: see `isAlreadyWelcomed`.
    ///   - hasKey: see `isAlreadyWelcomed`.
    ///   - isPresenting: something else is on screen — an import asking whose session it
    ///     is, an error, Settings. A *deferral*, not a refusal: the caller writes the flag
    ///     when the screen actually goes up, so the next clear moment asks again. Same
    ///     etiquette as `NewActivityPrompt`, and for the same reason.
    public static func shouldShow(hasSeen: Bool, sessionCount: Int, hasKey: Bool,
                                  isPresenting: Bool = false) -> Bool {
        !hasSeen && !isAlreadyWelcomed(sessionCount: sessionCount, hasKey: hasKey)
            && !isPresenting
    }

    /// Whether an install that has never seen the screen should have the flag written
    /// anyway, silently.
    ///
    /// The case is the rider who was already using the app when this shipped: he is never
    /// shown the welcome, so nothing would ever spend the flag, and the day he deletes his
    /// last session and clears his key the app would greet him like a stranger. Writing it
    /// down the first time we notice makes "already welcomed" a fact about the install
    /// rather than a fact about the current contents of the library.
    public static func shouldMarkSeenSilently(hasSeen: Bool, sessionCount: Int,
                                              hasKey: Bool) -> Bool {
        !hasSeen && isAlreadyWelcomed(sessionCount: sessionCount, hasKey: hasKey)
    }
}
