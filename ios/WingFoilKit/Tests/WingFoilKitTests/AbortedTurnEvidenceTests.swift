import Foundation
import Testing
@testable import WingFoilKit

/// **Did he get there?** (engine 0.27.0, docs/algorithms/turns.md "Did he get there",
/// ADR-037). Jan's library of 28 September 2026 counted 18 tacks where he had tried 3. An
/// aborted turn named by the axis it was closing on now needs evidence (R2 the no-go zone on a
/// flown heading, R3 the luff at speed), the tail of a same-way turn is that turn (R1), a
/// sweep through both axes is named by the first (R4), and a crossing in a short gap between
/// two sweeps belongs to the second (R5). The lab's twin is `lab/tests/test_turns.py`, "did he
/// get there"; corpus-wide agreement is `GoldenTests`, turn by turn.
@Suite struct AbortedTurnEvidenceTests {

    private let wind = WindEstimate(userDirDeg: 0)

    /// The 0.27.0 gates off, so a test can ask what 0.21.0 through 0.26.0 said.
    private var gatesOff: TurnConfig {
        var config = TurnConfig()
        config.abortAxisDeg = 0
        config.abortLuffDeg = 0
        return config
    }

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

    private func turns(_ track: CleanTrack, config: TurnConfig = TurnConfig(),
                       habit: DefaultTurnType = .jibes) -> [Turn] {
        TurnDetector.detect(track, flights: FlightSegmenter.segment(track), wind: wind,
                            config: config, defaultTurnType: habit)
    }

    private func leg(_ c: Double, _ n: Int, _ v: Double = 6) -> ([Double], [Double]) {
        (Array(repeating: c, count: n), Array(repeating: v, count: n))
    }

    private func ramp(_ c0: Double, _ c1: Double, _ speeds: [Double]) -> ([Double], [Double]) {
        let n = speeds.count
        return ((0..<n).map { c0 + (c1 - c0) * Double($0) / Double(n - 1) }, speeds)
    }

    private func join(_ parts: ([Double], [Double])...) -> CleanTrack {
        track(course: parts.flatMap(\.0), speed: parts.flatMap(\.1))
    }

    private func swim(_ c: Double) -> ([Double], [Double]) { leg(c, 12, 0.2) }

    private func attempted(_ all: [Turn]) -> [TurnKind] {
        all.filter { $0.aborted }.map(\.kind)
    }

    /// Broad reach on TWA +135, rounding up to +60 as he goes in: 0.21.0 called it a tack.
    private var luffIntoACrash: CleanTrack {
        join(leg(135, 40), ramp(135, 60, [6.0, 5.5, 5.0, 4.5, 4.0]), leg(60, 1, 3), swim(60))
    }

    @Test func r2ALuffThatStops60DegOffTheWindIsNotATack() {
        let now = turns(luffIntoACrash)
        #expect(now.map(\.kind) == [.roundUp])
        #expect(now.allSatisfy { !$0.counted && !$0.aborted })
        #expect(attempted(turns(luffIntoACrash, config: gatesOff)) == [.tack])
    }

    /// The step that reaches 25° off the wind ends on a sample at 2.1 m/s: above the COG floor,
    /// below `foilExitSpeed`. At 3 m/s the same step is flown, and it is a tack.
    @Test func r2AHeadingReadBelowFoilSpeedIsNotOneHeFlew() {
        func luff(_ v: Double) -> CleanTrack {
            join(leg(100, 40), ramp(100, 25, [6.0, 5.8, 5.5, 5.0]), ramp(15, 10, [v, v]),
                 swim(10))
        }
        #expect(!attempted(turns(luff(2.1))).contains(.tack))
        #expect(attempted(turns(luff(2.1), config: gatesOff)) == [.tack])
        #expect(attempted(turns(luff(3.0))) == [.tack])
    }

    @Test func r3ACrashThatRoundsUpLosesTheSpeedFirst() {
        let crash = join(leg(100, 40), ramp(100, 20, [6.0, 3.4, 3.2, 3.0, 2.9]), leg(20, 1, 2.8),
                         swim(20))
        #expect(!turns(crash).map(\.kind).contains(.tack))
        var luffOff = TurnConfig()
        luffOff.abortLuffDeg = 0
        #expect(turns(crash, config: luffOff).map(\.kind).contains(.tack))
    }

    @Test func theGateFollowsTheRidersDeclaredHabit() {
        #expect(turns(luffIntoACrash, habit: .tacks).map(\.kind).contains(.tack))
        #expect(!turns(luffIntoACrash, habit: .balanced).map(\.kind).contains(.tack))
        // Beam reach bearing away, in 40° short of dead downwind.
        let jibe = join(leg(90, 40), ([90, 115, 140, 140], [6, 6, 5.5, 5]), swim(140))
        #expect(turns(jibe).map(\.kind) == [.jibe])
        #expect(turns(jibe, habit: .balanced).isEmpty)
    }

    @Test func r1AnAbortedTurnRightAfterASameWayJibeIsThatJibe() {
        let jibe = ramp(90, 270, [6.0, 5.8, 5.6, 5.5, 5.5, 5.6, 5.8])
        let luff = [leg(270, 5, 3.5), ramp(270, 340, [3.5, 3.5, 3.4, 3.3]), leg(340, 1, 3),
                    swim(340)]
        let both = track(course: leg(90, 40).0 + jibe.0 + luff.flatMap(\.0),
                         speed: leg(90, 40).1 + jibe.1 + luff.flatMap(\.1))
        let all = turns(both)
        #expect(all.filter(\.counted).map(\.kind) == [.jibe])
        #expect(all.first?.outcome == .fellIn)
        #expect(!all.contains { $0.aborted })
        let alone = track(course: leg(270, 40, 3.5).0 + luff.flatMap(\.0),
                          speed: leg(270, 40, 3.5).1 + luff.flatMap(\.1))
        #expect(attempted(turns(alone)) == [.tack])
    }

    @Test func r4ASweepThroughBothAxesIsNamedByTheFirst() {
        #expect(TurnDetector.classifySweep(cogIn: 150, cogOut: 440, dirDeg: 0).kind == .tack)
        #expect(TurnDetector.classifySweep(cogIn: 150, cogOut: 440, dirDeg: 0,
                                           firstCrossing: true).kind == .jibe)
        #expect(TurnDetector.classifySweep(cogIn: 440, cogOut: 150, dirDeg: 0,
                                           firstCrossing: true).kind == .tack)
    }

    @Test func r5ACrossingInTheGapBetweenTwoSweepsBelongsToTheSecond() throws {
        let t = join(leg(70, 40), ramp(70, 380, Array(repeating: 6.0, count: 8)), leg(380, 40))
        let config = TurnConfig()
        let whole = try #require(TurnDetector.acceptedCandidates(
            t, flights: FlightSegmenter.segment(t), config: config).first)
        let k = try #require(whole.u.firstIndex { $0 >= 180 })
        func part(_ i: Int, _ j: Int) -> TurnDetector.Candidate {
            TurnDetector.Candidate(t: whole.t, man: whole.man, dop: whole.dop, tu: whole.tu,
                                   u: whole.u, rate: whole.rate, i: i, j: j, arc: whole.arc,
                                   x: whole.x, y: whole.y, a: whole.a, run: whole.run)
        }
        let p = part(whole.i, k - 1), c = part(k, whole.j)
        let own = TurnDetector.classify(cogIn: c.cogIn, cogOut: c.cogOut, wind: wind,
                                        minAngleDeg: config.classifyMinAngleDeg)
        #expect(own.kind == .tack)
        let joined = TurnDetector.joinSplit([p, c], wind: wind, config: config)
        #expect(joined[1].i == p.j && joined[1].j == c.j)
        #expect(TurnDetector.classify(cogIn: joined[1].cogIn, cogOut: joined[1].cogOut,
                                      wind: wind,
                                      minAngleDeg: config.classifyMinAngleDeg).kind == .jibe)
        var off = config
        off.joinGapS = 0
        #expect(TurnDetector.joinSplit([p, c], wind: wind, config: off)[1].i == c.i)
    }
}
