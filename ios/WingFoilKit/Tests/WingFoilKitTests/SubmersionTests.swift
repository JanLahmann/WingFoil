import Foundation
import Testing
@testable import WingFoilKit

/// Submersion episodes (engine 0.16.0, docs/algorithms.md "Submersion episodes").
///
/// The mask itself is old and covered through the outcome ladder; what is new is reading it
/// as *events*. So these cases are about the three decisions that turn a boolean array into
/// a list a map can draw: where a run starts and stops, what a recording gap does to it, and
/// what the episode is said to have happened during. Cross-implementation agreement with the
/// lab's own list is asserted in `GoldenTests.checkSubmersions`, on the whole corpus.
@Suite struct SubmersionTests {

    private let dropM = 25.0

    /// Episodes for a bare altitude series, on a regular clock with no gaps by default.
    private func runs(_ alt: [Double?], hz: Double = 1, gap: [Bool]? = nil,
                      mergeS: Double = Evidence.submersionMergeS) -> [Submersion] {
        let t = (0..<alt.count).map { Double($0) / hz }
        let gaps = gap ?? [Bool](repeating: false, count: alt.count)
        return Evidence.submersionRuns(t: t, gap: gaps,
                                       submerged: Evidence.submergedMask(alt, dropM: dropM),
                                       alt: alt, mergeS: mergeS)
    }

    private func wet(_ count: Int) -> [Double?] { [Double?](repeating: -200, count: count) }
    private func dry(_ count: Int) -> [Double?] { [Double?](repeating: 0, count: count) }

    // MARK: - The reference

    /// `dropM` is measured against the same line the mask is, so it can never be under
    /// `turnBaroDrop` — the check that says the two are one definition and not two.
    @Test func theDropIsMeasuredAgainstTheMasksOwnReference() throws {
        #expect(Evidence.submergedReference([0, 1, 2, 3, -300]) == 1)
        let run = try #require(runs(dry(10) + [-100, -347, -100] + dry(10)).first)
        #expect(run.dropM == 347)
        #expect(run.dropM >= dropM)
    }

    @Test func aSourceWithNoBarometerHasNoEpisodes() {
        #expect(Evidence.submergedReference([nil, nil, nil]) == nil)
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
        let out = runs(dry(4) + wet(6) + dry(4), gap: gap)
        #expect(out.map(\.startT) == [4, 7])
        #expect(out.map(\.endT) == [6, 9])
    }

    @Test func aGapIsNeverMergedAcross() {
        var gap = [Bool](repeating: false, count: 13)
        gap[7] = true
        #expect(runs(dry(4) + wet(2) + dry(1) + wet(2) + dry(4), hz: 4, gap: gap).count == 2)
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
        #expect(analysis.submersions.count == 35)

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
