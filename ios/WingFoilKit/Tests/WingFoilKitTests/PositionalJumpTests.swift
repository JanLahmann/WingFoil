import Foundation
import Testing
@testable import WingFoilKit

/// **A jump is not a turn** (engine 0.28.0, docs/algorithms/turns.md "A jump is not a turn",
/// ADR-038).
///
/// Jan, 1 Oct 2026: his 4 Sep 07:58 session came in through Strava and showed a tack that flew
/// through at 53:52, where the watch's own FIT has none. On a positions-only track one fix
/// thrown sideways is both a heading flip and a burst of speed. Both rules ask only of class
/// (c) — `CleanTrack.positionsOnly` — and each case below is checked on a class (b) reading of
/// the same arrays too, where nothing may move. The lab's twin is `lab/tests/test_turns.py`,
/// "a jump is not a turn".
@Suite struct PositionalJumpTests {

    private let wind = WindEstimate(userDirDeg: 0)

    /// A `CleanTrack` sailed along the given per-second course at the given speeds (the Swift
    /// twin of the lab's `_track`), read as positions-only when asked.
    private func track(course: [Double], speed: [Double], positionsOnly: Bool,
                       t times: [Double]? = nil) -> CleanTrack {
        var out = CleanTrack()
        var x = 0.0, y = 0.0, dist = 0.0
        let ts = times ?? course.indices.map(Double.init)
        var cuts: [Int] = [0]
        for (i, deg) in course.enumerated() {
            let v = speed[i]
            let dtBefore = i == 0 ? 0 : ts[i] - ts[i - 1]
            let gap = dtBefore > 3
            if gap { cuts.append(i) }
            out.samples.append(CleanSample(t: ts[i], dt: dtBefore, gapBefore: gap,
                                           x: x, y: y, dopplerMps: v, positionalMps: v,
                                           cumDistM: dist, altM: nil))
            // Like the lab's `_track`: each sample moves on for the interval that follows it.
            let dtAfter = i + 1 < ts.count ? ts[i + 1] - ts[i] : 1
            x += sin(deg * .pi / 180) * v * dtAfter
            y += cos(deg * .pi / 180) * v * dtAfter
            dist += v * dtAfter
        }
        cuts.append(out.samples.count)
        out.segments = zip(cuts, cuts.dropFirst()).map { $0.0..<$0.1 }
        out.medianDtS = 1
        out.gapThresholdS = 3
        out.spanS = out.samples.last.map { $0.t - (out.samples.first?.t ?? 0) } ?? 0
        out.timerTimeS = (ts.last ?? 0) - (ts.first ?? 0)
        out.positionsOnly = positionsOnly
        return out
    }

    private func counted(_ course: [Double], _ speed: [Double], positionsOnly: Bool,
                         config: TurnConfig = TurnConfig(), t: [Double]? = nil) -> [Turn] {
        let clean = track(course: course, speed: speed, positionsOnly: positionsOnly, t: t)
        return TurnDetector.detect(clean, flights: FlightSegmenter.segment(clean), wind: wind,
                                   config: config).filter(\.counted)
    }

    private func leg(_ course: Double, _ n: Int, _ speed: Double = 6.0) -> ([Double], [Double]) {
        (Array(repeating: course, count: n), Array(repeating: speed, count: n))
    }

    private func ramp(_ c0: Double, _ c1: Double, _ n: Int, _ v0: Double, _ v1: Double)
        -> ([Double], [Double]) {
        let f = (0..<n).map { Double($0) / Double(n - 1) }
        return (f.map { c0 + (c1 - c0) * $0 }, f.map { v0 + (v1 - v0) * $0 })
    }

    private func join(_ parts: ([Double], [Double])...) -> ([Double], [Double]) {
        (parts.flatMap(\.0), parts.flatMap(\.1))
    }

    /// A beam reach, then the heading flipped 150° in two fast samples (a fix jump).
    private var jump: ([Double], [Double]) {
        join(leg(90, 40), ([180, 240], [8, 8]), leg(240, 40))
    }

    @Test func aTwoSecondFlipOnAPositionsOnlyTrackIsNotATurn() {
        let (course, speed) = jump
        #expect(counted(course, speed, positionsOnly: false).map(\.kind) == [.jibe])
        #expect(counted(course, speed, positionsOnly: true).isEmpty)
        var off = TurnConfig()
        off.positionalMinSweepS = 0
        #expect(counted(course, speed, positionsOnly: true, config: off).map(\.kind) == [.jibe])
    }

    @Test func aRealJibeOnAPositionsOnlyTrackIsStillAJibe() {
        let (course, speed) = join(leg(90, 40), ramp(90, 270, 7, 6, 5), leg(270, 40))
        let turns = counted(course, speed, positionsOnly: true)
        #expect(turns.map(\.kind) == [.jibe])
        #expect(turns.first?.outcome == .flewThrough)
    }

    /// A 5 s jibe, a three-sample burst at 170 % of entry, then 20 s standing still.
    private var spikeThenStand: ([Double], [Double]) {
        join(leg(90, 40), ramp(90, 270, 6, 6, 5), leg(270, 3, 10), leg(270, 20, 0.3),
             leg(270, 40))
    }

    @Test func aRecoveryMadeOfAJumpAndThenAStandstillIsAFall() {
        let (course, speed) = spikeThenStand
        #expect(counted(course, speed, positionsOnly: false).first?.outcome == .flewThrough)
        let turn = counted(course, speed, positionsOnly: true).first
        #expect(turn?.kind == .jibe)
        #expect(turn?.outcome == .fellIn)
        var off = TurnConfig()
        off.positionalSpikePct = 0
        #expect(counted(course, speed, positionsOnly: true, config: off).first?.outcome
                == .flewThrough)
    }

    /// Powered out at entry speed and a stop a minute later: the spike rule never asks.
    @Test func aPositionsOnlyRecoveryAtCruisingSpeedStillClosesTheWindow() {
        let (course, speed) = join(leg(90, 40), ramp(90, 270, 7, 6, 5), leg(270, 60),
                                   leg(270, 20, 0.3), leg(270, 20))
        let turn = counted(course, speed, positionsOnly: true).first
        #expect(turn?.outcome == .flewThrough)
        #expect((turn?.outcomeWindowS ?? 99) < 5)
    }

    /// The cleaner reads the class off the recording: a GPX is positions-only, a FIT with
    /// speed is not.
    @Test func theCleanerMarksAPositionsOnlyTrack() {
        var raw = RawTrack()
        raw.capabilities.hasSpeed = false
        #expect(TrackCleaner.clean(raw).positionsOnly)
        raw.capabilities.hasSpeed = true
        #expect(!TrackCleaner.clean(raw).positionsOnly)
    }

    // MARK: - A turn has to be seen turning (ADR-038, amended 1 Oct 2026)

    /// A reach, then a 200° sweep whose middle step — a fix thrown 20 m — swings 170°.
    private var oneStepFlip: ([Double], [Double]) {
        join(leg(100, 40), ([110, 120, 290, 300], [6, 6, 20, 6]), leg(300, 40))
    }

    @Test func aSweepThatFlipsInOneStepOnAPositionsOnlyTrackIsNotATurn() {
        let (course, speed) = oneStepFlip
        #expect(counted(course, speed, positionsOnly: false).map(\.kind) == [.jibe])
        #expect(counted(course, speed, positionsOnly: true).isEmpty)
        var off = TurnConfig()
        off.positionalMaxStepDeg = 0
        #expect(counted(course, speed, positionsOnly: true, config: off).map(\.kind) == [.jibe])
    }

    /// The speed inside the sweep reaches 170 % of entry, then 20 s standing still.
    @Test func aSweepMadeOfABurstAndThenAStandstillIsNotATurn() {
        let (course, speed) = join(leg(90, 40),
                                   ((0..<6).map { 90 + 36 * Double($0) }, [6, 6, 10, 10, 6, 5]),
                                   leg(270, 20, 0.3), leg(270, 40))
        #expect(counted(course, speed, positionsOnly: false).map(\.kind) == [.jibe])
        #expect(counted(course, speed, positionsOnly: true).isEmpty)
        var off = TurnConfig()
        off.positionalSpikePct = 0
        #expect(counted(course, speed, positionsOnly: true, config: off).map(\.kind) == [.jibe])
    }

    /// A jibe that comes off the foil, two slow samples, an 18 s pause in the recording, then
    /// two samples at `tail` m/s and the end of the file (Jan's 10 Aug 2025 tack).
    private func endsInWater(tail: Double) -> ([Double], [Double], [Double]) {
        let (course, speed) = join(leg(90, 40),
                                   ((0..<7).map { 90 + 30 * Double($0) },
                                    [6, 5.5, 5, 4, 3, 2.5, 2]),
                                   leg(270, 2, 1.5), leg(270, 2, tail))
        var t = course.indices.map(Double.init)
        t[t.count - 2] += 18
        t[t.count - 1] += 18
        return (course, speed, t)
    }

    @Test func aRecordingThatEndsInTheWaterAfterATurnEndsInAFall() {
        let (course, speed, t) = endsInWater(tail: 0.6)
        var off = TurnConfig()
        off.recordingEndS = 0
        let before = counted(course, speed, positionsOnly: false, config: off, t: t)
        #expect(before.map(\.outcome) == [.touchdown])
        let turns = counted(course, speed, positionsOnly: false, t: t)
        #expect(turns.map(\.kind) == [.jibe])
        #expect(turns.map(\.outcome) == [.fellIn])
    }

    @Test func aRecordingThatEndsWhileHeIsStillMovingKeepsTheTouchdown() {
        let (course, speed, t) = endsInWater(tail: 1.5)
        #expect(counted(course, speed, positionsOnly: false, t: t).map(\.outcome) == [.touchdown])
    }
}
