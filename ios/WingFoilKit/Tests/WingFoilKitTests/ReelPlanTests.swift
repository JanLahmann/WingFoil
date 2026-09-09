import Foundation
import Testing
@testable import WingFoilKit

/// The session video's cut: which instants it stops for, and the clock it draws the track
/// on.
///
/// Asserted against a decoded analysis golden rather than a hand-built session, for the same
/// reason `ReplayBeatsTests` is: the interesting rules here are about a real afternoon's
/// turns, records and flights, and a synthetic one can be made to agree with any rule.
/// The warp's *properties* — monotone, exact at both ends, slower at a moment than in a gap
/// — are then checked on both the golden and on hand-built spans where the arithmetic can
/// be done by eye.
@Suite struct ReelPlanTests {

    private func golden(_ stem: String) throws -> SessionAnalysis {
        let url = testFixturesDir.appendingPathComponent("goldens/\(stem).expected.json")
        return try JSONDecoder().decode(SessionAnalysis.self, from: Data(contentsOf: url))
    }

    /// 2026-08-30 Torbole: 645 s, two flights (the longest starting at 85 s), ten counted
    /// jibes — eight flown of which five clean, two swum — a 2 s peak at 292 s, and one
    /// submersion at 496 s.
    private func torbole() throws -> SessionAnalysis {
        try golden("2026-08-30-1407_nago-torbole-windsurfen_ciq")
    }

    // MARK: - The moments

    @Test func theCutStopsForEveryCountedJibeTheRecordsAndTheLongestTakeoff() throws {
        let plan = ReelPlan.make(try torbole(), span: 0...645)

        // One takeoff (the longest flight's), ten jibes, three records, one wrist-under.
        #expect(plan.moments.count == 15)
        #expect(plan.moments.map(\.t) == plan.moments.map(\.t).sorted(),
                "moments must be in time order")
        #expect(Set(plan.moments.map(\.id)).count == plan.moments.count, "ids must be unique")

        #expect(plan.moments.first(where: { $0.kind == .takeoff })?.t == 85)

        let jibes = plan.moments.filter { if case .jibe = $0.kind { true } else { false } }
        #expect(jibes.map(\.t) == [151, 222, 255, 278, 320, 362, 399, 441, 467, 571])

        // The records the key-metrics block prints, each at its own window's start rather
        // than at a turn near it.
        let records = plan.moments.filter { if case .record = $0.kind { true } else { false } }
        #expect(records.map(\.id) == ["record-alpha500", "record-best5x10s", "record-best2s"]
            .sorted { lhs, rhs in
                let at = ["record-alpha500": 263.0, "record-best5x10s": 288.0,
                          "record-best2s": 292.0]
                return at[lhs]! < at[rhs]!
            })
        #expect(records.map(\.t) == [263, 288, 292])

        #expect(plan.moments.filter { $0.kind == .submersion }.map(\.t) == [496])
    }

    /// The callouts borrow every word they print. A reel that spelled a verdict or a record
    /// its own way would be a second, disagreeing vocabulary on the one surface that leaves
    /// the phone.
    @Test func calloutsBorrowTheirWordsFromTheLabelTable() throws {
        let plan = ReelPlan.make(try torbole(), span: 0...645)
        let byID = Dictionary(uniqueKeysWithValues: plan.moments.map { ($0.id, $0.headline) })

        #expect(byID["takeoff"] == "takeoff")
        // Jibe 0 flew through and was not clean; jibe 1 was clean and says so instead.
        #expect(byID["jibe-0"] == "jibe · flew through")
        #expect(byID["jibe-1"] == "clean jibe")
        #expect(byID["jibe-8"] == "jibe · fell in")
        #expect(byID["record-best2s"] == "best 2 s 13.47 kn")
        #expect(byID["record-alpha500"] == "best alpha 500 11.70 kn")
        #expect(byID["wet-0"] == "wrist under")

        // Every verdict word is `TurnOutcomeKind.label`'s, and every record's is
        // `RecordKind.windowLabel`'s — no reel-only spelling anywhere.
        for moment in plan.moments {
            switch moment.kind {
            case .jibe(let outcome, let clean):
                #expect(clean || moment.headline.hasSuffix(outcome.label))
            case .record(let key):
                let kind = RecordKind(rawValue: key)
                #expect(kind != nil && moment.headline.contains(kind!.windowLabel))
            case .takeoff, .submersion:
                break
            }
        }
    }

    /// A moment the playhead can never reach is a callout that never fires and a bump the
    /// warp spends its budget on.
    @Test func momentsOutsideTheSpanAreDropped() throws {
        let plan = ReelPlan.make(try torbole(), span: 200...400)
        #expect(plan.moments.allSatisfy { (200...400).contains($0.t) })
        #expect(!plan.moments.contains { $0.id == "takeoff" })      // 85 s, before the span
        #expect(!plan.moments.contains { $0.id == "wet-0" })        // 496 s, after it
        #expect(plan.moments.contains { $0.id == "jibe-4" })        // 320 s, inside it
    }

    // MARK: - The lengths

    @Test func theCutIsThreeSecondsOfEndCardAndTheRestOfMap() throws {
        for length in ReelPlan.Length.allCases {
            let plan = ReelPlan.make(try torbole(), span: 0...645, length: length)
            #expect(plan.totalS == length.seconds)
            #expect(plan.mapS == length.seconds - 3)
            #expect(plan.frameCount == Int(length.seconds) * 30)
            #expect(!plan.isEndCard(atReelTime: plan.mapS - 0.01))
            #expect(plan.isEndCard(atReelTime: plan.mapS))
            #expect(plan.endCardProgress(atReelTime: plan.totalS) == 1)
        }
        #expect(ReelPlan.Length.standard == .s20)
        #expect(ReelPlan.Length.allCases.map(\.label) == ["15 s", "20 s", "30 s"])
    }

    // MARK: - The warp

    /// The three properties a renderer depends on and cannot check for itself: the whole
    /// track draws (both ends land exactly), it never draws backwards, and the map section
    /// is used up exactly once.
    @Test func theWarpIsMonotoneAndExactAtBothEnds() throws {
        let plan = ReelPlan.make(try torbole(), span: 0...645)

        #expect(abs(plan.sessionTime(atReelTime: 0) - 0) < 0.01)
        #expect(abs(plan.sessionTime(atReelTime: plan.mapS) - 645) < 0.01)
        #expect(plan.reelTime(ofSessionTime: 0) == 0)
        #expect(abs(plan.reelTime(ofSessionTime: 645) - plan.mapS) < 1e-9)

        var previous = -1.0
        for frame in 0...(Int(plan.mapS) * ReelPlan.fps) {
            let t = plan.sessionTime(atReelTime: Double(frame) / Double(ReelPlan.fps))
            #expect(t >= previous, "the playhead must never go backwards")
            #expect((0...645).contains(t.rounded(.towardZero)))
            previous = t
        }

        // Past the map section the playhead holds on the last frame of the session, so the
        // end card is drawn over a finished track rather than a rewound one.
        #expect(plan.sessionTime(atReelTime: plan.totalS) == plan.sessionTime(atReelTime: plan.mapS))
    }

    /// Round-tripping is what makes the plan usable from both directions — the renderer asks
    /// "where am I at frame n", the callout scheduler asks "which frame is this jibe on".
    @Test func theTwoDirectionsAgree() throws {
        let plan = ReelPlan.make(try torbole(), span: 0...645)
        for t in stride(from: 0.0, through: 645.0, by: 5) {
            let round = plan.sessionTime(atReelTime: plan.reelTime(ofSessionTime: t))
            #expect(abs(round - t) < 1.0, "round trip drifted at \(t) s: \(round)")
        }
    }

    /// The point of the whole exercise: a jibe is slower than the water between jibes.
    @Test func theClockSlowsAtAMomentAndSpeedsUpBetweenThem() throws {
        let plan = ReelPlan.make(try torbole(), span: 0...645)

        // 222 s is a clean jibe; 190 s is open water halfway to the one before it.
        let atJibe = plan.compression(atReelTime: plan.reelTime(ofSessionTime: 222))
        let inGap = plan.compression(atReelTime: plan.reelTime(ofSessionTime: 190))
        #expect(atJibe < inGap, "a jibe must be slower than the gap before it")
        // The boost is 5×, and the dip's floor is reached at the moment's own instant.
        #expect(inGap / atJibe > 3, "the gap should run several times faster than the jibe")

        // And the moments really do own a share of the cut rather than all of it: the
        // fourteen slowing moments together stay under the budget.
        let premium = Double(plan.moments.filter(\.kind.slowsTheClock).count)
            * ReelPlan.calloutS
        #expect(premium > plan.mapS, "this session has more moments than seconds")
        #expect(plan.halfWidthS >= ReelPlan.minHalfWidthS)
    }

    /// Hand-built, where the arithmetic can be checked by eye: one moment in the middle of a
    /// hundred-second session must sit at the middle of the cut, and the two halves either
    /// side of it must be symmetric.
    @Test func oneMomentInTheMiddleSplitsTheCutInHalf() {
        let plan = ReelPlan(span: 0...100, length: .s20,
                            moments: [ReelMoment(id: "m", t: 50, kind: .takeoff,
                                                 headline: "takeoff")])
        #expect(abs(plan.reelTime(ofSessionTime: 50) - plan.mapS / 2) < 0.05)
        let before = plan.sessionTime(atReelTime: plan.mapS / 4)
        let after = plan.sessionTime(atReelTime: plan.mapS * 3 / 4)
        #expect(abs((50 - before) - (after - 50)) < 0.5, "the warp must be symmetric")
        // And the middle really is dwelt on: a quarter of the cut covers much less than a
        // quarter of the session on the half that contains the moment.
        #expect(after - 50 < 25)
    }

    /// A session with nothing in it is a linear draw, not a crash and not a still frame.
    @Test func aSessionWithNoMomentsDrawsAtOneEvenRate() {
        let plan = ReelPlan(span: 0...600, length: .s20, moments: [])
        #expect(plan.moments.isEmpty)
        #expect(plan.halfWidthS == 0)
        for fraction in stride(from: 0.0, through: 1.0, by: 0.1) {
            let t = plan.sessionTime(atReelTime: plan.mapS * fraction)
            #expect(abs(t - 600 * fraction) < 0.6, "an empty session must draw linearly")
        }
        #expect(plan.callout(atReelTime: 4) == nil)
    }

    /// Degenerate spans are what a two-sample import and a stopped watch produce, and the
    /// renderer divides by everything here.
    @Test func aSpanWithNoLengthDoesNotDivideByZero() {
        let plan = ReelPlan(span: 12...12, length: .s15,
                            moments: [ReelMoment(id: "m", t: 12, kind: .takeoff,
                                                 headline: "takeoff")])
        #expect(plan.sessionTime(atReelTime: 0) == 12)
        #expect(plan.sessionTime(atReelTime: plan.mapS) == 12)
        #expect(plan.reelTime(ofSessionTime: 12) == 0)
        #expect(plan.frameCount == 450)
    }

    // MARK: - Callouts

    @Test func oneCalloutAtATimeAndNeverBeforeTheThingItNames() throws {
        let plan = ReelPlan.make(try torbole(), span: 0...645)

        for moment in plan.moments {
            let opens = plan.reelTime(ofSessionTime: moment.t)
            // Nothing is on screen at the instant before a moment that names *that* moment.
            #expect(plan.callout(atReelTime: max(opens - 0.001, 0))?.moment.id != moment.id)
            // And it is up, from the start of its window, unless a later moment has already
            // taken the screen — which is the rule, not a failure.
            if let shown = plan.callout(atReelTime: opens) {
                #expect(shown.moment.t >= moment.t)
            }
        }

        // The window is `calloutS` of *reel* time and closes on its own.
        let takeoff = plan.reelTime(ofSessionTime: 85)
        #expect(plan.callout(atReelTime: takeoff)?.moment.id == "takeoff")
        #expect(plan.callout(atReelTime: takeoff)?.progress == 0)
        #expect(plan.callout(atReelTime: takeoff + ReelPlan.calloutS)?.moment.id != "takeoff")

        // Nothing pops over the end card — that frame is the card and only the card.
        #expect(plan.callout(atReelTime: plan.mapS + 0.5) == nil)
    }

    // MARK: - The running tally

    @Test func theTallyCountsTheJibesThatHaveHappenedAndNothingElse() throws {
        let plan = ReelPlan.make(try torbole(), span: 0...645)

        #expect(plan.tally(throughSessionTime: 0) == ReelPlan.Tally())
        // After the first jibe: one flew through, not clean, and it was dry.
        let first = plan.tally(throughSessionTime: 151)
        #expect(first.flew == 1 && first.touchdown == 0 && first.fell == 0)
        #expect(first.clean == 0 && first.dry == 1 && first.counted == 1)

        // After the first swim, at 467 s: eight flown, one fallen, five of them clean.
        let mid = plan.tally(throughSessionTime: 467)
        #expect(mid.flew == 8 && mid.fell == 1 && mid.clean == 5)
        #expect(mid.dry == 8, "a swim never advances the dry count")

        // The whole afternoon, which is the end card's tally.
        let final = plan.tally(throughSessionTime: 645)
        #expect(final.flew == 8 && final.touchdown == 0 && final.fell == 2)
        #expect(final.counted == 10 && final.clean == 5)

        // A takeoff, a record and a wrist-under are not jibes and never move it.
        #expect(plan.tally(throughSessionTime: 300) == plan.tally(throughSessionTime: 310))
    }

    /// Determinism is the whole reason this is a kit type: two renders of one session must
    /// be the same video, on the same machine and on a different one.
    @Test func twoPlansForOneSessionAreTheSamePlan() throws {
        let analysis = try torbole()
        let a = ReelPlan.make(analysis, span: 0...645)
        let b = ReelPlan.make(analysis, span: 0...645)
        #expect(a == b)
        #expect(a.halfWidthS == b.halfWidthS)
        for frame in stride(from: 0, to: a.frameCount, by: 7) {
            let r = Double(frame) / Double(ReelPlan.fps)
            #expect(a.sessionTime(atReelTime: r) == b.sessionTime(atReelTime: r))
        }
        #expect(ReelPlan.make(analysis, span: 0...645, length: .s30) != a)
    }
}
