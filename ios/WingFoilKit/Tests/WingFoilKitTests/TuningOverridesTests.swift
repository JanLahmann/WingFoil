import Foundation
import Testing
@testable import WingFoilKit

/// `TuningOverrides` — the dev build's threshold sliders (docs/presentation.md "Tuning").
///
/// The three things that have to hold, because everything downstream is built on them: an
/// empty set changes *nothing* (the shipping app is byte-identical to one built before the
/// feature existed), a set value reaches every config that reads that parameter, and the
/// fingerprint moves when and only when a value moves — it is the library's staleness key.
@Suite struct TuningOverridesTests {

    // MARK: - Nothing set changes nothing

    @Test func emptyOverridesAreANoOp() {
        let overrides = TuningOverrides()
        #expect(overrides.isEmpty)
        #expect(overrides.changedCount == 0)
        #expect(overrides.fingerprint == nil)
        #expect(overrides.engineVersionKey() == AnalysisEngine.version)

        let applied = overrides.apply()
        #expect(applied.turn == TurnConfig())
        #expect(applied.flight == FlightConfig())
        #expect(applied.flightEnd == FlightEndConfig())
    }

    /// Every parameter's declared default must actually *be* the engine's default, or the
    /// page prints "default 60" under a slider the engine reads as something else.
    @Test func declaredDefaultsMatchTheEngine() {
        let base = TuningOverrides.Configs()
        var overrides = TuningOverrides()
        for parameter in TuningParameter.allCases {
            overrides[parameter] = parameter.spec.defaultValue
        }
        // Setting every knob to its published default stores nothing…
        #expect(overrides.isEmpty)
        // …and applying it leaves all three configs exactly as they were.
        #expect(overrides.apply(to: base) == base)
    }

    @Test func everyParameterHasASpecAndSitsInItsRange() {
        for parameter in TuningParameter.allCases {
            let spec = parameter.spec
            #expect(spec.parameter == parameter)
            #expect(spec.range.contains(spec.defaultValue),
                    "\(parameter.rawValue) default outside its slider range")
            #expect(spec.step > 0)
            #expect(!spec.note.isEmpty)
        }
        // The page renders three sections and every parameter belongs to exactly one.
        let grouped = TuningGroup.allCases.flatMap { TuningParameter.all(in: $0) }
        #expect(Set(grouped) == Set(TuningParameter.allCases))
        #expect(grouped.count == TuningParameter.allCases.count)
    }

    // MARK: - Applying

    @Test func turnParametersReachTheTurnConfig() {
        var overrides = TuningOverrides()
        overrides[.turnMinAngle] = 70
        overrides[.turnClassifyMinAngle] = 100
        overrides[.turnMaxDuration] = 10
        overrides[.turnPeakRate] = 22
        overrides[.turnContinueRate] = 7
        overrides[.turnMinArc] = 16
        overrides[.turnMinRadius] = 9
        overrides[.turnSuccessPct] = 75
        overrides[.turnOutcomeWindow] = 20

        let out = overrides.apply()
        #expect(out.turn.minAngleDeg == 70)
        #expect(out.turn.classifyMinAngleDeg == 100)
        #expect(out.turn.maxDurationS == 10)
        #expect(out.turn.peakRateDegS == 22)
        #expect(out.turn.continueRateDegS == 7)
        #expect(out.turn.minArcM == 16)
        #expect(out.turn.minRadiusM == 9)
        #expect(out.turn.successPct == 75)
        #expect(out.turn.outcomeWindowS == 20)
        // Untouched knobs keep the published value.
        #expect(out.turn.baroDropM == TurnConfig().baroDropM)
        #expect(out.flight == FlightConfig())
    }

    /// The two foil speeds are read by all three configs, and a run where they disagree is a
    /// run whose turn scorer judges against a speed no flight was segmented on.
    @Test func foilSpeedsMoveInAllThreeConfigs() {
        var overrides = TuningOverrides()
        overrides[.foilEntrySpeed] = 14
        overrides[.foilExitSpeed] = 9.5

        let out = overrides.apply()
        #expect(out.flight.foilEntrySpeedKmh == 14)
        #expect(out.turn.foilEntrySpeedKmh == 14)
        #expect(out.flightEnd.foilEntrySpeedKmh == 14)
        #expect(out.flight.foilExitSpeedKmh == 9.5)
        #expect(out.turn.foilExitSpeedKmh == 9.5)
        #expect(out.flightEnd.foilExitSpeedKmh == 9.5)
        // `SessionSummarizer.analyze` only shares the off-foil evidence between the turn and
        // flight-end channels while these two agree — so they must still agree after tuning.
        #expect(out.flightEnd.foilExitSpeedKmh == out.turn.foilExitSpeedKmh)
        #expect(out.flightEnd.baroDropM == out.turn.baroDropM)
    }

    /// The stop ladder is one physical question asked of two channels: it moves as a pair.
    @Test func theStopLadderMovesAtBothEnds() {
        var overrides = TuningOverrides()
        overrides[.turnStopSpeedFloor] = 1.4
        overrides[.turnTouchdownMaxStop] = 4
        overrides[.turnFallStop] = 7
        overrides[.turnOutcomeLookahead] = 18
        overrides[.turnRecoverPct] = 80
        overrides[.turnRecoverHold] = 3
        overrides[.entrySpeedWindow] = 5

        let out = overrides.apply()
        #expect(out.turn.stopSpeedFloorMps == 1.4)
        #expect(out.flightEnd.stopSpeedFloorMps == 1.4)
        #expect(out.turn.touchdownMaxStopS == 4)
        #expect(out.flightEnd.touchdownMaxStopS == 4)
        #expect(out.turn.fallStopS == 7)
        #expect(out.flightEnd.fallStopS == 7)
        #expect(out.turn.outcomeLookaheadS == 18)
        #expect(out.flightEnd.outcomeLookaheadS == 18)
        #expect(out.turn.recoverPct == 80)
        #expect(out.flightEnd.recoverPct == 80)
        #expect(out.turn.recoverHoldS == 3)
        #expect(out.flightEnd.recoverHoldS == 3)
        #expect(out.turn.entrySpeedWindowS == 5)
        #expect(out.flightEnd.entrySpeedWindowS == 5)
    }

    /// …with one deliberate exception: the two outcome *windows* are not the same number
    /// today (12 s vs 60 s), so the turn's slider moves the turn's only.
    @Test func outcomeWindowMovesTheTurnOnly() {
        var overrides = TuningOverrides()
        overrides[.turnOutcomeWindow] = 30
        let out = overrides.apply()
        #expect(out.turn.outcomeWindowS == 30)
        #expect(out.flightEnd.outcomeWindowS == FlightEndConfig().outcomeWindowS)
    }

    @Test func flightParametersReachTheFlightConfig() {
        var overrides = TuningOverrides()
        overrides[.entryHold] = 1.5
        overrides[.exitHold] = 4
        overrides[.minFlightDuration] = 8

        let out = overrides.apply()
        #expect(out.flight.entryHoldS == 1.5)
        #expect(out.flight.exitHoldS == 4)
        #expect(out.flight.minFlightDurationS == 8)
        #expect(out.turn == TurnConfig())
    }

    /// `apply(to:)` starts from whatever it is handed — the ingestor passes its own
    /// `flightConfig` in, and an untouched parameter must not be reset to the published value.
    @Test func applyingBuildsOnTheConfigsItIsGiven() {
        var base = TuningOverrides.Configs()
        base.flight.touchdownMergeGapS = 2.5
        var overrides = TuningOverrides()
        overrides[.foilExitSpeed] = 7

        let out = overrides.apply(to: base)
        #expect(out.flight.touchdownMergeGapS == 2.5)
        #expect(out.flight.foilExitSpeedKmh == 7)
    }

    // MARK: - Setting, clearing, clamping

    @Test func settingTheDefaultClearsRatherThanStores() {
        var overrides = TuningOverrides()
        overrides[.turnPeakRate] = 25
        #expect(overrides.changedCount == 1)
        #expect(overrides.isOverridden(.turnPeakRate))

        overrides[.turnPeakRate] = TuningParameter.turnPeakRate.spec.defaultValue
        #expect(overrides.isEmpty)
        #expect(!overrides.isOverridden(.turnPeakRate))
        #expect(overrides.value(for: .turnPeakRate) == 18)
    }

    /// A `Slider` stepping 0.1 from 0.3 never lands exactly on 1.0, so "back to the default"
    /// has to be a tolerance and not `==` — otherwise dragging a knob home leaves the library
    /// permanently "tuned" to its own default value.
    @Test func aNearlyDefaultValueStillClears() {
        var overrides = TuningOverrides()
        overrides[.turnStopSpeedFloor] = 0.3 + 0.1 * 7
        #expect(overrides.isEmpty)
    }

    @Test func valuesAreClampedIntoTheSliderRange() {
        var overrides = TuningOverrides()
        overrides[.turnPeakRate] = 500
        #expect(overrides[.turnPeakRate] == 40)
        overrides[.turnPeakRate] = -10
        #expect(overrides[.turnPeakRate] == 5)
        overrides[.turnPeakRate] = .nan
        #expect(overrides[.turnPeakRate] == nil)
    }

    @Test func resetAndResetAll() {
        var overrides = TuningOverrides()
        overrides[.turnPeakRate] = 22
        overrides[.foilExitSpeed] = 7
        #expect(overrides.changedCount == 2)
        // `changed` reports in the parameter table's order, not the dictionary's.
        #expect(overrides.changed.map(\.parameter) == [.turnPeakRate, .foilExitSpeed])

        overrides.reset(.turnPeakRate)
        #expect(overrides.changedCount == 1)
        #expect(overrides.value(for: .turnPeakRate) == 18)

        overrides.resetAll()
        #expect(overrides.isEmpty)
    }

    // MARK: - Fingerprint and stamp

    @Test func fingerprintChangesWhenAValueChanges() {
        var a = TuningOverrides()
        a[.turnPeakRate] = 22
        var b = TuningOverrides()
        b[.turnPeakRate] = 23
        #expect(a.fingerprint != nil)
        #expect(a.fingerprint != b.fingerprint)

        // Same values, built in the other order: the same library, so the same fingerprint.
        var c = TuningOverrides()
        c[.foilExitSpeed] = 7
        c[.turnPeakRate] = 22
        var d = TuningOverrides()
        d[.turnPeakRate] = 22
        d[.foilExitSpeed] = 7
        #expect(c.fingerprint == d.fingerprint)
        #expect(c == d)

        // Adding a parameter moves it; taking it away again brings it back.
        var e = c
        e[.turnFallStop] = 6
        #expect(e.fingerprint != c.fingerprint)
        e.reset(.turnFallStop)
        #expect(e.fingerprint == c.fingerprint)
    }

    /// The stamp is the staleness key. It has to round-trip, and it has to leave an untuned
    /// engine version exactly as it was.
    @Test func stampRoundTrips() {
        var overrides = TuningOverrides()
        overrides[.turnPeakRate] = 22
        overrides[.foilExitSpeed] = 7

        let key = overrides.engineVersionKey()
        #expect(key.hasPrefix(AnalysisEngine.version))
        #expect(TuningStamp.isTuned(key))
        #expect(TuningStamp.changedCount(key) == 2)
        #expect(TuningStamp.baseVersion(key) == AnalysisEngine.version)

        let parsed = TuningStamp.parse(key)
        #expect(parsed?.base == AnalysisEngine.version)
        #expect(parsed?.changed == 2)
        #expect(parsed?.fingerprint == overrides.fingerprint)

        // A plain version is not tuned and is its own base.
        #expect(!TuningStamp.isTuned(AnalysisEngine.version))
        #expect(TuningStamp.changedCount(AnalysisEngine.version) == nil)
        #expect(TuningStamp.baseVersion("0.14.0") == "0.14.0")
    }

    // MARK: - Persistence

    @Test func codableRoundTrip() throws {
        var overrides = TuningOverrides()
        overrides[.turnPeakRate] = 22
        overrides[.turnStopSpeedFloor] = 1.4
        overrides[.minFlightDuration] = 8

        let data = try JSONEncoder().encode(overrides)
        let back = try JSONDecoder().decode(TuningOverrides.self, from: data)
        #expect(back == overrides)
        #expect(back.fingerprint == overrides.fingerprint)
        #expect(back.apply() == overrides.apply())

        // Encoded as the bare parameter map, so a stored preference reads as the table it
        // overrides rather than as a wrapper object.
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == ["turnPeakRate", "turnStopSpeedFloor", "minFlightDuration"])
    }

    @Test func decodingIsLenientAboutNamesItDoesNotKnow() throws {
        let data = Data("""
            {"turnPeakRate": 22, "somethingFromAFutureBuild": 3, "turnMinAngle": 4000}
            """.utf8)
        let decoded = try JSONDecoder().decode(TuningOverrides.self, from: data)
        // The unknown name is dropped, the known one survives, the out-of-range one is
        // clamped rather than trusted.
        #expect(decoded.changedCount == 2)
        #expect(decoded[.turnPeakRate] == 22)
        #expect(decoded[.turnMinAngle] == 120)
        #expect(decoded.apply().turn.minAngleDeg == 120)
    }

    @Test func emptyOverridesEncodeToAnEmptyObject() throws {
        let data = try JSONEncoder().encode(TuningOverrides())
        #expect(String(decoding: data, as: UTF8.self) == "{}")
        #expect(try JSONDecoder().decode(TuningOverrides.self, from: data) == TuningOverrides())
    }

    // MARK: - The config echo

    /// The four parameters the echo used to leave out — the turn-detail footnote names them,
    /// so the analysis has to write them down.
    @Test func theEchoCarriesTheFourNewParameters() {
        var turn = TurnConfig()
        turn.continueRateDegS = 7
        turn.entrySpeedWindowS = 5
        turn.minSpeedLagS = 3
        turn.recoverHoldS = 1.5
        let echo = AnalysisConfig(filter: FilterConfig(), flight: FlightConfig(),
                                  records: RecordsConfig(), turn: turn)
        #expect(echo.turnContinueRate == 7)
        #expect(echo.entrySpeedWindow == 5)
        #expect(echo.minSpeedLag == 3)
        #expect(echo.turnRecoverHold == 1.5)
    }
}
