import Foundation

/// HR-cost parameters (docs/algorithms.md "HR cost (phone)").
public struct HrConfig: Sendable, Equatable {
    /// hrCostPeakWindow: the peak is searched this far past the anchor. Deliberately much
    /// longer than a pump burst — optical HR trails effort by 10–20 s, so a window as short
    /// as the effort measures the HR the rider *arrived* with.
    public var peakWindowS: Double = 30.0
    /// hrBaselineWindow: median of the usable samples in the window ending at the anchor.
    public var baselineWindowS: Double = 10.0
    /// hrMinCoverage: a window carrying less usable time than this yields nil, never a number.
    public var minCoverageShare: Double = 0.6
    /// hrFlatlineMax: identical bpm for longer, inside one gap-free stretch, is a stuck sensor.
    public var flatlineMaxS: Double = 60.0
    /// hrMinBpm: below this is sensor garbage, not a heart rate.
    public var minBpm: Double = 30.0
    /// hrMaxBpm.
    public var maxBpm: Double = 220.0
    /// hrLag: optical HR trails effort by this much; the pumping/cruising classification
    /// windows are shifted forward by it, and cruising excludes a ±hrLag guard band.
    public var lagS: Double = 10.0
    /// hrRecoveryWindow: cap on the half-decay search.
    public var recoveryWindowS: Double = 120.0
    /// hrMinRise: below this there was no rise to recover from.
    public var minRiseBpm: Double = 5.0
    /// hrBinMinutes: fatigue-curve bin width.
    public var binMinutes: Double = 20.0
    /// hrMaxSampleGap: longer between two samples is an HR hole. Deliberately *not* the
    /// cleaner's dt-aware speed rule — that one protects speed integration, and Smart
    /// Recording's 1–9 s cadence would lose most of a native session's HR to it for nothing.
    public var maxSampleGapS: Double = 10.0

    public init() {}
}

/// The HR channel on the records' time base, with the usability mask already applied.
///
/// **Optical HR is not a measurement until it is proved to be one.** A wrist sensor under a
/// wetsuit sleeve, in cold water, on an arm being thrown around, drops out, sticks and lies.
/// Three per-sample guards decide what may be read: *plausible* (`hrMinBpm`…`hrMaxBpm`),
/// *not stale* (a run of identical bpm longer than `hrFlatlineMax` is a frozen sensor), and
/// *recorded* (the interval leading to the sample is not a hole). They collapse into one
/// number per window — `coverage` — and a window below `hrMinCoverage` yields nil.
/// Mirrors `lab/src/wingfoil_lab/hrcost.py`.
public struct HrTrack: Sendable, Equatable {
    /// Sample times, whole track, gaps included.
    public let t: [Double]
    /// Heart rate; nil where the sample failed a guard. Never 0 — a missing beat rate and a
    /// stopped heart are different claims.
    public let bpm: [Double?]
    /// Plausible and not stale.
    public let usable: [Bool]
    /// An HR hole precedes this sample (`hrMaxSampleGap`).
    public let gap: [Bool]
    public let config: HrConfig

    public var count: Int { t.count }

    /// Share of [a, b] carried by intervals whose *both* end samples are usable — the same
    /// both-ends-qualify convention flight segmentation and the stop measure use.
    public func coverage(_ a: Double, _ b: Double) -> Double {
        let span = b - a
        guard span > 0 else { return 0 }
        return min(recordedS(a, b) / span, 1.0)
    }

    /// Usable, gap-free seconds inside [a, b].
    public func recordedS(_ a: Double, _ b: Double) -> Double {
        guard count >= 2, b > a else { return 0 }
        var acc = 0.0
        for i in 0..<(count - 1) where !gap[i + 1] && usable[i] && usable[i + 1] {
            let lo = max(t[i], a), hi = min(t[i + 1], b)
            if hi > lo { acc += hi - lo }
        }
        return acc
    }

    /// (times, bpm) of the usable samples in [a, b].
    public func values(_ a: Double, _ b: Double) -> (t: [Double], bpm: [Double]) {
        let lo = searchSortedLeft(t, a), hi = searchSortedRight(t, b)
        var outT: [Double] = [], outBpm: [Double] = []
        guard lo < hi else { return (outT, outBpm) }
        for i in lo..<hi {
            guard let v = bpm[i] else { continue }
            outT.append(t[i])
            outBpm.append(v)
        }
        return (outT, outBpm)
    }

    /// Time-weighted mean bpm over `spans`, plus (usable seconds, total span seconds).
    ///
    /// Weighted by *recorded* time rather than by sample count so that a 1 Hz stretch and a
    /// 2 s Smart-Recording stretch of the same duration count the same.
    public func meanBpm(_ spans: [(Double, Double)]) -> (bpm: Double?, coveredS: Double,
                                                         spanS: Double) {
        let total = spans.reduce(0.0) { $0 + max($1.1 - $1.0, 0) }
        guard count >= 2, !spans.isEmpty else { return (nil, 0, total) }
        var wSum = 0.0, acc = 0.0
        for (a, b) in spans {
            for i in 0..<(count - 1) {
                guard !gap[i + 1], let v0 = bpm[i], let v1 = bpm[i + 1] else { continue }
                let w = max(min(t[i + 1], b) - max(t[i], a), 0)
                wSum += w
                acc += w * (v0 + v1) / 2
            }
        }
        return (wSum > 0 ? acc / wSum : nil, wSum, total)
    }
}

/// What an anchored HR measurement is hung on.
public enum HrEventKind: String, Sendable, Codable {
    case takeoff
    case swim
}

/// One anchored HR measurement: a takeoff effort or a swim, and what HR did around it.
public struct HrEvent: Sendable, Codable, Equatable {
    public var kind: HrEventKind
    /// Takeoff index, or flight-end index — turn index for the swims a turn owns.
    public var index: Int
    /// The anchor: the start of the effort, or the fall.
    public var t: Double
    /// Anchored on speed/flight evidence rather than on a pump burst.
    public var approximate = false
    /// Pumps in the run (takeoffs from accel sources only).
    public var strokes: Int?
    /// Median over `hrBaselineWindow` before the anchor.
    public var baselineBpm: Double?
    /// Max over `hrCostPeakWindow` after it.
    public var peakBpm: Double?
    /// peak − baseline. A negative cost is *reported*, not clamped: "he was still
    /// recovering when he started" is a different fact from "this cost nothing".
    public var costBpm: Double?
    /// Anchor → peak.
    public var peakLagS: Double?
    public var baselineCoverage: Double = 0
    public var peakCoverage: Double = 0
    /// Peak → halfway back to the baseline.
    public var recoveryHalfS: Double?
    /// The rise was real but the decay left the window or ran into a hole.
    public var recoveryCensored = false

    public var valid: Bool { costBpm != nil }

    public init(kind: HrEventKind, index: Int, t: Double, approximate: Bool = false,
                strokes: Int? = nil) {
        self.kind = kind
        self.index = index
        self.t = t
        self.approximate = approximate
        self.strokes = strokes
    }

    enum CodingKeys: String, CodingKey {
        case kind, index, ts, approximate, strokes, baselineBpm, peakBpm, costBpm
        case peakLagS, baselineCoverage, peakCoverage, recoveryHalfS, recoveryCensored
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(HrEventKind.self, forKey: .kind)
        index = try c.decode(Int.self, forKey: .index)
        t = try c.decode(Double.self, forKey: .ts)
        approximate = try c.decode(Bool.self, forKey: .approximate)
        strokes = try c.decodeIfPresent(Int.self, forKey: .strokes)
        baselineBpm = try c.decodeIfPresent(Double.self, forKey: .baselineBpm)
        peakBpm = try c.decodeIfPresent(Double.self, forKey: .peakBpm)
        costBpm = try c.decodeIfPresent(Double.self, forKey: .costBpm)
        peakLagS = try c.decodeIfPresent(Double.self, forKey: .peakLagS)
        baselineCoverage = try c.decode(Double.self, forKey: .baselineCoverage)
        peakCoverage = try c.decode(Double.self, forKey: .peakCoverage)
        recoveryHalfS = try c.decodeIfPresent(Double.self, forKey: .recoveryHalfS)
        recoveryCensored = try c.decode(Bool.self, forKey: .recoveryCensored)
    }

    /// Explicit nulls throughout: an unmeasurable window must not decode back as a zero.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(index, forKey: .index)
        try c.encode(t, forKey: .ts)
        try c.encode(approximate, forKey: .approximate)
        try c.encode(strokes, forKey: .strokes)
        try c.encode(baselineBpm, forKey: .baselineBpm)
        try c.encode(peakBpm, forKey: .peakBpm)
        try c.encode(costBpm, forKey: .costBpm)
        try c.encode(peakLagS, forKey: .peakLagS)
        try c.encode(baselineCoverage, forKey: .baselineCoverage)
        try c.encode(peakCoverage, forKey: .peakCoverage)
        try c.encode(recoveryHalfS, forKey: .recoveryHalfS)
        try c.encode(recoveryCensored, forKey: .recoveryCensored)
    }
}

/// `n valid / n total` for one metric — carried beside every aggregate so a summary can
/// never quietly average three takeoffs and call it a session.
public struct HrCoverage: Sendable, Equatable {
    public var valid = 0
    public var total = 0

    public init(valid: Int = 0, total: Int = 0) {
        self.valid = valid
        self.total = total
    }

    /// nil for an empty denominator: "no attempts" is not "0 %".
    public var pct: Double? {
        total > 0 ? 100.0 * Double(valid) / Double(total) : nil
    }

    public var text: String {
        pct.map { String(format: "\(valid)/\(total) (%.0f%%)", $0) } ?? "\(valid)/\(total)"
    }
}

/// Mean HR while pumping against mean HR cruising on the foil, both `hrLag`-shifted.
public struct PumpCruiseHr: Sendable, Codable, Equatable {
    public var pumpingBpm: Double?
    public var cruisingBpm: Double?
    public var deltaBpm: Double?
    public var pumpingSpans = 0
    public var cruisingSpans = 0
    public var pumpingCoveredS: Double = 0
    public var pumpingSpanS: Double = 0
    public var cruisingCoveredS: Double = 0
    public var cruisingSpanS: Double = 0

    public init() {}

    public var pumpingCoverage: Double? {
        pumpingSpanS > 0 ? pumpingCoveredS / pumpingSpanS : nil
    }

    public var cruisingCoverage: Double? {
        cruisingSpanS > 0 ? cruisingCoveredS / cruisingSpanS : nil
    }

    enum CodingKeys: String, CodingKey {
        case pumpingBpm, cruisingBpm, deltaBpm, pumpingSpans, cruisingSpans
        case pumpingCoveredS, pumpingSpanS, cruisingCoveredS, cruisingSpanS
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pumpingBpm = try c.decodeIfPresent(Double.self, forKey: .pumpingBpm)
        cruisingBpm = try c.decodeIfPresent(Double.self, forKey: .cruisingBpm)
        deltaBpm = try c.decodeIfPresent(Double.self, forKey: .deltaBpm)
        pumpingSpans = try c.decode(Int.self, forKey: .pumpingSpans)
        cruisingSpans = try c.decode(Int.self, forKey: .cruisingSpans)
        pumpingCoveredS = try c.decode(Double.self, forKey: .pumpingCoveredS)
        pumpingSpanS = try c.decode(Double.self, forKey: .pumpingSpanS)
        cruisingCoveredS = try c.decode(Double.self, forKey: .cruisingCoveredS)
        cruisingSpanS = try c.decode(Double.self, forKey: .cruisingSpanS)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pumpingBpm, forKey: .pumpingBpm)       // explicit null: no accel stream
        try c.encode(cruisingBpm, forKey: .cruisingBpm)
        try c.encode(deltaBpm, forKey: .deltaBpm)
        try c.encode(pumpingSpans, forKey: .pumpingSpans)
        try c.encode(cruisingSpans, forKey: .cruisingSpans)
        try c.encode(pumpingCoveredS, forKey: .pumpingCoveredS)
        try c.encode(pumpingSpanS, forKey: .pumpingSpanS)
        try c.encode(cruisingCoveredS, forKey: .cruisingCoveredS)
        try c.encode(cruisingSpanS, forKey: .cruisingSpanS)
    }
}

/// One time slice of the session: what he attempted in it, and what it cost him.
public struct FatigueBin: Sendable, Codable, Equatable {
    public var startT: Double
    public var endT: Double
    /// Successes + failed episodes anchored in the bin.
    public var attempts = 0
    public var successes = 0
    public var failed = 0
    public var successPct: Double?
    public var avgCostBpm: Double?
    public var medianCostBpm: Double?
    public var costCoverage = HrCoverage()
    /// The HR he *started* this bin's attempts at. A late rise shrinks because the baseline
    /// has drifted up, not because the effort got cheaper — so it sits beside the cost.
    public var avgBaselineBpm: Double?
    public var avgPumps: Double?
    /// Mean HR over the whole bin (usable time only).
    public var meanBpm: Double?

    public init(startT: Double, endT: Double) {
        self.startT = startT
        self.endT = endT
    }

    enum CodingKeys: String, CodingKey {
        case startTs, endTs, attempts, successes, failed, successPct, avgCostBpm
        case medianCostBpm, costValid, costTotal, avgBaselineBpm, avgPumps, meanBpm
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startT = try c.decode(Double.self, forKey: .startTs)
        endT = try c.decode(Double.self, forKey: .endTs)
        attempts = try c.decode(Int.self, forKey: .attempts)
        successes = try c.decode(Int.self, forKey: .successes)
        failed = try c.decode(Int.self, forKey: .failed)
        successPct = try c.decodeIfPresent(Double.self, forKey: .successPct)
        avgCostBpm = try c.decodeIfPresent(Double.self, forKey: .avgCostBpm)
        medianCostBpm = try c.decodeIfPresent(Double.self, forKey: .medianCostBpm)
        costCoverage = HrCoverage(valid: try c.decode(Int.self, forKey: .costValid),
                                  total: try c.decode(Int.self, forKey: .costTotal))
        avgBaselineBpm = try c.decodeIfPresent(Double.self, forKey: .avgBaselineBpm)
        avgPumps = try c.decodeIfPresent(Double.self, forKey: .avgPumps)
        meanBpm = try c.decodeIfPresent(Double.self, forKey: .meanBpm)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(startT, forKey: .startTs)
        try c.encode(endT, forKey: .endTs)
        try c.encode(attempts, forKey: .attempts)
        try c.encode(successes, forKey: .successes)
        try c.encode(failed, forKey: .failed)
        try c.encode(successPct, forKey: .successPct)       // explicit null: no attempts
        try c.encode(avgCostBpm, forKey: .avgCostBpm)
        try c.encode(medianCostBpm, forKey: .medianCostBpm)
        try c.encode(costCoverage.valid, forKey: .costValid)
        try c.encode(costCoverage.total, forKey: .costTotal)
        try c.encode(avgBaselineBpm, forKey: .avgBaselineBpm)
        try c.encode(avgPumps, forKey: .avgPumps)
        try c.encode(meanBpm, forKey: .meanBpm)
    }
}

/// Session-level HR-cost metrics. Every average carries its coverage.
public struct HrSummary: Sendable, Codable, Equatable {
    /// Not encoded — `HrAnalysis.hasHR` is the one place the golden spells it, and one fact
    /// written twice is one fact that can drift. Decoding restores it from there.
    public var hasHR = false
    /// Usable HR share of the recorded session span.
    public var usablePct: Double?
    public var avgTakeoffCostBpm: Double?
    public var medianTakeoffCostBpm: Double?
    public var takeoffCostCoverage = HrCoverage()
    /// Of the valid takeoffs, those not burst-anchored.
    public var approximateTakeoffs = 0
    public var medianPeakLagS: Double?
    /// Pooled Σcost ⁄ Σstrokes — the headline.
    public var bpmPerStroke: Double?
    /// Median of the per-takeoff ratios, reported beside the pooled figure so the spread is
    /// visible: dividing a 3 bpm cost by 4 strokes one takeoff at a time turns sensor noise
    /// into a wide range of ratios.
    public var medianBpmPerStroke: Double?
    public var bpmPerStrokeCoverage = HrCoverage()
    public var pumpCruise = PumpCruiseHr()
    public var medianTakeoffRecoveryS: Double?
    public var takeoffRecoveryCoverage = HrCoverage()
    public var medianSwimRecoveryS: Double?
    public var swimRecoveryCoverage = HrCoverage()
    public var avgSwimCostBpm: Double?
    public var swimCostCoverage = HrCoverage()

    public init() {}

    enum CodingKeys: String, CodingKey {
        case usablePct, avgTakeoffCostBpm, medianTakeoffCostBpm
        case takeoffCostValid, takeoffCostTotal, approximateTakeoffs, medianPeakLagS
        case bpmPerStroke, medianBpmPerStroke, bpmPerStrokeValid, bpmPerStrokeTotal
        case pumpCruise, medianTakeoffRecoveryS, takeoffRecoveryValid, takeoffRecoveryTotal
        case medianSwimRecoveryS, swimRecoveryValid, swimRecoveryTotal
        case avgSwimCostBpm, swimCostValid, swimCostTotal
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        usablePct = try c.decodeIfPresent(Double.self, forKey: .usablePct)
        avgTakeoffCostBpm = try c.decodeIfPresent(Double.self, forKey: .avgTakeoffCostBpm)
        medianTakeoffCostBpm = try c.decodeIfPresent(Double.self,
                                                     forKey: .medianTakeoffCostBpm)
        takeoffCostCoverage = HrCoverage(
            valid: try c.decode(Int.self, forKey: .takeoffCostValid),
            total: try c.decode(Int.self, forKey: .takeoffCostTotal))
        approximateTakeoffs = try c.decode(Int.self, forKey: .approximateTakeoffs)
        medianPeakLagS = try c.decodeIfPresent(Double.self, forKey: .medianPeakLagS)
        bpmPerStroke = try c.decodeIfPresent(Double.self, forKey: .bpmPerStroke)
        medianBpmPerStroke = try c.decodeIfPresent(Double.self, forKey: .medianBpmPerStroke)
        bpmPerStrokeCoverage = HrCoverage(
            valid: try c.decode(Int.self, forKey: .bpmPerStrokeValid),
            total: try c.decode(Int.self, forKey: .bpmPerStrokeTotal))
        pumpCruise = try c.decode(PumpCruiseHr.self, forKey: .pumpCruise)
        medianTakeoffRecoveryS = try c.decodeIfPresent(Double.self,
                                                       forKey: .medianTakeoffRecoveryS)
        takeoffRecoveryCoverage = HrCoverage(
            valid: try c.decode(Int.self, forKey: .takeoffRecoveryValid),
            total: try c.decode(Int.self, forKey: .takeoffRecoveryTotal))
        medianSwimRecoveryS = try c.decodeIfPresent(Double.self, forKey: .medianSwimRecoveryS)
        swimRecoveryCoverage = HrCoverage(
            valid: try c.decode(Int.self, forKey: .swimRecoveryValid),
            total: try c.decode(Int.self, forKey: .swimRecoveryTotal))
        avgSwimCostBpm = try c.decodeIfPresent(Double.self, forKey: .avgSwimCostBpm)
        swimCostCoverage = HrCoverage(
            valid: try c.decode(Int.self, forKey: .swimCostValid),
            total: try c.decode(Int.self, forKey: .swimCostTotal))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(usablePct, forKey: .usablePct)          // explicit nulls throughout:
        try c.encode(avgTakeoffCostBpm, forKey: .avgTakeoffCostBpm)   // an unmeasured cost
        try c.encode(medianTakeoffCostBpm, forKey: .medianTakeoffCostBpm)  // is not a free one
        try c.encode(takeoffCostCoverage.valid, forKey: .takeoffCostValid)
        try c.encode(takeoffCostCoverage.total, forKey: .takeoffCostTotal)
        try c.encode(approximateTakeoffs, forKey: .approximateTakeoffs)
        try c.encode(medianPeakLagS, forKey: .medianPeakLagS)
        try c.encode(bpmPerStroke, forKey: .bpmPerStroke)
        try c.encode(medianBpmPerStroke, forKey: .medianBpmPerStroke)
        try c.encode(bpmPerStrokeCoverage.valid, forKey: .bpmPerStrokeValid)
        try c.encode(bpmPerStrokeCoverage.total, forKey: .bpmPerStrokeTotal)
        try c.encode(pumpCruise, forKey: .pumpCruise)
        try c.encode(medianTakeoffRecoveryS, forKey: .medianTakeoffRecoveryS)
        try c.encode(takeoffRecoveryCoverage.valid, forKey: .takeoffRecoveryValid)
        try c.encode(takeoffRecoveryCoverage.total, forKey: .takeoffRecoveryTotal)
        try c.encode(medianSwimRecoveryS, forKey: .medianSwimRecoveryS)
        try c.encode(swimRecoveryCoverage.valid, forKey: .swimRecoveryValid)
        try c.encode(swimRecoveryCoverage.total, forKey: .swimRecoveryTotal)
        try c.encode(avgSwimCostBpm, forKey: .avgSwimCostBpm)
        try c.encode(swimCostCoverage.valid, forKey: .swimCostValid)
        try c.encode(swimCostCoverage.total, forKey: .swimCostTotal)
    }
}

/// Everything the HR channel had to say about this session — the golden schema's `hr` block.
///
/// The Python original also holds the `HrTrack` itself. This type is stored verbatim in
/// `analysis.json`, and the channel is thousands of raw sensor samples that re-derive from
/// the archived FIT for free, so it is deliberately not a member here; `HrCost.track(_:)`
/// hands it to callers that want the stream.
public struct HrAnalysis: Sendable, Codable, Equatable {
    /// False is a *fact about the source*, not an omission — see the golden schema note in
    /// docs/testing.md. Nothing else in the block is trustworthy when this is false.
    public var hasHR = false
    public var takeoffEvents: [HrEvent] = []
    public var swimEvents: [HrEvent] = []
    public var bins: [FatigueBin] = []
    public var summary = HrSummary()

    public init() {}

    public init(hasHR: Bool, takeoffEvents: [HrEvent], swimEvents: [HrEvent],
                bins: [FatigueBin], summary: HrSummary) {
        self.hasHR = hasHR
        self.takeoffEvents = takeoffEvents
        self.swimEvents = swimEvents
        self.bins = bins
        self.summary = summary
    }

    enum CodingKeys: String, CodingKey { case hasHR, takeoffEvents, swimEvents, bins, summary }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hasHR = try c.decode(Bool.self, forKey: .hasHR)
        takeoffEvents = try c.decode([HrEvent].self, forKey: .takeoffEvents)
        swimEvents = try c.decode([HrEvent].self, forKey: .swimEvents)
        bins = try c.decode([FatigueBin].self, forKey: .bins)
        summary = try c.decode(HrSummary.self, forKey: .summary)
        summary.hasHR = hasHR
    }
}

/// HR cost of pumping: what every takeoff attempt cost in heartbeats, and how that drifts.
///
/// Jan's question is simple — *"my HR goes up when I pump"* — and the session data answers
/// four versions of it: the per-takeoff rise from the start of the effort to the peak within
/// `hrCostPeakWindow`; pumping against cruising; how cost and success rate move over the
/// session; and how long HR takes to fall halfway back after a takeoff or a swim.
///
/// This is a separate module rather than more of `TakeoffAnalyzer` on purpose. Takeoff
/// analysis is a frozen golden contract read off the speed and accelerometer channels; HR is
/// a third channel with entirely different failure modes, it is read from the **raw** samples
/// (the cleaner drops rows for a missing or spiky *fix*, and such a row still carries a
/// perfectly good heart rate), and it joins to takeoffs, flight ends *and* turns. Wiring it
/// into the takeoff types would have made one contract answer to two sensors.
///
/// **Lag is real and is not corrected away.** `hrLag` shifts the pumping/cruising
/// classification windows forward, and `hrCostPeakWindow` looks well past the effort. The
/// per-takeoff cost is deliberately *not* lag-shifted — its baseline is read before the
/// effort and its peak after it, so the lag is inside the measurement rather than beside it.
///
/// Mirrors `lab/src/wingfoil_lab/hrcost.py`.
public enum HrCost {

    // MARK: - Building the channel

    /// Build an `HrTrack` from a parsed source, or nil when it carries no HR channel.
    ///
    /// Read from `RawTrack.samples` rather than the `CleanTrack`, and with its own
    /// continuity rule (`hrMaxSampleGap`) — see `HrConfig`.
    public static func track(_ raw: RawTrack, config: HrConfig = HrConfig()) -> HrTrack? {
        guard !raw.samples.isEmpty, raw.samples.contains(where: { $0.heartRate != nil })
        else { return nil }
        // Sorted by time and de-duplicated keeping the first of any repeated timestamp: a
        // FIT that restated a second must not put a backwards step into the time base.
        var seen = Set<Double>()
        var times: [Double] = [], bpm: [Double?] = []
        for s in raw.samples.enumerated().sorted(by: {
            $0.element.t == $1.element.t ? $0.offset < $1.offset : $0.element.t < $1.element.t
        }).map(\.element) where seen.insert(s.t).inserted {
            times.append(s.t)
            bpm.append(s.heartRate)
        }
        return track(times: times, bpm: bpm, config: config)
    }

    /// HrTrack from raw (time, bpm) samples — unit tests and non-FIT sources.
    ///
    /// A hole can only hide a *higher* peak than the one observed, so a windowed cost read
    /// across one is biased low, never high.
    public static func track(times: [Double], bpm: [Double?],
                             config: HrConfig = HrConfig()) -> HrTrack? {
        guard !times.isEmpty else { return nil }
        var gap = [Bool](repeating: false, count: times.count)
        if times.count > 1 {
            for i in 1..<times.count { gap[i] = times[i] - times[i - 1] > config.maxSampleGapS }
        }

        let stale = staleMask(times, bpm, gap, config.flatlineMaxS)
        var usable = [Bool](repeating: false, count: times.count)
        var kept = [Double?](repeating: nil, count: times.count)
        for i in times.indices {
            guard let v = bpm[i], v.isFinite, v >= config.minBpm, v <= config.maxBpm,
                  !stale[i] else { continue }
            usable[i] = true
            kept[i] = v
        }
        return HrTrack(t: times, bpm: kept, usable: usable, gap: gap, config: config)
    }

    /// Samples inside a run of identical bpm longer than `maxS`, measured across no gap.
    ///
    /// A frozen optical sensor repeats its last value; a heart does too, briefly. The line is
    /// drawn on duration, and the *whole* run is dropped rather than its tail, because there
    /// is no telling which end of it was still the rider. Runs are cut at recording gaps: a
    /// session paused for eleven minutes at 90 bpm and resumed at 90 bpm is not a stuck
    /// sensor. A missing sample breaks a run too — "no reading" is not "the same reading".
    static func staleMask(_ t: [Double], _ bpm: [Double?], _ gap: [Bool],
                          _ maxS: Double) -> [Bool] {
        var stale = [Bool](repeating: false, count: t.count)
        guard !t.isEmpty else { return stale }
        var starts: [Int] = []
        for i in t.indices {
            let same: Bool
            if i == 0 {
                same = false
            } else if let v = bpm[i], let prev = bpm[i - 1] {
                same = v == prev && !gap[i]
            } else {
                same = false
            }
            if !same { starts.append(i) }
        }
        for (j, a) in starts.enumerated() {
            let b = (j + 1 < starts.count ? starts[j + 1] : t.count) - 1
            guard b > a, t[b] - t[a] > maxS else { continue }
            for i in a...b { stale[i] = true }
        }
        return stale
    }

    // MARK: - The whole picture

    /// The whole HR-cost result for one session.
    ///
    /// Every argument past `takeoffs` is optional evidence: without `flightEnds`/`turns`
    /// there are no swim events, without `pump` the pumping/cruising split has no pumping
    /// side and the takeoff anchors degrade to `approximate`.
    public static func analyze(_ raw: RawTrack, flights: FlightSegmentation,
                               takeoffs: TakeoffAnalysis, flightEnds: [FlightEnd] = [],
                               pump: PumpTrack? = nil, turns: [Turn] = [],
                               config: HrConfig = HrConfig()) -> HrAnalysis {
        guard let hr = track(raw, config: config) else { return HrAnalysis() }
        let events = takeoffEvents(hr, takeoffs: takeoffs, config: config)
        let swims = swimEvents(hr, flightEnds: flightEnds, turns: turns, config: config)
        let pc = pumpVsCruise(hr, pump: pump, flights: flights, config: config)
        return HrAnalysis(hasHR: true, takeoffEvents: events, swimEvents: swims,
                          bins: fatigueCurve(hr, takeoffs: takeoffs, events: events,
                                             config: config),
                          summary: summarize(hr, takeoffEvents: events, swimEvents: swims,
                                             pumpCruise: pc, config: config))
    }

    // MARK: - Events

    /// One HR event per takeoff, anchored on the effort that produced the flight.
    ///
    /// The anchor is the takeoff *run* start — the first stroke of the burst that led into
    /// the flight, or the start of the speed rise when it began earlier. That is the moment
    /// the work started, and the only anchor for which "the HR rise this attempt cost" means
    /// anything: anchoring on ON_FOIL would begin measuring after the pumping was over.
    ///
    /// `approximate` marks the two degraded anchors: no strokes in the run (no accelerometer,
    /// or a genuinely free takeoff), and a truncated run, where the record does not reach
    /// back over the effort at all and the anchor falls to the flight start — the HR delta
    /// across the off-foil → on-foil transition alone.
    public static func takeoffEvents(_ hr: HrTrack, takeoffs: TakeoffAnalysis,
                                     config: HrConfig = HrConfig()) -> [HrEvent] {
        takeoffs.takeoffs.enumerated().map { i, k in
            let pumped = (k.pumpsToTakeoff ?? 0) > 0
            let anchor = k.truncated ? k.t : k.runStartT
            return measure(hr, HrEvent(kind: .takeoff, index: i, t: anchor,
                                       approximate: k.truncated || !pumped,
                                       strokes: k.pumpsToTakeoff), config)
        }
    }

    /// One HR event per swim, anchored on the moment the foil was lost.
    ///
    /// Swims are read off the flight ends that fell in, plus any turn that fell in without a
    /// flight end inside its outcome window — the same ownership rule `FlightEndClassifier`
    /// uses, so a jibe that ended in a swim yields exactly one event however many channels
    /// saw it.
    public static func swimEvents(_ hr: HrTrack, flightEnds: [FlightEnd], turns: [Turn],
                                  config: HrConfig = HrConfig()) -> [HrEvent] {
        let ends = flightEnds.filter { $0.outcome == .fellIn }
        var out = ends.map {
            measure(hr, HrEvent(kind: .swim, index: $0.flightIndex, t: $0.t), config)
        }
        for (k, turn) in turns.enumerated() where turn.outcome == .fellIn {
            let windowEnd = turn.endT + turn.outcomeWindowS
            if ends.contains(where: { turn.startT <= $0.t && $0.t <= windowEnd }) { continue }
            out.append(measure(hr, HrEvent(kind: .swim, index: k, t: turn.endT), config))
        }
        // Stable by construction: two swims at the same instant keep flight-end order ahead
        // of turn order, which is the order the lab's `sorted()` also produces.
        return out.enumerated()
            .sorted { $0.element.t == $1.element.t ? $0.offset < $1.offset
                                                   : $0.element.t < $1.element.t }
            .map(\.element)
    }

    /// Baseline / peak / cost / half-recovery around one anchor, or nils and a coverage.
    private static func measure(_ hr: HrTrack, _ event: HrEvent, _ config: HrConfig) -> HrEvent {
        var ev = event
        ev.baselineCoverage = hr.coverage(ev.t - config.baselineWindowS, ev.t)
        ev.peakCoverage = hr.coverage(ev.t, ev.t + config.peakWindowS)
        let base = hr.values(ev.t - config.baselineWindowS, ev.t).bpm
        let peak = hr.values(ev.t, ev.t + config.peakWindowS)
        guard ev.baselineCoverage >= config.minCoverageShare,
              ev.peakCoverage >= config.minCoverageShare,
              !base.isEmpty, !peak.bpm.isEmpty
        else { return ev }

        let baseline = Evidence.median(base)
        var j = 0
        for i in peak.bpm.indices where peak.bpm[i] > peak.bpm[j] { j = i }
        let cost = peak.bpm[j] - baseline
        ev.baselineBpm = baseline
        ev.peakBpm = peak.bpm[j]
        ev.peakLagS = peak.t[j] - ev.t
        ev.costBpm = cost
        if cost >= config.minRiseBpm {
            let r = halfRecovery(hr, peakT: peak.t[j], target: peak.bpm[j] - 0.5 * cost,
                                 config: config)
            ev.recoveryHalfS = r.halfS
            ev.recoveryCensored = r.censored
        }
        return ev
    }

    /// Seconds from the peak until HR first reaches `target`, or (nil, censored).
    ///
    /// The search runs forward over usable samples and **stops at a recording gap**, the same
    /// rule the outcome windows use: a heart rate that was 120 before an eleven-minute gap
    /// and 88 after it did not decay in that window, and reporting the gap as a fast recovery
    /// would be the most flattering possible lie. Running past `hrRecoveryWindow` without
    /// reaching the target is `censored` — a fact about the window, not about the rider.
    private static func halfRecovery(_ hr: HrTrack, peakT: Double, target: Double,
                                     config: HrConfig) -> (halfS: Double?, censored: Bool) {
        let lo = searchSortedRight(hr.t, peakT)
        var i = lo
        while i < hr.count {
            if hr.gap[i] || hr.t[i] > peakT + config.recoveryWindowS { break }
            if let v = hr.bpm[i], v <= target { return (hr.t[i] - peakT, false) }
            i += 1
        }
        return (nil, true)
    }

    // MARK: - Pumping vs cruising

    /// Mean HR while pumping against mean HR cruising on the foil.
    ///
    /// Both families are shifted forward by `hrLag`, because that is where the HR belonging
    /// to a given second of effort actually shows up. The cruising side additionally
    /// *excludes* a ±`hrLag` guard band around every shifted burst: the seconds either side
    /// of a pump are exactly the ones whose HR is ambiguous, and letting them into the
    /// cruising mean would close the gap the metric is trying to measure.
    ///
    /// Bursts are taken over the whole session — takeoff runs, failed attempts, recovery
    /// pumping and in-flight pumping alike. They are all the same physical act, and the
    /// takeoff/in-flight split is already reported by `TakeoffAnalyzer`.
    public static func pumpVsCruise(_ hr: HrTrack, pump: PumpTrack?,
                                    flights: FlightSegmentation,
                                    config: HrConfig = HrConfig()) -> PumpCruiseHr {
        var out = PumpCruiseHr()
        guard hr.count > 0, !flights.flights.isEmpty else { return out }
        let lag = config.lagS
        var spans: [(Double, Double)] = []
        if let pump {
            spans = pump.bursts(from: hr.t[0], to: hr.t[hr.count - 1])
                .filter { $0.count >= pump.config.minStrokes }
                .map { ($0[0] + lag, $0[$0.count - 1] + lag) }
        }
        let guardBands = spans.map { ($0.0 - lag, $0.1 + lag) }
        let cruise = subtract(flights.flights.map { ($0.startT + lag, $0.endT + lag) },
                              guardBands)

        out.pumpingSpans = spans.count
        out.cruisingSpans = cruise.count
        let pumping = hr.meanBpm(spans)
        out.pumpingBpm = pumping.bpm
        out.pumpingCoveredS = pumping.coveredS
        out.pumpingSpanS = pumping.spanS
        let cruising = hr.meanBpm(cruise)
        out.cruisingBpm = cruising.bpm
        out.cruisingCoveredS = cruising.coveredS
        out.cruisingSpanS = cruising.spanS
        if let p = out.pumpingBpm, let c = out.cruisingBpm { out.deltaBpm = p - c }
        return out
    }

    /// `spans` minus every interval in `cuts` (both may overlap; output is sorted, disjoint).
    static func subtract(_ spans: [(Double, Double)],
                         _ cuts: [(Double, Double)]) -> [(Double, Double)] {
        var out: [(Double, Double)] = []
        let merged = merge(cuts)
        for (a, b) in spans {
            var cur = a
            for (c, d) in merged {
                if d <= cur || c >= b { continue }
                if c > cur { out.append((cur, min(c, b))) }
                cur = max(cur, d)
                if cur >= b { break }
            }
            if cur < b { out.append((cur, b)) }
        }
        return out.filter { $0.1 > $0.0 }
    }

    static func merge(_ spans: [(Double, Double)]) -> [(Double, Double)] {
        var out: [(Double, Double)] = []
        for (a, b) in spans.sorted(by: { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }) {
            if let last = out.last, a <= last.1 {
                out[out.count - 1] = (last.0, max(last.1, b))
            } else {
                out.append((a, b))
            }
        }
        return out
    }

    // MARK: - Fatigue curve

    /// Takeoff cost and attempt success over session time, in `hrBinMinutes` slices.
    ///
    /// Pass `nBins` instead for equal slices (thirds are the readable default for a short
    /// session). Attempts are counted where the *effort* happened: a flight is credited to
    /// the bin its takeoff started in, a failed episode to the bin of its first stroke — so a
    /// bin's success rate is about what he tried in those minutes, not about where a flight
    /// ended up.
    public static func fatigueCurve(_ hr: HrTrack, takeoffs: TakeoffAnalysis,
                                    events: [HrEvent], config: HrConfig = HrConfig(),
                                    binMinutes: Double? = nil,
                                    nBins: Int? = nil) -> [FatigueBin] {
        guard hr.count >= 2 else { return [] }
        let edges = edges(t0: hr.t[0], t1: hr.t[hr.count - 1], config: config,
                          binMinutes: binMinutes, nBins: nBins)
        var byIndex: [Int: HrEvent] = [:]
        for e in events where e.kind == .takeoff { byIndex[e.index] = e }
        let failed = takeoffs.episodes.filter { $0.outcome == .failed }.map(\.startT)

        var out: [FatigueBin] = []
        for (a, b) in zip(edges, edges.dropFirst()) {
            var row = FatigueBin(startT: a, endT: b)
            row.failed = failed.filter { a <= $0 && $0 < b }.count
            var costs: [Double] = [], bases: [Double] = [], pumps: [Double] = []
            for (i, k) in takeoffs.takeoffs.enumerated() where a <= k.t && k.t < b {
                row.successes += 1
                row.costCoverage.total += 1
                if let ev = byIndex[i], let cost = ev.costBpm, let base = ev.baselineBpm {
                    row.costCoverage.valid += 1
                    costs.append(cost)
                    bases.append(base)
                }
                if let p = k.pumpsToTakeoff, !k.truncated { pumps.append(Double(p)) }
            }
            row.attempts = row.successes + row.failed
            if row.attempts > 0 {
                row.successPct = 100.0 * Double(row.successes) / Double(row.attempts)
            }
            row.avgCostBpm = mean(costs)
            row.medianCostBpm = medianOf(costs)
            row.avgBaselineBpm = mean(bases)
            row.avgPumps = mean(pumps)
            row.meanBpm = hr.meanBpm([(a, b)]).bpm
            out.append(row)
        }
        return out
    }

    private static func edges(t0: Double, t1: Double, config: HrConfig,
                              binMinutes: Double?, nBins: Int?) -> [Double] {
        if let n = nBins, n > 0 {
            let step = (t1 - t0) / Double(n)
            return (0..<n).map { t0 + Double($0) * step } + [t1]
        }
        let step = max(binMinutes ?? config.binMinutes, 1e-6) * 60.0
        let n = max(Int(((t1 - t0) / step).rounded(.up)), 1)
        return (0..<n).map { t0 + Double($0) * step } + [t1]
    }

    // MARK: - Summary

    /// Session tallies. Nothing is averaged without its `n valid / n total` beside it.
    public static func summarize(_ hr: HrTrack?, takeoffEvents: [HrEvent],
                                 swimEvents: [HrEvent],
                                 pumpCruise: PumpCruiseHr = PumpCruiseHr(),
                                 config: HrConfig = HrConfig()) -> HrSummary {
        var s = HrSummary()
        s.pumpCruise = pumpCruise
        guard let hr, hr.count > 0 else { return s }
        s.hasHR = true
        let span = hr.t[hr.count - 1] - hr.t[0]
        if span > 0 {
            s.usablePct = 100.0 * hr.recordedS(hr.t[0], hr.t[hr.count - 1]) / span
        }

        let valid = takeoffEvents.filter(\.valid)
        s.takeoffCostCoverage = HrCoverage(valid: valid.count, total: takeoffEvents.count)
        s.avgTakeoffCostBpm = mean(valid.compactMap(\.costBpm))
        s.medianTakeoffCostBpm = medianOf(valid.compactMap(\.costBpm))
        s.approximateTakeoffs = valid.filter(\.approximate).count
        s.medianPeakLagS = medianOf(valid.compactMap(\.peakLagS))

        // bpm per stroke: only takeoffs whose run has both a measured cost and counted
        // strokes. The pooled ratio is the headline; the median of the per-takeoff ratios
        // sits beside it so the spread is visible rather than hidden.
        let rated: [(cost: Double, strokes: Int)] = valid.compactMap {
            guard let cost = $0.costBpm, let strokes = $0.strokes, strokes > 0 else { return nil }
            return (cost, strokes)
        }
        s.bpmPerStrokeCoverage = HrCoverage(valid: rated.count, total: takeoffEvents.count)
        if !rated.isEmpty {
            let strokes = rated.reduce(0) { $0 + $1.strokes }
            s.bpmPerStroke = rated.reduce(0.0) { $0 + $1.cost } / Double(strokes)
            s.medianBpmPerStroke = medianOf(rated.map { $0.cost / Double($0.strokes) })
        }

        let takeoffRecovery = recovery(takeoffEvents, config)
        s.medianTakeoffRecoveryS = takeoffRecovery.medianS
        s.takeoffRecoveryCoverage = takeoffRecovery.coverage
        let swimRecovery = recovery(swimEvents, config)
        s.medianSwimRecoveryS = swimRecovery.medianS
        s.swimRecoveryCoverage = swimRecovery.coverage

        let swimValid = swimEvents.filter(\.valid)
        s.swimCostCoverage = HrCoverage(valid: swimValid.count, total: swimEvents.count)
        s.avgSwimCostBpm = mean(swimValid.compactMap(\.costBpm))
        return s
    }

    /// Median half-decay over the events that actually rose. The denominator is *those*,
    /// not every event: an attempt that never raised the heart rate has no recovery to miss.
    private static func recovery(_ events: [HrEvent],
                                 _ config: HrConfig) -> (medianS: Double?,
                                                         coverage: HrCoverage) {
        let rose = events.filter { ($0.costBpm ?? -.infinity) >= config.minRiseBpm }
        let got = rose.compactMap(\.recoveryHalfS)
        return (medianOf(got), HrCoverage(valid: got.count, total: rose.count))
    }

    // MARK: - Stats

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func medianOf(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : Evidence.median(values)
    }
}
