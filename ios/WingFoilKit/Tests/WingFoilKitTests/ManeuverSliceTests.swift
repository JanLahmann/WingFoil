import Foundation
import Testing
@testable import WingFoilKit

/// The parts of a maneuver page that are geometry rather than layout: the drawn window's two
/// pads, the tap's nearest-sample pick, the angle series' unwrap and TWA convention, the
/// barometer's reference, and the flight-end slice.
///
/// Synthetic, for the reason `TurnSliceTests` is: a quarter circle of known radius is the only
/// fixture that can tell a correct rotation from a plausible one, and a TWA series drawn with
/// its sign flipped looks entirely normal on a corpus session.
@Suite struct ManeuverSliceTests {

    // MARK: - Fixtures

    private static let lat0 = 45.87
    private static let lon0 = 10.87

    private func sample(t: Double, x: Double, y: Double, kn: Double,
                        altM: Double? = nil) -> TurnSlice.Sample {
        let cosLat = cos(Self.lat0 * .pi / 180)
        return TurnSlice.Sample(t: t,
                                lat: Self.lat0 + y / 110_540,
                                lon: Self.lon0 + x / (cosLat * 111_320),
                                kn: kn, altM: altM)
    }

    /// The same quarter circle `TurnSliceTests` uses — entered heading north at t = 100, left
    /// heading east at t = 106 — but with a **long** run-out, so a widened window has samples
    /// to draw rather than silently running out of them.
    private func quarterCircle(runOutS: Double = 70, altAt: ((Double) -> Double?)? = nil)
    -> [TurnSlice.Sample] {
        let radius = 20.0
        func kn(_ rt: Double) -> Double {
            rt < 0 ? 12 : (rt <= 3 ? 12 - 2 * rt : min(6 + 4 * ((rt - 3) / 3), 12))
        }
        var out: [TurnSlice.Sample] = []
        for step in stride(from: -25.0, to: 0, by: 1) {
            out.append(sample(t: 100 + step, x: 0, y: step * 5, kn: kn(step),
                              altM: altAt?(100 + step)))
        }
        for step in stride(from: 0.0, through: 6, by: 1) {
            let phi = step * 15 * .pi / 180
            out.append(sample(t: 100 + step,
                              x: radius - radius * cos(phi), y: radius * sin(phi),
                              kn: kn(step), altM: altAt?(100 + step)))
        }
        for step in stride(from: 7.0, through: 6 + runOutS, by: 1) {
            out.append(sample(t: 100 + step, x: radius + (step - 6) * 5, y: radius,
                              kn: kn(min(step, 6)), altM: altAt?(100 + step)))
        }
        return out
    }

    private func turn(ts: Double = 100, endTs: Double = 106, minTs: Double = 103,
                      axisTs: Double? = nil) throws -> TurnRecord {
        let json: [String: Any] = [
            "ts": ts, "endTs": endTs, "minTs": minTs, "type": "jibe", "counted": true,
            "entryKn": 12.0, "minKn": 6.0, "exitKn": 10.0, "score": 0.83, "success": true,
            "clean": false, "side": "port", "direction": "starboard", "netDeg": 90.0,
            "arcM": 31.4, "radiusM": 20.0, "outcome": "flew_through", "borderline": false,
            "offFoilS": 0.0, "stoppedS": 0.0, "pumped": false, "submerged": false,
            "outcomeWindowS": 11.0,
        ].merging(axisTs.map { ["axisTs": $0, "axisBeforeDeg": 87.0, "axisAfterDeg": 72.0] }
                    ?? [:]) { _, new in new }
        return try JSONDecoder().decode(TurnRecord.self,
                                        from: JSONSerialization.data(withJSONObject: json))
    }

    private func flightEnd(ts: Double = 106, outcome: String = "fell_in",
                           stoppedS: Double = 7, offFoilS: Double = 22,
                           minKn: Double? = 0.9, pumped: Bool = false,
                           submerged: Bool = false, borderline: Bool = false,
                           truncated: Bool = false,
                           ownedByTurn: Int? = nil) throws -> FlightEndRecord {
        let json: [String: Any] = [
            "flightIndex": 4, "ts": ts, "outcome": outcome, "borderline": borderline,
            "offFoilS": offFoilS, "stoppedS": stoppedS,
            "minKn": minKn as Any, "pumped": pumped, "submerged": submerged,
            "windowS": 12.0, "truncated": truncated,
            "ownedByTurn": ownedByTurn as Any,
        ]
        return try JSONDecoder().decode(FlightEndRecord.self,
                                        from: JSONSerialization.data(withJSONObject: json))
    }

    // MARK: - The two pads

    /// The lead-in and the run-out are separate numbers, and the drawn window is exactly
    /// `[−before, duration + after]`. They were one constant, and one constant could not hold
    /// the quiet tail without also pushing the sweep off-centre.
    @Test func theWindowIsCutWithItsOwnLeadInAndRunOut() throws {
        let cut = TurnSlice.make(samples: quarterCircle(), turn: try turn(),
                                 windDirDeg: nil, padBeforeS: 5, padAfterS: 40)
        #expect(cut.padBeforeS == 5)
        #expect(cut.padAfterS == 40)
        #expect(abs(cut.timeDomain.lowerBound - -5) < 0.001)
        #expect(abs(cut.timeDomain.upperBound - 46) < 0.001)
        // And the samples really were cut to it, not merely labelled.
        let first = try #require(cut.points.first)
        let last = try #require(cut.points.last)
        #expect(first.rt >= -5)
        #expect(last.rt <= 46)
        #expect(last.rt > 39)
    }

    /// The defaults are what they always were, so every caller that does not care is drawn
    /// exactly as it was before the pads were split.
    @Test func theDefaultsAreTheOldSingleConstant() throws {
        let cut = TurnSlice.make(samples: quarterCircle(), turn: try turn(), windDirDeg: nil)
        #expect(cut.padBeforeS == TurnSlice.defaultPadS)
        #expect(cut.padAfterS == TurnSlice.defaultPadS)
        #expect(abs(cut.timeDomain.lowerBound - -8) < 0.001)
        #expect(abs(cut.timeDomain.upperBound - 14) < 0.001)
    }

    /// **The quiet tail fits once the run-out is wide enough**, which is the whole reason the
    /// control exists: at the default 8 s the strip's `quiet` rule lands past the right edge
    /// and is never drawn, and the footnote is the only place the number appears.
    @Test func aWiderRunOutReachesTheQuietTail() throws {
        let quietS = TurnConfig().cleanQuietS ?? 10
        let narrow = TurnSlice.make(samples: quarterCircle(), turn: try turn(),
                                    windDirDeg: nil)
        let wide = TurnSlice.make(samples: quarterCircle(), turn: try turn(),
                                  windDirDeg: nil, padBeforeS: 8, padAfterS: 20)
        let quietRt = wide.speed.exitRt + quietS
        #expect(quietRt > narrow.timeDomain.upperBound)
        #expect(quietRt <= wide.timeDomain.upperBound)
    }

    // MARK: - The tap

    /// A tap picks the nearest **vertex** in metres — not the nearest point on the polyline,
    /// which would put a real-looking time on a reading nobody took.
    @Test func theTapPicksTheNearestSampleInMetres() throws {
        let figure = TurnSlice.make(samples: quarterCircle(), turn: try turn(),
                                    windDirDeg: nil).figure
        // Six seconds in the rider is 20 m east and 20 m north of the entry, and the next
        // sample is five metres further east. A finger two metres off the first lands on it
        // and not on its neighbour.
        let hit = try #require(figure.point(nearX: 21, y: 22, windUp: false, withinM: 8))
        #expect(abs(hit.rt - 6) < 0.001)

        // Ten metres from every vertex, inside a two-metre tolerance: nothing. A tap on open
        // water dismisses rather than snapping to the far end of the track.
        #expect(figure.point(nearX: 200, y: 200, windUp: false, withinM: 2) == nil)
        // Without a tolerance it always finds something — the drawing's own nearest vertex.
        #expect(figure.point(nearX: 200, y: 200, windUp: false) != nil)
    }

    /// The rotated frame is a different frame: a tap in wind-up coordinates must be answered
    /// against wind-up points, or it picks whichever vertex the rotation happened to leave
    /// under the finger.
    @Test func theTapIsAnsweredInTheFrameItWasMadeIn() throws {
        let cut = TurnSlice.make(samples: quarterCircle(), turn: try turn(), windDirDeg: 90)
        let north = try #require(cut.figure.point(atRelative: 6, windUp: false))
        let up = try #require(cut.figure.point(atRelative: 6, windUp: true))
        // Same instant, different coordinates. The rotation is the one that takes the
        // wind's own "from" direction to straight up the frame, so with the wind from the
        // east (20 m east, 20 m north) becomes 20 m *left* and 20 m up.
        #expect(abs(up.x - -20) < 0.05)
        #expect(abs(up.y - 20) < 0.05)
        let hit = try #require(cut.figure.point(nearX: up.x, y: up.y, windUp: true, withinM: 2))
        #expect(abs(hit.rt - 6) < 0.001)
        #expect(abs(north.y - 20) < 0.05)
    }

    /// The path labels are every five seconds of the event's own clock, negative side
    /// included, and never a zero — the origin already has three marks on it.
    @Test func thePathLabelsAreEveryFiveSecondsAndSkipZero() throws {
        let figure = TurnSlice.make(samples: quarterCircle(), turn: try turn(),
                                    windDirDeg: nil, padBeforeS: 8, padAfterS: 12).figure
        let labels = figure.pathLabels(everyS: 5, windUp: false).map(\.rt)
        #expect(labels.contains(-5))
        #expect(labels.contains(5))
        #expect(labels.contains(15))
        #expect(!labels.contains(0))
        #expect(labels == labels.sorted())
    }

    // MARK: - Angles

    /// **The unwrap**: a sweep that runs through north comes out as a straight climb, not as a
    /// 350° cliff and a 10° recovery.
    @Test func theHeadingSeriesIsUnwrappedAcrossTheSweep() {
        // Bearings 340, 350, 0, 10, 20 — two of them either side of the wrap.
        let points = [340.0, 350, 0, 10, 20].enumerated().map { index, deg in
            TurnSlice.Point(x: 0, y: 0, rt: Double(index), kn: 10,
                            headingDeg: deg, inTurn: true)
        }
        let angles = SliceAngles.make(points: points, windDirDeg: nil)
        #expect(!angles.isTwa)
        let drawn = angles.points.map(\.deg)
        #expect(drawn == [340, 350, 360, 370, 380])
        // Every step is +10°/s, and nothing anywhere near −340.
        let rates = angles.points.compactMap(\.rateDegS)
        #expect(rates.allSatisfy { abs($0 - 10) < 0.001 })
        #expect(abs(angles.peakRateDegS - 10) < 0.001)
    }

    /// **The TWA convention**: 0 is pointing straight at the wind it comes from, ±180 is dead
    /// downwind, and the sign says which side of the axis the board is on.
    @Test func theWindAngleIsZeroHeadToWindAndOneEightyDownwind() {
        let wind = 0.0                      // the wind blows *from* the north
        func twa(_ heading: Double) -> Double {
            let points = [TurnSlice.Point(x: 0, y: 0, rt: 0, kn: 10,
                                          headingDeg: heading, inTurn: true),
                          TurnSlice.Point(x: 0, y: 0, rt: 1, kn: 10,
                                          headingDeg: heading, inTurn: true)]
            return SliceAngles.make(points: points, windDirDeg: wind).points[0].deg
        }
        #expect(abs(twa(0)) < 0.001)        // sailing north, into the wind
        #expect(abs(twa(180) - 180) < 0.001 || abs(twa(180) + 180) < 0.001)
        #expect(abs(twa(90) - 90) < 0.001)  // on starboard beam reach
        #expect(abs(twa(270) + 90) < 0.001) // the mirror of it
    }

    /// A jibe drawn in TWA crosses ±180 and the unwrap carries it through, so the strip's
    /// downwind rule sits on the line rather than beside a cliff.
    @Test func aJibeCrossesTheDownwindAxisWithoutAJump() throws {
        // Wind from the north; the rider swings from 160° through 180° to 200° of TWA.
        let headings = [160.0, 170, 180, 190, 200]
        let points = headings.enumerated().map { index, deg in
            TurnSlice.Point(x: 0, y: 0, rt: Double(index), kn: 10,
                            headingDeg: deg, inTurn: true)
        }
        let angles = SliceAngles.make(points: points, windDirDeg: 0)
        #expect(angles.isTwa)
        let drawn = angles.points.map(\.deg)
        // 160, 170, ±180, and then *past* it rather than back down the other side.
        #expect(drawn[0] == 160)
        for index in 1..<drawn.count { #expect(abs(drawn[index] - drawn[index - 1]) < 15) }
        #expect(abs(drawn.last! - 200) < 0.001)
        let crossing = try #require(angles.axisCrossingDeg)
        #expect(abs(abs(crossing) - 180) < 0.001)
    }

    /// A heading series has no axis to cross: a compass 0 is north, and a rule there would
    /// invent a fact about a session with no usable wind.
    @Test func aHeadingSeriesHasNoAxisRule() {
        let points = (0..<4).map {
            TurnSlice.Point(x: 0, y: 0, rt: Double($0), kn: 10,
                            headingDeg: 350 + Double($0) * 5, inTurn: true)
        }
        #expect(SliceAngles.make(points: points, windDirDeg: nil).axisCrossingDeg == nil)
    }

    // MARK: - Barometer

    /// The reference is the engine's own — the same median the mask is measured against — so
    /// the threshold rule lands exactly where a sample crosses from dry to submerged.
    @Test func theBaroReferenceIsTheEnginesOwnSessionMedian() throws {
        let alt: [Double?] = [10, 10, 10, -30, 10, nil, 10]
        let reference = try #require(BaroReference.session(alt))
        #expect(reference == 10)
        // And it agrees with the mask that produced every stored `submerged` flag.
        let mask = Evidence.submergedMask(alt, dropM: 25)
        #expect(mask == [false, false, false, true, false, false, false])
    }

    /// Everything is drawn relative to that reference, which puts the wrist-under line at a
    /// fixed −`dropM` whatever the afternoon's pressure was doing.
    @Test func theBaroSeriesIsRelativeAndTheThresholdIsFixed() {
        let points = [10.0, 10, -30, 10].enumerated().map { index, alt in
            TurnSlice.Point(x: 0, y: 0, rt: Double(index), kn: 10, inTurn: true, altM: alt)
        }
        let baro = SliceBaro.make(points: points, referenceM: 10, dropM: 25,
                                  submersions: [2.0...2.0])
        #expect(baro.hasBarometer)
        #expect(baro.thresholdM == -25)
        #expect(baro.points.map(\.m) == [0, 0, -40, 0])
        #expect(baro.points.map(\.submerged) == [false, false, true, false])
        #expect(baro.submergedSpans.count == 1)
        // The threshold stays on screen even on a window that never went near it.
        let dry = SliceBaro.make(points: points.map {
            var copy = $0; copy.altM = 10; return copy
        }, referenceM: 10, dropM: 25)
        #expect(dry.metreDomain.lowerBound <= -25)
    }

    /// No barometer is not the same fact as a dry wrist, and the strip has to be able to tell
    /// them apart: a source with no altitude channel gets no points at all.
    @Test func aSourceWithNoBarometerDrawsNothing() {
        let points = (0..<4).map {
            TurnSlice.Point(x: 0, y: 0, rt: Double($0), kn: 10, inTurn: true)
        }
        #expect(!SliceBaro.make(points: points, referenceM: nil, dropM: 25).hasBarometer)
        #expect(!SliceBaro.make(points: points, referenceM: 10, dropM: 25).hasBarometer)
        #expect(BaroReference.session([nil, nil]) == nil)
    }

    // MARK: - The flight-end slice

    /// The end is the origin — of the projection *and* of the clock — and the flight is the
    /// part before it: everything after is already off the foil.
    @Test func theFlightEndIsTheOriginAndTheFlightIsWhatCameBefore() throws {
        let cut = FlightEndSlice.make(samples: quarterCircle(), end: try flightEnd(ts: 106),
                                      windDirDeg: nil)
        let zero = try #require(cut.points.first { abs($0.rt) < 0.001 })
        #expect(abs(zero.x) < 0.01)
        #expect(abs(zero.y) < 0.01)
        #expect(cut.points.filter { $0.rt < 0 }.allSatisfy { $0.inTurn })
        #expect(cut.points.filter { $0.rt > 0 }.allSatisfy { !$0.inTurn })
        // A flight end is an instant, not a sweep — and it crosses no wind axis.
        #expect(cut.figure.durationS == 0)
        #expect(cut.figure.axisRt == nil)
        #expect(cut.figure.endRt == 0)
        #expect(cut.figure.outcome == "fell_in")
    }

    /// Only `low` is the engine's. `in` is the fastest sample of the entry window and `out` is
    /// where the drawn line came back to the flying-again threshold — both read off this
    /// window, because a flight end record carries no entry or exit speed at all.
    @Test func onlyTheLowSpeedComesFromTheRecord() throws {
        let cut = FlightEndSlice.make(samples: quarterCircle(), end: try flightEnd(ts: 106),
                                      windDirDeg: nil, padBeforeS: 8, padAfterS: 40)
        #expect(cut.speed.lowKn == 0.9)
        #expect(cut.speed.entryRt <= 0)
        #expect(cut.speed.entryKn > 0)
        // The fixture comes back to 12 kn after the turn, so it does recover — and the mark
        // sits after the end, never before it.
        let recoverRt = try #require(cut.speed.recoverRt)
        #expect(recoverRt > 0)
        #expect(cut.speed.outKn != nil)
    }

    /// A record with no `minKn` — the off-foil run was never entered — gets no low mark at
    /// all rather than a zero, which would read as a measurement.
    @Test func aFlightEndWithNoMinimumHasNoLowMark() throws {
        let cut = FlightEndSlice.make(samples: quarterCircle(),
                                      end: try flightEnd(outcome: "glide_out", stoppedS: 0,
                                                         offFoilS: 3, minKn: nil),
                                      windDirDeg: nil)
        #expect(cut.speed.lowKn == nil)
        #expect(cut.speed.lowRt == nil)
        #expect(cut.figure.lowRt == nil)
    }

    /// The two pads work here for the same reason and in the same units.
    @Test func theFlightEndWindowTakesTheSamePads() throws {
        let cut = FlightEndSlice.make(samples: quarterCircle(), end: try flightEnd(),
                                      windDirDeg: nil, padBeforeS: 6, padAfterS: 45)
        #expect(abs(cut.timeDomain.lowerBound - -6) < 0.001)
        #expect(abs(cut.timeDomain.upperBound - 45) < 0.001)
    }

    /// A window with no positioned samples at all still carries its numbers — the page is
    /// mostly numbers — and simply draws no map.
    @Test func aFlightEndWithNoFixesDegradesToNumbers() throws {
        let cut = FlightEndSlice.make(samples: [], end: try flightEnd(), windDirDeg: nil)
        #expect(!cut.hasGeometry)
        #expect(cut.figure.bounds == nil)
        #expect(cut.speed.lowKn == 0.9)
    }

    // MARK: - The words

    /// "fell in · stopped 7 s · wrist under" — outcome first, then the evidence that made it,
    /// in the order the ladder settles them.
    @Test func theOutcomeLineSaysOnlyWhatIsThere() throws {
        #expect(FlightEndAnalytics.outcomeText(try flightEnd())
                == "fell in · stopped 7 s")
        #expect(FlightEndAnalytics.outcomeText(try flightEnd(submerged: true))
                == "fell in · stopped 7 s · wrist under")
        // No stop worth printing: off-foil seconds instead, never both — a rider who stopped
        // was off the foil too, and saying both says one loss twice.
        #expect(FlightEndAnalytics.outcomeText(
            try flightEnd(outcome: "touchdown", stoppedS: 0, offFoilS: 4))
                == "touchdown · off the foil 4 s")
        // Under a second is one sample at 1 Hz, and "0 s" would read as a measurement.
        #expect(FlightEndAnalytics.outcomeText(
            try flightEnd(outcome: "glide_out", stoppedS: 0, offFoilS: 0, minKn: 4.2))
                == "glided out")
        #expect(FlightEndAnalytics.outcomeText(
            try flightEnd(outcome: "touchdown", stoppedS: 4, borderline: true))
                == "touchdown (borderline) · stopped 4 s")
        // A truncated end says the one true thing about itself instead of a verdict.
        #expect(FlightEndAnalytics.outcomeText(
            try flightEnd(outcome: "unknown", truncated: true))
                == "the recording ended, not the flight")
    }

    /// The word is never the turn ladder's "flew through": by the time there is a flight end
    /// the rider is off the foil by definition.
    @Test func aFlightEndNeverFlewThrough() {
        #expect(FlightEndAnalytics.outcomeLabel("glide_out") == "glided out")
        #expect(FlightEndAnalytics.outcomeLabel("touchdown") == "touchdown")
        #expect(FlightEndAnalytics.outcomeLabel("fell_in") == "fell in")
        #expect(FlightEndAnalytics.outcomeLabel("something_else") == "unknown")
    }

    /// The swipeable set is the drawn ends and only those: a turn-owned end is the same swim
    /// already counted at its jibe, and a truncated one has no evidence to judge. It is the
    /// *same* list `PresentationRules.drawnFlightEnds` returns, carried by index so the map's
    /// callout and the Log tab's row open the same record — checked on the corpus session
    /// that has all three kinds in it.
    @Test func theSetIsTheDrawnEndsByIndex() throws {
        let url = testFixturesDir.appendingPathComponent(
            "goldens/2026-08-29-1440_nago-torbole-windsurfen_ciq.expected.json")
        let analysis = try JSONDecoder().decode(SessionAnalysis.self,
                                                from: Data(contentsOf: url))
        let indices = FlightEndAnalytics.drawnIndices(analysis)
        #expect(!indices.isEmpty)
        #expect(indices.count < analysis.flightEnds.count)
        #expect(indices.map { analysis.flightEnds[$0] }
                == PresentationRules.drawnFlightEnds(analysis))
        #expect(indices.allSatisfy {
            analysis.flightEnds[$0].ownedByTurn == nil && !analysis.flightEnds[$0].truncated
        })
        #expect(indices == indices.sorted())
    }
}
