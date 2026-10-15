import Foundation

/// Jump-detection and height parameters (docs/algorithms/jumps.md "Jumps"). Mirrors the
/// detection and height fields of the lab's `JumpConfig`; the baro secondary stays in the
/// lab, which is the only place it is reported.
///
/// Chosen from the synthetic grid and the shape of the real corpus, plus Freddy's labelled
/// sessions for the three context gates — **the heights are uncalibrated**.
public struct JumpConfig: Sendable, Equatable {
    // --- detection ---
    /// jumpSmooth, s: the *median* filter span on |a| (spike-safe, keeps the step edge).
    public var smoothS: Double = 0.06
    /// jumpAirborneMaxG: |a| below this is "airborne".
    public var airborneMaxG: Double = 0.75
    /// jumpBridge, s: a noise excursion this short does not end a window …
    public var bridgeS: Double = 0.10
    /// jumpBridgeMaxG: … provided it stays below this.
    public var bridgeMaxG: Double = 0.95
    /// jumpMinAirtime, s: shorter is chop, not a jump (and not even a candidate).
    public var minAirtimeS: Double = 0.4
    /// jumpMaxAirtime, s: longer is a dropout, not a jump.
    public var maxAirtimeS: Double = 4.0
    /// jumpTakeoffMinG: the pop spike before the window.
    public var takeoffMinG: Double = 1.8
    /// jumpImpactMinG: the landing spike after the window.
    public var impactMinG: Double = 2.5
    /// jumpSpikeWindow, s: the search span for both spikes.
    public var spikeWindowS: Double = 1.0
    /// jumpRefractory, s: dead time after an accepted jump.
    public var refractoryS: Double = 2.0
    /// jumpMaxGap, s: a sensor hole inside the window voids it.
    public var maxGapS: Double = 0.1
    /// jumpMinSpeedKmh: the peak Doppler speed before the pop …
    public var minSpeedKmh: Double = 18.0
    /// jumpSpeedWindow, s: … over this span before t0.
    public var speedWindowS: Double = 3.0

    // --- height estimation ---
    /// s(t) is clipped to [0, supportMax] before integrating.
    public var supportMax: Double = 1.0
    /// jumpSupportSigma: the assumed error on the support profile (the dominant term).
    public var supportSigma: Double = 0.1
    /// Heights are clamped here (a jump cannot go down).
    public var minHeightM: Double = 0.0

    public init() {}
}

/// Three estimates of the same jump plus the uncertainty budget of the primary one.
/// Mirrors the lab's `HeightEstimate`.
public struct JumpHeight: Sendable, Equatable {
    /// Primary: z'' = −(1 − s(t))·g simulated over [t0, t1].
    public var integratedM: Double
    /// (1 − s_mean)·g·T²/8.
    public var closedFormM: Double
    /// g·T²/8 — comparison only, never a metric.
    public var naiveM: Double
    public var airtimeS: Double
    public var sMean: Double
    public var sMin: Double
    public var sMax: Double
    /// Initial vertical velocity the profile implies.
    public var v0Mps: Double
    /// Combined 1σ on `integratedM`.
    public var sigmaM: Double
    public var sigmaNoiseM: Double
    public var sigmaProfileM: Double
    public var sigmaTimingM: Double
    public var nSamples: Int
}

/// One accepted jump. Mirrors the lab's `Jump` (without the baro fit).
public struct Jump: Sendable, Equatable {
    /// Airborne window, seconds on the records' base.
    public var tStart: Double
    public var tEnd: Double
    public var height: JumpHeight
    /// Peak raw |a| in the spike window before `tStart`.
    public var takeoffG: Double
    /// Peak raw |a| in the spike window after `tEnd`.
    public var impactG: Double
}

/// Why a low-g span of jump-like duration was not accepted. Raw values are the lab's
/// `JumpCandidate.reason` strings, in gate order.
public enum JumpRejection: String, Sendable, Equatable, CaseIterable {
    case airtimeOverMax = "airtime_over_max"
    case gapInWindow = "gap_in_window"
    case noTakeoffSpike = "no_takeoff_spike"
    case noLandingImpact = "no_landing_impact"
    case offFoil = "off_foil"
    case tooSlow = "too_slow"
    case insideTurn = "inside_turn"
    case refractory = "refractory"
}

/// A span that failed a gate. **Never** called a jump. Mirrors the lab's `JumpCandidate`.
public struct JumpCandidate: Sendable, Equatable {
    public var tStart: Double
    public var tEnd: Double
    public var airtimeS: Double
    public var minG: Double
    public var takeoffG: Double
    public var impactG: Double
    public var reason: JumpRejection
}

/// Mirrors the lab's `JumpResult`.
public struct JumpResult: Sendable, Equatable {
    public var jumps: [Jump] = []
    public var candidates: [JumpCandidate] = []
    public var sampleRateHz: Double = 0
    public var nSamples: Int = 0
    public var notes: [String] = []
}

/// A closed span in seconds on the records' base (a flight's or a turn's start and end).
public typealias JumpSpan = (start: Double, end: Double)

/// Jump detection and height estimation from the wrist accelerometer — a port of the
/// detection and height half of `lab/src/wingfoil_lab/jump.py` (docs/algorithms/jumps.md).
///
/// Takeoff spike → a sustained low-g phase (the airborne window) → a landing impact; then
/// three context gates (the takeoff inside a flight, the rider fast before it, the window
/// outside every turn's sweep) and a refractory dead time. The height is the peak of
/// z'' = −(1 − s(t))·g over the window with z(t0) = z(t1) = 0, where the accelerometer reads
/// the support fraction s(t) directly. Uncalibrated: an estimate on every surface.
public enum JumpDetector {

    public static let g = 9.80665
    /// Per-sample |a| noise of the 2026-08-07 ciq fixture's quiet on-foil spans; sizes the
    /// (sub-dominant) noise term. Mirrors `_ACCEL_SIGMA_DEFAULT`.
    static let accelSigmaDefault = 0.11
    /// √(π/2): a median is ~1.25× less efficient than a mean. Mirrors `MEDIAN_EFFICIENCY`.
    static let medianEfficiency = (Double.pi / 2).squareRoot()
    /// **Hostile-file guard, not a parameter.** The median width follows the stream's own
    /// clock, and a file that claims a microsecond step would ask for a window tens of
    /// thousands wide. A real watch logs at ≤ 100 Hz, where the width is 7; this bound is
    /// two orders above that and never reached by a recording the lab can read either.
    static let maxMedianWidth = 255

    /// Jumps in a parsed source on the given context, or nil when it carries no
    /// accelerometer stream. Mirrors `detect_jumps` with the context handed in (as
    /// `goldens.analyze` does): |a| straight from `raw.accel`, the stream `PumpAnalyzer`
    /// reads, on the records' time base.
    public static func detect(_ raw: RawTrack, config: JumpConfig = JumpConfig(),
                              flightSpans: [JumpSpan]?, turnSpans: [JumpSpan]?,
                              speed: (t: [Double], mps: [Double])?) -> JumpResult? {
        guard !raw.accel.isEmpty else { return nil }
        return detect(times: raw.accel.map(\.t), magnitudes: raw.accel.map(\.magnitudeG),
                      config: config, flightSpans: flightSpans, turnSpans: turnSpans,
                      speed: speed)
    }

    /// The cleaned track's Doppler speed (m/s) on the records' base, for `too_slow`.
    /// Mirrors `clean_speed`.
    public static func cleanSpeed(_ clean: CleanTrack) -> (t: [Double], mps: [Double]) {
        (clean.samples.map(\.t), clean.samples.map(\.dopplerMps))
    }

    /// Jumps in raw (time, |a| in g) samples. Mirrors `detect_jumps_from_arrays` (no baro).
    /// A context gate runs only when its input is given (nil = no gate).
    public static func detect(times t: [Double], magnitudes mag: [Double],
                              config cfg: JumpConfig = JumpConfig(),
                              flightSpans: [JumpSpan]? = nil, turnSpans: [JumpSpan]? = nil,
                              speed: (t: [Double], mps: [Double])? = nil) -> JumpResult {
        var res = JumpResult()
        let n = min(t.count, mag.count)
        res.nSamples = t.count
        if n < 8 {
            res.notes.append("too few accel samples")
            return res
        }
        let t = Array(t.prefix(n)), mag = Array(mag.prefix(n))
        var diffs = [Double](repeating: 0, count: n - 1)
        for i in 1..<n { diffs[i - 1] = t[i] - t[i - 1] }
        let step = median(diffs)
        guard step > 0 else {
            res.notes.append("non-monotonic accel time base")
            return res
        }
        let fs = 1.0 / step
        res.sampleRateHz = (fs * 1000).rounded(.toNearestOrEven) / 1000

        // Python's `round` is round-half-even, so 1.5 samples (0.06 s at 25 Hz) is 2.
        let raw = (cfg.smoothS * fs).rounded(.toNearestOrEven)
        let width = raw.isFinite ? max(1, Int(min(raw, Double(maxMedianWidth)))) : maxMedianWidth
        // A *median*, not a box average: a box drags the takeoff spike's tail into the
        // window and shortens the airtime (h goes as T²).
        let sm = medianSmooth(mag, width: width)

        var lastEnd = -Double.infinity
        for (i0, i1) in bridgedRuns(t, sm, cfg) {
            // Sub-sample crossing refinement: at 25 Hz the half-sample matters.
            let t0 = crossing(t, sm, i0 - 1, i0, cfg.airborneMaxG)
            let t1 = crossing(t, sm, i1, i1 + 1, cfg.airborneMaxG)
            let airtime = t1 - t0
            if airtime < cfg.minAirtimeS { continue }         // chop, arm swing, one sample
            let segT = Array(t[i0...i1]), segM = Array(sm[i0...i1])
            let pre = peakIn(t, mag, t0 - cfg.spikeWindowS, t0)
            let post = peakIn(t, mag, t1, t1 + cfg.spikeWindowS)

            var reason: JumpRejection?
            var maxStep = -Double.infinity
            for i in segT.indices.dropFirst() { maxStep = max(maxStep, segT[i] - segT[i - 1]) }
            if airtime > cfg.maxAirtimeS {
                reason = .airtimeOverMax
            } else if segT.count > 1 && maxStep > max(cfg.maxGapS, 3 * step) {
                reason = .gapInWindow
            } else if pre < cfg.takeoffMinG {
                reason = .noTakeoffSpike
            } else if post < cfg.impactMinG {
                reason = .noLandingImpact
            } else if let spans = flightSpans, !spans.contains(where: { $0.start <= t0 && t0 <= $0.end }) {
                reason = .offFoil
            } else if let speed, peakSpeedKmh(speed, t0, cfg) < cfg.minSpeedKmh {
                reason = .tooSlow
            } else if let spans = turnSpans, spans.contains(where: { $0.start <= t1 && t0 <= $0.end }) {
                reason = .insideTurn
            } else if t0 - lastEnd < cfg.refractoryS {
                reason = .refractory
            }

            if let reason {
                res.candidates.append(JumpCandidate(
                    tStart: t0, tEnd: t1, airtimeS: airtime, minG: segM.min() ?? 0,
                    takeoffG: pre, impactG: post, reason: reason))
                continue
            }
            let height = estimateHeight(segT, segM, airtimeS: airtime, config: cfg, rateHz: fs)
            res.jumps.append(Jump(tStart: t0, tEnd: t1, height: height,
                                  takeoffG: pre, impactG: post))
            lastEnd = t1
        }
        return res
    }

    /// Height from the support profile over one airborne window. Mirrors `estimate_height`.
    /// `airtimeS` is the crossing-refined window length, the timing T² depends on.
    public static func estimateHeight(_ t: [Double], _ mag: [Double], airtimeS: Double? = nil,
                                      config cfg: JumpConfig = JumpConfig(),
                                      rateHz: Double? = nil) -> JumpHeight {
        let T = airtimeS ?? ((t.last ?? 0) - (t.first ?? 0))
        let fs: Double
        if let r = rateHz, r != 0 {
            fs = r
        } else if t.count > 1 {
            fs = 1.0 / median(zip(t.dropFirst(), t).map { $0 - $1 })
        } else {
            fs = 100.0
        }
        let s = mag.map { min(max($0, 0.0), cfg.supportMax) }
        let sMean = s.isEmpty ? 0 : s.reduce(0, +) / Double(s.count)

        let naive = g * T * T / 8.0
        let closed = max(cfg.minHeightM, (1.0 - sMean) * naive)
        let (integrated, v0) = integrateProfile(t, s, T, cfg)

        // dh/ds = −g T²/8 for the whole window; the timing term is dh/dT = 2h/T.
        let sens = naive
        let sigmaNoise = sens * medianEfficiency * accelSigmaDefault
            / Double(max(s.count, 1)).squareRoot()
        let sigmaProfile = sens * cfg.supportSigma
        let sigmaTiming = T > 0 ? 2.0 * integrated / T * (1.0 / fs) : 0.0
        let sigma = (sigmaNoise * sigmaNoise + sigmaProfile * sigmaProfile
                     + sigmaTiming * sigmaTiming).squareRoot()
        return JumpHeight(integratedM: integrated, closedFormM: closed, naiveM: naive,
                          airtimeS: T, sMean: sMean, sMin: s.min() ?? 0, sMax: s.max() ?? 0,
                          v0Mps: v0, sigmaM: sigma, sigmaNoiseM: sigmaNoise,
                          sigmaProfileM: sigmaProfile, sigmaTimingM: sigmaTiming,
                          nSamples: s.count)
    }

    /// Peak of z'' = −(1 − s(t))·g over [0, T] with z(0) = z(T) = 0 → (h, v0). Mirrors
    /// `_integrate_profile`: the boundary condition pins v0, it is never assumed.
    static func integrateProfile(_ t: [Double], _ s: [Double], _ T: Double,
                                 _ cfg: JumpConfig) -> (Double, Double) {
        if s.isEmpty || T <= 0 { return (0, 0) }
        if s.count == 1 {
            let phi = 1.0 - s[0]
            return (max(cfg.minHeightM, phi * g * T * T / 8.0), phi * g * T / 2.0)
        }
        // Samples onto [0, T], stretched to the true window edges.
        let span = t[t.count - 1] - t[0]
        if span <= 0 { return (0, 0) }
        let scale = T / span
        let u = t.map { ($0 - t[0]) * scale }
        let a = s.map { -(1.0 - $0) * g }
        // v(t) = v0 + A(t); z(T) = v0·T + ∫A = 0.
        let A = cumtrapz(a, u)
        let intA = cumtrapz(A, u)
        let v0 = -intA[intA.count - 1] / T
        var zMax = -Double.infinity
        for i in u.indices { zMax = max(zMax, v0 * u[i] + intA[i]) }
        return (max(cfg.minHeightM, zMax), v0)
    }

    /// Cumulative trapezoid, starting at 0. Mirrors `_cumtrapz`.
    static func cumtrapz(_ y: [Double], _ x: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: y.count)
        var acc = 0.0
        for i in y.indices.dropFirst() {
            acc += (y[i] + y[i - 1]) / 2.0 * (x[i] - x[i - 1])
            out[i] = acc
        }
        return out
    }

    /// Centred running median, edge-padded, odd width. Mirrors `_median_smooth`.
    static func medianSmooth(_ x: [Double], width: Int) -> [Double] {
        if width <= 1 || x.isEmpty { return x }
        let w = width | 1
        let pad = w / 2
        let n = x.count
        var out = [Double](repeating: 0, count: n)
        var win = [Double](repeating: 0, count: w)
        for i in 0..<n {
            for k in 0..<w { win[k] = x[min(max(i - pad + k, 0), n - 1)] }
            // Insertion sort: w is 3 at 25 Hz and 7 at 100 Hz.
            for k in 1..<w {
                let v = win[k]
                var j = k - 1
                while j >= 0 && win[j] > v { win[j + 1] = win[j]; j -= 1 }
                win[j + 1] = v
            }
            out[i] = win[pad]
        }
        return out
    }

    /// Low-g runs with short noise excursions bridged. Mirrors `_bridged_runs`.
    static func bridgedRuns(_ t: [Double], _ sm: [Double], _ cfg: JumpConfig) -> [(Int, Int)] {
        let r = runs(sm.map { $0 < cfg.airborneMaxG })
        guard var last = r.first else { return [] }
        var merged: [(Int, Int)] = []
        for (a, b) in r.dropFirst() {
            let (pa, pb) = last
            let between = pb + 1 < a ? sm[(pb + 1)..<a].max() : nil
            if t[a] - t[pb] <= cfg.bridgeS && (between == nil || between! <= cfg.bridgeMaxG) {
                last = (pa, b)
            } else {
                merged.append(last)
                last = (a, b)
            }
        }
        merged.append(last)
        return merged
    }

    /// Inclusive index pairs of the contiguous true runs. Mirrors `_runs`.
    static func runs(_ mask: [Bool]) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        var start: Int?
        for (i, m) in mask.enumerated() {
            if m, start == nil { start = i }
            if !m, let s = start { out.append((s, i - 1)); start = nil }
        }
        if let s = start { out.append((s, mask.count - 1)) }
        return out
    }

    /// Linearly interpolated time `y` crosses `level` between two samples. Mirrors `_crossing`.
    static func crossing(_ t: [Double], _ y: [Double], _ iOut: Int, _ iIn: Int,
                         _ level: Double) -> Double {
        if iOut < 0 || iIn < 0 || iOut >= t.count || iIn >= t.count {
            return t[max(0, min(iIn, t.count - 1))]
        }
        let y0 = y[iOut], y1 = y[iIn]
        if y0 == y1 { return t[iIn] }
        let frac = min(max((y0 - level) / (y0 - y1), 0.0), 1.0)
        return t[iOut] + frac * (t[iIn] - t[iOut])
    }

    /// Peak speed over `jumpSpeedWindow` before the takeoff, km/h; 0 with no sample there.
    /// Mirrors `_peak_speed_kmh`.
    static func peakSpeedKmh(_ speed: (t: [Double], mps: [Double]), _ t0: Double,
                             _ cfg: JumpConfig) -> Double {
        var best: Double?
        for i in speed.t.indices where i < speed.mps.count {
            let st = speed.t[i], v = speed.mps[i]
            guard st >= t0 - cfg.speedWindowS && st <= t0 && v.isFinite else { continue }
            best = max(best ?? v, v)
        }
        return best.map { $0 * 3.6 } ?? 0
    }

    /// Max of `y` over t ∈ [a, b] on a sorted `t`, 0 when empty. Mirrors `_peak_in`
    /// (`searchsorted` left for `a`, right for `b`).
    static func peakIn(_ t: [Double], _ y: [Double], _ a: Double, _ b: Double) -> Double {
        let lo = lowerBound(t) { $0 < a }
        let hi = lowerBound(t) { $0 <= b }
        guard hi > lo else { return 0 }
        return y[lo..<hi].max() ?? 0
    }

    /// First index whose element fails `before` (binary search on a sorted array).
    private static func lowerBound(_ t: [Double], _ before: (Double) -> Bool) -> Int {
        var lo = 0, hi = t.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if before(t[mid]) { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// numpy's median: the mean of the two middle values on an even count.
    static func median(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return .nan }
        let s = v.sorted()
        let m = s.count / 2
        return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
    }
}
