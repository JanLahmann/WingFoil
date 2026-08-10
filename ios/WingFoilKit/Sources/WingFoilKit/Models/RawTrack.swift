import Foundation

/// One 1 Hz sample from the FIT record stream. Times are seconds from session start.
public struct RecordSample: Sendable, Equatable {
    public var t: Double
    public var timestamp: Date
    public var lat: Double?
    public var lon: Double?
    /// Device speed channel in m/s (Doppler-based on Garmin; `enhanced_speed` preferred).
    public var speedMps: Double?
    public var heartRate: Double?
    public var distanceM: Double?
    public var altitudeM: Double?
    /// Our developer fields when present (source class a) — see docs/fit-schema.md.
    public var foilState: Int?
    public var flightIndex: Int?
    public var pumpCadence: Int?
    public var turnMarker: Int?
    /// Rolling 0–255 counter; its only job is to defeat smart-recording collapse.
    public var tick: Int?

    public init(t: Double, timestamp: Date) {
        self.t = t
        self.timestamp = timestamp
    }
}

/// What channels a parsed source actually provides. Drives graceful degradation
/// (docs/plan.md §3.3: source classes a/b/c).
public struct SourceCapabilities: Sendable, Equatable {
    public var hasSpeed = false
    public var hasPosition = false
    public var hasDevFields = false
    public var hasWatchLaps = false
    public var hasAccel = false
    public var hasHR = false
    public var sampleRateHz: Double = 0
    /// FIT session sport (raw name or number as string, e.g. "windsurfing" / "43").
    public var sport: String?
    /// Session dev field `discipline` (e.g. "wingfoil") — authoritative discipline tag.
    public var discipline: String?

    public var sourceClass: String {
        if hasDevFields { return "a" }
        if hasSpeed { return "b" }
        return "c"
    }

    public init() {}
}

public struct LapInfo: Sendable, Equatable {
    public var startT: Double
    public var totalTimeS: Double?
    public var distanceM: Double?
    public var maxSpeedMps: Double?
    public var avgSpeedMps: Double?
    /// Dev fields (docs/fit-schema.md lap 10–16), when present.
    public var lapType: Int?
    public var flightNum: Int?
    public var takeoffPumps: Int?
    public var takeoffTimeS: Double?
    public var pumpStrokes: Int?
    public var turnCount: Int?
    public var bestTurnScorePct: Double?

    public init(startT: Double) { self.startT = startT }
}

/// What the *watch* reported at save time — the session developer fields of
/// docs/fit-schema.md (ids 20–43), present only for source class (a).
///
/// This is not an input to the analysis pipeline: the phone's own `SessionSummarizer`
/// stays authoritative (docs/fit-schema.md, "watch lap boundaries are hints"). It is kept
/// so the watch-vs-phone divergence can be checked, and so `cfg_*` echoes reveal which
/// thresholds the watch actually ran with.
public struct WatchSummary: Sendable, Equatable {
    /// Authoritative discipline tag, e.g. "wingfoil" — *not* the FIT sport code.
    public var discipline: String?
    public var foilTimeS: Double?
    public var foilPct: Double?
    public var flightCount: Int?
    public var longestFlightS: Double?
    public var longestFlightM: Double?
    /// Speeds arrive as uint16 cm/s on the wire; exposed here in m/s like the rest of the model.
    public var best2sMps: Double?
    public var best10sMps: Double?
    public var best5x10sMps: Double?
    public var best500mMps: Double?
    public var bestNmMps: Double?
    public var alpha500LiteMps: Double?
    public var tackCount: Int?
    public var jibeCount: Int?
    public var turnSuccessPct: Double?
    public var takeoffAttempts: Int?
    public var takeoffSuccesses: Int?
    /// Strokes, already un-scaled from the wire's ×0.1 encoding.
    public var avgPumpsToTakeoff: Double?
    public var totalPumpStrokes: Int?
    public var windDirUserDeg: Double?
    public var cfgEntrySpeedMps: Double?
    public var cfgExitSpeedMps: Double?
    public var cfgMinFlightS: Double?
    public var appVersion: Int?

    /// Low byte of `app_version` — the docs/fit-schema.md `SCHEMA_VERSION` the watch wrote.
    public var schemaVersion: Int? { appVersion.map { $0 & 0xFF } }
    public var isEmpty: Bool { self == WatchSummary() }

    public init() {}
}

/// One wrist-accelerometer sample from the CIQ SensorLogging stream (~100 Hz, batched
/// 25 to an `accelerometer_data` message). `t` is on the *record* time base, so pump
/// analysis and the speed channels share one clock. Only the magnitude is kept: the
/// detector is orientation-free by construction (docs/algorithms.md "Pumping"), the
/// wrist rotates constantly, and 400 k samples of three axes would be dead weight.
public struct AccelSample: Sendable, Equatable {
    public var t: Double
    /// |a| in g (Garmin writes milli-g in a field the profile labels "g" — the parser
    /// sniffs the scale from the resting magnitude rather than assuming).
    public var magnitudeG: Double

    public init(t: Double, magnitudeG: Double) {
        self.t = t
        self.magnitudeG = magnitudeG
    }
}

/// Parsed-but-unanalyzed session: the input to the analysis pipeline.
public struct RawTrack: Sendable {
    public var sourceURL: URL?
    public var startDate: Date?
    public var samples: [RecordSample] = []
    public var laps: [LapInfo] = []
    public var capabilities = SourceCapabilities()
    /// The watch's own summary, when this is one of our class-(a) recordings.
    public var watchSummary = WatchSummary()
    /// Wrist accelerometer, time-sorted; empty for every source without the stream.
    public var accel: [AccelSample] = []

    public init() {}
}

public enum Units {
    public static let mpsToKn = 1.9438445
    public static let mpsToKmh = 3.6
}
