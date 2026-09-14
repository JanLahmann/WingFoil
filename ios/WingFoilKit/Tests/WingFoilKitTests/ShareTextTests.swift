import Foundation
import Testing
@testable import WingFoilKit

/// The words that go into a chat with a shared file. Three surfaces, one lead-in — and the
/// lead-in is the whole change: what used to arrive was a machine-named attachment and a
/// sentence about the app, which told the receiver nothing about *which* afternoon he had
/// been sent.
@Suite struct ShareTextTests {

    /// 30 Aug 2026, 14:07 CEST — the same instant the replay's title card and the share card
    /// are pinned against.
    private let startedAt = Date(timeIntervalSince1970: 1_788_091_620)
    private let cest = TimeZone(secondsFromGMT: 2 * 3600)!

    /// Place, comma, the share card's own long date — and it *is* the share card's, not a
    /// second formatter that would drift from it.
    @Test func theLeadIsThePlaceAndTheCardsOwnDate() {
        #expect(ShareText.lead(place: "Torbole", startedAt: startedAt, timeZone: cest)
                == "Torbole, 30 August 2026")
        #expect(ShareText.lead(place: "Torbole", startedAt: startedAt, timeZone: cest)
                .hasSuffix(ShareCardStats.dateLine(startedAt, timeZone: cest)))
    }

    /// A recording whose filename says nothing gets the date alone. `SessionDisplay.title`
    /// falls back to the literal "Session", and "Session, 30 August 2026 — CleanJibe session"
    /// is one sentence saying one thing three times.
    @Test func anUnnamedSessionLeadsWithTheDateAlone() {
        for place in [nil, "", "   ", ShareText.unnamedPlace] {
            #expect(ShareText.lead(place: place, startedAt: startedAt, timeZone: cest)
                    == "30 August 2026")
        }
    }

    /// The FIT keeps its invitation — it is the one attachment the receiver can actually do
    /// something with, and no way of knowing it.
    @Test func theFitMessageLeadsWithThePlaceAndKeepsTheInvitation() {
        let message = ShareText.fitMessage(place: "Torbole", startedAt: startedAt,
                                           timeZone: cest)
        #expect(message.hasPrefix("Torbole, 30 August 2026 — "))
        #expect(message.contains(Branding.siteURL))
        #expect(message.contains("no account needed"))
    }

    /// The clip does not. A paragraph of small print under a forty-second video is what makes
    /// people share the video some other way — so it gets the credit and stops.
    @Test func theClipMessageIsShortAndCarriesNoPitch() {
        let message = ShareText.clipMessage(place: "Torbole", startedAt: startedAt,
                                            timeZone: cest)
        #expect(message == "Torbole, 30 August 2026 — CleanJibe session clip · cleanjibe.org")
        #expect(!message.contains("no account needed"))
        #expect(!message.contains("https://"))
    }

    /// Same shape for the card: a PNG cannot be re-analysed either, and the card already
    /// carries the site in its footer pixels.
    @Test func theCardMessageMatchesTheClipsShape() {
        #expect(ShareText.cardMessage(place: "Torbole", startedAt: startedAt, timeZone: cest)
                == "Torbole, 30 August 2026 — CleanJibe session · cleanjibe.org")
    }

    /// All three start with the same words, which is the point of there being one helper:
    /// an afternoon exported three ways is named and dated identically all three times.
    @Test func allThreeShareOneLeadIn() {
        let lead = ShareText.lead(place: "Nago Torbole Windsurfen", startedAt: startedAt,
                                  timeZone: cest)
        for message in [ShareText.fitMessage(place: "Nago Torbole Windsurfen",
                                             startedAt: startedAt, timeZone: cest),
                        ShareText.clipMessage(place: "Nago Torbole Windsurfen",
                                              startedAt: startedAt, timeZone: cest),
                        ShareText.cardMessage(place: "Nago Torbole Windsurfen",
                                              startedAt: startedAt, timeZone: cest)] {
            #expect(message.hasPrefix(lead + " — "))
        }
    }

    // MARK: - The card's caption

    /// The sentence a receiver reads before the picture has loaded, and the one place the
    /// two platforms have to agree word for word: this is the twin of `shareCaption` in
    /// web/js/sharecard.js, asserted against the exact string that function produces.
    @Test func theCardCaptionIsTheWebsSentence() {
        #expect(ShareCaption.line(title: "Torbole", dateLine: "30 August 2026",
                                  foilPct: 66.2, cleanJibes: 30)
                == "Torbole · 30 August 2026 · 66 % on the foil · 30 clean jibes "
                   + "— analysed with CleanJibe, free at cleanjibe.org")
    }

    /// One jibe is a jibe. The twin of the web's `cleanPhrase`.
    @Test func theCleanCountIsWordedOnce() {
        #expect(ShareCaption.cleanPhrase(1) == "1 clean jibe")
        #expect(ShareCaption.cleanPhrase(0) == "0 clean jibes")
        #expect(ShareCaption.cleanPhrase(30) == "30 clean jibes")
    }

    /// An absence is a silence, never a zero: a session whose wind axis named no jibes has
    /// no clean ones to report, so the part is simply not there. Same gate as the web's.
    @Test func absentNumbersLeaveTheirPartsOut() {
        #expect(ShareCaption.line(title: "Torbole", dateLine: "30 August 2026",
                                  foilPct: nil, cleanJibes: nil)
                == "Torbole · 30 August 2026 — analysed with CleanJibe, free at cleanjibe.org")
        #expect(ShareCaption.line(title: nil, dateLine: "30 August 2026",
                                  foilPct: 66.2, cleanJibes: nil)
                == "30 August 2026 · 66 % on the foil "
                   + "— analysed with CleanJibe, free at cleanjibe.org")
    }

    /// The fallback title is not a place, so it is not printed as one — the same rule
    /// `ShareText.lead` follows, for the same reason.
    @Test func theUnnamedFallbackIsNotPrintedAsAPlace() {
        #expect(ShareCaption.line(title: ShareText.unnamedPlace, dateLine: "30 August 2026",
                                  foilPct: nil, cleanJibes: nil)
                == "30 August 2026 — analysed with CleanJibe, free at cleanjibe.org")
        #expect(ShareCaption.line(title: "   ", dateLine: "", foilPct: nil, cleanJibes: nil)
                == "analysed with CleanJibe, free at cleanjibe.org")
    }

    /// Rounded, not truncated, and rounded the way `Math.round` does it on the other side.
    @Test func theFoilShareIsRoundedLikeTheWebs() {
        for (pct, printed) in [(66.4, "66"), (66.5, "67"), (0.4, "0"), (99.6, "100")] {
            #expect(ShareCaption.line(title: nil, dateLine: "", foilPct: pct,
                                      cleanJibes: nil).hasPrefix("\(printed) % on the foil"))
        }
    }

    /// The subject is the facts and not the offer: an invitation in a mail's subject line
    /// reads as an advertisement rather than as a message from somebody you know.
    @Test func theSubjectCarriesNoInvitation() {
        let subject = ShareCaption.subject(title: "Torbole", dateLine: "30 August 2026")
        #expect(subject == "Torbole · 30 August 2026")
        #expect(!subject.contains(ShareCaption.offer))
        #expect(ShareCaption.subject(title: nil, dateLine: "") == "CleanJibe session")
    }
}
