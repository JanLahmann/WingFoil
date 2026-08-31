import Foundation
import Testing
@testable import WingFoilKit

/// Picking a rate from a length. The picker was inverted because a rate is not what anybody
/// chooses — so the one thing this suite has to prove is that the number on the button is the
/// number that comes out, on a real afternoon with real milestones in it.
///
/// The Torbole run times `ReplayDriverTests` pins are the input here, not a second derivation
/// of them: a change to the pacing fails there, a change to the length arithmetic fails here.
@Suite struct ReplayPacingTests {

    /// 2026-08-30 Torbole: 645 s of session, twelve commentary lines.
    private func torbole() throws -> SessionAnalysis {
        let url = testFixturesDir.appendingPathComponent(
            "goldens/2026-08-30-1407_nago-torbole-windsurfen_ciq.expected.json")
        return try JSONDecoder().decode(SessionAnalysis.self, from: Data(contentsOf: url))
    }

    private let span = 0.0...645.0

    private func script() throws -> [ReplayMilestone] {
        ReplayCommentary.make(try torbole(), span: span)
    }

    // MARK: - The button says what comes out

    /// The whole point, pinned on the fixture: ask for ten seconds of replay and get ten
    /// seconds of replay — not `645 / rate`, which ignores the ease, and not "about ten".
    @Test func everyTargetLandsOnItsOwnLength() throws {
        let milestones = try script()
        for target in [10.0, 25.0, 60.0] {
            let board = ReplayStoryboard.make(span: span, targetWallS: target,
                                              milestones: milestones)
            #expect(abs(board.replayWallS - target) < 0.01,
                    "\(Int(target)) s should run \(target) s, got \(board.replayWallS)")
            // …and the clip is that plus the two cards, said out loud by the sheet.
            #expect(abs(board.runWallS - (target + 6.5)) < 0.01)
        }
    }

    /// The rates the three targets resolve to on this afternoon. Pinned because they are what
    /// the sheet prints under the picker ("about 106×") and what the cinema view's own speed
    /// chip shows in the finished video — two numbers a viewer can check against each other.
    @Test func theTorboleRatesAreKnown() throws {
        let milestones = try script()
        let expected: [Double: Double] = [10: 99.233, 25: 39.663, 60: 13.781]
        for (target, rate) in expected {
            let plan = ReplayPacing.plan(span: span, targetWallS: target,
                                         easeAt: milestones.map(\.t))
            #expect(abs(plan.rate - rate) < 0.01,
                    "\(Int(target)) s should need about \(rate)×, got \(plan.rate)")
            #expect(plan.rate <= ReplayPacing.maxRate)
        }
    }

    /// "Full detail" is not a target at all — it is the old 10×, kept because a rider who
    /// wants to *watch* the session rather than post it is choosing a pace, not a length.
    /// Its numbers are exactly the ones `ReplayDriverTests` and `ReplayStoryboardTests`
    /// already pin, which is the point of leaving it as a rate.
    @Test func fullDetailIsStillThePinnedTenTimes() throws {
        let board = ReplayStoryboard.make(span: span, rate: 10, milestones: try script())
        #expect(abs(board.replayWallS - 77.70) < 0.05)
        #expect(abs(board.runWallS - 84.20) < 0.05)
    }

    // MARK: - The ease budget

    /// A ten-second clip cannot afford twelve one-second ritardandos: on this fixture the
    /// standard 0.6 s half-width costs about thirteen seconds of slow motion, which is more
    /// than the whole clip. So the dips shrink — still there, still on the same milestones,
    /// just briefer — rather than the clip growing past the length that was asked for.
    @Test func theDipsShrinkOnAShortTargetAndAreUntouchedOnALongOne() throws {
        let milestones = try script()
        let easeAt = milestones.map(\.t)

        let long = ReplayPacing.plan(span: span, targetWallS: 60, easeAt: easeAt)
        #expect(long.ease.halfWidthWallS == ReplayDriver.Ease.cinema.halfWidthWallS)

        let medium = ReplayPacing.plan(span: span, targetWallS: 25, easeAt: easeAt)
        let short = ReplayPacing.plan(span: span, targetWallS: 10, easeAt: easeAt)
        #expect(abs(medium.ease.halfWidthWallS - 0.4026) < 0.001)
        #expect(abs(short.ease.halfWidthWallS - 0.1613) < 0.001)
        // Monotone: a shorter clip never gets *longer* dips.
        #expect(short.ease.halfWidthWallS < medium.ease.halfWidthWallS)
        #expect(medium.ease.halfWidthWallS < long.ease.halfWidthWallS)

        // The floor is untouched at every length — the slow moments are still a quarter
        // speed, which is what makes a jibe recognisable. Only their width is budgeted.
        #expect(short.ease.floor == ReplayDriver.Ease.cinema.floor)
        // And they are still *on* the milestones: this is the assertion that would fail if
        // budgeting had quietly turned the slow motion off.
        let driver = ReplayDriver(span: span, rate: short.rate, easeAt: easeAt,
                                  ease: short.ease)
        for milestone in milestones {
            #expect(driver.pace(at: milestone.t) == 0.25,
                    "\(milestone.text) should still be watched in slow motion")
        }
    }

    /// The dips never take more than their share of the clip, whatever the target.
    @Test func theEaseStaysInsideItsBudget() throws {
        let easeAt = try script().map(\.t)
        for target in [8.0, 10.0, 15.0, 25.0, 40.0, 60.0, 120.0] {
            let plan = ReplayPacing.plan(span: span, targetWallS: target, easeAt: easeAt)
            let driver = ReplayDriver(span: span, rate: plan.rate, easeAt: easeAt,
                                      ease: plan.ease)
            let overhead = driver.runWallS - 645 / plan.rate
            #expect(overhead <= ReplayPacing.easeShare * target + 0.01,
                    "\(Int(target)) s spent \(overhead) s on slow motion")
        }
    }

    /// A rider with the commentary switched off has no milestones, so there is no ease and
    /// the arithmetic is the plain division the picker's label implies.
    @Test func aSilentReplayIsExactlyTheSessionOverTheRate() {
        for target in [10.0, 25.0, 60.0] {
            let plan = ReplayPacing.plan(span: span, targetWallS: target)
            #expect(abs(plan.rate - 645 / target) < 0.001)
            #expect(abs(ReplayStoryboard.make(span: span, targetWallS: target).replayWallS
                        - target) < 0.01)
        }
    }

    // MARK: - The two saturations

    /// A four-hour afternoon asked to be ten seconds long would need 1440×, at which point one
    /// tick of the cinema view's 20 Hz clock is more than a minute of session and the dot is a
    /// series of positions rather than a movement. The cap binds, the clip comes out longer
    /// than asked — and the sheet quotes the longer number, because a clip in which nothing
    /// recognisable happens is not the shorter clip the rider wanted.
    @Test func aVeryLongSessionSaturatesAtTheRateCap() throws {
        let long = 0.0...14400.0
        let plan = ReplayPacing.plan(span: long, targetWallS: 10, easeAt: try script().map(\.t))
        #expect(plan.rate == ReplayPacing.maxRate)
        let board = ReplayStoryboard.make(span: long, targetWallS: 10,
                                          milestones: try script())
        #expect(board.replayWallS > 10)
        #expect(abs(board.replayWallS - 61.15) < 0.05)
        // Whatever it comes out at, the quoted clip length is still the honest sum.
        #expect(abs(board.runWallS - (board.replayWallS + 6.5)) < 0.01)
    }

    /// You cannot stretch half a minute into a minute by playing it back faster. The slowest
    /// a replay ever runs is real time, and a target longer than the session simply gets the
    /// session.
    @Test func aSessionShorterThanTheTargetPlaysInRealTime() {
        let plan = ReplayPacing.plan(span: 0.0...30.0, targetWallS: 60)
        #expect(plan.rate == ReplayPacing.minRate)
        #expect(ReplayStoryboard.make(span: 0.0...30.0, targetWallS: 60).replayWallS == 30)
    }

    /// A recording with no duration, and a nonsense target, both come back with something a
    /// driver can be built from rather than a division by zero.
    @Test func degenerateInputsDoNotDivideByZero() {
        #expect(ReplayPacing.plan(span: 42.0...42.0, targetWallS: 10).rate
                == ReplayPacing.minRate)
        #expect(ReplayPacing.plan(span: span, targetWallS: 0).rate == ReplayPacing.minRate)
        #expect(ReplayPacing.plan(span: span, targetWallS: -5).rate == ReplayPacing.minRate)
        #expect(ReplayStoryboard.make(span: 42.0...42.0, targetWallS: 10).runWallS == 0)
    }

    // MARK: - The estimate is the run

    /// The length under the picker and the clip that comes out are the same thing: ticking
    /// the solved driver out at the view's own 20 Hz lands within a tick of the target.
    @Test func tickingASolvedTargetLandsOnIt() throws {
        let easeAt = try script().map(\.t)
        for target in [10.0, 25.0, 60.0] {
            let plan = ReplayPacing.plan(span: span, targetWallS: target, easeAt: easeAt)
            let driver = ReplayDriver(span: span, rate: plan.rate, easeAt: easeAt,
                                      ease: plan.ease)
            let dt = 1 / 20.0
            var t = driver.start
            var ticks = 0
            while !driver.hasFinished(t) && ticks < 200_000 {
                t = driver.advance(t, byWallSeconds: dt)
                ticks += 1
            }
            #expect(t == 645)
            #expect(abs(Double(ticks) * dt - target) < 0.2,
                    "\(Int(target)) s ran for \(Double(ticks) * dt) s")
        }
    }
}
