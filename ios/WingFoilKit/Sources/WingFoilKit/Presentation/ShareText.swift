import Foundation

/// The words that travel with a shared file: the message body on a FIT, on a clip, and on
/// the card.
///
/// **Why they all start with a place and a date.** What arrives in a chat is an attachment
/// with a machine-made filename and, until now, a line about what the app is. The receiver —
/// who is usually the friend who was on the water at the same time — could not tell *which
/// afternoon* he was being sent without opening it. "Torbole, 30 August 2026" is the one fact
/// that makes the message readable at a glance, and it is the fact the sender means.
///
/// **Why it is one type and not three literals.** They were three literals, in three files,
/// and two of them already disagreed about whether to name the site. A shared lead-in also
/// means the place and the date are formatted once: the same `ShareCardStats.dateLine` the
/// share card prints and the clip's own title card uses, so an afternoon exported three ways
/// is dated identically all three times.
///
/// **What "place" is.** The caller's, exactly as `ReplayCommentary.make` and
/// `ReplayStoryboard.make` take it — the app passes `SessionDisplay.title(row)`, which reads a
/// readable name out of the recording's filename ("Nago Torbole Windsurfen"). There is no
/// place-*only* form in the app today: spots are clustered and named separately and a session
/// may not have one, whereas the title always resolves to something. When it degrades to its
/// own fallback the lead-in drops the place rather than printing the word "Session" twice.
public enum ShareText {

    /// The title the app falls back to when a recording's filename says nothing. Recognised
    /// here so the lead-in can decline to lead with it — "Session, 30 August 2026 — CleanJibe
    /// session" is a sentence that says one thing three times.
    public static let unnamedPlace = "Session"

    /// "Torbole, 30 August 2026" — or just the date, when there is no name worth printing.
    public static func lead(place: String?, startedAt: Date,
                            timeZone: TimeZone) -> String {
        let date = ShareCardStats.dateLine(startedAt, timeZone: timeZone)
        let trimmed = place?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !trimmed.isEmpty, trimmed != unnamedPlace else { return date }
        return "\(trimmed), \(date)"
    }

    /// The message that goes with a shared **recording**.
    ///
    /// It keeps the invitation, because a FIT is the one attachment the receiver can do
    /// something with and has no way of knowing it: the web app reads the same file with the
    /// same engine, in a browser, without an account.
    public static func fitMessage(place: String?, startedAt: Date,
                                  timeZone: TimeZone) -> String {
        "\(lead(place: place, startedAt: startedAt, timeZone: timeZone)) — "
            + "\(Branding.appName) session. Analyze it free in the browser at "
            + "\(Branding.siteURL) (no account needed)."
    }

    /// The message that goes with a shared **clip**.
    ///
    /// Deliberately short, and deliberately without the analyzer pitch: a video is not a file
    /// anybody is going to open in a browser tool, and a paragraph of small print under a
    /// forty-second clip is the sort of thing that makes people share the clip some other way.
    /// The site is still named — whoever gets this should be able to find out what made it —
    /// but as a credit rather than as an offer.
    public static func clipMessage(place: String?, startedAt: Date,
                                   timeZone: TimeZone) -> String {
        "\(lead(place: place, startedAt: startedAt, timeZone: timeZone)) — "
            + "\(Branding.appName) session clip · \(Branding.site)"
    }

    /// The message that goes with a shared **card**. Same shape as the clip's, for the same
    /// reason: a PNG is not something the receiver can re-analyse either, and the card already
    /// carries its own footer credit in the pixels.
    public static func cardMessage(place: String?, startedAt: Date,
                                   timeZone: TimeZone) -> String {
        "\(lead(place: place, startedAt: startedAt, timeZone: timeZone)) — "
            + "\(Branding.appName) session · \(Branding.site)"
    }
}
