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

        // The setup section is reachable from the index and holds exactly these three.
        #expect(HelpCatalog.topics(in: .setup).map(\.id)
                == [.icuSetup, .icuTroubleshooting, .icuPrivacy])
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
