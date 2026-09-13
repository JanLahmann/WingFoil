import Foundation
import Testing
@testable import WingFoilKit

/// The beta feedback mail. Every assertion here is about a fact a reply would need and a
/// reporter would never think to type: which build, which engine, whether the thresholds
/// were standard, and which session the complaint is about.
@Suite struct FeedbackReportTests {

    private func facts(dev: Bool = false, tuned: Int = 0,
                       watch: FeedbackFacts.Watch? = nil,
                       session: FeedbackFacts.Session? = nil) -> FeedbackFacts {
        FeedbackFacts(
            app: .init(version: "1.0", build: "17", isDev: dev,
                       engineVersion: "0.19.0", tunedThresholds: tuned),
            phone: .init(model: "iPhone18,2", system: "iOS 26.0", locale: "en_DE"),
            watch: watch ?? .init(garminModel: "fenix 8", garminAppVersion: "2.2",
                                  appleWatchPaired: false, healthImport: false),
            library: .init(sessionCount: 42,
                           sources: [.init(label: "intervals.icu", count: 38),
                                     .init(label: "Strava", count: 4)]),
            session: session)
    }

    // MARK: The subject

    /// The build number, not the marketing version: the two TestFlight variants of a
    /// release share the latter and differ only in the former.
    @Test func theSubjectNamesTheBuildAndTheWatch() {
        #expect(FeedbackReport.subject(facts())
                == "CleanJibe beta feedback · build 17 · fenix 8")
    }

    @Test func theDevBuildSaysSoInTheSubject() {
        #expect(FeedbackReport.subject(facts(dev: true))
                == "CleanJibe beta feedback · build 17 dev · fenix 8")
    }

    @Test func aRiderWithNoWatchStillGetsASubject() {
        let none = FeedbackFacts.Watch(garminModel: nil, garminAppVersion: nil,
                                       appleWatchPaired: nil, healthImport: true)
        #expect(FeedbackReport.subject(facts(watch: none))
                == "CleanJibe beta feedback · build 17 · no watch")
    }

    // MARK: The body

    /// The rider's own line comes first, before a single diagnostic — a mail that opens
    /// with twenty lines of facts makes him scroll past them to write his report.
    @Test func theBodyOpensWithTheRidersOwnLine() {
        let lines = FeedbackReport.body(facts()).split(separator: "\n",
                                                       omittingEmptySubsequences: false)
        #expect(lines.first == "What happened")
        #expect(lines[1] == "")
        #expect(lines[2] == "")
        #expect(lines[3] == "App")
    }

    @Test func theAppSectionNamesTheVariantAndTheEngine() {
        let body = FeedbackReport.body(facts())
        #expect(body.contains("  CleanJibe 1.0 (17) · public build"))
        #expect(body.contains("  Analysis engine 0.19.0"))
        #expect(FeedbackReport.body(facts(dev: true))
            .contains("  CleanJibe 1.0 (17) · dev build (TUNING)"))
    }

    /// Absent when nothing is tuned, present the moment something is: an absent line reads
    /// as "nothing unusual", and a "0" would be one more line to skip on every report.
    @Test func tunedThresholdsAreNamedOnlyWhenThereAreSome() {
        #expect(!FeedbackReport.body(facts()).contains("Tuned thresholds"))
        #expect(FeedbackReport.body(facts(dev: true, tuned: 3))
            .contains("  Tuned thresholds: 3 changed from the published defaults"))
    }

    /// The identifier survives beside the friendly name, so a table this file gets wrong —
    /// and it will, the week a new phone ships — still reports something answerable.
    @Test func thePhoneKeepsItsIdentifierBesideItsName() {
        #expect(FeedbackReport.body(facts()).contains("  iPhone 17 Pro Max (iPhone18,2)"))
        #expect(FeedbackFacts.Phone(model: "iPhone42,9", system: "iOS 31.0",
                                    locale: "de_DE").described == "iPhone42,9")
    }

    @Test func theWatchSectionSaysWhatTheLinkKnows() {
        let body = FeedbackReport.body(facts())
        #expect(body.contains("  Garmin fenix 8 · CleanJibe watch app 2.2"))
        #expect(body.contains("  No Apple Watch paired"))
        #expect(body.contains("  Health import off"))

        let unknown = FeedbackFacts.Watch(garminModel: "fenix 8", garminAppVersion: nil,
                                          appleWatchPaired: true, healthImport: true)
        let other = FeedbackReport.body(facts(watch: unknown))
        #expect(other.contains("  Garmin fenix 8 · watch app version unknown "
                               + "(no summary card has arrived yet)"))
        #expect(other.contains("  Apple Watch paired"))
        #expect(other.contains("  Health import on"))
    }

    /// `WCSession` can decline the question entirely, and a mail that guessed "no" would be
    /// stating something it does not know.
    @Test func anUnaskableAppleWatchQuestionIsLeftOut() {
        let quiet = FeedbackFacts.Watch(garminModel: nil, garminAppVersion: nil,
                                        appleWatchPaired: nil, healthImport: false)
        let body = FeedbackReport.body(facts(watch: quiet))
        #expect(body.contains("  No Garmin watch chosen"))
        #expect(!body.contains("Apple Watch"))
    }

    @Test func theLibrarySectionCountsAndBreaksDown() {
        let body = FeedbackReport.body(facts())
        #expect(body.contains("  42 sessions"))
        #expect(body.contains("  intervals.icu 38 · Strava 4"))
    }

    /// The `importSource` column is a `+`-joined set, so one session can be counted under
    /// two doors — which is the answer a duplicate-session report needs.
    @Test func theBreakdownCountsEveryDoorASessionCameInBy() {
        let sources = FeedbackFacts.Library.sources(
            importSources: ["icu", "applewatch+icu", "strava", nil, "applehealth"])
        #expect(sources == [.init(label: "CleanJibe watch app", count: 1),
                            .init(label: "intervals.icu", count: 2),
                            .init(label: "Strava", count: 1),
                            .init(label: "Apple Health", count: 1)])
    }

    // MARK: The session

    @Test func aMailFromASessionCarriesThatSession() {
        let session = FeedbackFacts.Session(
            id: "A1B2C3", date: "30 Aug 2026, 14:07", spot: "Torbole",
            discipline: "Wingfoil", duration: "1:42:11", sourceClass: "a",
            engineStamp: "0.19.0+t3.a41f")
        let body = FeedbackReport.body(facts(session: session))
        #expect(body.contains("  30 Aug 2026, 14:07 · Torbole"))
        #expect(body.contains("  Source class a · Wingfoil · 1:42:11"))
        #expect(body.contains("  Analysed by engine 0.19.0+t3.a41f"))
        #expect(body.contains("  Session id A1B2C3"))
    }

    /// From Settings there is no session, and the section is absent rather than empty.
    @Test func aMailFromSettingsHasNoSessionSection() {
        #expect(!FeedbackReport.body(facts()).contains("Session"))
    }

    @Test func theBodyEndsWhereItCameFrom() {
        #expect(FeedbackReport.body(facts()).hasSuffix("sent from CleanJibe"))
    }

    // MARK: The fallback

    /// The `mailto:` fallback for a phone with no mail account: same address, same subject,
    /// same body, and a body full of `&` and `=` must not truncate the query.
    @Test func theMailtoFallbackCarriesTheSameText() throws {
        let session = FeedbackFacts.Session(
            id: "A&B=C", date: "30 Aug 2026", spot: "Torbole", discipline: nil,
            duration: "1:42:11", sourceClass: "c", engineStamp: nil)
        let all = facts(session: session)
        let url = try #require(FeedbackReport.mailtoURL(all))
        #expect(url.scheme == "mailto")
        #expect(url.path == FeedbackReport.recipient)

        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems)
        #expect(items.first { $0.name == "subject" }?.value == FeedbackReport.subject(all))
        #expect(items.first { $0.name == "body" }?.value == FeedbackReport.body(all))
    }
}
