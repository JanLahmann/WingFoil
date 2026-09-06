import Foundation
import Testing
@testable import WingFoilKit

/// One turn cut out of a session: the projection, the headings, the wind-up rotation, the
/// choice of comparison turn — and the one sentence written from all of it.
///
/// Synthetic rather than golden, deliberately, and for the opposite reason to
/// `ReplayCommentaryTests`. The commentary is about the *shape of an afternoon*, which only a
/// real one has; this is about geometry, where a quarter circle of known radius is the only
/// fixture that can tell a correct rotation from a plausible one. A turn drawn mirrored, or
/// rotated the wrong way round the wind, looks entirely normal on a corpus session.
@Suite struct TurnSliceTests {

    // MARK: - Fixtures

    /// The anchor everything is projected around. The equirectangular round trip is exact at
    /// the anchor's own latitude, and the entry point of every synthetic turn below sits
    /// exactly there — so a metre in is a metre out and the assertions can be tight.
    private static let lat0 = 45.87
    private static let lon0 = 10.87

    private func sample(t: Double, x: Double, y: Double, kn: Double) -> TurnSlice.Sample {
        let cosLat = cos(Self.lat0 * .pi / 180)
        return TurnSlice.Sample(t: t,
                                lat: Self.lat0 + y / 110_540,
                                lon: Self.lon0 + x / (cosLat * 111_320),
                                kn: kn)
    }

    /// A turn built field by field, through the golden schema — the same trick
    /// `PresentationTests` uses, because `TurnRecord`'s only initializer takes an engine
    /// `Turn` and this suite has no business constructing one.
    private func turn(ts: Double = 100, endTs: Double = 106, type: String = "jibe",
                      counted: Bool = true, entryKn: Double = 12, minKn: Double = 6,
                      minTs: Double = 103, exitKn: Double = 10,
                      score: Double = 0.5, success: Bool = false, side: String = "port",
                      direction: String = "starboard", netDeg: Double = 90,
                      radiusM: Double = 20, outcome: String = "flew_through",
                      offFoilS: Double = 0, stoppedS: Double = 0,
                      pumped: Bool = false, submerged: Bool = false) throws -> TurnRecord {
        let json: [String: Any] = [
            "ts": ts, "endTs": endTs, "minTs": minTs, "type": type, "counted": counted,
            "entryKn": entryKn, "minKn": minKn, "exitKn": exitKn,
            "score": score, "success": success,
            // The engine's 0.12.0 clean rule, spelled here so a fixture is never cleaner
            // than a real turn with the same fields would be.
            "clean": counted && type == "jibe" && success && outcome == "flew_through",
            "side": side, "direction": direction, "netDeg": netDeg, "arcM": 31.4,
            "radiusM": radiusM, "outcome": outcome, "borderline": false,
            "offFoilS": offFoilS, "stoppedS": stoppedS, "pumped": pumped,
            "submerged": submerged, "outcomeWindowS": 11.0,
        ]
        return try JSONDecoder().decode(TurnRecord.self,
                                        from: JSONSerialization.data(withJSONObject: json))
    }

    /// A quarter circle of radius 20 m, entered heading **north** at t = 100 and left heading
    /// **east** at t = 106, with 8 s of straight lead-in before it and 8 s of run-out after.
    ///
    /// The parameterization is the one the heading test leans on: with the centre 20 m to the
    /// east of the entry, position(φ) = centre + R·(−cos φ, sin φ) puts the entry at the
    /// origin and makes the course over ground exactly φ. So a sample at φ = 45° is a rider
    /// pointing north-east, and any bug in `atan2`'s argument order shows up as 45° of error
    /// rather than as a plausible-looking arc.
    ///
    /// Speed dips to 6 kn at the halfway point and comes out at 10.
    private func quarterCircle(speedAtHalfway halfwayRt: Double = 3) -> [TurnSlice.Sample] {
        let radius = 20.0
        func kn(_ rt: Double) -> Double {
            // A V through the window with its point at `halfwayRt`, so the minimum is where
            // the test asked for it and nowhere else.
            rt < 0 ? 12 : (rt <= halfwayRt
                           ? 12 - 6 * (rt / max(halfwayRt, 0.001))
                           : min(6 + 4 * ((rt - halfwayRt) / max(6 - halfwayRt, 0.001)), 12))
        }
        var out: [TurnSlice.Sample] = []
        // Lead-in: straight north, 5 m/s, arriving at the origin at t = 100.
        for step in stride(from: -8.0, to: 0, by: 1) {
            out.append(sample(t: 100 + step, x: 0, y: step * 5, kn: kn(step)))
        }
        // The sweep: φ = 15° per second, 0 → 90 over six seconds.
        for step in stride(from: 0.0, through: 6, by: 1) {
            let phi = step * 15 * .pi / 180
            out.append(sample(t: 100 + step,
                              x: radius - radius * cos(phi),
                              y: radius * sin(phi),
                              kn: kn(step)))
        }
        // Run-out: straight east from the exit.
        for step in stride(from: 7.0, through: 14, by: 1) {
            out.append(sample(t: 100 + step, x: radius + (step - 6) * 5, y: radius,
                              kn: kn(min(step, 6))))
        }
        return out
    }

    private func slice(_ turn: TurnRecord, windDirDeg: Double? = nil,
                       samples: [TurnSlice.Sample]? = nil) -> TurnSlice {
        TurnSlice.make(samples: samples ?? quarterCircle(), turn: turn,
                       windDirDeg: windDirDeg)
    }

    // MARK: - Projection

    /// The entry point is the origin, and everything else is metres east and north of it.
    /// That is what lets a ghost turn be laid over this one by doing nothing at all.
    @Test func theTurnIsProjectedIntoMetresAroundItsOwnEntryPoint() throws {
        let cut = slice(try turn())
        let entry = try #require(cut.points.first { $0.rt == 0 })
        #expect(abs(entry.x) < 0.01)
        #expect(abs(entry.y) < 0.01)

        // Six seconds in the rider has swept a quarter of a 20 m circle: 20 m east and 20 m
        // north of where he started.
        let exit = try #require(cut.points.first { $0.rt == 6 })
        #expect(abs(exit.x - 20) < 0.05)
        #expect(abs(exit.y - 20) < 0.05)

        // Relative time is the turn's clock, negative through the approach.
        // The window is the sweep plus `defaultPadS` either side of it, on the turn's clock.
        #expect(cut.points.first?.rt == -8)
        #expect(cut.points.last?.rt == 14)
        #expect(cut.points.filter(\.inTurn).map(\.rt) == [0, 1, 2, 3, 4, 5, 6])
    }

    /// A window with no positioned samples anywhere near it still carries its numbers — the
    /// sheet is mostly numbers — and simply draws nothing.
    @Test func aTurnWithNoFixesDegradesToNumbersOnly() throws {
        let cut = TurnSlice.make(samples: [], turn: try turn(), windDirDeg: 210)
        #expect(!cut.hasGeometry)
        #expect(cut.bounds == nil)
        #expect(cut.windUpBounds == nil)
        #expect(cut.midRotationRt == nil)
        // The engine's numbers survive, because they never came from the samples.
        #expect(cut.speed.entryKn == 12)
        #expect(cut.speed.minKn == 6)
    }

    // MARK: - Heading

    @Test func headingIsTheCourseFromEachVertexToTheNext() throws {
        let cut = slice(try turn())
        let arc = cut.points.filter(\.inTurn)

        // Entered heading north, left heading east, monotonically clockwise in between.
        let entry = try #require(arc.first?.headingDeg)
        #expect(abs(entry - 7.5) < 1.5, "the chord of the first second, half a step round")
        let exit = try #require(arc.last?.headingDeg)
        #expect(abs(exit - 90) < 4)
        let headings = arc.compactMap(\.headingDeg)
        #expect(headings.count == arc.count)
        #expect(zip(headings, headings.dropFirst()).allSatisfy { $0 < $1 })
    }

    /// The bearing of a metre of GPS noise is a random number, and a tick drawn along it
    /// would spin. Below `minStepM` there is simply no heading.
    @Test func aStepTooShortToHaveABearingHasNone() throws {
        let stalled = [
            sample(t: 100, x: 0, y: 0, kn: 4),
            sample(t: 101, x: 0.2, y: 0.1, kn: 4),
            sample(t: 102, x: 6, y: 0.1, kn: 4),
        ]
        let cut = TurnSlice.make(samples: stalled,
                                 turn: try turn(ts: 100, endTs: 102), windDirDeg: nil)
        #expect(cut.points[0].headingDeg == nil, "0.22 m is under the half-metre floor")
        #expect(cut.points[1].headingDeg != nil)
        // The last vertex inherits the one before it rather than vanishing at the frame edge.
        #expect(cut.points[2].headingDeg == cut.points[1].headingDeg)
    }

    // MARK: - Wind up

    /// Wind up means the wind blows **from the top of the frame**. So the direction it comes
    /// from lands on +y, and a rider running downwind travels toward the bottom of the page —
    /// which is the shape a rider recognises a jibe by.
    @Test func windUpPutsTheWindAtTheTopOfTheFrame() throws {
        // Wind from the east.
        let cut = slice(try turn(), windDirDeg: 90)
        let up = try #require(cut.windUpPoints)

        // The exit vertex: 20 m east and 20 m north of the entry. East is upwind, so its
        // eastings become the height up the page; north becomes the left edge.
        let index = try #require(cut.points.firstIndex { abs($0.x - 20) < 0.05
                                                          && abs($0.y - 20) < 0.05 })
        #expect(abs(up[index].y - 20) < 0.05, "20 m east becomes 20 m toward the top")
        #expect(abs(up[index].x + 20) < 0.05, "20 m north becomes 20 m to the left")

        // And the headings rotate with the points: due east is now straight up the page.
        let eastbound = try #require(cut.points.last(where: {
            ($0.headingDeg.map { abs($0 - 90) < 1 }) == true
        }))
        let rotated = TurnSlice.rotated([eastbound], windFromDeg: 90)[0]
        #expect(abs(try #require(rotated.headingDeg)) < 1, "sailing into the wind points up")

        // A rider running dead downwind travels toward the bottom.
        let downwind = TurnSlice.Point(x: -10, y: 0, rt: 0, kn: 8, headingDeg: 270,
                                       inTurn: true)
        let spun = TurnSlice.rotated([downwind], windFromDeg: 90)[0]
        #expect(abs(spun.x) < 0.001)
        #expect(abs(spun.y + 10) < 0.001)
        #expect(abs(try #require(spun.headingDeg) - 180) < 0.001)
    }

    /// A rotation is a rotation: it moves the frame, never the shape. The two orientations of
    /// one turn must be the same size, or the control would be a zoom as well as a rotate.
    @Test func rotatingTheFrameChangesNothingAboutTheTurn() throws {
        let cut = slice(try turn(), windDirDeg: 210)
        let north = try #require(cut.bounds)
        let up = try #require(cut.windUpBounds)
        // The bounding box of a rotated arc is not the rotated bounding box, so the sides
        // move; the *distances between points* do not.
        let a = cut.points[0], b = cut.points[cut.points.count - 1]
        let upA = try #require(cut.windUpPoints)[0]
        let upB = try #require(cut.windUpPoints)[cut.points.count - 1]
        let before = hypot(a.x - b.x, a.y - b.y)
        let after = hypot(upA.x - upB.x, upA.y - upB.y)
        #expect(abs(before - after) < 0.001)
        #expect(north.width > 0 && up.width > 0)
    }

    /// No wind, no wind-up frame — which is exactly when the orientation control's second
    /// option is disabled rather than quietly drawing north up under the wrong label.
    @Test func withoutAWindDirectionThereIsNoWindUpFrame() throws {
        let cut = slice(try turn(), windDirDeg: nil)
        #expect(cut.windUpPoints == nil)
        #expect(cut.windUpBounds == nil)
        // The accessor falls back rather than returning nothing to draw.
        #expect(cut.points(windUp: true) == cut.points)
        #expect(cut.bounds(windUp: true) == cut.bounds)
    }

    // MARK: - Framing

    @Test func theFrameIsPaddedAndNeverNarrowerThanTheFloor() throws {
        let cut = slice(try turn())
        let bounds = try #require(cut.bounds)
        // The drawn window is about 60 m across; the pad adds 14 % of the larger side to
        // every edge.
        #expect(bounds.width > 60)
        #expect(bounds.height > 40)

        // A rider who pivoted on the spot gets a 20 m frame, not a picture of the receiver's
        // own scatter.
        let tiny = TurnSlice.Bounds(minX: 0, minY: 0, maxX: 1, maxY: 1).padded()
        #expect(tiny.spanM >= TurnSlice.minSpanM)

        #expect(TurnSlice.scaleBarM(forSpanM: 200) == 50)
        #expect(TurnSlice.scaleBarM(forSpanM: 60) == 25)
        #expect(TurnSlice.scaleBarM(forSpanM: 25) == 10)
        #expect(TurnSlice.scaleBarM(forSpanM: 4) == 10, "there is always a bar")
    }

    // MARK: - Speed marks and the halfway point

    /// The strip's three markers are the record's own `entryKn` / `minKn` at `minTs` / `exitKn`
    /// (6 Sep 2026): the strip draws the maneuver channel the record was scored on, so the
    /// engine's numbers *are* on the line, and the row and the strip print the same digits.
    @Test func theStripsMarksAreTheRecordsOwnNumbers() throws {
        let cut = slice(try turn())
        #expect(abs(cut.speed.entryKn - 12) < 0.001)
        #expect(abs(cut.speed.minKn - 6) < 0.001)
        #expect(cut.speed.minRt == 3)
        #expect(abs(cut.speed.exitKn - 10) < 0.001)
        #expect(cut.speed.exitRt == 6)
        #expect(cut.durationS == 6)
        #expect(cut.timeDomain == -8 ... 14)
    }

    /// The low point is the record's `minTs`, which the engine only ever places **inside the
    /// sweep** — a slow approach in the samples cannot move it, and marking a lead-in crawl
    /// would have put the label outside the shaded band.
    @Test func theLowPointIsInsideTheSweepAndNotInTheApproach() throws {
        var samples = quarterCircle()
        // A crawl through the lead-in, slower than anything in the turn.
        samples = samples.map { s in
            s.t < 96 ? TurnSlice.Sample(t: s.t, lat: s.lat, lon: s.lon, kn: 1) : s
        }
        let cut = TurnSlice.make(samples: samples, turn: try turn(), windDirDeg: nil)
        #expect(abs(cut.speed.minKn - 6) < 0.001)
        #expect(cut.speed.minRt == 3)
        // A record whose minTs lies outside its own sweep (a hand-built one) is clamped
        // into it rather than trusted.
        let odd = TurnSlice.make(samples: samples, turn: try turn(minTs: 90), windDirDeg: nil)
        #expect(odd.speed.minRt == 0)
    }

    /// Halfway is measured as cumulative heading change, because the question the coach asks
    /// is "had he got round yet" — and a sweep that overshoots and comes back has swept more
    /// than its net.
    @Test func halfwayRoundIsHalfTheSweptHeading() throws {
        let cut = slice(try turn())
        let mid = try #require(cut.midRotationRt)
        #expect(abs(mid - 3) <= 1, "a 90° sweep at 15°/s is halfway at three seconds")
    }

    // MARK: - Ghost

    private func session() throws -> [TurnRecord] {
        [
            // The turn under the microscope: spun to starboard, mediocre.
            try turn(ts: 100, endTs: 106, score: 0.55, direction: "starboard"),
            // Same rotation, flew through, and the best score of the ones that did.
            try turn(ts: 200, endTs: 206, score: 0.88, success: true,
                     direction: "starboard", outcome: "flew_through"),
            // Same rotation, flew through, but slower.
            try turn(ts: 300, endTs: 306, score: 0.71, success: true,
                     direction: "starboard", outcome: "flew_through"),
            // The mirror image: better than any of them, and useless as a model.
            try turn(ts: 400, endTs: 406, score: 0.95, success: true,
                     direction: "port", outcome: "flew_through"),
            // A touchdown, however well it scored: not a turn to copy.
            try turn(ts: 500, endTs: 506, score: 0.93, direction: "starboard",
                     outcome: "touchdown"),
            // A tack, not a jibe.
            try turn(ts: 600, endTs: 606, type: "tack", score: 0.97, success: true,
                     direction: "starboard", outcome: "flew_through"),
            // A course change the engine rejected.
            try turn(ts: 700, endTs: 706, type: "bear_away", counted: false, score: 0.99,
                     direction: "starboard", outcome: "flew_through"),
        ]
    }

    @Test func theGhostIsTheBestCleanJibeSpunTheSameWay() throws {
        let turns = try session()
        let best = try #require(TurnSlice.bestClean(for: turns[0], in: turns))
        #expect(best.ts == 200, "the highest-scoring flew-through jibe of the same rotation")
    }

    @Test func theGhostRejectsTheMirrorImageTheLadderAndTheUncounted() throws {
        let turns = try session()
        let best = try #require(TurnSlice.bestClean(for: turns[0], in: turns))
        #expect(best.direction == "starboard")
        #expect(best.type == "jibe")
        #expect(best.counted)
        #expect(TurnOutcomeKind(best.outcome) == .flewThrough)
        // Every rejected candidate scored higher than the one that won, so nothing here can
        // pass by accident.
        #expect(turns.filter { $0.ts != best.ts }.map(\.score).max()! > best.score)
    }

    /// A dashed line exactly under the solid one reads as a rendering bug.
    @Test func aTurnIsNeverItsOwnGhost() throws {
        let turns = try session()
        // The best clean jibe of the session, asked to compare itself with something.
        let best = turns[1]
        let ghost = try #require(TurnSlice.bestClean(for: best, in: turns))
        #expect(ghost.ts == 300, "the next best of the same rotation, not itself")

        // And a session whose only same-rotation clean jibe *is* this turn has no ghost.
        let alone = [turns[0], turns[3], turns[5]]
        #expect(TurnSlice.bestClean(for: turns[3], in: alone) == nil)
    }

    /// Both slices are anchored at their own entry points, so the comparison is already
    /// aligned — in space at the origin, and in time at t = 0.
    @Test func theGhostArrivesAlreadyLaidOverTheTurn() throws {
        let turns = try session()
        let samples = quarterCircle() + quarterCircle().map {
            TurnSlice.Sample(t: $0.t + 100, lat: $0.lat + 0.01, lon: $0.lon + 0.01, kn: $0.kn)
        }
        let ghost = try #require(TurnSlice.ghost(for: turns[0], in: turns, samples: samples,
                                                 windDirDeg: 210))
        let entry = try #require(ghost.points.first { $0.rt == 0 })
        #expect(abs(entry.x) < 0.01, "a different bay, the same origin")
        #expect(abs(entry.y) < 0.01)
        #expect(ghost.turn.ts == 200)
    }

    @Test func aSessionWithNothingToCompareGetsNoGhost() throws {
        let lonely = [try turn(ts: 100, direction: "starboard")]
        #expect(TurnSlice.ghost(for: lonely[0], in: lonely, samples: quarterCircle(),
                                windDirDeg: nil) == nil)
    }

    // MARK: - The coach
    //
    // The ladder is the thing worth testing. A rule shadowed by the one above it is invisible
    // until a rider reads "the speed went before the downwind point" under a jibe he fell out
    // of, so every rung is asserted against a turn that must reach it and no other.

    @Test func everyRungOfTheLadderIsReachable() throws {
        let arc = quarterCircle()
        func rule(_ t: TurnRecord, samples: [TurnSlice.Sample] = []) -> TurnCoach.Rule {
            TurnCoach.rule(turn: t, slice: TurnSlice.make(
                samples: samples.isEmpty ? arc : samples, turn: t, windDirDeg: nil))
        }

        #expect(rule(try turn(outcome: "fell_in")) == .fellIn)
        #expect(rule(try turn(outcome: "touchdown", submerged: true)) == .wristUnder)
        #expect(rule(try turn(outcome: "touchdown", offFoilS: 4, pumped: true)) == .pumpedOut)
        // The low point at 3 s is at the halfway mark, so it was lost on the way out.
        #expect(rule(try turn(outcome: "touchdown")) == .touchdownOnExit)
        // The same turn with the engine's low point in the first second was lost coming in.
        // (`minTs` is the record's, since 6 Sep — the samples cannot move it.)
        #expect(rule(try turn(minTs: 101, outcome: "touchdown")) == .touchdownComingIn)
        #expect(rule(try turn(score: 0.9, success: true)) == .cleanAndFast)
        #expect(rule(try turn(score: 0.6)) == .cleanButSlow)
        #expect(rule(try turn(minTs: 101, score: 0.75)) == .slowedEarly)
        #expect(rule(try turn(score: 0.75)) == .slowedLate)

        // Without geometry there is no halfway point, so no rule that depends on one may
        // fire — the ladder falls through to the plain reading of the numbers.
        let blind = try turn(score: 0.75)
        #expect(TurnCoach.rule(turn: blind,
                               slice: TurnSlice.make(samples: [], turn: blind,
                                                     windDirDeg: nil)) == .plain)
        // The 0.12.0 rung: the speed held all the way round and it still ended in the
        // water — the one turn the old rule called clean.
        #expect(rule(try turn(score: 0.92, success: true, outcome: "fell_in")) == .fellInFast)
        #expect(TurnCoach.Rule.allCases.count == 11)
    }

    /// A fall outranks everything below it. The most specific true thing is the one worth
    /// the sentence, and a jibe he swam out of must never be described by its heading.
    @Test func theLadderIsOrderedBySpecificity() throws {
        let arc = quarterCircle()
        // Every flag at once: swum, wrist under, pumped, and a fine score.
        let everything = try turn(score: 0.92, success: true, outcome: "fell_in",
                                  offFoilS: 9, pumped: true, submerged: true)
        let cut = TurnSlice.make(samples: arc, turn: everything, windDirDeg: nil)
        // A fall it is, and the fast rung says so first: the score is the only thing that
        // separates the two fall sentences, and neither reaches for the heading.
        #expect(TurnCoach.rule(turn: everything, slice: cut) == .fellInFast)

        // The same fall with the speed gone gets the plain fall sentence.
        let slow = try turn(score: 0.4, outcome: "fell_in",
                            offFoilS: 9, pumped: true, submerged: true)
        #expect(TurnCoach.rule(turn: slow,
                               slice: TurnSlice.make(samples: arc, turn: slow,
                                                     windDirDeg: nil)) == .fellIn)

        // Take the fall away and the wrist is the next most specific fact.
        let wet = try turn(score: 0.92, success: true, outcome: "touchdown",
                           offFoilS: 9, pumped: true, submerged: true)
        #expect(TurnCoach.rule(turn: wet,
                               slice: TurnSlice.make(samples: arc, turn: wet,
                                                     windDirDeg: nil)) == .wristUnder)
    }

    /// The voice: plain, numbered from the engine, and never louder than the fact.
    @Test func everySentenceIsCalmAndCarriesItsNumbers() throws {
        let arc = quarterCircle()
        var seen: Set<TurnCoach.Rule> = []
        let cases: [TurnRecord] = [
            try turn(outcome: "fell_in"),
            try turn(outcome: "touchdown", submerged: true),
            try turn(outcome: "touchdown", offFoilS: 4, pumped: true),
            try turn(outcome: "touchdown", pumped: true),
            try turn(outcome: "touchdown"),
            try turn(score: 0.9, success: true),
            try turn(score: 0.6),
            try turn(score: 0.75),
        ]
        for record in cases {
            let cut = TurnSlice.make(samples: arc, turn: record, windDirDeg: nil)
            let line = TurnCoach.line(turn: record, slice: cut)
            seen.insert(TurnCoach.rule(turn: record, slice: cut))
            #expect(!line.isEmpty)
            #expect(!line.contains("!"), "the coach never shouts: \(line)")
            #expect(!line.lowercased().contains("should"), "and never blames: \(line)")
            #expect(line.hasSuffix("."))
        }
        #expect(seen.count >= 7)

        // A jibe passes through dead downwind and a tack through head-to-wind; a sweep the
        // wind axis could not name passes through neither, and gets the plain words.
        #expect(TurnCoach.midPointWord("jibe") == "downwind point")
        #expect(TurnCoach.midPointWord("tack") == "head-to-wind")
        #expect(TurnCoach.midPointWord("turn") == "middle of the turn")

        // The pump line has two forms, and the one without a duration is the one for a foil
        // that came straight back up.
        let instant = try turn(outcome: "touchdown", offFoilS: 0, pumped: true)
        let cut = TurnSlice.make(samples: arc, turn: instant, windDirDeg: nil)
        #expect(TurnCoach.line(turn: instant, slice: cut).contains("straight away"))

        // Nothing invents a format: the score prints the way the turn list prints it.
        let quick = try turn(score: 0.9123, success: true)
        let quickCut = TurnSlice.make(samples: arc, turn: quick, windDirDeg: nil)
        #expect(TurnCoach.line(turn: quick, slice: quickCut).contains("91 %"))
    }
}
