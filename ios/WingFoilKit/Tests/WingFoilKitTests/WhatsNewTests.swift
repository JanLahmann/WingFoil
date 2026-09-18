import Foundation
import Testing
@testable import WingFoilKit

/// **The release notes have one source, and this is the half of the proof that lives in
/// Swift.**
///
/// The other half is `python3 web/tools/make_whats_new.py --check`, run by
/// `web/tools/verify_links.py`: it fails while `WhatsNew.swift` or the card block of
/// `web/whats-new/index.html` disagrees with `docs/copy/whats-new.json`. That catches an
/// edit to the *generated* files. What it cannot catch is the generator itself producing
/// notes that are off the voice, or a channel filter that quietly hands a release rider a
/// note about a beta door — which is what these are for.
@Suite struct WhatsNewTests {

    /// The words a machine can hold from docs/voice.md register 1, on the data the app
    /// actually renders. The generator holds the same numbers on the JSON, so this is the
    /// second lock rather than the first.
    static let lineBudget = 20
    static let titleBudget = 8

    static func words(_ text: String) -> Int {
        text.replacingOccurrences(of: "**", with: "")
            .split(whereSeparator: \.isWhitespace)
            .count
    }

    @Test func thereAreNotesAndTheNewestIsFirst() {
        #expect(!WhatsNew.entries.isEmpty, "the app would show an empty What's new screen")

        let dates = WhatsNew.entries.map(\.date)
        #expect(dates == dates.sorted(by: >), "the entries are not newest first")
        // ISO 8601 is what makes the string comparison above a date comparison.
        for entry in WhatsNew.entries {
            #expect(entry.date.count == 10 && entry.date.filter { $0 == "-" }.count == 2,
                    "\(entry.id): \(entry.date) is not yyyy-MM-dd")
            #expect(!entry.dateText.isEmpty, "\(entry.id) has no written date")
        }

        // Two products, one list: the iPhone builds still run downwards among themselves.
        let builds = WhatsNew.entries.compactMap(\.build)
        #expect(builds == builds.sorted(by: >))
        #expect(Set(builds).count == builds.count, "a build number is listed twice")
    }

    /// Register 1: one thought per sentence, never over 20 words, and no em-dash anywhere —
    /// a dash in a release note is a second sentence hiding.
    @Test func everyLineIsInsideTheVoice() {
        for entry in WhatsNew.entries {
            #expect(Self.words(entry.title) <= Self.titleBudget,
                    "\(entry.id): title is \(Self.words(entry.title)) words")
            #expect(!entry.lines.isEmpty, "\(entry.id) has no lines")
            for line in entry.lines {
                #expect(Self.words(line) <= Self.lineBudget,
                        "\(entry.id): \(Self.words(line)) words — \(line)")
                #expect(!line.contains("—") && !line.contains("–"),
                        "\(entry.id): a dash — \(line)")
                #expect(!line.contains(";"), "\(entry.id): a semicolon — \(line)")
            }
        }
    }

    /// **Pattern D, the channel filter** (docs/channels.md): a release build reads the
    /// release notes, a beta build reads beta and release, the dev build reads everything.
    /// A note about a build the reader could never have is the app describing a door he
    /// cannot open.
    @Test func eachChannelReadsItsOwnNotesAndTheOnesBelowIt() {
        let release = WhatsNew.entries(for: .release)
        let beta = WhatsNew.entries(for: .beta)
        let dev = WhatsNew.entries(for: .dev)

        #expect(!release.isEmpty, "the App Store build would show nothing")
        #expect(release.allSatisfy { $0.channel == .release })
        #expect(Set(release.map(\.id)).isSubset(of: Set(beta.map(\.id))))
        #expect(Set(beta.map(\.id)).isSubset(of: Set(dev.map(\.id))))
        #expect(dev.count == WhatsNew.entries.count)
        #expect(!beta.contains { $0.channel == .dev })

        // Order survives the filter: the newest first is the whole point of the screen.
        #expect(beta.map(\.date) == beta.map(\.date).sorted(by: >))
    }

    /// The row's own title, from the one field that says which product an entry is about.
    @Test func aBuildNumberMeansTheiPhoneAndNoneMeansTheWatch() {
        for entry in WhatsNew.entries {
            if entry.build == nil {
                #expect(entry.heading.hasPrefix("Garmin watch app"))
                #expect(entry.heading.contains(entry.version))
            } else {
                #expect(entry.heading.hasPrefix("iPhone · build"))
            }
        }
        #expect(WhatsNew.entries.contains { $0.build == nil }, "no watch release is listed")
    }

    /// The Help topic is the door, and the screen behind it is the notes — so the topic
    /// carries the action and no items of its own to drift from them.
    @Test func theHelpTopicOpensTheScreen() {
        let topic = HelpCatalog.topic(.whatsNew)
        #expect(topic.action == .openWhatsNew)
        #expect(topic.items.isEmpty)
        #expect(topic.channel == .release, "every channel has release notes to read")
    }
}
