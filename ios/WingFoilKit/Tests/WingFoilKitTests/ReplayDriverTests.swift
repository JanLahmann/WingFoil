import Foundation
import Testing
@testable import WingFoilKit

/// The pacing of a replay that plays itself — position over time, where it stops, and the
/// slow-motion dips it takes around the commentary's milestones.
///
/// Two kinds of assertion here, deliberately kept apart:
///
/// * the **curve** is checked on hand-made spans, because "a raised cosine bottoming out at a
///   quarter" is a statement about arithmetic and a real session cannot make it any truer;
/// * the **clip length** is pinned against the 30 Aug Torbole golden, because that is the
///   number a rider is actually choosing between when they pick a speed, and it depends on
///   how a real afternoon's milestones fall against each other.
@Suite struct ReplayDriverTests {

    /// 2026-08-30 Torbole: 645 s of session, and a commentary script of twelve lines at
    /// 0, 85, 151, 255, 278, 292, 320, 362, 399, 441, 477 and 645 s (`ReplayCommentaryTests`).
    private func torbole() throws -> SessionAnalysis {
        let url = testFixturesDir.appendingPathComponent(
            "goldens/2026-08-30-1407_nago-torbole-windsurfen_ciq.expected.json")
        return try JSONDecoder().decode(SessionAnalysis.self, from: Data(contentsOf: url))
    }

    private let torboleSpan = 0.0...645.0

    // MARK: - Constant rate

    /// With no milestones the driver is exactly the scrubber's own arithmetic: 645 s at 30×
    /// is 21.5 s of watching, and the ticking agrees with the estimate to within a tick.
    @Test func aConstantRateRunIsTheSessionDividedByTheRate() {
        let driver = ReplayDriver(span: torboleSpan, rate: 30)

        #expect(driver.runWallS == 21.5)
        #expect(driver.pace(at: 0) == 1)
        #expect(driver.pace(at: 292) == 1)
        #expect(driver.rate(at: 292) == 30)

        let (wallS, end) = run(driver)
        #expect(abs(wallS - 21.5) <= 0.05)
        #expect(end == 645)
    }

    /// An explicit `.none` ease is the same thing said the other way round: a caller that has
    /// milestones but does not want the slow-down gets constant rate.
    @Test func theEaseCanBeSwitchedOffWithTheMilestonesLeftIn() {
        let driver = ReplayDriver(span: torboleSpan, rate: 30,
                                  easeAt: [85, 292, 441], ease: .none)
        #expect(driver.runWallS == 21.5)
        #expect(driver.pace(at: 292) == 1)
    }

    /// The playhead may not leave the span at either end, whatever it is handed — the clamp
    /// is what makes "the run is over" a position rather than a separate flag the view has to
    /// keep in step.
    @Test func theRunNeverLeavesItsSpan() {
        let driver = ReplayDriver(span: 100.0...200.0, rate: 60)

        #expect(driver.start == 100)
        // A position from before the session is pulled to the start and then stepped, rather
        // than pinned there: a caller who seeded the playhead badly still gets a replay that
        // moves, instead of one that looks broken.
        #expect(driver.advance(-500, byWallSeconds: 0.05) == 103)
        #expect(driver.advance(199.9, byWallSeconds: 10) == 200)
        #expect(driver.advance(200, byWallSeconds: 0.05) == 200)
        // A tick of no duration is a paused replay, not a rewind.
        #expect(driver.advance(150, byWallSeconds: 0) == 150)

        #expect(!driver.hasFinished(199))
        #expect(driver.hasFinished(200))
        #expect(driver.progress(at: 100) == 0)
        #expect(driver.progress(at: 150) == 0.5)
        #expect(driver.progress(at: 200) == 1)
    }

    /// A recording with no duration is over before it starts — the cinema view must offer
    /// the clip rather than tick forever against a span it can never cross.
    @Test func aSessionWithNoDurationIsAlreadyOver() {
        let driver = ReplayDriver(span: 42.0...42.0, rate: 30, easeAt: [42])
        #expect(driver.sessionSpanS == 0)
        #expect(driver.runWallS == 0)
        #expect(driver.hasFinished(driver.start))
        #expect(driver.progress(at: 42) == 1)
    }

    // MARK: - The slow-down curve

    /// One dip, checked shape-first: a quarter speed exactly on the milestone, full speed at
    /// the edge of the window and outside it, symmetric, and monotone on the way out. The
    /// half-width is `halfWidthWallS × rate` — 18 s of session at 30×.
    @Test func theEaseDipsToAQuarterOnTheMilestoneAndRecoversSmoothly() {
        let driver = ReplayDriver(span: 0.0...600.0, rate: 30, easeAt: [300])
        let halfWidth = 0.6 * 30.0

        #expect(driver.pace(at: 300) == 0.25)
        #expect(driver.rate(at: 300) == 7.5)
        // Full speed at the window's edge, which is what "no corner in it" means: the curve
        // arrives at 1 with a zero slope rather than stepping up to it.
        #expect(abs(driver.pace(at: 300 + halfWidth) - 1) < 1e-9)
        #expect(driver.pace(at: 300 - halfWidth) == driver.pace(at: 300 + halfWidth))
        #expect(driver.pace(at: 0) == 1)
        #expect(driver.pace(at: 600) == 1)

        // Symmetric, and never outside [floor, 1] anywhere in the window.
        for offset in stride(from: 0.0, through: halfWidth, by: 0.5) {
            let before = driver.pace(at: 300 - offset)
            let after = driver.pace(at: 300 + offset)
            #expect(abs(before - after) < 1e-12)
            #expect(before >= 0.25 && before <= 1)
        }
        // Monotone away from the milestone.
        var previous = driver.pace(at: 300)
        for offset in stride(from: 0.5, through: halfWidth, by: 0.5) {
            let here = driver.pace(at: 300 + offset)
            #expect(here >= previous)
            previous = here
        }
    }

    /// The window is measured in wall seconds, so it is the *same* 0.6 s of watching at every
    /// speed — which means it covers three times as much session at 60× as at 20×.
    @Test func theWindowIsWallTimeAndNotSessionTime() {
        for rate in [10.0, 30.0, 60.0] {
            let driver = ReplayDriver(span: 0.0...5000.0, rate: rate, easeAt: [2500])
            #expect(driver.pace(at: 2500) == 0.25)
            #expect(abs(driver.pace(at: 2500 + 0.6 * rate) - 1) < 1e-9)
            // Just inside the window at this rate, and comfortably outside it at a third of
            // the speed — the point of the unit.
            #expect(driver.pace(at: 2500 + 0.6 * rate * 0.5) < 0.7)
        }
    }

    /// Two milestones inside one window are one slow passage, not a crawl: the dips take the
    /// deepest of themselves rather than multiplying, or a busy minute of a session would
    /// grind to a sixty-fourth of the rate and the clip would never end.
    @Test func overlappingMilestonesEaseOnceRatherThanCompounding() {
        let driver = ReplayDriver(span: 0.0...600.0, rate: 30,
                                  easeAt: [300, 302, 304, 306, 308])
        for t in stride(from: 280.0, through: 330.0, by: 0.25) {
            #expect(driver.pace(at: t) >= 0.25)
        }
        // Between two milestones two seconds apart the pace is still essentially the floor —
        // the cluster reads as one held moment.
        #expect(driver.pace(at: 301) < 0.26)
    }

    // MARK: - The Torbole clip

    /// What the rate picker offers, pinned. The ease roughly halves the speed a run averages,
    /// so the three choices are about 79 s, 36 s and 24 s of video for the same afternoon —
    /// and it is *those* numbers, not "10x / 30x / 60x", that a rider is choosing between.
    ///
    /// Thirteen lines since the clean-jibe beat joined the commentary (engine 0.10.0), and a
    /// line is a dip: each of the three ran about a second longer for it.
    @Test func theEasedTorboleRunHasAKnownLength() throws {
        let script = ReplayCommentary.make(try torbole(), span: torboleSpan, timeZone: fixtureZone)
        #expect(script.count == 13)

        let expected: [Double: Double] = [10: 78.90, 30: 35.64, 60: 23.58]
        for (rate, wallS) in expected {
            let driver = ReplayDriver(span: torboleSpan, rate: rate,
                                      easeAt: script.map(\.t))
            #expect(abs(driver.runWallS - wallS) < 0.05,
                    "\(Int(rate))× should run about \(wallS) s, got \(driver.runWallS)")
            // Longer than the constant-rate run, which is the whole point of the ease, but
            // not so much longer that the label lies about the speed.
            #expect(driver.runWallS > 645 / rate)
            #expect(driver.runWallS < 2.2 * 645 / rate)
        }
    }

    /// The estimate and the ticking are the same run: whatever the view's tick rate, playing
    /// the driver out at 20 Hz lands on the end within a tick of what `runWallS` promised.
    @Test func tickingTheEasedRunAgreesWithTheEstimate() throws {
        let script = ReplayCommentary.make(try torbole(), span: torboleSpan, timeZone: fixtureZone)
        let driver = ReplayDriver(span: torboleSpan, rate: 30, easeAt: script.map(\.t))

        let (wallS, end) = run(driver)
        #expect(end == 645)
        #expect(abs(wallS - driver.runWallS) < 0.1)
    }

    /// The dips land on the captions, because they are built from the same list: the run is
    /// at its slowest while a milestone's line is on screen and back up to speed between
    /// them. This is the assertion that would fail if the commentary's script and the cinema
    /// view's pacing ever came from two different places.
    @Test func theSlowMomentsAreExactlyTheCommentedOnes() throws {
        let script = ReplayCommentary.make(try torbole(), span: torboleSpan, timeZone: fixtureZone)
        let driver = ReplayDriver(span: torboleSpan, rate: 30, easeAt: script.map(\.t))

        for milestone in script {
            #expect(driver.pace(at: milestone.t) == 0.25,
                    "\(milestone.text) should be watched in slow motion")
        }
        // 200 s is the longest gap in this session's script (151 → 255) and nothing is said
        // there, so the replay runs at its full rate through it.
        #expect(driver.pace(at: 200) == 1)
        #expect(driver.rate(at: 200) == 30)
    }

    /// The same property with a **budget** in front of it, which is where it could most easily
    /// have been lost: a ten-second clip says four of this afternoon's twelve lines, and the
    /// four dips have to be on those four and nowhere else.
    ///
    /// A clip that slowed down for a caption it had dropped would be a held moment with
    /// nothing in it; one that captioned a moment it did not slow for would put the words up
    /// and take the jibe away in the same frame. Both are what `ReplayPacing.Plan` carrying the
    /// pruned list — rather than a caller carrying a second copy — is for.
    @Test func theBudgetedScriptIsStillTheOneTheRunSlowsFor() throws {
        let full = ReplayCommentary.make(try torbole(), span: torboleSpan,
                                         timeZone: fixtureZone)
        let plan = ReplayPacing.plan(span: torboleSpan, targetWallS: 10, milestones: full)
        #expect(plan.milestones.count == 4)

        let driver = ReplayDriver(span: torboleSpan, rate: plan.rate,
                                  easeAt: plan.milestones.map(\.t), ease: plan.ease)
        let kept = Set(plan.milestones.map(\.t))
        for milestone in plan.milestones {
            #expect(driver.pace(at: milestone.t) == 0.25,
                    "\(milestone.text) is captioned, so it must be slowed for")
        }
        // And the eight that were cut are neither said nor slowed for. 255 s is the nearest
        // dropped milestone to a kept one (292 s), and at 99× the dips are ±58 s of session,
        // so this is a real check rather than an arithmetic accident.
        for milestone in full where !kept.contains(milestone.t) {
            #expect(driver.pace(at: milestone.t) > 0.25,
                    "\(milestone.text) was cut, so nothing may dwell on it")
        }
        #expect(!kept.contains(255))
    }

    // MARK: - Helpers

    /// Plays a driver out at the view's own 20 Hz and reports (wall seconds, final position).
    /// A generous iteration cap so a pacing bug that stalls the playhead fails as a test
    /// rather than as a hung suite.
    private func run(_ driver: ReplayDriver, ticksPerSecond: Double = 20)
        -> (wallS: Double, end: Double) {
        let dt = 1 / ticksPerSecond
        var t = driver.start
        var ticks = 0
        while !driver.hasFinished(t) && ticks < 200_000 {
            t = driver.advance(t, byWallSeconds: dt)
            ticks += 1
        }
        return (Double(ticks) * dt, t)
    }
}
