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
    ///
    /// 0.5.0 adds the **default-turn-type prior** (docs/algorithms.md "Default turn type"):
    /// `config.windDefaultTurnType`, and the evidence trail it leaves on the wind object.
    /// Unlike the three bumps above this one *can* move pre-existing numbers — a session
    /// whose no-go cones nearly tie can now have its wind direction resolved the other way,
    /// taking every tack/jibe label with it — which is exactly why a stored document must
    /// re-derive rather than be read as if the rider had never declared a habit.
    ///
    /// 0.6.0 adds the **session rate metrics** (docs/algorithms.md "Session rates"):
    /// `summary.durationS` / `avgSpeedKmh` / `turnsPerHour` / `jibesPerHour` / `wetPerHour`
    /// (`cleanJibesPerHour` joins them in 0.10.0).
    /// Nothing pre-existing moves — they are arithmetic over numbers the summary already
    /// carried — but a 0.5.0 document cannot answer "how busy was that hour" at all, and a
    /// missing rate decoded as 0 would claim a session with no jibes in it.
    ///
    /// 0.7.0 reworks that block twice (docs/algorithms.md "Session rates"). `jibesPerHour`
    /// now counts **dry** jibes — `turns.jibes - turns.jibeOutcomes.fellIn` — so the number
    /// a rider reads as the measure of his afternoon stops counting the jibes he swam out
    /// of; unlike the four bumps above, this one *moves* a value every stored document
    /// already carries, which is precisely why it must re-derive. And `summary.windowRates`
    /// adds the rolling 15-minute view of the same two events (`config.windowRateMin`): the
    /// busiest quarter of an hour, which a session average cannot say.
    ///
    /// 0.8.0 fixes the **session total** (docs/algorithms.md "The session total").
    /// `summary.takeoff.totalPumpStrokes` was the one pump metric that skipped
    /// `pumpMinStrokes`, so it reported the raw output of the peak picker — and chop, it
    /// turns out, runs at pumping cadence and clears `pumpStrokeAmp` at its crests, so a
    /// flight contributed roughly one "stroke" per chop crest. On the bundled example that
    /// read 286 against a hand count of ~26. Like 0.7.0's `jibesPerHour`, this *moves* a
    /// value every stored document already carries, which is why it must re-derive.
    ///
    /// 0.8.1 finishes that job. 0.8.0 left `inFlightStrokes` on the burst-length rule alone,
    /// so the bundled example reported a session total of 31 beside an in-flight 60 — a part
    /// larger than its whole, because the in-flight window is precisely where the chop lives.
    /// The in-flight count now takes the same `pumpBurstPeakG` gate (60 → 5 there), and the
    /// total is a superset of its parts again. Another value that moves under stored
    /// documents, so again: re-derive.
    ///
    /// 0.8.2 moves no metric at all — it adds one: the session's own UTC offset
    /// (`RawTrack.startUtcOffsetS`, `meta.utcOffsetS`, `session.startUtcOffsetS`), so that
    /// a session's times read the way the rider saw them rather than the way the reader's
    /// device would render the same instant (docs/presentation.md, "Session time"). The
    /// analysis numbers are byte-identical to 0.8.1's; the bump is here because the
    /// document gained a field and stored rows have to pick it up.
    ///
    /// 0.9.0 moves no metric either — it opens a door. **GPX** now reaches the pipeline
    /// (`GpxSessionParser`, docs/plan.md's input class (c)), and it arrives honestly
    /// labelled: a GPX carries no speed channel, so its speed is differentiated from
    /// positions and `capabilities.hasDoppler` is false, which is what `sourceClass` "c"
    /// and every "uncertified" surface downstream already read. Pump strokes, failed
    /// attempts and the episode list degrade to their accel-less nulls and empties exactly
    /// as they already do on a native FIT. Existing sessions re-derive to numbers identical
    /// to 0.8.2's; the bump is what makes them re-derive at all, and what keeps a stored
    /// document from claiming an engine that could not have read half the corpus.
    ///
    /// 0.9.1 moves no metric either, and adds one field for an honesty reason. The
    /// UTC-offset ladder 0.8.2 built never recorded **which rung answered**
    /// (`RawTrack.startUtcOffsetSource`, `session.startUtcOffsetSource` on schema v8,
    /// `meta.utcOffsetSource`), so a page printed "times as recorded on the water" over an
    /// offset that might be `round(lon / 15°)` — the *solar* offset, an hour out under DST.
    /// 0.9.0's GPX door made that the common case rather than the exotic one, because a GPX
    /// usually states no zone at all. The ladder is unchanged; what was missing was the
    /// qualification, and a stored 0.9.0 document cannot supply it retroactively, which is
    /// what the bump is for (docs/presentation.md, "Session time").
    ///
    /// 0.10.0 adds one field and moves no other: `summary.cleanJibesPerHour`
    /// (docs/algorithms.md "Session rates"), the rate over the **strict** verdict —
    /// `turns.jibesSuccessful` over the same elapsed hour every other rate divides by. It is
    /// arithmetic over a count the summary has always carried, so every stored number
    /// re-derives identical; what a 0.9.1 document cannot do is answer the question the
    /// rider actually asks. JPH says he got away with the jibe, CPH says he rode it, and CPH
    /// is what the key-metrics block prints from here on (docs/presentation.md, "Clean
    /// jibe"). A missing rate decoded as 0 would claim a session with no clean jibes in it,
    /// which is why the bump — and the null — are both here.
    ///
    /// 0.11.0 moves no number and adds five per-turn fields: `minTs`, `exitKn`,
    /// `peakRateDegS`, `twaInDeg`, `twaOutDeg`. Every one of them is something
    /// `TurnDetector` has computed since 0.1.0 and then dropped — the stored record kept a
    /// turn's two endpoints, so a per-turn page could say a jibe went 11.1 → 7.5 kn but not
    /// *when* the bottom was, what the rider came out carrying, how hard it was carved, or
    /// where the wind stood at either end. `exitKn` is the one new definition
    /// (docs/algorithms.md): the maneuver channel at the first sample at or after `endTs`,
    /// the same channel `minKn` is read on. The TWA pair is nil without a usable wind axis,
    /// because a 0 there would read as dead upwind. Every stored session re-derives to
    /// identical numbers; the bump is what makes them re-derive at all, and what stops a
    /// 0.10.0 document from answering a question it has no fields for.
    ///
    /// 0.12.0 narrows **the clean jibe**, and it is the first bump here that moves numbers
    /// on purpose. Clean was the per-turn `success` flag alone — the score verdict,
    /// deliberately independent of how the turn *ended* — so a jibe could be starred as
    /// clean and still be one the rider swam out of. It now reads `counted && type ==
    /// "jibe" && success && outcome == "flew_through"`, which is what a rider means by the
    /// word. Each turn carries it as a new `clean` key beside `success`, and
    /// `turns.jibesSuccessful` — hence `summary.cleanJibesPerHour` — counts `clean`.
    /// `success` is unchanged and still per turn; `tacksSuccessful`/`turnsSuccessful` still
    /// read it, because "clean" is a jibe word. Nothing else moves: no parameter, no
    /// detection, no score, no outcome, no streak (the streaks already ran on the outcome).
    public static let version = "0.12.0"
}

/// Session-rate parameters (docs/algorithms.md "Session rates"). Mirrors the lab's
/// `RateConfig`.
public struct RatesConfig: Sendable, Equatable {
    /// The rolling window the per-hour series is measured over. 15 minutes is long enough
    /// that one jibe cannot dominate it, short enough to separate the hour the wind filled
    /// in from the hour it did not.
    public var windowRateMin: Double = 15
    /// How finely the same function is sampled *for the file* — not a tuning knob, and
    /// never where the peak is read from.
    public var gridS: Double = 60

    public init() {}
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
    /// The rider's declared turn habit, feeding the 180° prior. Optional only so a stored
    /// `analysis.json` from 0.4.0 still decodes; such a row re-derives on its version.
    public var windDefaultTurnType: DefaultTurnType?
    // Pumping
    public var pumpStrokeAmp: Double
    public var pumpMinStrokes: Int
    /// The two session-total gates (engine 0.8.0). Optional only so a stored
    /// `analysis.json` from 0.7.0 still decodes; such a row re-derives on its version.
    public var pumpBurstPeakG: Double?
    public var pumpMinSpeedKmh: Double?
    // Takeoff
    public var takeoffAttemptWindow: Double
    public var freeTakeoff: Int
    // Session rates
    /// The rolling-rate window, in minutes. Optional only so a stored `analysis.json` from
    /// 0.6.0 still decodes; such a row re-derives on its version.
    public var windowRateMin: Double?

    public init(filter: FilterConfig, flight: FlightConfig, records: RecordsConfig,
                turn: TurnConfig = TurnConfig(), wind: WindConfig = WindConfig(),
                pump: PumpConfig = PumpConfig(), takeoff: TakeoffConfig = TakeoffConfig(),
                rates: RatesConfig = RatesConfig()) {
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
        windDefaultTurnType = wind.defaultTurnType
        pumpStrokeAmp = pump.strokeAmpG
        pumpMinStrokes = pump.minStrokes
        pumpBurstPeakG = pump.burstPeakG
        pumpMinSpeedKmh = pump.minSpeedKmh
        takeoffAttemptWindow = takeoff.attemptWindowS
        freeTakeoff = takeoff.freeTakeoffStrokes
        windowRateMin = rates.windowRateMin
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
/// the phase-2 geometry, the three-way outcome, the 0.11.0 shape-of-the-maneuver fields
/// (`minTs`, `exitKn`, `peakRateDegS`, `twaInDeg`, `twaOutDeg`) — all five computed by the
/// detector since 0.1.0 and, until then, thrown away — and 0.12.0's `clean`.
public struct TurnRecord: Sendable, Codable, Equatable {
    public var ts: Double
    public var endTs: Double
    /// Time of the speed minimum, on the session clock like `ts`/`endTs` (engine 0.11.0).
    public var minTs: Double
    /// "jibe" | "tack" | "turn" | "bear_away" | "round_up".
    public var type: String
    /// tack/jibe (or a plain turn) count in the summaries; course changes do not.
    public var counted: Bool
    public var entryKn: Double
    public var minKn: Double
    /// Maneuver channel at the first sample at or after `endTs` — the same channel and
    /// scale as `minKn`, so entry → min → exit reads as one line (engine 0.11.0).
    public var exitKn: Double
    public var score: Double
    /// The score verdict alone: `score >= turnSuccessPct` and the foil held across the
    /// *scored window*. Still shown per turn; it is no longer what "clean" means.
    public var success: Bool
    /// **The clean jibe** (engine 0.12.0): `counted && type == "jibe" && success &&
    /// outcome == "flew_through"`.
    public var clean: Bool
    /// "port" | "starboard" | "unknown".
    public var side: String
    public var direction: String
    public var netDeg: Double
    /// Signed peak COG rate, + = clockwise/starboard like `netDeg` (engine 0.11.0).
    public var peakRateDegS: Double
    /// True wind angle entering the sweep — **nil** without a usable wind axis, which is
    /// "no wind was known", never a 0 that would read as dead upwind (engine 0.11.0).
    public var twaInDeg: Double?
    /// True wind angle leaving the sweep; nil under the same rule as `twaInDeg`.
    public var twaOutDeg: Double?
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
        minTs = turn.minT
        type = turn.kind.rawValue
        counted = turn.counted
        entryKn = turn.entryKn
        minKn = turn.minKn
        exitKn = turn.exitKn
        score = turn.score
        success = turn.success
        clean = turn.clean
        side = turn.side
        direction = turn.direction
        netDeg = turn.netDeg
        peakRateDegS = turn.peakRateDegS
        twaInDeg = turn.twaInDeg.isFinite ? turn.twaInDeg : nil
        twaOutDeg = turn.twaOutDeg.isFinite ? turn.twaOutDeg : nil
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

    enum CodingKeys: String, CodingKey {
        case ts, endTs, minTs, type, counted, entryKn, minKn, exitKn, score, success, clean
        case side, direction, netDeg, peakRateDegS, twaInDeg, twaOutDeg, arcM, radiusM
        case outcome, borderline, offFoilS, stoppedS, pumped, submerged, outcomeWindowS
    }

    /// The 0.11.0 keys decode as *optional*, so an `analysis.json` written by an older
    /// engine still loads rather than throwing. Such a document is stale by `engineVersion`
    /// anyway and `reanalyzeStale()` re-derives it from the FIT with the real numbers; the
    /// fallbacks below only have to survive the trip between the two, which is why the two
    /// speeds fall back to the endpoints beside them and the TWA pair falls back to nil.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ts = try c.decode(Double.self, forKey: .ts)
        endTs = try c.decode(Double.self, forKey: .endTs)
        type = try c.decode(String.self, forKey: .type)
        counted = try c.decode(Bool.self, forKey: .counted)
        entryKn = try c.decode(Double.self, forKey: .entryKn)
        minKn = try c.decode(Double.self, forKey: .minKn)
        score = try c.decode(Double.self, forKey: .score)
        success = try c.decode(Bool.self, forKey: .success)
        side = try c.decode(String.self, forKey: .side)
        direction = try c.decode(String.self, forKey: .direction)
        netDeg = try c.decode(Double.self, forKey: .netDeg)
        arcM = try c.decode(Double.self, forKey: .arcM)
        radiusM = try c.decode(Double.self, forKey: .radiusM)
        outcome = try c.decode(String.self, forKey: .outcome)
        borderline = try c.decode(Bool.self, forKey: .borderline)
        offFoilS = try c.decode(Double.self, forKey: .offFoilS)
        stoppedS = try c.decode(Double.self, forKey: .stoppedS)
        pumped = try c.decode(Bool.self, forKey: .pumped)
        submerged = try c.decode(Bool.self, forKey: .submerged)
        outcomeWindowS = try c.decode(Double.self, forKey: .outcomeWindowS)
        minTs = try c.decodeIfPresent(Double.self, forKey: .minTs) ?? ts
        exitKn = try c.decodeIfPresent(Double.self, forKey: .exitKn) ?? minKn
        peakRateDegS = try c.decodeIfPresent(Double.self, forKey: .peakRateDegS) ?? 0
        // 0.12.0: absent in a pre-0.12.0 document, where "clean" meant `success` and the
        // verdict cannot be reconstructed without the outcome ladder anyway. `false` is the
        // honest fallback for the trip to `reanalyzeStale()`, which the version bump forces.
        // Absent, derive it from the fields that define it rather than default to false:
        // between 5 and 6 Sep 2026 the encoder below forgot the key, so every document
        // written by builds 23–25 came back with no clean jibe in it after a relaunch
        // (the tally was right — it was counted in memory and stored as a number — while
        // the turn sheet's chip and the ghost, which read the record, said "not clean").
        // The rule is the engine's own (`TurnDetector.isClean`), so deriving is exact.
        clean = try c.decodeIfPresent(Bool.self, forKey: .clean)
            ?? (counted && type == "jibe" && success && outcome == "flew_through")
        twaInDeg = try c.decodeIfPresent(Double.self, forKey: .twaInDeg)
        twaOutDeg = try c.decodeIfPresent(Double.self, forKey: .twaOutDeg)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ts, forKey: .ts)
        try c.encode(endTs, forKey: .endTs)
        try c.encode(minTs, forKey: .minTs)
        try c.encode(type, forKey: .type)
        try c.encode(counted, forKey: .counted)
        try c.encode(entryKn, forKey: .entryKn)
        try c.encode(minKn, forKey: .minKn)
        try c.encode(exitKn, forKey: .exitKn)
        try c.encode(score, forKey: .score)
        try c.encode(success, forKey: .success)
        try c.encode(clean, forKey: .clean)
        try c.encode(side, forKey: .side)
        try c.encode(direction, forKey: .direction)
        try c.encode(netDeg, forKey: .netDeg)
        try c.encode(peakRateDegS, forKey: .peakRateDegS)
        try c.encode(twaInDeg, forKey: .twaInDeg)           // explicit null
        try c.encode(twaOutDeg, forKey: .twaOutDeg)         // explicit null
        try c.encode(arcM, forKey: .arcM)
        try c.encode(radiusM, forKey: .radiusM)
        try c.encode(outcome, forKey: .outcome)
        try c.encode(borderline, forKey: .borderline)
        try c.encode(offFoilS, forKey: .offFoilS)
        try c.encode(stoppedS, forKey: .stoppedS)
        try c.encode(pumped, forKey: .pumped)
        try c.encode(submerged, forKey: .submerged)
        try c.encode(outcomeWindowS, forKey: .outcomeWindowS)
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
    /// The default-turn-type prior's evidence trail (docs/algorithms.md "Default turn
    /// type"): |default − other| ÷ votes, the strength of the rider's declared majority.
    public var turnTypeMargin: Double
    /// The axis end the declared habit favours. Nil when the prior did not run (`balanced`,
    /// or a cone margin at/above `windFullMargin`) or found no sweep that is a maneuver
    /// under both ends — which is not the same statement as a margin of 0.
    public var turnTypeDirDeg: Double?
    /// Sweeps that were tack-or-jibe under **both** ends of the axis.
    public var turnTypeVotes: Int
    /// The prior overturned the no-go-cone call.
    public var priorFlipped: Bool
    public var distanceM: Double
    public var usable: Bool

    public init(dirDeg: Double, confidence: Double, source: String, axisDeg: Double,
                axisConfidence: Double, ambiguityMargin: Double, separationDeg: Double?,
                lobesDeg: [Double]?, lobeMass: [Double]?, speedAsymmetry: Double,
                turnTypeMargin: Double = 0, turnTypeDirDeg: Double? = nil,
                turnTypeVotes: Int = 0, priorFlipped: Bool = false,
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
        self.turnTypeMargin = turnTypeMargin
        self.turnTypeDirDeg = turnTypeDirDeg
        self.turnTypeVotes = turnTypeVotes
        self.priorFlipped = priorFlipped
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

    enum CodingKeys: String, CodingKey {
        case dirDeg, confidence, source, axisDeg, axisConfidence, ambiguityMargin
        case separationDeg, lobesDeg, lobeMass, speedAsymmetry
        case turnTypeMargin, turnTypeDirDeg, turnTypeVotes, priorFlipped
        case distanceM, usable
    }

    /// The four prior fields decode leniently so a stored `analysis.json` from 0.4.0 still
    /// opens; such a row is stale by `engineVersion` anyway and `reanalyzeStale()` re-derives
    /// it (which is the whole point of the bump — the prior *can* move a wind direction).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dirDeg = try c.decode(Double.self, forKey: .dirDeg)
        confidence = try c.decode(Double.self, forKey: .confidence)
        source = try c.decode(String.self, forKey: .source)
        axisDeg = try c.decode(Double.self, forKey: .axisDeg)
        axisConfidence = try c.decode(Double.self, forKey: .axisConfidence)
        ambiguityMargin = try c.decode(Double.self, forKey: .ambiguityMargin)
        separationDeg = try c.decodeIfPresent(Double.self, forKey: .separationDeg)
        lobesDeg = try c.decodeIfPresent([Double].self, forKey: .lobesDeg)
        lobeMass = try c.decodeIfPresent([Double].self, forKey: .lobeMass)
        speedAsymmetry = try c.decode(Double.self, forKey: .speedAsymmetry)
        turnTypeMargin = try c.decodeIfPresent(Double.self, forKey: .turnTypeMargin) ?? 0
        turnTypeDirDeg = try c.decodeIfPresent(Double.self, forKey: .turnTypeDirDeg)
        turnTypeVotes = try c.decodeIfPresent(Int.self, forKey: .turnTypeVotes) ?? 0
        priorFlipped = try c.decodeIfPresent(Bool.self, forKey: .priorFlipped) ?? false
        distanceM = try c.decode(Double.self, forKey: .distanceM)
        usable = try c.decode(Bool.self, forKey: .usable)
    }

    /// `separationDeg`, `lobesDeg`, `lobeMass` and `turnTypeDirDeg` are written as explicit
    /// nulls, matching the lab's golden JSON: "the prior did not run" is a fact, not a
    /// missing key.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(dirDeg, forKey: .dirDeg)
        try c.encode(confidence, forKey: .confidence)
        try c.encode(source, forKey: .source)
        try c.encode(axisDeg, forKey: .axisDeg)
        try c.encode(axisConfidence, forKey: .axisConfidence)
        try c.encode(ambiguityMargin, forKey: .ambiguityMargin)
        try c.encode(separationDeg, forKey: .separationDeg)
        try c.encode(lobesDeg, forKey: .lobesDeg)
        try c.encode(lobeMass, forKey: .lobeMass)
        try c.encode(speedAsymmetry, forKey: .speedAsymmetry)
        try c.encode(turnTypeMargin, forKey: .turnTypeMargin)
        try c.encode(turnTypeDirDeg, forKey: .turnTypeDirDeg)   // explicit null
        try c.encode(turnTypeVotes, forKey: .turnTypeVotes)
        try c.encode(priorFlipped, forKey: .priorFlipped)
        try c.encode(distanceM, forKey: .distanceM)
        try c.encode(usable, forKey: .usable)
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

/// Session basics and the per-hour rates (docs/algorithms.md "Session rates").
///
/// All four rates share one denominator — **elapsed** session time, first to last cleaned
/// sample — so they answer "per hour on the water", not "per hour of flight". A rider who
/// jibes forty times in two hours of drifting and a rider who does it in one are not having
/// the same session, and only a wall-clock denominator says so.
///
/// Every rate is nil rather than 0 when there is no duration to divide by: a one-sample
/// track has no answer, and a zero would read as "he did nothing". Mirrors
/// `lab/src/wingfoil_lab/goldens.py` `session_rates`.
public struct SessionRates: Sendable, Equatable {
    public var durationS: Double
    public var avgSpeedKmh: Double?
    /// **All** counted turns per hour: this one answers "how busy", which is a question
    /// about activity and not about quality.
    public var turnsPerHour: Double?
    /// **Dry** jibes per hour (engine 0.7.0): the ones he came out of still sailing —
    /// flew-through and touchdown alike, since pumping straight back up out of a touchdown
    /// is a jibe he made. A jibe he swam out of is one he did not, and counting it would
    /// let a rider raise his headline number by falling more often.
    public var jibesPerHour: Double?
    /// **Clean** jibes per hour (engine 0.10.0): `turns.jibesSuccessful` over the same hour —
    /// the strict verdict, a counted jibe flown all the way through carrying its speed
    /// (docs/presentation.md "Clean jibe"). Not a new measurement, just the engine's
    /// per-turn `success` flag given a rate. Dry asks whether he got away with it; clean
    /// asks whether he rode it, and clean is the one the key-metrics block prints.
    public var cleanJibesPerHour: Double?
    /// How often the rider got **wet**, per hour: every `fell_in` flight end, straight-line
    /// swims and turn swims alike. Deliberately not the turn ladder's `fellIn` — most of a
    /// session's falls happen outside a counted turn, and the water does not care.
    public var wetPerHour: Double?

    public init(durationS: Double, distanceM: Double, turnsCounted: Int, dryJibes: Int,
                fellIn: Int, cleanJibes: Int = 0) {
        guard durationS > 0 else {
            self.durationS = max(durationS, 0)
            return
        }
        self.durationS = durationS
        let hours = durationS / 3600
        avgSpeedKmh = distanceM / durationS * 3.6
        turnsPerHour = Double(turnsCounted) / hours
        jibesPerHour = Double(dryJibes) / hours
        cleanJibesPerHour = Double(cleanJibes) / hours
        wetPerHour = Double(fellIn) / hours
    }
}

/// One evaluation of the rolling window: its start, and the two rates over it.
public struct WindowRatePoint: Sendable, Codable, Equatable {
    public var ts: Double
    public var jph: Double
    public var wph: Double

    public init(ts: Double, jph: Double, wph: Double) {
        self.ts = ts
        self.jph = jph
        self.wph = wph
    }
}

/// The rolling-window rate series and its two peaks (docs/algorithms.md "Session rates").
/// Mirrors the lab's `WindowRates` / `window_rates`.
///
/// `bestJph` / `bestWph` are the **true** sliding maxima, not the largest value in `series`:
/// the count in a window can only be highest when the window opens on an event, so the peak
/// search is anchored on the events while the series is a coarse sampling of the same
/// function. `best* >= max(series)` therefore always holds, and often strictly.
///
/// Every number here is measured over a **full** window. A session shorter than one window
/// gets a single point over its actual elapsed span instead — an honest whole-session rate —
/// and never a partial window scaled up to the hour, which is how three good minutes turn
/// into a peak the rider never sailed.
public struct SessionWindowRates: Sendable, Codable, Equatable {
    public var windowMin: Double
    public var bestJph: Double?
    public var bestJphStartTs: Double?
    public var bestWph: Double?
    public var bestWphStartTs: Double?
    public var series: [WindowRatePoint]

    public init(windowMin: Double = 15, series: [WindowRatePoint] = []) {
        self.windowMin = windowMin
        self.series = series
    }

    /// The rolling block for one session. `dryJibeTs` / `wetTs` are the same events the
    /// session rates count, timestamped where the goldens already timestamp them — a dry
    /// jibe at its turn's `ts`, a swim at its flight end's `ts`.
    public init(dryJibeTs: [Double], wetTs: [Double], startT: Double, durationS: Double,
                config: RatesConfig = RatesConfig()) {
        self.init(windowMin: config.windowRateMin)
        let windowS = config.windowRateMin * 60
        guard durationS > 0, windowS > 0 else { return }

        (bestJph, bestJphStartTs) = Self.peak(dryJibeTs, startT: startT,
                                              durationS: durationS, windowS: windowS)
        (bestWph, bestWphStartTs) = Self.peak(wetTs, startT: startT,
                                              durationS: durationS, windowS: windowS)

        if durationS < windowS {
            // One point over the span the session actually lasted: the series says what the
            // rates were, once, rather than pretending to a window that never closed.
            let hours = durationS / 3600
            series = [WindowRatePoint(ts: startT, jph: Double(dryJibeTs.count) / hours,
                                      wph: Double(wetTs.count) / hours)]
            return
        }
        let hours = windowS / 3600
        let steps = Int(((durationS - windowS) / config.gridS + 1e-9).rounded(.down))
        series = (0...max(steps, 0)).map { k in
            let s = startT + Double(k) * config.gridS
            return WindowRatePoint(ts: s,
                                   jph: Double(Self.count(dryJibeTs, from: s, windowS)) / hours,
                                   wph: Double(Self.count(wetTs, from: s, windowS)) / hours)
        }
    }

    /// Events in the half-open window `[start, start + window)`. Half-open so that sliding
    /// the window by one event's spacing never counts that event twice.
    static func count(_ events: [Double], from start: Double, _ windowS: Double) -> Int {
        events.reduce(into: 0) { n, e in
            if start <= e && e < start + windowS { n += 1 }
        }
    }

    /// (peak per-hour rate, the window start that achieved it) over **full** windows only.
    ///
    /// The count in `[s, s+W)` is a step function of `s` that can only reach a local maximum
    /// where the window opens exactly on an event, so those instants — plus the two ends of
    /// the allowed range, where a maximum can be clipped — are the whole candidate set. A
    /// session shorter than one window has no full window to search: its peak is its own
    /// whole-session rate over the span it lasted, never a partial window scaled up.
    static func peak(_ events: [Double], startT: Double, durationS: Double,
                     windowS: Double) -> (Double?, Double?) {
        guard durationS > 0 else { return (nil, nil) }
        guard durationS >= windowS else {
            return (Double(events.count) / (durationS / 3600), startT)
        }
        let lastStart = startT + durationS - windowS
        var candidates = Set([startT, lastStart])
        for e in events where e >= startT && e <= lastStart { candidates.insert(e) }
        var bestN = -1
        var bestStart = startT
        for s in candidates.sorted() {
            let n = count(events, from: s, windowS)
            if n > bestN {                      // ties keep the earliest window
                bestN = n
                bestStart = s
            }
        }
        return (Double(bestN) / (windowS / 3600), bestStart)
    }
}

public struct SessionSummary: Sendable, Codable, Equatable {
    public var foilTimeS: Double
    public var foilPct: Double
    public var flightCount: Int
    public var longestFlightS: Double
    public var longestFlightM: Double
    public var distanceKm: Double
    /// Elapsed session span (s), first to last cleaned sample — gaps included, because a
    /// paused recording still spent that time on the water. The rate denominator.
    public var durationS: Double = 0
    public var avgSpeedKmh: Double?
    public var turnsPerHour: Double?
    public var jibesPerHour: Double?
    /// The strict jibe rate (engine 0.10.0) — see `SessionRates.cleanJibesPerHour`.
    public var cleanJibesPerHour: Double?
    public var wetPerHour: Double?
    /// The rolling 15-minute view of the same two events (engine 0.7.0).
    public var windowRates = SessionWindowRates()
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

    /// Fills the six session-rate fields from one computed rate block.
    public mutating func apply(_ rates: SessionRates) {
        durationS = rates.durationS
        avgSpeedKmh = rates.avgSpeedKmh
        turnsPerHour = rates.turnsPerHour
        jibesPerHour = rates.jibesPerHour
        cleanJibesPerHour = rates.cleanJibesPerHour
        wetPerHour = rates.wetPerHour
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
                               hrConfig: HrConfig = HrConfig(),
                               ratesConfig: RatesConfig = RatesConfig()) -> SessionAnalysis {
        let clean = TrackCleaner.clean(raw, config: filterConfig)
        let segmentation = FlightSegmenter.segment(clean, config: flightConfig)
        let records = GP3SCalculator.records(for: clean, config: recordsConfig)
        // `turnConfig` because the default-turn-type prior (docs/algorithms.md "Default turn
        // type") votes on the very sweeps `TurnDetector` is about to report — one turn
        // config, or the prior and the session would be talking about different turns.
        let wind = WindEstimator.estimate(clean, flights: segmentation, config: windConfig,
                                          turnConfig: turnConfig)
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
        // Session rates (docs/algorithms.md "Session rates"): elapsed wall clock as the one
        // denominator, *dry* jibes as the JPH numerator — a jibe he swam out of is one he
        // did not make — and *every* fell-in end as the wet count, since most of a session's
        // swims happen outside a counted turn.
        let dryJibeTs = SessionSummarizer.dryJibeTimes(turns)
        let wetTs = ends.filter { $0.outcome == .fellIn }.map(\.t)
        summary.apply(SessionRates(durationS: clean.spanS,
                                   distanceM: records.totalDistanceM,
                                   turnsCounted: turnSummary.turnsCounted,
                                   dryJibes: dryJibeTs.count,
                                   fellIn: endSummary.all.fellIn,
                                   cleanJibes: turnSummary.jibesSuccessful))
        summary.windowRates = SessionWindowRates(dryJibeTs: dryJibeTs, wetTs: wetTs,
                                                 startT: clean.samples.first?.t ?? 0,
                                                 durationS: clean.spanS,
                                                 config: ratesConfig)

        var pumpsByFlight = [Int?](repeating: nil, count: segmentation.flights.count)
        for t in takeoffs.takeoffs where segmentation.flights.indices.contains(t.flightIndex) {
            pumpsByFlight[t.flightIndex] = t.pumpsToTakeoff
        }

        return SessionAnalysis(
            engineVersion: AnalysisEngine.version,
            config: AnalysisConfig(filter: filterConfig, flight: flightConfig,
                                   records: recordsConfig, turn: turnConfig, wind: windConfig,
                                   pump: pumpConfig, takeoff: takeoffConfig,
                                   rates: ratesConfig),
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

    /// When each **dry** jibe happened, in time order: a counted jibe he did not swim out
    /// of, at the turn's own `ts` (its start). The list's length is the `jibesPerHour`
    /// numerator — one definition, spelled once. Mirrors the lab's `dry_jibe_times`.
    public static func dryJibeTimes(_ turns: [Turn]) -> [Double] {
        turns.filter { $0.counted && $0.kind == .jibe && $0.outcome != .fellIn }
            .map(\.startT)
    }
}
