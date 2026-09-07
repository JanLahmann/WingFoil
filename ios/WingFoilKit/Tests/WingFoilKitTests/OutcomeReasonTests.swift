import Foundation
import Testing
@testable import WingFoilKit

/// **Why a turn is a touchdown or a fall** (engine 0.18.0) — the reason the engine records,
/// the sentence presentation makes of it, and the switch that retired the pump rung.
///
/// Jan, 7 Sep 2026, two things in one breath: *"Can we add a short comment for the user why a
/// jibe is a touchdown or a fall?"* and, about the pump rung, *"change to '…below min foil
/// speed…'"*. The second is why his Jibe 50 of 4 Sep is a fly-through; the first is why the
/// page now says so in words.
@Suite struct OutcomeReasonTests {

    /// One turn record, built from JSON so the decoder is exercised on the way in — the same
    /// trip a stored `analysis.json` takes.
    private func record(reason: String?, outcome: String, borderline: Bool = false,
                        offFoilS: Double = 0, stoppedS: Double = 0,
                        omitReason: Bool = false) throws -> TurnRecord {
        var json: [String: Any] = [
            "ts": 100.0, "endTs": 106.0, "minTs": 103.0, "type": "jibe", "counted": true,
            "entryKn": 12.0, "minKn": 9.0, "exitKn": 11.0, "score": 0.75, "success": true,
            "clean": false, "side": "port", "direction": "starboard",
            "netDeg": 170.0, "arcM": 31.4, "radiusM": 20.0, "outcome": outcome,
            "borderline": borderline, "offFoilS": offFoilS, "stoppedS": stoppedS,
            "pumped": false, "submerged": false, "outcomeWindowS": 8.0,
        ]
        if !omitReason { json["outcomeReason"] = reason as Any? ?? NSNull() }
        return try JSONDecoder().decode(
            TurnRecord.self, from: JSONSerialization.data(withJSONObject: json))
    }

    // MARK: - The sentence

    /// The exact strings, and `web/tools/verify_presentation.py` §6 asserts the same list
    /// against the JavaScript. Two apps wording one fact differently is how a rider learns to
    /// trust one of them.
    @Test func theLineSaysWhichRungDecided() throws {
        // A touchdown that lost the foil briefly and never stopped.
        #expect(TurnAnalytics.outcomeText(
            try record(reason: "off_foil", outcome: "touchdown", offFoilS: 2, stoppedS: 0.4),
            foilExitSpeedKmh: 8) == "touchdown · off the foil 2 s, no stop")
        // …and one that did stop, briefly.
        #expect(TurnAnalytics.outcomeText(
            try record(reason: "off_foil", outcome: "touchdown", offFoilS: 2, stoppedS: 1.2),
            foilExitSpeedKmh: 8) == "touchdown · off the foil 2 s, stopped 1 s")
        // A stop in the ambiguous band: nearly a fall, and the word for that is borderline.
        #expect(TurnAnalytics.outcomeText(
            try record(reason: "stop", outcome: "touchdown", borderline: true,
                       offFoilS: 6, stoppedS: 4),
            foilExitSpeedKmh: 8) == "touchdown · stopped 4 s, borderline")
        // A fall the stop decided, and one the wrist decided.
        #expect(TurnAnalytics.outcomeText(
            try record(reason: "stop", outcome: "fell_in", offFoilS: 20, stoppedS: 7),
            foilExitSpeedKmh: 8) == "fell in · stopped 7 s")
        #expect(TurnAnalytics.outcomeText(
            try record(reason: "submerged", outcome: "fell_in", offFoilS: 30, stoppedS: 12),
            foilExitSpeedKmh: 8) == "fell in · wrist under")
    }

    /// The pump rung's wording. Unreachable at the published defaults since 0.18.0, and kept
    /// because a stored document written by an older engine still carries it.
    @Test func thePumpRungNamesTheSpeedFromTheDocumentsOwnConfig() throws {
        let turn = try record(reason: "pumped_marginal", outcome: "touchdown")
        #expect(TurnAnalytics.outcomeText(turn, foilExitSpeedKmh: 8)
                == "touchdown · pumped out below 4.3 kn, no sample off the foil")
        // A different exit speed is a different sentence — the number is never a literal.
        #expect(TurnAnalytics.outcomeText(turn, foilExitSpeedKmh: 10)
                == "touchdown · pumped out below 5.4 kn, no sample off the foil")
        // No config echo to read it off ⇒ the plainer wording, never an invented number.
        #expect(TurnAnalytics.outcomeText(turn)
                == "touchdown · pumped out below min foil speed, no sample off the foil")
    }

    /// Nothing to explain, and nothing recorded to explain it with.
    @Test func aFlyThroughAndAnOlderDocumentSayNothing() throws {
        #expect(TurnAnalytics.outcomeText(
            try record(reason: nil, outcome: "flew_through"), foilExitSpeedKmh: 8) == nil)
        // A document written before 0.18.0 carries no reason at all. Rebuilding one from
        // `stoppedS` would be a guess about a ladder that may not have been climbed that way.
        let old = try record(reason: nil, outcome: "touchdown", offFoilS: 2, stoppedS: 1,
                             omitReason: true)
        #expect(old.outcomeReason == nil)
        #expect(TurnAnalytics.outcomeText(old, foilExitSpeedKmh: 8) == nil)
    }

    /// Whole seconds, half **away from zero** — the one rounding rule the three languages
    /// share. `%.0f` would print 4.5 as "4" and disagree with the web's `Math.round`.
    @Test func aHalfSecondRoundsUpOnEveryPlatform() throws {
        #expect(TurnAnalytics.outcomeText(
            try record(reason: "stop", outcome: "fell_in", offFoilS: 9, stoppedS: 6.5),
            foilExitSpeedKmh: 8) == "fell in · stopped 7 s")
    }

    // MARK: - The rung itself

    /// The published default is **on**, and it is inert: `flying` already requires speed above
    /// `foilExitSpeed`, so on the branch the rung lives on there is nothing left below it.
    @Test func thePumpRungIsOnByDefaultAndCannotFire() {
        #expect(TurnConfig().pumpedOutIsTouchdown)
        #expect(TurnConfig().foilExitSpeedKmh < TurnConfig().foilEntrySpeedKmh)
    }

    /// The tuning row is a **switch**, not a slider, and it reads in the rider's words.
    @Test func theTuningRowIsASwitch() {
        let spec = TuningParameter.turnPumpedOutIsTouchdown.spec
        #expect(spec.kind == .toggle)
        #expect(spec.group == .outcomes)
        #expect(spec.defaultValue == 1)
        #expect(spec.title == "Pumped out below min foil speed is a touchdown")
        #expect(!spec.hidden)
        // "on" / "off", never "1" / "0" — the stored shape is not the rider's word for it.
        #expect(spec.formatted(1) == "on")
        #expect(spec.formatted(0) == "off")
        #expect(spec.formatted(spec.defaultValue) == "on")
        // Every other row stays a slider, so the split cannot leak.
        #expect(TuningParameter.allCases.filter { $0.spec.kind == .toggle }
                == [.turnPumpedOutIsTouchdown])
    }

    /// Stored as the same `Double` every other override is, and it moves the engine config.
    @Test func theSwitchStoresAsZeroOrOneAndReachesTheEngine() {
        var overrides = TuningOverrides()
        #expect(overrides.isEmpty)
        // Setting it to its default is a no-op, exactly like a slider dragged back home.
        overrides[.turnPumpedOutIsTouchdown] = 1
        #expect(overrides.isEmpty)
        #expect(overrides.apply().turn.pumpedOutIsTouchdown)

        overrides[.turnPumpedOutIsTouchdown] = 0
        #expect(overrides.changedCount == 1)
        #expect(overrides.value(for: .turnPumpedOutIsTouchdown) == 0)
        #expect(!overrides.apply().turn.pumpedOutIsTouchdown)
        // …and it rides in the engine-version stamp like any other moved threshold.
        #expect(TuningStamp.isTuned(overrides.engineVersionKey()))

        overrides.reset(.turnPumpedOutIsTouchdown)
        #expect(overrides.apply().turn.pumpedOutIsTouchdown)
    }

    /// The config echo writes it down, so a stored analysis says which reading produced it.
    @Test func theConfigEchoCarriesTheSwitch() {
        var turn = TurnConfig()
        let on = AnalysisConfig(filter: FilterConfig(), flight: FlightConfig(),
                                records: RecordsConfig(), turn: turn)
        #expect(on.turnPumpedOutIsTouchdown == true)
        turn.pumpedOutIsTouchdown = false
        let off = AnalysisConfig(filter: FilterConfig(), flight: FlightConfig(),
                                 records: RecordsConfig(), turn: turn)
        #expect(off.turnPumpedOutIsTouchdown == false)
    }
}
