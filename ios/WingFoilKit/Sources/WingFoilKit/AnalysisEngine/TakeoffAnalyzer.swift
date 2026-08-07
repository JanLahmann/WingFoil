import Foundation

/// Takeoff-analysis parameters (docs/algorithms.md "Takeoff analysis").
public struct TakeoffConfig: Sendable, Equatable {
    /// takeoffMaxRun: cap on the pre-flight window searched back from ON_FOIL.
    public var maxRunS: Double = 30.0
    /// takeoffRiseSlack: wobble allowed in the speed rise.
    public var riseSlackMps: Double = 0.3
    /// takeoffRestSpeed: at rest — the run starts here.
    public var restSpeedMps: Double = 1.0
    /// takeoffAttemptWindow: an attempt stays open this long after its last stroke —
    /// ON_FOIL inside it is that attempt's success, silence past it is failure.
    public var attemptWindowS: Double = 10.0
    /// takeoffMinPreWindow: less visible record than this ⇒ truncated.
    public var minPreWindowS: Double = 3.0
    /// freeTakeoff: fewer strokes ⇒ got up on wind alone.
    public var freeTakeoffStrokes: Int = 3
    public var foilExitSpeedKmh: Double = 8.0
    public var baroDropM: Double = 25.0

    public init() {}
}

/// One flight start, with the run that produced it.
public struct Takeoff: Sendable, Equatable {
    public var flightIndex: Int
    /// The flight's `startT` (ON_FOIL).
    public var t: Double
    /// First stroke or start of the speed rise.
    public var runStartT: Double
    /// runStartT → ON_FOIL (0 when truncated).
    public var durationS: Double = 0
    /// The speed-only part of it (the no-accel metric).
    public var speedRiseS: Double = 0
    /// nil: no accel stream, or truncated.
    public var pumpsToTakeoff: Int?
    public var cadenceSpm: Double?
    /// Doppler at ON_FOIL: what he took off at.
    public var entryKn: Double = 0
    /// Pumping *during* the flight — a separate metric.
    public var inFlightStrokes: Int?
    /// Fewer than `freeTakeoff` strokes: the wind did the work.
    public var free = false
    /// The record does not reach back over the run.
    public var truncated = false
    /// Gap-free record available before the flight start.
    public var preWindowS: Double = 0

    public var judged: Bool { !truncated }
}

/// How a continuous pumping effort ended.
public enum PumpEpisodeOutcome: String, Sendable, Codable {
    /// The episode lies wholly inside a flight: pumping to hold or extend a glide.
    case inFlight = "in_flight"
    /// A flight starts between the first stroke and `takeoffAttemptWindow` after the last.
    case success
    /// The episode lies inside a detected turn's outcome window: the turn's own touchdown.
    case recovery
    /// He pumped a real burst and did not get up.
    case failed
    /// The record does not run gap-free for `takeoffAttemptWindow` past the last stroke.
    case unknown
}

/// One continuous pumping effort, classified exactly once. An episode is one or more bursts
/// of at least `pumpMinStrokes` with less than `takeoffAttemptWindow` of silence between
/// them — four bursts inside a minute of thrashing are one failed attempt, not four.
public struct PumpEpisode: Sendable, Equatable {
    public var startT: Double
    public var endT: Double
    public var strokes: Int
    public var outcome: PumpEpisodeOutcome
    /// Bursts merged into this effort.
    public var bursts: Int = 1
    public var flightIndex: Int?
    public var turnIndex: Int?
    public var lookaheadS: Double = 0

    public var durationS: Double { endT - startT }
}

/// Both halves of the picture: the takeoffs that worked and every burst that tried.
public struct TakeoffAnalysis: Sendable {
    public var takeoffs: [Takeoff] = []
    public var episodes: [PumpEpisode] = []
    public var hasAccel = false
    /// Every detected stroke, bursts and singletons alike.
    public var totalStrokes: Int?
}

/// Session-level takeoff metrics; the first four mirror FIT session fields 35–38.
public struct TakeoffSummary: Sendable, Codable, Equatable {
    /// Field 35: successes + failed attempts.
    public var takeoffAttempts = 0
    /// Field 36: flights — every one is a takeoff that took.
    public var takeoffSuccesses = 0
    /// Field 37 (×0.1 on the wire).
    public var avgPumpsToTakeoff: Double?
    /// Field 38: every stroke in the session.
    public var totalPumpStrokes: Int?
    /// nil without accel: failures are invisible there, and 100 % would be flattering.
    public var successPct: Double?
    public var failedAttempts = 0
    /// Efforts whose lookahead a gap cut short.
    public var unknownAttempts = 0
    /// Pumping back up after a turn: the turn's event.
    public var recoveryEpisodes = 0
    public var inFlightEpisodes = 0
    public var inFlightPumpStrokes: Int?
    /// Flight starts with the run actually in the record.
    public var runsJudged = 0
    public var runsTruncated = 0
    /// Of the judged runs, those under `freeTakeoff` strokes.
    public var freeTakeoffs = 0
    public var pumpedTakeoffs = 0
    public var medianPumpsToTakeoff: Double?
    /// Excludes the free ones.
    public var avgPumpsWhenPumped: Double?
    public var avgTakeoffS: Double?
    public var medianTakeoffS: Double?

    public init() {}
}

/// Takeoff analysis: how every flight *started*, and every attempt that never became one.
///
/// The flight-START analogue of `FlightEndClassifier` and the product's differentiator
/// metric. Flight segmentation says a flight began; this says what it cost to get there —
/// how many strokes, over how long — and how many times the rider pumped and *did not* get
/// up, which no summary built from flights alone can ever see.
///
/// Sources without an accelerometer degrade instead of failing: the run is the speed rise
/// alone, stroke counts are nil, and because their failures are invisible the success rate
/// is nil rather than a flattering 100 %. Mirrors `lab/src/wingfoil_lab/takeoff.py`.
public enum TakeoffAnalyzer {

    public static func analyze(_ track: CleanTrack, flights: FlightSegmentation,
                               turns: [Turn] = [], config: TakeoffConfig = TakeoffConfig(),
                               pump: PumpTrack? = nil) -> TakeoffAnalysis {
        guard let ev = Evidence.build(track, flights: flights,
                                      exitSpeedKmh: config.foilExitSpeedKmh,
                                      baroDropM: config.baroDropM)
        else { return TakeoffAnalysis(hasAccel: pump != nil) }

        var takeoffs: [Takeoff] = []
        var prevEndT = -Double.infinity
        for (i, f) in flights.flights.enumerated() {
            takeoffs.append(takeoff(index: i, flight: f, ev: ev, config: config, pump: pump,
                                    prevEndT: prevEndT))
            prevEndT = f.endT
        }
        let total = pump.map { $0.strokes(from: ev.t[0], to: ev.t[ev.count - 1]).count }
        return TakeoffAnalysis(takeoffs: takeoffs,
                               episodes: episodes(ev: ev, flights: flights, turns: turns,
                                                  config: config, pump: pump),
                               hasAccel: pump != nil, totalStrokes: total)
    }

    /// Session tallies. `takeoffSuccesses` counts *every* flight, truncated runs included:
    /// the flight happened, only the cost of getting into it is unknown. The averages, in
    /// contrast, are taken over the judged runs alone.
    public static func summarize(_ analysis: TakeoffAnalysis) -> TakeoffSummary {
        var s = TakeoffSummary()
        let judged = analysis.takeoffs.filter(\.judged)
        s.takeoffSuccesses = analysis.takeoffs.count
        s.runsJudged = judged.count
        s.runsTruncated = analysis.takeoffs.count - judged.count

        for ep in analysis.episodes {
            switch ep.outcome {
            case .failed: s.failedAttempts += 1
            case .unknown: s.unknownAttempts += 1
            case .recovery: s.recoveryEpisodes += 1
            case .inFlight: s.inFlightEpisodes += 1
            case .success: break
            }
        }
        s.takeoffAttempts = s.takeoffSuccesses + s.failedAttempts
        if analysis.hasAccel, s.takeoffAttempts > 0 {
            s.successPct = 100.0 * Double(s.takeoffSuccesses) / Double(s.takeoffAttempts)
            s.totalPumpStrokes = analysis.totalStrokes
            s.inFlightPumpStrokes = analysis.takeoffs.reduce(0) { $0 + ($1.inFlightStrokes ?? 0) }
        }

        let durations = judged.map(\.durationS)
        s.avgTakeoffS = mean(durations)
        s.medianTakeoffS = medianOf(durations)

        let pumps = judged.compactMap(\.pumpsToTakeoff).map(Double.init)
        if !pumps.isEmpty {
            s.avgPumpsToTakeoff = mean(pumps)
            s.medianPumpsToTakeoff = medianOf(pumps)
            s.freeTakeoffs = judged.filter { $0.pumpsToTakeoff != nil && $0.free }.count
            s.pumpedTakeoffs = pumps.count - s.freeTakeoffs
            s.avgPumpsWhenPumped = mean(judged.filter { $0.pumpsToTakeoff != nil && !$0.free }
                .compactMap(\.pumpsToTakeoff).map(Double.init))
        }
        return s
    }

    // MARK: - The takeoff run

    /// The run behind one flight start: the contiguous pre-flight window of rising speed
    /// *plus* the pump burst that led into it, whichever started earlier.
    private static func takeoff(index: Int, flight: Flight, ev: OffFoilEvidence,
                                config: TakeoffConfig, pump: PumpTrack?,
                                prevEndT: Double) -> Takeoff {
        let t = ev.t
        let lo = min(searchSortedLeft(t, flight.startT), ev.count - 1)
        let segStart = segmentStart(ev, lo)
        let preWindowS = t[lo] - t[segStart]
        var out = Takeoff(flightIndex: index, t: flight.startT, runStartT: t[lo],
                          entryKn: ev.doppler[lo] * Units.mpsToKn, preWindowS: preWindowS)
        if let pump {
            out.inFlightStrokes = burstStrokes(pump, from: flight.startT, to: flight.endT)
        }
        // The flight start sits at (or within a breath of) a segment boundary: the run that
        // produced it is simply not in the recording. Reporting a 1 s takeoff here would be
        // inventing data, so the run is flagged and kept out of every average.
        guard preWindowS >= config.minPreWindowS else {
            out.truncated = true
            return out
        }

        let winStartT = max(flight.startT - config.maxRunS, t[segStart], prevEndT)
        let riseStartT = riseStart(ev, lo: lo, segStart: segStart, winStartT: winStartT,
                                   config: config)
        out.speedRiseS = flight.startT - riseStartT
        out.runStartT = riseStartT
        if let pump {
            if let lead = leadBurst(pump, winStartT: winStartT, startT: flight.startT,
                                    config: config) {
                out.runStartT = min(riseStartT, lead[0])
            }
            out.pumpsToTakeoff = pump.strokes(from: out.runStartT, to: flight.startT).count
            out.free = (out.pumpsToTakeoff ?? 0) < config.freeTakeoffStrokes
        }
        out.durationS = flight.startT - out.runStartT
        if let p = out.pumpsToTakeoff, p > 0, out.durationS > 0 {
            out.cadenceSpm = 60.0 * Double(p) / out.durationS
        }
        return out
    }

    /// Walk back from the flight start while the speed was still climbing toward it: a
    /// sample counts while it is no more than `takeoffRiseSlack` above the slowest sample
    /// seen so far. The walk also stops on the first sample at or below `takeoffRestSpeed`,
    /// which is *kept* as the run start — without it a slack-tolerant walk-back would
    /// swallow the whole rest, because a flat trace is "non-increasing" too.
    private static func riseStart(_ ev: OffFoilEvidence, lo: Int, segStart: Int,
                                  winStartT: Double, config: TakeoffConfig) -> Double {
        var i = lo
        var ref = ev.doppler[lo]
        while i - 1 >= segStart, ev.t[i - 1] >= winStartT {
            let v = ev.doppler[i - 1]
            if v > ref + config.riseSlackMps { break }
            ref = min(ref, v)
            i -= 1
            if v <= config.restSpeedMps { break }
        }
        return ev.t[i]
    }

    /// The burst that led into this flight: the last qualifying one close enough to it.
    private static func leadBurst(_ pump: PumpTrack, winStartT: Double, startT: Double,
                                  config: TakeoffConfig) -> [Double]? {
        for b in pump.bursts(from: winStartT, to: startT).reversed() {
            guard b.count >= pump.config.minStrokes else { continue }
            return b[b.count - 1] >= startT - config.attemptWindowS ? b : nil
        }
        return nil
    }

    /// Strokes in [startT, endT] that belong to a burst of at least `pumpMinStrokes`.
    private static func burstStrokes(_ pump: PumpTrack, from startT: Double,
                                     to endT: Double) -> Int {
        pump.bursts(from: startT, to: endT)
            .filter { $0.count >= pump.config.minStrokes }
            .reduce(0) { $0 + $1.count }
    }

    /// First index of the gap-free segment holding sample `i`.
    private static func segmentStart(_ ev: OffFoilEvidence, _ i: Int) -> Int {
        var j = i
        while j > 0, !ev.gap[j] { j -= 1 }
        return j
    }

    // MARK: - Pumping episodes

    /// Group the qualifying bursts into efforts and classify each exactly once.
    private static func episodes(ev: OffFoilEvidence, flights: FlightSegmentation,
                                 turns: [Turn], config: TakeoffConfig,
                                 pump: PumpTrack?) -> [PumpEpisode] {
        guard let pump, ev.count > 0 else { return [] }
        let bursts = pump.bursts(from: ev.t[0], to: ev.t[ev.count - 1])
            .filter { $0.count >= pump.config.minStrokes }
        return group(bursts, flights: flights, config: config).map {
            classify($0, ev: ev, flights: flights, turns: turns, config: config)
        }
    }

    /// Chain bursts into episodes: silence below `takeoffAttemptWindow` keeps one going.
    /// Two things break a chain whatever the silence — a burst wholly inside a flight (that
    /// is in-flight pumping, a different act), and a flight *starting* between two bursts
    /// (the earlier effort demonstrably worked).
    private static func group(_ bursts: [[Double]], flights: FlightSegmentation,
                              config: TakeoffConfig) -> [PumpEpisode] {
        var out: [PumpEpisode] = []
        for b in bursts {
            let first = b[0], last = b[b.count - 1], n = b.count
            let inFlight = flightContaining(flights, first, last) != nil
            let joins: Bool
            if let prev = out.last {
                joins = !inFlight
                    && flightContaining(flights, prev.startT, prev.endT) == nil
                    && first - prev.endT < config.attemptWindowS
                    && !flightStartsBetween(flights, prev.endT, first)
            } else {
                joins = false
            }
            if !joins {
                out.append(PumpEpisode(startT: first, endT: last, strokes: n, outcome: .failed))
                continue
            }
            out[out.count - 1].endT = last
            out[out.count - 1].strokes += n
            out[out.count - 1].bursts += 1
        }
        return out
    }

    private static func classify(_ episode: PumpEpisode, ev: OffFoilEvidence,
                                 flights: FlightSegmentation, turns: [Turn],
                                 config: TakeoffConfig) -> PumpEpisode {
        var ep = episode
        ep.lookaheadS = lookaheadS(ev, from: ep.endT, cap: config.attemptWindowS)
        if let inside = flightContaining(flights, ep.startT, ep.endT) {
            ep.outcome = .inFlight
            ep.flightIndex = inside
        } else if let produced = flightProduced(flights, ep.startT, ep.endT,
                                                window: config.attemptWindowS) {
            ep.outcome = .success
            ep.flightIndex = produced
        } else if let owner = turnOwner(turns, ep.startT, ep.endT) {
            ep.outcome = .recovery
            ep.turnIndex = owner
        } else if ep.lookaheadS < config.attemptWindowS {
            ep.outcome = .unknown
        }
        return ep
    }

    /// Index of the flight that holds the whole burst — pumping while already flying.
    private static func flightContaining(_ flights: FlightSegmentation, _ first: Double,
                                         _ last: Double) -> Int? {
        flights.flights.firstIndex { $0.startT <= first && last <= $0.endT }
    }

    /// Index of the flight this burst pumped into, if one starts soon enough after it. The
    /// flight may start *during* the effort or up to `takeoffAttemptWindow` after its last
    /// stroke — the accelerating board carries on after the pumping stops.
    private static func flightProduced(_ flights: FlightSegmentation, _ first: Double,
                                       _ last: Double, window: Double) -> Int? {
        flights.flights.firstIndex { first <= $0.startT && $0.startT <= last + window }
    }

    private static func flightStartsBetween(_ flights: FlightSegmentation, _ a: Double,
                                            _ b: Double) -> Bool {
        flights.flights.contains { a < $0.startT && $0.startT <= b }
    }

    /// Index of the turn whose outcome window holds the burst: recovery pumping. The same
    /// window `FlightEndClassifier` assigns ownership over.
    private static func turnOwner(_ turns: [Turn], _ first: Double, _ last: Double) -> Int? {
        turns.firstIndex { $0.startT <= first && last <= $0.endT + $0.outcomeWindowS }
    }

    /// Gap-free recorded time available after `fromT`, capped at `cap`. Zero when the stroke
    /// itself falls inside a recording gap (the accelerometer keeps logging when the GPS
    /// drops out), which is exactly the case where nothing can be concluded.
    private static func lookaheadS(_ ev: OffFoilEvidence, from fromT: Double,
                                   cap: Double) -> Double {
        let t = ev.t
        let i = searchSortedLeft(t, fromT)
        guard i < t.count, !(i > 0 && ev.gap[i]) else { return 0 }
        var j = i
        while t[j] < fromT + cap, j + 1 < t.count, !ev.gap[j + 1] { j += 1 }
        return min(t[j] - fromT, cap)
    }

    // MARK: - Stats

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func medianOf(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : Evidence.median(values)
    }
}
