import Foundation
import Testing
@testable import WingFoilKit

/// Unit cover for the phase-2/3 engine: wind-axis classification, the turn spatial gate,
/// the accelerometer path, source-capability degradation and the divergence banner.
/// Cross-implementation agreement with the lab is asserted separately in `GoldenTests`.
@Suite struct Phase23Tests {

    // MARK: - Turn classification against a wind axis

    /// TWA is wrap180(cog − windFrom): a tack crosses head-to-wind, a jibe crosses dead
    /// downwind, and a sweep that crosses neither is a course change (docs/algorithms.md).
    @Test func classifiesTackJibeAndCourseChanges() {
        let north = WindEstimate(userDirDeg: 0)

        // 315° → 405° (= 45°): passes through 0, head to wind.
        #expect(TurnDetector.classify(cogIn: 315, cogOut: 405, wind: north).kind == .tack)
        // 135° → 225°: passes through 180, dead downwind.
        #expect(TurnDetector.classify(cogIn: 135, cogOut: 225, wind: north).kind == .jibe)
        // 45° → 135°: crosses neither, and turns away from the wind.
        #expect(TurnDetector.classify(cogIn: 45, cogOut: 135, wind: north).kind == .bearAway)
        // 135° → 45°: crosses neither, and turns toward the wind.
        #expect(TurnDetector.classify(cogIn: 135, cogOut: 45, wind: north).kind == .roundUp)
    }

    @Test func sideIsTheTackSailedBeforeTheTurn() {
        let north = WindEstimate(userDirDeg: 0)
        // Positive TWA = wind over the port bow.
        #expect(TurnDetector.classify(cogIn: 45, cogOut: 135, wind: north).side == "port")
        #expect(TurnDetector.classify(cogIn: 315, cogOut: 225, wind: north).side == "starboard")
    }

    /// Without a usable axis nothing is named — the low-confidence case is a plain "turn",
    /// never a guessed jibe.
    @Test func unusableWindLeavesTurnsUnclassified() {
        var weak = WindEstimate(userDirDeg: 0)
        weak.confidence = 0.2
        weak.usable = false
        let c = TurnDetector.classify(cogIn: 135, cogOut: 225, wind: weak)
        #expect(c.kind == .unclassified)
        #expect(c.side == "unknown")
        #expect(TurnDetector.classify(cogIn: 135, cogOut: 225, wind: nil).kind == .unclassified)
    }

    // MARK: - Spatial gate

    /// `turnMinArc` / `turnMinRadius`: a heading flip on the spot covers no water however
    /// wide its angle, so it is dropped — not counted as a rejected course change.
    @Test func spatialGateDropsPivotsAndKeepsCarvedTurns() {
        var config = TurnConfig()
        config.minArcM = 12
        config.minRadiusM = 6

        var pivot = makeTurn(netDeg: 180, arcM: 8, radiusM: 2.5)
        #expect(!TurnDetector.carved(pivot, config))

        pivot.arcM = 30                    // enough water, still pivoting on the spot
        pivot.radiusM = 4
        #expect(!TurnDetector.carved(pivot, config))

        let jibe = makeTurn(netDeg: 150, arcM: 44, radiusM: 16.7)
        #expect(TurnDetector.carved(jibe, config))

        // Corpus-calibration anchor (docs/algorithms.md): the tightest genuine turn in the
        // three reference sessions measures arc 14.4 m / radius 8.7 m and must survive.
        #expect(TurnDetector.carved(makeTurn(netDeg: 95, arcM: 14.4, radiusM: 8.7), config))
    }

    /// Below `turnCogSpeedFloor` the COG is position noise, so those samples never form a
    /// geometry run — and a run needs at least 3 samples.
    @Test func sailingRunsNeedThreeConsecutiveSamples() {
        let runs = TurnDetector.sailingRuns([false, true, true, false,
                                             true, true, true, true, false, true])
        #expect(runs.count == 1)
        #expect(runs[0] == (4, 7))
    }

    // MARK: - Pump detection

    /// A clean 1 Hz oscillation inside the 0.5–2.5 Hz band is picked as one stroke per
    /// cycle; a 5 Hz chop of the same amplitude is rejected by the band-pass.
    @Test func pumpBandPassSeparatesPumpingFromChop() throws {
        func track(hz: Double, amplitudeG: Double) -> PumpTrack? {
            var t: [Double] = []
            var mag: [Double] = []
            for i in 0..<10_000 {                       // 100 Hz for 100 s
                let time = Double(i) / 100
                t.append(time)
                mag.append(1.0 + amplitudeG * sin(2 * .pi * hz * time))
            }
            return PumpAnalyzer.track(times: t, magnitudes: mag)
        }

        let pumping = try #require(track(hz: 1.0, amplitudeG: 0.6))
        let strokes = pumping.strokes(from: 10, to: 90)
        #expect(strokes.count >= 70 && strokes.count <= 85)   // ~1 per second
        #expect(pumping.isPumping(from: 10, to: 30))

        let chop = try #require(track(hz: 5.0, amplitudeG: 0.6))
        #expect(chop.strokes(from: 10, to: 90).isEmpty)
        #expect(!chop.isPumping(from: 10, to: 90))
    }

    /// `pumpStrokeMaxInterval` splits efforts: two clusters a long silence apart are two
    /// bursts, and `pumpMinStrokes` decides which of them counts as pumping.
    @Test func burstsSplitOnSilence() {
        let strokes = [0.0, 0.9, 1.8, 2.7, 20.0, 20.9]
        let bursts = PumpAnalyzer.groupBursts(strokes, maxIntervalS: 1.5)
        #expect(bursts.count == 2)
        #expect(bursts[0].count == 4)
        #expect(bursts[1].count == 2)
    }

    // MARK: - Accelerometer decoding

    /// The sanitizer strips `accelerometer_data` before the C decoder, so the stream has to
    /// come off the original bytes — this asserts it actually arrives, on the record clock,
    /// with the milli-g scale sniffed away.
    @Test func decodesTheSensorLoggingAccelStream() throws {
        let stem = "2026-08-07-0754_nago-torbole-windsurfen_ciq"
        guard let url = findFixtureFIT(stem: stem) else { return }   // fixture-optional
        let raw = try FitSessionParser.parse(url: url)

        #expect(raw.capabilities.hasAccel)
        #expect(raw.accel.count > 100_000, "expected the ~100 Hz stream, got \(raw.accel.count)")
        // Resting magnitude is ~1 g once the milli-g scale is undone.
        let median = Evidence.median(raw.accel.map(\.magnitudeG))
        #expect(abs(median - 1.0) < 0.3, "magnitude median \(median) is not in g")
        // Time-sorted and on the record time base (the first record is t = 0).
        #expect(zip(raw.accel, raw.accel.dropFirst()).allSatisfy { $0.t <= $1.t })
        #expect(abs(raw.accel[0].t) < 60)
        #expect(PumpAnalyzer.track(raw) != nil)
    }

    /// A source with no accelerometer must degrade, not fail: speed-only takeoff runs, nil
    /// stroke counts, and a nil success rate rather than a flattering 100 %.
    @Test func sourcesWithoutAccelDegradeInsteadOfFailing() {
        let analysis = SessionSummarizer.analyze(syntheticFlightTrack())
        #expect(analysis.capabilities.hasAccel == false)
        #expect(analysis.flights.count == 1)
        #expect(analysis.takeoffs.count == 1)
        #expect(analysis.takeoffs[0].pumps == nil)
        #expect(analysis.takeoffs[0].inFlightStrokes == nil)
        #expect(analysis.flights[0].takeoffPumps == nil)
        #expect(analysis.summary.takeoff.successPct == nil)
        #expect(analysis.summary.takeoff.totalPumpStrokes == nil)
        #expect(analysis.summary.takeoff.takeoffSuccesses == 1)
        // The speed-only half of the run is still measured.
        #expect(analysis.takeoffs[0].speedRiseS > 0)
    }

    /// No barometer ⇒ no submersion evidence, and an all-nil altitude channel must not
    /// make every sample look submerged.
    @Test func missingBarometerYieldsNoSubmersionEvidence() {
        let none = Evidence.submergedMask([nil, nil, nil], dropM: 25)
        #expect(none == [false, false, false])
        // With a channel, only a sample far below the median counts.
        let some = Evidence.submergedMask([100, 101, 99, -200], dropM: 25)
        #expect(some == [false, false, false, true])
    }

    // MARK: - Divergence check

    @Test func divergenceBannerFiresOnlyPastTheThresholds() {
        var analysis = SessionSummarizer.analyze(syntheticFlightTrack())
        analysis.summary.foilTimeS = 1000
        analysis.records.best2sKn = 20.0
        analysis.summary.flightCount = 10

        var agreeing = WatchSummary()
        agreeing.foilTimeS = 1030                      // +3 % — inside 5 %
        agreeing.best2sMps = 20.2 / Units.mpsToKn      // +0.2 kn — inside 0.3
        agreeing.flightCount = 11                      // ±1 — inside the count threshold
        #expect(DivergenceCheck.compare(watch: agreeing, phone: analysis).isEmpty)

        var diverging = WatchSummary()
        diverging.foilTimeS = 800                      // −20 %
        diverging.best2sMps = 19.0 / Units.mpsToKn     // −1.0 kn
        diverging.flightCount = 14                     // +4
        let found = DivergenceCheck.compare(watch: diverging, phone: analysis)
        #expect(Set(found.map(\.metric)) == ["Foil time", "Best 2 s", "Flights"])

        // Nothing to compare on a source without our session dev fields.
        #expect(DivergenceCheck.compare(watch: WatchSummary(), phone: analysis).isEmpty)
    }

    // MARK: - Helpers

    private func makeTurn(netDeg: Double, arcM: Double, radiusM: Double) -> Turn {
        Turn(startT: 0, endT: 5, minT: 3, kind: .jibe, netDeg: netDeg, peakRateDegS: 40,
             direction: "starboard", side: "port", entryKn: 12, minKn: 8,
             entryKnDoppler: 12, minKnDoppler: 8, score: 0.66, success: false,
             twaInDeg: 120, twaOutDeg: -120, arcM: arcM, chordM: arcM * 0.6, radiusM: radiusM)
    }

    /// 1 Hz, one clear flight, no position/accel/altitude channel.
    private func syntheticFlightTrack() -> RawTrack {
        var raw = RawTrack()
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        for t in stride(from: 0.0, through: 200, by: 1) {
            var s = RecordSample(t: t, timestamp: epoch.addingTimeInterval(t))
            switch t {
            case ..<40: s.speedMps = 0.5                     // sitting on the board
            case 40..<50: s.speedMps = 0.5 + (t - 40) * 0.6  // the rise
            case 50...140: s.speedMps = 6.5                  // flying
            default: s.speedMps = 0.4
            }
            raw.samples.append(s)
        }
        raw.capabilities.hasSpeed = true
        raw.capabilities.sampleRateHz = 1
        return raw
    }
}
