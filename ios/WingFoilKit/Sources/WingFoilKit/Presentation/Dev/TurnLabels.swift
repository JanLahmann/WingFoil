import Foundation

/// **Ground truth: what the rider says happened, kept beside what the engine said.**
///
/// Every threshold in docs/algorithms.md was tuned against Jan reading a session and saying
/// "that one I flew, that one I touched, that one I swam" — and each of those readings was
/// spent once, in a conversation, and then lost. This is the same reading, written down: a
/// three-way label per counted turn, stored per session, scored against the analyses whenever
/// he wants to know what a slider did to his agreement rate.
///
/// **It is emphatically not part of the analysis.** A label never reaches `SessionAnalysis`,
/// never reaches the archive's `analysis.json`, and never moves a verdict — it is the *other*
/// column, and the whole value of it is that the engine cannot see it. It lives in the app's
/// own preferences beside the map-layer sets, keyed by session id, and the public build has no
/// way to write one.
public enum TurnLabel: String, Codable, Sendable, CaseIterable, Equatable {
    /// Carried it all the way through, board never touched.
    case flew
    /// Touched down and carried on.
    case touched
    /// Swam.
    case fell

    /// The control's own wording — first person, because it is the rider's claim.
    public var label: String {
        switch self {
        case .flew: return "I flew"
        case .touched: return "I touched"
        case .fell: return "I fell"
        }
    }

    /// The engine verdict this label agrees with.
    public var verdict: TurnOutcomeKind {
        switch self {
        case .flew: return .flewThrough
        case .touched: return .touchdown
        case .fell: return .fellIn
        }
    }

    /// The label a verdict would have to be, to agree.
    public init(_ verdict: TurnOutcomeKind) {
        switch verdict {
        case .flewThrough: self = .flew
        case .touchdown: self = .touched
        case .fellIn: self = .fell
        }
    }
}

/// One session's labels — the Codable sidecar the app persists per session.
///
/// Keyed by the turn's **index into `analysis.turns`**, as a string because a `[Int: …]` encodes
/// to a JSON array of alternating keys and values and this file is meant to be readable. The
/// index is the same identity the turn sheet, the pins and the Turns tab already share; a
/// re-analysis that changes the turn list therefore invalidates labels by construction, which is
/// the honest behaviour — a label is about a maneuver the detector found, and if it no longer
/// finds it there is nothing left to label.
public struct TurnLabelSheet: Codable, Sendable, Equatable {
    public var sessionID: String
    /// Turn index (as a string) → label.
    public var labels: [String: TurnLabel]

    public init(sessionID: String, labels: [String: TurnLabel] = [:]) {
        self.sessionID = sessionID
        self.labels = labels
    }

    public subscript(turnIndex: Int) -> TurnLabel? {
        get { labels[String(turnIndex)] }
        set { labels[String(turnIndex)] = newValue }
    }

    public var isEmpty: Bool { labels.isEmpty }
    public var count: Int { labels.count }
}

/// One labelled turn, with everything the scoring page has to print about it.
public struct LabelledTurn: Sendable, Equatable, Identifiable {
    public var sessionID: String
    /// What the library calls this session, for the disagreement list.
    public var sessionTitle: String
    /// Session start, so the list can be ordered newest first.
    public var startDate: Date
    /// Index into that session's `analysis.turns`.
    public var turnIndex: Int
    /// Seconds from the session's start — what the row's clock prints.
    public var ts: Double
    /// "jibe" | "tack" | "turn".
    public var type: String
    public var verdict: TurnOutcomeKind
    public var clean: Bool
    public var label: TurnLabel

    public var id: String { "\(sessionID)#\(turnIndex)" }
    public var agrees: Bool { label.verdict == verdict }

    public init(sessionID: String, sessionTitle: String, startDate: Date, turnIndex: Int,
                ts: Double, type: String, verdict: TurnOutcomeKind, clean: Bool,
                label: TurnLabel) {
        self.sessionID = sessionID
        self.sessionTitle = sessionTitle
        self.startDate = startDate
        self.turnIndex = turnIndex
        self.ts = ts
        self.type = type
        self.verdict = verdict
        self.clean = clean
        self.label = label
    }
}

/// Agreement, the confusion table, and the list of the ones that disagree.
public struct TurnLabelScore: Sendable, Equatable {
    public var agreed: Int
    public var total: Int
    /// The whole point of the page. nil with nothing labelled — 0 % would be a claim.
    public var agreedPct: Double?
    /// `confusion[label][verdict]` — rows are what the rider said, columns what the engine said.
    /// The diagonal is agreement.
    public var confusion: [TurnLabel: [TurnOutcomeKind: Int]]
    /// Every labelled turn the engine called differently, newest session first.
    public var disagreements: [LabelledTurn]

    public var isEmpty: Bool { total == 0 }

    /// How many turns the rider labelled with this word.
    public func labelled(_ label: TurnLabel) -> Int {
        (confusion[label] ?? [:]).values.reduce(0, +)
    }

    /// How many turns the engine called this, among the labelled ones.
    public func called(_ verdict: TurnOutcomeKind) -> Int {
        TurnLabel.allCases.reduce(0) { $0 + (confusion[$1]?[verdict] ?? 0) }
    }

    public func count(label: TurnLabel, verdict: TurnOutcomeKind) -> Int {
        confusion[label]?[verdict] ?? 0
    }

    /// "31 of 38 · 82 %" — the headline, or the empty state's own sentence.
    public var caption: String {
        guard let agreedPct else { return "nothing labelled yet" }
        return String(format: "%d of %d · %.0f %%", agreed, total, agreedPct)
    }
}

public enum TurnLabelScoring {

    /// Scores a flat list of labelled turns. The caller assembles the list from the sessions it
    /// has (one per session, per label), so this stays pure and testable and knows nothing about
    /// the library.
    public static func score(_ entries: [LabelledTurn]) -> TurnLabelScore {
        var confusion: [TurnLabel: [TurnOutcomeKind: Int]] = [:]
        for label in TurnLabel.allCases {
            confusion[label] = Dictionary(uniqueKeysWithValues:
                                            TurnOutcomeKind.allCases.map { ($0, 0) })
        }
        var agreed = 0
        for entry in entries {
            confusion[entry.label]?[entry.verdict, default: 0] += 1
            if entry.agrees { agreed += 1 }
        }
        let total = entries.count
        // Newest session first, then in the session's own turn order: a rider reviewing
        // disagreements works back from the afternoon he remembers.
        let disagreements = entries.filter { !$0.agrees }
            .sorted {
                $0.startDate == $1.startDate
                    ? $0.turnIndex < $1.turnIndex
                    : $0.startDate > $1.startDate
            }
        return TurnLabelScore(agreed: agreed, total: total,
                              agreedPct: total > 0
                                ? 100 * Double(agreed) / Double(total) : nil,
                              confusion: confusion, disagreements: disagreements)
    }

    /// The labels as a file, one row per labelled turn, oldest first.
    ///
    /// Format is documented in docs/testing.md ("Ground-truth labels"): it is meant to be read
    /// by the lab as well as by a spreadsheet, so the session id is carried verbatim and the
    /// turn index is the same identity the app uses.
    public static func csv(_ entries: [LabelledTurn]) -> String {
        var out = "session_id,session_title,session_start,turn_index,turn_ts_s,turn_type,"
            + "label,verdict,clean,agrees\n"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        for entry in entries.sorted(by: {
            $0.startDate == $1.startDate
                ? $0.turnIndex < $1.turnIndex
                : $0.startDate < $1.startDate
        }) {
            out += [
                quote(entry.sessionID),
                quote(entry.sessionTitle),
                formatter.string(from: entry.startDate),
                "\(entry.turnIndex)",
                String(format: "%.1f", entry.ts),
                entry.type,
                entry.label.rawValue,
                engineOutcome(entry.verdict),
                entry.clean ? "1" : "0",
                entry.agrees ? "1" : "0",
            ].joined(separator: ",") + "\n"
        }
        return out
    }

    /// The engine's own spelling of a verdict (`TurnRecord.outcome`), not the presentation
    /// enum's camel case: this file is read beside `analysis.json` in the lab, and one word
    /// per verdict across the repo is worth the three lines.
    static func engineOutcome(_ verdict: TurnOutcomeKind) -> String {
        switch verdict {
        case .flewThrough: return TurnOutcome.flewThrough.rawValue
        case .touchdown: return TurnOutcome.touchdown.rawValue
        case .fellIn: return TurnOutcome.fellIn.rawValue
        }
    }

    /// RFC 4180 quoting, applied to the two free-text columns only.
    static func quote(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
