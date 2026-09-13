import Foundation
import Testing
@testable import WingFoilKit

/// **One tuning set per discipline** (docs/presentation.md "Tuning", Jan 13 Sep 2026: *"for
/// the windsurf analysis, we need to be able to set other parameters (min planing speed, etc)
/// than for wingfoil"*).
///
/// Four things have to hold, and everything the page does is built on them: a stored flat set
/// from before this existed becomes the wingfoil set and nothing else moves; each set stands
/// against its **own preset's** defaults; the two layers compose preset-first; and — the whole
/// point — a fin slider marks fin sessions stale and leaves wingfoil sessions exactly where
/// they were.
@Suite struct TuningOverrideSetsTests {

    // MARK: - Nothing set changes nothing

    @Test func emptySetsAreANoOpForEveryDiscipline() {
        let sets = TuningOverrideSets()
        #expect(sets.isEmpty)
        #expect(sets.totalChangedCount == 0)
        #expect(sets.tuned.isEmpty)
        for discipline in Discipline.allCases {
            #expect(sets.isEmpty(discipline))
            #expect(sets.changedCount(discipline) == 0)
            // The preset still applies — it is not a tuning — but nothing is applied on top,
            // and the stamp is the one a build without this feature would have written.
            #expect(sets.configs(for: discipline)
                    == discipline.apply(to: Discipline.Configs()))
            #expect(sets.engineVersionKey(discipline: discipline)
                    == DisciplineStamp.key(discipline: discipline))
        }
        #expect(sets.engineVersionKey(discipline: .wingfoil) == AnalysisEngine.version)
    }

    // MARK: - Each set stands against its own preset

    /// The fin's flight rows read 20.0 / 15.0, not 12.0 / 8.0 — which is what the caption
    /// under the slider prints and what dragging the slider home clears it to.
    @Test func aSetReadsItsOwnPresetsDefaults() {
        var sets = TuningOverrideSets()
        let fin = sets[.windsurfFin]
        #expect(fin.value(for: .foilEntrySpeed) == 20.0)   // PROVISIONAL, issue #6
        #expect(fin.value(for: .foilExitSpeed) == 15.0)
        #expect(fin.value(for: .turnPeakRate) == TuningParameter.turnPeakRate.spec.defaultValue)
        #expect(sets[.wingfoil].value(for: .foilEntrySpeed) == 12.0)
        #expect(sets[.windsurfFoil].value(for: .foilEntrySpeed) == 12.0)

        // Setting the preset's own number is a no-op and is dropped, exactly the way the
        // published default always has been.
        sets[.windsurfFin][.foilEntrySpeed] = 20.0
        #expect(sets.isEmpty(.windsurfFin))
        // …and the *wingfoil* number is a real override here, not a clear. Without this a fin
        // slider dragged to 12 would silently snap back to the preset's 20.
        sets[.windsurfFin][.foilEntrySpeed] = 12.0
        #expect(sets.changedCount(.windsurfFin) == 1)
        #expect(sets[.windsurfFin].value(for: .foilEntrySpeed) == 12.0)
        #expect(sets.configs(for: .windsurfFin).flight.foilEntrySpeedKmh == 12.0)
    }

    /// Every parameter a preset does not move reads the published default under every
    /// discipline — the wingfoil column *is* the parameter table.
    @Test func onlyThePresetsOwnThresholdsHaveADisciplineOfTheirOwn() {
        let moved: Set<TuningParameter> = [.foilEntrySpeed, .foilExitSpeed,
                                           .turnPumpedOutIsTouchdown]
        for parameter in TuningParameter.allCases {
            let spec = parameter.spec
            #expect(spec.presetDefault(for: .wingfoil) == spec.defaultValue)
            for discipline in [Discipline.windsurfFoil, .windsurfFin] where
                !moved.contains(parameter) {
                #expect(spec.presetDefault(for: discipline) == spec.defaultValue,
                        "\(parameter.rawValue) moved under \(discipline.rawValue)")
            }
        }
        // And the three that do are read out of the preset itself, so they cannot drift from
        // `Discipline.apply`.
        #expect(TuningParameter.foilEntrySpeed.spec.presetDefault(for: .windsurfFoil) == 12.0)
        #expect(TuningParameter.foilEntrySpeed.spec.presetDefault(for: .windsurfFin) == 20.0)
        #expect(TuningParameter.foilExitSpeed.spec.presetDefault(for: .windsurfFin) == 15.0)
        #expect(TuningParameter.turnPumpedOutIsTouchdown.spec
                .presetDefault(for: .windsurfFin) == 0)
    }

    /// A preset that grew a fourth threshold without the page being told would leave a slider
    /// printing the wrong default. This is the guard: the fin preset moves these and nothing
    /// else.
    @Test func thePresetStillMovesOnlyTheThresholdsThePageKnowsAbout() {
        for discipline in [Discipline.windsurfFoil, .windsurfFin] {
            var out = discipline.apply(to: Discipline.Configs())
            let entry = TuningParameter.foilEntrySpeed.spec.presetDefault(for: discipline)
            let exit = TuningParameter.foilExitSpeed.spec.presetDefault(for: discipline)
            #expect(out.flight.foilEntrySpeedKmh == entry)
            #expect(out.flight.foilExitSpeedKmh == exit)
            // Put the three known ones back; whatever is left must be the published configs.
            out.flight.foilEntrySpeedKmh = FlightConfig().foilEntrySpeedKmh
            out.flight.foilExitSpeedKmh = FlightConfig().foilExitSpeedKmh
            out.turn.foilEntrySpeedKmh = TurnConfig().foilEntrySpeedKmh
            out.turn.foilExitSpeedKmh = TurnConfig().foilExitSpeedKmh
            out.turn.pumpedOutIsTouchdown = TurnConfig().pumpedOutIsTouchdown
            out.flightEnd.foilEntrySpeedKmh = FlightEndConfig().foilEntrySpeedKmh
            out.flightEnd.foilExitSpeedKmh = FlightEndConfig().foilExitSpeedKmh
            out.takeoff.foilExitSpeedKmh = TakeoffConfig().foilExitSpeedKmh
            #expect(out == Discipline.Configs(),
                    "\(discipline.rawValue) moves a threshold the tuning page does not know")
        }
    }

    // MARK: - The pump rows a windsurf preset does not ask

    @Test func aPumpRowIsRefusedOnAWindsurfSetRatherThanStored() {
        #expect(TuningParameter.turnPumpedOutIsTouchdown.spec.available(in: .wingfoil))
        #expect(TuningParameter.turnPumpedMarginalSpeed.spec.available(in: .wingfoil))
        for discipline in [Discipline.windsurfFoil, .windsurfFin] {
            #expect(!TuningParameter.turnPumpedOutIsTouchdown.spec.available(in: discipline))
            #expect(!TuningParameter.turnPumpedMarginalSpeed.spec.available(in: discipline))
            // Every other row is asked of every rig.
            for parameter in TuningParameter.allCases where !parameter.spec.pumpChannel {
                #expect(parameter.spec.available(in: discipline))
            }
            var sets = TuningOverrideSets()
            sets[discipline][.turnPumpedMarginalSpeed] = 14
            sets[discipline][.turnPumpedOutIsTouchdown] = 1
            // Dropped, so the count and the fingerprint never carry a knob that moves nothing
            // — and the preset's refusal of the rung stands.
            #expect(sets.isEmpty(discipline))
            #expect(!sets.configs(for: discipline).turn.pumpedOutIsTouchdown)
        }
    }

    // MARK: - Preset first, overrides on top

    @Test func theCompositionIsThePresetThenTheRidersOwnNumbers() {
        var sets = TuningOverrideSets()
        sets[.windsurfFin][.foilEntrySpeed] = 22
        sets[.windsurfFin][.foilExitSpeed] = 17
        let out = sets.configs(for: .windsurfFin)
        // The rider's number wins over the preset's — the other order would stomp a slider he
        // has just moved.
        #expect(out.flight.foilEntrySpeedKmh == 22)
        #expect(out.turn.foilEntrySpeedKmh == 22)
        #expect(out.flightEnd.foilEntrySpeedKmh == 22)
        // …in all four configs, the same rule the preset itself follows: the off-foil evidence
        // is shared only while the three ladders agree, and the takeoff reads "planing" off
        // the same speed the runs were segmented on.
        for exit in [out.flight.foilExitSpeedKmh, out.turn.foilExitSpeedKmh,
                     out.flightEnd.foilExitSpeedKmh, out.takeoff.foilExitSpeedKmh] {
            #expect(exit == 17)
        }
        // A threshold the preset never touches still comes from the published table.
        #expect(out.turn.peakRateDegS == TurnConfig().peakRateDegS)
        // And the other two sets are untouched by any of it.
        #expect(sets.configs(for: .wingfoil) == Discipline.Configs())
        #expect(sets.configs(for: .windsurfFoil)
                == Discipline.windsurfFoil.apply(to: Discipline.Configs()))
    }

    /// The same, through the analyzer, read back off the document's own config echo — which is
    /// what the turn page's "Measured at" line and the workbench's what-if print.
    @Test func theEchoCarriesThePresetWithTheOverridesOnTop() {
        let raw = Self.planingTrack()
        var sets = TuningOverrideSets()
        sets[.windsurfFin][.foilEntrySpeed] = 22

        let fin = SessionSummarizer.analyze(raw, discipline: .windsurfFin,
                                            tuning: sets[.windsurfFin])
        #expect(fin.config.discipline == "windsurfFin")
        #expect(fin.config.foilEntrySpeed == 22)
        #expect(fin.config.foilExitSpeed == 15.0)        // the preset's, untouched
        // The wingfoil set is empty, so a wingfoil run is byte-identical to an untuned one.
        let wing = SessionSummarizer.analyze(raw, discipline: .wingfoil,
                                             tuning: sets[.wingfoil])
        #expect(wing.config.discipline == nil)
        #expect(wing.config.foilEntrySpeed == 12.0)
        #expect(wing.summary.foilTimeS == SessionSummarizer.analyze(raw).summary.foilTimeS)
    }

    // MARK: - Staleness, one rig at a time

    /// **The reason the sets are split.** Moving a fin threshold must not re-derive a library
    /// of wingfoil afternoons: the fingerprint rides inside that discipline's stamp, so only
    /// the fin's expected version changes and only fin rows come out stale.
    @Test func aFinSliderMarksOnlyFinSessionsStale() {
        var sets = TuningOverrideSets()
        let before = Discipline.allCases.map { sets.engineVersionKey(discipline: $0) }

        sets[.windsurfFin][.foilEntrySpeed] = 22
        let after = Discipline.allCases.map { sets.engineVersionKey(discipline: $0) }

        for (index, discipline) in Discipline.allCases.enumerated() {
            if discipline == .windsurfFin {
                #expect(after[index] != before[index])
                #expect(TuningStamp.changedCount(after[index]) == 1)
                #expect(DisciplineStamp.discipline(after[index]) == .windsurfFin)
                #expect(DisciplineStamp.baseVersion(after[index]) == AnalysisEngine.version)
            } else {
                // A wingfoil session analysed yesterday still carries exactly this string, so
                // `reanalyzeStale()` walks past it.
                #expect(after[index] == before[index])
                #expect(!TuningStamp.isTuned(after[index]))
            }
        }
        #expect(after[0] == AnalysisEngine.version)      // wingfoil, plain, as it always was
    }

    /// And the other way round: a wingfoil slider leaves the windsurf sessions alone.
    @Test func aWingfoilSliderMarksOnlyWingfoilSessionsStale() {
        var sets = TuningOverrideSets()
        let finBefore = sets.engineVersionKey(discipline: .windsurfFin)
        sets[.wingfoil][.turnPeakRate] = 22
        #expect(sets.engineVersionKey(discipline: .windsurfFin) == finBefore)
        #expect(TuningStamp.isTuned(sets.engineVersionKey(discipline: .wingfoil)))
        // Two sets, two fingerprints, one library — and each rig's stamp names its own.
        sets[.windsurfFin][.turnPeakRate] = 24
        let wing = sets.engineVersionKey(discipline: .wingfoil)
        let fin = sets.engineVersionKey(discipline: .windsurfFin)
        #expect(wing != fin)
        #expect(TuningStamp.parse(wing)?.fingerprint != TuningStamp.parse(fin)?.fingerprint)
        #expect(sets.totalChangedCount == 2)
        #expect(sets.tuned == [.wingfoil, .windsurfFin])
    }

    // MARK: - Persistence, and the one migration

    /// **The migration.** A `tuningOverrides.v1` written by a dev build before this existed is
    /// a flat parameter map, and its values are wingfoil's by construction — the windsurf
    /// presets did not exist while the single set did. So it becomes the wingfoil set, and the
    /// other two start empty.
    @Test func aStoredFlatSetBecomesTheWingfoilSet() throws {
        let data = Data("""
            {"turnPeakRate": 22, "foilEntrySpeed": 14}
            """.utf8)
        let sets = try JSONDecoder().decode(TuningOverrideSets.self, from: data)
        #expect(sets.changedCount(.wingfoil) == 2)
        #expect(sets[.wingfoil][.turnPeakRate] == 22)
        #expect(sets[.wingfoil][.foilEntrySpeed] == 14)
        #expect(sets.isEmpty(.windsurfFoil))
        #expect(sets.isEmpty(.windsurfFin))
        // The library it was analysed under is unchanged by the migration: same set, same
        // fingerprint, same wingfoil stamp — nothing re-derives because of the upgrade.
        var same = TuningOverrides()
        same[.turnPeakRate] = 22
        same[.foilEntrySpeed] = 14
        #expect(sets.engineVersionKey(discipline: .wingfoil) == same.engineVersionKey())
    }

    @Test func theNestedShapeRoundTripsAndKeepsEachSetApart() throws {
        var sets = TuningOverrideSets()
        sets[.wingfoil][.turnPeakRate] = 22
        sets[.windsurfFin][.foilEntrySpeed] = 22
        sets[.windsurfFin][.foilExitSpeed] = 17

        let data = try JSONEncoder().encode(sets)
        let back = try JSONDecoder().decode(TuningOverrideSets.self, from: data)
        #expect(back == sets)
        #expect(back.configs(for: .windsurfFin) == sets.configs(for: .windsurfFin))

        // Keyed by discipline, each one still the bare parameter map it always was.
        let json = try #require(try JSONSerialization.jsonObject(with: data)
                                as? [String: [String: Double]])
        #expect(Set(json.keys) == ["wingfoil", "windsurfFin"])
        #expect(json["windsurfFin"]?["foilEntrySpeed"] == 22)
        #expect(json["wingfoil"]?["turnPeakRate"] == 22)
    }

    @Test func nothingTunedAnywhereEncodesToAnEmptyObject() throws {
        let data = try JSONEncoder().encode(TuningOverrideSets())
        #expect(String(decoding: data, as: UTF8.self) == "{}")
        #expect(try JSONDecoder().decode(TuningOverrideSets.self, from: data)
                == TuningOverrideSets())
    }

    @Test func decodingIsLenientAboutDisciplinesAndNamesItDoesNotKnow() throws {
        let data = Data("""
            {"wingfoil": {"turnPeakRate": 22}, "kitefoil": {"turnPeakRate": 30},
             "windsurfFin": {"somethingFromAFutureBuild": 3, "foilEntrySpeed": 400}}
            """.utf8)
        let sets = try JSONDecoder().decode(TuningOverrideSets.self, from: data)
        #expect(sets.tuned == [.wingfoil, .windsurfFin])
        #expect(sets[.wingfoil][.turnPeakRate] == 22)
        // Unknown name dropped, out-of-range value clamped rather than trusted.
        #expect(sets.changedCount(.windsurfFin) == 1)
        #expect(sets[.windsurfFin][.foilEntrySpeed] == 25)
    }

    // MARK: - Moving a set between rigs

    @Test func aSetReadAgainstAnotherRigIsReReadNotReinterpreted() {
        var wing = TuningOverrides()
        wing[.foilEntrySpeed] = 20            // an override of wingfoil's 12…
        wing[.turnPumpedMarginalSpeed] = 14
        #expect(wing.changedCount == 2)

        // …and the fin's own default, so on the fin it is not an override at all; the pump row
        // is a channel the fin does not have, so it goes with it.
        let fin = wing.forDiscipline(.windsurfFin)
        #expect(fin.discipline == .windsurfFin)
        #expect(fin.isEmpty)

        // The container tags whatever it is handed, so a set can never sit under the wrong
        // rig's defaults.
        var sets = TuningOverrideSets()
        sets[.windsurfFin] = wing
        #expect(sets.isEmpty(.windsurfFin))
        sets[.wingfoil] = wing
        #expect(sets[.wingfoil].discipline == .wingfoil)
        #expect(sets.changedCount(.wingfoil) == 2)
    }

    @Test func resettingOneSetLeavesTheOthersAlone() {
        var sets = TuningOverrideSets()
        sets[.wingfoil][.turnPeakRate] = 22
        sets[.windsurfFin][.foilEntrySpeed] = 22
        sets.resetAll(.windsurfFin)
        #expect(sets.isEmpty(.windsurfFin))
        #expect(sets.changedCount(.wingfoil) == 1)
        sets.resetEverything()
        #expect(sets.isEmpty)
    }

    // MARK: - Helpers

    /// 120 s with one fast run in the middle — 21.6 km/h, over both the foil's 12 and the
    /// fin's provisional 20, so the same track segments under either preset.
    private static func planingTrack() -> RawTrack {
        var raw = RawTrack()
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        for t in stride(from: 0.0, through: 120, by: 1) {
            var s = RecordSample(t: t, timestamp: epoch.addingTimeInterval(t))
            s.speedMps = (20 <= t && t <= 90) ? 6.0 : 0.5
            raw.samples.append(s)
        }
        raw.capabilities.hasSpeed = true
        raw.capabilities.sampleRateHz = 1
        return raw
    }
}
