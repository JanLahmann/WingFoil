import Foundation
import Testing
@testable import WingFoilKit

/// The feedback mail. Every assertion here is about a fact a reply would need and a
/// reporter would never think to type: which build, which engine, whether the thresholds
/// were standard, and which session the complaint is about.
@Suite struct FeedbackReportTests {

    private func facts(dev: Bool = false, channel: HelpChannel? = nil, tuned: Int = 0,
                       watch: FeedbackFacts.Watch? = nil,
                       session: FeedbackFacts.Session? = nil) -> FeedbackFacts {
        FeedbackFacts(
            app: .init(version: "1.0", build: "17",
                       channel: channel ?? (dev ? .dev : .release),
                       engineVersion: "0.20.0", tunedThresholds: tuned),
            phone: .init(model: "iPhone18,2", system: "iOS 26.0", locale: "en_DE"),
            watch: watch ?? .init(garminModel: "fenix 8", garminAppVersion: "2.2",
                                  appleWatchPaired: false, healthImport: false),
            library: .init(sessionCount: 42,
                           sources: [.init(label: "intervals.icu", count: 38),
                                     .init(label: "Strava", count: 4)]),
            session: session)
    }

    // MARK: The subject

    /// The build number, not the marketing version: the three channels of a release share
    /// the latter and differ only in the former (docs/channels.md).
    @Test func theSubjectNamesTheBuildAndTheWatch() {
        #expect(FeedbackReport.subject(facts())
                == "CleanJibe feedback · build 17 · fenix 8")
    }

    @Test func theDevBuildSaysSoInTheSubject() {
        #expect(FeedbackReport.subject(facts(dev: true))
                == "CleanJibe feedback · build 17 dev · fenix 8")
    }

    @Test func aRiderWithNoWatchStillGetsASubject() {
        let none = FeedbackFacts.Watch(garminModel: nil, garminAppVersion: nil,
                                       appleWatchPaired: nil, healthImport: true)
        #expect(FeedbackReport.subject(facts(watch: none))
                == "CleanJibe feedback · build 17 · no watch")
    }

    // MARK: The body

    /// The rider's own half comes first, before a single diagnostic — a mail that opens
    /// with twenty lines of facts makes him scroll past them to write his report.
    ///
    /// Three labelled blanks now, not one: the three follow-up mails "it said 3 jibes" used
    /// to cost, asked in advance. Each label owns exactly two lines after it — one for the
    /// answer, one of air — asserted by index, because a field that quietly lost its blank
    /// line would still read fine in a diff and badly in a mail client.
    @Test func theBodyOpensWithThreeLabelledBlanks() {
        let lines = FeedbackReport.body(facts()).split(separator: "\n",
                                                       omittingEmptySubsequences: false)
        #expect(lines[0] == "What happened, or what you would like:")
        #expect(lines[1] == "")
        #expect(lines[2] == "")
        #expect(lines[3] == "What you expected instead:")
        #expect(lines[4] == "")
        #expect(lines[5] == "")
        #expect(lines[6] == "Which session, its date and spot, if it is about one:")
        #expect(lines[7] == "")
        #expect(lines[8] == "")
    }

    /// A wish is as welcome as a fault, and the mail is the fifth place that says so — the
    /// same sentence as the menu row, the page footers, the welcome screen and Settings.
    @Test func theMailInvitesIdeasAsWellAsFaults() {
        #expect(FeedbackReport.body(facts()).contains(FeedbackInvitation.sentence))
        #expect(FeedbackInvitation.welcomeSentence
                .contains("Ideas and wishes are as welcome as bugs"))
        // "·", like every other separator the app draws; never an em dash.
        #expect(!FeedbackInvitation.welcomeSentence.contains("—"))
    }

    /// The rule between the two halves, and the sentence that makes the facts under it
    /// deletable rather than merely present.
    @Test func theFactsSitUnderARuleThatSaysWhatTheyAre() {
        let lines = FeedbackReport.body(facts()).split(separator: "\n",
                                                       omittingEmptySubsequences: false)
        let rule = try! #require(lines.firstIndex(of: Substring(FeedbackReport.Separator.rule)))
        #expect(lines[rule + 1] == Substring(FeedbackReport.Separator.note))
        #expect(lines[rule + 1].contains("Delete any line you would rather not send"))
        #expect(lines[rule + 2] == "")
        #expect(lines[rule + 3] == "App")
        // Everything the rider writes is above it; every diagnostic is below it.
        #expect(rule > lines.firstIndex(of: "What you expected instead:")!)
    }

    /// From the share sheet the app already knows which afternoon, so the third question is
    /// answered for him — on the first of the label's two lines, not as a fourth line.
    @Test func theSessionQuestionIsAnsweredWhenTheMailCameFromOne() {
        let session = FeedbackFacts.Session(
            id: "A1B2C3", date: "30 August 2026", spot: "Torbole",
            discipline: "Wingfoil", duration: "1:42:11", sourceClass: "a",
            engineStamp: nil)
        let lines = FeedbackReport.body(facts(session: session))
            .split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines[6] == "Which session, its date and spot, if it is about one:")
        #expect(lines[7] == "30 August 2026 · Torbole")
        #expect(lines[8] == "")
    }

    /// A session with no spot named still answers the question, with the half it has.
    @Test func aSessionWithNoSpotStillFillsTheDate() {
        let session = FeedbackFacts.Session(
            id: "A1B2C3", date: "30 August 2026", spot: nil, discipline: nil,
            duration: "1:42:11", sourceClass: "c", engineStamp: nil)
        let lines = FeedbackReport.body(facts(session: session))
            .split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines[7] == "30 August 2026")
    }

    /// **One word per channel** (22 September 2026). The line read "public build" on the
    /// App Store app and on the public beta alike, so a reader answering a report could not
    /// tell a tester's phone from a buyer's — and nearly every report comes from the beta
    /// (docs/review-checklist.md, pattern L).
    @Test func theAppSectionNamesTheChannelAndTheEngine() {
        let body = FeedbackReport.body(facts())
        #expect(body.contains("  CleanJibe 1.0 (17) · release build"))
        #expect(body.contains("  Analysis engine 0.20.0"))
        #expect(!body.contains("public build"))
        #expect(FeedbackReport.body(facts(channel: .beta))
            .contains("  CleanJibe 1.0 (17) · beta build"))
        #expect(FeedbackReport.body(facts(channel: .dev))
            .contains("  CleanJibe 1.0 (17) · dev build, TUNING on"))
    }

    /// Three channels, three words, and only the dev one is the `TUNING` variant — the
    /// subject's "dev" suffix and the body's line have to agree about that.
    @Test func everyChannelHasItsOwnWordAndOnlyDevIsTuning() {
        let words: [HelpChannel: String] = [.release: "release build", .beta: "beta build",
                                            .dev: "dev build, TUNING on"]
        for channel in HelpChannel.allCases {
            let these = facts(channel: channel)
            #expect(FeedbackReport.body(these).contains("  CleanJibe 1.0 (17) · "
                                                        + words[channel]!))
            #expect(these.app.isDev == (channel == .dev))
            #expect(FeedbackReport.subject(these).contains("build 17 dev")
                    == (channel == .dev))
        }
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
        #expect(other.contains("  Garmin fenix 8 · watch app version unknown, "
                               + "no summary card has arrived yet"))
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

    /// The App Store build has no Health door and no Apple Watch app (docs/channels.md), so
    /// it passes both facts as nil — and a report that answered either would be describing
    /// a switch the reader cannot find.
    @Test func aChannelWithoutTheDoorReportsNeitherHealthNorTheWatch() {
        let release = FeedbackFacts.Watch(garminModel: nil, garminAppVersion: nil,
                                          appleWatchPaired: nil, healthImport: nil)
        let body = FeedbackReport.body(facts(watch: release))
        #expect(!body.contains("Health import"))
        #expect(!body.contains("Apple Watch"))
        #expect(body.contains("  No Garmin watch chosen"))
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

    // MARK: - Sending one session to the developer (beta)

    /// The session the analysis mail is about, with everything only that mail carries.
    private var analysed: FeedbackFacts.Session {
        FeedbackFacts.Session(
            id: "A1B2C3", date: "30 August 2026", spot: "Torbole",
            discipline: "Wingfoil", duration: "1:42:11", sourceClass: "a",
            engineStamp: "0.23.0",
            distance: "18.4 km",
            tally: "18 flew through \u{00B7} 4 touchdown \u{00B7} 2 fell in",
            windSource: "estimate \u{00B7} axis 212\u{00B0}",
            divergences: ["Best 2 s: watch 24.10 kn, phone 23.80 kn, delta 0.30 kn"])
    }

    /// Named for the afternoon, not for the build: a mailbox sorted by subject then groups
    /// the mails about one session, and the build is under the rule with the rest.
    @Test func theAnalysisSubjectNamesTheSession() {
        #expect(SessionAnalysisMail.subject(date: "30 August 2026")
                == "CleanJibe session 30 August 2026 \u{00B7} for analysis")
    }

    /// The rider's half first, then what he is agreeing to, then the rule. Asserted by
    /// index for the reason the feedback mail's own opening is: a lost blank line reads
    /// fine in a diff and badly in a mail client.
    @Test func theAnalysisBodyOpensWithTheNoteAndTheConsent() {
        let body = SessionAnalysisMail.body(facts(session: analysed),
                                            comment: "  jibe 7 says touchdown, it flew  ",
                                            attachment: .originalRecording(
                                                filename: "2026-08-30-torbole.fit"))
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines[0] == "What looks wrong:")
        #expect(lines[1] == "jibe 7 says touchdown, it flew", "the comment is trimmed")
        #expect(lines[2] == "")
        #expect(lines[3] == SessionAnalysisMail.consent)
        #expect(lines[4] == "")
        #expect(lines[5] == FeedbackReport.Separator.rule)
        #expect(lines[6] == FeedbackReport.Separator.note)
    }

    /// An empty comment still leaves a labelled, empty field rather than collapsing the
    /// mail's first two lines into one — the same shape a filled one has.
    @Test func anEmptyCommentKeepsItsField() {
        let lines = SessionAnalysisMail.body(facts(session: analysed), comment: "",
                                             attachment: .none)
            .split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines[0] == "What looks wrong:")
        #expect(lines[1] == "")
        #expect(lines[3] == SessionAnalysisMail.consent)
    }

    /// The consent sentence says four things and no more: what is in the file, what was
    /// taken out of it, what it is for, and what will not happen to it. It is the sentence
    /// the sheet shows above the button, so the screen and the mail cannot say different
    /// things.
    @Test func theConsentSentenceSaysWhatIsInTheFile() {
        let consent = SessionAnalysisMail.consent
        #expect(consent.contains("track"))
        #expect(consent.contains("heart rate"))
        #expect(consent.contains("stripped of your watch's serial number and profile"))
        #expect(consent.contains("never published"))
        #expect(consent.split(separator: ".").count == 4)
    }

    /// The same fact sheet the feedback mail prints, plus this session's headline numbers
    /// and the watch-vs-phone rows. Two mails, one block, so a reader answering either is
    /// reading the same lines in the same order.
    @Test func theAnalysisBodyCarriesTheDiagnosticsAndTheHeadlineNumbers() {
        let body = SessionAnalysisMail.body(facts(session: analysed), comment: "x",
                                            attachment: .originalRecording(
                                                filename: "2026-08-30-torbole.fit"))
        for expected in ["CleanJibe 1.0 (17) \u{00B7} release build",
                         "Analysis engine 0.20.0",
                         "iPhone 17 Pro Max (iPhone18,2)",
                         "42 sessions",
                         "30 August 2026 \u{00B7} Torbole",
                         "Source class a \u{00B7} Wingfoil \u{00B7} 1:42:11",
                         "Distance 18.4 km",
                         "Jibes 18 flew through \u{00B7} 4 touchdown \u{00B7} 2 fell in",
                         "Wind estimate \u{00B7} axis 212\u{00B0}",
                         "Session id A1B2C3",
                         "Attached",
                         "2026-08-30-torbole.fit",
                         "Watch and phone disagree",
                         "Best 2 s: watch 24.10 kn, phone 23.80 kn, delta 0.30 kn"] {
            #expect(body.contains(expected), "the mail never says \(expected)")
        }
        #expect(body.hasSuffix("sent from CleanJibe"))
    }

    /// A session with no summary card behind it has nothing to disagree with, so the block
    /// is absent rather than present and empty.
    @Test func theDivergenceBlockIsAbsentWhenNothingDisagrees() {
        let quiet = FeedbackFacts.Session(
            id: "A1B2C3", date: "30 August 2026", spot: nil, discipline: nil,
            duration: "1:42:11", sourceClass: "b", engineStamp: nil)
        let body = SessionAnalysisMail.body(facts(session: quiet), comment: "x",
                                            attachment: .none)
        #expect(!body.contains(SessionAnalysisMail.divergenceHeading))
        // And the headline lines are absent too, rather than printed as zeros: a mail that
        // said "0.0 km" would send a reader looking for a bug in the distance.
        #expect(!body.contains("Distance"))
        #expect(!body.contains("Jibes "))
    }

    /// Three attachments, three sentences. A session that arrived as positions says so, and
    /// a session with nothing archived says *that* rather than leaving the reader to
    /// discover the missing file after he has opened the mail.
    @Test func theAttachmentSaysWhichFileItIs() {
        func attached(_ attachment: SessionAnalysisMail.Attachment) -> String {
            SessionAnalysisMail.body(facts(session: analysed), comment: "x",
                                     attachment: attachment)
        }
        #expect(attached(.originalRecording(filename: "a.fit"))
                .contains("The original recording, as it was imported."))
        #expect(attached(.derivedTrack(filename: "a.gpx"))
                .contains("arrived without a recording of its own"))
        #expect(attached(.none).contains("No recording could be read for this session."))
    }

    /// The fallback route. No URL scheme carries an attachment, so the body goes alone and
    /// the caller says so; what must not happen is a body cut short at an ampersand a
    /// rider typed.
    @Test func theAnalysisMailtoSurvivesAnAmpersand() throws {
        let subject = SessionAnalysisMail.subject(date: "30 August 2026")
        let body = SessionAnalysisMail.body(facts(session: analysed),
                                            comment: "3 jibes & 2 tacks, +1 fall?",
                                            attachment: .none)
        let url = try #require(SessionAnalysisMail.mailtoURL(subject: subject, body: body))
        #expect(url.scheme == "mailto")
        #expect(url.path == FeedbackReport.recipient)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems)
        #expect(items.first { $0.name == "subject" }?.value == subject)
        #expect(items.first { $0.name == "body" }?.value == body)
    }
}
