import Foundation

/// One moment worth skipping to while a session replays.
///
/// The scrub bar is 300 pt of uniform grey for a two-hour ride, and the events a rider
/// actually wants to watch — the takeoffs, the jibes, the two seconds he was fastest —
/// are a few dozen instants scattered through it. A beat is one of those instants, with
/// enough with it to draw a tick and name what the tick is.
public struct ReplayBeat: Sendable, Equatable, Identifiable {

    /// What happened. A jibe carries its verdict rather than being three cases, because
    /// the outcome is exactly the thing the tick's colour has to say — and the ladder that
    /// names those colours (`DesignTokens.Outcome`) already exists.
    public enum Kind: Sendable, Equatable {
        /// A flight started. `free` is the engine's "the wind did it" — under
        /// `config.freeTakeoff` strokes — the same split the map's arrows draw.
        case takeoff(free: Bool)
        /// A counted jibe, with what it ended as.
        case jibe(TurnOutcomeKind)
        /// The start of the session's fastest 2 s — the number riders quote at each other,
        /// and the one window every session opens on (`RecordWindowSelection.defaultKey`).
        case record
        /// The start of the longest flight. Not a fifth event: it is the takeoff that began
        /// it, promoted, which is why a collision at the same instant keeps only this one.
        case longestFlight
    }

    /// Stable across rebuilds of the same analysis — `ForEach` identity for the ticks.
    public let id: String
    /// Session-clock seconds, the same clock the playhead rides on.
    public let t: Double
    public let kind: Kind
    /// Short enough for a tooltip beside a 2 pt tick: "Jibe · fell in", "Best 2 s".
    public let label: String

    public init(id: String, t: Double, kind: Kind, label: String) {
        self.id = id
        self.t = t
        self.kind = kind
        self.label = label
    }
}

/// Derives the replay's beats from one analysis.
///
/// Pure, and deliberately in the kit rather than in the scrubber: what counts as a beat is
/// a statement about the session — "a counted jibe, not a bear-away" — of exactly the kind
/// `PresentationRules` already owns for the map, and it is the sort of rule that is
/// invisible in a screenshot until a rider notices his best run has no mark on it.
public enum ReplayBeats {

    /// Every beat, in time order.
    ///
    /// **Collisions.** A takeoff and the flight it starts share an instant, and so can a
    /// record window that begins on one. Two ticks one pixel apart would read as two
    /// events, so beats at the same instant collapse to the most specific one:
    /// `record` › `longestFlight` › `jibe` › `takeoff`. The rank is also the sort's
    /// tie-break, so the order is total and the test can pin it.
    public static func make(_ analysis: SessionAnalysis) -> [ReplayBeat] {
        var beats: [ReplayBeat] = []

        for (index, takeoff) in analysis.takeoffs.enumerated() {
            beats.append(ReplayBeat(id: "takeoff-\(index)", t: takeoff.startTs,
                                    kind: .takeoff(free: takeoff.free),
                                    label: takeoff.free ? "Free takeoff" : "Takeoff"))
        }

        // Counted jibes only. A bear-away or a round-up is a course change with no verdict
        // in it (`PresentationRules.layer(for:)`), and nothing to replay.
        for (index, turn) in analysis.turns.enumerated()
        where turn.counted && turn.type == "jibe" {
            let outcome = TurnOutcomeKind(turn.outcome)
            beats.append(ReplayBeat(id: "jibe-\(index)", t: turn.ts, kind: .jibe(outcome),
                                    label: "Jibe · \(outcome.label)"))
        }

        // The 2 s peak, and only when the engine gave it a window to point at — a record
        // with a value but no provenance cannot be located on the clock.
        if let window = analysis.records.windows[RecordWindowSelection.defaultKey],
           (analysis.records.best2sKn ?? 0) > 0 {
            beats.append(ReplayBeat(id: "record", t: window.startTs, kind: .record,
                                    label: "Best 2 s"))
        }

        // Longest by *time*, which is the flight a rider remembers; ties go to the earlier
        // one so the choice does not depend on array order.
        if let longest = analysis.flights.enumerated().max(by: {
            let (a, b) = ($0.element, $1.element)
            let (da, db) = (a.endTs - a.startTs, b.endTs - b.startTs)
            return da == db ? a.startTs > b.startTs : da < db
        }), longest.element.endTs > longest.element.startTs {
            beats.append(ReplayBeat(id: "longest", t: longest.element.startTs,
                                    kind: .longestFlight, label: "Longest flight"))
        }

        beats.sort { $0.t == $1.t ? rank($0.kind) > rank($1.kind) : $0.t < $1.t }
        var out: [ReplayBeat] = []
        for beat in beats where out.last?.t != beat.t { out.append(beat) }
        return out
    }

    /// Collision priority — see `make`.
    private static func rank(_ kind: ReplayBeat.Kind) -> Int {
        switch kind {
        case .record: 3
        case .longestFlight: 2
        case .jibe: 1
        case .takeoff: 0
        }
    }

    /// The nearest beat strictly before `t`, for the "skip back" button.
    ///
    /// `epsilon` is what makes repeated taps walk the list instead of sticking: the button
    /// puts the playhead exactly on a beat, so "before the playhead" has to mean "before
    /// this one" rather than "before or at it", and a playhead a hair off from float
    /// arithmetic must still count as being on it.
    public static func beat(before t: Double, in beats: [ReplayBeat],
                            epsilon: Double = 0.25) -> ReplayBeat? {
        beats.last { $0.t < t - epsilon }
    }

    /// The nearest beat strictly after `t`, for "skip forward".
    public static func beat(after t: Double, in beats: [ReplayBeat],
                            epsilon: Double = 0.25) -> ReplayBeat? {
        beats.first { $0.t > t + epsilon }
    }
}
