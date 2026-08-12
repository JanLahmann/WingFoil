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

    public init(bestByKind: [String: Double] = [:]) {
        self.bestByKind = bestByKind
    }

    public init(records: [RecordBest]) {
        var best: [String: Double] = [:]
        for record in records {
            best[record.kind.rawValue] = max(best[record.kind.rawValue] ?? -.infinity,
                                             record.valueKn)
        }
        bestByKind = best
    }

    public var isEmpty: Bool { bestByKind.isEmpty }

    public func value(for kind: RecordKind) -> Double? { bestByKind[kind.rawValue] }
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
