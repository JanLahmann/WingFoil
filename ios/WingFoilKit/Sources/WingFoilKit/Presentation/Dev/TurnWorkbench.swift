import Foundation

/// **The dev workbench's shared input** — everything a turn's trace and its evidence table are
/// re-derived from, rebuilt once per session from the stored analysis and the archived track.
///
/// **It is presentation, not engine.** Nothing here decides anything: the verdicts on the page
/// stay the ones in `SessionAnalysis`, and this exists so a reader can be *shown the working*
/// behind them — which sample the entry speed was read at, why the outcome window closed where
/// it did, what the quiet tail found. The channels are the engine's own
/// (`TrackCleaner` → `FlightSegmenter` → `Evidence.build`), rebuilt with the config the stored
/// analysis echoes, so what the page draws is what the run actually read.
///
/// **Where the echo cannot say, it says so.** `AnalysisConfig` gained several turn fields late
/// (`turnContinueRate`, `entrySpeedWindow`, `minSpeedLag`, `turnRecoverHold`, `turnCleanQuietS`,
/// the two axis angles, `turnClassifyMinAngle`), so a document written by an older engine simply
/// omits them. Those fall back to `TurnConfig`'s published default and are named in
/// `assumedDefaults`, because a trace that quietly assumed 3 s where the run used 5 s would be a
/// confident wrong answer — the one thing a workbench must never give.
///
/// Pure and in the kit for the reason `TurnSlice` is: the re-derivation is a claim about the
/// session that is invisible in a screenshot until it disagrees with the record, and it belongs
/// where a test can hold it. The app gates its *use* behind `#if TUNING`; there is no `#if` here.
public enum TurnWorkbench {

    /// One session's rebuilt channels, plus the config they were rebuilt with.
    public struct Context: Sendable {
        /// The cleaned track the engine scored on — the maneuver channel, the gaps, the
        /// barometer.
        public var clean: CleanTrack
        /// The three outcome channels, whole-track. nil only on an empty recording.
        public var evidence: OffFoilEvidence?
        /// The accelerometer band, where the source carried one.
        public var pump: PumpTrack?
        /// The flight ends the quiet tail reads, rebuilt from the stored records rather than
        /// re-classified: the document already knows how each loss was called, and asking the
        /// classifier again would answer with *this* build's ladder rather than the run's.
        public var ends: [FlightEnd]
        /// The turn parameters in force, as far as the echo could say.
        public var turn: TurnConfig
        /// Echo fields the document did not carry, where `TurnConfig`'s default was assumed.
        /// Named exactly as docs/algorithms.md names them.
        public var assumedDefaults: [String]
        /// Degrees the wind blows **from**, for the TWA column — the caller's value (the
        /// rider's own, then the estimate) or nil where the session has neither.
        public var windDirDeg: Double?

        public init(clean: CleanTrack, evidence: OffFoilEvidence?, pump: PumpTrack?,
                    ends: [FlightEnd], turn: TurnConfig, assumedDefaults: [String],
                    windDirDeg: Double?) {
            self.clean = clean
            self.evidence = evidence
            self.pump = pump
            self.ends = ends
            self.turn = turn
            self.assumedDefaults = assumedDefaults
            self.windDirDeg = windDirDeg
        }
    }

    /// Rebuilds one session's channels from its stored analysis and its archived recording.
    ///
    /// `windDirDeg` is the caller's, because the rider's own declared wind (session dev field
    /// 39) lives on the track's watch summary rather than in the analysis, and the turn detail
    /// page already resolves the two in one place (`SessionDetail.windDirDeg`). Passing it in
    /// keeps one answer per session rather than two.
    public static func context(analysis: SessionAnalysis, track: RawTrack,
                               windDirDeg: Double? = nil) -> Context {
        let echo = analysis.config
        var filter = FilterConfig()
        filter.maxHdop = echo.maxHdop
        filter.minSatellites = echo.minSatellites
        filter.maxAccelMps2 = echo.maxAccel1Hz
        filter.gapMinS = echo.gapMinS
        filter.gapFactor = echo.gapFactor

        var flight = FlightConfig()
        flight.foilEntrySpeedKmh = echo.foilEntrySpeed
        flight.foilExitSpeedKmh = echo.foilExitSpeed
        flight.entryHoldS = echo.entryHold
        flight.exitHoldS = echo.exitHold
        flight.minFlightDurationS = echo.minFlightDuration

        var pumpConfig = PumpConfig()
        pumpConfig.strokeAmpG = echo.pumpStrokeAmp
        pumpConfig.minStrokes = echo.pumpMinStrokes
        if let peak = echo.pumpBurstPeakG { pumpConfig.burstPeakG = peak }
        if let speed = echo.pumpMinSpeedKmh { pumpConfig.minSpeedKmh = speed }

        let (turn, assumed) = turnConfig(from: echo)
        let clean = TrackCleaner.clean(track, config: filter)
        let flights = FlightSegmenter.segment(clean, config: flight)
        let evidence = Evidence.build(clean, flights: flights,
                                      exitSpeedKmh: turn.foilExitSpeedKmh,
                                      baroDropM: turn.baroDropM)
        return Context(clean: clean, evidence: evidence,
                       pump: PumpAnalyzer.track(track, config: pumpConfig),
                       ends: analysis.flightEnds.map(flightEnd(from:)),
                       turn: turn, assumedDefaults: assumed,
                       windDirDeg: windDirDeg
                        ?? analysis.wind.flatMap { $0.usable ? $0.dirDeg : nil })
    }

    /// The turn parameters the run used, and the names of the ones the echo could not say.
    public static func turnConfig(from echo: AnalysisConfig) -> (TurnConfig, [String]) {
        var turn = TurnConfig()
        var assumed: [String] = []
        func take(_ value: Double?, _ name: String, into keyPath: WritableKeyPath<TurnConfig, Double>) {
            if let value { turn[keyPath: keyPath] = value } else { assumed.append(name) }
        }
        turn.minAngleDeg = echo.turnMinAngle
        turn.maxDurationS = echo.turnMaxDuration
        turn.peakRateDegS = echo.turnPeakRate
        turn.minArcM = echo.turnMinArc
        turn.minRadiusM = echo.turnMinRadius
        turn.successPct = echo.turnSuccessPct
        turn.stopSpeedFloorMps = echo.turnStopSpeedFloor
        turn.touchdownMaxStopS = echo.turnTouchdownMaxStop
        turn.fallStopS = echo.turnFallStop
        turn.outcomeLookaheadS = echo.turnOutcomeLookahead
        turn.recoverPct = echo.turnRecoverPct
        turn.outcomeWindowS = echo.turnOutcomeWindow
        turn.baroDropM = echo.turnBaroDrop
        turn.foilEntrySpeedKmh = echo.foilEntrySpeed
        turn.foilExitSpeedKmh = echo.foilExitSpeed
        take(echo.turnClassifyMinAngle, "turnClassifyMinAngle", into: \.classifyMinAngleDeg)
        take(echo.turnAxisBeforeDeg, "turnAxisBeforeDeg", into: \.axisBeforeDeg)
        take(echo.turnAxisAfterDeg, "turnAxisAfterDeg", into: \.axisAfterDeg)
        take(echo.turnCleanQuietS, "turnCleanQuietS", into: \.cleanQuietS)
        take(echo.turnContinueRate, "turnContinueRate", into: \.continueRateDegS)
        take(echo.entrySpeedWindow, "entrySpeedWindow", into: \.entrySpeedWindowS)
        take(echo.minSpeedLag, "minSpeedLag", into: \.minSpeedLagS)
        take(echo.turnRecoverHold, "turnRecoverHold", into: \.recoverHoldS)
        return (turn, assumed)
    }

    /// The engine's `FlightEnd` back out of the stored record — the quiet tail's input.
    static func flightEnd(from record: FlightEndRecord) -> FlightEnd {
        var end = FlightEnd(flightIndex: record.flightIndex, t: record.ts,
                            outcome: FlightEndOutcome(rawValue: record.outcome) ?? .unknown)
        end.borderline = record.borderline
        end.offFoilS = record.offFoilS
        end.stoppedS = record.stoppedS
        end.minSpeedMps = record.minKn.map { $0 / Units.mpsToKn }
        end.pumped = record.pumped
        end.submerged = record.submerged
        end.windowS = record.windowS
        end.truncated = record.truncated
        end.ownedByTurn = record.ownedByTurn
        return end
    }

    // MARK: - The sweep's own heading series

    /// Heading and turn rate around one turn, **on the detector's own array**.
    ///
    /// The detector does not read a heading per sample of the track: it unwraps bearings over
    /// each *sailing run* — the consecutive samples whose Doppler clears `turnCogSpeedFloor`,
    /// because below that the COG is position noise rather than a heading — and the sweep it
    /// accepted lives inside one of those. Rebuilding the same run is what makes "the rate fell
    /// below `turnContinueRate` here" a statement about the number the engine actually read,
    /// rather than about a heading series invented for a table.
    ///
    /// Samples outside the run have no heading and no rate, and say so with nil rather than a 0.
    public struct HeadingSeries: Sendable {
        /// Session-clock time per element.
        public var t: [Double]
        /// Unwrapped COG in degrees, one per element; element `k` describes the step *leaving*
        /// sample `k` (`GP3SCalculator.unwrappedBearings`).
        public var u: [Double]
        /// Signed rate between consecutive elements, `count - 1` long.
        public var rate: [Double]

        /// The index of the element at or nearest before `time`, or nil outside the run.
        public func index(at time: Double) -> Int? {
            guard let first = t.first, let last = t.last, time >= first, time <= last else {
                return nil
            }
            let i = searchSortedRight(t, time) - 1
            return t.indices.contains(i) ? i : nil
        }

        public func heading(at time: Double) -> Double? {
            index(at: time).map { TurnSlice.normalize(u[$0]) }
        }

        /// The rate *leaving* the element at `time`, in °/s.
        public func rate(at time: Double) -> Double? {
            guard let i = index(at: time), rate.indices.contains(i) else { return nil }
            return rate[i]
        }

        /// The rate *into* the element at `time` — the one `TurnDetector.trim` reads when it
        /// decides whether to shrink the sweep off this sample. The sweep's last step is above
        /// `turnContinueRate` by construction; the step *after* it is not, and confusing the
        /// two is how a trace comes to print a number that contradicts its own sentence.
        public func rateInto(at time: Double) -> Double? {
            guard let i = index(at: time), rate.indices.contains(i - 1) else { return nil }
            return rate[i - 1]
        }
    }

    /// The sailing run that contains `[startT, endT]`, unwrapped like the detector does it.
    public static func headingSeries(_ clean: CleanTrack, from startT: Double, to endT: Double,
                                     config: TurnConfig) -> HeadingSeries? {
        for seg in clean.segments where seg.count >= 3 {
            let t = seg.map { clean.samples[$0].t }
            guard let first = t.first, let last = t.last, startT >= first, startT <= last else {
                continue
            }
            let x = seg.map { clean.samples[$0].x ?? .nan }
            let y = seg.map { clean.samples[$0].y ?? .nan }
            let ok = seg.map { clean.samples[$0].dopplerMps >= config.minCogSpeedMps }
            for (a, b) in TurnDetector.sailingRuns(ok) {
                let u = GP3SCalculator.unwrappedBearings(x: Array(x[a...b]), y: Array(y[a...b]))
                guard !u.isEmpty else { continue }
                let tu = Array(t[a..<(a + u.count)])
                guard let lo = tu.first, let hi = tu.last, startT >= lo, startT <= hi else {
                    continue
                }
                return HeadingSeries(t: tu, u: u, rate: TurnDetector.rates(tu, u))
            }
        }
        return nil
    }

    /// True wind angle for a heading, −180…180, or nil without a wind.
    public static func twa(heading: Double?, windDirDeg: Double?) -> Double? {
        guard let heading, let windDirDeg else { return nil }
        return WindEstimator.wrap180(heading - windDirDeg)
    }
}
