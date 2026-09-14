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
    ///
    /// **Superseded for the composer's own share sheet** by `ShareCaption.line`, which is the
    /// same sentence with the afternoon's two headline numbers in the middle of it. This stays
    /// because it is the *fallback* shape — a card with no analysis behind it yet — and
    /// because nothing else should have to think about which of the two it wants.
    public static func cardMessage(place: String?, startedAt: Date,
                                   timeZone: TimeZone) -> String {
        "\(lead(place: place, startedAt: startedAt, timeZone: timeZone)) — "
            + "\(Branding.appName) session · \(Branding.site)"
    }
}

/// The sentence that travels **beside** a shared card, on both platforms.
///
/// "Torbole · 30 August 2026 · 66 % on the foil · 30 clean jibes — analysed with CleanJibe,
/// free at cleanjibe.org."
///
/// **Why the numbers are in the text and not only in the picture.** A card arrives in a chat
/// as an image with a machine-made filename, and on every surface that shows a preview before
/// the image loads — a notification, a reply quote, a thread list, a screen reader — the
/// picture is not there yet and the text is all there is. Everything a receiver would learn by
/// opening it is therefore said in one line, ending in the offer, because the receiver is the
/// audience the card has (Jan, item 8 of the 14 Sep 2026 review).
///
/// **It is the web's sentence, ported, not a second one.** `shareCaption` in
/// web/js/sharecard.js is the reference and this is its twin: the same parts, the same order,
/// the same gates, the same separators. Two platforms writing "the same" caption from two
/// literals is how one of them ends up saying "jibes" where the other says "clean jibes", and
/// a rider who shares the same afternoon from the phone and from the browser gets two
/// different sentences about it.
///
/// **The one em dash the app is allowed.** Everywhere else the separator is "·". Here it is
/// " — ", because the web's sentence has it and the point of this type is that the two are
/// byte-identical; the dash is what separates the *report* from the *offer*, which is a
/// different kind of break from the one between two facts.
public enum ShareCaption {

    /// "analysed with CleanJibe, free at cleanjibe.org" — the offer, and the only half of the
    /// line addressed to somebody who does not have the app.
    public static let offer =
        "analysed with \(Branding.appName), free at \(Branding.site)"

    /// "30 clean jibes", and "1 clean jibe" — the one place the count is worded, the twin of
    /// the web's `cleanPhrase`.
    public static func cleanPhrase(_ count: Int) -> String {
        "\(count) clean \(count == 1 ? "jibe" : "jibes")"
    }

    /// The facts, in the order the web joins them: where, when, how much of it was flown, and
    /// how many of the jibes were clean.
    ///
    /// Every part is optional and every absence is a *silence* rather than a zero, which is
    /// the app's rule everywhere: a session whose wind axis named no jibes has no clean jibes
    /// to report, and "0 clean jibes" would be a verdict nobody measured. Callers gate
    /// `cleanJibes` on that (pass nil when `jibes == 0`), exactly as the web does.
    public static func parts(title: String?, dateLine: String,
                            foilPct: Double?, cleanJibes: Int?) -> [String] {
        var out: [String] = []
        let trimmed = title?.trimmingCharacters(in: .whitespaces) ?? ""
        if !trimmed.isEmpty, trimmed != ShareText.unnamedPlace { out.append(trimmed) }
        if !dateLine.isEmpty { out.append(dateLine) }
        if let foilPct { out.append("\(Int(foilPct.rounded())) % on the foil") }
        if let cleanJibes { out.append(cleanPhrase(cleanJibes)) }
        return out
    }

    /// The whole sentence: the facts, then the offer.
    public static func line(title: String?, dateLine: String,
                            foilPct: Double?, cleanJibes: Int?) -> String {
        let facts = parts(title: title, dateLine: dateLine,
                          foilPct: foilPct, cleanJibes: cleanJibes)
        guard !facts.isEmpty else { return offer }
        return facts.joined(separator: " · ") + " — " + offer
    }

    /// The **subject** the share sheet offers where a subject exists at all — mail, and
    /// nothing else. The facts without the offer: a subject line is a name for the thing, and
    /// an invitation in it reads as an advertisement rather than as a message from a friend.
    public static func subject(title: String?, dateLine: String) -> String {
        let facts = parts(title: title, dateLine: dateLine, foilPct: nil, cleanJibes: nil)
        return facts.isEmpty ? "\(Branding.appName) session" : facts.joined(separator: " · ")
    }
}
