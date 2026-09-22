import Foundation
import Testing
@testable import WingFoilKit

/// **The beta's update reminder** (docs/presentation/status-feedback-start-widgets-ipad.md, "The beta's update reminder";
/// docs/channels.md, beta furniture). The app fetches the file and draws the screens; this
/// suite holds the one thing that decides whether a rider sees anything at all.
@Suite struct UpdateVerdictTests {

    // MARK: - The floor

    @Test func aBuildAtTheFloorIsCurrent() {
        #expect(UpdateVerdict.decide(minBuild: 60, level: .remind,
                                     runningBuild: 60, dismissedMinBuild: nil) == .current)
    }

    /// `minBuild` is the oldest build still worth a report, not the newest that exists — the
    /// dev build cut this morning is ahead of the file and must never be told to go back.
    @Test func aBuildAboveTheFloorIsCurrent() {
        #expect(UpdateVerdict.decide(minBuild: 60, level: .insist,
                                     runningBuild: 61, dismissedMinBuild: nil) == .current)
    }

    @Test func aBuildBelowTheFloorReminds() {
        #expect(UpdateVerdict.decide(minBuild: 60, level: .remind,
                                     runningBuild: 59, dismissedMinBuild: nil) == .remind)
    }

    @Test func insistIsTheWholeScreen() {
        #expect(UpdateVerdict.decide(minBuild: 60, level: .insist,
                                     runningBuild: 59, dismissedMinBuild: nil) == .insist)
    }

    // MARK: - The dismissal

    @Test func dismissingThisNumberSilencesTheLine() {
        #expect(UpdateVerdict.decide(minBuild: 60, level: .remind,
                                     runningBuild: 59, dismissedMinBuild: 60) == .dismissed)
    }

    /// The dismissal is kept against the number, so the next raise asks again by itself and
    /// nobody has to remember to clear anything.
    @Test func raisingTheNumberAsksAgain() {
        #expect(UpdateVerdict.decide(minBuild: 61, level: .remind,
                                     runningBuild: 59, dismissedMinBuild: 60) == .remind)
    }

    /// A file that lowers its floor under a rider who has already waved a higher one away
    /// says nothing new: he has answered this question.
    @Test func loweringTheNumberStaysDismissed() {
        #expect(UpdateVerdict.decide(minBuild: 59, level: .remind,
                                     runningBuild: 58, dismissedMinBuild: 60) == .dismissed)
    }

    /// A dismissal answers a line, never a screen.
    @Test func insistIgnoresTheDismissal() {
        #expect(UpdateVerdict.decide(minBuild: 60, level: .insist,
                                     runningBuild: 59, dismissedMinBuild: 60) == .insist)
    }

    // MARK: - Failure is silence

    @Test(arguments: [0, -1])
    func aBuildNumberWeCannotReadSaysNothing(running: Int) {
        #expect(UpdateVerdict.decide(minBuild: 60, level: .insist,
                                     runningBuild: running, dismissedMinBuild: nil) == .current)
    }

    @Test(arguments: [0, -1])
    func aFloorWeCannotReadSaysNothing(floor: Int) {
        #expect(UpdateVerdict.decide(minBuild: floor, level: .insist,
                                     runningBuild: 59, dismissedMinBuild: nil) == .current)
    }

    // MARK: - What the two other halves promise

    @Test func onlyTheTwoLoudVerdictsPutAnythingOnScreen() {
        #expect(UpdateVerdict.current.isSilent)
        #expect(UpdateVerdict.dismissed.isSilent)
        #expect(!UpdateVerdict.remind.isSilent)
        #expect(!UpdateVerdict.insist.isSilent)
    }

    /// Settings names all four, and none of them names a build number — the row prints the
    /// running build beside the sentence and two spellings of it would read as two facts.
    @Test func everyVerdictHasALineAndNoneCarriesANumber() {
        for verdict in UpdateVerdict.allCases {
            #expect(!verdict.label.isEmpty)
            #expect(verdict.label.rangeOfCharacter(from: .decimalDigits) == nil)
        }
    }

    /// A typo in the file reminds; it never escalates to a screen nobody can get past.
    @Test func anUnknownLevelIsNotInsist() {
        #expect(UpdateLevel(rawValue: "shout") == nil)
        #expect(UpdateLevel(rawValue: "remind") == .remind)
        #expect(UpdateLevel(rawValue: "insist") == .insist)
    }
}
