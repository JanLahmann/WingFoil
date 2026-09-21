import Foundation
import Testing
@testable import WingFoilKit

/// Engine 0.23.0 (ADR-030), the three fixes a tester's fenix 5 Plus files found:
/// a Smart Recording cadence is not a hole, an opposed pair of reaches still has a wind,
/// and an accelerometer stream may arrive without a clock. Twin of
/// `lab/tests/test_filters.py`, `test_wind.py`, `test_parse.py` and `test_pump.py`; the
/// numbers themselves are held by the goldens.
@Suite struct Engine023Tests {

    // MARK: - A cadence is not a hole

    private func raw(_ t: [Double], _ v: [Double]) -> RawTrack {
        var track = RawTrack()
        for (i, time) in t.enumerated() {
            var s = RecordSample(t: time, timestamp: Date(timeIntervalSince1970: time))
            s.speedMps = v[i]
            s.lat = 45
            s.lon = 10
            track.samples.append(s)
        }
        return track
    }

    /// The three terms of the rule (docs/algorithms.md "speed sample hygiene").
    @Test func theGapThresholdHasASmartRecordingFloor() {
        // Smart Recording: median dt 2 ⇒ the 10 s floor applies, so a 5 s and an 8 s step
        // are cadence, not holes, and only the 17 s one cuts.
        let smart = TrackCleaner.clean(raw([0, 2, 4, 6, 8, 13, 21, 38], [Double](repeating: 1, count: 8)))
        #expect(abs(smart.gapThresholdS - 10) < 1e-9)
        #expect(smart.samples.map(\.gapBefore) == [false, false, false, false, false, false, false, true])

        // 1 Hz: median 1 is below smartMedianDtS, so the threshold is max(3, 2) = 3.
        let fast = TrackCleaner.clean(raw([0, 1, 2, 3, 7], [Double](repeating: 1, count: 5)))
        #expect(abs(fast.gapThresholdS - 3) < 1e-9)
        #expect(fast.samples.map(\.gapBefore) == [false, false, false, false, true])
    }

    /// `smartGapS` is a floor under `max(gapMinS, gapFactor × median)`, never a cap.
    @Test func theFloorOnlyLiftsTheThreshold() {
        var config = FilterConfig()
        // A 20 s cadence: 2 × 20 = 40 already exceeds the floor, so the dt rule keeps winning.
        #expect(abs(TrackCleaner.gapThreshold(medianDtS: 20, config: config) - 40) < 1e-9)
        // Switched off, a median-2 track is cut at 4 s exactly as it was before 0.23.0.
        config.smartGapS = 0
        #expect(abs(TrackCleaner.gapThreshold(medianDtS: 2, config: config) - 4) < 1e-9)
    }

    /// A reacquisition burst across a long Smart Recording step is still a spike.
    ///
    /// `maxAccelMps2` is a 1 Hz value, so `|dv| ≤ 4 × dt` would let a 7 s step carry
    /// 28 m/s — which is what a receiver emits when it finds the sky again.
    @Test func theSpikeBudgetStopsGrowingAtThreeSeconds() {
        let t: [Double] = [0, 2, 4, 6, 8, 15, 17, 19, 21, 23, 25]
        let v: [Double] = [1, 1, 1, 1, 1, 17, 1, 1, 1, 1, 1]
        let clean = TrackCleaner.clean(raw(t, v))
        #expect(abs(clean.gapThresholdS - 10) < 1e-9)     // the 7 s step is not a gap
        #expect((clean.samples.map(\.dopplerMps).max() ?? 0) == 1)

        var loose = FilterConfig()
        loose.spikeMaxDtS = 1e9
        let uncapped = TrackCleaner.clean(raw(t, v), config: loose)
        #expect((uncapped.samples.map(\.dopplerMps).max() ?? 0) == 17)
    }

    // MARK: - An opposed pair of reaches still has a wind

    /// The half-angle bisector is the equal-weight circular mean wherever that is defined.
    @Test func theBisectorAgreesWithTheCircularMean() {
        for (a, b) in [(10.0, 100.0), (350.0, 95.0), (200.0, 25.0), (132.74, 311.9)] {
            let mean = WindEstimator.circularMean([a, b], [1, 1])
            #expect(abs(WindEstimator.wrap180(WindEstimator.bisector(a, b) - mean)) < 1e-9)
        }
    }

    /// At exactly 180° the mean is `atan2(0, 0)` — a bearing read off nothing. The
    /// half-angle form returns the perpendicular of the lobe axis, which is where the
    /// wind is when a rider sailed one beam reach and its reciprocal.
    @Test func exactlyOpposedLobesTakeThePerpendicular() {
        #expect(abs(WindEstimator.wrap180(WindEstimator.bisector(90, 270) - 0)) < 1e-9)
        #expect(abs(WindEstimator.wrap180(WindEstimator.bisector(132.74, 312.74) - 42.74)) < 1e-9)
        // 179.2°, the tester's shape: still a plain bisector, no refusal anywhere.
        #expect(abs(WindEstimator.wrap180(WindEstimator.bisector(132.74, 311.9) - 222.32)) < 0.01)
    }

    /// End to end: a nearly opposed pair used to come back with no axis at all, so not one
    /// of the session's maneuvers could be named a tack or a jibe.
    @Test func aNearlyOpposedSessionStillGetsAnAxis() throws {
        var cog: [Double] = []
        for _ in 0..<2 {
            cog += [Double](repeating: 89.6, count: 100)
            cog += [Double](repeating: -89.6, count: 100)
        }
        cog += [Double](repeating: 170, count: 40)
        let track = courseTrack(cog, speedMps: 6)
        let est = try #require(WindEstimator.estimate(track, flights: FlightSegmenter.segment(track)))
        #expect(abs((est.separationDeg ?? 0) - 179.2) < 0.6)
        #expect(abs(WindEstimator.wrap180(est.dirDeg)) <= 10)
        #expect(est.confidence > 0)
    }

    // MARK: - An accelerometer stream without a clock

    private func batch(base: Double, offsets: [Double], afterRecords: Int,
                       n: Int = 25) -> FitAccelReader.Batch {
        FitAccelReader.Batch(base: base, offsetsMs: offsets,
                             magnitudes: [Double](repeating: 1000, count: n),
                             afterRecords: afterRecords)
    }

    /// Offsets that spread inside the batch and bases inside the session: nothing moves.
    @Test func aTimedAccelStreamIsBelieved() {
        let epochs = (0..<4).map { 1000.0 + Double($0) }
        let batches = (0..<4).map {
            batch(base: 1000 + Double($0), offsets: (0..<25).map { Double($0) * 40 },
                  afterRecords: $0 + 1)
        }
        #expect(FitAccelReader.clockIsUsable(batches, recordEpochs: epochs))
    }

    /// Twenty-five samples all at offset 0 are twenty-five samples with one time.
    @Test func flatOffsetsCondemnTheClock() {
        let epochs = (0..<4).map { 1000.0 + Double($0) }
        let batches = (0..<4).map {
            batch(base: 1000 + Double($0), offsets: [Double](repeating: 0, count: 25),
                  afterRecords: $0 + 1)
        }
        #expect(!FitAccelReader.clockIsUsable(batches, recordEpochs: epochs))
    }

    /// The other half: bases days away from the ride, whatever the offsets say.
    @Test func staleBatchTimestampsCondemnTheClock() {
        let epochs = (0..<4).map { 1000.0 + Double($0) }
        let batches = (0..<4).map {
            batch(base: 1000 - 5 * 86400, offsets: (0..<25).map { Double($0) * 40 },
                  afterRecords: $0 + 1)
        }
        #expect(!FitAccelReader.clockIsUsable(batches, recordEpochs: epochs))
    }

    /// With no records to compare the bases against, the file is believed.
    @Test func noRecordsLeavesTheFileBelieved() {
        #expect(FitAccelReader.clockIsUsable(
            [batch(base: 1000, offsets: (0..<25).map { Double($0) * 40 }, afterRecords: 0)],
            recordEpochs: []))
    }

    // MARK: - The pump grid never trusts a file's clock

    /// Three shapes, one answer: `nil`, which is what a source with no accelerometer
    /// already gets, so every consumer degrades the way it always has.
    @Test func aBrokenClockIsRefusedRatherThanAllocatedOn() {
        let t = (0..<400).map { Double($0) / 100 }
        let mag = [Double](repeating: 1, count: 400)
        #expect(PumpAnalyzer.track(times: t.map { _ in Double.nan }, magnitudes: mag) == nil)
        #expect(PumpAnalyzer.track(times: [0, 50 * 86400], magnitudes: [1, 1]) == nil)
    }

    /// One poisoned sample costs one sample, not the channel.
    @Test func nonFiniteSamplesAreDroppedAndTheRestStillReads() throws {
        var t = (0..<3000).map { Double($0) / 100 }
        var mag = t.map { 1 + 0.5 * sin(2 * .pi * 1.0 * $0) }
        t[100] = .nan
        mag[200] = .infinity
        let track = try #require(PumpAnalyzer.track(times: t, magnitudes: mag))
        #expect(track.band.allSatisfy { $0.isFinite })
        #expect(track.longestBurst(from: 0, to: 30) >= 4)
    }

    /// An out-of-order stream is sorted rather than mis-binned.
    @Test func anUnsortedStreamIsSorted() throws {
        var t = (0..<2000).map { Double($0) / 100 }
        var mag = t.map { 1 + 0.5 * sin(2 * .pi * 1.0 * $0) }
        let straight = try #require(PumpAnalyzer.track(times: t, magnitudes: mag))
        t.swapAt(5, 9)
        mag.swapAt(5, 9)
        let shuffled = try #require(PumpAnalyzer.track(times: t, magnitudes: mag))
        #expect(shuffled.band.count == straight.band.count)
        for i in straight.band.indices where abs(shuffled.band[i] - straight.band[i]) > 1e-9 {
            Issue.record("band differs at \(i)")
            break
        }
    }

    // MARK: - Helpers

    private func courseTrack(_ cogDeg: [Double], speedMps: Double) -> CleanTrack {
        var track = CleanTrack()
        var x = 0.0, y = 0.0, dist = 0.0
        for (i, deg) in cogDeg.enumerated() {
            track.samples.append(CleanSample(t: Double(i), dt: i == 0 ? 0 : 1, gapBefore: false,
                                             x: x, y: y, dopplerMps: speedMps,
                                             positionalMps: speedMps, cumDistM: dist))
            x += sin(deg * .pi / 180) * speedMps
            y += cos(deg * .pi / 180) * speedMps
            dist += speedMps
        }
        track.segments = [0..<track.samples.count]
        track.medianDtS = 1
        track.gapThresholdS = 3
        track.spanS = Double(cogDeg.count - 1)
        track.timerTimeS = Double(cogDeg.count - 1)
        return track
    }
}
