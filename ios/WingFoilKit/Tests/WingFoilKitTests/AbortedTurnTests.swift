import Foundation
import Testing
@testable import WingFoilKit

/// **The aborted turn** (engine 0.21.0, docs/algorithms.md "The aborted turn", ADR-028).
///
/// Jan, 20 September 2026: *"an attempted turn that ends in the water is a turn that fell
/// in."* A tester tried two tacks on 19 September, went in both times, and the session showed
/// 0 tacks and 0 falls in a turn: the scan asks for `turnMinAngle` of heading change inside
/// `turnMaxDuration`, and a rider who goes in halfway round never gets there.
///
/// Each case is built on the same shape — a leg at foiling speed, a sweep that is still
/// turning when the speed dies, and a swim — because that shape is the whole rule. The lab's
/// twin is `lab/tests/test_turns.py`, "the aborted turn"; corpus-wide agreement between the
/// two is asserted by `GoldenTests` over every fixture, turn by turn.
@Suite struct AbortedTurnTests {

    private let wind = WindEstimate(userDirDeg: 0)

    /// The pass switched off, so a test can ask what the session looked like before 0.21.0.
    private var abortOff: TurnConfig {
        var config = TurnConfig()
        config.abortMinAngleDeg = 0
        return config
    }

    /// A `CleanTrack` sailed along the given per-second course at the given speeds (the Swift
    /// twin of the lab's `_track`).
    private func track(course: [Double], speed: [Double]) -> CleanTrack {
        var out = CleanTrack()
        var x = 0.0, y = 0.0, dist = 0.0
        for (i, deg) in course.enumerated() {
            let v = speed[i]
            out.samples.append(CleanSample(t: Double(i), dt: i == 0 ? 0 : 1, gapBefore: false,
                                           x: x, y: y, dopplerMps: v, positionalMps: v,
                                           cumDistM: dist, altM: nil))
            x += sin(deg * .pi / 180) * v
            y += cos(deg * .pi / 180) * v
            dist += v
        }
        out.segments = [0..<out.samples.count]
        out.medianDtS = 1
        out.gapThresholdS = 3
        out.spanS = out.samples.last.map { $0.t - (out.samples.first?.t ?? 0) } ?? 0
        out.timerTimeS = Double(course.count - 1)
        return out
    }

    private func turns(_ track: CleanTrack, config: TurnConfig = TurnConfig()) -> [Turn] {
        TurnDetector.detect(track, flights: FlightSegmenter.segment(track), wind: wind,
                            config: config)
    }

    /// `n` samples going nowhere: a swim, which the ladder reads as `fellIn`.
    private func swim(_ course: Double, _ n: Int = 12) -> ([Double], [Double]) {
        (Array(repeating: course, count: n), Array(repeating: 0.2, count: n))
    }

    /// Broad reach on TWA +135, luffing up hard toward head-to-wind, in at TWA +60.
    ///
    /// 75° of sweep: wide enough for `turnMinAngle`, so the main scan already sees it — and
    /// files it as an uncounted round-up, because it is nowhere near the 90° classification
    /// floor and it never crossed the wind. That is the tester's case of 19 September exactly.
    private func abortedTack() -> CleanTrack {
        var course = Array(repeating: 135.0, count: 40)
        var speed = Array(repeating: 6.0, count: 40)
        for k in 0..<5 {
            course.append(135 - 75 * Double(k) / 4)
            speed.append(6 - 0.5 * Double(k))
        }
        // One more sample still making way, so the last heading the *run* can read is the one
        // he was on when he went in: the COG element `k` is the step leaving sample `k`, and
        // the step off the last moving sample is not in the run.
        course.append(60); speed.append(3)
        let (c, s) = swim(60)
        return track(course: course + c, speed: speed + s)
    }

    /// Beam reach on TWA +90 bearing away toward dead downwind, in at TWA +140.
    ///
    /// 50° of sweep — below `turnMinAngle`, so the main scan does not see it at all.
    private func abortedJibe() -> CleanTrack {
        var course = Array(repeating: 90.0, count: 40)
        var speed = Array(repeating: 6.0, count: 40)
        course += [90, 115, 140, 140]
        speed += [6, 6, 5.5, 5]
        let (c, s) = swim(140)
        return track(course: course + c, speed: speed + s)
    }

    // MARK: - The rule

    @Test func anAbortedTackIsATackThatFellIn() throws {
        let all = turns(abortedTack())
        #expect(all.count == 1)
        let turn = try #require(all.first)
        #expect(turn.aborted)
        #expect(turn.counted)
        #expect(turn.kind == .tack)
        #expect(turn.outcome == .fellIn)
        #expect(!turn.success)
        #expect(!turn.clean)
        #expect(abs(abs(turn.netDeg) - 75) < 2)

        let summary = TurnDetector.summarize(all)
        #expect(summary.tacks == 1)
        #expect(summary.turnsCounted == 1)
        #expect(summary.rejected == 0)
        #expect(summary.outcomes.fellIn == 1)
        #expect(summary.outcomes.dry == 0)
    }

    @Test func theSameTackWasAnUncountedCourseChangeBefore0_21_0() throws {
        let all = turns(abortedTack(), config: abortOff)
        let turn = try #require(all.first)
        #expect(all.count == 1)
        #expect(turn.kind == .roundUp)
        #expect(!turn.counted)
        #expect(!turn.aborted)
        #expect(TurnDetector.summarize(all).rejected == 1)
    }

    /// Below `turnMinAngle`, so before 0.21.0 there was no sweep here at all.
    @Test func anAbortedJibeIsAJibeThatFellIn() throws {
        #expect(turns(abortedJibe(), config: abortOff).isEmpty)

        let all = turns(abortedJibe())
        #expect(all.count == 1)
        let turn = try #require(all.first)
        #expect(turn.aborted)
        #expect(turn.counted)
        #expect(turn.kind == .jibe)
        #expect(turn.outcome == .fellIn)
        #expect(!turn.success)
        #expect(!turn.clean)

        let summary = TurnDetector.summarize(all)
        #expect(summary.jibes == 1)
        #expect(summary.jibesSuccessful == 0)
        #expect(summary.jibeOutcomes.fellIn == 1)
    }

    /// The whole guard: no heading change, no turn — however hard the rider went in.
    @Test func aStraightLineFallStaysAStraightLineFall() {
        let (c, s) = swim(90, 20)
        let straight = track(course: Array(repeating: 90.0, count: 40) + c,
                             speed: Array(repeating: 6.0, count: 40) + s)
        #expect(turns(straight).isEmpty)
    }

    /// 20° of wobble before a swim is a swim (`turnAbortMinAngle`).
    @Test func aSweepBelowTheFloorIsNotATurn() {
        let (c, s) = swim(110)
        let wobble = track(course: Array(repeating: 90.0, count: 40) + [90, 100, 110, 110] + c,
                           speed: Array(repeating: 6.0, count: 40) + [6, 6, 5.5, 5] + s)
        #expect(turns(wobble).isEmpty)
    }

    /// The same 75° luff, ridden out of: the ladder says no fall, so there is no turn. What
    /// is left is what the scan always said — an uncounted round-up.
    @Test func anAbortedTurnNeedsTheFallNotMerelyTheSweep() throws {
        var course = Array(repeating: 135.0, count: 40)
        var speed = Array(repeating: 6.0, count: 40)
        for k in 0..<5 {
            course.append(135 - 75 * Double(k) / 4)
            speed.append(6 - 0.5 * Double(k))
        }
        course += Array(repeating: 60.0, count: 40)
        speed += Array(repeating: 6.0, count: 40)

        let all = turns(track(course: course, speed: speed))
        let turn = try #require(all.first)
        #expect(all.count == 1)
        #expect(turn.kind == .roundUp)
        #expect(!turn.counted)
        #expect(!turn.aborted)
    }
}
