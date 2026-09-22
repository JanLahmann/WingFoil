import Foundation
import Testing
@testable import WingFoilKit

/// Discipline presets (docs/algorithms/disciplines.md "Disciplines") — the Swift half of the contract
/// `lab/tests/test_discipline.py` holds on the Python side. The *numbers* are cross-checked
/// against the lab by `GoldenTests.disciplineGoldensMatchWhenPresent`; this file holds the
/// rules that have no golden: that wingfoil is untouched, that the two speeds reach all four
/// configs, that the stamp composes with tuning, and that the lexicon leaves wing alone.
@Suite struct DisciplineTests {

    // MARK: - The map from a tag to a preset

    @Test func theDisciplineTagDecidesAndTheSportCodeIsNeverAsked() {
        #expect(Discipline.resolve(tag: nil) == .wingfoil)
        #expect(Discipline.resolve(tag: "") == .wingfoil)
        #expect(Discipline.resolve(tag: "wingfoil") == .wingfoil)
        // The corpus's own case: every "…-windsurfen…" recording in it is a wingfoil
        // afternoon ridden under Garmin's windsurf profile (ADR-004), and the sport code is
        // not an argument to `resolve` — which is how that is enforced rather than promised.
        #expect(Discipline.resolve(tag: "wingfoil", override: nil) == .wingfoil)
        #expect(Discipline.resolve(tag: "windsurf") == .windsurfFoil)
        #expect(Discipline.resolve(tag: "windsurfing") == .windsurfFoil)
        #expect(Discipline.resolve(tag: "windsurf_fin") == .windsurfFin)
        #expect(Discipline.resolve(tag: "Windsurf Fin") == .windsurfFin)
        #expect(Discipline.resolve(tag: "kitefoil") == .wingfoil)   // unreadable ⇒ default
    }

    @Test func theRidersOverrideWins() {
        #expect(Discipline.resolve(tag: "wingfoil", override: "windsurfFin") == .windsurfFin)
        #expect(Discipline.resolve(tag: "windsurf", override: "wingfoil") == .wingfoil)
        #expect(Discipline.resolve(tag: "windsurf", override: "") == .windsurfFoil)
    }

    @Test func theRowPutsTheTwoInTheirOrderOfAuthority() {
        var row = SessionRow(id: "x", startDate: Date(), durationS: 60, sourceClass: "b")
        #expect(row.analysisDiscipline == .wingfoil)
        row.sport = "windsurfing"                       // the sport code alone: still wing
        #expect(row.analysisDiscipline == .wingfoil)
        row.discipline = "windsurf"
        #expect(row.analysisDiscipline == .windsurfFoil)
        row.disciplineOverride = "wingfoil"
        #expect(row.analysisDiscipline == .wingfoil)
    }

    // MARK: - The preset over the configs

    @Test func wingfoilIsNotAppliedAtAll() {
        // Not "equal to the defaults": a caller's own thresholds — a tuning slider — have to
        // come out the other side untouched, which is only true if the preset is skipped.
        var turn = TurnConfig()
        turn.foilExitSpeedKmh = 6.5
        turn.pumpedOutIsTouchdown = true
        let out = Discipline.wingfoil.apply(to: Discipline.Configs(turn: turn))
        #expect(out.turn.foilExitSpeedKmh == 6.5)
        #expect(out.turn.pumpedOutIsTouchdown)
    }

    @Test func theFinSpeedsReachAllFourConfigs() {
        // The seam that would break silently: `SessionSummarizer.analyze` shares one off-foil
        // evidence object only while the turn, flight-end and takeoff configs agree on the
        // exit speed, and the flight segmenter is what defines the runs they judge.
        let out = Discipline.windsurfFin.apply(to: Discipline.Configs())
        #expect(out.flight.foilEntrySpeedKmh == 20.0)      // PROVISIONAL, issue #6
        #expect(out.turn.foilEntrySpeedKmh == 20.0)
        #expect(out.flightEnd.foilEntrySpeedKmh == 20.0)
        for exit in [out.flight.foilExitSpeedKmh, out.turn.foilExitSpeedKmh,
                     out.flightEnd.foilExitSpeedKmh, out.takeoff.foilExitSpeedKmh] {
            #expect(exit == 15.0)                          // PROVISIONAL, issue #6
        }
        // Holds and the minimum duration are *not* the fin's question — a plane holds like a
        // flight does, and moving them would have been a second, unargued hypothesis.
        #expect(out.flight.entryHoldS == FlightConfig().entryHoldS)
        #expect(out.flight.exitHoldS == FlightConfig().exitHoldS)
        #expect(out.flight.minFlightDurationS == FlightConfig().minFlightDurationS)
    }

    @Test func windsurfFoilMovesNoThresholdAtAllExceptThePumpRung() {
        let out = Discipline.windsurfFoil.apply(to: Discipline.Configs())
        #expect(out.flight == FlightConfig())
        #expect(out.flightEnd == FlightEndConfig())
        #expect(out.takeoff == TakeoffConfig())
        var expectedTurn = TurnConfig()
        expectedTurn.pumpedOutIsTouchdown = false
        #expect(out.turn == expectedTurn)
    }

    // MARK: - Pumping is absent, not zero

    @Test func aWindsurfRunAsksTheAccelerometerNothing() {
        let raw = Self.pumpingTrack()
        let wing = SessionSummarizer.analyze(raw)
        #expect(wing.capabilities.hasAccel)
        for discipline in [Discipline.windsurfFoil, .windsurfFin] {
            let a = SessionSummarizer.analyze(raw, discipline: discipline)
            #expect(a.pumpEpisodes.isEmpty)
            #expect(a.summary.takeoff.totalPumpStrokes == nil)
            #expect(a.summary.takeoff.avgPumpsToTakeoff == nil)
            #expect(a.flights.allSatisfy { $0.takeoffPumps == nil })
            #expect(a.takeoffs.allSatisfy { $0.pumps == nil })
            #expect(a.turns.allSatisfy { !$0.pumped })
            #expect(a.flightEnds.allSatisfy { !$0.pumped })
            #expect(a.config.turnPumpedOutIsTouchdown == false)
            // The source still *has* an accelerometer — the capability is a fact about the
            // recording, and it must not be rewritten to make a preset look consistent.
            #expect(a.capabilities.hasAccel)
        }
    }

    // MARK: - The echo

    @Test func theEchoNamesThePresetOnlyWhenThereIsOneToName() throws {
        let raw = Self.pumpingTrack()
        #expect(SessionSummarizer.analyze(raw).config.discipline == nil)
        let data = try JSONEncoder().encode(SessionSummarizer.analyze(raw))
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let cfg = try #require(obj["config"] as? [String: Any])
        // Absent, never `"wingfoil"` — the corpus goldens must not move for a layer that,
        // for the default, is not even reached.
        #expect(cfg["discipline"] == nil)

        let fin = SessionSummarizer.analyze(raw, discipline: .windsurfFin)
        #expect(fin.config.discipline == "windsurfFin")
        #expect(fin.config.foilEntrySpeed == 20.0)
        #expect(fin.config.foilExitSpeed == 15.0)
        // The version stamp is the engine's, unchanged: a preset is not a new engine.
        #expect(fin.engineVersion == AnalysisEngine.version)
    }

    // MARK: - The staleness stamp

    @Test func theStampRidesInTheEngineVersionAndComposesWithTuning() {
        #expect(DisciplineStamp.key(discipline: .wingfoil) == AnalysisEngine.version)
        let fin = DisciplineStamp.key(discipline: .windsurfFin)
        #expect(fin == "\(AnalysisEngine.version)+disc.windsurfFin")
        #expect(DisciplineStamp.discipline(fin) == .windsurfFin)
        #expect(DisciplineStamp.discipline(AnalysisEngine.version) == .wingfoil)
        #expect(DisciplineStamp.baseVersion(fin) == AnalysisEngine.version)

        var tuning = TuningOverrides()
        tuning[.turnPeakRate] = 22
        let both = tuning.engineVersionKey(base: fin)
        #expect(both.hasPrefix(fin))
        #expect(TuningStamp.isTuned(both))
        #expect(TuningStamp.changedCount(both) == 1)
        #expect(DisciplineStamp.discipline(both) == .windsurfFin)
        #expect(DisciplineStamp.baseVersion(both) == AnalysisEngine.version)
        // An untuned wingfoil run is byte-identical to one from a build without either
        // feature — which is the property that lets a stamped library stay comparable.
        #expect(TuningOverrides().engineVersionKey(
            base: DisciplineStamp.key(discipline: .wingfoil)) == AnalysisEngine.version)
    }

    // MARK: - The lexicon

    @Test func theWingfoilColumnIsTheStringsTheAppAlreadyPrinted() {
        let words = Discipline.wingfoil.lexicon
        #expect(words.flying == "flying")
        #expect(words.foilTime == "Foil time")
        #expect(words.onFoil == "On foil")
        #expect(words.takeoff == "Takeoff")
        #expect(words.takeoffs == "Takeoffs")
        #expect(words.lostTheFoil == "lost the foil")
        #expect(words.offTheFoil == "off the foil")
        #expect(words.chip == nil)
        #expect(!words.isExperimental)
        #expect(words.pumping)
        // Every surface that takes a discipline defaults to wingfoil and must be unmoved.
        #expect(SessionSection.takeoffs.label(.wingfoil) == SessionSection.takeoffs.label)
        for layer in MapLayer.allCases {
            #expect(layer.label(.wingfoil) == layer.label)
        }
        #expect(MapLayerScope.ride.layers(.wingfoil) == MapLayerScope.ride.layers)
    }

    @Test func theWindsurfColumnPlanesInsteadOfFlying() {
        for discipline in [Discipline.windsurfFoil, .windsurfFin] {
            let words = discipline.lexicon
            #expect(words.flying == "planing")
            #expect(words.foilTime == "Planing time")
            #expect(words.onFoil == "Planing")
            #expect(words.takeoff == "Planing start")
            #expect(words.lostTheFoil == "stopped planing")
            #expect(words.chip == "windsurf · experimental")
            #expect(words.isExperimental)
            #expect(!words.pumping)
            #expect(SessionSection.takeoffs.label(discipline) == "Planing starts")
            #expect(MapLayer.flying.label(discipline) == "planing")
            // The pump chip is not offered for a channel that was never run.
            #expect(!MapLayerScope.ride.layers(discipline).contains(.pumping))
            #expect(!MapLayerScope.takeoffs.layers(discipline).contains(.pumping))
            // The turn vocabulary is untouched on purpose — a jibe is a jibe.
            #expect(MapLayer.cleanJibe.label(discipline) == "clean jibe")
            #expect(MapLayer.flewThrough.label(discipline) == "flew through")
            #expect(SessionSection.turns.label(discipline) == "Turns")
        }
    }

    @Test func theOutcomeSentenceSwapsOneWordAndKeepsTheRest() throws {
        var turn = try Self.turnRecord(outcome: "touchdown", reason: "off_foil", offFoilS: 3)
        #expect(TurnAnalytics.outcomeText(turn)
                == "touchdown · off the foil 3 s, no stop")
        #expect(TurnAnalytics.outcomeText(turn, discipline: .windsurfFin)
                == "touchdown · off the plane 3 s, no stop")
        // Every other rung says the same thing on either rig.
        turn = try Self.turnRecord(outcome: "fell_in", reason: "submerged", offFoilS: 3)
        #expect(TurnAnalytics.outcomeText(turn, discipline: .windsurfFin)
                == "fell in · wrist under")
    }

    // MARK: - Helpers

    /// One turn record, through its own decoder — the record has no memberwise initialiser a
    /// test may reach, and building it from JSON is also how a stored document reaches the
    /// sentence under test.
    private static func turnRecord(outcome: String, reason: String,
                                   offFoilS: Double) throws -> TurnRecord {
        let json: [String: Any] = [
            "ts": 0.0, "endTs": 4.0, "type": "jibe", "counted": true,
            "entryKn": 14.0, "minKn": 9.0, "score": 64.0, "success": false,
            "side": "port", "direction": "left", "netDeg": 150.0,
            "arcM": 30.0, "radiusM": 11.0, "outcome": outcome, "borderline": false,
            "offFoilS": offFoilS, "stoppedS": 0.0, "pumped": false, "submerged": false,
            "outcomeWindowS": 12.0, "outcomeReason": reason,
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(TurnRecord.self, from: data)
    }

    /// 120 s with one flight in it and an accelerometer pumping through the run-up, so the
    /// wingfoil pass has strokes, episodes and a `takeoffPumps` to be stripped of.
    private static func pumpingTrack() -> RawTrack {
        var raw = RawTrack()
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        for t in stride(from: 0.0, through: 120, by: 1) {
            var s = RecordSample(t: t, timestamp: epoch.addingTimeInterval(t))
            s.speedMps = (20 <= t && t <= 90) ? 6.0 : 0.5
            raw.samples.append(s)
        }
        raw.capabilities.hasSpeed = true
        raw.capabilities.sampleRateHz = 1
        raw.capabilities.hasAccel = true
        // 25 Hz |a| with a 1 Hz swing through the run-up — pumping cadence, above
        // `pumpStrokeAmp` and above `pumpBurstPeakG`.
        var t = 0.0
        while t <= 120 {
            let pumping = 8 <= t && t <= 20
            let amp = pumping ? 1.2 : 0.02
            raw.accel.append(AccelSample(t: t,
                                         magnitudeG: 1.0 + amp * sin(2 * .pi * 1.0 * t)))
            t += 1.0 / 25
        }
        return raw
    }
}
