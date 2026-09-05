import Foundation

/// The marker-eligibility rules of `docs/presentation.md`, in one place, plus the counts
/// they produce.
///
/// The session-detail views used to carry these conditions inline — "flight ends no turn
/// owns", "pumping episodes the classifier called failed" — and so did the web app, in
/// JavaScript, on the other side of the repo. Two copies of a rule that can only be
/// checked by looking at a screenshot is exactly how a marker quietly appears on one
/// platform and not the other.
///
/// So the rules live here, the app's builders iterate through them, and
/// `fixtures/presentation/*.expected.json` pins the counts they produce on every corpus
/// fixture — the same file the web verification asserts against. A count that differs
/// between the platforms is a failing test, not a bug report.
public enum PresentationRules {

    /// The chip an outcome answers to. An uncounted turn is a bear-away or a round-up:
    /// a course change, never a verdict, whatever its outcome field says.
    public static func layer(for turn: TurnRecord) -> MapLayer {
        guard turn.counted else { return .courseChange }
        return layer(forOutcome: turn.outcome)
    }

    /// The ladder. `glide_out` is a flight that ended without drama, which is the green
    /// end of it — the same reading `SessionDetail.outcomeTone` has always had.
    public static func layer(forOutcome outcome: String) -> MapLayer {
        switch TurnOutcomeKind(outcome) {
        case .fellIn: return .fellIn
        case .touchdown: return .touchdown
        case .flewThrough: return .flewThrough
        }
    }

    /// The straight-line flight ends that get a (hollow) marker: the ones no turn already
    /// explains — marking both would draw one swim twice — from a recording that did not
    /// simply stop mid-flight.
    public static func drawnFlightEnds(_ analysis: SessionAnalysis) -> [FlightEndRecord] {
        analysis.flightEnds.filter { $0.ownedByTurn == nil && !$0.truncated }
    }

    /// The attempts that produced nothing. `success` is the same event as the takeoff
    /// drawn beside it, `recovery` is pumping the foil back after a touchdown, `inFlight`
    /// is holding a glide, and `unknown` is a recording that stopped before it could be
    /// judged — none of them is an attempt at getting up, and none is ever drawn.
    public static func failedAttempts(_ analysis: SessionAnalysis) -> [PumpEpisodeRecord] {
        analysis.pumpEpisodes.filter { $0.outcome == .failed }
    }

    /// Pump-burst spans: the attempts, both halves. The other three outcomes are counted
    /// by the engine and drawn by nobody.
    public static func attemptEpisodes(_ analysis: SessionAnalysis) -> [PumpEpisodeRecord] {
        analysis.pumpEpisodes.filter { $0.outcome == .success || $0.outcome == .failed }
    }

    /// The **clean jibes**: the engine's own per-turn `clean` verdict — counted, named a
    /// jibe, it carried its speed *and* it flew through (docs/presentation.md, "Clean
    /// jibe"). The map draws each of these as a star instead of its outcome dot, and the
    /// same list is what the `cleanJibe` chip counts.
    ///
    /// One definition, spelled once, and since engine 0.12.0 it is spelled in the engine:
    /// the rule is no longer re-derived here or in the web's `session.js`, both of which
    /// read the stored flag. That is what stopped a jibe from being starred as clean on the
    /// map and listed as a swim six rows below it.
    public static func cleanJibes(_ analysis: SessionAnalysis) -> [TurnRecord] {
        analysis.turns.filter(\.clean)
    }

    /// Turns whose swim the barometer actually saw. Evidence, not a census — and the UI
    /// never re-derives it.
    public static func splashTurns(_ analysis: SessionAnalysis) -> [TurnRecord] {
        analysis.turns.filter { $0.submerged && $0.counted }
    }

    /// The same evidence on the other channel, under the same ownership rule.
    public static func splashEnds(_ analysis: SessionAnalysis) -> [FlightEndRecord] {
        drawnFlightEnds(analysis).filter(\.submerged)
    }

    /// The records this session can highlight: a value *and* the window provenance the map
    /// draws with it. A record with neither is inert and says nothing.
    public static func achievedRecordWindows(_ analysis: SessionAnalysis) -> [String] {
        RecordWindowSelection.catalogue.compactMap { kind in
            guard let kn = kind.value(in: analysis.records), kn > 0,
                  analysis.records.windows[kind.rawValue] != nil else { return nil }
            return kind.rawValue
        }
    }
}

/// Everything a session-detail screen may draw, as counts — the shape
/// `fixtures/presentation/*.expected.json` pins.
public struct PresentationFacts: Sendable, Equatable {

    /// Turn outcomes and straight-line flight ends, by the chip they answer to.
    public struct MarkerCounts: Sendable, Equatable {
        public var flewThrough = 0
        public var touchdown = 0
        public var fellIn = 0
        public var courseChange = 0

        public init(flewThrough: Int = 0, touchdown: Int = 0, fellIn: Int = 0,
                    courseChange: Int = 0) {
            self.flewThrough = flewThrough
            self.touchdown = touchdown
            self.fellIn = fellIn
            self.courseChange = courseChange
        }

        public var total: Int { flewThrough + touchdown + fellIn + courseChange }

        public func count(_ layer: MapLayer) -> Int {
            switch layer {
            case .flewThrough: return flewThrough
            case .touchdown: return touchdown
            case .fellIn: return fellIn
            case .courseChange: return courseChange
            default: return 0
            }
        }

        mutating func add(_ layer: MapLayer) {
            switch layer {
            case .flewThrough: flewThrough += 1
            case .touchdown: touchdown += 1
            case .fellIn: fellIn += 1
            case .courseChange: courseChange += 1
            default: break
            }
        }
    }

    /// Every flight end, in the three buckets the marker rules already distinguish.
    ///
    /// They partition the block, so `total` is also the flight count — which is the point:
    /// one end stops every flight, and the pairing line a callout draws ("ends flight 12 ·
    /// started 41:07") is only meaningful while that holds. A flight with two ends would
    /// print a wrong number in a popover long before any tally looked odd.
    public struct FlightEndCounts: Sendable, Equatable {
        /// The hollow mark: no turn owns it, the recording did not stop.
        public var drawn = 0
        /// A turn's outcome window already explains it; marking both would draw one swim
        /// twice.
        public var ownedByTurn = 0
        /// The recording stopped, not the flight.
        public var truncated = 0

        public init(drawn: Int = 0, ownedByTurn: Int = 0, truncated: Int = 0) {
            self.drawn = drawn
            self.ownedByTurn = ownedByTurn
            self.truncated = truncated
        }

        public var total: Int { drawn + ownedByTurn + truncated }
    }

    /// One chip, three glyphs: the takeoff layer's split.
    public struct TakeoffCounts: Sendable, Equatable {
        public var pumped = 0
        public var free = 0
        public var failed = 0

        public init(pumped: Int = 0, free: Int = 0, failed: Int = 0) {
            self.pumped = pumped
            self.free = free
            self.failed = failed
        }

        public var total: Int { pumped + free + failed }
    }

    /// One row of the filter grid: what a type × entry-side combination keeps, and how
    /// much of it flew through.
    public struct FilterTally: Sendable, Equatable {
        public let type: TurnTypeFilter
        public let side: TurnSideFilter
        public let count: Int
        public let flewThrough: Int

        public init(type: TurnTypeFilter, side: TurnSideFilter, count: Int,
                    flewThrough: Int) {
            self.type = type
            self.side = side
            self.count = count
            self.flewThrough = flewThrough
        }
    }

    /// The engine's own flight count — the number both blocks below have to add up to
    /// (docs/presentation.md "Enforcement" 3).
    public let flightCount: Int
    public let markers: MarkerCounts
    /// **Clean jibes** — the star layer (docs/presentation.md, "Clean jibe"). Deliberately
    /// *not* one of `markers`: those partition the turns and the drawn flight ends one mark
    /// each, and a clean jibe is already counted there under whatever outcome it ended on.
    /// This is the second, stricter reading laid over the same set, and adding it to the
    /// ladder's counts would break the one invariant they are worth pinning for.
    public let cleanJibes: Int
    public let flightEnds: FlightEndCounts
    public let takeoff: TakeoffCounts
    public let splash: Int
    public let pumpingSpans: Int
    /// Catalogue order, achieved windows only.
    public let recordWindows: [String]
    /// What the session opens on: the default when it was achieved, otherwise nothing
    /// rather than an arbitrary substitute.
    public let defaultRecordWindow: String?
    /// Every type × side combination, in catalogue order (both/jibes/tacks × both/port/
    /// starboard).
    public let filters: [FilterTally]

    public init(_ analysis: SessionAnalysis) {
        flightCount = analysis.summary.flightCount
        flightEnds = FlightEndCounts(
            drawn: PresentationRules.drawnFlightEnds(analysis).count,
            ownedByTurn: analysis.flightEnds.filter { $0.ownedByTurn != nil && !$0.truncated }
                .count,
            truncated: analysis.flightEnds.filter(\.truncated).count)

        var markers = MarkerCounts()
        for turn in analysis.turns { markers.add(PresentationRules.layer(for: turn)) }
        for end in PresentationRules.drawnFlightEnds(analysis) {
            markers.add(PresentationRules.layer(forOutcome: end.outcome))
        }
        self.markers = markers
        cleanJibes = PresentationRules.cleanJibes(analysis).count

        let free = analysis.takeoffs.filter(\.free).count
        takeoff = TakeoffCounts(pumped: analysis.takeoffs.count - free, free: free,
                                failed: PresentationRules.failedAttempts(analysis).count)

        splash = PresentationRules.splashTurns(analysis).count
            + PresentationRules.splashEnds(analysis).count
        pumpingSpans = PresentationRules.attemptEpisodes(analysis).count

        let windows = PresentationRules.achievedRecordWindows(analysis)
        recordWindows = windows
        defaultRecordWindow = RecordWindowSelection.initial(available: Set(windows))

        var tallies: [FilterTally] = []
        for type in TurnTypeFilter.allCases {
            for side in TurnSideFilter.allCases {
                let filter = TurnFilter(type: type, side: side)
                let tally = TurnAnalytics.tally(analysis.turns, filter: filter)
                tallies.append(FilterTally(type: type, side: side, count: tally.total,
                                           flewThrough: tally.flewThrough))
            }
        }
        filters = tallies
    }

    /// The legend's "is this chip a live toggle?" counts, from the same rules.
    public var layerTally: MapLayerTally {
        var tally = MapLayerTally()
        tally.add(.flewThrough, markers.flewThrough)
        tally.add(.touchdown, markers.touchdown)
        tally.add(.fellIn, markers.fellIn)
        tally.add(.courseChange, markers.courseChange)
        tally.add(.cleanJibe, cleanJibes)
        tally.add(.takeoff, takeoff.total)
        tally.add(.splash, splash)
        tally.add(.pumping, pumpingSpans)
        return tally
    }
}
