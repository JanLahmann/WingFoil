import Foundation
import Testing
@testable import WingFoilKit

/// The turn sheet's two new readings: the speed ramp the breadcrumb is coloured on, and the
/// number of pumps the "pumped out" chip carries.
///
/// Both are pure arithmetic over the engine's own numbers, and both are the kind of thing
/// that is invisible in a screenshot when it is wrong: a line drawn one stop cold looks like
/// a slower turn, and a stroke count taken from the wrong episode looks like a fact.
@Suite struct TurnSpeedRampTests {

    // MARK: - The ramp

    /// The three anchors that define it: nothing at 0, the middle stop at the entry speed,
    /// the hot end at the cap.
    @Test func theRampIsAnchoredOnTheTurnsOwnEntrySpeed() {
        #expect(TurnSpeedRamp.position(kn: 0, entryKn: 12) == 0)
        #expect(TurnSpeedRamp.position(kn: 12, entryKn: 12) == 0.5)
        #expect(abs(TurnSpeedRamp.position(kn: 6, entryKn: 12) - 0.25) < 1e-9)
        // The cap: 1.3x the entry speed is the hot end, and anything past it stays there
        // rather than running off the end of a palette that has no more colours.
        #expect(TurnSpeedRamp.position(kn: 12 * 1.3, entryKn: 12) == 1)
        #expect(TurnSpeedRamp.position(kn: 40, entryKn: 12) == 1)
        #expect(abs(TurnSpeedRamp.position(kn: 12 * 1.15, entryKn: 12) - 0.75) < 1e-9)
    }

    /// Faster is never colder. The property matters more than any single value: the whole
    /// claim the drawing makes is "this stretch was quicker than that one".
    @Test func theRampNeverGoesBackwards() {
        var previous = -1.0
        for tenths in stride(from: 0.0, through: 200, by: 1) {
            let position = TurnSpeedRamp.position(kn: tenths / 10, entryKn: 12)
            #expect(position >= previous)
            #expect(position >= 0 && position <= 1)
            previous = position
        }
    }

    /// A turn with no reference speed reads cold rather than dividing by a rounding error.
    @Test func aTurnWithNoEntrySpeedHasNoRamp() {
        #expect(TurnSpeedRamp.position(kn: 5, entryKn: 0) == 0)
        #expect(TurnSpeedRamp.position(kn: 5, entryKn: 0.1) == 0)
        // And a standstill is the cold end at any reference speed.
        #expect(TurnSpeedRamp.position(kn: 0, entryKn: 20) == 0)
    }

    /// Which two stops a position falls between — the arithmetic a renderer mixes on, and
    /// the one place an off-by-one would draw a whole stop cold.
    @Test func everyPositionLandsBetweenTwoStops() {
        let stops = DesignTokens.Speed.ramp.count
        #expect(stops == 5)
        #expect(DesignTokens.Speed.rampRGB.count == stops)

        let cold = TurnSpeedRamp.stop(at: 0)
        #expect(cold.lower == 0 && cold.upper == 1 && cold.blend == 0)
        // The entry anchor is a stop exactly, not a mix of the two either side of it.
        let anchor = TurnSpeedRamp.stop(at: 0.5)
        #expect(anchor.lower == 2 && anchor.blend == 0)
        // The hot end is the last pair fully blended, never a sixth stop that is not there.
        let hot = TurnSpeedRamp.stop(at: 1)
        #expect(hot.lower == stops - 2 && hot.upper == stops - 1 && hot.blend == 1)
        // Out of range is clamped rather than trapped.
        #expect(TurnSpeedRamp.stop(at: 4).upper == stops - 1)
        #expect(TurnSpeedRamp.stop(at: -2).lower == 0)
        let quarter = TurnSpeedRamp.stop(at: 0.375)
        #expect(quarter.lower == 1 && abs(quarter.blend - 0.5) < 1e-9)
    }

    /// The middle stop is the flying teal, on purpose: "he held the speed he came in with"
    /// is drawn in the ink the app already means flying with.
    @Test func theEntryStopIsTheFlyingTeal() {
        #expect(DesignTokens.Hex.speedEntry == DesignTokens.Hex.phaseFlying)
        // And the ramp is clear of the verdict inks and of the clean-jibe mint, which are
        // drawn on the same picture.
        let ramp = [DesignTokens.Hex.speedStopped, DesignTokens.Hex.speedSlow,
                    DesignTokens.Hex.speedEntry, DesignTokens.Hex.speedFast,
                    DesignTokens.Hex.speedFastest]
        let taken = [DesignTokens.Hex.outcomeFlew, DesignTokens.Hex.outcomeTouchdown,
                     DesignTokens.Hex.outcomeFellIn, DesignTokens.Hex.outcomeCourseChange,
                     DesignTokens.Hex.cleanJibe]
        #expect(Set(ramp).intersection(taken).isEmpty)
        #expect(Set(ramp).count == ramp.count)
    }

    /// The legend's bar ends where the rider actually got to — never past the ramp, and
    /// never below the anchor it has to be able to mark.
    @Test func theLegendTopIsTheFastestHeActuallyWent() {
        // He accelerated through it: the bar ends at his maximum.
        #expect(TurnSpeedRamp.legendTopKn(entryKn: 12, maxKn: 13.2) == 13.2)
        // He went a great deal faster than the ramp can colour: the bar ends at the cap.
        #expect(abs(TurnSpeedRamp.legendTopKn(entryKn: 12, maxKn: 40) - 15.6) < 1e-9)
        // He never beat his entry speed: the bar ends there, and the top half of the ramp
        // is honestly unused rather than labelled with a speed nobody rode.
        #expect(TurnSpeedRamp.legendTopKn(entryKn: 12, maxKn: 9) == 12)
    }

    // MARK: - How many pumps

    private func episode(strokes: Int, turnIndex: Int?, startTs: Double = 100,
                         endTs: Double = 104,
                         outcome: PumpEpisodeOutcome = .recovery) -> PumpEpisodeRecord {
        PumpEpisodeRecord(PumpEpisode(startT: startTs, endT: endTs, strokes: strokes,
                                      outcome: outcome, bursts: 1, flightIndex: nil,
                                      turnIndex: turnIndex, lookaheadS: 12))
    }

    /// A turn built through the golden schema, the same trick `TurnSliceTests` uses.
    private func turn(ts: Double = 100, endTs: Double = 106,
                      outcomeWindowS: Double = 11) throws -> TurnRecord {
        let json: [String: Any] = [
            "ts": ts, "endTs": endTs, "minTs": ts + 3, "type": "jibe", "counted": true,
            "entryKn": 12, "minKn": 6, "exitKn": 10, "score": 0.5, "success": false,
            "clean": false, "side": "port", "direction": "starboard", "netDeg": 90,
            "arcM": 31.4, "radiusM": 20, "outcome": "touchdown", "borderline": false,
            "offFoilS": 4, "stoppedS": 0, "pumped": true, "submerged": false,
            "outcomeWindowS": outcomeWindowS,
        ]
        return try JSONDecoder().decode(TurnRecord.self,
                                        from: JSONSerialization.data(withJSONObject: json))
    }

    /// The episodes the engine assigned to *this* turn, summed — a rider who pumps, sinks
    /// and pumps again pumped twice out of one jibe.
    @Test func theStrokesAreTheEpisodesThisTurnOwns() {
        let episodes = [
            episode(strokes: 4, turnIndex: 3),
            episode(strokes: 3, turnIndex: 3, startTs: 108, endTs: 111),
            episode(strokes: 9, turnIndex: 4, startTs: 200, endTs: 210),
            episode(strokes: 6, turnIndex: nil, startTs: 300, endTs: 306, outcome: .success),
        ]
        #expect(TurnAnalytics.pumpStrokes(for: 3, in: episodes) == 7)
        #expect(TurnAnalytics.pumpStrokes(for: 4, in: episodes) == 9)
        // A turn no episode names has no count — and nil is not 0, which would be a claim.
        #expect(TurnAnalytics.pumpStrokes(for: 5, in: episodes) == nil)
        #expect(TurnAnalytics.pumpStrokes(for: 0, in: []) == nil)
        // An episode the classifier counted no strokes in says nothing either.
        #expect(TurnAnalytics.pumpStrokes(for: 1, in: [episode(strokes: 0, turnIndex: 1)])
                == nil)
    }

    /// The fallback: an analysis that carries `pumped` but no assignment still answers, from
    /// the episodes overlapping the window the outcome was judged on.
    @Test func anUnassignedEpisodeIsFoundByItsWindow() throws {
        let record = try turn()  // 100 … 106, judged out to 117
        let inside = episode(strokes: 5, turnIndex: nil, startTs: 108, endTs: 112,
                             outcome: .failed)
        let after = episode(strokes: 9, turnIndex: nil, startTs: 400, endTs: 410,
                            outcome: .failed)
        #expect(TurnAnalytics.pumpStrokes(for: 2, turn: record,
                                          in: [inside, after]) == 5)
        // An episode that only *touches* the window counts; one wholly outside it does not.
        #expect(TurnAnalytics.pumpStrokes(for: 2, turn: record, in: [after]) == nil)

        // The assignment wins where there is one: the overlapping episode is not added to it.
        let assigned = episode(strokes: 2, turnIndex: 2, startTs: 101, endTs: 103)
        #expect(TurnAnalytics.pumpStrokes(for: 2, turn: record,
                                          in: [assigned, inside]) == 2)
    }

    /// One stroke is a stroke. The chip and the coach line print the same words.
    @Test func theStrokeCountIsSpelledOnceForBothSurfaces() {
        #expect(TurnAnalytics.strokesText(1) == "1 stroke")
        #expect(TurnAnalytics.strokesText(7) == "7 strokes")
        #expect(TurnAnalytics.strokesText(0) == "0 strokes")
    }

    /// The coach's pump rung carries the count when there is one, and says exactly what it
    /// used to say when there is not.
    @Test func theCoachCountsThePumpsWhenItKnows() throws {
        let record = try turn()
        let cut = TurnSlice.make(samples: [], turn: record, windDirDeg: nil)
        let counted = TurnCoach.line(turn: record, slice: cut, pumpStrokes: 7)
        #expect(TurnCoach.rule(turn: record, slice: cut) == .pumpedOut)
        #expect(counted.contains("7 strokes"))
        #expect(counted.contains("4 s off the foil"))
        #expect(counted.hasSuffix("."))
        #expect(!counted.contains("!"))

        let uncounted = TurnCoach.line(turn: record, slice: cut)
        #expect(!uncounted.contains("stroke"))
        #expect(uncounted.contains("4 s off the foil"))
    }
}
