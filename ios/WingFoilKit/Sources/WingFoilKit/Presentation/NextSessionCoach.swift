import Foundation

/// **"What do I practise next?"**, answered once for the whole session — the Turns tab's
/// *Next session* card (rider review I2, 9 Oct 2026: *"I have to open ten turn pages to work
/// out what to practise next time."*).
///
/// Two facts, and nothing the turn pages do not already say:
///
/// 1. **The commonest tip.** Every turn that was not clean gets one "Next time…" line on its
///    page (`TurnCoach.tipKind`). This counts them across the session's counted turns and
///    keeps the one that came up most often, with its count, so the card never claims more
///    than the pages do. A tie goes to the tip that comes first in `TurnCoach.Tip.allCases`
///    — entry before exit, the order the turn is ridden in. No tip on any turn, no tip line.
/// 2. **Port against starboard.** The same verdict counted on each entry tack. Clean jibes
///    when the session has jibes with a known entry tack — clean is the headline (CPH first,
///    docs/algorithms/rates.md) — else flew through over every counted turn, the outcome
///    the Trends side split already plots (`TurnSideSplit`). Both sides need a turn, or the
///    card has no comparison. The card names the side to work on only when both sides have
///    `minSideTurns` and their shares are `sideGapPct` apart; with enough turns and a smaller
///    gap it says they went much the same; with fewer it gives the two counts and no verdict.
///
/// **Session-wide on purpose.** The card sits above the Turns tab's cards, which count the
/// whole afternoon, and the type/side filters lower down the tab do not move it: a
/// port-against-starboard line under a "starboard only" filter would compare one side with
/// nothing.
///
/// Pure and in the kit for the reason `TurnCoach` is: the counting rule is the thing worth
/// testing, and the browser will read the same words (`lines`) when it builds the card
/// (docs/screens.md, the Turns tab's row).
public struct NextSessionCoach: Sendable, Equatable {

    /// The commonest tip and how often it came up.
    public struct TipCount: Sendable, Equatable {
        public let tip: TurnCoach.Tip
        /// Counted turns that got this tip.
        public let turns: Int
        /// Counted turns in the session, the count's "of".
        public let ofTurns: Int
        /// The sentence, in the turn page's words. The jibe's wording only when every turn
        /// that got the tip was a jibe.
        public let text: String
    }

    /// What the side comparison counts.
    public enum SideMeasure: String, Sendable, Equatable {
        /// Clean jibes over the jibes entered on that tack.
        case cleanJibes
        /// Turns that flew through over the counted turns entered on that tack.
        case flewThrough
    }

    /// One entry tack's count.
    public struct SideCount: Sendable, Equatable {
        /// "port" | "starboard", the engine's field.
        public let side: String
        public let hits: Int
        public let total: Int

        public var share: Double { total > 0 ? Double(hits) / Double(total) : 0 }
    }

    /// Port against starboard.
    public struct Sides: Sendable, Equatable {
        public let measure: SideMeasure
        public let port: SideCount
        public let starboard: SideCount
        /// "port" | "starboard" — the side to work on — or nil.
        public let weaker: String?
        /// Both sides had enough turns and went much the same.
        public let even: Bool
    }

    public let tip: TipCount?
    public let sides: Sides?

    /// Nothing to say: no tip on any turn and no side comparison. The card is then absent.
    public var isEmpty: Bool { tip == nil && sides == nil }

    /// Both sides need this many turns before the card names a weaker one.
    public static let minSideTurns = 3
    /// The gap, in percentage points, between the two sides' shares that makes one weaker.
    public static let sideGapPct = 20.0

    // MARK: - Building

    /// From the session's turns. `slice` cuts one turn's window; it is asked only for the
    /// counted turns that were not clean, the only ones that can carry a tip.
    public static func make(turns: [TurnRecord], quietS: Double? = nil,
                            slice: (TurnRecord) -> TurnSlice) -> NextSessionCoach {
        let counted = turns.filter(\.counted)
        return NextSessionCoach(tip: commonestTip(counted, quietS: quietS, slice: slice),
                                sides: sides(counted))
    }

    /// The app's path: the turn windows the session page already holds
    /// (`SessionDetail.sliceSamples`), cut with the turn page's standard pads.
    public static func make(turns: [TurnRecord], samples: [TurnSlice.Sample],
                            windDirDeg: Double?, quietS: Double? = nil) -> NextSessionCoach {
        make(turns: turns, quietS: quietS) {
            TurnSlice.make(samples: samples, turn: $0, windDirDeg: windDirDeg)
        }
    }

    static func commonestTip(_ counted: [TurnRecord], quietS: Double?,
                             slice: (TurnRecord) -> TurnSlice) -> TipCount? {
        var count: [TurnCoach.Tip: Int] = [:]
        var allJibes: [TurnCoach.Tip: Bool] = [:]
        for turn in counted where !turn.clean {
            guard let tip = TurnCoach.tipKind(turn: turn, slice: slice(turn)) else { continue }
            count[tip, default: 0] += 1
            allJibes[tip] = (allJibes[tip] ?? true) && turn.type == "jibe"
        }
        // First in `allCases` wins a tie: `max(by:)` only replaces its pick on a strictly
        // greater count, so the earlier of two equals stays.
        guard let best = TurnCoach.Tip.allCases
            .filter({ count[$0] != nil })
            .max(by: { count[$0, default: 0] < count[$1, default: 0] }),
              let turns = count[best] else { return nil }
        let text = TurnCoach.tipText(best, type: allJibes[best] == true ? "jibe" : "turn",
                                     quietS: quietS)
        return TipCount(tip: best, turns: turns, ofTurns: counted.count, text: text)
    }

    static func sides(_ counted: [TurnRecord]) -> Sides? {
        let known = counted.filter { $0.side == "port" || $0.side == "starboard" }
        let jibes = known.filter { $0.type == "jibe" }
        let measure: SideMeasure = jibes.isEmpty ? .flewThrough : .cleanJibes
        let pool = measure == .cleanJibes ? jibes : known
        func side(_ name: String) -> SideCount {
            let mine = pool.filter { $0.side == name }
            let hits = mine.filter {
                measure == .cleanJibes ? $0.clean : TurnOutcomeKind($0.outcome) == .flewThrough
            }.count
            return SideCount(side: name, hits: hits, total: mine.count)
        }
        let port = side("port"), starboard = side("starboard")
        guard port.total > 0, starboard.total > 0 else { return nil }
        var weaker: String?
        var even = false
        if port.total >= minSideTurns && starboard.total >= minSideTurns {
            let gap = 100 * (port.share - starboard.share)
            if abs(gap) >= sideGapPct {
                weaker = gap < 0 ? "port" : "starboard"
            } else {
                even = true
            }
        }
        return Sides(measure: measure, port: port, starboard: starboard,
                     weaker: weaker, even: even)
    }

    // MARK: - The words

    /// The card's wording, as templates, so the browser can read the same table when it
    /// builds the card. `{n}`, `{total}` and `{side}` are filled below.
    public static let lines: [String: String] = [
        "title": "Next session",
        "tipCount": "It came up on {n} of your {total} turns.",
        "tipCountOnly": "It came up on your one turn.",
        "sideClean": "{n} of {total} jibes clean",
        "sideFlew": "{n} of {total} flew through",
        "workOn": "Work on your {side} entry next.",
        "even": "Your port and starboard entries went much the same.",
    ]

    private static func say(_ key: String, _ args: [String: String] = [:]) -> String {
        AppShellCopy.fill(lines[key] ?? key, args)
    }

    public static var title: String { say("title") }

    /// "It came up on 4 of your 12 turns."
    public static func countLine(_ tip: TipCount) -> String {
        tip.ofTurns == 1
            ? say("tipCountOnly")
            : say("tipCount", ["n": String(tip.turns), "total": String(tip.ofTurns)])
    }

    /// "Port entry", "Starboard entry" — the list's own words with a capital.
    public static func sideTitle(_ count: SideCount) -> String {
        let label = TurnAnalytics.sideLabel(count.side)
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    /// "3 of 8 jibes clean" / "7 of 9 flew through".
    public static func sideValue(_ count: SideCount, measure: SideMeasure) -> String {
        say(measure == .cleanJibes ? "sideClean" : "sideFlew",
            ["n": String(count.hits), "total": String(count.total)])
    }

    /// "Work on your starboard entry next.", the even line, or nil with too few turns.
    public static func sideVerdict(_ sides: Sides) -> String? {
        if let weaker = sides.weaker { return say("workOn", ["side": weaker]) }
        return sides.even ? say("even") : nil
    }
}
