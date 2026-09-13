import Foundation
import Testing
@testable import WingFoilKit

/// First-run setup: the intervals.icu guide, the failure→cause mapping behind every
/// message the setup card can show, and the state machine that decides which card it is.
///
/// All three are the sort of thing that is only exercised once per install by hand — the
/// path a returning user never walks again — so it is asserted here instead.
@Suite struct OnboardingTests {

    // MARK: - The written guide

    @Test func setupGuideIsFourNumberedWrittenSteps() {
        let steps = IcuSetupGuide.steps
        #expect(steps.count == 4)
        #expect(steps.map(\.number) == [1, 2, 3, 4])
        for step in steps {
            #expect(!step.title.isEmpty, "step \(step.number) has no title")
            #expect(step.detail.count > 40, "step \(step.number) has a stub detail")
        }
        // Step 1 sends you to intervals.icu; step 4 sends you back into the app.
        #expect(steps[0].link?.url == IcuSetupGuide.intervalsURL)
        #expect(steps[0].link?.url.absoluteString == "https://intervals.icu")
        #expect(steps[3].action == .openIcuSettings)
        // The three facts a first-timer needs and cannot guess.
        #expect(steps[1].detail.lowercased().contains("garmin"))
        #expect(steps[2].detail.contains("Developer Settings"))
        #expect(steps[2].detail.lowercased().contains("free"))
    }

    /// intervals.icu is the *easiest* way in, not the only one. The rationale used to open
    /// "CleanJibe reads your sessions through intervals.icu", which is false — a shared
    /// `.fit` and a Garmin export ZIP both work — and read to a rider who does not want a
    /// third-party account as a wall with no door in it.
    @Test func theRationaleOffersTheManualWayInAsWellAsTheAutomaticOne() {
        let rationale = IcuSetupGuide.rationale
        #expect(rationale.contains("no open API"), "the reason for the detour is missing")
        #expect(rationale.lowercased().contains("easiest"),
                "intervals.icu is stated as the only way in")
        // The alternatives, by name, in the sentence a first-timer actually reads.
        #expect(rationale.contains(".fit"))
        #expect(rationale.contains("ZIP"))
        #expect(rationale.contains("Files"))
        // The short form on the setup card keeps the reason but not the alternatives —
        // that card's reader has already chosen this path.
        #expect(IcuSetupGuide.rationaleShort.contains("no open API"))
    }

    @Test func privacyNoteNamesTheKeychainAndTheOnlyRecipient() {
        let note = IcuSetupGuide.privacyNote
        #expect(note.contains("Keychain"))
        #expect(note.contains("intervals.icu"))
        #expect(note.lowercased().contains("never"))
    }

    @Test func troubleshootingCoversTheFailuresTheAppCanActuallyReport() {
        let entries = IcuSetupGuide.troubleshooting
        #expect(entries.count >= 3)
        #expect(entries.allSatisfy { !$0.term.isEmpty && $0.detail.count > 40 })
        let all = entries.map { $0.term + " " + $0.detail }.joined(separator: " ").lowercased()
        #expect(all.contains("401"))
        #expect(all.contains("garmin"))
        #expect(all.contains("watersport"))
    }

    // MARK: - The help topics built from it

    @Test func setupHelpTopicsAreCompleteAndCarryTheirLinks() {
        let setup = HelpCatalog.topic(.icuSetup)
        #expect(setup.section == .setup)
        // The card and the topic render the *same* steps — asserted, not assumed.
        #expect(setup.items.count == IcuSetupGuide.steps.count)
        #expect(setup.items.first?.term.hasPrefix("1.") == true)
        #expect(setup.items.last?.term.hasPrefix("4.") == true)
        #expect(setup.links.contains { $0.url == IcuSetupGuide.intervalsURL })
        #expect(setup.action == .openIcuSettings)

        let trouble = HelpCatalog.topic(.icuTroubleshooting)
        #expect(trouble.items == IcuSetupGuide.troubleshooting)

        let privacy = HelpCatalog.topic(.icuPrivacy)
        #expect(privacy.body.contains(IcuSetupGuide.privacyNote))

        // The setup section is reachable from the index and holds exactly these ten, in
        // this order — the example session sits second, right after the path it is an
        // alternative to; the Apple Workout app sits third because for a rider with no
        // Garmin it is not a footnote about data quality but the whole way in (ADR-017);
        // Strava and the share sheet follow it for exactly the same reason (ADR-023), with
        // the watch table under them answering "will mine work" once instead of a third of
        // an answer in each; the two intervals.icu troubleshooting topics stay together; and
        // the backup topic sits under them because it is the one a rider reads before he
        // leaves a phone rather than when he arrives on one — with "Sending feedback" last
        // of all, which is the section's way back out: every topic above it is how a session
        // gets in, and that one is what to do when it did not.
        #expect(HelpCatalog.topics(in: .setup).map(\.id)
                == [.icuSetup, .exampleSession, .appleWorkoutApp, .stravaImport,
                    .shareFromWatchApp, .whichWatch, .icuTroubleshooting,
                    .icuPrivacy, .libraryBackup, .sendingFeedback])
    }

    /// The topic for the rider who owns no Garmin (ADR-017). It has one job — get him from
    /// "I have an Apple Watch" to a session in the library — so it has to name the three
    /// steps *and* the two things he would otherwise learn by being disappointed: salt water
    /// kills GPS, and nothing in a Health workout records his wrist.
    @Test func theAppleWorkoutTopicSaysHowToRecordAndWhatIsMissing() {
        let topic = HelpCatalog.topic(.appleWorkoutApp)
        #expect(topic.section == .setup)
        let prose = (topic.body + topic.items.flatMap { [$0.term, $0.detail] })
            .joined(separator: " ").lowercased()
        for phrase in ["surfing", "water sports", "sailing", "import", "health",
                       "above water", "certified", "accelerometer", "automatically"] {
            #expect(prose.contains(phrase), "the Apple Workout topic never mentions \(phrase)")
        }
        // The promise the permission prompt is about to make, made here first.
        #expect(prose.contains("never reads anything else"))
        #expect(HelpCatalog.search("Apple Watch").contains { $0.id == .appleWorkoutApp })
    }

    /// The Strava topic (ADR-023) has one job the others do not: it must say what the source
    /// **costs** before the rider imports, not after he finds the pump card empty and his
    /// speed records marked. Both ceilings Strava puts on the application are named here too,
    /// because "it will not connect" is otherwise a mystery nobody can solve.
    @Test func theStravaTopicSaysWhatItCostsBeforeTheRiderImports() {
        let topic = HelpCatalog.topic(.stravaImport)
        #expect(topic.section == .setup)
        let prose = (topic.body + topic.items.flatMap { [$0.term, $0.detail] })
            .joined(separator: " ").lowercased()
        for phrase in ["uncertified", "pump strokes", "intervals.icu", "never writes",
                       "one connected rider", "fifteen minutes", "disconnect"] {
            #expect(prose.contains(phrase), "the Strava topic never mentions \(phrase)")
        }
        // The one recommendation that saves a rider from importing the worse copy.
        #expect(prose.contains("import it from there instead"))
        #expect(HelpCatalog.search("Strava").contains { $0.id == .stravaImport })
    }

    /// The share-sheet topic exists for the rider whose watch is neither a Garmin nor an
    /// Apple Watch. Two things make it trustworthy rather than merely helpful: every vendor
    /// path carries the date it was checked against that vendor's own help page, and the one
    /// app that *cannot* do it says so rather than being quietly left out.
    @Test func theShareSheetTopicDatesEveryVendorPathAndNamesTheOneThatCannot() {
        let topic = HelpCatalog.topic(.shareFromWatchApp)
        #expect(topic.section == .setup)
        let terms = topic.items.map(\.term)
        for vendor in ["Suunto", "COROS", "Polar", "Garmin"] {
            #expect(terms.contains { $0.hasPrefix(vendor) },
                    "no path for \(vendor)")
        }
        // Dated, every one of them — a menu path with no date on it rots silently.
        #expect(terms.filter { $0.contains("2026") }.count == 4)
        let prose = (topic.body + topic.items.map(\.detail)).joined(separator: " ").lowercased()
        // Garmin's phone app cannot export at all, and the rider is sent somewhere that works
        // rather than left hunting for a menu item that does not exist.
        #expect(prose.contains("cannot export"))
        #expect(prose.contains("intervals.icu"))
        // FIT over GPX/TCX, and why.
        #expect(prose.contains("fit, every time"))
        #expect(prose.contains("uncertified"))
        // Each vendor path links to the page it was verified against.
        #expect(topic.links.count == 4)
        #expect(topic.links.allSatisfy { $0.url.scheme == "https" })
    }

    /// One table, so "will my watch work" is answered in one place. Every door the app has
    /// must appear in it — a row missing here is a rider concluding his watch is unsupported.
    @Test func theWatchTableCoversEveryDoorTheAppHas() {
        let topic = HelpCatalog.topic(.whichWatch)
        #expect(topic.section == .setup)
        let prose = (topic.body + topic.items.flatMap { [$0.term, $0.detail] })
            .joined(separator: " ").lowercased()
        for door in ["garmin", "apple watch", "polar", "suunto", "coros", "strava", "gpx"] {
            #expect(prose.contains(door), "the watch table never mentions \(door)")
        }
        // The two axes the table is actually about.
        #expect(prose.contains("certified"))
        #expect(prose.contains("accelerometer"))
        #expect(topic.items.count == 6)
    }

    /// The backup topic has to answer three questions in order, because a rider who reads
    /// it is deciding whether he needs to do anything at all: does an ordinary phone swap
    /// already cover this (yes), what is actually irrecoverable without it (the metadata),
    /// and can restoring hurt what is already on the phone (no).
    @Test func theBackupTopicSaysWhatIsCoveredAlreadyAndWhatIsNot() {
        let topic = HelpCatalog.topic(.libraryBackup)
        #expect(topic.section == .setup)
        let prose = topic.body.joined(separator: " ").lowercased()
        for phrase in ["new iphone", "icloud", "deleted", "gear", "accelerometer",
                       "additive", "refused"] {
            #expect(prose.contains(phrase), "the backup topic never mentions \(phrase)")
        }
        // The recordings inside are the rider's own, unscrubbed — the opposite promise
        // from `shareFit`, and the one a reader could otherwise get wrong.
        #expect(prose.contains(".fit"))
        #expect(HelpCatalog.search("backup").contains { $0.id == .libraryBackup })
    }

    @Test func setupTopicIsSearchable() {
        #expect(HelpCatalog.search("Developer Settings").contains { $0.id == .icuSetup })
        #expect(HelpCatalog.search("keychain").contains { $0.id == .icuPrivacy })
    }

    // MARK: - Error mapping

    @Test func rejectedKeyMapsToTheRegenerateAdvice() {
        for error in [IcuClient.Error.unauthorized,
                      .http(status: 401, body: "{}"),
                      .http(status: 403, body: "")] {
            let problem = IcuDiagnosis.describe(error)
            #expect(problem.kind == .unauthorized)
            #expect(problem.fix.contains("Developer Settings"))
            #expect(problem.helpTopic == .icuTroubleshooting)
        }
    }

    @Test func networkFailuresAreNotBlamedOnTheKey() {
        let transport = IcuDiagnosis.describe(IcuClient.Error.transport("no HTTP response"))
        #expect(transport.kind == .network)
        let offline = IcuDiagnosis.describe(URLError(.notConnectedToInternet))
        #expect(offline.kind == .network)
        // The distinction is the whole point: neither tells the rider to touch the key.
        #expect(!transport.fix.lowercased().contains("key"))
        #expect(!offline.fix.lowercased().contains("key"))
    }

    @Test func serverErrorsKeepTheStatusAndDropTheBody() {
        let problem = IcuDiagnosis.describe(
            IcuClient.Error.http(status: 502, body: "<html>secret echo</html>"))
        #expect(problem.kind == .server)
        #expect(problem.detail == "HTTP 502")
        // A response body can echo the request back; it never reaches the screen.
        #expect(!problem.message.contains("secret echo"))
        #expect(!problem.alertText.contains("secret echo"))
    }

    @Test func missingKeyAndUnknownErrorsAreStillActionable() {
        #expect(IcuDiagnosis.describe(IcuClient.Error.missingKey).kind == .noKey)
        #expect(IcuDiagnosis.describe(IcuClient.Error.missingKey).helpTopic == .icuSetup)
        #expect(IcuDiagnosis.describe(IcuClient.Error.decoding("bad json")).kind == .unknown)
        #expect(IcuProblem.Kind.allCases.allSatisfy {
            let problem = IcuProblem(kind: $0)
            return !problem.title.isEmpty && problem.message.count > 20 && !problem.fix.isEmpty
        })
    }

    @Test func aSyncThatBroughtNothingBackBlamesTheGarminConnection() {
        var empty = IcuSyncSummary()
        empty.listed = 12                       // rides and runs, no watersports
        let problem = IcuDiagnosis.describe(empty)
        #expect(problem?.kind == .empty)
        #expect(problem?.fix.contains("Garmin") == true)

        // Anything actually landed (or already known) is not a failure.
        var imported = IcuSyncSummary()
        imported.watersports = 3
        imported.imported = 3
        #expect(IcuDiagnosis.describe(imported) == nil)
        var known = IcuSyncSummary()
        known.watersports = 3
        known.alreadyKnown = 3
        #expect(IcuDiagnosis.describe(known) == nil)

        // Watersports listed but every download failed is not "empty" — it is a failure.
        var broken = IcuSyncSummary()
        broken.watersports = 2
        broken.failed = ["a: boom", "b: boom"]
        #expect(IcuDiagnosis.describe(broken)?.kind == .unknown)
    }

    // MARK: - The key check

    private struct StubTransport: IcuTransport {
        let status: Int
        let body: Data

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            (body, HTTPURLResponse(url: request.url!, statusCode: status,
                                   httpVersion: nil, headerFields: nil)!)
        }
    }

    private static let activityList = """
    [{"id":"i1","name":"Nago-Torbole Windsurfen","type":"Windsurf"},
     {"id":"i2","name":"Wingfoiling","type":"Walk"},
     {"id":"i3","name":"Morning Ride","type":"Ride"}]
    """

    @Test func aGoodKeyReportsWhatItCanSee() async {
        let client = IcuClient(apiKey: "k", transport: StubTransport(
            status: 200, body: Data(Self.activityList.utf8)))
        guard case .success(let report) = await IcuDiagnosis.check(client) else {
            Issue.record("expected a successful check")
            return
        }
        #expect(report.activities == 3)
        #expect(report.watersports == 2)                 // the Walk is rescued by its name
        #expect(report.message.contains("Connected"))
        #expect(report.message.contains("2 watersport"))
        #expect(report.caveat == nil)
    }

    @Test func aValidKeyWithNoWatersportsSaysSoRatherThanClaimingSuccess() async {
        let json = """
        [{"id":"i3","name":"Morning Ride","type":"Ride"}]
        """
        let client = IcuClient(apiKey: "k", transport: StubTransport(
            status: 200, body: Data(json.utf8)))
        guard case .success(let report) = await IcuDiagnosis.check(client) else {
            Issue.record("expected a successful check")
            return
        }
        #expect(report.watersports == 0)
        #expect(report.message.contains("none of them a watersport"))
        #expect(report.caveat?.kind == .empty)

        // An account with nothing in it at all still reads as "the key works".
        let bare = IcuConnectionReport(activities: 0, watersports: 0)
        #expect(bare.message.contains("the key works"))
    }

    @Test func aBadKeyCheckFailsWithTheMappedCause() async {
        let client = IcuClient(apiKey: "wrong", transport: StubTransport(
            status: 401, body: Data("unauthorized".utf8)))
        guard case .failure(let problem) = await IcuDiagnosis.check(client) else {
            Issue.record("expected a failed check")
            return
        }
        #expect(problem.kind == .unauthorized)
    }

    @Test func theCheckNeverEchoesTheKeyBack() async {
        let secret = "abcdef0123456789"
        let client = IcuClient(apiKey: secret, transport: StubTransport(
            status: 500, body: Data("Basic API_KEY:\(secret)".utf8)))
        guard case .failure(let problem) = await IcuDiagnosis.check(client) else {
            Issue.record("expected a failed check")
            return
        }
        // Nothing user-visible may carry the secret — not the message, not the crumb.
        #expect(!problem.message.contains(secret))
        #expect(!problem.alertText.contains(secret))
        #expect(!(problem.detail ?? "").contains(secret))
    }

    // MARK: - Onboarding state

    @Test func emptyLibraryWithoutAKeyAsksForSetup() {
        #expect(IcuOnboarding.state(sessionCount: 0, hasKey: false, lastProblem: nil) == .setup)
        // A stale problem cannot outrank a missing key: the fix is the same four steps.
        #expect(IcuOnboarding.state(sessionCount: 0, hasKey: false,
                                    lastProblem: IcuProblem(kind: .network)) == .setup)
    }

    @Test func aStoredKeyPlusAFailedSyncShowsTheCause() {
        let problem = IcuProblem(kind: .unauthorized)
        #expect(IcuOnboarding.state(sessionCount: 0, hasKey: true,
                                    lastProblem: problem) == .problem(problem))
        #expect(IcuOnboarding.state(sessionCount: 0, hasKey: true,
                                    lastProblem: IcuProblem(kind: .empty))
                == .problem(IcuProblem(kind: .empty)))
    }

    @Test func aStoredKeyThatHasNotSyncedYetJustWaits() {
        #expect(IcuOnboarding.state(sessionCount: 0, hasKey: true, lastProblem: nil) == .waiting)
    }

    @Test func aLibraryWithSessionsIsNeverOnboarding() {
        #expect(IcuOnboarding.state(sessionCount: 1, hasKey: false, lastProblem: nil) == .ready)
        #expect(IcuOnboarding.state(sessionCount: 9, hasKey: true,
                                    lastProblem: IcuProblem(kind: .unauthorized)) == .ready)
    }

    @Test func problemsSurviveTheRoundTripThroughUserDefaults() throws {
        // The card must still name the cause after a relaunch, so the problem is stored.
        let problem = IcuProblem(kind: .server, detail: "HTTP 502")
        let data = try JSONEncoder().encode(problem)
        #expect(try JSONDecoder().decode(IcuProblem.self, from: data) == problem)
    }
}

/// The screen in front of the setup card: what it says, and when it is allowed to say it.
///
/// The show-once rule is the whole risk here. Every other outcome of getting it wrong is
/// invisible on a device that has been used once — which is every device the author owns.
@Suite struct WelcomeTests {

    // MARK: - What it says

    @Test func theWelcomeIsWrittenRatherThanStubbed() {
        #expect(!WelcomeGuide.headline.isEmpty)
        #expect(WelcomeGuide.lede.count > 200, "the one paragraph is the whole pitch")
        #expect(WelcomeGuide.highlights.count >= 4)
        for highlight in WelcomeGuide.highlights {
            #expect(!highlight.term.isEmpty)
            #expect(highlight.detail.count > 40, "\(highlight.term) has a stub detail")
        }
        for title in [WelcomeGuide.tryExampleTitle, WelcomeGuide.connectTitle,
                      WelcomeGuide.laterTitle] {
            #expect(!title.isEmpty)
        }
        for detail in [WelcomeGuide.tryExampleDetail, WelcomeGuide.connectDetail,
                       WelcomeGuide.laterDetail] {
            #expect(detail.count > 40)
        }
    }

    /// The first screen a wingfoiler ever sees must not open in a neighbouring sport's
    /// vocabulary. "GP3S" and "alpha 500" are GPS-speedsurfing terms; the Records topic is
    /// where somebody who asked for them can learn them.
    @Test func theWelcomeUsesNoSpeedsurfingJargon() {
        let prose = ([WelcomeGuide.headline, WelcomeGuide.lede]
                     + WelcomeGuide.highlights.map { $0.term + " " + $0.detail }
                     + [WelcomeGuide.tryExampleDetail, WelcomeGuide.connectDetail,
                        WelcomeGuide.laterDetail])
            .joined(separator: " ")
            .lowercased()
        for jargon in ["gp3s", "alpha 500", "ciq", "connect iq", "class a", "class b"] {
            #expect(!prose.contains(jargon), "the welcome says \"\(jargon)\"")
        }
        // The windows are named in seconds and metres instead.
        #expect(prose.contains("2 seconds"))
        #expect(prose.contains("nautical mile"))
    }

    /// The vocabulary the rest of the app uses. A welcome that promised something in words
    /// the session page never repeats would teach the wrong ones.
    @Test func theWelcomeSpeaksTheAppsOwnVocabulary() {
        let prose = ([WelcomeGuide.headline, WelcomeGuide.lede]
                     + WelcomeGuide.highlights.map { $0.term + " " + $0.detail })
            .joined(separator: " ")
            .lowercased()
        for word in ["foil", "flight", "touchdown", "jibe", "streak", "record"] {
            #expect(prose.contains(word), "the welcome never says \"\(word)\"")
        }
        // The three verdicts, in the ladder's own order.
        #expect(WelcomeGuide.lede.contains("flew through"))
        #expect(WelcomeGuide.lede.contains("touched down"))
        #expect(WelcomeGuide.lede.contains("fell in"))
    }

    /// All three offers name the thing behind them, so no button is a surprise. "Later"
    /// used to be a bare verb, which told a rider holding a `.fit` file nothing at all.
    @Test func theThreeOffersNameWhatIsBehindThem() {
        #expect(WelcomeGuide.tryExampleDetail.contains(ExampleSession.place
            .split(separator: ",").last!.trimmingCharacters(in: .whitespaces)))
        #expect(WelcomeGuide.connectDetail.contains("intervals.icu"))
        // …and says *why* a stranger's name is on a first-run screen.
        #expect(WelcomeGuide.connectDetail.contains("no open API"))
        #expect(WelcomeGuide.laterDetail.contains(".fit"))
        #expect(WelcomeGuide.laterDetail.contains("Files"))
    }

    // MARK: - When it is allowed to say it

    @Test func aFreshInstallIsWelcomed() {
        #expect(WelcomePrompt.shouldShow(hasSeen: false, sessionCount: 0, hasKey: false))
    }

    @Test func onceIsTheWholeContract() {
        #expect(!WelcomePrompt.shouldShow(hasSeen: true, sessionCount: 0, hasKey: false))
        #expect(!WelcomePrompt.shouldMarkSeenSilently(hasSeen: true, sessionCount: 0,
                                                      hasKey: false))
    }

    /// The upgrade case: a rider mid-season must not be greeted as a stranger.
    @Test func anInstallWithAHistoryIsTreatedAsAlreadyWelcomed() {
        #expect(WelcomePrompt.isAlreadyWelcomed(sessionCount: 12, hasKey: false))
        #expect(WelcomePrompt.isAlreadyWelcomed(sessionCount: 0, hasKey: true))
        #expect(!WelcomePrompt.isAlreadyWelcomed(sessionCount: 0, hasKey: false))
        for (count, key) in [(12, false), (0, true), (12, true)] {
            #expect(!WelcomePrompt.shouldShow(hasSeen: false, sessionCount: count,
                                              hasKey: key))
            // …and the flag is spent anyway, so emptying the library later cannot
            // resurrect the screen.
            #expect(WelcomePrompt.shouldMarkSeenSilently(hasSeen: false,
                                                         sessionCount: count, hasKey: key))
        }
    }

    /// Deferral, not refusal — the same etiquette the notification offer keeps.
    @Test func aBusyScreenDefersRatherThanCancels() {
        #expect(!WelcomePrompt.shouldShow(hasSeen: false, sessionCount: 0, hasKey: false,
                                          isPresenting: true))
        #expect(WelcomePrompt.shouldShow(hasSeen: false, sessionCount: 0, hasKey: false,
                                         isPresenting: false))
        // A deferral must not be mistaken for evidence that the rider has been welcomed.
        #expect(!WelcomePrompt.shouldMarkSeenSilently(hasSeen: false, sessionCount: 0,
                                                      hasKey: false))
    }
}
