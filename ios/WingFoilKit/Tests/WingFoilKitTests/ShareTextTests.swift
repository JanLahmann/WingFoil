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
}
