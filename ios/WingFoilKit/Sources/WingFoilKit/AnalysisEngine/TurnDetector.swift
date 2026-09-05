import Foundation

/// Turn detection, scoring and wind-axis classification parameters
/// (docs/algorithms.md "Turn detection & classification").
public struct TurnConfig: Sendable, Equatable {
    /// turnMinAngle: net unwrapped COG change.
    public var minAngleDeg: Double = 60.0
    /// turnMaxDuration: window for the net change.
    public var maxDurationS: Double = 8.0
    /// turnPeakRate: at ≥ 1 sample.
    public var peakRateDegS: Double = 25.0
    /// turnContinueRate: edge trim — below this the rider is not turning.
    public var continueRateDegS: Double = 5.0
    /// turnCogSpeedFloor: COG ≠ heading below this (COAPS).
    public var minCogSpeedMps: Double = 2.0
    /// turnMinArc: path travelled across the sweep.
    public var minArcM: Double = 12.0
    /// turnMinRadius: arc ÷ |net angle| in radians.
    public var minRadiusM: Double = 6.0
    /// turnContext: ON_FOIL or ≤ this after a flight.
    public var contextAfterS: Double = 3.0
    /// entrySpeedWindow: max speed before the turn start.
    public var entrySpeedWindowS: Double = 3.0
    /// minSpeedLag: the minimum can land past the sweep's end.
    public var minSpeedLagS: Double = 2.0
    public var successPct: Double = 70.0
    /// The flight config's exit speed (success floor).
    public var foilExitSpeedKmh: Double = 8.0
    /// The flight config's entry speed (recovery floor).
    public var foilEntrySpeedKmh: Double = 12.0
    /// turnStopSpeedFloor: below this the rider is not making way.
    public var stopSpeedFloorMps: Double = 1.0
    public var touchdownMaxStopS: Double = 3.0
    public var fallStopS: Double = 5.0
    /// turnOutcomeLookahead: cap on the tail past the sweep the outcome is judged over.
    public var outcomeLookaheadS: Double = 12.0
    public var recoverPct: Double = 70.0
    public var recoverHoldS: Double = 2.0
    /// turnOutcomeWindow: cap on following the recovery.
    public var outcomeWindowS: Double = 60.0
    /// turnBaroDrop: apparent altitude below the session median that means "submerged".
    public var baroDropM: Double = 25.0

    public init() {}
}

/// Turn classification. `turn` is the golden schema's wording for "no usable wind axis".
public enum TurnKind: String, Sendable, Codable {
    case tack, jibe
    case bearAway = "bear_away"
    case roundUp = "round_up"
    case unclassified = "turn"

    /// tack/jibe (or a plain turn) count in the summaries; course changes do not.
    public var counted: Bool { self == .tack || self == .jibe || self == .unclassified }
}

/// The rider-facing three-way verdict (docs/algorithms.md "Turn outcome").
public enum TurnOutcome: String, Sendable, Codable {
    case flewThrough = "flew_through"
    case touchdown
    case fellIn = "fell_in"
}

/// One detected course change, scored and (given wind) classified.
public struct Turn: Sendable, Equatable {
    public var startT: Double
    public var endT: Double
    /// Time of the speed minimum (maneuver channel).
    public var minT: Double
    public var kind: TurnKind
    /// Signed net COG change (+ = clockwise/starboard).
    public var netDeg: Double
    public var peakRateDegS: Double
    /// "starboard" (clockwise) | "port" (counter-clockwise).
    public var direction: String
    /// Tack sailed *before* the turn: port | starboard | unknown.
    public var side: String
    public var entryKn: Double
    public var minKn: Double
    /// Maneuver channel at the first sample at or after `endT` — the speed the rider came
    /// out of the sweep carrying (docs/algorithms.md "Turn detection & classification").
    public var exitKn: Double = 0
    public var entryKnDoppler: Double
    public var minKnDoppler: Double
    public var score: Double
    public var success: Bool
    public var twaInDeg: Double
    public var twaOutDeg: Double
    /// Path length travelled across the COG sweep.
    public var arcM: Double = 0
    public var chordM: Double = 0
    /// arcM ÷ |netDeg| in radians: how tightly it carved.
    public var radiusM: Double = 0
    public var outcome: TurnOutcome = .flewThrough
    /// The stop landed in the ambiguous 3–5 s band.
    public var borderline = false
    public var offFoilS: Double = 0
    public var stoppedS: Double = 0
    /// Accel: a pump burst inside the outcome window.
    public var pumped = false
    /// Baro: the wrist went under inside the window.
    public var submerged = false
    /// Tail past the sweep the outcome was judged over.
    public var outcomeWindowS: Double = 0
    /// **The clean jibe** (engine ≥ 0.12.0): a counted jibe that carried its speed *and*
    /// flew through — `counted && kind == .jibe && success && outcome == .flewThrough`.
    /// Filled once the outcome is final (`assignOutcomes`), which is why it is stored and
    /// not computed: `success` is known at scoring time, the outcome is not. `borderline`
    /// needs no mention — it only ever rides on a `touchdown`, already excluded here.
    public var clean = false

    public var counted: Bool { kind.counted }
}

/// The three fields overlap resolution reads. Declared so a `Candidate` and a `Turn` can
/// go through the same `dropOverlaps` — the resolution happens before scoring, so both
/// paths see one list.
protocol SweepSpan {
    var startT: Double { get }
    var endT: Double { get }
    var netDeg: Double { get }
}

extension Turn: SweepSpan {}

/// Three-way outcome tally for one family of turns.
public struct OutcomeCounts: Sendable, Codable, Equatable {
    public var flewThrough = 0
    public var touchdown = 0
    public var fellIn = 0
    /// Touchdowns whose stop fell in the ambiguous band.
    public var borderline = 0

    public init() {}

    public var total: Int { flewThrough + touchdown + fellIn }

    mutating func add(_ turn: Turn) {
        switch turn.outcome {
        case .flewThrough: flewThrough += 1
        case .touchdown: touchdown += 1
        case .fellIn: fellIn += 1
        }
        if turn.borderline { borderline += 1 }
    }
}

/// Counts suitable for session fields / goldens (bear-aways excluded by design).
public struct TurnSummary: Sendable, Codable, Equatable {
    public var tacks = 0
    /// Tacks that passed the *score* verdict. Deliberately still `success`: "clean" is a
    /// jibe word in the product, and a tack has no clean/dirty reading to carry.
    public var tacksSuccessful = 0
    public var jibes = 0
    /// **Clean jibes** (engine ≥ 0.12.0): `Turn.clean`, i.e. the score verdict *and*
    /// `flewThrough`. Read by `cleanJibesPerHour` and every "clean" surface; the name is
    /// kept because the golden key `jibesSuccessful` has never moved.
    public var jibesSuccessful = 0
    /// Detected turns with no usable wind axis.
    public var unclassified = 0
    /// tacks + jibes + unclassified (the "attempted" count).
    public var turnsCounted = 0
    public var turnsSuccessful = 0
    /// Of `turnsCounted`.
    public var successPct: Double = 0
    /// Bear-aways / round-ups: real course changes, not maneuvers.
    public var rejected = 0
    public var port = 0
    public var starboard = 0
    public var unknownSide = 0
    /// Longest run of counted turns, in turn-end order, that did not end in `fellIn`.
    public var longestDryStreak = 0
    /// Longest run of counted turns, in turn-end order, that all `flewThrough`.
    public var longestFlewStreak = 0
    public var outcomes = OutcomeCounts()
    public var tackOutcomes = OutcomeCounts()
    public var jibeOutcomes = OutcomeCounts()

    public init() {}
}

/// Turn detection over the cleaned track.
///
/// Per gap-free segment the unwrapped COG is scanned for a net change of at least
/// `turnMinAngle` inside at most `turnMaxDuration` seconds containing a `turnPeakRate`
/// spike; candidates are non-maximum-suppressed, trimmed to the actually-turning part,
/// kept only when they touch a flight (`turnContext`), and then must have **carved an
/// arc** — `turnMinArc` metres of path with an effective radius of at least
/// `turnMinRadius`. A rider swimming beside the board produces heading flips that are
/// indistinguishable from a jibe *in angle terms* while covering almost no water; the
/// gate is deliberately geometric, not another speed floor.
///
/// Mirrors `lab/src/wingfoil_lab/turns.py` (the authoritative reference).
public enum TurnDetector {

    static let mpsToKn = Units.mpsToKn
    static let kmhToMps = 1.0 / 3.6

    /// One accepted sweep, before any wind is applied — the geometry half of a `Turn`.
    ///
    /// Detection is split here so the wind estimator can ask "what sweeps did this session
    /// contain?" without a wind axis (`sweeps`, feeding the default-turn-type prior in
    /// `WindEstimator`) while `detect` builds the very same list into scored turns. The
    /// arrays are the segment's, held by copy-on-write reference: nothing here copies a
    /// track. Mirrors `_Candidate` in `lab/src/wingfoil_lab/turns.py`.
    struct Candidate: SweepSpan {
        let t: [Double], man: [Double], dop: [Double]
        let tu: [Double], u: [Double], rate: [Double]
        let i: Int, j: Int
        let arc: (Double, Double)

        var startT: Double { tu[i] }
        var endT: Double { tu[j] }
        var netDeg: Double { u[j] - u[i] }
        var cogIn: Double { u[i] }
        var cogOut: Double { u[j] }
    }

    /// `evidence` lets the caller hand in the whole-track `OffFoilEvidence` it already
    /// built (the flight-end classifier needs the same arrays); omitted, it is built here.
    public static func detect(_ track: CleanTrack, flights: FlightSegmentation,
                              wind: WindEstimate? = nil, config: TurnConfig = TurnConfig(),
                              pump: PumpTrack? = nil,
                              evidence: OffFoilEvidence? = nil) -> [Turn] {
        var turns = acceptedCandidates(track, flights: flights, config: config).map {
            build($0, wind: wind, config: config)
        }
        assignOutcomes(&turns, track: track, flights: flights, config: config, pump: pump,
                       evidence: evidence)
        return turns
    }

    /// The (COG in, COG out) sweep of every turn `detect` would report, in order.
    ///
    /// Exactly the same scan, non-maximum suppression, on-foil test, carve gate and overlap
    /// resolution — only the scoring and the wind classification are left off, because the
    /// caller (`WindEstimator.turnTypePrior`) has no wind axis yet and needs none: a sweep
    /// plus a candidate direction is enough to say "tack" or "jibe".
    static func sweeps(_ track: CleanTrack, flights: FlightSegmentation,
                       config: TurnConfig) -> [(Double, Double)] {
        acceptedCandidates(track, flights: flights, config: config).map { ($0.cogIn, $0.cogOut) }
    }

    /// Every sweep that survives detection, in time order with overlaps resolved.
    static func acceptedCandidates(_ track: CleanTrack, flights: FlightSegmentation,
                                   config: TurnConfig) -> [Candidate] {
        var cands: [Candidate] = []
        for seg in track.segments where seg.count >= 3 {
            let t = seg.map { track.samples[$0].t }
            let x = seg.map { track.samples[$0].x ?? .nan }
            let y = seg.map { track.samples[$0].y ?? .nan }
            let v = seg.map { track.samples[$0].dopplerMps }
            let man = seg.map { track.samples[$0].hybridMps }
            guard x.contains(where: { !$0.isNaN }) else { continue }

            for (a, b) in sailingRuns(v.map { $0 >= config.minCogSpeedMps }) {
                let u = GP3SCalculator.unwrappedBearings(x: Array(x[a...b]), y: Array(y[a...b]))
                guard !u.isEmpty else { continue }
                let tu = Array(t[a..<(a + u.count)])
                let rate = rates(tu, u)
                for pair in suppress(candidates(tu, u, rate, config)) {
                    let (i, j) = trim(pair.0, pair.1, rate: rate, u: u, config: config)
                    guard onFoil(tu[i], tu[j], flights: flights, config: config) else { continue }
                    let arc = arcAndChord(x, y, lo: a + i, hi: a + j + 1)
                    guard carved(arcM: arc.0, netDeg: u[j] - u[i], config) else { continue }
                    cands.append(Candidate(t: t, man: man, dop: v, tu: tu, u: u, rate: rate,
                                           i: i, j: j, arc: arc))
                }
            }
        }
        // Stable by start time, like numpy's sort in the lab, then overlap-resolved.
        cands = cands.enumerated()
            .sorted { $0.element.startT != $1.element.startT
                        ? $0.element.startT < $1.element.startT : $0.offset < $1.offset }
            .map(\.element)
        return dropOverlaps(cands)
    }

    /// Aggregate detected turns; bear-aways/round-ups only feed `rejected`.
    ///
    /// Every count reads turns alone. `ends` is needed by the **streaks** only, which are a
    /// claim about the rider rather than about the turn channel and so must also see the
    /// losses that happened outside a maneuver (`streaks`).
    public static func summarize(_ turns: [Turn], ends: [FlightEnd] = []) -> TurnSummary {
        var s = TurnSummary()
        for t in turns {
            guard t.counted else { s.rejected += 1; continue }
            switch t.kind {
            case .tack:
                s.tacks += 1
                if t.success { s.tacksSuccessful += 1 }
                s.tackOutcomes.add(t)
            case .jibe:
                s.jibes += 1
                if t.clean { s.jibesSuccessful += 1 }
                s.jibeOutcomes.add(t)
            default:
                s.unclassified += 1
            }
            s.outcomes.add(t)
            s.turnsCounted += 1
            if t.success { s.turnsSuccessful += 1 }
            if t.side == "port" { s.port += 1 }
            if t.side == "starboard" { s.starboard += 1 }
            if t.side == "unknown" { s.unknownSide += 1 }
        }
        s.successPct = s.turnsCounted > 0
            ? 100.0 * Double(s.turnsSuccessful) / Double(s.turnsCounted) : 0
        (s.longestDryStreak, s.longestFlewStreak) = streaks(turns, ends: ends)
        return s
    }

    /// One thing that happened to the rider, from either outcome channel (see `streaks`).
    private struct StreakEvent {
        let t: Double
        let isTurn: Bool
        /// A counted turn carried all the way through — the only thing `flew` extends on.
        /// `borderline` only ever rides on a touchdown, so the flag is redundant against
        /// the outcome today; it is spelled out because a streak is exactly where a "nearly
        /// a fall" must not read as a clean one, whatever a re-tune does to the flag later.
        let flewClean: Bool
        let fellIn: Bool
        let touchdown: Bool
    }

    /// (longest dry streak, longest flown streak) over one merged, time-ordered event list.
    ///
    /// A streak is a claim about *the rider*, not about the turn channel, so it cannot be
    /// read from turn outcomes alone: a swim in a straight line, or one inside a bear-away,
    /// ends a run of clean jibes just as surely as a botched jibe does. The events are
    /// every **counted turn** (at its `endT`, carrying its turn outcome) plus every
    /// **flight end no counted turn owns** — straight-line ends, and ends owned by a
    /// rejected sweep — at its `t`, carrying its flight-end outcome. An end a counted turn
    /// *does* own is excluded: that turn's outcome already speaks for it, and counting both
    /// would charge one swim twice. Truncated ends are dropped — the recording stopped,
    /// which is not evidence that anything happened to the rider.
    ///
    /// Only a counted turn can lengthen a run; a non-turn event can only cut one short.
    /// `dry` is reset by `fellIn` from either channel, `flew` by `fellIn` or `touchdown`
    /// from either channel. `glideOut`/`unknown` change nothing.
    ///
    /// Mirrors `streaks()` in `lab/src/wingfoil_lab/turns.py`.
    public static func streaks(_ turns: [Turn],
                               ends: [FlightEnd] = []) -> (dry: Int, flew: Int) {
        var longestDry = 0, longestFlew = 0, dry = 0, flew = 0
        for ev in streakEvents(turns, ends) {
            if ev.isTurn {
                dry = ev.fellIn ? 0 : dry + 1
                flew = ev.flewClean ? flew + 1 : 0
                longestDry = max(longestDry, dry)
                longestFlew = max(longestFlew, flew)
            } else {
                // Nothing outside a maneuver is a maneuver the rider carried, so a non-turn
                // event never lengthens a run — it can only cut one short.
                if ev.fellIn { dry = 0 }
                if ev.fellIn || ev.touchdown { flew = 0 }
            }
        }
        return (longestDry, longestFlew)
    }

    /// The merged event list a streak walks, in time order. At an identical timestamp the
    /// non-turn event is applied first, so a coincident fall breaks the run rather than
    /// being masked by the turn that would extend it — the conservative reading, and a tie
    /// the ownership window makes unreachable in practice anyway.
    private static func streakEvents(_ turns: [Turn], _ ends: [FlightEnd]) -> [StreakEvent] {
        let counted = Set(turns.indices.filter { turns[$0].counted })
        var events = counted.sorted().map { i -> StreakEvent in
            let turn = turns[i]
            return StreakEvent(t: turn.endT, isTurn: true,
                               flewClean: turn.outcome == .flewThrough && !turn.borderline,
                               fellIn: turn.outcome == .fellIn,
                               touchdown: turn.outcome == .touchdown)
        }
        for end in ends {
            if end.truncated { continue }
            if let owner = end.ownedByTurn, counted.contains(owner) { continue }
            events.append(StreakEvent(t: end.t, isTurn: false, flewClean: false,
                                      fellIn: end.outcome == .fellIn,
                                      touchdown: end.outcome == .touchdown))
        }
        return events.sorted {
            $0.t == $1.t ? (!$0.isTurn && $1.isTurn) : $0.t < $1.t
        }
    }

    // MARK: - Geometry scan

    /// Maximal index runs (a, b) of consecutive true, at least 3 samples long. Below
    /// `turnCogSpeedFloor` the COG is position noise rather than a heading, so a capsize
    /// would otherwise read as a multi-turn spin.
    static func sailingRuns(_ ok: [Bool]) -> [(Int, Int)] {
        var runs: [(Int, Int)] = []
        var start: Int? = nil
        for (i, good) in ok.enumerated() {
            if good, start == nil {
                start = i
            } else if !good, let s = start {
                if i - s >= 3 { runs.append((s, i - 1)) }
                start = nil
            }
        }
        if let s = start, ok.count - s >= 3 { runs.append((s, ok.count - 1)) }
        return runs
    }

    /// Signed COG rate per interval between consecutive bearings (count − 1).
    static func rates(_ tu: [Double], _ u: [Double]) -> [Double] {
        guard u.count >= 2 else { return [] }
        return (1..<u.count).map { k in
            let dt = tu[k] - tu[k - 1]
            return dt > 0 ? (u[k] - u[k - 1]) / dt : 0
        }
    }

    /// Per start index, the largest net COG change reachable within the duration cap;
    /// kept when it clears `minAngleDeg` and contains a `peakRateDegS` sample.
    static func candidates(_ tu: [Double], _ u: [Double], _ rate: [Double],
                           _ config: TurnConfig) -> [(Int, Int, Double)] {
        var out: [(Int, Int, Double)] = []
        let n = u.count
        guard n >= 2 else { return out }
        for i in 0..<(n - 1) {
            let jEnd = searchSortedRight(tu, tu[i] + config.maxDurationS)
            guard jEnd > i + 1 else { continue }
            var k = 0
            var best = abs(u[i + 1] - u[i])
            for m in (i + 1)..<jEnd where abs(u[m] - u[i]) > best {
                best = abs(u[m] - u[i])
                k = m - (i + 1)
            }
            guard best >= config.minAngleDeg else { continue }
            let j = i + 1 + k
            var peak = 0.0
            for r in i..<j where abs(rate[r]) > peak { peak = abs(rate[r]) }
            guard peak >= config.peakRateDegS else { continue }
            out.append((i, j, best))
        }
        return out
    }

    /// Non-maximum suppression: strongest net change first, drop anything overlapping it.
    /// Ties keep detection order (numpy's stable sort).
    static func suppress(_ cands: [(Int, Int, Double)]) -> [(Int, Int)] {
        let order = cands.indices.sorted {
            cands[$0].2 != cands[$1].2 ? cands[$0].2 > cands[$1].2 : $0 < $1
        }
        var taken: [(Int, Int)] = []
        for idx in order {
            let (i, j, _) = cands[idx]
            if taken.contains(where: { i <= $0.1 && $0.0 <= j }) { continue }
            taken.append((i, j))
        }
        return taken.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
    }

    /// Shrink the span to the actually-turning part; revert if that loses the turn.
    static func trim(_ i: Int, _ j: Int, rate: [Double], u: [Double],
                     config: TurnConfig) -> (Int, Int) {
        var a = i, b = j
        while a < b, abs(rate[a]) < config.continueRateDegS { a += 1 }
        while b > a, abs(rate[b - 1]) < config.continueRateDegS { b -= 1 }
        if b <= a || abs(u[b] - u[a]) < config.minAngleDeg { return (i, j) }
        return (a, b)
    }

    /// (path length, straight-line displacement) in metres over the samples [lo, hi].
    /// The COG element `k` describes the step *leaving* sample `k`, so a sweep over COG
    /// elements i…j spans samples i…j+1.
    static func arcAndChord(_ x: [Double], _ y: [Double], lo: Int, hi: Int) -> (Double, Double) {
        let l = max(lo, 0), h = min(hi, x.count - 1)
        guard h > l else { return (0, 0) }
        var arc = 0.0
        for k in (l + 1)...h {
            let dx = x[k] - x[k - 1], dy = y[k] - y[k - 1]
            arc += (dx * dx + dy * dy).squareRoot()
        }
        let cx = x[h] - x[l], cy = y[h] - y[l]
        return (arc, (cx * cx + cy * cy).squareRoot())
    }

    /// The spatial gate: did the rider actually move around the curve? Takes the raw
    /// geometry rather than a built `Turn` so it runs during the scan, before scoring —
    /// `sweeps` needs the same accepted set.
    static func carved(arcM: Double, netDeg: Double, _ config: TurnConfig) -> Bool {
        arcM >= config.minArcM && radius(arcM: arcM, netDeg: netDeg) >= config.minRadiusM
    }

    /// Effective turn radius: path length over the swept angle in radians.
    static func radius(arcM: Double, netDeg: Double) -> Double {
        netDeg != 0 ? arcM / abs(netDeg * .pi / 180) : 0
    }

    /// True when the turn overlaps a flight, or starts within `contextAfterS` of one.
    static func onFoil(_ startT: Double, _ endT: Double, flights: FlightSegmentation,
                       config: TurnConfig) -> Bool {
        flights.flights.contains { startT <= $0.endT + config.contextAfterS && endT >= $0.startT }
    }

    /// Keep the wider-sweeping turn when two detections overlap in time across runs.
    static func dropOverlaps<T: SweepSpan>(_ turns: [T]) -> [T] {
        var out: [T] = []
        for t in turns {
            if let last = out.last, t.startT <= last.endT {
                if abs(t.netDeg) > abs(last.netDeg) { out[out.count - 1] = t }
                continue
            }
            out.append(t)
        }
        return out
    }

    // MARK: - Scoring & classification

    private static func build(_ c: Candidate, wind: WindEstimate?,
                              config: TurnConfig) -> Turn {
        let t = c.t, man = c.man, dop = c.dop, rate = c.rate
        let i = c.i, j = c.j, arc = c.arc
        let startT = c.startT, endT = c.endT
        let net = c.netDeg
        let radiusM = radius(arcM: arc.0, netDeg: net)
        var peak = 0.0
        if j > i {
            for r in i..<j where abs(rate[r]) > abs(peak) { peak = rate[r] }
        }

        // Entry over the window before the start; minimum over the sweep plus the lag.
        var entryMan = -Double.infinity, entryDop = -Double.infinity
        for k in t.indices where t[k] >= startT - config.entrySpeedWindowS && t[k] <= startT {
            entryMan = max(entryMan, man[k])
            entryDop = max(entryDop, dop[k])
        }
        if !entryMan.isFinite {                       // unreachable: startT is a sample time
            let k = min(max(i, 0), t.count - 1)
            entryMan = man[k]
            entryDop = dop[k]
        }
        var minIdx = -1
        var minMan = Double.infinity, minDop = Double.infinity
        for k in t.indices where t[k] >= startT && t[k] <= endT + config.minSpeedLagS {
            if man[k] < minMan { minMan = man[k]; minIdx = k }
            minDop = min(minDop, dop[k])
        }
        // Exit speed: the maneuver channel at the *first sample at or after* the sweep's
        // end. `endT` is itself a sample time, so in practice that is the sweep's last
        // sample — the clamp only guards a track whose segment ends there. Mirrors
        // `_build_turn` in `lab/src/wingfoil_lab/turns.py`.
        let exitMan = man[min(searchSortedLeft(t, endT), t.count - 1)]
        let score = entryMan > 0 ? minMan / entryMan : 0
        let stayedUp = minDop > config.foilExitSpeedKmh * kmhToMps
        let success = score >= config.successPct / 100 && stayedUp

        let k = classify(cogIn: c.cogIn, cogOut: c.cogOut, wind: wind)
        return Turn(startT: startT, endT: endT, minT: t[max(minIdx, 0)], kind: k.kind,
                    netDeg: net, peakRateDegS: peak,
                    direction: net >= 0 ? "starboard" : "port", side: k.side,
                    entryKn: entryMan * mpsToKn, minKn: minMan * mpsToKn,
                    exitKn: exitMan * mpsToKn,
                    entryKnDoppler: entryDop * mpsToKn, minKnDoppler: minDop * mpsToKn,
                    score: score, success: success, twaInDeg: k.twaIn, twaOutDeg: k.twaOut,
                    arcM: arc.0, chordM: arc.1, radiusM: radiusM)
    }

    /// (kind, side, twaIn, twaOut) from the unwrapped COG sweep and the wind estimate.
    /// Without a *usable* wind axis every turn stays unclassified; with one, the naming is
    /// `classifySweep`'s.
    static func classify(cogIn: Double, cogOut: Double, wind: WindEstimate?)
    -> (kind: TurnKind, side: String, twaIn: Double, twaOut: Double) {
        guard let wind, wind.usable else { return (.unclassified, "unknown", .nan, .nan) }
        return classifySweep(cogIn: cogIn, cogOut: cogOut, dirDeg: wind.dirDeg)
    }

    /// (kind, side, twaIn, twaOut) for one sweep against one candidate wind direction.
    ///
    /// The sweep is carried onto TWA unwrapped, so "crosses head-to-wind" is "passes a
    /// multiple of 360" and "crosses dead downwind" is "passes 180 + a multiple of 360".
    /// A sweep wide enough to do both is named after whichever crossing sits nearer its
    /// middle.
    ///
    /// Split out of `classify` because the 180° ambiguity prior in `WindEstimator` has to
    /// name the same sweep under *both* ends of the axis, before either of them is the
    /// wind: flipping `dirDeg` by 180° shifts every TWA by 180°, turning each head-to-wind
    /// crossing into a dead-downwind one and so swapping tack and jibe.
    static func classifySweep(cogIn: Double, cogOut: Double, dirDeg: Double)
    -> (kind: TurnKind, side: String, twaIn: Double, twaOut: Double) {
        let twaIn = WindEstimator.wrap180(cogIn - dirDeg)
        let twaOut = twaIn + (cogOut - cogIn)
        let lo = min(twaIn, twaOut), hi = max(twaIn, twaOut)
        let mid = 0.5 * (lo + hi)
        let head = nearestCrossing(lo: lo, hi: hi, offset: 0, mid: mid)
        let down = nearestCrossing(lo: lo, hi: hi, offset: 180, mid: mid)
        let side = twaIn > 0 ? "port" : "starboard"
        let kind: TurnKind
        if head == nil && down == nil {
            kind = abs(twaOut) > abs(twaIn) ? .bearAway : .roundUp
        } else if down == nil || (head != nil && abs(head! - mid) <= abs(down! - mid)) {
            kind = .tack
        } else {
            kind = .jibe
        }
        return (kind, side, twaIn, WindEstimator.wrap180(twaOut))
    }

    /// The value `offset + 360k` inside [lo, hi] closest to `mid`, if any.
    static func nearestCrossing(lo: Double, hi: Double, offset: Double, mid: Double) -> Double? {
        let k0 = ((lo - offset) / 360).rounded(.down)
        var best: Double?
        for k in [k0, k0 + 1, k0 + 2] {
            let v = offset + 360 * k
            if v >= lo, v <= hi, best == nil || abs(v - mid) < abs(best! - mid) { best = v }
        }
        return best
    }

    // MARK: - Outcomes

    static func assignOutcomes(_ turns: inout [Turn], track: CleanTrack,
                               flights: FlightSegmentation, config: TurnConfig,
                               pump: PumpTrack?, evidence: OffFoilEvidence? = nil) {
        guard let ev = evidence ?? Evidence.build(track, flights: flights,
                                                  exitSpeedKmh: config.foilExitSpeedKmh,
                                                  baroDropM: config.baroDropM) else {
            // No evidence: every turn keeps the `flewThrough` default, but `clean` still
            // has to be filled — a session the ladder cannot judge is not one where every
            // jibe is dirty. Mirrors `_assign_outcomes` in `lab/.../turns.py`.
            for i in turns.indices { turns[i].clean = isClean(turns[i]) }
            return
        }
        for i in turns.indices {
            outcome(&turns[i], ev: ev, config: config, pump: pump)
            turns[i].clean = isClean(turns[i])
        }
    }

    /// **A clean jibe is a counted jibe that carried its speed and flew through** —
    /// `counted && kind == .jibe && success && outcome == .flewThrough` (engine 0.12.0).
    ///
    /// Until 0.12.0 "clean" was `success` alone, deliberately independent of the outcome:
    /// a jibe carved cleanly through the sweep stayed clean even when the foil was lost in
    /// the recovery tail. To a rider that reads as a lie — a jibe held at 71 % that ends in
    /// 54 s of swimming is not one he would call clean — so the outcome joined the verdict.
    /// `success` is untouched: it is still the score verdict, and the Turns tab still shows
    /// it. `borderline` needs no test: it only rides on a `touchdown`, already excluded.
    static func isClean(_ turn: Turn) -> Bool {
        turn.counted && turn.kind == .jibe && turn.success && turn.outcome == .flewThrough
    }

    /// Three-way outcome for one turn (docs/algorithms.md "Turn outcome", steps 0–5).
    ///
    /// Every scan is bounded to the window's index range by binary search: the evidence
    /// arrays span the whole session, and an outcome window is a handful of seconds of it.
    static func outcome(_ turn: inout Turn, ev: OffFoilEvidence, config: TurnConfig,
                        pump: PumpTrack?) {
        let t = ev.t
        let hi = windowEnd(turn, ev: ev, config: config)
        let startT = turn.startT, windowEndT = t[hi]
        turn.outcomeWindowS = max(windowEndT - turn.endT, 0)
        // [first sample at or after startT, last sample at or before windowEndT].
        let lo = searchSortedLeft(t, startT)
        let win = lo..<max(lo, searchSortedRight(t, windowEndT))
        turn.pumped = pump?.isPumping(from: startT, to: windowEndT) ?? false
        turn.submerged = win.contains { ev.submerged[$0] }

        guard let a = win.first(where: { !ev.flying[$0] }) else {
            turn.borderline = false
            turn.offFoilS = 0
            turn.stoppedS = 0
            let marginal = win.contains {
                ev.speed[$0] < config.foilEntrySpeedKmh * kmhToMps
            }
            turn.outcome = (turn.pumped && marginal) ? .touchdown : .flewThrough
            return
        }

        let (b, end) = Evidence.offFoilRun(t: t, flying: ev.flying, a: a,
                                           capT: turn.endT + config.outcomeWindowS)
        turn.offFoilS = Evidence.elapsed(t: t, gap: ev.gap, a: a, b: end)
        turn.stoppedS = Evidence.longestStop(t: t, gap: ev.gap, v: ev.speed, a: a, b: b,
                                             floor: config.stopSpeedFloorMps)
        if turn.submerged || turn.stoppedS > config.fallStopS {
            turn.outcome = .fellIn
            turn.borderline = false
        } else {
            turn.outcome = .touchdown
            turn.borderline = turn.stoppedS > config.touchdownMaxStopS
        }
    }

    /// Last sample index the turn is judged over: recovery, a gap, or the lookahead cap.
    /// Recovery is measured against `turnRecoverPct` of the *turn's* entry speed, floored
    /// at `foilEntrySpeed`, and searched only past the speed minimum.
    static func windowEnd(_ turn: Turn, ev: OffFoilEvidence, config: TurnConfig) -> Int {
        let lo = min(searchSortedLeft(ev.t, turn.startT), ev.count - 1)
        let thr = max(config.recoverPct / 100 * turn.entryKn / mpsToKn,
                      config.foilEntrySpeedKmh * kmhToMps)
        return Evidence.recoveryEnd(t: ev.t, gap: ev.gap, doppler: ev.doppler, lo: lo,
                                    capT: turn.endT + config.outcomeLookaheadS,
                                    afterT: turn.minT, thrMps: thr, holdS: config.recoverHoldS)
    }
}

// MARK: - Search helpers (numpy searchsorted semantics)

/// First index whose value is ≥ `value` (np.searchsorted(..., "left")).
func searchSortedLeft(_ a: [Double], _ value: Double) -> Int {
    var lo = 0, hi = a.count
    while lo < hi {
        let mid = (lo + hi) / 2
        if a[mid] < value { lo = mid + 1 } else { hi = mid }
    }
    return lo
}

/// First index whose value is > `value` (np.searchsorted(..., "right")).
func searchSortedRight(_ a: [Double], _ value: Double) -> Int {
    var lo = 0, hi = a.count
    while lo < hi {
        let mid = (lo + hi) / 2
        if a[mid] <= value { lo = mid + 1 } else { hi = mid }
    }
    return lo
}
