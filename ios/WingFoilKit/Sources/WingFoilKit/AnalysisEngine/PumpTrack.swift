import Foundation

/// Pump-stroke detection parameters (docs/algorithms.md "Pumping (accelerometer)").
public struct PumpConfig: Sendable, Equatable {
    public var bandLoHz: Double = 0.5
    public var bandHiHz: Double = 2.5
    /// |a| box-averaged onto a uniform grid (anti-alias + gap bookkeeping); matches the
    /// watch's rate so the two implementations can be compared sample-for-sample.
    public var resampleHz: Double = 25.0
    /// FIR length (Hamming-windowed sinc difference) = two full slow cycles.
    public var filterSpanS: Double = 2.0
    /// Band-passed peak height that counts as a stroke.
    public var strokeAmpG: Double = 0.25
    /// Dead time after a stroke (a human cannot pump at > 2.5 Hz).
    public var refractoryS: Double = 0.4
    /// Strokes closer than this belong to the same burst.
    public var strokeMaxIntervalS: Double = 1.5
    /// Burst length that means "the rider was pumping".
    public var minStrokes: Int = 4
    /// pumpBurstPeakG — **PROVISIONAL**. A burst's tallest stroke must reach this to be
    /// counted in the *session total*; nothing else reads it (`TakeoffAnalyzer`).
    public var burstPeakG: Double = 0.8
    /// pumpMinSpeedKmh — below this a stroke is a swim stroke, not a pump. Session total only.
    public var minSpeedKmh: Double = 3.0

    public init() {}
}

/// Band-passed accel magnitude on a uniform grid, plus the stroke queries built on it.
///
/// A wing pump is a whole-body oscillation the wrist sees as a large swing in |a|; wing trim
/// and arm drift are slower or smaller, and chop — measured, since engine 0.8.0 —  is at
/// *pumping cadence* and only about half the amplitude, which is why `burstPeakG` exists.
/// The stream is orientation-free by construction (magnitude, not axes). Consumers ask
/// questions about time windows, never about the raw signal.
/// Mirrors `lab/src/wingfoil_lab/pump.py`.
public struct PumpTrack: Sendable {
    /// Uniform grid, seconds on the records' time base.
    public let t: [Double]
    /// Band-passed |a| in g (0 where there is no data).
    public let band: [Double]
    /// The bin held at least one raw sample.
    public let valid: [Bool]
    public let config: PumpConfig

    /// Times of the pump strokes detected in [startT, endT].
    public func strokes(from startT: Double, to endT: Double) -> [Double] {
        let lo = searchSortedLeft(t, startT)
        let hi = searchSortedRight(t, endT)
        guard hi - lo >= 3 else { return [] }
        return PumpAnalyzer.pickPeaks(t: t, band: band, valid: valid, lo: lo, hi: hi,
                                      amp: config.strokeAmpG, refractoryS: config.refractoryS)
    }

    /// Band-passed height, in g, at each of these stroke times.
    ///
    /// Stroke times are grid samples by construction, so this reads the peak the picker
    /// actually fired on rather than an interpolation of it.
    public func peakAmps(_ strokes: [Double]) -> [Double] {
        strokes.map { linearInterp($0, t, band) }
    }

    /// Stroke times grouped into bursts (runs no more than `pumpStrokeMaxInterval` apart).
    /// Bursts are reported at every length; callers apply `pumpMinStrokes` themselves.
    public func bursts(from startT: Double, to endT: Double) -> [[Double]] {
        PumpAnalyzer.groupBursts(strokes(from: startT, to: endT),
                                 maxIntervalS: config.strokeMaxIntervalS)
    }

    /// Most strokes in a row with no gap longer than `pumpStrokeMaxInterval`.
    public func longestBurst(from startT: Double, to endT: Double) -> Int {
        bursts(from: startT, to: endT).map(\.count).max() ?? 0
    }

    /// True when [startT, endT] holds a burst of at least `pumpMinStrokes`.
    public func isPumping(from startT: Double, to endT: Double) -> Bool {
        longestBurst(from: startT, to: endT) >= config.minStrokes
    }
}

/// `np.interp`: piecewise-linear read of (xs, ys) at `q`, clamped at both ends.
func linearInterp(_ q: Double, _ xs: [Double], _ ys: [Double]) -> Double {
    guard !xs.isEmpty else { return 0 }
    if q <= xs[0] { return ys[0] }
    if q >= xs[xs.count - 1] { return ys[ys.count - 1] }
    var lo = 0, hi = xs.count - 1
    while hi - lo > 1 {
        let mid = (lo + hi) / 2
        if xs[mid] <= q { lo = mid } else { hi = mid }
    }
    guard xs[hi] > xs[lo] else { return ys[lo] }
    return ys[lo] + (q - xs[lo]) / (xs[hi] - xs[lo]) * (ys[hi] - ys[lo])
}

public enum PumpAnalyzer {

    /// Build a PumpTrack from a parsed source, or nil when it carries no accel stream.
    public static func track(_ raw: RawTrack, config: PumpConfig = PumpConfig()) -> PumpTrack? {
        guard !raw.accel.isEmpty else { return nil }
        return track(times: raw.accel.map(\.t), magnitudes: raw.accel.map(\.magnitudeG),
                     config: config)
    }

    /// PumpTrack from raw (time, |a| in g) samples — also the unit-test / replay entry point.
    public static func track(times: [Double], magnitudes: [Double],
                             config: PumpConfig = PumpConfig()) -> PumpTrack? {
        guard times.count >= 2 else { return nil }
        let t0 = times[0]
        let step = 1.0 / config.resampleHz
        let nBins = Int(((times[times.count - 1] - t0) / step).rounded(.down)) + 1
        guard nBins > 0 else { return nil }

        var count = [Double](repeating: 0, count: nBins)
        var total = [Double](repeating: 0, count: nBins)
        for i in times.indices {
            let idx = min(max(Int((times[i] - t0) / step), 0), nBins - 1)
            count[idx] += 1
            total[idx] += magnitudes[i]
        }
        let valid = count.map { $0 > 0 }
        guard valid.filter({ $0 }).count >= 3 else { return nil }

        var sumTotal = 0.0, sumCount = 0.0
        for i in 0..<nBins where valid[i] { sumTotal += total[i]; sumCount += count[i] }
        let level = sumTotal / sumCount

        // Empty bins (sensor gaps) are held at the mean so the FIR does not ring on them;
        // the filtered value there is discarded via `valid` anyway.
        var centered = [Double](repeating: 0, count: nBins)
        for i in 0..<nBins { centered[i] = valid[i] ? total[i] / count[i] - level : 0 }

        let taps = bandpassTaps(config)
        var band = convolveSame(centered, taps)
        for i in 0..<nBins where !valid[i] { band[i] = 0 }

        var grid = [Double](repeating: 0, count: nBins)
        for i in 0..<nBins { grid[i] = t0 + Double(i) * step }
        return PumpTrack(t: grid, band: band, valid: valid, config: config)
    }

    /// Hamming-windowed sinc band-pass (difference of two low-passes), odd tap count.
    static func bandpassTaps(_ config: PumpConfig) -> [Double] {
        let n = Int((config.filterSpanS * config.resampleHz).rounded()) | 1
        let mid = Double(n - 1) / 2
        func lowPass(_ fc: Double, _ k: Double) -> Double {
            let a = 2 * fc / config.resampleHz
            return a * sinc(a * k)
        }
        return (0..<n).map { i in
            let k = Double(i) - mid
            let hamming = 0.54 - 0.46 * cos(2 * .pi * Double(i) / Double(n - 1))
            return (lowPass(config.bandHiHz, k) - lowPass(config.bandLoHz, k)) * hamming
        }
    }

    /// np.sinc: sin(πx)/(πx), 1 at 0.
    static func sinc(_ x: Double) -> Double {
        x == 0 ? 1 : sin(.pi * x) / (.pi * x)
    }

    /// np.convolve(a, taps, mode: "same") for len(a) ≥ len(taps), taps of odd length.
    static func convolveSame(_ a: [Double], _ taps: [Double]) -> [Double] {
        let n = a.count, m = taps.count
        let offset = (m - 1) / 2
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            var acc = 0.0
            for j in 0..<m {
                let k = i + offset - j
                if k >= 0, k < n { acc += a[k] * taps[j] }
            }
            out[i] = acc
        }
        return out
    }

    /// Local maxima above `amp`, at least `refractoryS` apart (first-wins), over [lo, hi).
    static func pickPeaks(t: [Double], band: [Double], valid: [Bool], lo: Int, hi: Int,
                          amp: Double, refractoryS: Double) -> [Double] {
        var out: [Double] = []
        var last = -Double.infinity
        guard hi - lo >= 3 else { return out }
        for i in (lo + 1)..<(hi - 1) {
            guard valid[i], band[i] > amp, band[i] > band[i - 1], band[i] >= band[i + 1]
            else { continue }
            if t[i] - last >= refractoryS {
                out.append(t[i])
                last = t[i]
            }
        }
        return out
    }

    /// Split stroke times on any interval longer than `maxIntervalS`.
    static func groupBursts(_ strokes: [Double], maxIntervalS: Double) -> [[Double]] {
        guard !strokes.isEmpty else { return [] }
        var out: [[Double]] = []
        var current: [Double] = [strokes[0]]
        for i in 1..<strokes.count {
            if strokes[i] - strokes[i - 1] > maxIntervalS {
                out.append(current)
                current = []
            }
            current.append(strokes[i])
        }
        out.append(current)
        return out
    }
}
