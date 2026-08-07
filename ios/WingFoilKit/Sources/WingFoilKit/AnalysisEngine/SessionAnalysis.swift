import Foundation

/// Analysis engine version (docs/algorithms.md `ENGINE_VERSION`). Bump on any change
/// that alters outputs — triggers phone re-analysis.
public enum AnalysisEngine {
    public static let version = "0.1.0"
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

    public init(filter: FilterConfig, flight: FlightConfig, records: RecordsConfig) {
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

/// Golden-schema turn (empty in P1 — populated by the phase-2 turn engine).
public struct TurnRecord: Sendable, Codable, Equatable {
    public var ts: Double
    public var type: String        // "jibe" | "tack" | "turn"
    public var entryKn: Double
    public var minKn: Double
    public var score: Double
    public var side: String        // "port" | "starboard" | "unknown"
}

/// Golden-schema wind estimate (nil/null in P1 — phase-2 wind engine).
public struct WindEstimate: Sendable, Codable, Equatable {
    public var dirDeg: Double
    public var confidence: Double
    public var source: String      // "estimate" | "openmeteo" | "user"
}

/// Golden-schema takeoff (empty in P1 — phase-3 pump engine).
public struct TakeoffRecord: Sendable, Codable, Equatable {
    public var startTs: Double
    public var pumps: Int
    public var success: Bool
    public var timeToFoilS: Double
}

public struct SessionSummary: Sendable, Codable, Equatable {
    public var foilTimeS: Double
    public var foilPct: Double
    public var flightCount: Int
    public var longestFlightS: Double
    public var longestFlightM: Double
    public var distanceKm: Double
}

/// The full analysis result — Codable 1:1 against the golden JSON schema in
/// docs/testing.md (camelCase keys verbatim).
public struct SessionAnalysis: Sendable, Codable, Equatable {
    public var engineVersion: String
    public var config: AnalysisConfig
    public var capabilities: AnalysisCapabilities
    public var flights: [FlightRecord]
    public var turns: [TurnRecord]
    public var records: GP3SRecords
    public var wind: WindEstimate?
    public var takeoffs: [TakeoffRecord]
    public var summary: SessionSummary

    enum CodingKeys: String, CodingKey {
        case engineVersion, config, capabilities, flights, turns, records, wind, takeoffs, summary
    }

    public init(engineVersion: String, config: AnalysisConfig, capabilities: AnalysisCapabilities,
                flights: [FlightRecord], turns: [TurnRecord], records: GP3SRecords,
                wind: WindEstimate?, takeoffs: [TakeoffRecord], summary: SessionSummary) {
        self.engineVersion = engineVersion
        self.config = config
        self.capabilities = capabilities
        self.flights = flights
        self.turns = turns
        self.records = records
        self.wind = wind
        self.takeoffs = takeoffs
        self.summary = summary
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        engineVersion = try c.decode(String.self, forKey: .engineVersion)
        config = try c.decode(AnalysisConfig.self, forKey: .config)
        capabilities = try c.decode(AnalysisCapabilities.self, forKey: .capabilities)
        flights = try c.decode([FlightRecord].self, forKey: .flights)
        turns = try c.decode([TurnRecord].self, forKey: .turns)
        records = try c.decode(GP3SRecords.self, forKey: .records)
        wind = try c.decodeIfPresent(WindEstimate.self, forKey: .wind)
        takeoffs = try c.decode([TakeoffRecord].self, forKey: .takeoffs)
        summary = try c.decode(SessionSummary.self, forKey: .summary)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(engineVersion, forKey: .engineVersion)
        try c.encode(config, forKey: .config)
        try c.encode(capabilities, forKey: .capabilities)
        try c.encode(flights, forKey: .flights)
        try c.encode(turns, forKey: .turns)
        try c.encode(records, forKey: .records)
        try c.encode(wind, forKey: .wind)          // explicit null per schema
        try c.encode(takeoffs, forKey: .takeoffs)
        try c.encode(summary, forKey: .summary)
    }
}

/// Assembles the golden-schema result from the pipeline stages.
public enum SessionSummarizer {

    public static func summarize(raw: RawTrack, clean: CleanTrack,
                                 segmentation: FlightSegmentation, records: GP3SRecords,
                                 filterConfig: FilterConfig = FilterConfig(),
                                 flightConfig: FlightConfig = FlightConfig(),
                                 recordsConfig: RecordsConfig = RecordsConfig()) -> SessionAnalysis {
        let longest = segmentation.longest
        let summary = SessionSummary(
            foilTimeS: segmentation.foilTimeS,
            foilPct: segmentation.foilPct,
            flightCount: segmentation.flights.count,
            longestFlightS: longest?.durationS ?? 0,
            longestFlightM: longest?.distM ?? 0,
            distanceKm: records.totalDistanceM / 1000)
        return SessionAnalysis(
            engineVersion: AnalysisEngine.version,
            config: AnalysisConfig(filter: filterConfig, flight: flightConfig, records: recordsConfig),
            capabilities: AnalysisCapabilities(raw.capabilities),
            flights: segmentation.flights.map { FlightRecord($0) },
            turns: [],
            records: records,
            wind: nil,
            takeoffs: [],
            summary: summary)
    }

    /// One-shot pipeline: clean → segment → records → summarize.
    public static func analyze(_ raw: RawTrack,
                               filterConfig: FilterConfig = FilterConfig(),
                               flightConfig: FlightConfig = FlightConfig(),
                               recordsConfig: RecordsConfig = RecordsConfig()) -> SessionAnalysis {
        let clean = TrackCleaner.clean(raw, config: filterConfig)
        let segmentation = FlightSegmenter.segment(clean, config: flightConfig)
        let records = GP3SCalculator.records(for: clean, config: recordsConfig)
        return summarize(raw: raw, clean: clean, segmentation: segmentation, records: records,
                         filterConfig: filterConfig, flightConfig: flightConfig,
                         recordsConfig: recordsConfig)
    }
}
