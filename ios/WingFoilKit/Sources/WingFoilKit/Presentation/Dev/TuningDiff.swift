import Foundation

/// **What the tuning actually did — this session, tuned against published, turn by turn.**
///
/// The tuning page says how many thresholds moved; the library says nothing about what moving
/// them *did*, and "re-analysed 41 sessions" is not an answer to "was that better". So the dev
/// build analyses the open session a second time with the published defaults, in memory, and
/// puts the two side by side: the counts at the top, and underneath the turns that actually
/// changed — one that only the tuned run found, one only the default run found, one whose
/// verdict moved, one whose clean flag moved.
///
/// **Turns are matched on their start time, not their index.** A tuned run that finds one extra
/// turn shifts every index after it, so matching on position would report the whole rest of the
/// session as changed. `matchToleranceS` is 1 s because a sweep's start is a sample time and the
/// two runs read the same samples — a turn whose start moved by more than a second is a
/// different turn, and saying so is the point.
public struct TuningDiff: Sendable, Equatable {

    /// One turn the two runs disagree about.
    public struct Change: Sendable, Equatable, Identifiable {
        public enum Kind: String, Sendable, Equatable {
            /// Only the tuned run counts it.
            case added
            /// Only the default run counts it.
            case removed
            /// Both count it; the outcome differs.
            case verdictChanged
            /// Both count it and agree on the outcome; `clean` differs.
            case cleanChanged

            public var label: String {
                switch self {
                case .added: return "added"
                case .removed: return "removed"
                case .verdictChanged: return "verdict"
                case .cleanChanged: return "clean"
                }
            }
        }

        /// Index into the **tuned** analysis' turns, where the tuned run has this turn. nil on
        /// a `removed` turn, which is exactly the one the tuned run does not have — and which
        /// is therefore the one change on this list that cannot be opened.
        public var tunedIndex: Int?
        /// Index into the default analysis' turns, where the default run has it.
        public var defaultIndex: Int?
        /// Session-clock start of whichever run has it.
        public var ts: Double
        public var kind: Kind
        /// "jibe · touchdown → fell in" — the change in the run's own words.
        public var detail: String

        public var id: String { "\(kind.rawValue)-\(Int(ts.rounded()))" }
    }

    /// Tuned minus default, over the counted turns.
    public var turnDelta: Int
    public var jibeDelta: Int
    public var tackDelta: Int
    public var cleanDelta: Int
    public var verdictChanged: Int
    public var cleanChanged: Int
    public var changes: [Change]

    public var isEmpty: Bool { changes.isEmpty && turnDelta == 0 && cleanDelta == 0 }

    /// "Tuned vs default: +3 jibes, −2 clean, 4 verdicts changed" — only the clauses that are
    /// not zero, because a headline full of "+0" is a headline nobody reads.
    public var headline: String {
        var parts: [String] = []
        func signed(_ value: Int, _ singular: String, _ plural: String) {
            guard value != 0 else { return }
            // A real minus sign, not a hyphen: this string is read at a glance beside "+3".
            let sign = value > 0 ? "+" : "−"
            parts.append("\(sign)\(abs(value)) \(abs(value) == 1 ? singular : plural)")
        }
        signed(jibeDelta, "jibe", "jibes")
        signed(tackDelta, "tack", "tacks")
        signed(cleanDelta, "clean", "clean")
        if verdictChanged > 0 {
            parts.append("\(verdictChanged) verdict\(verdictChanged == 1 ? "" : "s") changed")
        }
        if cleanChanged > 0 && cleanDelta == 0 {
            // Two jibes swapping places leaves the count alone and is still a change.
            parts.append("\(cleanChanged) clean flag\(cleanChanged == 1 ? "" : "s") moved")
        }
        guard !parts.isEmpty else { return "Tuned vs default: nothing changed" }
        return "Tuned vs default: " + parts.joined(separator: ", ")
    }
}

public enum TuningDiffBuilder {

    /// Two turns are the same turn when their sweeps start within this of each other.
    public static let matchToleranceS = 1.0

    /// The diff between a tuned analysis and the same session analysed on the defaults.
    public static func diff(tuned: SessionAnalysis, base: SessionAnalysis) -> TuningDiff {
        let tunedTurns = tuned.turns.enumerated().filter(\.element.counted)
        let baseTurns = base.turns.enumerated().filter(\.element.counted)
        var matchedBase = Set<Int>()
        var changes: [TuningDiff.Change] = []
        var verdictChanged = 0, cleanChanged = 0

        for (index, turn) in tunedTurns {
            guard let hit = baseTurns.first(where: {
                !matchedBase.contains($0.offset)
                    && abs($0.element.ts - turn.ts) <= matchToleranceS
            }) else {
                changes.append(.init(tunedIndex: index, defaultIndex: nil, ts: turn.ts,
                                     kind: .added, detail: describe(turn)))
                continue
            }
            matchedBase.insert(hit.offset)
            let other = hit.element
            if turn.outcome != other.outcome {
                verdictChanged += 1
                changes.append(.init(
                    tunedIndex: index, defaultIndex: hit.offset, ts: turn.ts,
                    kind: .verdictChanged,
                    detail: "\(TurnAnalytics.typeLabel(turn.type).lowercased()) · "
                        + "\(TurnOutcomeKind(other.outcome).label) → "
                        + "\(TurnOutcomeKind(turn.outcome).label)"))
            } else if turn.clean != other.clean {
                cleanChanged += 1
                changes.append(.init(
                    tunedIndex: index, defaultIndex: hit.offset, ts: turn.ts,
                    kind: .cleanChanged,
                    detail: "\(TurnAnalytics.typeLabel(turn.type).lowercased()) · "
                        + (turn.clean ? "not clean → clean" : "clean → not clean")))
            }
        }
        for (index, turn) in baseTurns where !matchedBase.contains(index) {
            changes.append(.init(tunedIndex: nil, defaultIndex: index, ts: turn.ts,
                                 kind: .removed, detail: describe(turn)))
        }
        // Both counts are also moved by `cleanChanged`, so the two are reported separately and
        // the headline only prints the flag count where the total did not move.
        let cleanChangedNet = tuned.summary.turns.jibesSuccessful
            - base.summary.turns.jibesSuccessful
        return TuningDiff(
            turnDelta: tuned.summary.turns.turnsCounted - base.summary.turns.turnsCounted,
            jibeDelta: tuned.summary.turns.jibes - base.summary.turns.jibes,
            tackDelta: tuned.summary.turns.tacks - base.summary.turns.tacks,
            cleanDelta: cleanChangedNet,
            verdictChanged: verdictChanged, cleanChanged: cleanChanged,
            changes: changes.sorted { $0.ts < $1.ts })
    }

    static func describe(_ turn: TurnRecord) -> String {
        "\(TurnAnalytics.typeLabel(turn.type).lowercased()) · "
            + "\(TurnOutcomeKind(turn.outcome).label)\(turn.clean ? " · clean" : "")"
    }
}

/// **One turn under two tunings** — the two-column card on the turn page.
///
/// The same match rule as the session diff, applied to one turn: find this turn in the default
/// run by its start time, and print the six numbers a rider tunes against side by side. Where
/// the default run has no such turn, that is the answer — the tuning is what *found* it — and
/// the card says so rather than printing a column of dashes.
public struct TurnWhatIf: Sendable, Equatable {

    /// One run's reading of one turn.
    public struct Column: Sendable, Equatable {
        public var verdict: TurnOutcomeKind
        public var clean: Bool
        /// 0…1, as the record carries it.
        public var score: Double
        public var entryKn: Double
        public var minKn: Double
        public var exitKn: Double
        public var outcomeWindowS: Double
        /// Why the window closed, where the trace could say. nil where no context was handed in.
        public var windowReason: String?

        public init(_ turn: TurnRecord, windowReason: String? = nil) {
            verdict = TurnOutcomeKind(turn.outcome)
            clean = turn.clean
            score = turn.score
            entryKn = turn.entryKn
            minKn = turn.minKn
            exitKn = turn.exitKn
            outcomeWindowS = turn.outcomeWindowS
            self.windowReason = windowReason
        }
    }

    public var tuned: Column
    /// nil where the default run did not find this turn at all.
    public var base: Column?
    /// The default run found it, and nothing on the card differs.
    public var identical: Bool

    public init(tuned: Column, base: Column?) {
        self.tuned = tuned
        self.base = base
        identical = base.map {
            $0.verdict == tuned.verdict && $0.clean == tuned.clean
                && abs($0.score - tuned.score) < 0.005
                && abs($0.outcomeWindowS - tuned.outcomeWindowS) < 0.05
                && abs($0.entryKn - tuned.entryKn) < 0.05
                && abs($0.minKn - tuned.minKn) < 0.05
                && abs($0.exitKn - tuned.exitKn) < 0.05
        } ?? false
    }

    /// The card for one turn of a tuned analysis, against the same session on the defaults.
    public static func make(turnIndex: Int, tuned: SessionAnalysis,
                            base: SessionAnalysis?) -> TurnWhatIf? {
        guard tuned.turns.indices.contains(turnIndex) else { return nil }
        let turn = tuned.turns[turnIndex]
        let match = base?.turns.first {
            $0.counted && abs($0.ts - turn.ts) <= TuningDiffBuilder.matchToleranceS
        }
        return TurnWhatIf(tuned: Column(turn), base: match.map { Column($0) })
    }
}
