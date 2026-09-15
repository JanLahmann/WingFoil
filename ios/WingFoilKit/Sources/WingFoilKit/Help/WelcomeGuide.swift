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
        "CleanJibe reads a wingfoil session off your watch and tells you what actually "
        + "happened: how much of it you spent on the foil, how long each flight lasted, your "
        + "speed records, and — for every turn — whether you flew through it, touched down, "
        + "or fell in."

    /// One tight paragraph of what the app actually does, in the order the rider meets it:
    /// detection first (nothing else is possible without it), then the counts, then the
    /// verdicts, then the records, then the replay.
    public static let lede =
        "CleanJibe takes a session recording apart: when you were really up on the foil, "
        + "every flight and touchdown, a verdict on each jibe — flew through, touched down, "
        + "fell in — the dry streak, your fastest seconds. Then it plays it back, with a "
        + "commentary."

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

    // MARK: - The three ways on

    /// The demo. First, and the prominent one: four setup steps are a lot to walk before
    /// you know whether the app is worth it, and one tap fills every screen instead.
    public static let tryExampleTitle = "Try the example session"
    public static let tryExampleDetail =
        "Ten real minutes on Lake Garda, already analysed — the track, the replay, the "
        + "turn outcomes and the share card, with nothing to connect first."

    /// The real path. `IcuSetupCard` takes it from here, so this says only where it goes —
    /// but it names intervals.icu *and* says why a third party is in the story at all. A
    /// stranger's name on a first-run screen, with no reason beside it, reads as a catch.
    public static let connectTitle = "Connect your Garmin"
    public static let connectDetail =
        "Garmin has no open API for a personal app, so CleanJibe collects your sessions "
        + "through intervals.icu — free, four steps, about five minutes, once. Every session "
        + "after that arrives on its own."

    /// The quiet way out. Not a hidden one: a rider who wants to import a file by hand has
    /// nothing to gain from either button above — but "Later" on its own does not tell him
    /// that hand-importing is even possible, so the third way on gets a line like the other
    /// two rather than a bare verb.
    public static let laterTitle = "Later"
    public static let laterDetail =
        "You can also open a .fit file straight from Files, Mail or a message — yours or one "
        + "a friend sent you."
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
    /// the evidence — and **only** the library.
    ///
    /// A stored intervals.icu key used to count as well, and that was the bug Jan found in
    /// release candidate 58 (15 Sep 2026): iOS keeps keychain items across an app delete,
    /// so a reinstall hands the key back, the welcome was marked seen on sight, and the
    /// first screen of a genuinely fresh install was the intervals.icu setup card — the
    /// four steps and a key field, in front of a rider who had not been told what the app
    /// does. A key says something survived a delete; a session says the rider has been
    /// through the front door. Only the second is evidence.
    ///
    /// - Parameter sessionCount: rows in the library, including the example — someone who
    ///   loaded the example got the welcome's whole point already.
    public static func isAlreadyWelcomed(sessionCount: Int) -> Bool {
        sessionCount > 0
    }

    /// - Parameters:
    ///   - hasSeen: the flag is written. Once is the whole contract — a welcome screen that
    ///     comes back on the second launch is not a welcome, it is an obstacle.
    ///   - sessionCount: see `isAlreadyWelcomed`.
    ///   - isPresenting: something else is on screen — an import asking whose session it
    ///     is, an error, Settings. A *deferral*, not a refusal: the caller writes the flag
    ///     when the screen actually goes up, so the next clear moment asks again. Same
    ///     etiquette as `NewActivityPrompt`, and for the same reason.
    public static func shouldShow(hasSeen: Bool, sessionCount: Int,
                                  isPresenting: Bool = false) -> Bool {
        !hasSeen && !isAlreadyWelcomed(sessionCount: sessionCount) && !isPresenting
    }

    /// Whether an install that has never seen the screen should have the flag written
    /// anyway, silently.
    ///
    /// The case is the rider who was already using the app when this shipped: he is never
    /// shown the welcome, so nothing would ever spend the flag, and the day he deletes his
    /// last session the app would greet him like a stranger. Writing it down the first time
    /// we notice makes "already welcomed" a fact about the install rather than a fact about
    /// the current contents of the library.
    ///
    /// **A key alone never spends it** — see `isAlreadyWelcomed`.
    public static func shouldMarkSeenSilently(hasSeen: Bool, sessionCount: Int) -> Bool {
        !hasSeen && isAlreadyWelcomed(sessionCount: sessionCount)
    }
}
