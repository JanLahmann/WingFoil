import Foundation
import Testing
@testable import WingFoilKit

/// **The help catalogue's word budget.**
///
/// Jan, on release candidate 58: *"the FAQ is nice, but many of the answers are way too
/// verbose; it looks AI generated in a negative way."* Every topic was cut back to answer
/// its own title in the first sentence and then the facts — and the only thing that keeps
/// a catalogue of forty topics that way is a number a new paragraph has to fit inside.
///
/// The budgets, agreed 15 September 2026:
///
/// | surface | budget |
/// |---|---|
/// | a topic's whole body | 120 words |
/// | one body paragraph | 45 words |
/// | one item's detail | 30 words |
/// | a summary (the index line) | 25 words |
///
/// A topic that needs more than the body allows does not get a longer body: it gets an
/// `items:` list, which is what the long topics here already are. Words are whitespace-
/// separated tokens with the markdown emphasis markers removed, which is close enough to
/// what a reader counts and exact enough to fail on.
@Suite struct HelpBudgetTests {

    static let bodyBudget = 120
    static let paragraphBudget = 45
    static let itemBudget = 30
    static let summaryBudget = 25

    /// Whitespace-separated tokens, with `**` and `*` emphasis markers dropped so a bolded
    /// word costs exactly what the same word costs unbolded.
    static func words(_ text: String) -> Int {
        text.replacingOccurrences(of: "**", with: "")
            .split(whereSeparator: \.isWhitespace)
            .count
    }

    @Test func noHelpTopicRunsOverItsWordBudget() {
        for topic in HelpCatalog.topics {
            let id = topic.id.rawValue

            #expect(Self.words(topic.summary) <= Self.summaryBudget,
                    "\(id): summary is \(Self.words(topic.summary)) words, budget \(Self.summaryBudget)")

            let body = topic.body.map(Self.words).reduce(0, +)
            #expect(body <= Self.bodyBudget,
                    "\(id): body is \(body) words, budget \(Self.bodyBudget) — move the detail into items:")

            for paragraph in topic.body {
                #expect(Self.words(paragraph) <= Self.paragraphBudget,
                        "\(id): a paragraph is \(Self.words(paragraph)) words, budget \(Self.paragraphBudget): \(paragraph.prefix(60))…")
            }

            for item in topic.items {
                #expect(Self.words(item.detail) <= Self.itemBudget,
                        "\(id): item \(item.term) is \(Self.words(item.detail)) words, budget \(Self.itemBudget)")
            }
        }
    }

    /// The same budgets on the two shared guides the catalogue renders, because a topic
    /// that is inside its budget only until `IcuSetupGuide` grows is not inside its budget.
    @Test func theSharedGuidesFitTheSameBudgets() {
        #expect(Self.words(IcuSetupGuide.rationale) <= Self.paragraphBudget)
        #expect(Self.words(IcuSetupGuide.rationaleShort) <= Self.paragraphBudget)
        #expect(Self.words(IcuSetupGuide.privacyNote) <= Self.paragraphBudget)
        for step in IcuSetupGuide.steps {
            #expect(Self.words(step.detail) <= Self.itemBudget,
                    "setup step \(step.number) is \(Self.words(step.detail)) words")
        }
        for entry in IcuSetupGuide.troubleshooting {
            #expect(Self.words(entry.detail) <= Self.itemBudget,
                    "troubleshooting \"\(entry.term)\" is \(Self.words(entry.detail)) words")
        }
        #expect(Self.words(WelcomeGuide.lede) <= Self.paragraphBudget)
        for highlight in WelcomeGuide.highlights {
            #expect(Self.words(highlight.detail) <= Self.itemBudget)
        }
        for detail in [WelcomeGuide.tryExampleDetail, WelcomeGuide.connectDetail,
                       WelcomeGuide.laterDetail] {
            #expect(Self.words(detail) <= Self.paragraphBudget)
        }

        // The getting-started guide, generated from docs/guide/getting-started.json. Its
        // route summaries are the Getting started topic's item details and its steps are
        // the web page's, and both are written to the item budget — `make_start.py`
        // asserts the same numbers on the source, so a long sentence fails at the
        // generator rather than here. The two Settings captions are budgeted too: they are
        // one row of a Form, not a footer.
        #expect(Self.words(GettingStartedGuide.framing) <= Self.paragraphBudget)
        #expect(Self.words(GettingStartedGuide.topicSummary) <= Self.summaryBudget)
        for route in GettingStartedGuide.routes + GettingStartedGuide.notes {
            #expect(Self.words(route.summary) <= Self.itemBudget,
                    "route \(route.id) is \(Self.words(route.summary)) words")
            for step in route.steps {
                #expect(Self.words(step.detail) <= Self.itemBudget,
                        "\(route.id) step \(step.number) is \(Self.words(step.detail)) words")
            }
        }
        for caption in [GettingStartedGuide.settingsIcu, GettingStartedGuide.settingsStrava] {
            #expect(Self.words(caption) <= Self.itemBudget,
                    "a Settings caption is \(Self.words(caption)) words")
        }
    }

    /// **One wording, referenced, not copied.** The Getting started topic names the route
    /// each way in takes; the steps themselves stay in `IcuSetupGuide` and in the import
    /// topics, so there is one place to fix a menu that moved.
    @Test func gettingStartedPointsAtTheStepsRatherThanRepeatingThem() {
        let topic = HelpCatalog.topic(.gettingStarted)
        let items = topic.items.map { $0.term + " " + $0.detail }
        let prose = (topic.body + items).joined(separator: " ")

        // One route per item, with the heading a rider scans for.
        for route in ["Garmin with the CleanJibe watch app", "Any watch that writes a .fit",
                      "Strava", "If you cannot wait for wind"] {
            #expect(topic.items.contains { $0.term == route }, "no route \"\(route)\"")
        }
        // The intervals.icu route names the door and the step count, and hands the steps to
        // the topic that owns them — which is on `related`, so the chevron is really there.
        #expect(prose.contains("Settings → intervals.icu"))
        #expect(IcuSetupGuide.steps.count == 4, "the item says \"four steps\"")
        #expect(prose.contains("4 steps"))
        #expect(topic.related.contains(.icuSetup))
        // The FIT route says what the import topics say: intervals.icu, or the file itself.
        #expect(prose.contains("Files, Mail, AirDrop"))
        #expect(topic.related.contains(.shareFromWatchApp))
        // Strava, in the app's own spelling.
        #expect(prose.contains("Settings → Strava → Connect with Strava"))
        #expect(prose.contains("Import → Import from Strava"))
        #expect(topic.related.contains(.stravaImport))
        // The two Apple doors are beta doors, so they are topics on `related` rather than
        // paragraphs in a body that cannot branch by channel (docs/channels.md).
        #expect(topic.related.contains(.appleWatchApp))
        #expect(topic.related.contains(.appleWorkoutApp))
        for beta in [HelpTopicID.appleWatchApp, .appleWorkoutApp] {
            #expect(HelpCatalog.topic(beta).channel == .beta)
        }
        #expect(!HelpCatalog.relatedTopics(of: topic, channel: .release)
                    .contains { $0.id == .appleWatchApp || $0.id == .appleWorkoutApp })
        // Where a report goes, and the mirror — named last, never as the place the
        // instructions live.
        #expect(prose.contains("Menu → Support & ideas"))
        #expect(topic.items.last?.detail == "\(Branding.site)/start")
        #expect(topic.links.contains { $0.url.absoluteString.hasSuffix("/start") })
    }
}
