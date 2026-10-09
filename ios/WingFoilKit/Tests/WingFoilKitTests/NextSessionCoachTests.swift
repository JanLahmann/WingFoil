import Foundation
import Testing
@testable import WingFoilKit

/// The Turns tab's *Next session* card (rider review I2, 9 Oct 2026): the commonest tip and
/// port against starboard. Synthetic turns, because the counting rule is the thing under
/// test and every turn page's own tip is already pinned in `TurnSliceTests`.
@Suite struct NextSessionCoachTests {

    // MARK: - Fixtures

    private static let lat0 = 45.87
    private static let lon0 = 10.87

    /// The same quarter circle `TurnSliceTests` rides: in at t = 100, the low point at the
    /// halfway mark, so a turn's own `minTs` decides whether the speed went early or late.
    private static let arc: [TurnSlice.Sample] = {
        let cosLat = cos(lat0 * .pi / 180)
        func sample(_ t: Double, _ x: Double, _ y: Double, _ kn: Double) -> TurnSlice.Sample {
            TurnSlice.Sample(t: t, lat: lat0 + y / 110_540,
                             lon: lon0 + x / (cosLat * 111_320), kn: kn)
        }
        var out: [TurnSlice.Sample] = []
        for step in stride(from: -8.0, to: 0, by: 1) { out.append(sample(100 + step, 0, step * 5, 12)) }
        for step in stride(from: 0.0, through: 6, by: 1) {
            let phi = step * 15 * .pi / 180
            let kn = step <= 3 ? 12 - 2 * step : 6 + 4 * (step - 3) / 3
            out.append(sample(100 + step, 20 - 20 * cos(phi), 20 * sin(phi), kn))
        }
        for step in stride(from: 7.0, through: 14, by: 1) {
            out.append(sample(100 + step, 20 + (step - 6) * 5, 20, 10))
        }
        return out
    }()

    private func turn(type: String = "jibe", counted: Bool = true, minTs: Double = 103,
                      score: Double = 0.5, success: Bool = false, side: String = "port",
                      outcome: String = "flew_through",
                      cleanBlockedBy: String? = nil) throws -> TurnRecord {
        var json: [String: Any] = [
            "ts": 100.0, "endTs": 106.0, "minTs": minTs, "type": type, "counted": counted,
            "entryKn": 12.0, "minKn": 6.0, "exitKn": 10.0, "score": score, "success": success,
            "clean": counted && type == "jibe" && success && outcome == "flew_through"
                && cleanBlockedBy == nil,
            "side": side, "direction": "starboard", "netDeg": 90.0, "arcM": 31.4,
            "radiusM": 20.0, "outcome": outcome, "borderline": false,
            "offFoilS": 0.0, "stoppedS": 0.0, "pumped": false,
            "submerged": false, "outcomeWindowS": 11.0,
        ]
        if let cleanBlockedBy { json["cleanBlockedBy"] = cleanBlockedBy }
        return try JSONDecoder().decode(TurnRecord.self,
                                        from: JSONSerialization.data(withJSONObject: json))
    }

    private func coach(_ turns: [TurnRecord], quietS: Double? = nil) -> NextSessionCoach {
        NextSessionCoach.make(turns: turns, samples: Self.arc, windDirDeg: nil, quietS: quietS)
    }

    private var clean: TurnRecord { get throws { try turn(score: 0.9, success: true) } }
    /// Lost on the way out: "power the wing up".
    private var lateLoss: TurnRecord { get throws { try turn(outcome: "touchdown") } }
    /// Lost coming in: "come in faster".
    private var earlyLoss: TurnRecord { get throws { try turn(minTs: 101, outcome: "touchdown") } }

    // MARK: - The tip

    /// The tip that came up on the most turns, with its count over the counted turns.
    @Test func theCommonestTipWinsAndSaysHowOften() throws {
        let card = coach([try lateLoss, try lateLoss, try earlyLoss, try clean, try clean])
        let tip = try #require(card.tip)
        #expect(tip.tip == .powerUpOnExit)
        #expect(tip.turns == 2)
        #expect(tip.ofTurns == 5)
        #expect(tip.text == TurnCoach.tipText(.powerUpOnExit, type: "jibe"))
        #expect(NextSessionCoach.countLine(tip) == "It came up on 2 of your 5 turns.")
    }

    /// A tie goes to the tip first in `Tip.allCases`: entry before exit.
    @Test func aTieGoesToTheEntryTip() throws {
        let tip = try #require(coach([try lateLoss, try earlyLoss]).tip)
        #expect(tip.tip == .comeInFaster)
        let flipped = try #require(coach([try earlyLoss, try lateLoss]).tip)
        #expect(flipped.tip == .comeInFaster)
    }

    /// The jibe's words only when every turn behind the tip was a jibe.
    @Test func theJibeWordingNeedsJibesOnly() throws {
        let jibes = try #require(coach([try earlyLoss]).tip)
        #expect(jibes.text == TurnCoach.tipLines["comeInFasterJibe"])
        let mixed = try #require(coach([try earlyLoss,
                                        try turn(type: "tack", minTs: 101,
                                                 outcome: "touchdown")]).tip)
        #expect(mixed.text == TurnCoach.tipLines["comeInFaster"])
    }

    /// The quiet-tail tip names the analysis' own hold, as the turn page does.
    @Test func theRideItOutTipCarriesTheHold() throws {
        let blocked = try turn(score: 0.92, success: true, cleanBlockedBy: "quiet_flight_end")
        let tip = try #require(coach([blocked], quietS: 10).tip)
        #expect(tip.tip == .rideItOut)
        #expect(tip.text.contains("10 s"))
        #expect(NextSessionCoach.countLine(tip) == "It came up on your one turn.")
    }

    /// Clean turns, course changes and turns without a tip give no tip line.
    @Test func noTipWithoutATurnThatGotOne() throws {
        #expect(coach([try clean, try clean]).tip == nil)
        let courseChange = try turn(counted: false, minTs: 101, outcome: "touchdown")
        #expect(coach([courseChange]).tip == nil)
        // A tack that flew through fast is not clean and has no tip either.
        #expect(coach([try turn(type: "tack", score: 0.9, success: true)]).tip == nil)
    }

    // MARK: - Port against starboard

    /// Jibes in the session: clean jibes per entry tack, and the weaker side named once both
    /// sides have three and the gap is twenty points.
    @Test func cleanJibesDecideTheWeakerSide() throws {
        let port = [try clean, try clean, try clean, try lateLoss]
        let starboard = [try turn(score: 0.9, success: true, side: "starboard"),
                         try turn(side: "starboard", outcome: "touchdown"),
                         try turn(side: "starboard", outcome: "touchdown")]
        let sides = try #require(coach(port + starboard).sides)
        #expect(sides.measure == .cleanJibes)
        #expect(sides.port == .init(side: "port", hits: 3, total: 4))
        #expect(sides.starboard == .init(side: "starboard", hits: 1, total: 3))
        #expect(sides.weaker == "starboard")
        #expect(NextSessionCoach.sideVerdict(sides) == "Work on your starboard entry next.")
        #expect(NextSessionCoach.sideTitle(sides.port) == "Port entry")
        #expect(NextSessionCoach.sideValue(sides.port, measure: sides.measure)
                == "3 of 4 jibes clean")
    }

    /// A gap under twenty points is "much the same"; fewer than three a side is no verdict.
    @Test func smallGapsAndFewTurnsAreNoVerdict() throws {
        let even = [try clean, try clean, try lateLoss,
                    try turn(score: 0.9, success: true, side: "starboard"),
                    try turn(score: 0.9, success: true, side: "starboard"),
                    try turn(side: "starboard", outcome: "touchdown")]
        let sides = try #require(coach(even).sides)
        #expect(sides.weaker == nil)
        #expect(sides.even)
        #expect(NextSessionCoach.sideVerdict(sides)
                == "Your port and starboard entries went much the same.")

        let few = try #require(coach([try clean, try turn(side: "starboard",
                                                          outcome: "touchdown")]).sides)
        #expect(few.weaker == nil)
        #expect(!few.even)
        #expect(NextSessionCoach.sideVerdict(few) == nil)
    }

    /// Tacks only: flew through per entry tack. One side ridden: no comparison.
    @Test func tacksCompareFlewThroughAndOneSideIsNoComparison() throws {
        let tacks = [try turn(type: "tack"), try turn(type: "tack", side: "starboard",
                                                      outcome: "fell_in")]
        let sides = try #require(coach(tacks).sides)
        #expect(sides.measure == .flewThrough)
        #expect(sides.port.hits == 1)
        #expect(sides.starboard.hits == 0)
        #expect(NextSessionCoach.sideValue(sides.port, measure: .flewThrough)
                == "1 of 1 flew through")

        #expect(coach([try clean, try clean]).sides == nil)
        #expect(coach([try clean, try turn(side: "unknown")]).sides == nil)
        #expect(coach([try clean, try clean]).isEmpty)
    }
}
