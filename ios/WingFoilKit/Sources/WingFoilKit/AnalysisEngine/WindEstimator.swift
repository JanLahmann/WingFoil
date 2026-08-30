import Foundation

/// The rider's declared turn habit — evidence for the 180° call only
/// (docs/algorithms.md "Default turn type"). Mirrors the `default_turn_type` vocabulary
/// in `lab/src/wingfoil_lab/wind.py`.
public enum DefaultTurnType: String, Sendable, Codable, CaseIterable {
    /// Wingfoilers overwhelmingly jibe — the default.
    case jibes
    case tacks
    /// Prior off: the no-go cone decides alone, exactly as it did before 0.5.0.
    case balanced

    /// Rider-facing wording for the settings picker.
    public var label: String {
        switch self {
        case .jibes: "Mostly jibes (typical)"
        case .tacks: "Mostly tacks"
        case .balanced: "No assumption"
        }
    }
}

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
    /// The rider's declared habit; `.balanced` switches the prior off.
    public var defaultTurnType: DefaultTurnType = .jibes
    /// Cap on the prior's signed evidence contribution.
    public var turnPriorWeight: Double = 0.5

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
/// so it is kept as a diagnostic only.
///
/// The 180° call has a second, *rider-declared* source of evidence: the **default turn
/// type**. Flipping the wind 180° swaps every jibe and tack, so a rider's declared habit is
/// evidence about orientation. It is a prior, not a measurement, so it may only ever break a
/// tie the cone could not — see `turnTypePrior`. Mirrors `lab/src/wingfoil_lab/wind.py`.
public enum WindEstimator {

    /// Estimate the wind axis, or nil when the COG distribution is not usefully bimodal
    /// (too little foiling, one lobe only, or an exactly opposed pair).
    ///
    /// `turnConfig` is the config the *same* pipeline will detect turns with. It is only
    /// read when the default-turn-type prior actually runs (a weak cone margin and a
    /// declared habit), and only to find the same sweeps that pipeline will report.
    public static func estimate(_ track: CleanTrack, flights: FlightSegmentation,
                                config: WindConfig = WindConfig(),
                                turnConfig: TurnConfig = TurnConfig()) -> WindEstimate? {
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
        let (coneDir, margin) = resolve180(courses, bisector: bisector, total: total,
                                           config: config)
        let prior = turnTypePrior(track, flights: flights, coneDir: coneDir,
                                  coneMargin: margin, config: config, turnConfig: turnConfig)
        let dirDeg = coneDir + (prior.flipped ? 180 : 0)
        let asym = weightedCorrelation(courses.cog.map { cos(($0 - dirDeg) * .pi / 180) },
                                       courses.speed, courses.weight)
        let conf = axisConf * prior.certainty

        return WindEstimate(
            dirDeg: mod360(dirDeg),
            confidence: conf, source: "estimate",
            axisDeg: mod360(dirDeg).truncatingRemainder(dividingBy: 180),
            axisConfidence: axisConf, ambiguityMargin: margin, separationDeg: sep,
            lobesDeg: lobes, lobeMass: mass, speedAsymmetry: asym,
            turnTypeMargin: prior.margin, turnTypeDirDeg: prior.favouredDeg,
            turnTypeVotes: prior.votes, priorFlipped: prior.flipped,
            distanceM: total, usable: conf >= config.minConfidence)
    }

    // MARK: - Default-turn-type prior

    /// What the default-turn-type prior did to one 180° call.
    struct Prior {
        /// The [0,1] factor `confidence` is scaled by.
        var certainty: Double
        /// The prior overturned the cone's pick.
        var flipped = false
        /// |default − other| ÷ votes, in [0,1].
        var margin: Double = 0
        /// The axis end the declared habit points at.
        var favouredDeg: Double?
        var votes = 0
    }

    /// Blend the rider's declared turn habit into a *weak* 180° call.
    ///
    /// Flipping the wind 180° shifts every TWA by 180°, so every head-to-wind crossing
    /// becomes a dead-downwind one: the same sweep that is a tack under one end of the axis
    /// is a jibe under the other. A rider who declares "mostly jibes" is therefore stating a
    /// preference between the two ends, and on a session whose no-go cones cannot separate
    /// them that statement is the best evidence left.
    ///
    /// It is a prior, not a measurement, and the blend keeps it in its place:
    ///
    /// * `eCone = clip01(coneMargin / fullMargin)` — the cone's own certainty, exactly the
    ///   factor confidence has always been scaled by. `eCone ≥ 1` means the cone is decisive
    ///   and the prior is **not consulted at all**, so a strong call is untouchable and its
    ///   numbers are bit-identical to the pre-prior engine.
    /// * Only sweeps that come out tack-or-jibe under **both** ends vote — a bear-away is not
    ///   evidence about the wind, and a sweep that is a maneuver under one end only would let
    ///   the prior manufacture its own electorate.
    /// * `mTurn = (nDefault − nOther) / votes` in [−1, 1], signed *toward the cone's pick*.
    /// * `e = eCone + turnPriorWeight · mTurn`; the call is the cone's when `e ≥ 0` and the
    ///   opposite end when `e < 0`, and `certainty = clip01(|e|)` replaces the cone factor.
    ///
    /// With the default weight 0.5 the prior can only overturn a cone margin below half of
    /// `fullMargin`, and only then with a decisive turn-type majority. `balanced`, no votes
    /// and an exact tie all leave the pre-prior result untouched, to the bit.
    static func turnTypePrior(_ track: CleanTrack, flights: FlightSegmentation,
                              coneDir: Double, coneMargin: Double, config: WindConfig,
                              turnConfig: TurnConfig) -> Prior {
        let eCone = config.fullMargin > 0 ? clip01(coneMargin / config.fullMargin) : 1
        guard config.defaultTurnType != .balanced, eCone < 1 else {
            return Prior(certainty: eCone)
        }
        let sweeps = TurnDetector.sweeps(track, flights: flights, config: turnConfig)
        let (nDefault, nOther) = turnTypeVotes(sweeps, coneDir: coneDir,
                                               defaultTurnType: config.defaultTurnType)
        return blend(eCone: eCone, nDefault: nDefault, nOther: nOther, coneDir: coneDir,
                     config: config)
    }

    /// (votes for the declared type, votes against) among `sweeps`, judged at `coneDir`.
    ///
    /// A sweep votes only if it is a tack-or-jibe under **both** ends of the axis. The two
    /// ends give opposite names to every sweep that does vote, so the count against is the
    /// count the flipped orientation would return — one pass answers for both.
    static func turnTypeVotes(_ sweeps: [(Double, Double)], coneDir: Double,
                              defaultTurnType: DefaultTurnType) -> (Int, Int) {
        let wanted: TurnKind = defaultTurnType == .jibes ? .jibe : .tack
        var nDefault = 0, nOther = 0
        for (cogIn, cogOut) in sweeps {
            let here = TurnDetector.classifySweep(cogIn: cogIn, cogOut: cogOut,
                                                  dirDeg: coneDir).kind
            let there = TurnDetector.classifySweep(cogIn: cogIn, cogOut: cogOut,
                                                   dirDeg: coneDir + 180).kind
            guard here == .tack || here == .jibe, there == .tack || there == .jibe else {
                continue
            }
            if here == wanted { nDefault += 1 } else { nOther += 1 }
        }
        return (nDefault, nOther)
    }

    /// The arithmetic of the blend (`turnTypePrior`, and docs/algorithms.md).
    ///
    /// `e = eCone + turnPriorWeight · mTurn` with `mTurn` signed toward the cone's own pick;
    /// the call is the cone's while `e ≥ 0` and the opposite end below that, and
    /// `clip01(|e|)` is the certainty that replaces the cone factor in `confidence`.
    static func blend(eCone: Double, nDefault: Int, nOther: Int, coneDir: Double,
                      config: WindConfig) -> Prior {
        let votes = nDefault + nOther
        guard votes > 0 else { return Prior(certainty: eCone) }
        let mTurn = Double(nDefault - nOther) / Double(votes)
        let favoured: Double? = mTurn == 0 ? nil : mod360(coneDir + (mTurn > 0 ? 0 : 180))
        let e = eCone + config.turnPriorWeight * mTurn
        return Prior(certainty: clip01(abs(e)), flipped: e < 0, margin: abs(mTurn),
                     favouredDeg: favoured, votes: votes)
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
