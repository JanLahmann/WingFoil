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

    /// Where the CleanJibe watch app's tacks and jibes get their wind (rider review S15):
    /// `AutoWind` estimates the axis live (docs/algorithms/wind.md, "Watch approximation"),
    /// and a bearing set by hand still wins. Said in these words on the help's Garmin
    /// Connect item and on /start/'s watch-app card.
    public static let watchWind =
        "The watch works the wind direction out after a few minutes of flying."

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
        AppShellCopy.fill(outcomeWindowTemplate, ["seconds": String(seconds)])
    }

    /// The same sentence as a template, which is how the browser reads it
    /// (`docs/copy/app-words.json`, `copy.outcomeWindow`).
    public static let outcomeWindowTemplate = "\"Outcome\" is the {seconds} s the verdict is read from."

    /// The axis crossing, as the dev trace and the turn page's tick both label it.
    /// A format string: the two angles are degrees before and after the crossing.
    public static let axisSweepFormat = "Through the axis · %.0f° before, %.0f° after"

    // MARK: - The inline maps

    /// The capsule on the Ride, Turns and Flights maps when a one-finger drag that started
    /// on them scrolled the page instead (rule 4 in the app's `ScrubPan`, Jan 30 Sep 2026).
    /// Phone only: the browser's maps still move with one finger, so it is not exported.
    public static let twoFingerMap = "Use two fingers to move the map"

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

    /// The way in that still works while Strava is full: Strava's own export of the
    /// original file, then the file door. Settings → Strava and Import → Strava show it under
    /// the refusal, with the two buttons beside it (rider review I5, 9 Oct 2026), and the
    /// help topic and the guide say the same path.
    public static let stravaFullExport =
        "Your Strava sessions can still come in as files. " + stravaExportOriginal
        + " AirDrop the file to this iPhone and import it."

    /// Strava's own path to the file it was given, the one sentence the refusal, the help
    /// topic and the guide share. A computer, because strava.com offers the export only in
    /// its desktop page.
    public static let stravaExportOriginal =
        "On a computer, open the activity on strava.com and choose ⋯ → Export Original."

    // MARK: - The feedback mails

    /// Why a fallback sheet is on screen at all. Said by both of the app's prefilled
    /// mails — the feedback one and the analysis one — so it lives here rather than in the
    /// two sheets that show it (docs/review-checklist.md, pattern F).
    public static let noMailAccount =
        "No mail account is set up on this phone, so CleanJibe cannot open a mail for you."

    /// The way out when the phone has no mail account set up.
    public static let copyTheReportInstead =
        "Copy the report and send it from any mail app to " + FeedbackReport.recipient + "."

    /// The rider's permission over the block below the rule. Every prefilled mail says it.
    public static let deleteAnyLine = "Delete any line you would rather not send."
}
