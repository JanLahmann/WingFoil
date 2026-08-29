import Foundation

/// Analysis engine version (docs/algorithms.md `ENGINE_VERSION`). Bump on any change
/// that alters outputs — triggers phone re-analysis (the archive discards a cached
/// `analysis.json` whose version does not match).
public enum AnalysisEngine {
    /// 0.3.0 adds the `pumpEpisodes` block: the classifier's per-episode verdicts, which
    /// until now only reached the file as tallies. Nothing pre-existing moved, but a stored
    /// analysis written by 0.2.0 has no episodes at all — so it must re-derive rather than
    /// silently present a map with no failed attempts on it.
    ///
    /// 0.4.0 adds `summary.turns.longestDryStreak` / `longestFlewStreak`. Same shape of
    /// change: no pre-existing number moved, but a 0.3.0 document cannot answer "how many
    /// in a row" at all, and a missing streak would decode as 0 — indistinguishable from a
    /// real session where every turn ended wet. It must re-derive.
    public static let version = "0.4.0"
}

/// Echo of the parameters actually used, keyed by their docs/algorithms.md names.
/// Speeds in km/h, holds in s, accel in m/s².
public struct AnalysisConfig: Sendable, Codable, Equatable {
    public var foilEntrySpeed: Double
    public var entryHold: Double
    public var foilExitSpeed: Double
    public var exitHold: Double
    public var minFlightDuration: Double
    public var maxHdop: Double
    public var minSatellites: Int
    public var maxAccel1Hz: Double
    public var gapMinS: Double
    public var gapFactor: Double
    public var alphaProximity: Double
    public var alphaMaxDistance: Double
    // Turn detection & classification
    public var turnMinAngle: Double
    public var turnMaxDuration: Double
    public var turnPeakRate: Double
    public var turnMinArc: Double
    public var turnMinRadius: Double
    public var turnSuccessPct: Double
    // The 3-way outcome ladder (shared by turns and flight ends)
    public var turnStopSpeedFloor: Double
    public var turnTouchdownMaxStop: Double
    public var turnFallStop: Double
    public var turnOutcomeLookahead: Double
    public var turnRecoverPct: Double
    public var turnOutcomeWindow: Double
    public var turnBaroDrop: Double
    // Wind axis
    public var windMinSpeed: Double
    public var windBinDeg: Double
    public var windMinConfidence: Double
    // Pumping
    public var pumpStrokeAmp: Double
    public var pumpMinStrokes: Int
    // Takeoff
    public var takeoffAttemptWindow: Double
    public var freeTakeoff: Int

    public init(filter: FilterConfig, flight: FlightConfig, records: RecordsConfig,
                turn: TurnConfig = TurnConfig(), wind: WindConfig = WindConfig(),
                pump: PumpConfig = PumpConfig(), takeoff: TakeoffConfig = TakeoffConfig()) {
        foilEntrySpeed = flight.foilEntrySpeedKmh
        entryHold = flight.entryHoldS
        foilExitSpeed = flight.foilExitSpeedKmh
        exitHold = flight.exitHoldS
        minFlightDuration = flight.minFlightDurationS
        maxHdop = filter.maxHdop
        minSatellites = filter.minSatellites
        maxAccel1Hz = filter.maxAccelMps2
        gapMinS = filter.gapMinS
        gapFactor = filter.gapFactor
        alphaProximity = records.alphaProximityM
        alphaMaxDistance = records.alphaMaxDistanceM
        turnMinAngle = turn.minAngleDeg
        turnMaxDuration = turn.maxDurationS
        turnPeakRate = turn.peakRateDegS
        turnMinArc = turn.minArcM
        turnMinRadius = turn.minRadiusM
        turnSuccessPct = turn.successPct
        turnStopSpeedFloor = turn.stopSpeedFloorMps
        turnTouchdownMaxStop = turn.touchdownMaxStopS
        turnFallStop = turn.fallStopS
        turnOutcomeLookahead = turn.outcomeLookaheadS
        turnRecoverPct = turn.recoverPct
        turnOutcomeWindow = turn.outcomeWindowS
        turnBaroDrop = turn.baroDropM
        windMinSpeed = wind.minSpeedMps
        windBinDeg = wind.binDeg
        windMinConfidence = wind.minConfidence
        pumpStrokeAmp = pump.strokeAmpG
        pumpMinStrokes = pump.minStrokes
        takeoffAttemptWindow = takeoff.attemptWindowS
        freeTakeoff = takeoff.freeTakeoffStrokes
    }
}

/// Golden-schema `capabilities` object (docs/testing.md).
public struct AnalysisCapabilities: Sendable, Codable, Equatable {
    public var hasDoppler: Bool
    public var hasDevFields: Bool
    public var hasWatchLaps: Bool
    public var hasAccel: Bool
    public var hasHR: Bool
    public var sampleRateHz: Double

    public init(_ caps: SourceCapabilities) {
        hasDoppler = caps.hasSpeed
        hasDevFields = caps.hasDevFields
        hasWatchLaps = caps.hasWatchLaps
        hasAccel = caps.hasAccel
        hasHR = caps.hasHR
        sampleRateHz = caps.sampleRateHz
    }
}

/// Golden-schema flight (internal `Flight` uses startT/endT; JSON uses startTs/endTs).
public struct FlightRecord: Sendable, Codable, Equatable {
    public var startTs: Double
    public var endTs: Double
    public var distM: Double
    public var maxKn: Double
    /// Strokes of the run that produced this flight; nil without accel or when truncated.
    public var takeoffPumps: Int?

    public init(_ flight: Flight, takeoffPumps: Int? = nil) {
        startTs = flight.startT
        endTs = flight.endT
        distM = flight.distM
        maxKn = flight.maxKn
        self.takeoffPumps = takeoffPumps
    }

    enum CodingKeys: String, CodingKey { case startTs, endTs, distM, maxKn, takeoffPumps }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startTs = try c.decode(Double.self, forKey: .startTs)
        endTs = try c.decode(Double.self, forKey: .endTs)
        distM = try c.decode(Double.self, forKey: .distM)
        maxKn = try c.decode(Double.self, forKey: .maxKn)
        takeoffPumps = try c.decodeIfPresent(Int.self, forKey: .takeoffPumps)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(startTs, forKey: .startTs)
        try c.encode(endTs, forKey: .endTs)
        try c.encode(distM, forKey: .distM)
        try c.encode(maxKn, forKey: .maxKn)
        try c.encode(takeoffPumps, forKey: .takeoffPumps)  // explicit null per schema
    }
}

/// Golden-schema turn: the 0.1.0 keys (`ts`/`type`/`entryKn`/`minKn`/`score`/`side`) plus
/// the phase-2 geometry and the three-way outcome.
public struct TurnRecord: Sendable, Codable, Equatable {
    public var ts: Double
    public var endTs: Double
    /// "jibe" | "tack" | "turn" | "bear_away" | "round_up".
    public var type: String
    /// tack/jibe (or a plain turn) count in the summaries; course changes do not.
    public var counted: Bool
    public var entryKn: Double
    public var minKn: Double
    public var score: Double
    public var success: Bool
    /// "port" | "starboard" | "unknown".
    public var side: String
    public var direction: String
    public var netDeg: Double
    public var arcM: Double
    public var radiusM: Double
    /// "flew_through" | "touchdown" | "fell_in".
    public var outcome: String
    public var borderline: Bool
    public var offFoilS: Double
    public var stoppedS: Double
    public var pumped: Bool
    public var submerged: Bool
    public var outcomeWindowS: Double

    public init(_ turn: Turn) {
        ts = turn.startT
        endTs = turn.endT
        type = turn.kind.rawValue
        counted = turn.counted
        entryKn = turn.entryKn
        minKn = turn.minKn
        score = turn.score
        success = turn.success
        side = turn.side
        direction = turn.direction
        netDeg = turn.netDeg
        arcM = turn.arcM
        radiusM = turn.radiusM
        outcome = turn.outcome.rawValue
        borderline = turn.borderline
        offFoilS = turn.offFoilS
        stoppedS = turn.stoppedS
        pumped = turn.pumped
        submerged = turn.submerged
        outcomeWindowS = turn.outcomeWindowS
    }
}

/// Golden-schema flight end (docs/algorithms.md "Flight-end outcome").
public struct FlightEndRecord: Sendable, Codable, Equatable {
    public var flightIndex: Int
    public var ts: Double
    /// "glide_out" | "touchdown" | "fell_in" | "unknown".
    public var outcome: String
    public var borderline: Bool
    public var offFoilS: Double
    public var stoppedS: Double
    public var minKn: Double?
    public var pumped: Bool
    public var submerged: Bool
    public var windowS: Double
    /// The recording ended, not the flight: excluded from every tally.
    public var truncated: Bool
    /// Index of the turn whose outcome window already explains this end.
    public var ownedByTurn: Int?

    public init(_ end: FlightEnd) {
        flightIndex = end.flightIndex
        ts = end.t
        outcome = end.outcome.rawValue
        borderline = end.borderline
        offFoilS = end.offFoilS
        stoppedS = end.stoppedS
        minKn = end.minSpeedMps.flatMap { $0.isFinite ? $0 * Units.mpsToKn : nil }
        pumped = end.pumped
        submerged = end.submerged
        windowS = end.windowS
        truncated = end.truncated
        ownedByTurn = end.ownedByTurn
    }

    enum CodingKeys: String, CodingKey {
        case flightIndex, ts, outcome, borderline, offFoilS, stoppedS, minKn
        case pumped, submerged, windowS, truncated, ownedByTurn
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        flightIndex = try c.decode(Int.self, forKey: .flightIndex)
        ts = try c.decode(Double.self, forKey: .ts)
        outcome = try c.decode(String.self, forKey: .outcome)
        borderline = try c.decode(Bool.self, forKey: .borderline)
        offFoilS = try c.decode(Double.self, forKey: .offFoilS)
        stoppedS = try c.decode(Double.self, forKey: .stoppedS)
        minKn = try c.decodeIfPresent(Double.self, forKey: .minKn)
        pumped = try c.decode(Bool.self, forKey: .pumped)
        submerged = try c.decode(Bool.self, forKey: .submerged)
        windowS = try c.decode(Double.self, forKey: .windowS)
        truncated = try c.decode(Bool.self, forKey: .truncated)
        ownedByTurn = try c.decodeIfPresent(Int.self, forKey: .ownedByTurn)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(flightIndex, forKey: .flightIndex)
        try c.encode(ts, forKey: .ts)
        try c.encode(outcome, forKey: .outcome)
        try c.encode(borderline, forKey: .borderline)
        try c.encode(offFoilS, forKey: .offFoilS)
        try c.encode(stoppedS, forKey: .stoppedS)
        try c.encode(minKn, forKey: .minKn)                 // explicit null
        try c.encode(pumped, forKey: .pumped)
        try c.encode(submerged, forKey: .submerged)
        try c.encode(windowS, forKey: .windowS)
        try c.encode(truncated, forKey: .truncated)
        try c.encode(ownedByTurn, forKey: .ownedByTurn)     // explicit null
    }
}

/// Golden-schema wind estimate. `dirDeg` is the direction the wind blows *from*
/// (0 = north, clockwise). `usable` gates tack/jibe naming — below `windMinConfidence`
/// every turn stays a plain "turn".
public struct WindEstimate: Sendable, Codable, Equatable {
    public var dirDeg: Double
    public var confidence: Double
    /// "estimate" | "openmeteo" | "user".
    public var source: String
    /// Ambiguity-free axis line: `dirDeg` mod 180.
    public var axisDeg: Double
    public var axisConfidence: Double
    /// No-go cone asymmetry backing the 180° call.
    public var ambiguityMargin: Double
    public var separationDeg: Double?
    /// The two reach modes.
    public var lobesDeg: [Double]?
    /// Their share of foiled distance.
    public var lobeMass: [Double]?
    /// Diagnostic only: weighted corr(cos TWA, speed). The corpus runs positive (upwind
    /// faster on a foil), which is why it is not the 180° rule.
    public var speedAsymmetry: Double
    public var distanceM: Double
    public var usable: Bool

    public init(dirDeg: Double, confidence: Double, source: String, axisDeg: Double,
                axisConfidence: Double, ambiguityMargin: Double, separationDeg: Double?,
                lobesDeg: [Double]?, lobeMass: [Double]?, speedAsymmetry: Double,
                distanceM: Double, usable: Bool) {
        self.dirDeg = dirDeg
        self.confidence = confidence
        self.source = source
        self.axisDeg = axisDeg
        self.axisConfidence = axisConfidence
        self.ambiguityMargin = ambiguityMargin
        self.separationDeg = separationDeg
        self.lobesDeg = lobesDeg
        self.lobeMass = lobeMass
        self.speedAsymmetry = speedAsymmetry
        self.distanceM = distanceM
        self.usable = usable
    }

    /// A user- or model-supplied direction (manual always wins over the estimate).
    public init(userDirDeg: Double, source: String = "user") {
        self.init(dirDeg: userDirDeg, confidence: 1, source: source,
                  axisDeg: userDirDeg.truncatingRemainder(dividingBy: 180),
                  axisConfidence: 1, ambiguityMargin: 1, separationDeg: nil,
                  lobesDeg: nil, lobeMass: nil, speedAsymmetry: 0, distanceM: 0, usable: true)
    }
}

/// Golden-schema takeoff: the 0.1.0 keys plus the run detail.
public struct TakeoffRecord: Sendable, Codable, Equatable {
    public var startTs: Double
    public var runStartTs: Double
    /// nil without an accel stream, or when the run is truncated.
    public var pumps: Int?
    /// Always true: the flight demonstrably happened; only its cost can be unknown.
    public var success: Bool
    public var timeToFoilS: Double
    public var speedRiseS: Double
    public var entryKn: Double
    public var cadenceSpm: Double?
    public var inFlightStrokes: Int?
    public var free: Bool
    public var truncated: Bool
    public var preWindowS: Double

    public init(_ takeoff: Takeoff) {
        startTs = takeoff.t
        runStartTs = takeoff.runStartT
        pumps = takeoff.pumpsToTakeoff
        success = true
        timeToFoilS = takeoff.durationS
        speedRiseS = takeoff.speedRiseS
        entryKn = takeoff.entryKn
        cadenceSpm = takeoff.cadenceSpm
        inFlightStrokes = takeoff.inFlightStrokes
        free = takeoff.free
        truncated = takeoff.truncated
        preWindowS = takeoff.preWindowS
    }

    enum CodingKeys: String, CodingKey {
        case startTs, runStartTs, pumps, success, timeToFoilS, speedRiseS, entryKn
        case cadenceSpm, inFlightStrokes, free, truncated, preWindowS
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startTs = try c.decode(Double.self, forKey: .startTs)
        runStartTs = try c.decode(Double.self, forKey: .runStartTs)
        pumps = try c.decodeIfPresent(Int.self, forKey: .pumps)
        success = try c.decode(Bool.self, forKey: .success)
        timeToFoilS = try c.decode(Double.self, forKey: .timeToFoilS)
        speedRiseS = try c.decode(Double.self, forKey: .speedRiseS)
        entryKn = try c.decode(Double.self, forKey: .entryKn)
        cadenceSpm = try c.decodeIfPresent(Double.self, forKey: .cadenceSpm)
        inFlightStrokes = try c.decodeIfPresent(Int.self, forKey: .inFlightStrokes)
        free = try c.decode(Bool.self, forKey: .free)
        truncated = try c.decode(Bool.self, forKey: .truncated)
        preWindowS = try c.decode(Double.self, forKey: .preWindowS)
    }

    /// Explicit nulls for the optional fields, matching the lab's golden JSON: "no accel
    /// stream" and "zero strokes" are different facts and must not collapse to a missing key.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(startTs, forKey: .startTs)
        try c.encode(runStartTs, forKey: .runStartTs)
        try c.encode(pumps, forKey: .pumps)
        try c.encode(success, forKey: .success)
        try c.encode(timeToFoilS, forKey: .timeToFoilS)
        try c.encode(speedRiseS, forKey: .speedRiseS)
        try c.encode(entryKn, forKey: .entryKn)
        try c.encode(cadenceSpm, forKey: .cadenceSpm)
        try c.encode(inFlightStrokes, forKey: .inFlightStrokes)
        try c.encode(free, forKey: .free)
        try c.encode(truncated, forKey: .truncated)
        try c.encode(preWindowS, forKey: .preWindowS)
    }
}

/// Golden-schema pumping episode (docs/algorithms.md "Takeoff analysis", the outcome
/// ladder). One continuous effort, classified exactly once.
///
/// Every outcome is carried, not just `failed`: the summary already counts the five
/// buckets, and what it cannot carry is *when*. A failed attempt with a timestamp can be
/// placed on the map and shaded in the chart; the same attempt as a tally can only be
/// apologized for. Which outcomes a screen draws is presentation's decision.
///
/// `durationS` is deliberately not encoded — it is `endTs - startTs`, and one fact spelled
/// twice is one fact that can drift.
public struct PumpEpisodeRecord: Sendable, Codable, Equatable {
    /// First stroke of the effort.
    public var startTs: Double
    /// Last stroke of the effort.
    public var endTs: Double
    public var strokes: Int
    public var outcome: PumpEpisodeOutcome
    /// Bursts merged into this one effort.
    public var bursts: Int
    /// The flight it produced (`success`) or happened inside (`inFlight`); nil otherwise.
    public var flightIndex: Int?
    /// The turn whose outcome window owns it (`recovery`); nil otherwise.
    public var turnIndex: Int?
    /// Gap-free record available past the last stroke, capped at `takeoffAttemptWindow`.
    public var lookaheadS: Double

    public init(_ episode: PumpEpisode) {
        startTs = episode.startT
        endTs = episode.endT
        strokes = episode.strokes
        outcome = episode.outcome
        bursts = episode.bursts
        flightIndex = episode.flightIndex
        turnIndex = episode.turnIndex
        lookaheadS = episode.lookaheadS
    }

    enum CodingKeys: String, CodingKey {
        case startTs, endTs, strokes, outcome, bursts, flightIndex, turnIndex, lookaheadS
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startTs = try c.decode(Double.self, forKey: .startTs)
        endTs = try c.decode(Double.self, forKey: .endTs)
        strokes = try c.decode(Int.self, forKey: .strokes)
        outcome = try c.decode(PumpEpisodeOutcome.self, forKey: .outcome)
        bursts = try c.decode(Int.self, forKey: .bursts)
        flightIndex = try c.decodeIfPresent(Int.self, forKey: .flightIndex)
        turnIndex = try c.decodeIfPresent(Int.self, forKey: .turnIndex)
        lookaheadS = try c.decode(Double.self, forKey: .lookaheadS)
    }

    /// Explicit nulls for the two indices, matching the lab's golden JSON: "this episode
    /// produced no flight" is a fact, not a missing key.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(startTs, forKey: .startTs)
        try c.encode(endTs, forKey: .endTs)
        try c.encode(strokes, forKey: .strokes)
        try c.encode(outcome, forKey: .outcome)
        try c.encode(bursts, forKey: .bursts)
        try c.encode(flightIndex, forKey: .flightIndex)     // explicit null
        try c.encode(turnIndex, forKey: .turnIndex)         // explicit null
        try c.encode(lookaheadS, forKey: .lookaheadS)
    }
}

public struct SessionSummary: Sendable, Codable, Equatable {
    public var foilTimeS: Double
    public var foilPct: Double
    public var flightCount: Int
    public var longestFlightS: Double
    public var longestFlightM: Double
    public var distanceKm: Double
    public var turns = TurnSummary()
    public var flightEnds = FlightEndSummary()
    public var outcomeSplit = OutcomeSplit()
    public var takeoff = TakeoffSummary()

    public init(foilTimeS: Double, foilPct: Double, flightCount: Int, longestFlightS: Double,
                longestFlightM: Double, distanceKm: Double) {
        self.foilTimeS = foilTimeS
        self.foilPct = foilPct
        self.flightCount = flightCount
        self.longestFlightS = longestFlightS
        self.longestFlightM = longestFlightM
        self.distanceKm = distanceKm
    }
}

/// The full analysis result — Codable 1:1 against the golden JSON schema in
/// docs/testing.md (camelCase keys verbatim).
public struct SessionAnalysis: Sendable, Codable, Equatable {
    public var engineVersion: String
    public var config: AnalysisConfig
    public var capabilities: AnalysisCapabilities
    public var flights: [FlightRecord]
    public var turns: [TurnRecord]
    public var flightEnds: [FlightEndRecord]
    public var records: GP3SRecords
    public var wind: WindEstimate?
    public var takeoffs: [TakeoffRecord]
    /// Every classified pumping effort, in detection (= time) order — the block that gives
    /// the failed attempts a position. Empty rather than absent on a source with no
    /// accelerometer: there were no bursts to classify, which is a fact about the source.
    /// Decoded leniently so a stored `analysis.json` from 0.2.0 still opens; such a row is
    /// stale by `engineVersion` anyway and `reanalyzeStale()` re-derives it.
    public var pumpEpisodes: [PumpEpisodeRecord]
    /// The HR-cost block (docs/algorithms.md "HR cost"). Optional only so a stored
    /// `analysis.json` written before the block existed still decodes; a fresh analysis
    /// always fills it, with `hasHR: false` when the source carries no heart rate.
    public var hr: HrAnalysis?
    public var summary: SessionSummary

    enum CodingKeys: String, CodingKey {
        case engineVersion, config, capabilities, flights, turns, flightEnds
        case records, wind, takeoffs, pumpEpisodes, hr, summary
    }

    public init(engineVersion: String, config: AnalysisConfig, capabilities: AnalysisCapabilities,
                flights: [FlightRecord], turns: [TurnRecord], flightEnds: [FlightEndRecord],
                records: GP3SRecords, wind: WindEstimate?, takeoffs: [TakeoffRecord],
                pumpEpisodes: [PumpEpisodeRecord] = [],
                hr: HrAnalysis? = nil, summary: SessionSummary) {
        self.engineVersion = engineVersion
        self.config = config
        self.capabilities = capabilities
        self.flights = flights
        self.turns = turns
        self.flightEnds = flightEnds
        self.records = records
        self.wind = wind
        self.takeoffs = takeoffs
        self.pumpEpisodes = pumpEpisodes
        self.hr = hr
        self.summary = summary
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        engineVersion = try c.decode(String.self, forKey: .engineVersion)
        config = try c.decode(AnalysisConfig.self, forKey: .config)
        capabilities = try c.decode(AnalysisCapabilities.self, forKey: .capabilities)
        flights = try c.decode([FlightRecord].self, forKey: .flights)
        turns = try c.decode([TurnRecord].self, forKey: .turns)
        flightEnds = try c.decodeIfPresent([FlightEndRecord].self, forKey: .flightEnds) ?? []
        records = try c.decode(GP3SRecords.self, forKey: .records)
        wind = try c.decodeIfPresent(WindEstimate.self, forKey: .wind)
        takeoffs = try c.decode([TakeoffRecord].self, forKey: .takeoffs)
        pumpEpisodes = try c.decodeIfPresent([PumpEpisodeRecord].self,
                                             forKey: .pumpEpisodes) ?? []
        hr = try c.decodeIfPresent(HrAnalysis.self, forKey: .hr)
        summary = try c.decode(SessionSummary.self, forKey: .summary)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(engineVersion, forKey: .engineVersion)
        try c.encode(config, forKey: .config)
        try c.encode(capabilities, forKey: .capabilities)
        try c.encode(flights, forKey: .flights)
        try c.encode(turns, forKey: .turns)
        try c.encode(flightEnds, forKey: .flightEnds)
        try c.encode(records, forKey: .records)
        try c.encode(wind, forKey: .wind)          // explicit null per schema
        try c.encode(takeoffs, forKey: .takeoffs)
        try c.encode(pumpEpisodes, forKey: .pumpEpisodes)
        try c.encode(hr, forKey: .hr)              // explicit null per schema
        try c.encode(summary, forKey: .summary)
    }
}

/// Assembles the golden-schema result from the pipeline stages.
public enum SessionSummarizer {

    /// One-shot pipeline (docs/plan.md §3.3): clean → flights → records → wind → turns →
    /// flight ends → takeoffs → HR cost → summarize. Every stage degrades with the source:
    /// no accel ⇒ nil stroke counts and no pump corroboration, no barometer ⇒ no submersion
    /// evidence, no heart rate ⇒ `hr.hasHR: false`, Smart-Recording truncation ⇒ `unknown`
    /// outcomes excluded from tallies.
    public static func analyze(_ raw: RawTrack,
                               filterConfig: FilterConfig = FilterConfig(),
                               flightConfig: FlightConfig = FlightConfig(),
                               recordsConfig: RecordsConfig = RecordsConfig(),
                               turnConfig: TurnConfig = TurnConfig(),
                               windConfig: WindConfig = WindConfig(),
                               flightEndConfig: FlightEndConfig = FlightEndConfig(),
                               pumpConfig: PumpConfig = PumpConfig(),
                               takeoffConfig: TakeoffConfig = TakeoffConfig(),
                               hrConfig: HrConfig = HrConfig()) -> SessionAnalysis {
        let clean = TrackCleaner.clean(raw, config: filterConfig)
        let segmentation = FlightSegmenter.segment(clean, config: flightConfig)
        let records = GP3SCalculator.records(for: clean, config: recordsConfig)
        let wind = WindEstimator.estimate(clean, flights: segmentation, config: windConfig)
        let pump = PumpAnalyzer.track(raw, config: pumpConfig)
        // The turn ladder and the flight-end ladder read the same three channels of the
        // same track, so the whole-track evidence is built once here and handed to both.
        // It is only shared while both configs agree on the two parameters it is built
        // from — a caller that tunes them apart still gets one build per stage.
        let evidence = Evidence.build(clean, flights: segmentation,
                                      exitSpeedKmh: turnConfig.foilExitSpeedKmh,
                                      baroDropM: turnConfig.baroDropM)
        let sharable = flightEndConfig.foilExitSpeedKmh == turnConfig.foilExitSpeedKmh
            && flightEndConfig.baroDropM == turnConfig.baroDropM
        let turns = TurnDetector.detect(clean, flights: segmentation, wind: wind,
                                        config: turnConfig, pump: pump, evidence: evidence)
        let ends = FlightEndClassifier.classify(clean, flights: segmentation, turns: turns,
                                                config: flightEndConfig, pump: pump,
                                                evidence: sharable ? evidence : nil)
        let takeoffs = TakeoffAnalyzer.analyze(clean, flights: segmentation, turns: turns,
                                               config: takeoffConfig, pump: pump)
        // HR is the one channel read from the *raw* samples rather than the cleaned track,
        // and it joins to three earlier phases at once (runs, ends, turns) — so it runs last.
        let hr = HrCost.analyze(raw, flights: segmentation, takeoffs: takeoffs,
                                flightEnds: ends, pump: pump, turns: turns, config: hrConfig)

        // `ends` because the streaks span both channels: a straight-line swim ends a run of
        // clean turns too (docs/algorithms.md "Turn streaks").
        let turnSummary = TurnDetector.summarize(turns, ends: ends)
        let endSummary = FlightEndClassifier.summarize(ends)
        let longest = segmentation.longest
        var summary = SessionSummary(
            foilTimeS: segmentation.foilTimeS,
            foilPct: segmentation.foilPct,
            flightCount: segmentation.flights.count,
            longestFlightS: longest?.durationS ?? 0,
            longestFlightM: segmentation.flights.map(\.distM).max() ?? 0,
            distanceKm: records.totalDistanceM / 1000)
        summary.turns = turnSummary
        summary.flightEnds = endSummary
        summary.outcomeSplit = FlightEndClassifier.split(turns: turnSummary, ends: endSummary)
        summary.takeoff = TakeoffAnalyzer.summarize(takeoffs)

        var pumpsByFlight = [Int?](repeating: nil, count: segmentation.flights.count)
        for t in takeoffs.takeoffs where segmentation.flights.indices.contains(t.flightIndex) {
            pumpsByFlight[t.flightIndex] = t.pumpsToTakeoff
        }

        return SessionAnalysis(
            engineVersion: AnalysisEngine.version,
            config: AnalysisConfig(filter: filterConfig, flight: flightConfig,
                                   records: recordsConfig, turn: turnConfig, wind: windConfig,
                                   pump: pumpConfig, takeoff: takeoffConfig),
            capabilities: AnalysisCapabilities(raw.capabilities),
            flights: segmentation.flights.enumerated().map {
                FlightRecord($0.element, takeoffPumps: pumpsByFlight[$0.offset])
            },
            turns: turns.map(TurnRecord.init),
            flightEnds: ends.map(FlightEndRecord.init),
            records: records,
            wind: wind,
            takeoffs: takeoffs.takeoffs.map(TakeoffRecord.init),
            pumpEpisodes: takeoffs.episodes.map(PumpEpisodeRecord.init),
            hr: hr,
            summary: summary)
    }
}
