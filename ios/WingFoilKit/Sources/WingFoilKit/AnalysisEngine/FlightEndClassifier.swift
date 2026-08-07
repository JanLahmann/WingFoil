import Foundation

/// Flight-end thresholds (docs/algorithms.md "Flight-end outcome"). Deliberately the *same
/// numbers* as the turn ladder — one physical question ("did the rider stop, and for how
/// long") deserves one set of thresholds however the loss started. They are separate fields
/// only so a future tuning pass can move one end without the other.
public struct FlightEndConfig: Sendable, Equatable {
    public var stopSpeedFloorMps: Double = 1.0
    public var touchdownMaxStopS: Double = 3.0
    public var fallStopS: Double = 5.0
    public var baroDropM: Double = 25.0
    public var foilExitSpeedKmh: Double = 8.0
    public var foilEntrySpeedKmh: Double = 12.0
    /// entrySpeedWindow: the speed the flight was ending at.
    public var entrySpeedWindowS: Double = 3.0
    public var recoverPct: Double = 70.0
    public var recoverHoldS: Double = 2.0
    public var outcomeLookaheadS: Double = 12.0
    public var outcomeWindowS: Double = 60.0

    public init() {}
}

/// What happened when the rider came off the foil in a straight line.
public enum FlightEndOutcome: String, Sendable, Codable {
    /// Came off the foil and kept making way — never reached `turnStopSpeedFloor`.
    case glideOut = "glide_out"
    /// Came off and came to rest, briefly.
    case touchdown
    /// Stopped longer than `turnFallStop`, or the barometer says the wrist went under.
    case fellIn = "fell_in"
    /// The **recording** ended, not the flight: no evidence at all. Excluded from tallies.
    case unknown
}

/// One flight ending, with its verdict and the evidence behind it.
public struct FlightEnd: Sendable, Equatable {
    public var flightIndex: Int
    /// The flight's `endT` (first sub-exit sample).
    public var t: Double
    public var outcome: FlightEndOutcome
    public var borderline = false
    public var offFoilS: Double = 0
    public var stoppedS: Double = 0
    /// Slowest sample in the off-foil run; nil when the run was never entered.
    public var minSpeedMps: Double?
    public var pumped = false
    public var submerged = false
    /// Evidence actually available past the flight end.
    public var windowS: Double = 0
    /// The recording ended, not the flight.
    public var truncated = false
    /// Index into the turn list, when a turn's outcome window already explains this.
    public var ownedByTurn: Int?

    public var inTurn: Bool { ownedByTurn != nil }
}

/// Four-way tally for one family of flight ends.
public struct FlightEndCounts: Sendable, Codable, Equatable {
    public var glideOut = 0
    public var touchdown = 0
    public var fellIn = 0
    /// Truncated by a recording gap — evidence-free.
    public var unknown = 0
    public var borderline = 0

    public init() {}

    /// Flight ends with usable evidence — `unknown` is deliberately not counted.
    public var total: Int { glideOut + touchdown + fellIn }

    mutating func add(_ end: FlightEnd) {
        switch end.outcome {
        case .glideOut: glideOut += 1
        case .touchdown: touchdown += 1
        case .fellIn: fellIn += 1
        case .unknown: unknown += 1
        }
        if end.borderline { borderline += 1 }
    }
}

/// Every flight end, split by whether a turn already owns it.
public struct FlightEndSummary: Sendable, Codable, Equatable {
    public var all = FlightEndCounts()
    /// Not inside any detected turn's outcome window.
    public var straight = FlightEndCounts()
    public var inTurn = FlightEndCounts()

    public init() {}

    enum CodingKeys: String, CodingKey { case all, straight, inTurn }
}

/// The rider-facing session split: where did the falls and touchdowns happen?
public struct OutcomeSplit: Sendable, Codable, Equatable {
    public var turnFalls = 0
    public var straightFalls = 0
    public var turnTouchdowns = 0
    public var straightTouchdowns = 0
    public var glideOuts = 0
    /// Flight ends truncated by a gap: nothing can be said.
    public var unknownEnds = 0

    public init() {}

    public var falls: Int { turnFalls + straightFalls }
    public var touchdowns: Int { turnTouchdowns + straightTouchdowns }
}

/// Classifies every flight ending with the *same three-channel evidence ladder* the turns
/// use (`Evidence`, docs/algorithms.md "Turn outcome" steps 0–4). Only the leaf verdicts
/// differ, because a flight end is by definition already off the foil — there is no
/// `flew_through`.
///
/// **Ownership.** A flight end inside a detected turn's outcome window is *that turn's*
/// event, already counted there: it is flagged and kept out of the straight-line tallies.
/// Without this rule every jibe ending in a swim would be counted twice. Ownership is
/// tested against *every* detected turn, bear-aways included.
///
/// Mirrors `lab/src/wingfoil_lab/flightend.py`.
public enum FlightEndClassifier {

    static let kmhToMps = 1.0 / 3.6

    public static func classify(_ track: CleanTrack, flights: FlightSegmentation,
                                turns: [Turn] = [], config: FlightEndConfig = FlightEndConfig(),
                                pump: PumpTrack? = nil) -> [FlightEnd] {
        guard let ev = Evidence.build(track, flights: flights,
                                      exitSpeedKmh: config.foilExitSpeedKmh,
                                      baroDropM: config.baroDropM) else { return [] }
        var ends = flights.flights.enumerated().map {
            classifyOne(index: $0.offset, endT: $0.element.endT, ev: ev, config: config,
                        pump: pump)
        }
        assignOwnership(&ends, turns: turns)
        return ends
    }

    /// Tally all flight ends and split them into turn-owned and straight-line.
    public static func summarize(_ ends: [FlightEnd]) -> FlightEndSummary {
        var s = FlightEndSummary()
        for end in ends {
            s.all.add(end)
            if end.inTurn { s.inTurn.add(end) } else { s.straight.add(end) }
        }
        return s
    }

    /// Combine the two channels into the falls/touchdowns split for a session summary.
    public static func split(turns: TurnSummary, ends: FlightEndSummary) -> OutcomeSplit {
        var s = OutcomeSplit()
        s.turnFalls = turns.outcomes.fellIn
        s.straightFalls = ends.straight.fellIn
        s.turnTouchdowns = turns.outcomes.touchdown
        s.straightTouchdowns = ends.straight.touchdown
        s.glideOuts = ends.straight.glideOut
        s.unknownEnds = ends.all.unknown
        return s
    }

    // MARK: - The ladder

    private static func classifyOne(index: Int, endT: Double, ev: OffFoilEvidence,
                                    config: FlightEndConfig, pump: PumpTrack?) -> FlightEnd {
        let t = ev.t
        let lo = min(searchSortedLeft(t, endT), ev.count - 1)
        // The segment ends here, so the flight machine never saw an exit: the *recording*
        // stopped mid-flight. Nothing after it is evidence about anything.
        if lo + 1 >= ev.count || ev.gap[lo + 1] {
            return FlightEnd(flightIndex: index, t: endT, outcome: .unknown, truncated: true)
        }
        let hi = Evidence.recoveryEnd(t: t, gap: ev.gap, doppler: ev.doppler, lo: lo,
                                      capT: endT + config.outcomeLookaheadS, afterT: endT,
                                      thrMps: recoverThreshold(ev, endT: endT, config: config),
                                      holdS: config.recoverHoldS)
        var end = FlightEnd(flightIndex: index, t: endT, outcome: .glideOut,
                            windowS: max(t[hi] - endT, 0))
        let inWindow = { (k: Int) in t[k] >= endT && t[k] <= t[hi] }
        end.pumped = pump?.isPumping(from: endT, to: t[hi]) ?? false
        end.submerged = t.indices.contains { inWindow($0) && ev.submerged[$0] }

        if let a = t.indices.first(where: { inWindow($0) && !ev.flying[$0] }) {
            let (b, last) = Evidence.offFoilRun(t: t, flying: ev.flying, a: a,
                                                capT: endT + config.outcomeWindowS)
            end.offFoilS = Evidence.elapsed(t: t, gap: ev.gap, a: a, b: last)
            end.stoppedS = Evidence.longestStop(t: t, gap: ev.gap, v: ev.speed, a: a, b: b,
                                                floor: config.stopSpeedFloorMps)
            var lowest = Double.infinity
            for k in a...b { lowest = min(lowest, ev.speed[k]) }
            end.minSpeedMps = lowest
        }

        if end.submerged || end.stoppedS > config.fallStopS {
            end.outcome = .fellIn
        } else if (end.minSpeedMps ?? .infinity) < config.stopSpeedFloorMps {
            end.outcome = .touchdown
            end.borderline = end.stoppedS > config.touchdownMaxStopS
        } else if end.pumped, marginal(ev, inWindow: inWindow, config: config) {
            // Same corroboration rule as the turns: accel promotes only when the speed
            // channels also went marginal. At a flight end that test is nearly vacuous —
            // and that is intended: a rider who has to pump a burst out of it did not
            // glide out by choice, he touched down.
            end.outcome = .touchdown
        }
        return end
    }

    /// Doppler that means "flying again": `recoverPct` of the speed the flight was carrying,
    /// read over `entrySpeedWindow` *before* the end — not the flight's peak, which would
    /// demand 17 kn back after a 25 kn run. Floored at `foilEntrySpeed`.
    private static func recoverThreshold(_ ev: OffFoilEvidence, endT: Double,
                                         config: FlightEndConfig) -> Double {
        var entry = -Double.infinity
        for k in ev.t.indices
        where ev.t[k] >= endT - config.entrySpeedWindowS && ev.t[k] <= endT {
            entry = max(entry, ev.doppler[k])
        }
        if !entry.isFinite { entry = 0 }
        return max(config.recoverPct / 100 * entry, config.foilEntrySpeedKmh * kmhToMps)
    }

    private static func marginal(_ ev: OffFoilEvidence, inWindow: (Int) -> Bool,
                                 config: FlightEndConfig) -> Bool {
        ev.t.indices.contains {
            inWindow($0) && ev.speed[$0] < config.foilEntrySpeedKmh * kmhToMps
        }
    }

    /// Flag each flight end that falls inside a turn's outcome window. A turn's window runs
    /// from `startT` to `endT + outcomeWindowS` (the tail its outcome was actually judged
    /// over, not the lookahead cap), so the two channels agree by construction.
    private static func assignOwnership(_ ends: inout [FlightEnd], turns: [Turn]) {
        for i in ends.indices {
            for (k, turn) in turns.enumerated()
            where turn.startT <= ends[i].t && ends[i].t <= turn.endT + turn.outcomeWindowS {
                ends[i].ownedByTurn = k
                break
            }
        }
    }
}
