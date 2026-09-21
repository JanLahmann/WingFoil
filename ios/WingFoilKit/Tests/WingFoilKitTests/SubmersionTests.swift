import Foundation
import Testing
@testable import WingFoilKit

/// The wrist-under mask and its episodes (docs/algorithms.md "Turn outcome" step 2 and
/// "Submersion episodes").
///
/// Two halves. The **mask** (engine 0.22.0, ADR-029) reads a local, causal baseline rather
/// than the session median, and the cases below are the four traces that rule was written
/// from: the fenix 8 dunk that crawls back, the fenix 5X Plus dunk that re-anchors, the slow
/// drift that is not a dunk at all, and the recording gap. The **episodes** turn that boolean
/// array into a list a map can draw, and those cases are about where a run starts and stops,
/// what a recording gap does to it, and what the episode is said to have happened during.
/// The lab's `tests/test_submersion.py` asserts the same cases on the same traces, and
/// cross-implementation agreement on the whole corpus is `GoldenTests.checkSubmersions`.
@Suite struct SubmersionTests {

    private let dropM = 25.0

    /// Episodes for a bare altitude series, on a regular clock with no gaps by default.
    private func runs(_ alt: [Double?], hz: Double = 1, gap: [Bool]? = nil,
                      mergeS: Double = Evidence.submersionMergeS) -> [Submersion] {
        let t = (0..<alt.count).map { Double($0) / hz }
        let gaps = gap ?? [Bool](repeating: false, count: alt.count)
        let trace = Evidence.submergedTrace(alt, t: t, gap: gaps, dropM: dropM)
        return Evidence.submersionRuns(t: t, gap: gaps, submerged: trace.mask, alt: alt,
                                       baseline: trace.baseline, mergeS: mergeS)
    }

    /// The wrist-under mask for a bare altitude series, on a regular clock.
    private func mask(_ alt: [Double?], hz: Double = 1, gap: [Bool]? = nil) -> [Bool] {
        let t = (0..<alt.count).map { Double($0) / hz }
        return Evidence.submergedMask(alt, t: t,
                                      gap: gap ?? [Bool](repeating: false, count: alt.count),
                                      dropM: dropM)
    }

    /// Episodes for a mask written by hand, against a baseline of zero.
    ///
    /// Three cases below are about `submersionRuns`' **own** gap rule rather than the mask's,
    /// and since engine 0.22.0 the mask can no longer produce the shape they test: a gap
    /// restarts the baseline, so the first sample after one is dry by construction. The two
    /// are separate decisions and the run rule still has to hold on its own, so it is
    /// asserted on a mask handed in directly.
    private func episodes(_ submerged: [Bool], _ alt: [Double?], hz: Double = 1,
                          gap: [Bool]? = nil,
                          mergeS: Double = Evidence.submersionMergeS) -> [Submersion] {
        let t = (0..<alt.count).map { Double($0) / hz }
        return Evidence.submersionRuns(
            t: t, gap: gap ?? [Bool](repeating: false, count: alt.count),
            submerged: submerged, alt: alt,
            baseline: [Double](repeating: 0, count: alt.count), mergeS: mergeS)
    }

    private func wet(_ count: Int) -> [Double?] { [Double?](repeating: -200, count: count) }
    private func dry(_ count: Int) -> [Double?] { [Double?](repeating: 0, count: count) }

    // MARK: - The mask

    /// Jan's watch: ~250 m of apparent drop, then a slew-limited crawl back over minutes.
    /// The crawl moves far more than `baroSettleM` in `baroSettleS`, so it is never a level —
    /// the wrist stays flagged for the whole time the altimeter is still recovering, which is
    /// what it was flagged for before the baseline became local.
    @Test func aFenix8DunkFlagsAllTheWayBackUp() {
        let crawl: [Double?] = (0...250).map { -250 + Double($0) }   // 250 m over 250 s
        let m = mask(dry(120) + crawl + dry(60))
        #expect(!m[0..<120].contains(true))
        #expect(m[120])
        #expect(!m[120..<320].contains(false))
        #expect(!m[(m.count - 60)...].contains(true))
    }

    /// A tester's fenix 5X Plus (20 Sep 2026) dunks and then sits at a *new* level. The spike
    /// is a fall and reads as one; the level that follows is not, and the settle release says
    /// so. Against a session median the whole of it read as one very long swim.
    @Test func aFenix5xPlusDunkThatReAnchorsFlagsTheSpikeAndThenStops() {
        let level: Double? = -100
        let m = mask(dry(120) + [-65, -134, -173] + [Double?](repeating: level, count: 600))
        #expect(!m[0..<120].contains(true))
        #expect(!m[120..<123].contains(false), "the dunk is still a dunk")
        let settled = 123 + Int(Evidence.baroSettleS)
        #expect(!m[123..<settled].contains(false), "the level is not accepted before it holds")
        #expect(!m[settled...].contains(true), "and the rest is riding, not swimming")
    }

    /// 100 m over ten minutes — weather, not water. The baseline walks with it.
    @Test func aSlowDriftIsNeverADunk() {
        #expect(!mask((0..<600).map { -Double($0) / 6 }).contains(true))
    }

    /// The samples either side of a gap are not evidence about one another, so the level
    /// after one is the level, not a 200 m fall.
    @Test func aRecordingGapRestartsTheBaseline() {
        let alt = dry(60) + wet(30)
        #expect(mask(alt).contains(true), "with no gap it is a dunk")
        var gap = [Bool](repeating: false, count: alt.count)
        gap[60] = true
        #expect(!mask(alt, gap: gap).contains(true), "across a gap it is a new baseline")
    }

    @Test func noAltitudeChannelIsAllFalse() {
        #expect(!mask([nil, nil, nil, nil]).contains(true))
    }

    // MARK: - The reference

    /// `dropM` is measured against the baseline in force at the run's first wet sample — the
    /// same line the mask crossed to open it — so it can never be under `turnBaroDrop`.
    @Test func theDropIsMeasuredAgainstTheMasksOwnReference() throws {
        let run = try #require(runs(dry(10) + [-100, -347, -100] + dry(10)).first)
        #expect(run.dropM == 347)
        #expect(run.dropM >= dropM)
    }

    @Test func aSourceWithNoBarometerHasNoEpisodes() {
        let none = runs([nil, nil, nil, nil])
        #expect(none.isEmpty)
    }

    /// A channel that never moves is not a dunk. Nothing is invented from GPS altitude.
    @Test func aFlatChannelHasNoEpisodes() {
        let flat = runs([Double?](repeating: 12, count: 40))
        #expect(flat.isEmpty)
    }

    // MARK: - Runs

    @Test func oneRunIsOneEpisodeAtItsFirstSample() throws {
        let run = try #require(runs(dry(10) + wet(4) + dry(10)).first)
        #expect(run.startT == 10)
        #expect(run.endT == 13)
        #expect(run.durationS == 3)
        #expect(run.turnIndex == nil)
        #expect(run.flightEndIndex == nil)
    }

    @Test func twoRunsFarApartStayTwo() {
        #expect(runs(dry(5) + wet(2) + dry(10) + wet(2) + dry(5)).count == 2)
    }

    /// One dunk and the wave right after it. At 4 Hz two runs 1 s apart are one episode —
    /// and two again the moment the merge window is closed.
    @Test func runsCloserThanTheMergeWindowBecomeOne() {
        let alt = dry(8) + wet(4) + dry(4) + wet(4) + dry(8)
        #expect(runs(alt, hz: 4).count == 1)
        #expect(runs(alt, hz: 4, mergeS: 0).count == 2)
    }

    /// The samples either side of a recording gap are not evidence about one another — the
    /// rule every other window in `Evidence` obeys — so a hole mid-dunk is two episodes and
    /// neither of them is timed across it.
    @Test func aRecordingGapAlwaysBreaksARun() {
        var gap = [Bool](repeating: false, count: 14)
        gap[7] = true
        var flags = [Bool](repeating: false, count: 14)
        for i in 4..<10 { flags[i] = true }
        let out = episodes(flags, dry(4) + wet(6) + dry(4), gap: gap)
        #expect(out.map(\.startT) == [4, 7])
        #expect(out.map(\.endT) == [6, 9])
    }

    @Test func aGapIsNeverMergedAcross() {
        var gap = [Bool](repeating: false, count: 13)
        gap[7] = true
        var flags = [Bool](repeating: false, count: 13)
        for i in [4, 5, 7, 8] { flags[i] = true }
        #expect(episodes(flags, dry(4) + wet(2) + dry(1) + wet(2) + dry(4),
                         hz: 4, gap: gap).count == 2)
    }

    // MARK: - Attribution

    private func sub(_ startT: Double, _ endT: Double) -> Submersion {
        Submersion(startT: startT, endT: endT, durationS: endT - startT, dropM: 200)
    }

    @Test func aTurnWinsOverAFlightEnd() {
        var subs = [sub(10, 12)]
        Evidence.attribute(&subs, turnWindows: [(index: 3, start: 8, end: 14)],
                           endWindows: [(index: 1, start: 9, end: 20)])
        #expect(subs[0].turnIndex == 3)
        #expect(subs[0].flightEndIndex == nil)
    }

    @Test func aFlightEndCatchesWhatNoTurnDoes() {
        var subs = [sub(30, 31)]
        Evidence.attribute(&subs, turnWindows: [(index: 3, start: 8, end: 14)],
                           endWindows: [(index: 1, start: 29, end: 40)])
        #expect(subs[0].turnIndex == nil)
        #expect(subs[0].flightEndIndex == 1)
    }

    /// Neither is a real answer — "while off foil" — and not a missing one.
    @Test func anEpisodeInNoWindowIsOffFoil() {
        var subs = [sub(100, 140)]
        Evidence.attribute(&subs, turnWindows: [(index: 3, start: 8, end: 14)],
                           endWindows: [(index: 1, start: 29, end: 40)])
        #expect(subs[0].turnIndex == nil)
        #expect(subs[0].flightEndIndex == nil)
    }

    /// A 47 s swim that merely *starts* inside a jibe's outcome window is that jibe's: the
    /// window is where the verdict was read, and overlapping it is what the flag meant.
    @Test func overlapIsEnoughContainmentIsNotRequired() {
        var subs = [sub(13, 60)]
        Evidence.attribute(&subs, turnWindows: [(index: 2, start: 8, end: 14)], endWindows: [])
        #expect(subs[0].turnIndex == 2)
    }

    // MARK: - The verdict flags do not move

    /// The corpus check, on the one fixture with wrist dunks in it: every turn and end the
    /// mask flagged still carries its flag, and every one of them has an episode overlapping
    /// the window the verdict was read from. The relationship is one-way — an episode need
    /// not belong to anything, which is exactly the case the old layer could not draw.
    @Test func everyFlaggedVerdictStillHasItsEvidence() throws {
        let url = testFixturesDir.appendingPathComponent(
            "goldens/2026-08-29-1440_nago-torbole-windsurfen_ciq.expected.json")
        let analysis = try JSONDecoder().decode(SessionAnalysis.self,
                                                from: Data(contentsOf: url))
        // 35 until engine 0.22.0: seventeen of them were stretches where this watch's
        // altimeter had simply re-anchored, and are read as riding now (ADR-029).
        #expect(analysis.submersions.count == 18)

        for turn in analysis.turns where turn.submerged && turn.counted {
            let w0 = turn.ts, w1 = turn.endTs + turn.outcomeWindowS
            #expect(analysis.submersions.contains { $0.ts <= w1 && $0.endTs >= w0 })
        }
        for end in analysis.flightEnds
        where end.submerged && end.ownedByTurn == nil && !end.truncated {
            let w0 = end.ts, w1 = end.ts + end.windowS
            #expect(analysis.submersions.contains { $0.ts <= w1 && $0.endTs >= w0 })
        }

        // Runs of one mask: disjoint, in time order, never shallower than the threshold, and
        // named at most once.
        for (a, b) in zip(analysis.submersions, analysis.submersions.dropFirst()) {
            #expect(a.endTs < b.ts)
        }
        for s in analysis.submersions {
            #expect(s.endTs >= s.ts)
            #expect(s.dropM >= analysis.config.turnBaroDrop)
            #expect(s.turnIndex == nil || s.flightEndIndex == nil)
            if let i = s.turnIndex { #expect(analysis.turns[i].counted) }
            if let i = s.flightEndIndex {
                #expect(analysis.flightEnds[i].ownedByTurn == nil)
                #expect(!analysis.flightEnds[i].truncated)
            }
        }
    }

    /// A stored analysis written before the block decodes with an empty list rather than
    /// throwing — the same lenience every earlier block's keys get. Such a row is stale by
    /// `engineVersion` anyway and `reanalyzeStale()` re-derives it.
    @Test func anAnalysisWithoutTheBlockStillDecodes() throws {
        let url = testFixturesDir.appendingPathComponent(
            "goldens/2026-08-29-1440_nago-torbole-windsurfen_ciq.expected.json")
        var obj = try #require(try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)) as? [String: Any])
        obj.removeValue(forKey: "submersions")
        let data = try JSONSerialization.data(withJSONObject: obj)
        let analysis = try JSONDecoder().decode(SessionAnalysis.self, from: data)
        #expect(analysis.submersions.isEmpty)
        // And the verdict flags it was read beside are still there, untouched.
        #expect(analysis.turns.contains { $0.submerged })
    }
}
