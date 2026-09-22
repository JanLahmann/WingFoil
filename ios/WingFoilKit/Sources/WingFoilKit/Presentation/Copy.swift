import Foundation

/// **One sentence, one home** — the lines two screens both have to say.
///
/// Pattern F of `docs/review-checklist.md`, made a place rather than a rule: when the same
/// sentence is true on the turn page and on the flight-end page, on the card composer and
/// on the period card, in an Import footer and in a Settings footer, it is written here once
/// and referenced from both. `docs/copy/check_duplicates.py` fails the build the moment a
/// sentence of eight words or more has two homes among the kit's `Help/`, `Presentation/`
/// and the app's `Features/`, so the next author finds this file before he retypes a line.
///
/// What belongs here: a sentence, in the voice of `docs/voice.md`, that two surfaces say
/// **about the same thing**. What does not: a sentence that happens to read alike but
/// answers two different questions — those keep their own words, and the check's exemption
/// list (`docs/copy/duplicate-exemptions.json`, empty on purpose) is not a substitute for
/// deciding which of the two homes is the real one.
///
/// Sentences that go out to the website or a store are not here but in `docs/copy/*.json`:
/// that file is the contract across *products*, this enum is the one inside the app.
public enum Copy {

    // MARK: - Strava (docs/copy/phrases.json `stravaFall`, pinned by CopyContractTests)

    /// What a positions-only recording loses (docs/algorithms/pumping.md, "Positions-only
    /// recordings and touchdowns"): the stop under a fall never shows in positional speed,
    /// so the verdict reads touchdown. Said once, on every Strava setup surface.
    public static let stravaFall = "Without the watch's own speed, a fall can read as a touchdown."

    // MARK: - The drawn track (the turn page and the flight-end page)
    /// Why a drawn track is north up: no wind direction the engine trusts, none set on
    /// the watch. Said under the orientation switch on the turn page and the flight-end page.
    public static let noWindForOrientation =
        "Wind up needs a wind direction. This session has none the engine trusts, and none "
        + "set on the watch."


    /// The second numbers printed along a drawn track.
    public static let pathNumbers = "The numbers along the path are every five."

    /// Where the compass and the wind arrow sit on a drawn track.
    public static let northAndWind = "North and the wind are marked top right."

    /// The engine's outcome window, in the seconds this analysis actually used.
    public static func outcomeWindow(seconds: Int) -> String {
        // Concatenated rather than interpolated: `check_voice.py` reads the literal, and an
        // interpolation inside one reads to it as a parenthesis in a rider sentence.
        "\"Outcome\" is the " + String(seconds) + " s the verdict is read from."
    }

    /// The axis crossing, as the dev trace and the turn page's tick both label it.
    /// A format string: the two angles are degrees before and after the crossing.
    public static let axisSweepFormat = "Through the axis · %.0f° before, %.0f° after"

    // MARK: - Sharing an image

    /// What happens to a rendered card. Said under every preview, because "share" is the
    /// word a rider reads as "upload" until something says otherwise.
    public static let straightToTheShareSheet =
        "Nothing is uploaded. The image goes straight to the share sheet."

    // MARK: - Recording the replay

    /// Why the screen recorder is not there. The three switches are iOS', not CleanJibe's,
    /// which is why the sentence names them.
    public static let screenRecordingUnavailable =
        "Screen recording is not available right now. Low Power Mode, AirPlay and "
        + "screen mirroring all switch it off."

    // MARK: - Sessions that arrive on their own

    /// The Apple Watch app's promise, on the help topic and on the empty library's row.
    public static let watchSessionArrives = "The session comes to the phone by itself."

    /// What to do when iOS has not woken the app yet. Both the Import screen and the
    /// Settings switch end on it, because both describe the same wake-up.
    public static let openToPickUp = "Open CleanJibe to pick up the session you just finished."

    // MARK: - Strava is full

    /// What to do when Strava refuses a new connection. The Import screen and the Settings
    /// section both end on it. What the cap *is* belongs to `docs/copy/phrases.json`
    /// (`strava`), which is the sentence this one follows.
    public static let stravaAskForMore =
        "Tell us under Menu → Support & ideas, and CleanJibe asks Strava for more."

    // MARK: - The feedback mails

    /// The way out when the phone has no mail account set up.
    public static let copyTheReportInstead =
        "Copy the report and send it from any mail app to " + FeedbackReport.recipient + "."

    /// The rider's permission over the block below the rule. Every prefilled mail says it.
    public static let deleteAnyLine = "Delete any line you would rather not send."
}
