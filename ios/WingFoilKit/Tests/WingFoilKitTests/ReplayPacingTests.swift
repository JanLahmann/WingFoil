import Foundation
import Testing
@testable import WingFoilKit

/// Picking a rate from a length. The picker was inverted because a rate is not what anybody
/// chooses — so the one thing this suite has to prove is that the number on the button is the
/// number that comes out, on a real afternoon with real milestones in it, **and on a long one**.
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
        ReplayCommentary.make(try torbole(), span: span, timeZone: fixtureZone)
    }

    /// A synthetic two-hour afternoon with thirty things to say in it — the shape of the
    /// session that produced the bug report ("the video is 40 s when I selected 10 s").
    ///
    /// Synthetic rather than golden because the corpus has no two-hour session in it, and the
    /// property under test is about *arithmetic at scale* rather than about detection: thirty
    /// milestones over 7200 s is what saturated the old rate cap, and any thirty would have.
    /// The mix is a real one though — seven jibe ordinals, three splashes, a run of fifteen
    /// streak records and the two superlatives — because the pruning is a choice *between*
    /// kinds and a list of thirty identical milestones could not exercise it.
    private func longAfternoon() -> [ReplayMilestone] {
        var out: [ReplayMilestone] = [
            ReplayMilestone(id: "start", t: 0, kind: .sessionStart,
                            text: "Torbole, 10:00 — session start"),
            ReplayMilestone(id: "flying", t: 240, kind: .firstTakeoff, text: "Flying!"),
            ReplayMilestone(id: "longest-flight", t: 3000, kind: .longestFlight,
                            text: "Longest flight — 11:20"),
            ReplayMilestone(id: "top-speed", t: 4680, kind: .topSpeed,
                            text: "Top speed — 21.4 kn over 2 s"),
            ReplayMilestone(id: "end", t: 7200, kind: .sessionEnd,
                            text: "Session end — 2:00:00 · 41.8 km · 40 dry jibes"),
        ]
        for (index, n) in [1, 3, 5, 10, 20, 30, 40].enumerated() {
            out.append(ReplayMilestone(
                id: "jibe-\(n)", t: 300 + Double(index) * 940, kind: .jibe(n),
                text: n == 1 ? "First jibe — flew through" : "\(n) dry jibes"))
        }
        for (index, n) in [1, 5, 10].enumerated() {
            out.append(ReplayMilestone(
                id: "splash-\(n)", t: 420 + Double(index) * 2200, kind: .splash(n),
                text: n == 1 ? "First splash" : "\(n) splashes"))
        }
        for (index, n) in (3...17).enumerated() {
            out.append(ReplayMilestone(id: "streak-\(n)", t: 360 + Double(index) * 430,
                                       kind: .streak(n),
                                       text: "New streak — \(n) dry jibes"))
        }
        return out.sorted { $0.t < $1.t }
    }

    private let longSpan = 0.0...7200.0

    // MARK: - The button says what comes out

    /// The whole point, pinned on the fixture: ask for ten seconds of replay and get ten
    /// seconds of replay — not `645 / rate`, which ignores the ease, and not "about ten".
    @Test func everyTargetLandsOnItsOwnLength() throws {
        let milestones = try script()
        for target in [10.0, 25.0, 60.0] {
            let board = ReplayStoryboard.make(span: span, targetWallS: target,
                                              milestones: milestones, timeZone: fixtureZone)
            #expect(abs(board.replayWallS - target) < 0.01,
                    "\(Int(target)) s should run \(target) s, got \(board.replayWallS)")
            // …and the clip is that plus the two cards, said out loud by the sheet.
            #expect(abs(board.runWallS - (target + 6.5)) < 0.01)
        }
    }

    /// **The bug report, as a test.** Jan's two-hour afternoon asked for ten seconds came back
    /// as a forty-second video: thirty milestones' worth of slow motion, a rate pinned at the
    /// old 250× ceiling, and a sheet that relabelled the estimate rather than honouring the
    /// choice. Ten seconds now means ten seconds — the clip is 16.5 s of video because the two
    /// cards are 6.5 s of it and the sheet says so.
    @Test func aTwoHourAfternoonStillGetsTheTenSecondsItAskedFor() {
        let milestones = longAfternoon()
        #expect(milestones.count == 30)

        let plan = ReplayPacing.plan(span: longSpan, targetWallS: 10, milestones: milestones)
        // 1107×, which the old cap would have refused. Nothing about the map's drawing depends
        // on the rate — the track is static and the dot is a lookup — so the number the span
        // needs is the number it gets.
        #expect(abs(plan.rate - 1107.692) < 0.01)
        #expect(plan.milestones.count == 4)

        let board = ReplayStoryboard.make(span: longSpan, targetWallS: 10,
                                          milestones: milestones, timeZone: fixtureZone)
        #expect(abs(board.replayWallS - 10) < 0.1)
        #expect(abs(board.runWallS - 16.5) < 0.1)
        #expect(board.photoWallS == 0)
        // The dips are on the four that survived, not on the thirty that were said.
        #expect(board.driver.easeAt.count == 4)
    }

    /// The same afternoon at the other two lengths: the length is kept in all three cases, and
    /// what changes is how much gets said.
    @Test func theLongAfternoonKeepsEveryLengthOnItsPicker() {
        let milestones = longAfternoon()
        for (target, lines) in [(10.0, 4), (25.0, 8), (60.0, 12)] {
            let board = ReplayStoryboard.make(span: longSpan, targetWallS: target,
                                              milestones: milestones, timeZone: fixtureZone)
            #expect(abs(board.replayWallS - target) < 0.05,
                    "\(Int(target)) s ran \(board.replayWallS) s")
            #expect(board.driver.easeAt.count == lines)
        }
    }

    /// The rates the three targets resolve to on this afternoon. Pinned because they are what
    /// the sheet prints under the picker ("about 99×") and what the cinema view's own speed
    /// chip shows in the finished video — two numbers a viewer can check against each other.
    @Test func theTorboleRatesAreKnown() throws {
        let milestones = try script()
        let expected: [Double: Double] = [10: 99.020, 25: 38.834, 60: 13.781]
        for (target, rate) in expected {
            let plan = ReplayPacing.plan(span: span, targetWallS: target,
                                         milestones: milestones)
            #expect(abs(plan.rate - rate) < 0.01,
                    "\(Int(target)) s should need about \(rate)×, got \(plan.rate)")
        }
    }

    /// "Full detail" is not a target at all — it is the old 10×, kept because a rider who
    /// wants to *watch* the session rather than post it is choosing a pace, not a length.
    /// Its numbers are exactly the ones `ReplayDriverTests` and `ReplayStoryboardTests`
    /// already pin, which is the point of leaving it as a rate.
    @Test func fullDetailIsStillThePinnedTenTimes() throws {
        let board = ReplayStoryboard.make(span: span, rate: 10, milestones: try script(), timeZone: fixtureZone)
        #expect(abs(board.replayWallS - 78.90) < 0.05)
        #expect(abs(board.runWallS - 85.40) < 0.05)
    }

    // MARK: - What each length has room to say

    /// **Which four survive on the Torbole afternoon**, verbatim — the assertion that says the
    /// pruning kept the session's headlines rather than its first four seconds. The two
    /// bookends frame the clip; between them, the longest flight and the fastest two seconds.
    /// At twenty-five seconds the firsts and the best streak come back; at sixty all but one
    /// line survives, because twelve lines is what a minute has room for and the clean-jibe
    /// beat made this afternoon thirteen.
    @Test func eachLengthKeepsTheMomentsItHasRoomFor() throws {
        let milestones = try script()

        #expect(ReplayPacing.plan(span: span, targetWallS: 10, milestones: milestones)
            .milestones.map(\.text) == [
                // No place and no clock were handed in, so the opening line degrades — see
                // `ReplayCommentaryTests`. On the phone it reads "Torbole, 14:07 — session
                // start"; what matters here is that it is the *opening* line.
                "Session start",
                "Flying! · Longest flight — 6:32",
                "Top speed — 13.47 kn over 2 s",
                "Session end — 10:45 · 2.6 km · 8 dry jibes",
            ])

        #expect(ReplayPacing.plan(span: span, targetWallS: 25, milestones: milestones)
            .milestones.map(\.id) == [
                // The two bookends, the two superlatives, the best streak of the day and the
                // three firsts — which since engine 0.10.0 includes the first **clean** jibe,
                // and it takes the slot the earliest leftover streak record used to have.
                "start", "longest-flight", "jibe-1", "clean-1", "top-speed", "streak-8",
                "splash-1", "end",
            ])

        // A minute has room for twelve lines and this afternoon now has thirteen to say, so
        // the one thing a sixty-second clip leaves out is the seventh streak record — the
        // lowest-ranked line of the run-up to the eight it does keep.
        #expect(ReplayPacing.plan(span: span, targetWallS: 60, milestones: milestones)
            .milestones.map(\.id) == milestones.map(\.id).filter { $0 != "streak-7" })
    }

    /// A rider who picked "Full detail" is watching rather than posting, and hears everything.
    @Test func fullDetailBudgetsNothingAway() throws {
        #expect(ReplayCommentary.budget(forTargetWallS: nil) == nil)
        let milestones = try script()
        #expect(ReplayCommentary.pruned(milestones, forTargetWallS: nil) == milestones)
    }

    // MARK: - The ease budget

    /// With the script cut first, the dips barely need trimming: four milestones in ten seconds
    /// are already close to their allowance, so the survivors keep a width that can actually be
    /// watched. (Before the budget existed, a ten-second clip cut the 0.6 s half-width to 0.16 —
    /// slow motion too brief to see, on twelve captions too quick to read.)
    @Test func theDipsKeepAReadableWidthOnceTheScriptIsCut() throws {
        let milestones = try script()

        let long = ReplayPacing.plan(span: span, targetWallS: 60, milestones: milestones)
        let medium = ReplayPacing.plan(span: span, targetWallS: 25, milestones: milestones)
        let short = ReplayPacing.plan(span: span, targetWallS: 10, milestones: milestones)

        // Untouched at both of the longer lengths — twelve dips fit inside sixty seconds and
        // eight fit inside twenty-five.
        #expect(long.ease.halfWidthWallS == ReplayDriver.Ease.cinema.halfWidthWallS)
        #expect(medium.ease.halfWidthWallS == ReplayDriver.Ease.cinema.halfWidthWallS)
        // Trimmed by a fiftieth of a second at ten, which is the budget doing its job quietly.
        #expect(abs(short.ease.halfWidthWallS - 0.5833) < 0.001)
        #expect(short.ease.halfWidthWallS <= medium.ease.halfWidthWallS)

        // The floor is untouched at every length — the slow moments are still a quarter
        // speed, which is what makes a jibe recognisable. Only their width is budgeted.
        #expect(short.ease.floor == ReplayDriver.Ease.cinema.floor)
        // And they are still *on* the milestones the clip kept: this is the assertion that
        // would fail if budgeting had quietly turned the slow motion off.
        let driver = ReplayDriver(span: span, rate: short.rate,
                                  easeAt: short.milestones.map(\.t), ease: short.ease)
        for milestone in short.milestones {
            #expect(driver.pace(at: milestone.t) == 0.25,
                    "\(milestone.text) should still be watched in slow motion")
        }
    }

    /// The dips never take more than their share of the clip, whatever the target — on the
    /// short afternoon and on the two-hour one.
    @Test func theEaseStaysInsideItsBudget() throws {
        for (span, spanS, milestones) in [(self.span, 645.0, try script()),
                                          (longSpan, 7200.0, longAfternoon())] {
            for target in [8.0, 10.0, 15.0, 25.0, 40.0, 60.0, 120.0] {
                let plan = ReplayPacing.plan(span: span, targetWallS: target,
                                             milestones: milestones)
                let driver = ReplayDriver(span: span, rate: plan.rate,
                                          easeAt: plan.milestones.map(\.t), ease: plan.ease)
                let overhead = driver.runWallS - spanS / plan.rate
                #expect(overhead <= ReplayPacing.easeShare * target + 0.01,
                        "\(Int(target)) s spent \(overhead) s on slow motion")
            }
        }
    }

    /// A rider with the commentary switched off has no milestones, so there is nothing to
    /// prune, no ease, and the arithmetic is the plain division the picker's label implies.
    @Test func aSilentReplayIsExactlyTheSessionOverTheRate() {
        for target in [10.0, 25.0, 60.0] {
            let plan = ReplayPacing.plan(span: span, targetWallS: target)
            #expect(plan.milestones.isEmpty)
            #expect(plan.ease == .cinema, "nothing to budget means nothing to shorten")
            #expect(abs(plan.rate - 645 / target) < 0.001)
            #expect(abs(ReplayStoryboard.make(span: span, targetWallS: target, timeZone: fixtureZone).replayWallS
                        - target) < 0.01)
        }
        // Same on the long one, where the old cap used to bind hardest.
        let plan = ReplayPacing.plan(span: longSpan, targetWallS: 10)
        #expect(abs(plan.rate - 720) < 0.001)
    }

    // MARK: - The one remaining saturation

    /// You cannot stretch half a minute into a minute by playing it back faster. The slowest
    /// a replay ever runs is real time, and a target longer than the session simply gets the
    /// session. This is the only saturation left: there is no ceiling at the other end.
    @Test func aSessionShorterThanTheTargetPlaysInRealTime() {
        let plan = ReplayPacing.plan(span: 0.0...30.0, targetWallS: 60)
        #expect(plan.rate == ReplayPacing.minRate)
        #expect(ReplayStoryboard.make(span: 0.0...30.0, targetWallS: 60, timeZone: fixtureZone).replayWallS == 30)
    }

    /// However long the afternoon, the ten-second button keeps its word. Four hours, eight,
    /// a day left recording in a car — the rate simply goes up, because nothing downstream of
    /// it is a function of the rate.
    @Test func thereIsNoLengthOfAfternoonThatBreaksThePromise() throws {
        let milestones = try script()
        for hours in [1.0, 4.0, 8.0, 24.0] {
            let span = 0.0...(hours * 3600)
            let board = ReplayStoryboard.make(span: span, targetWallS: 10,
                                              milestones: milestones, timeZone: fixtureZone)
            #expect(abs(board.replayWallS - 10) < 0.05,
                    "\(hours) h ran \(board.replayWallS) s")
            #expect(abs(board.runWallS - 16.5) < 0.05)
        }
    }

    /// A recording with no duration, and a nonsense target, both come back with something a
    /// driver can be built from rather than a division by zero.
    @Test func degenerateInputsDoNotDivideByZero() {
        #expect(ReplayPacing.plan(span: 42.0...42.0, targetWallS: 10).rate
                == ReplayPacing.minRate)
        #expect(ReplayPacing.plan(span: span, targetWallS: 0).rate == ReplayPacing.minRate)
        #expect(ReplayPacing.plan(span: span, targetWallS: -5).rate == ReplayPacing.minRate)
        #expect(ReplayStoryboard.make(span: 42.0...42.0, targetWallS: 10, timeZone: fixtureZone).runWallS == 0)
    }

    // MARK: - The estimate is the run

    /// The length under the picker and the clip that comes out are the same thing: ticking
    /// the solved driver out at the view's own 20 Hz lands within a tick of the target — at
    /// 99× on the short afternoon and at 1107× on the long one, which is the rate the old cap
    /// refused to reach.
    @Test func tickingASolvedTargetLandsOnIt() throws {
        for (span, end, milestones) in [(self.span, 645.0, try script()),
                                        (longSpan, 7200.0, longAfternoon())] {
            for target in [10.0, 25.0, 60.0] {
                let plan = ReplayPacing.plan(span: span, targetWallS: target,
                                             milestones: milestones)
                let driver = ReplayDriver(span: span, rate: plan.rate,
                                          easeAt: plan.milestones.map(\.t), ease: plan.ease)
                let dt = 1 / 20.0
                var t = driver.start
                var ticks = 0
                while !driver.hasFinished(t) && ticks < 200_000 {
                    t = driver.advance(t, byWallSeconds: dt)
                    ticks += 1
                }
                #expect(t == end)
                #expect(abs(Double(ticks) * dt - target) < 0.2,
                        "\(Int(target)) s ran for \(Double(ticks) * dt) s")
            }
        }
    }
}
