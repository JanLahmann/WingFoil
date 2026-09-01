import Foundation
import Testing
@testable import WingFoilKit

/// The clip around the replay: the two cards, the rider's photos, and the length the rate
/// picker quotes once all of them are in it.
///
/// `ReplayDriverTests` pins the *replay's* run times on the 30 Aug Torbole golden. This suite
/// extends exactly those numbers rather than re-deriving them: every expectation below is a
/// pinned driver time plus a card, plus a pause, plus a slide — so a change to the pacing
/// fails there, and a change to the clip's furniture fails here.
@Suite struct ReplayStoryboardTests {

    /// 2026-08-30 Torbole: 645 s of session and twelve commentary lines.
    private func torbole() throws -> SessionAnalysis {
        let url = testFixturesDir.appendingPathComponent(
            "goldens/2026-08-30-1407_nago-torbole-windsurfen_ciq.expected.json")
        return try JSONDecoder().decode(SessionAnalysis.self, from: Data(contentsOf: url))
    }

    private let span = 0.0...645.0
    /// The afternoon the clip is of: 14:07 CEST, which is what the fixture's filename says.
    private let startedAt = Date(timeIntervalSince1970: 1_788_091_620)
    private let cest = TimeZone(secondsFromGMT: 2 * 3600)!

    private func script() throws -> [ReplayMilestone] {
        ReplayCommentary.make(try torbole(), span: span, timeZone: fixtureZone)
    }

    // MARK: - Length

    /// The number under each speed in the setup sheet. The replay's own times are
    /// `ReplayDriverTests`' pinned 77.70 / 34.44 / 22.52; the cards add the same 6.5 s to all
    /// three, which is why they matter most at 60× — a fifth of that clip is bookends.
    @Test func theCardsExtendEveryClipByTheSameSixAndAHalfSeconds() throws {
        let milestones = try script()
        let replay: [Double: Double] = [10: 77.70, 30: 34.44, 60: 22.52]

        for (rate, runWallS) in replay {
            let board = ReplayStoryboard.make(span: span, rate: rate, milestones: milestones, timeZone: fixtureZone)
            #expect(abs(board.replayWallS - runWallS) < 0.05)
            #expect(board.photoWallS == 0)
            // 2.5 s of title + 4 s of outro, on top of the driver's own run.
            #expect(abs(board.runWallS - (runWallS + 6.5)) < 0.05,
                    "\(Int(rate))× should now offer about \(runWallS + 6.5) s, got \(board.runWallS)")
        }
    }

    /// Asked for a **length**, the storyboard builds its driver from the script that length can
    /// carry rather than from everything the session had to say.
    ///
    /// The rate-taking factory is the raw one and stays raw — a caller that hands it twelve
    /// milestones gets twelve dips, which is what "Full detail" and the scrubber's own speeds
    /// want. It is the target-taking one that budgets, because a target is a promise and the
    /// twelfth dip is what used to break it (`ReplayPacing`).
    @Test func askingForALengthBuildsTheDriverFromTheScriptThatFits() throws {
        let milestones = try script()
        #expect(milestones.count == 12)

        #expect(ReplayStoryboard.make(span: span, rate: 30, milestones: milestones,
                                      timeZone: fixtureZone).driver.easeAt.count == 12)
        for (target, lines) in [(10.0, 4), (25.0, 8), (60.0, 12)] {
            let board = ReplayStoryboard.make(span: span, targetWallS: target,
                                              milestones: milestones, timeZone: fixtureZone)
            #expect(board.driver.easeAt.count == lines,
                    "\(Int(target)) s has room for \(lines) lines")
            // The dips are on instants the session actually named, never on invented ones.
            #expect(Set(board.driver.easeAt).isSubset(of: Set(milestones.map(\.t))))
        }
    }

    /// A session with no duration has no clip at all — not a 6.5 s clip of two cards over a
    /// replay that never moves. The cinema view reads this to know it has nothing to record.
    @Test func aSessionWithNoDurationHasNoClip() {
        let board = ReplayStoryboard.make(span: 42.0...42.0, rate: 30, timeZone: fixtureZone)
        #expect(board.runWallS == 0)
        #expect(board.driver.hasFinished(board.driver.start))
    }

    /// `.bare` is the shape the clip had before it grew furniture: the driver's number and
    /// nothing else, photos included (a timing with no photo budget carries no photos).
    @Test func theBareTimingIsExactlyTheReplay() throws {
        let milestones = try script()
        let board = ReplayStoryboard.make(
            span: span, rate: 30, milestones: milestones,
            photos: [.init(id: "a", takenAt: startedAt.addingTimeInterval(100))],
            startedAt: startedAt, timeZone: fixtureZone, timing: .bare)
        #expect(abs(board.runWallS - 34.44) < 0.05)
        #expect(board.splices.isEmpty)
        #expect(board.slideshow.isEmpty)
    }

    // MARK: - Where the photos go

    /// A photo shot during the session splices in at the moment it was shot; one that cannot
    /// say when it was taken goes to the closing slideshow rather than being guessed at.
    @Test func aDatedPhotoLandsOnItsOwnMomentAndAnUndatedOneGoesToTheEnd() throws {
        let board = ReplayStoryboard.make(
            span: span, rate: 30, milestones: try script(),
            photos: [.init(id: "jibe", takenAt: startedAt.addingTimeInterval(292)),
                     .init(id: "screenshot", takenAt: nil),
                     .init(id: "launch", takenAt: startedAt.addingTimeInterval(40))],
            startedAt: startedAt, timeZone: fixtureZone)

        // In time order, not picked order — the replay can only pass them one way.
        #expect(board.splices.map(\.photo) == ["launch", "jibe"])
        #expect(board.splices.map(\.t) == [40, 292])
        #expect(board.slideshow == ["screenshot"])

        // Two 2 s pauses and one 1.5 s slide on top of the 34.44 s replay and 6.5 s of cards.
        #expect(board.photoWallS == 5.5)
        #expect(abs(board.runWallS - (34.44 + 6.5 + 5.5)) < 0.05)
    }

    /// A picture from before the launch or after the drive home is not a picture of the
    /// session. It still goes in the clip — the rider chose it — but at the end, where it
    /// makes no claim about when it happened.
    @Test func aPhotoOutsideTheSessionIsNotPlacedInsideIt() {
        #expect(ReplayStoryboard.sessionTime(of: startedAt.addingTimeInterval(300),
                                             startedAt: startedAt, in: span) == 300)
        #expect(ReplayStoryboard.sessionTime(of: startedAt, startedAt: startedAt,
                                             in: span) == 0)
        #expect(ReplayStoryboard.sessionTime(of: startedAt.addingTimeInterval(645),
                                             startedAt: startedAt, in: span) == 645)
        #expect(ReplayStoryboard.sessionTime(of: startedAt.addingTimeInterval(-1),
                                             startedAt: startedAt, in: span) == nil)
        #expect(ReplayStoryboard.sessionTime(of: startedAt.addingTimeInterval(646),
                                             startedAt: startedAt, in: span) == nil)

        let board = ReplayStoryboard.make(
            span: span, rate: 30,
            photos: [.init(id: "car-park", takenAt: startedAt.addingTimeInterval(4000))],
            startedAt: startedAt, timeZone: fixtureZone)
        #expect(board.splices.isEmpty)
        #expect(board.slideshow == ["car-park"])
    }

    /// Without a `startedAt` there is no way to turn a wall-clock EXIF date into a position on
    /// the session clock, so every photo falls to the slideshow. Degrading rather than
    /// guessing: a photo placed against an assumed start would be placed confidently and
    /// wrongly.
    @Test func withNoSessionStartEveryPhotoIsASlide() {
        let board = ReplayStoryboard.make(
            span: span, rate: 30,
            photos: [.init(id: "a", takenAt: startedAt.addingTimeInterval(100)),
                     .init(id: "b", takenAt: startedAt.addingTimeInterval(200))], timeZone: fixtureZone)
        #expect(board.splices.isEmpty)
        #expect(board.slideshow == ["a", "b"])
    }

    /// The cap is applied to the order the rider picked in, before anything is sorted by time
    /// — so the six that survive are the six he chose first, whenever they happened.
    @Test func theCapKeepsTheFirstSixPickedAndNotTheFirstSixShot() {
        // Picked newest-first, which is what a photo grid hands you.
        let photos = (0..<8).map {
            ReplayStoryboard.Photo(id: "p\($0)",
                                   takenAt: startedAt.addingTimeInterval(600 - Double($0) * 60))
        }
        let board = ReplayStoryboard.make(span: span, rate: 30, photos: photos,
                                          startedAt: startedAt, timeZone: fixtureZone)
        #expect(board.splices.count == 6)
        #expect(Set(board.splices.map(\.photo)) == Set(["p0", "p1", "p2", "p3", "p4", "p5"]))
        // …and *played* oldest-first, because a replay passes them in one order only.
        #expect(board.splices.map(\.t) == [300, 360, 420, 480, 540, 600])
    }

    /// Two frames of one burst are two splices, in the order they were shot. Deliberately not
    /// merged: at 30× they are a tenth of a wall second apart, so the clip shows them back to
    /// back and the pair reads as one four-second interlude.
    @Test func aBurstPlaysBackToBackInTheOrderItWasShot() {
        let board = ReplayStoryboard.make(
            span: span, rate: 30,
            photos: [.init(id: "burst-1", takenAt: startedAt.addingTimeInterval(292)),
                     .init(id: "burst-2", takenAt: startedAt.addingTimeInterval(292))],
            startedAt: startedAt, timeZone: fixtureZone)
        #expect(board.splices.map(\.photo) == ["burst-1", "burst-2"])
        #expect(board.photoWallS == 4)
    }

    /// The cinema loop's own question, asked by count rather than by position — a splice
    /// pauses the replay *at* its instant, so "the next one after the playhead" would fire the
    /// same photo forever.
    @Test func theNextSpliceIsAskedForByCount() {
        let board = ReplayStoryboard.make(
            span: span, rate: 30,
            photos: [.init(id: "a", takenAt: startedAt.addingTimeInterval(100)),
                     .init(id: "b", takenAt: startedAt.addingTimeInterval(200))],
            startedAt: startedAt, timeZone: fixtureZone)
        #expect(board.nextSplice(shown: 0)?.photo == "a")
        #expect(board.nextSplice(shown: 1)?.photo == "b")
        #expect(board.nextSplice(shown: 2) == nil)
        #expect(board.nextSplice(shown: -1) == nil)
    }

    // MARK: - The two cards

    /// The opening card is the commentary's opening bookend, laid out rather than spoken: the
    /// same place string, the same POSIX 24-hour clock, and the share card's own long date.
    @Test func theTitleCardSpeaksTheCommentarysOpeningBookend() {
        let card = ReplayTitleCard.make(place: "Nago-Torbole Windsurfen",
                                        startedAt: startedAt, timeZone: cest)
        #expect(card.place == "Nago-Torbole Windsurfen")
        #expect(card.dateLine == "30 August 2026 · 14:07")
        // The two halves come from the two existing helpers and must still agree with them.
        #expect(ReplayCommentary.startLine(place: "Torbole", startedAt: startedAt,
                                           timeZone: cest)
                == "Torbole, 14:07 — session start")
        #expect(ShareCardStats.dateLine(startedAt, timeZone: cest) == "30 August 2026")
    }

    /// No place and no date invents neither. The card then carries the session's own title,
    /// which the view supplies, and nothing else.
    @Test func theTitleCardDegradesRatherThanInventing() {
        #expect(ReplayTitleCard.make(place: "  ", startedAt: nil, timeZone: fixtureZone).place == nil)
        #expect(ReplayTitleCard.make(place: "  ", startedAt: nil, timeZone: fixtureZone).dateLine == "")
        #expect(ReplayTitleCard.make(place: nil, startedAt: startedAt, timeZone: cest).place
                == nil)
    }

    /// The commentary's superlatives, still picked out of the script the clip said out loud.
    ///
    /// The **closing card no longer prints them** — two of the three restated cells of its own
    /// metrics grid, so the lines went and the one number the grid was missing became its
    /// ninth cell instead (`ShareCardStatsTests.theOutroGridIsTheBlockPlusTheLongestFlight`).
    /// The picker itself stays: it is a fact about the commentary, and what it names is what
    /// the grid now has to carry.
    @Test func theCommentarysSuperlativesAreStillTheOnesTheGridHasToCover() throws {
        let milestones = try script()
        let highlights = ReplayCommentary.highlights(milestones)

        #expect(highlights.map(\.text) == [
            "Top speed — 13.47 kn over 2 s",
            // Eight, not the three/four/five/six/seven it passed on the way there.
            "New streak — 8 dry jibes",
            // Collapsed with the first takeoff at the same instant, exactly as the caption
            // read when the clip played it.
            "Flying! · Longest flight — 6:32",
        ])
        #expect(highlights.allSatisfy { milestones.contains($0) })
        // The first two are the max-2 s and streaks cells said in a sentence; the third is
        // the one the grid did not have, and now does.
        #expect(ReplayCommentary.highlights([]).isEmpty)
    }

    /// The limit is a limit, not a shape — a caller with room for two lines gets the two most
    /// worth having, in the same order.
    @Test func theHighlightLimitTakesFromTheTop() throws {
        let milestones = try script()
        #expect(ReplayCommentary.highlights(milestones, limit: 2).map(\.text)
                == ["Top speed — 13.47 kn over 2 s", "New streak — 8 dry jibes"])
        #expect(ReplayCommentary.highlights(milestones, limit: 0).isEmpty)
    }
}
