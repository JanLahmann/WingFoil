import Foundation
import Testing
@testable import WingFoilKit

/// Synthetic tracks with hand-computable answers. All profiles are functions of *time*
/// (piecewise-constant over ≥ 2 s blocks aligned to even seconds), so sampling them at
/// 1 Hz and 0.5 Hz must yield identical analysis — the engine's dt-awareness contract.
@Suite struct AnalysisEngineTests {

    private let kn = Units.mpsToKn
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    /// Speed-only track: v(t) sampled every `dt` from 0 through `duration` inclusive.
    private func speedTrack(dt: Double, duration: Double, v: (Double) -> Double) -> RawTrack {
        var raw = RawTrack()
        var t = 0.0
        while t <= duration + 1e-9 {
            var s = RecordSample(t: t, timestamp: epoch.addingTimeInterval(t))
            s.speedMps = v(t)
            raw.samples.append(s)
            t += dt
        }
        return raw
    }

    /// Positioned track: local meters x(t)/y(t) converted back to degrees with the same
    /// constants the cleaner uses (equator-adjacent, so cos(lat0) ≈ 1 to < 0.1 ppm).
    private func positionedTrack(dt: Double, duration: Double, v: (Double) -> Double,
                                 x: (Double) -> Double, y: (Double) -> Double) -> RawTrack {
        var raw = speedTrack(dt: dt, duration: duration, v: v)
        for i in raw.samples.indices {
            let t = raw.samples[i].t
            raw.samples[i].lat = y(t) / 110_540
            raw.samples[i].lon = x(t) / 111_320
        }
        return raw
    }

    private func analyzeFlights(_ raw: RawTrack) -> FlightSegmentation {
        FlightSegmenter.segment(TrackCleaner.clean(raw))
    }

    // MARK: - Flight hysteresis

    /// 12 km/h = 3.333 m/s entry, 8 km/h = 2.222 m/s exit. Profile (m/s):
    /// off 1.0 → [10,40) fly 5.0 → off → [50,56) fly 5.0 → off → [70,74) burst 5.0 (4 s,
    /// discarded: < minFlightDuration) → off. Expected flights [10,40] and [50,56].
    private func hysteresisProfile(_ t: Double) -> Double {
        switch t {
        case 10..<40, 50..<56, 70..<74: return 5.0
        default: return 1.0
        }
    }

    @Test func flightHysteresisAt1Hz() {
        let seg = analyzeFlights(speedTrack(dt: 1, duration: 80, v: hysteresisProfile))
        #expect(seg.flights.count == 2)
        #expect(seg.flights[0].startT == 10 && seg.flights[0].endT == 40)
        #expect(seg.flights[1].startT == 50 && seg.flights[1].endT == 56)
        #expect(seg.foilTimeS == 36)
        #expect(abs(seg.foilPct - 45.0) < 1e-9)          // 36 s of 80 s, no gaps
        #expect(seg.longest?.durationS == 30)
        #expect(abs((seg.flights[0].maxKn) - 5 * kn) < 1e-9)
    }

    @Test func flightHysteresisSameAt0p5Hz() {
        let a = analyzeFlights(speedTrack(dt: 1, duration: 80, v: hysteresisProfile))
        let b = analyzeFlights(speedTrack(dt: 2, duration: 80, v: hysteresisProfile))
        #expect(b.flights.count == a.flights.count)
        for (fa, fb) in zip(a.flights, b.flights) {
            #expect(fa.startT == fb.startT)
            #expect(fa.endT == fb.endT)
        }
        #expect(b.foilTimeS == a.foilTimeS)
        #expect(abs(b.foilPct - a.foilPct) < 1e-9)
    }

    @Test func entryHoldRejectsShortBurst() {
        // ≥ entry for < entryHold (2 s): never ON at either rate.
        let v: (Double) -> Double = { t in (10 <= t && t < 12) ? 5.0 : 1.0 }
        #expect(analyzeFlights(speedTrack(dt: 1, duration: 40, v: v)).flights.isEmpty)
        #expect(analyzeFlights(speedTrack(dt: 2, duration: 40, v: v)).flights.isEmpty)
    }

    // MARK: - Duration peaks

    @Test func best2sAnd10sPeaks() throws {
        // 3 m/s baseline, 8 m/s for t ∈ [25, 29]. Trapezoid increments: ramps (24,25) and
        // (29,30) contribute 5.5 each. best2s = fully inside plateau = 8.0 m/s.
        // best10s = any window ⊇ [24, 30] = (2×3 + 5.5 + 4×8 + 5.5 + 2×3)/10 = 5.5 m/s.
        let raw = speedTrack(dt: 1, duration: 60) { t in (25 <= t && t <= 29) ? 8.0 : 3.0 }
        let records = GP3SCalculator.records(for: TrackCleaner.clean(raw))
        #expect(abs(try #require(records.best2sKn) - 8.0 * kn) < 1e-9)
        #expect(abs(try #require(records.best10sKn) - 5.5 * kn) < 1e-9)
        #expect(records.windows["best2s"]?.durS == 2)
        #expect(records.windows["best10s"]?.durS == 10)
    }

    // MARK: - Distance records

    @Test func best500mConstantSpeed() throws {
        let raw = speedTrack(dt: 1, duration: 100) { _ in 10.0 }
        let records = GP3SCalculator.records(for: TrackCleaner.clean(raw))
        #expect(abs(try #require(records.best500mKn) - 10.0 * kn) < 1e-9)
        #expect(abs(try #require(records.windows["best500m"]).durS - 50) < 1e-9)
        #expect(abs(try #require(records.best100mKn) - 10.0 * kn) < 1e-9)
        #expect(records.bestNmKn == nil)                 // only 1000 m sailed
        #expect(abs(records.totalDistanceM - 1000) < 1e-9)
    }

    @Test func best500mEdgeInterpolation() throws {
        // 5 m/s for t < 60, 8 m/s from t = 60. The 3 m/s step stays under the 4 m/s²
        // spike gate (a 5→10 step would get the ramp sample dropped — by design).
        // Trapezoid distance: D(60) = 301.5, D(100) = 621.5. Best 500 m is the
        // backward-anchored window ending at t = 100: start where D = 121.5
        // ⇒ t1 = 24 + 1.5/5 = 24.3 ⇒ 75.7 s — beats every forward-anchored window;
        // exercises both families + start-edge interpolation.
        let raw = speedTrack(dt: 1, duration: 100) { t in t < 60 ? 5.0 : 8.0 }
        let clean = TrackCleaner.clean(raw)
        #expect(clean.droppedSpike == 0)
        let records = GP3SCalculator.records(for: clean)
        let expected = 500.0 / 75.7 * kn
        #expect(abs(try #require(records.best500mKn) - expected) < 1e-6)
        let window = try #require(records.windows["best500m"])
        #expect(abs(window.startTs - 24.3) < 1e-6)
        #expect(abs(window.durS - 75.7) < 1e-6)
    }

    // MARK: - Alpha 500

    @Test func alpha500OutAndBack() throws {
        // Due north 10 m/s for 25 s (250 m), then due south 10 m/s for 25 s, back to the
        // start. Window [0, 50]: path 500 m, endpoints 0 m apart, COG spread 180°.
        // Alpha = 10 m/s. Constant speed ⇒ every valid window ties at 10 m/s.
        let raw = positionedTrack(dt: 1, duration: 50, v: { _ in 10.0 },
                                  x: { _ in 0 },
                                  y: { t in t <= 25 ? 10 * t : 250 - 10 * (t - 25) })
        let records = GP3SCalculator.records(for: TrackCleaner.clean(raw))
        #expect(abs(try #require(records.alpha500Kn) - 10.0 * kn) < 1e-9)
    }

    @Test func alpha500NilOnStraightLine() {
        // Straight north at 10 m/s: no window with ≥ 250 m path keeps endpoints ≤ 50 m
        // apart (and COG spread is 0) ⇒ no alpha.
        let raw = positionedTrack(dt: 1, duration: 100, v: { _ in 10.0 },
                                  x: { _ in 0 }, y: { t in 10 * t })
        let records = GP3SCalculator.records(for: TrackCleaner.clean(raw))
        #expect(records.alpha500Kn == nil)
    }

    // MARK: - 5 × 10 s

    @Test func fiveByTenDisjointWindows() throws {
        // 5 m/s baseline, 10 m/s for t ∈ [20, 40]. The two best disjoint windows are
        // [20,30] and [30,40] (touching endpoints are disjoint), both 10.0 m/s. Then
        // [10,20] and [40,50] (5.25 with the ramp), then 5.0.
        // Mean = (10 + 10 + 5.25 + 5.25 + 5)/5 = 7.1 m/s.
        let raw = speedTrack(dt: 1, duration: 120) { t in (20 <= t && t <= 40) ? 10.0 : 5.0 }
        let records = GP3SCalculator.records(for: TrackCleaner.clean(raw))
        #expect(abs(try #require(records.best5x10sKn) - 7.1 * kn) < 1e-9)
        #expect(abs(try #require(records.best10sKn) - 10.0 * kn) < 1e-9)
        #expect(records.windows.best5x10s?.count == 5)
        // Greedy without the disjointness constraint would report 10.0; with it but
        // without touching-allowed it would report (10+5.25+5.25+5+5)/5 = 6.1.
    }

    /// Fewer than five disjoint windows is a *partial* mean, not "no record" — the lab's
    /// rule (`gp3s.py` `_best_5x10`: `if vals`), which Swift used to round down to nil.
    ///
    /// 45 s of clean data at 10 m/s for t ≤ 10 and 7 m/s after (a 3 m/s² step, under the
    /// cleaner's 4 m/s² gate, so nothing is dropped). Candidate starts run to
    /// t_last − 10 = 35, so the greedy search yields exactly four disjoint windows:
    /// [0,10] = 10.0, then [10,20] = (8.5 + 7×9)/10 = 7.15 (the trapezoid over the step),
    /// then [20,30] and [30,40] at 7.0. Mean = 31.15 / 4 = 7.7875 m/s.
    @Test func fiveByTenPartialMeanOverFewerThanFiveWindows() throws {
        let raw = speedTrack(dt: 1, duration: 45) { t in t <= 10 ? 10.0 : 7.0 }
        let records = GP3SCalculator.records(for: TrackCleaner.clean(raw))
        let windows = try #require(records.windows.best5x10s)
        #expect(windows.count == 4)
        #expect(windows.map(\.startTs) == [0, 10, 20, 30])
        #expect(windows.allSatisfy { $0.durS == 10 })
        #expect(abs(try #require(records.best5x10sKn) - (31.15 / 4) * kn) < 1e-9)
    }

    /// Three windows fit in 30 s (starts 0/10/20), so even a short session reports a mean.
    @Test func fiveByTenPartialMeanOnShortTrack() throws {
        let raw = speedTrack(dt: 1, duration: 30) { _ in 5.0 }
        let records = GP3SCalculator.records(for: TrackCleaner.clean(raw))
        #expect(records.windows.best5x10s?.count == 3)
        #expect(abs(try #require(records.best5x10sKn) - 5.0 * kn) < 1e-9)
        #expect(records.best10sKn != nil)
    }

    /// Nil only when not one 10 s window fits.
    @Test func fiveByTenNilWhenNoWindowFits() {
        let raw = speedTrack(dt: 1, duration: 8) { _ in 5.0 }
        let records = GP3SCalculator.records(for: TrackCleaner.clean(raw))
        #expect(records.best5x10sKn == nil)
        #expect(records.windows.best5x10s == nil)
        #expect(records.best2sKn != nil)
    }

    // MARK: - Gaps & cleaning

    @Test func gapSplitsSegmentsAndFoilPctUsesNonGapTime() throws {
        // 10 m/s from 0–30 and 45–60; 15 s hole (> max(3 s, 2×median dt) = 3 s).
        var raw = RawTrack()
        for t in stride(from: 0.0, through: 30, by: 1) {
            var s = RecordSample(t: t, timestamp: epoch.addingTimeInterval(t))
            s.speedMps = 10
            raw.samples.append(s)
        }
        for t in stride(from: 45.0, through: 60, by: 1) {
            var s = RecordSample(t: t, timestamp: epoch.addingTimeInterval(t))
            s.speedMps = 10
            raw.samples.append(s)
        }
        let clean = TrackCleaner.clean(raw)
        #expect(clean.segments.count == 2)
        #expect(clean.samples[31].gapBefore)
        #expect(clean.timerTimeS == 45)
        #expect(clean.samples.last!.cumDistM == 450)     // no distance across the gap

        let seg = FlightSegmenter.segment(clean)
        #expect(seg.flights.count == 2)                  // gap forces a flight break
        #expect(seg.flights[0].endT == 30)
        #expect(seg.flights[1].startT == 45)
        #expect(abs(seg.foilPct - 100.0) < 1e-9)         // 45 s foiling of 45 s non-gap

        let records = GP3SCalculator.records(for: clean)
        #expect(abs(try #require(records.best2sKn) - 10 * kn) < 1e-9) // windows stay inside segments
        #expect(records.bestHourKn == nil)
    }

    @Test func dopplerSpikeDropped() throws {
        // Constant 5 m/s with one 20 m/s spike at t = 30: |dv/dt| = 15 > 4 m/s².
        // Cleaner semantics: the spiked sample is DROPPED (surfaces as a larger dt),
        // never filled — every kept sample keeps its true Doppler value.
        let raw = speedTrack(dt: 1, duration: 60) { t in t == 30 ? 20.0 : 5.0 }
        let clean = TrackCleaner.clean(raw)
        #expect(clean.droppedSpike == 1)
        #expect(clean.samples.count == raw.samples.count - 1)
        #expect(!clean.samples.contains { $0.dopplerMps > 19 })
        let after = clean.samples[30]                    // t = 31 now follows t = 29
        #expect(abs(after.dt - 2.0) < 1e-9)
        #expect(!after.gapBefore)                        // 2 s < gap threshold (3 s)

        let records = GP3SCalculator.records(for: clean)
        #expect(abs(try #require(records.best2sKn) - 5.0 * kn) < 1e-9)  // spike doesn't inflate peaks
    }

    @Test func positionalSpeedFromProjection() throws {
        // Due east at 8 m/s: positional speed (dt-aware central difference on the
        // local-meter projection) must reconstruct the speed alongside the Doppler channel.
        let raw = positionedTrack(dt: 1, duration: 30, v: { _ in 8 },
                                  x: { t in 8 * t }, y: { _ in 0 })
        let clean = TrackCleaner.clean(raw)
        let mid = clean.samples[15]
        #expect(abs(try #require(mid.positionalMps) - 8.0) < 0.001)
        #expect(abs(mid.dopplerMps - 8.0) < 1e-9)
        let last = clean.samples.last!
        #expect(abs(last.cumDistM - 8.0 * last.t) < 0.5)
    }
}
