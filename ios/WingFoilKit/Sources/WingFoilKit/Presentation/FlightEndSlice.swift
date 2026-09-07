import Foundation

/// **One straight-line flight end, cut out of the session and put in its own frame** — the
/// turn detail sheet's picture, for the losses no turn owns.
///
/// Half of a session's swims do not happen in a maneuver. A gust dies, the foil ventilates,
/// a tip catches on a reach: the engine has classified every one of those since it started
/// carrying `flightEnds`, and the map has drawn them as hollow rings for as long — but the
/// ring was the end of the road. Tapping it said "Fell in · straight-line · stopped 7 s" and
/// there was nowhere to go. Every question a rider asks of a jibe he asks of a fall on a
/// reach too: how fast was I going, how long was I in the water, did I pump back out.
///
/// **What is genuinely different from a turn, and therefore what this type does not
/// pretend.** A flight end is an *instant*, not a sweep: there is no arc, no entry tack, no
/// rotation, no score and no wind-axis crossing. So `t = 0` is the end itself, the drawn
/// window is `[−padBefore, +padAfter]` around it, `durationS` is zero and the figure's
/// `axisRt` is always nil. Everything else — the projection, the wind-up rotation, the
/// ticks, the ring, the outcome dot — is the same picture, drawn by the same `Canvas`
/// through `ManeuverFigure`.
///
/// **It derives, it never re-decides.** `outcome`, `stoppedS`, `offFoilS`, `minKn`,
/// `pumped` and `submerged` are the engine's and stay the engine's. Definitions:
/// docs/algorithms.md "Flight-end outcome", docs/presentation.md "Flight-end detail".
public struct FlightEndSlice: Sendable, Equatable {

    // MARK: - Output

    /// The speeds the strip marks. Only one of the three is the engine's, and the type says
    /// which — see each field.
    public struct SpeedMarks: Sendable, Equatable {
        /// **Read on this window, not from the record.** The maximum of the drawn channel
        /// over the entry window (`entrySpeedWindowS` before the end) — the same *rule* the
        /// classifier's recovery threshold uses, on the channel this strip draws. A flight
        /// end record carries no entry speed at all, so there is nothing to print instead;
        /// the footnote says out loud that this number is the picture's and not the verdict's.
        public var entryKn: Double
        public var entryRt: Double
        /// **The engine's** `minKn` — the slowest sample of the off-foil run — placed at the
        /// sample of the drawn window nearest that value, the same trick `TurnSlice` uses for
        /// the entry mark. nil where the record carries none, which is every end whose
        /// off-foil run was never entered.
        public var lowKn: Double?
        public var lowRt: Double?
        /// The drawn channel where the rider was flying again — `recoverPct` of the entry
        /// speed, the classifier's own threshold — and nil where he never got there inside
        /// the window, which is exactly what a fall looks like.
        public var outKn: Double?
        public var recoverRt: Double?

        public init(entryKn: Double, entryRt: Double, lowKn: Double?, lowRt: Double?,
                    outKn: Double?, recoverRt: Double?) {
            self.entryKn = entryKn
            self.entryRt = entryRt
            self.lowKn = lowKn
            self.lowRt = lowRt
            self.outKn = outKn
            self.recoverRt = recoverRt
        }
    }

    /// The windows the classifier read, on the end's own clock — what the strip shades and
    /// names, exactly as the turn strip does.
    public struct Windows: Sendable, Equatable {
        /// `−entryS … 0`: the speed the flight was ending at.
        public var entryS: Double
        /// `0 … outcomeS`: the lookahead the verdict is read from.
        public var outcomeS: Double
        /// `0 … windowS`: how much gap-free evidence there actually **was** past the end.
        /// Drawn because it is the one window that is a property of the recording rather
        /// than of the configuration — a `truncated` end is one where this is nothing.
        public var evidenceS: Double

        public init(entryS: Double, outcomeS: Double, evidenceS: Double) {
            self.entryS = entryS
            self.outcomeS = outcomeS
            self.evidenceS = evidenceS
        }
    }

    // MARK: - Stored

    public let end: FlightEndRecord
    /// The drawing's input — see `ManeuverFigure`.
    public let figure: ManeuverFigure
    public let speed: SpeedMarks
    public let windows: Windows
    public let padBeforeS: Double
    public let padAfterS: Double

    public var hasGeometry: Bool { figure.hasGeometry }
    public var points: [TurnSlice.Point] { figure.points }
    public var timeDomain: ClosedRange<Double> { figure.timeDomain }
    public var windDirDeg: Double? { figure.windDirDeg }

    public func points(windUp: Bool) -> [TurnSlice.Point] { figure.points(windUp: windUp) }
    public func point(atRelative rt: Double, windUp: Bool) -> TurnSlice.Point? {
        figure.point(atRelative: rt, windUp: windUp)
    }

    // MARK: - Building

    /// Cuts the flight end out of `samples`, which must be in time order and carry positions.
    ///
    /// The projection is anchored on the **end itself** rather than on the window's centroid,
    /// for the reason `TurnSlice` anchors on the entry: the thing the page is about sits at
    /// the origin, and a reader looking for it does not have to find it first.
    public static func make(samples: [TurnSlice.Sample], end: FlightEndRecord,
                            windDirDeg: Double?,
                            config: FlightEndConfig = FlightEndConfig(),
                            padBeforeS: Double = TurnSlice.defaultPadS,
                            padAfterS: Double = TurnSlice.defaultPadS) -> FlightEndSlice {
        let before = max(padBeforeS, 0)
        let after = max(padAfterS, 0)
        let window = samples.filter { $0.t >= end.ts - before && $0.t <= end.ts + after }
        let windows = Windows(entryS: config.entrySpeedWindowS,
                              outcomeS: config.outcomeLookaheadS,
                              evidenceS: end.windowS)
        let marks = Self.marks(window, end: end, config: config)
        let domain = -before ... max(after, -before + 1)

        guard let anchor = TurnSlice.nearest(window, t: end.ts)
                ?? TurnSlice.nearest(samples, t: end.ts) else {
            return FlightEndSlice(end: end,
                                  figure: figure(points: [], windUp: nil, windDirDeg: windDirDeg,
                                                 marks: marks, end: end, domain: domain),
                                  speed: marks, windows: windows,
                                  padBeforeS: before, padAfterS: after)
        }
        let cosLat = cos(anchor.lat * .pi / 180)
        var points: [TurnSlice.Point] = []
        points.reserveCapacity(window.count)
        for sample in window {
            points.append(TurnSlice.Point(x: (sample.lon - anchor.lon) * cosLat * 111_320,
                                          y: (sample.lat - anchor.lat) * 110_540,
                                          rt: sample.t - end.ts,
                                          kn: sample.kn,
                                          // The flight is what came *before*: everything at
                                          // or after the end is already off the foil, so the
                                          // thick, speed-coloured part is the run-in.
                                          inTurn: sample.t <= end.ts,
                                          altM: sample.altM))
        }
        TurnSlice.applyHeadings(&points)
        let up = windDirDeg.map { TurnSlice.rotated(points, windFromDeg: $0) }
        return FlightEndSlice(end: end,
                              figure: figure(points: points, windUp: up,
                                             windDirDeg: windDirDeg, marks: marks, end: end,
                                             domain: domain),
                              speed: marks, windows: windows,
                              padBeforeS: before, padAfterS: after)
    }

    private static func figure(points: [TurnSlice.Point], windUp: [TurnSlice.Point]?,
                               windDirDeg: Double?, marks: SpeedMarks,
                               end: FlightEndRecord,
                               domain: ClosedRange<Double>) -> ManeuverFigure {
        ManeuverFigure(points: points, windUpPoints: windUp,
                       bounds: TurnSlice.Bounds.around(points)?.padded(),
                       windUpBounds: windUp.flatMap(TurnSlice.Bounds.around)?.padded(),
                       windDirDeg: windDirDeg,
                       entryKn: marks.entryKn,
                       lowRt: points.count >= 2 ? marks.lowRt : nil,
                       // The filled outcome dot goes on the end itself, which is the origin.
                       endRt: points.count >= 2 ? 0 : nil,
                       outcome: end.outcome,
                       // A flight end crosses no wind axis: it is not a maneuver, and the
                       // engine records no crossing for one. Absent, never zeroed.
                       axisRt: nil,
                       timeDomain: domain,
                       // A flight end is an instant. The thick part of the line is the
                       // approach, and the shaded band on the strip is the outcome window.
                       durationS: 0,
                       title: "Flight end")
    }

    /// The three marks. Only `lowKn` is the engine's; the other two are read off this window
    /// and are labelled as such wherever they are printed.
    private static func marks(_ window: [TurnSlice.Sample], end: FlightEndRecord,
                              config: FlightEndConfig) -> SpeedMarks {
        let entryWindow = window.filter {
            $0.t >= end.ts - config.entrySpeedWindowS && $0.t <= end.ts
        }
        let entryAt = entryWindow.max { $0.kn < $1.kn }
        let entryKn = entryAt?.kn ?? 0
        let lowAt = end.minKn.flatMap { low in
            window
                .filter { $0.t >= end.ts }
                .min { abs($0.kn - low) < abs($1.kn - low) }
        }
        let threshold = max(config.recoverPct / 100 * entryKn,
                            config.foilEntrySpeedKmh / Units.mpsToKmh * Units.mpsToKn)
        let recoverAt = window.first { $0.t > end.ts && $0.kn >= threshold }
        return SpeedMarks(entryKn: entryKn,
                          entryRt: entryAt.map { $0.t - end.ts } ?? 0,
                          lowKn: end.minKn,
                          lowRt: lowAt.map { $0.t - end.ts },
                          outKn: recoverAt?.kn,
                          recoverRt: recoverAt.map { $0.t - end.ts })
    }
}

/// The rider's words for a flight end — the same sentence shape `TurnAnalytics` gives a turn,
/// composed from the record's own fields.
///
/// It is here rather than in the view for the reason every other spelling is: the map's
/// callout, the Log tab's row and the detail page's header all print it, and three copies of
/// "stopped %.0f s" is three places for it to drift.
public enum FlightEndAnalytics {

    /// "Glided out", "Touchdown", "Fell in" — and never the turn ladder's "flew through",
    /// which is a verdict a flight end cannot earn: by the time there is a flight end the
    /// rider is off the foil by definition.
    public static func outcomeLabel(_ outcome: String) -> String {
        switch outcome {
        case "fell_in": return "fell in"
        case "touchdown": return "touchdown"
        case "glide_out": return "glided out"
        default: return "unknown"
        }
    }

    /// **"fell in · stopped 7 s · wrist under"** — the outcome, then the evidence that made
    /// it, in the order the ladder settles them.
    ///
    /// Only what is there: a stop of under a second is not printed (at 1 Hz it is one sample,
    /// and "0 s" would read as a measurement), and a `truncated` end says the one true thing
    /// about itself instead of a verdict it does not have.
    public static func outcomeText(_ end: FlightEndRecord) -> String {
        guard !end.truncated, end.outcome != "unknown" else {
            return "the recording ended, not the flight"
        }
        var parts = [outcomeLabel(end.outcome)]
        if end.borderline { parts[0] += " (borderline)" }
        if end.stoppedS.rounded() >= 1 {
            parts.append(String(format: "stopped %.0f s", end.stoppedS))
        } else if end.offFoilS.rounded() >= 1 {
            // Off-foil seconds only where there is no stop to print: a rider who stopped was
            // off the foil too, and saying both is saying the same loss twice.
            parts.append(String(format: "off the foil %.0f s", end.offFoilS))
        }
        if end.submerged { parts.append("wrist under") }
        if end.pumped { parts.append("pumped out") }
        return parts.joined(separator: " · ")
    }

    /// The drawn flight ends with their position in the swipeable set — "3 of 9". One place,
    /// because the map's sheet and the Log tab's rows must open the *same* set in the same
    /// order or "next" means two different things on two screens.
    public static func drawnIndices(_ analysis: SessionAnalysis) -> [Int] {
        analysis.flightEnds.indices
            .filter { analysis.flightEnds[$0].ownedByTurn == nil
                        && !analysis.flightEnds[$0].truncated }
    }
}
