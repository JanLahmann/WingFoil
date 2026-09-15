import Foundation
import Testing
@testable import WingFoilKit

/// **The getting-started guide has one source, and this is the half of the proof that lives
/// in Swift.**
///
/// The other half is `python3 web/tools/make_start.py --check`, run by
/// `web/tools/verify_links.py`: it fails while `GettingStartedGuide.swift` or the block of
/// `web/start/index.html` disagrees with `docs/guide/getting-started.json`. That catches an
/// edit to the *generated* files. What it cannot catch is somebody typing a route straight
/// into `HelpCatalog` — the catalogue is hand-written everywhere else, so that is the
/// natural mistake — and that is what these tests are for: the topic a rider opens is
/// exactly the guide, in order, word for word.
@Suite struct GettingStartedGuideTests {

    static let topic = HelpCatalog.topic(.gettingStarted)

    // MARK: - The topic is the guide

    @Test func theTopicRendersTheGuideAndNothingOfItsOwn() {
        #expect(Self.topic.summary == GettingStartedGuide.topicSummary)
        #expect(Self.topic.body == [GettingStartedGuide.framing])
        #expect(Self.topic.items == GettingStartedGuide.items(for: .release))
    }

    /// Titles and summaries, in order, against the data rather than against the same call
    /// the catalogue makes — so a filter that silently started dropping or reordering
    /// routes fails here instead of shipping.
    @Test func everyReleaseRouteIsAnItemInSourceOrder() {
        let expected = (GettingStartedGuide.routes + GettingStartedGuide.notes)
            .filter { $0.channel == .release }
        #expect(Self.topic.items.count == expected.count + 1, "routes, notes, and the web line")

        for (item, route) in zip(Self.topic.items, expected) {
            #expect(item.term == route.title)
            #expect(item.detail == route.summary)
        }
        #expect(Self.topic.items.last == GettingStartedGuide.onTheWeb)
    }

    /// The on-water framing opens both surfaces, and it is one paragraph rather than a
    /// walkthrough: the steps are the web's job.
    @Test func theOnWaterFramingComesFirst() {
        #expect(GettingStartedGuide.framing.hasPrefix("The real test is one session on the water"))
        #expect(Self.topic.body.first == GettingStartedGuide.framing)
    }

    /// The last item promises **every step**, and points at the page that has them.
    @Test func theWebLinePromisesTheSteps() {
        let web = GettingStartedGuide.onTheWeb
        #expect(web.term == "The same guide, with every step, on the web")
        #expect(web.detail == "\(Branding.site)/start")
        #expect(Self.topic.links.contains { $0.url.absoluteString.hasSuffix("/start") })
    }

    // MARK: - Channels

    /// The two Apple doors are beta doors (docs/channels.md): the release build never names
    /// them as items, a beta build's `items(for:)` does, and either way they are reachable
    /// as `related` topics — which `relatedTopics(of:channel:)` filters on its own.
    @Test func theAppleRoutesAreBetaOnly() {
        let apple = ["appleWatchApp", "appleWorkoutApp"]
        for id in apple {
            let route = GettingStartedGuide.routes.first { $0.id == id }
            #expect(route?.channel == .beta, "\(id) must be a beta route")
        }

        let release = GettingStartedGuide.items(for: .release).map(\.term)
        let beta = GettingStartedGuide.items(for: .beta).map(\.term)
        for id in apple {
            let title = GettingStartedGuide.routes.first { $0.id == id }!.title
            #expect(!release.contains(title), "the release names \(title)")
            #expect(beta.contains(title), "the beta does not name \(title)")
        }
        // Nothing is lost in the release: the beta's list is the release's plus the two.
        #expect(beta.count == release.count + apple.count)
        #expect(Set(release).isSubset(of: Set(beta)))
        #expect(GettingStartedGuide.items(for: .dev).map(\.term) == beta)
    }

    /// Every route the app names has a `related` topic that owns its steps, so the item is
    /// a signpost rather than a second copy of an instruction.
    @Test func everyRouteHasATopicThatOwnsIt() {
        for id in [HelpTopicID.icuSetup, .shareFromWatchApp, .stravaImport,
                   .appleWatchApp, .appleWorkoutApp] {
            #expect(Self.topic.related.contains(id), "no related topic \(id.rawValue)")
        }
    }

    // MARK: - The source's own shape

    @Test func theGuideIsWellFormed() {
        let all = GettingStartedGuide.routes + GettingStartedGuide.notes
        #expect(!all.isEmpty)

        let ids = all.map(\.id) + [GettingStartedGuide.onTheWeb.term]
        #expect(Set(ids).count == ids.count, "duplicate route id")

        for route in all {
            #expect(!route.title.isEmpty)
            #expect(!route.summary.isEmpty)
            #expect(!route.steps.isEmpty, "\(route.id) has no steps for the web to show")
            #expect(route.steps.map(\.number) == Array(1...route.steps.count),
                    "\(route.id): steps are not numbered 1…n")
            for step in route.steps {
                #expect(!step.title.isEmpty)
                #expect(!step.detail.isEmpty)
            }
        }
    }

    // The word budgets on the routes, the steps and the two captions below live where every
    // other help budget lives: `HelpBudgetTests.theSharedGuidesFitTheSameBudgets`. The
    // generator asserts the same numbers on the source, so an over-long sentence fails
    // before either copy is written.

    // MARK: - The two Settings captions

    /// **Settings says what the help says.** Both sections open with a caption the view
    /// reads from here, so "why is this account here" has one answer (Jan, 15 Sep 2026).
    @Test func theSettingsCaptionsAnswerWhyTheAccountIsThere() {
        let icu = GettingStartedGuide.settingsIcu
        #expect(icu.contains("no open API"))
        #expect(icu.contains("intervals.icu"))

        let strava = GettingStartedGuide.settingsStrava
        #expect(strava.contains("Strava"))
        #expect(strava.contains("uncertified"), "the cost is said in the same breath")

        // The house voice: you and CleanJibe, never we. ("your" is fine — the spaces are
        // what make this a word check rather than a substring one.)
        for line in [icu, strava] {
            #expect(!line.lowercased().contains(" we "))
            #expect(!line.lowercased().contains(" our "))
            #expect(!line.lowercased().contains(" us "))
        }
    }
}
