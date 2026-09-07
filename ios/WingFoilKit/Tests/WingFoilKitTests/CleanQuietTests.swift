import Foundation
import Testing
@testable import WingFoilKit

/// **The clean jibe's quiet tail** (engine 0.17.0, docs/algorithms.md "The quiet tail").
///
/// Jan, 7 Sep 2026: *"an additional requirement for a clean jibe: no touch down or fall
/// within 10 s afterwards. This only applies to clean jibe, not to carried through."*
///
/// Every case here is built on the same shape, because that shape is the whole point: a jibe
/// powered straight out of closes its outcome window at recovery, two or three seconds after
/// the sweep, so a loss at +7 s is *outside* the verdict and the ladder is right to keep
/// calling the turn a fly-through. What moves is `clean`, and only `clean`.
///
/// The lab's twin is `lab/tests/test_turns.py`, "the clean jibe's quiet tail"; corpus-wide
/// agreement between the two is asserted by `GoldenTests` over every fixture.
@Suite struct CleanQuietTests {

    private let wind = WindEstimate(userDirDeg: 0)

    /// A `CleanTrack` sailed along the given per-second course at the given speeds, with the
    /// local-metre frame integrated from both (the Swift twin of the lab's `_track`).
    private func track(course: [Double], speed: [Double],
                       altM: [Double?]? = nil, gapAt: Int? = nil) -> CleanTrack {
        var out = CleanTrack()
        var x = 0.0, y = 0.0, dist = 0.0
        var t = 0.0
        for (i, deg) in course.enumerated() {
            let v = speed[i]
            let gap = gapAt == i
            if gap { t += 30 }                        // the recording stopped for half a minute
            out.samples.append(CleanSample(t: t, dt: i == 0 ? 0 : (gap ? 30 : 1),
                                           gapBefore: gap, x: x, y: y, dopplerMps: v,
                                           positionalMps: v, cumDistM: dist,
                                           altM: altM?[i] ?? nil))
            x += sin(deg * .pi / 180) * v
            y += cos(deg * .pi / 180) * v
            dist += v
            t += 1
        }
        if let gapAt {
            out.segments = [0..<gapAt, gapAt..<out.samples.count]
        } else {
            out.segments = [0..<out.samples.count]
        }
        out.medianDtS = 1
        out.gapThresholdS = 3
        out.spanS = out.samples.last.map { $0.t - (out.samples.first?.t ?? 0) } ?? 0
        out.timerTimeS = Double(course.count - 1)
        return out
    }

    /// A jibe powered straight out of, `quiet` seconds of cruising, then `dip`.
    ///
    /// The cruising leg closes the outcome window, so the dip is past the verdict and inside
    /// the quiet tail — the shape the rule was written for.
    private func jibeThenLater(dip: [Double], quiet: Int = 6,
                               altM: [Double?]? = nil,
                               gapAt: Int? = nil) -> CleanTrack {
        var course: [Double] = Array(repeating: 90, count: 40)
        var speed: [Double] = Array(repeating: 6, count: 40)
        for k in 0..<7 {                              // 90° → 270° through dead downwind
            course.append(90 + 180 * Double(k) / 6)
            speed.append(6 - Double(k) / 6)
        }
        course += Array(repeating: 270, count: quiet)
        speed += Array(repeating: 6, count: quiet)
        course += Array(repeating: 270, count: dip.count)
        speed += dip
        course += Array(repeating: 270, count: 40)
        speed += Array(repeating: 6, count: 40)
        return track(course: course, speed: speed, altM: altM, gapAt: gapAt)
    }

    private func turns(_ track: CleanTrack, config: TurnConfig = TurnConfig(),
                       ends: [FlightEnd] = []) -> [Turn] {
        TurnDetector.detect(track, flights: FlightSegmenter.segment(track), wind: wind,
                            config: config, ends: ends)
    }

    // MARK: - The rule

    @Test func aTouchdownInsideTheQuietTailCostsTheJibeItsStar() throws {
        let turn = try #require(turns(jibeThenLater(dip: [0.5, 0.5, 0.5])).first)
        // The ladder is untouched: the loss is outside the window the outcome was read from.
        #expect(turn.outcome == .flewThrough)
        #expect(turn.success)
        #expect(!turn.clean)
        #expect(turn.cleanBlockedBy == .quietOffFoil)
    }

    @Test func theQuietTailIsOffAtZero() throws {
        var config = TurnConfig()
        config.cleanQuietS = 0
        let turn = try #require(turns(jibeThenLater(dip: [0.5, 0.5, 0.5]),
                                      config: config).first)
        #expect(turn.clean)
        #expect(turn.cleanBlockedBy == nil)
    }

    @Test func aLossPastTheQuietTailLeavesTheJibeClean() throws {
        let turn = try #require(turns(jibeThenLater(dip: [0.5, 0.5, 0.5], quiet: 20)).first)
        #expect(turn.clean)
    }

    /// Samples the far side of a hole are not evidence about what happened in it.
    @Test func aRecordingGapEndsTheQuietTail() throws {
        let turn = try #require(turns(jibeThenLater(dip: [0.5, 0.5, 0.5], gapAt: 50)).first)
        #expect(turn.outcome == .flewThrough)
        #expect(turn.clean)
    }

    /// The three flight-end verdicts the rule distinguishes, on one clean jibe.
    @Test func onlyALossOfTheFoilInTheTailBlocksIt() throws {
        let clean = jibeThenLater(dip: [], quiet: 40)

        func verdict(_ ends: FlightEnd...) throws -> (Bool, CleanBlock?) {
            let turn = try #require(turns(clean, ends: ends).first)
            return (turn.clean, turn.cleanBlockedBy)
        }
        func end(_ t: Double, _ outcome: TurnOutcome?, truncated: Bool = false) -> FlightEnd {
            var e = FlightEnd(flightIndex: 0, t: t, outcome: .glideOut)
            if let outcome {
                e.outcome = outcome == .fellIn ? .fellIn : .touchdown
            }
            e.truncated = truncated
            return e
        }

        let after = 52.0                              // a few seconds past the sweep
        #expect(try verdict() == (true, nil))
        #expect(try verdict(end(after, nil)) == (true, nil))          // a glide-out is no loss
        #expect(try verdict(end(after, .touchdown, truncated: true)) == (true, nil))
        #expect(try verdict(end(after, .touchdown)) == (false, .quietFlightEnd))
        #expect(try verdict(end(after, .fellIn)) == (false, .quietFlightEnd))
        #expect(try verdict(end(after + 30, .touchdown)) == (true, nil))   // past the tail
    }

    /// One submerged sample, too short to be an off-foil spell, and still a swim.
    @Test func aWristUnderInTheTailBlocksIt() throws {
        var alt = [Double?](repeating: 70, count: 128)
        alt[52] = -200                                // 30 cm of water, past the window
        let turn = try #require(turns(jibeThenLater(dip: [], quiet: 40, altM: alt)).first)
        #expect(turn.outcome == .flewThrough)
        #expect(!turn.submerged)
        #expect(turn.cleanBlockedBy == .quietSubmerged)
    }

    /// Every other number a rider reads is the same with the gate on and off.
    @Test func theQuietTailMovesCleanAndNothingElse() throws {
        let cut = jibeThenLater(dip: [0.5, 0.5, 0.5])
        var off = TurnConfig()
        off.cleanQuietS = 0
        let on = try #require(turns(cut).first)
        let plain = try #require(turns(cut, config: off).first)
        #expect(on.outcome == plain.outcome)
        #expect(on.success == plain.success)
        #expect(on.score == plain.score)
        #expect(on.offFoilS == plain.offFoilS)
        #expect(on.stoppedS == plain.stoppedS)
        #expect(on.outcomeWindowS == plain.outcomeWindowS)
        #expect(on.clean != plain.clean)

        let a = TurnDetector.summarize([on]), b = TurnDetector.summarize([plain])
        #expect(a.jibes == b.jibes)
        #expect(a.turnsSuccessful == b.turnsSuccessful)
        #expect((a.jibesSuccessful, b.jibesSuccessful) == (0, 1))
    }

    /// `cleanBlockedBy` is for the refusals nothing else on the page shows.
    @Test func aJibeTheOutcomeAlreadyFailedNeedsNoExplanation() throws {
        let turn = try #require(turns(jibeThenLater(dip: Array(repeating: 0.3, count: 11),
                                                    quiet: 1)).first)
        #expect(turn.outcome != .flewThrough)
        #expect(!turn.clean)
        #expect(turn.cleanBlockedBy == nil)
    }

    // MARK: - The words

    /// The chip beside the outcome — the wording, and where it refuses to guess.
    @Test func theChipSaysWhyInRiderWords() throws {
        func record(_ blocked: String?, axisAfter: Double? = nil) throws -> TurnRecord {
            var json: [String: Any] = [
                "ts": 100.0, "endTs": 106.0, "minTs": 103.0, "type": "jibe", "counted": true,
                "entryKn": 12.0, "minKn": 9.0, "exitKn": 11.0, "score": 0.75, "success": true,
                "clean": blocked == nil, "side": "port", "direction": "starboard",
                "netDeg": 170.0, "arcM": 31.4, "radiusM": 20.0, "outcome": "flew_through",
                "borderline": false, "offFoilS": 0.0, "stoppedS": 0.0, "pumped": false,
                "submerged": false, "outcomeWindowS": 3.0,
            ]
            if let blocked { json["cleanBlockedBy"] = blocked }
            if let axisAfter { json["axisAfterDeg"] = axisAfter }
            return try JSONDecoder().decode(
                TurnRecord.self, from: JSONSerialization.data(withJSONObject: json))
        }
        func end(_ t: Double, _ outcome: String) throws -> FlightEndRecord {
            try JSONDecoder().decode(FlightEndRecord.self, from: JSONSerialization.data(
                withJSONObject: ["flightIndex": 0, "ts": t, "outcome": outcome,
                                 "borderline": false, "offFoilS": 4.0, "stoppedS": 0.0,
                                 "pumped": false, "submerged": false, "windowS": 8.0,
                                 "truncated": false] as [String: Any]))
        }

        // A clean jibe explains nothing: it wears the star instead.
        #expect(TurnAnalytics.notCleanText(try record(nil)) == nil)

        let ends = [try end(112, "touchdown")]
        #expect(TurnAnalytics.notCleanText(try record("quiet_flight_end"), ends: ends,
                                           quietS: 10) == "not clean · touched down 6 s after")
        // No end to read the instant off ⇒ the plainer wording, never a fabricated number.
        #expect(TurnAnalytics.notCleanText(try record("quiet_flight_end"), quietS: 10)
                == "not clean · touched down after")
        #expect(TurnAnalytics.notCleanText(try record("quiet_off_foil"))
                == "not clean · off the foil after")
        #expect(TurnAnalytics.notCleanText(try record("quiet_submerged"))
                == "not clean · wrist under after")
        #expect(TurnAnalytics.notCleanText(try record("axis_after", axisAfter: 18.4))
                == "not clean · carried 18° past the axis")
        #expect(TurnAnalytics.notCleanText(try record("axis_after"))
                == "not clean · short of the axis")
    }
}
