import Foundation

/// A record kind that just got beaten, with what it beat.
public struct NewPersonalBest: Sendable, Equatable, Identifiable {
    public let kind: RecordKind
    public let valueKn: Double
    /// The best that stood before. nil means this kind had never been achieved — which is
    /// only reported when the library already had *other* records (see `improvements`).
    public let previousKn: Double?
    public let sessionId: String

    public var id: String { kind.rawValue }

    public var deltaKn: Double? { previousKn.map { valueKn - $0 } }

    public init(kind: RecordKind, valueKn: Double, previousKn: Double?, sessionId: String) {
        self.kind = kind
        self.valueKn = valueKn
        self.previousKn = previousKn
        self.sessionId = sessionId
    }
}

/// The all-time best per record kind, small enough to keep in `UserDefaults` so an import
/// can be compared against what the library knew *before* it ran.
public struct PersonalBestSnapshot: Codable, Sendable, Equatable {

    /// Keyed by `RecordKind.rawValue` so an unknown future kind round-trips instead of
    /// failing to decode an old snapshot.
    public var bestByKind: [String: Double]

    /// The clean-jibe records, keyed by `CleanJibeRecordKind.rawValue` (engine 0.10.0).
    ///
    /// **Optional, and the optionality is the point.** A snapshot written before this
    /// existed decodes with nil here, and nil means "this library has never been measured
    /// for clean jibes" — which is precisely the state that must *not* celebrate, for the
    /// same reason an empty `bestByKind` does not: the first measurement beats nothing. An
    /// empty dictionary is a different statement ("measured, and there were none").
    public var bestCleanJibeByKind: [String: Double]?

    public init(bestByKind: [String: Double] = [:],
                bestCleanJibeByKind: [String: Double]? = nil) {
        self.bestByKind = bestByKind
        self.bestCleanJibeByKind = bestCleanJibeByKind
    }

    public init(records: [RecordBest], cleanJibes: [CleanJibeBest] = []) {
        var best: [String: Double] = [:]
        for record in records {
            best[record.kind.rawValue] = max(best[record.kind.rawValue] ?? -.infinity,
                                             record.valueKn)
        }
        bestByKind = best
        bestCleanJibeByKind = Dictionary(cleanJibes.map { ($0.kind.rawValue, $0.value) },
                                         uniquingKeysWith: max)
    }

    public var isEmpty: Bool { bestByKind.isEmpty }

    public func value(for kind: RecordKind) -> Double? { bestByKind[kind.rawValue] }

    public func value(for kind: CleanJibeRecordKind) -> Double? {
        bestCleanJibeByKind?[kind.rawValue]
    }
}

public enum PersonalBestDetector {

    /// Floats arriving from two different query runs must not celebrate a rounding
    /// difference; a record has to actually move by this much to count.
    public static let epsilonKn = 0.005

    /// Kinds whose all-time best improved between the two snapshots.
    ///
    /// **An empty `previous` yields nothing.** The first import populates every kind at
    /// once, and calling that nine simultaneous personal bests would fire a celebration at
    /// the one moment it means least — there was nothing to beat. Only certified sources
    /// are eligible: a class-(c) recording can read high, and a confetti burst is exactly
    /// the wrong response to a bad speed sample.
    public static func improvements(previous: PersonalBestSnapshot,
                                    current: [RecordBest]) -> [NewPersonalBest] {
        guard !previous.isEmpty else { return [] }
        return current.compactMap { record in
            guard record.certified else { return nil }
            guard let before = previous.value(for: record.kind) else {
                return NewPersonalBest(kind: record.kind, valueKn: record.valueKn,
                                       previousKn: nil, sessionId: record.sessionId)
            }
            guard record.valueKn > before + epsilonKn else { return nil }
            return NewPersonalBest(kind: record.kind, valueKn: record.valueKn,
                                   previousKn: before, sessionId: record.sessionId)
        }
    }
}

// MARK: - The clean jibe as a personal best

/// The two clean-jibe records a library keeps, beside the nine speed ones.
///
/// **Why the clean jibe gets a PB at all.** Every record the app celebrated until engine
/// 0.10.0 was a speed — nine windows of one fact. But the number a wingfoiler actually
/// chases is the jibe he rides all the way through (docs/presentation.md, "Clean jibe"), and
/// a rider who went from two clean jibes in an afternoon to eleven had the best session of
/// his season with nothing in the app to say so. These two say it.
///
/// **Two, because they are two different afternoons.** The count is the session that beat
/// the others outright; the rate is the one that beat them *per hour*, which is what a short
/// evening in good wind wins. Neither implies the other and a rider recognises both.
public enum CleanJibeRecordKind: String, CaseIterable, Sendable, Codable {
    /// Most clean jibes in one session.
    case cleanJibes
    /// Best clean jibes per hour — CPH, over a session long enough to mean it.
    case cleanJibesPerHour

    public var label: String {
        switch self {
        case .cleanJibes: "Clean jibes"
        case .cleanJibesPerHour: "Best CPH"
        }
    }

    /// How the value is spelled: a count is a count, a rate gets the block's one decimal.
    public func format(_ value: Double) -> String {
        switch self {
        case .cleanJibes: "\(Int(value.rounded()))"
        case .cleanJibesPerHour: String(format: "%.1f", value)
        }
    }
}

/// One session's standing in one clean-jibe record.
public struct CleanJibeBest: Sendable, Equatable, Identifiable {
    public let kind: CleanJibeRecordKind
    public let value: Double
    public let sessionId: String

    public var id: String { kind.rawValue }

    public init(kind: CleanJibeRecordKind, value: Double, sessionId: String) {
        self.kind = kind
        self.value = value
        self.sessionId = sessionId
    }
}

/// A clean-jibe record that just got beaten — the twin of `NewPersonalBest`, kept a separate
/// type because it is not a speed and must never land in the knots table.
public struct NewCleanJibeBest: Sendable, Equatable, Identifiable {
    public let kind: CleanJibeRecordKind
    public let value: Double
    /// The best that stood before; nil when the library had never held this kind at all.
    public let previous: Double?
    public let sessionId: String

    public var id: String { kind.rawValue }

    /// "Clean jibes — 11 (was 8)": the whole celebration in one line, and the reason the
    /// burst is not unexplained.
    public var headline: String {
        let now = kind.format(value)
        guard let previous else { return "\(kind.label) — \(now)" }
        return "\(kind.label) — \(now) (was \(kind.format(previous)))"
    }

    public init(kind: CleanJibeRecordKind, value: Double, previous: Double?,
                sessionId: String) {
        self.kind = kind
        self.value = value
        self.previous = previous
        self.sessionId = sessionId
    }
}

extension PersonalBestDetector {

    /// A session must last at least this long to hold the **CPH** record.
    ///
    /// The rule the rolling window already obeys (`docs/algorithms.md`, "Never a flattering
    /// peak"): one clean jibe in a four-minute evening sail is fifteen an hour, and a
    /// personal best a rider can set by going home early is not one. A rate window is the
    /// shortest span this engine is willing to call an hour's worth of anything. The *count*
    /// takes no such floor — nine clean jibes are nine clean jibes however long it took.
    public static let cphMinDurationS: Double = 15 * 60

    /// Counts have to move by a whole one; rates by the corpus tolerance for a rate.
    static func epsilon(_ kind: CleanJibeRecordKind) -> Double {
        switch kind {
        case .cleanJibes: 0.5
        case .cleanJibesPerHour: 0.05
        }
    }

    /// The standing clean-jibe records across a library, one session each.
    ///
    /// CPH is recomputed from the row rather than stored, and from the same two numbers the
    /// engine divides — `jibesSuccessful` over `durationS` — so a library row and a session
    /// page can never disagree about a rider's best afternoon.
    ///
    /// Ties keep the **earlier** session, the way the window peak keeps the earliest window:
    /// a record is set the first time it is reached, and equalling it later is not beating it.
    public static func cleanJibeBests(_ sessions: [SessionRow]) -> [CleanJibeBest] {
        var best: [CleanJibeRecordKind: CleanJibeBest] = [:]
        for session in sessions.sorted(by: { $0.startDate < $1.startDate }) {
            guard let clean = session.jibesSuccessful, clean > 0 else { continue }
            consider(.cleanJibes, Double(clean), session.id, into: &best)
            guard session.durationS >= cphMinDurationS else { continue }
            consider(.cleanJibesPerHour, Double(clean) / (session.durationS / 3600),
                     session.id, into: &best)
        }
        return CleanJibeRecordKind.allCases.compactMap { best[$0] }
    }

    private static func consider(_ kind: CleanJibeRecordKind, _ value: Double,
                                 _ sessionId: String,
                                 into best: inout [CleanJibeRecordKind: CleanJibeBest]) {
        guard value > (best[kind]?.value ?? -.infinity) else { return }
        best[kind] = CleanJibeBest(kind: kind, value: value, sessionId: sessionId)
    }

    /// Clean-jibe records that improved between the two snapshots.
    ///
    /// Silent on a snapshot that never carried them (`bestCleanJibeByKind == nil` — one
    /// written before engine 0.10.0), for exactly the reason `improvements` is silent on an
    /// empty one: the first library to be measured beats nothing, and a celebration at that
    /// moment means the least it ever will.
    public static func cleanJibeImprovements(previous: PersonalBestSnapshot,
                                             current: [CleanJibeBest]) -> [NewCleanJibeBest] {
        guard let known = previous.bestCleanJibeByKind else { return [] }
        return current.compactMap { best in
            guard let before = known[best.kind.rawValue] else {
                return NewCleanJibeBest(kind: best.kind, value: best.value, previous: nil,
                                        sessionId: best.sessionId)
            }
            guard best.value > before + epsilon(best.kind) else { return nil }
            return NewCleanJibeBest(kind: best.kind, value: best.value, previous: before,
                                    sessionId: best.sessionId)
        }
    }
}
