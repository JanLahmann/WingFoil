import Foundation

/// **Tuning: the published defaults, moved by hand, on one phone.**
///
/// Every number in docs/algorithms.md is a *contract* — the watch, the lab and the web all
/// hold to it, and a session analysed on one of them has to come out the same on the others.
/// Tuning is the deliberate exception, and it is deliberately small: an optional override per
/// parameter, held on **this device only**, applied to the engine configs on the way into
/// `SessionSummarizer.analyze` and nowhere else.
///
/// It exists because tuning a threshold used to mean editing a Swift file, rebuilding, and
/// re-importing a corpus — an afternoon per question. A slider answers the same question in a
/// minute, against the rider's own sessions, on the water.
///
/// **The rules that keep it honest.**
/// - `nil` means "the published default". An override that is *set* to the default is dropped
///   rather than stored, so `changedCount` never counts a knob that changes nothing and the
///   fingerprint of "all defaults" is the fingerprint of "nothing set".
/// - The fingerprint goes into the analysis' `engineVersion` (`TuningStamp`), which is the
///   staleness key `SessionIngestor.reanalyzeStale()` already sweeps on. So a moved slider
///   makes every stored analysis stale exactly the way an engine bump does, and the library
///   re-derives itself lazily — no new mechanism, and no way to end up with half a library
///   analysed one way and half the other.
/// - Because the fingerprint rides in `engineVersion`, every number the app then shows can be
///   traced back to a tuned run — which is what the "tuned thresholds" chip in the session
///   header, in Records and in Trends reads, and why a tuned number can never be mistaken for
///   a published one on a share card or in a trend line.
///
/// Phone-only, on purpose: the watch computes live with no way to be told, and the web reads
/// documents the phone wrote. Neither is asked to follow a slider on someone's phone.
public struct TuningOverrides: Sendable, Equatable {

    /// Override values, keyed by `TuningParameter.rawValue` — the docs/algorithms.md name, so
    /// the stored JSON reads as the parameter table it overrides. A `[String: Double]` rather
    /// than a wall of `Double?` properties because every consumer here is generic over the
    /// parameter list (the page, the reset, the fingerprint), and an unknown key from a newer
    /// build is then simply dropped instead of failing the whole decode.
    public private(set) var values: [String: Double]

    public init() { values = [:] }

    /// Sanitising initialiser: unknown names are dropped, values are clamped into the
    /// parameter's range, and anything equal to the published default is dropped as a no-op.
    public init(values: [String: Double]) {
        self.values = [:]
        for (name, value) in values {
            guard let parameter = TuningParameter(rawValue: name) else { continue }
            self[parameter] = value
        }
    }

    // MARK: - Access

    /// The override for one parameter, or nil where the published default stands. Setting the
    /// default value (or nil, or NaN) clears the override rather than storing it.
    public subscript(parameter: TuningParameter) -> Double? {
        get { values[parameter.rawValue] }
        set {
            let spec = parameter.spec
            guard let newValue, newValue.isFinite else {
                values[parameter.rawValue] = nil
                return
            }
            // Rounded to the precision the fingerprint is taken at, so a slider that lands on
            // 0.9999999999 and one that lands on 1.0 are the same setting rather than two
            // different libraries. Same reason the default test is a tolerance and not `==`:
            // a `Slider` stepping 0.1 from 0.3 does not reach 1.0 exactly, and a rider who
            // drags a knob back to its default has cleared it, not set it.
            let clamped = min(max(newValue, spec.range.lowerBound), spec.range.upperBound)
            let snapped = (clamped * 10_000).rounded() / 10_000
            if abs(snapped - spec.defaultValue) < 1e-6 {
                values[parameter.rawValue] = nil
            } else {
                values[parameter.rawValue] = snapped
            }
        }
    }

    /// What the engine will actually use: the override where there is one, the published
    /// default where there is not. This is the number the tuning page prints.
    public func value(for parameter: TuningParameter) -> Double {
        values[parameter.rawValue] ?? parameter.spec.defaultValue
    }

    public func isOverridden(_ parameter: TuningParameter) -> Bool {
        values[parameter.rawValue] != nil
    }

    public mutating func reset(_ parameter: TuningParameter) {
        values[parameter.rawValue] = nil
    }

    public mutating func resetAll() { values = [:] }

    /// Nothing overridden — the published contract, unmodified.
    public var isEmpty: Bool { values.isEmpty }

    /// How many parameters stand away from their published default. The number the chip and
    /// the banner say out loud.
    public var changedCount: Int { values.count }

    /// Every override, in the parameter table's own order, for a page that lists them.
    public var changed: [(parameter: TuningParameter, value: Double)] {
        TuningParameter.allCases.compactMap { parameter in
            values[parameter.rawValue].map { (parameter, $0) }
        }
    }

    // MARK: - Applying (the one pure function)

    /// The three engine configs the tuning can move, together. They travel as one struct
    /// because several parameters live in more than one of them and *must* move together —
    /// see `apply(to:)`.
    public struct Configs: Sendable, Equatable {
        public var turn: TurnConfig
        public var flight: FlightConfig
        public var flightEnd: FlightEndConfig

        public init(turn: TurnConfig = TurnConfig(),
                    flight: FlightConfig = FlightConfig(),
                    flightEnd: FlightEndConfig = FlightEndConfig()) {
            self.turn = turn
            self.flight = flight
            self.flightEnd = flightEnd
        }
    }

    /// Applies every override to a set of configs. Pure: same input, same output, no clock, no
    /// defaults file, no I/O.
    ///
    /// **Three parameters land in more than one config, and all three must.**
    /// - `foilEntrySpeed` / `foilExitSpeed` are the flight hysteresis *and* the turn's success
    ///   floor and recovery floor *and* the flight-end ladder's. Moving the flight's alone
    ///   would leave the turn scorer judging against a speed no flight is segmented on.
    /// - `entrySpeedWindow` is read identically by the turn scorer and the flight-end
    ///   classifier ("the speed it was going at before").
    /// - The stop ladder (`turnStopSpeedFloor`, `turnTouchdownMaxStop`, `turnFallStop`,
    ///   `turnOutcomeLookahead`, `turnRecoverPct`, `turnRecoverHold`) is one physical question
    ///   — did the rider stop, and for how long — and `FlightEndConfig` says in its own doc
    ///   comment that it carries the same numbers on purpose. So they move as a pair.
    ///
    /// The one deliberate exception is `turnOutcomeWindow`: the turn's is 12 s and the flight
    /// end's is 60 s, they are *not* the same number today, and pushing the turn's slider onto
    /// the flight end would silently move a threshold the rider did not touch. It moves the
    /// turn config only.
    public func apply(to base: Configs = Configs()) -> Configs {
        var out = base
        // Turns — detection and scoring.
        if let v = self[.turnMinAngle] { out.turn.minAngleDeg = v }
        if let v = self[.turnClassifyMinAngle] { out.turn.classifyMinAngleDeg = v }
        if let v = self[.turnMaxDuration] { out.turn.maxDurationS = v }
        if let v = self[.turnPeakRate] { out.turn.peakRateDegS = v }
        if let v = self[.turnContinueRate] { out.turn.continueRateDegS = v }
        if let v = self[.turnMinArc] { out.turn.minArcM = v }
        if let v = self[.turnMinRadius] { out.turn.minRadiusM = v }
        if let v = self[.turnSuccessPct] { out.turn.successPct = v }
        if let v = self[.minSpeedLag] { out.turn.minSpeedLagS = v }
        // Shared by the turn scorer and the flight-end classifier.
        if let v = self[.entrySpeedWindow] {
            out.turn.entrySpeedWindowS = v
            out.flightEnd.entrySpeedWindowS = v
        }
        // The stop ladder, both ends of it.
        if let v = self[.turnStopSpeedFloor] {
            out.turn.stopSpeedFloorMps = v
            out.flightEnd.stopSpeedFloorMps = v
        }
        if let v = self[.turnTouchdownMaxStop] {
            out.turn.touchdownMaxStopS = v
            out.flightEnd.touchdownMaxStopS = v
        }
        if let v = self[.turnFallStop] {
            out.turn.fallStopS = v
            out.flightEnd.fallStopS = v
        }
        if let v = self[.turnOutcomeLookahead] {
            out.turn.outcomeLookaheadS = v
            out.flightEnd.outcomeLookaheadS = v
        }
        if let v = self[.turnRecoverPct] {
            out.turn.recoverPct = v
            out.flightEnd.recoverPct = v
        }
        if let v = self[.turnRecoverHold] {
            out.turn.recoverHoldS = v
            out.flightEnd.recoverHoldS = v
        }
        if let v = self[.turnOutcomeWindow] { out.turn.outcomeWindowS = v }
        // Flights — and the two speeds every channel is judged against.
        if let v = self[.foilEntrySpeed] {
            out.flight.foilEntrySpeedKmh = v
            out.turn.foilEntrySpeedKmh = v
            out.flightEnd.foilEntrySpeedKmh = v
        }
        if let v = self[.foilExitSpeed] {
            out.flight.foilExitSpeedKmh = v
            out.turn.foilExitSpeedKmh = v
            out.flightEnd.foilExitSpeedKmh = v
        }
        if let v = self[.entryHold] { out.flight.entryHoldS = v }
        if let v = self[.exitHold] { out.flight.exitHoldS = v }
        if let v = self[.minFlightDuration] { out.flight.minFlightDurationS = v }
        return out
    }

    // MARK: - Fingerprint

    /// A stable 8-hex digest of the overrides, or nil when nothing is overridden.
    ///
    /// Stable across processes and launches, which `Hashable.hashValue` is emphatically not
    /// (Swift seeds it per process): this ends up written into stored documents and compared
    /// against on the next launch, so it is computed by hand — sorted `name=value` pairs at a
    /// fixed 4-decimal precision, FNV-1a 64.
    public var fingerprint: String? {
        guard !values.isEmpty else { return nil }
        let body = values.keys.sorted()
            .map { "\($0)=\(String(format: "%.4f", values[$0] ?? 0))" }
            .joined(separator: ";")
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in body.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return String(format: "%08x", UInt32(truncatingIfNeeded: hash >> 32)
            ^ UInt32(truncatingIfNeeded: hash))
    }

    /// The engine version a run under these overrides should be stamped with — the plain
    /// engine version when nothing is tuned, so an untuned install is byte-identical to one
    /// built before tuning existed.
    public func engineVersionKey(base: String = AnalysisEngine.version) -> String {
        TuningStamp.key(base: base, overrides: self)
    }
}

// MARK: - Codable

extension TuningOverrides: Codable {
    /// Encoded as the bare map — `{"turnPeakRate": 22, "foilExitSpeed": 7.5}` — so a stored
    /// preference reads as the parameter table it overrides, and an unknown name written by a
    /// newer build is dropped on the way in rather than failing the decode.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(values: try container.decode([String: Double].self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}

// MARK: - The stamp in `engineVersion`

/// How a tuned run marks itself: `"0.14.0+tuned.3.a1b2c3d4"` — the engine version, the number
/// of parameters moved, and the fingerprint of what they were moved to.
///
/// It rides in `SessionAnalysis.engineVersion` rather than in a field of its own because that
/// string is *already* the staleness key: `SessionIngestor.reanalyzeStale()` sweeps every row
/// whose stored version differs from the current one, `SessionArchive.analysis(for:)` refuses
/// a cached document that does not match, and `SessionStore.detail(for:)` reloads the library
/// when the two disagree. Tuning gets all of that for free, and gets it right, by changing the
/// one string all three already read.
public enum TuningStamp: Sendable {

    static let marker = "+tuned."

    public static func key(base: String = AnalysisEngine.version,
                           overrides: TuningOverrides) -> String {
        guard let fingerprint = overrides.fingerprint else { return base }
        return "\(base)\(marker)\(overrides.changedCount).\(fingerprint)"
    }

    /// Splits a stamped version back into its parts, or nil for a plain (untuned) one.
    public static func parse(_ engineVersion: String)
    -> (base: String, changed: Int, fingerprint: String)? {
        guard let range = engineVersion.range(of: marker) else { return nil }
        let base = String(engineVersion[engineVersion.startIndex..<range.lowerBound])
        let tail = engineVersion[range.upperBound...].split(separator: ".",
                                                            maxSplits: 1,
                                                            omittingEmptySubsequences: false)
        guard tail.count == 2, let changed = Int(tail[0]) else { return nil }
        return (base, changed, String(tail[1]))
    }

    /// Was this analysis produced with tuned thresholds?
    public static func isTuned(_ engineVersion: String) -> Bool {
        parse(engineVersion) != nil
    }

    /// How many parameters were moved, or nil where none were.
    public static func changedCount(_ engineVersion: String) -> Int? {
        parse(engineVersion)?.changed
    }

    /// The published engine version behind a stamped one — what "Analysis engine" means when
    /// the reader is asking which *engine*, not which tuning.
    public static func baseVersion(_ engineVersion: String) -> String {
        parse(engineVersion)?.base ?? engineVersion
    }
}

// MARK: - The parameter table

/// Which section of the tuning page a parameter belongs to.
public enum TuningGroup: String, CaseIterable, Sendable {
    case turns = "Turns"
    case outcomes = "Outcomes"
    case flights = "Flights"

    /// One sentence on what moving anything in this group does to the numbers.
    public var blurb: String {
        switch self {
        case .turns:
            "What counts as a turn at all, and how its score is measured. Loosening these "
                + "finds more turns; tightening them finds fewer, better-defined ones."
        case .outcomes:
            "The stop ladder: flew through, touched down, fell in. Shared with the flight-end "
                + "verdict, which asks the same physical question."
        case .flights:
            "The speed hysteresis that decides when you are on the foil — and therefore foil "
                + "time, flight count and every per-flight number."
        }
    }
}

/// One tunable parameter, named exactly as docs/algorithms.md names it.
public enum TuningParameter: String, CaseIterable, Sendable, Codable {
    // Turns
    case turnMinAngle
    case turnClassifyMinAngle
    case turnMaxDuration
    case turnPeakRate
    case turnContinueRate
    case turnMinArc
    case turnMinRadius
    case entrySpeedWindow
    case minSpeedLag
    case turnSuccessPct
    // Outcomes
    case turnStopSpeedFloor
    case turnTouchdownMaxStop
    case turnFallStop
    case turnOutcomeLookahead
    case turnRecoverPct
    case turnRecoverHold
    case turnOutcomeWindow
    // Flights
    case foilEntrySpeed
    case foilExitSpeed
    case entryHold
    case exitHold
    case minFlightDuration

    public var spec: TuningParameterSpec { TuningParameterSpec.table[self]! }

    public static func all(in group: TuningGroup) -> [TuningParameter] {
        allCases.filter { $0.spec.group == group }
    }
}

/// The published default and the range a slider may move it over. Ranges are wide enough to
/// find the edge of a parameter's usefulness and no wider — a `turnPeakRate` of 200°/s is not
/// a hypothesis anyone holds, and a slider that spends most of its travel in nonsense is a
/// slider nobody can set precisely.
public struct TuningParameterSpec: Sendable, Equatable {
    public let parameter: TuningParameter
    public let group: TuningGroup
    public let unit: String
    public let defaultValue: Double
    public let range: ClosedRange<Double>
    public let step: Double
    /// The half-line under the row, after "default N".
    public let note: String

    /// Decimals a value of this parameter is written with — one where the step is fractional,
    /// none where it is whole, so a 1 °/s step never prints "18.0".
    public var decimals: Int { step < 1 ? 1 : 0 }

    public func format(_ value: Double) -> String {
        String(format: "%.\(decimals)f", value)
    }

    /// "70 %" / "8 s" / "12 km/h" — value and unit, spaced except for the degree sign.
    public func formatted(_ value: Double) -> String {
        unit == "°" ? "\(format(value))°" : "\(format(value)) \(unit)"
    }

    static let table: [TuningParameter: TuningParameterSpec] = {
        var table: [TuningParameter: TuningParameterSpec] = [:]
        for spec in list { table[spec.parameter] = spec }
        return table
    }()

    private static let list: [TuningParameterSpec] = [
        .init(parameter: .turnMinAngle, group: .turns, unit: "°", defaultValue: 60,
              range: 30...120, step: 5,
              note: "net COG change that makes a sweep a turn at all"),
        .init(parameter: .turnClassifyMinAngle, group: .turns, unit: "°", defaultValue: 90,
              range: 60...150, step: 5,
              note: "below this a sweep is never named a tack or a jibe"),
        .init(parameter: .turnMaxDuration, group: .turns, unit: "s", defaultValue: 8,
              range: 4...20, step: 1,
              note: "window the net change has to happen inside"),
        .init(parameter: .turnPeakRate, group: .turns, unit: "°/s", defaultValue: 18,
              range: 5...40, step: 1,
              note: "fastest instant of the sweep — a carve peaks lower than a pivot"),
        .init(parameter: .turnContinueRate, group: .turns, unit: "°/s", defaultValue: 5,
              range: 1...15, step: 1,
              note: "edge trim: below this the rider is not turning any more"),
        .init(parameter: .turnMinArc, group: .turns, unit: "m", defaultValue: 12,
              range: 4...40, step: 2,
              note: "path actually travelled around the curve"),
        .init(parameter: .turnMinRadius, group: .turns, unit: "m", defaultValue: 6,
              range: 2...30, step: 1,
              note: "arc ÷ swept angle — a pivot on the spot has none"),
        .init(parameter: .entrySpeedWindow, group: .turns, unit: "s", defaultValue: 3,
              range: 1...8, step: 1,
              note: "how far back the entry speed is read from"),
        .init(parameter: .minSpeedLag, group: .turns, unit: "s", defaultValue: 2,
              range: 0...6, step: 1,
              note: "how far past the sweep the speed minimum is still looked for"),
        .init(parameter: .turnSuccessPct, group: .turns, unit: "%", defaultValue: 70,
              range: 50...95, step: 5,
              note: "of the entry speed you have to hold for the turn to succeed"),

        .init(parameter: .turnStopSpeedFloor, group: .outcomes, unit: "m/s", defaultValue: 1.0,
              range: 0.3...3, step: 0.1,
              note: "below this you are not making way"),
        .init(parameter: .turnTouchdownMaxStop, group: .outcomes, unit: "s", defaultValue: 3,
              range: 1...10, step: 0.5,
              note: "longest stop still called a touchdown"),
        .init(parameter: .turnFallStop, group: .outcomes, unit: "s", defaultValue: 5,
              range: 1...15, step: 0.5,
              note: "a stop longer than this is a fall"),
        .init(parameter: .turnOutcomeLookahead, group: .outcomes, unit: "s", defaultValue: 12,
              range: 5...30, step: 1,
              note: "tail past the sweep the outcome is judged over"),
        .init(parameter: .turnRecoverPct, group: .outcomes, unit: "%", defaultValue: 70,
              range: 40...95, step: 5,
              note: "of the entry speed that means you are flying again"),
        .init(parameter: .turnRecoverHold, group: .outcomes, unit: "s", defaultValue: 2,
              range: 0...6, step: 0.5,
              note: "how long the recovery has to hold before it counts"),
        .init(parameter: .turnOutcomeWindow, group: .outcomes, unit: "s", defaultValue: 12,
              range: 5...60, step: 1,
              note: "cap on following the recovery (turns only)"),

        .init(parameter: .foilEntrySpeed, group: .flights, unit: "km/h", defaultValue: 12,
              range: 6...25, step: 0.5,
              note: "speed at which a flight starts"),
        .init(parameter: .foilExitSpeed, group: .flights, unit: "km/h", defaultValue: 8,
              range: 4...20, step: 0.5,
              note: "speed at which a flight ends"),
        .init(parameter: .entryHold, group: .flights, unit: "s", defaultValue: 2,
              range: 0...6, step: 0.5,
              note: "how long the entry speed has to hold"),
        .init(parameter: .exitHold, group: .flights, unit: "s", defaultValue: 3,
              range: 0...8, step: 0.5,
              note: "how long the exit speed has to hold"),
        .init(parameter: .minFlightDuration, group: .flights, unit: "s", defaultValue: 5,
              range: 1...20, step: 1,
              note: "shorter than this and it was not a flight"),
    ]
}
