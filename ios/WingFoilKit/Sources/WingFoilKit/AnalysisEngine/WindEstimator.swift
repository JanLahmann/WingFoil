import Foundation

/// Wind-axis estimation parameters (docs/algorithms.md "Wind axis estimation").
/// Mirrors `lab/src/wingfoil_lab/wind.py` `WindConfig`.
public struct WindConfig: Sendable, Equatable {
    /// Below this COG ≠ heading (COAPS caveat).
    public var minSpeedMps: Double = 2.0
    public var binDeg: Double = 10.0
    /// Circular moving-average half-width on the histogram.
    public var smoothDeg: Double = 20.0
    /// Mass window used to refine and weigh a lobe.
    public var lobeHalfWidthDeg: Double = 25.0
    /// Two modes closer than this are one lobe.
    public var minLobeSeparationDeg: Double = 60.0
    /// Above this the bisector is degenerate (pure beam-reach out-and-back).
    public var maxLobeSeparationDeg: Double = 179.0
    public var minDistanceM: Double = 500.0
    /// Below this, turns stay "turn" rather than tack/jibe.
    public var minConfidence: Double = 0.5
    /// Cone around an axis end used for the 180° call.
    public var noGoHalfAngleDeg: Double = 45.0
    /// Both cones emptier than this ⇒ unresolved.
    public var minConeMass: Double = 0.01
    /// Cone asymmetry at/above which the 180° call is certain.
    public var fullMargin: Double = 0.4

    public init() {}
}

/// Wind axis from the course-over-ground distribution.
///
/// Foiling samples only (COG is not heading below ~2 m/s) → distance-weighted circular COG
/// histogram → the two dominant reach lobes → the wind axis is their bisector. The axis is
/// a *line*, so the bisector leaves a 180° ambiguity, resolved by the **no-go zone**: a
/// sailor can hold any downwind course but none within ~45° of the wind, so of the two axis
/// ends the one whose ±45° cone holds (almost) no distance is where the wind blows *from*.
///
/// The up/downwind **speed** asymmetry originally specified for that step is not used: on
/// the whole fixture corpus its sign is inverted (a foil loses apparent wind deep downwind),
/// so it is kept as a diagnostic only. Mirrors `lab/src/wingfoil_lab/wind.py`.
public enum WindEstimator {

    /// Estimate the wind axis, or nil when the COG distribution is not usefully bimodal
    /// (too little foiling, one lobe only, or an exactly opposed pair).
    public static func estimate(_ track: CleanTrack, flights: FlightSegmentation,
                                config: WindConfig = WindConfig()) -> WindEstimate? {
        let courses = foilingCourses(track, flights: flights, config: config)
        let total = courses.weight.reduce(0, +)
        guard total >= config.minDistanceM else { return nil }

        let (centers, hist) = circularHistogram(courses.cog, courses.weight,
                                                binDeg: config.binDeg,
                                                smoothDeg: config.smoothDeg)
        guard let modes = dominantLobes(centers: centers, hist: hist,
                                        minSepDeg: config.minLobeSeparationDeg)
        else { return nil }

        let lobes = [refineLobe(courses, center: modes.0, halfWidth: config.lobeHalfWidthDeg),
                     refineLobe(courses, center: modes.1, halfWidth: config.lobeHalfWidthDeg)]
        let mass = lobes.map { lobeMass(courses, center: $0,
                                        halfWidth: config.lobeHalfWidthDeg) / total }
        let sep = abs(wrap180(lobes[1] - lobes[0]))
        guard sep <= config.maxLobeSeparationDeg else { return nil }

        let bisector = circularMean(lobes, [1, 1])
        let axisConf = axisConfidence(mass: mass, sepDeg: sep, config: config)
        let (dirDeg, margin) = resolve180(courses, bisector: bisector, total: total,
                                          config: config)
        let asym = weightedCorrelation(courses.cog.map { cos(($0 - dirDeg) * .pi / 180) },
                                       courses.speed, courses.weight)
        let conf = config.fullMargin > 0
            ? axisConf * clip01(margin / config.fullMargin) : axisConf

        return WindEstimate(
            dirDeg: dirDeg.truncatingRemainder(dividingBy: 360),
            confidence: conf, source: "estimate",
            axisDeg: dirDeg.truncatingRemainder(dividingBy: 180),
            axisConfidence: axisConf, ambiguityMargin: margin, separationDeg: sep,
            lobesDeg: lobes, lobeMass: mass, speedAsymmetry: asym, distanceM: total,
            usable: conf >= config.minConfidence)
    }

    // MARK: - Sampling

    struct Courses {
        var cog: [Double] = []       // deg, 0..360
        var weight: [Double] = []    // step distance (m)
        var speed: [Double] = []     // Doppler at the step's start sample
    }

    /// Per-step (cog, distance, speed) over foiling steps above the speed floor: one entry
    /// per gap-free 1-sample step whose start sample lies inside a flight.
    static func foilingCourses(_ track: CleanTrack, flights: FlightSegmentation,
                               config: WindConfig) -> Courses {
        var out = Courses()
        let onFoil = foilingMask(track, flights: flights)
        for seg in track.segments where seg.count >= 2 {
            let xs = seg.map { track.samples[$0].x ?? .nan }
            let ys = seg.map { track.samples[$0].y ?? .nan }
            guard xs.contains(where: { !$0.isNaN }) else { continue }
            let u = GP3SCalculator.unwrappedBearings(x: xs, y: ys)
            for k in u.indices {
                let i = seg.lowerBound + k
                guard onFoil[i], track.samples[i].dopplerMps >= config.minSpeedMps else { continue }
                let dx = xs[k + 1] - xs[k], dy = ys[k + 1] - ys[k]
                var deg = u[k].truncatingRemainder(dividingBy: 360)
                if deg < 0 { deg += 360 }
                out.cog.append(deg)
                out.weight.append((dx * dx + dy * dy).squareRoot())
                out.speed.append(track.samples[i].dopplerMps)
            }
        }
        return out
    }

    /// Per clean record: is this sample inside a detected flight?
    static func foilingMask(_ track: CleanTrack, flights: FlightSegmentation) -> [Bool] {
        var mask = [Bool](repeating: false, count: track.samples.count)
        for f in flights.flights {
            for i in track.samples.indices
            where track.samples[i].t >= f.startT && track.samples[i].t <= f.endT {
                mask[i] = true
            }
        }
        return mask
    }

    // MARK: - Histogram

    /// Weighted circular histogram of COG → (bin centers, cyclically smoothed weights).
    static func circularHistogram(_ cog: [Double], _ weight: [Double], binDeg: Double,
                                  smoothDeg: Double) -> ([Double], [Double]) {
        let n = Int((360.0 / binDeg).rounded())
        var hist = [Double](repeating: 0, count: n)
        for (c, w) in zip(cog, weight) {
            var m = c.truncatingRemainder(dividingBy: 360)
            if m < 0 { m += 360 }
            let idx = ((Int(floor(m / binDeg)) % n) + n) % n
            hist[idx] += w
        }
        let half = max(Int((smoothDeg / binDeg).rounded()), 0)
        var centers = [Double](repeating: 0, count: n)
        for i in 0..<n { centers[i] = (Double(i) + 0.5) * binDeg }
        guard half > 0 else { return (centers, hist) }
        var smoothed = [Double](repeating: 0, count: n)
        let width = Double(2 * half + 1)
        for i in 0..<n {
            var sum = 0.0
            for k in -half...half { sum += hist[((i + k) % n + n) % n] }
            smoothed[i] = sum / width
        }
        return (centers, smoothed)
    }

    /// Highest histogram bin, plus the highest bin at least `minSepDeg` away.
    static func dominantLobes(centers: [Double], hist: [Double],
                              minSepDeg: Double) -> (Double, Double)? {
        guard hist.reduce(0, +) > 0 else { return nil }
        var first = 0
        for i in hist.indices where hist[i] > hist[first] { first = i }
        var second = -1
        for i in hist.indices where abs(wrap180(centers[i] - centers[first])) >= minSepDeg {
            if second < 0 || hist[i] > hist[second] { second = i }
        }
        guard second >= 0, hist[second] > 0 else { return nil }
        return (centers[first], centers[second])
    }

    /// Weighted circular mean of the samples inside the lobe window (sub-bin resolution).
    static func refineLobe(_ c: Courses, center: Double, halfWidth: Double) -> Double {
        var deg: [Double] = []
        var w: [Double] = []
        for i in c.cog.indices where abs(wrap180(c.cog[i] - center)) <= halfWidth {
            deg.append(c.cog[i])
            w.append(c.weight[i])
        }
        guard !deg.isEmpty else { return mod360(center) }
        return mod360(circularMean(deg, w))
    }

    static func lobeMass(_ c: Courses, center: Double, halfWidth: Double) -> Double {
        var sum = 0.0
        for i in c.cog.indices where abs(wrap180(c.cog[i] - center)) <= halfWidth {
            sum += c.weight[i]
        }
        return sum
    }

    /// Product of three [0,1] factors: lobe mass, lobe balance, mode separation.
    static func axisConfidence(mass: [Double], sepDeg: Double, config: WindConfig) -> Double {
        let total = mass[0] + mass[1]
        let hi = max(mass[0], mass[1]), lo = min(mass[0], mass[1])
        let balance = hi > 0 ? lo / hi : 0
        let fMass = clip01((total - 0.2) / 0.4)
        let fBalance = clip01(balance / 0.5)
        let fSep = clip01((sepDeg - config.minLobeSeparationDeg) / 20.0)
        return fMass * fBalance * fSep
    }

    /// Pick the axis end the wind blows *from* → (dirDeg, margin ∈ [0,1]).
    /// No-go zone: courses within ~45° of the wind are unsailable while dead downwind is
    /// not, so the emptier of the two end cones is upwind.
    static func resolve180(_ c: Courses, bisector: Double, total: Double,
                           config: WindConfig) -> (Double, Double) {
        let th = config.noGoHalfAngleDeg
        var mA = 0.0, mB = 0.0
        for i in c.cog.indices {
            if abs(wrap180(c.cog[i] - bisector)) <= th { mA += c.weight[i] }
            if abs(wrap180(c.cog[i] - bisector - 180)) <= th { mB += c.weight[i] }
        }
        mA /= total
        mB /= total
        guard mA + mB >= config.minConeMass else { return (mod360(bisector), 0) }
        let dir = mA < mB ? bisector : bisector + 180
        return (mod360(dir), abs(mA - mB) / (mA + mB))
    }

    // MARK: - Math helpers

    static func weightedCorrelation(_ a: [Double], _ b: [Double], _ w: [Double]) -> Double {
        let total = w.reduce(0, +)
        guard total > 0, a.count >= 2 else { return 0 }
        var ma = 0.0, mb = 0.0
        for i in a.indices { ma += w[i] * a[i]; mb += w[i] * b[i] }
        ma /= total
        mb /= total
        var saa = 0.0, sbb = 0.0, sab = 0.0
        for i in a.indices {
            let da = a[i] - ma, db = b[i] - mb
            saa += w[i] * da * da
            sbb += w[i] * db * db
            sab += w[i] * da * db
        }
        let den = (saa * sbb).squareRoot()
        return den > 0 ? sab / den : 0
    }

    static func circularMean(_ deg: [Double], _ weight: [Double]) -> Double {
        var s = 0.0, c = 0.0
        for i in deg.indices {
            let r = deg[i] * .pi / 180
            s += weight[i] * sin(r)
            c += weight[i] * cos(r)
        }
        return mod360(atan2(s, c) * 180 / .pi)
    }

    /// Signed angle difference folded into (-180, 180].
    static func wrap180(_ deg: Double) -> Double {
        var m = (deg + 180).truncatingRemainder(dividingBy: 360)
        if m < 0 { m += 360 }
        return m - 180
    }

    static func mod360(_ deg: Double) -> Double {
        var m = deg.truncatingRemainder(dividingBy: 360)
        if m < 0 { m += 360 }
        return m
    }

    static func clip01(_ v: Double) -> Double { min(max(v, 0), 1) }
}
