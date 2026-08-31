import Foundation

/// One line of commentary over a replaying session — the caption a friend on the beach
/// would say out loud as it happened.
///
/// `ReplayBeat` answers "where can I jump to"; this answers "what is happening, and why does
/// it matter *now*". The two are deliberately different lists: every counted jibe is worth a
/// tick on the scrub bar, but only the first, the third, the tenth and the ones that set a
/// record are worth interrupting the rider's watching with. A milestone therefore carries a
/// finished sentence rather than a noun — the view renders it and nothing else.
public struct ReplayMilestone: Sendable, Equatable, Identifiable {

    /// What kind of moment this is. The ordinal cases carry their count because the
    /// collision rule needs it: two milestones at one instant that both say "5" would print
    /// the number twice (see `ReplayCommentary.make`).
    public enum Kind: Sendable, Equatable {
        /// The opening frame — where and when.
        case sessionStart
        /// The first flight of the session. Only the first: the tenth takeoff is not news.
        case firstTakeoff
        /// The nth **dry** jibe — the JPH count, the one a fall never advances — at one of
        /// the counts worth saying out loud.
        case jibe(Int)
        /// A new session-best run of dry maneuvers, at the maneuver that set it.
        case streak(Int)
        /// The nth swim.
        case splash(Int)
        /// The session's fastest measured window.
        case topSpeed
        /// The start of the longest flight.
        case longestFlight
        /// The closing frame — the session in three numbers.
        case sessionEnd
    }

    /// Stable across rebuilds of the same analysis — `ForEach` identity, and the key the
    /// view watches to know a *new* comment has come up.
    public let id: String
    /// Session-clock seconds, the same clock the playhead rides on.
    public let t: Double
    /// The highest-ranked kind at this instant — what the caption's icon and ink read.
    public let kind: Kind
    /// The whole line, ready to draw: "New streak — 5 dry jibes".
    public let text: String

    public init(id: String, t: Double, kind: Kind, text: String) {
        self.id = id
        self.t = t
        self.kind = kind
        self.text = text
    }
}

/// Derives a session's commentary track from one analysis.
///
/// Pure, and in the kit for the same reason `ReplayBeats` is: "the third jibe is worth a
/// mention and the fourth is not" is a statement about the session, of exactly the kind
/// `PresentationRules` already owns, and it is invisible in a screenshot until a rider
/// notices his best run went by unremarked.
///
/// **Nothing here invents a number format.** Knots come from `KeyMetrics.knots`, distance
/// from `KeyMetrics.km`, durations from `FlightPairing.clock` (the replay's own `m:ss`,
/// which is what the scrubber's elapsed field beside the map already shows) and the record
/// window's name from `RecordKind.label`. A commentary line that rounded differently from
/// the metrics block six inches above it would read as a second, disagreeing measurement.
public enum ReplayCommentary {

    // MARK: - The counts worth saying

    /// Dry-jibe ordinals that get a line: the first, the third, the fifth, then every tenth.
    ///
    /// Three and five are close together on purpose — early in a session they are the
    /// numbers a rider is actually counting — and after ten the interval opens up, because
    /// on a fifty-jibe afternoon a line every fifth jibe is not commentary, it is a metronome.
    static func isJibeMilestone(_ n: Int) -> Bool {
        n == 1 || n == 3 || n == 5 || (n >= 10 && n % 10 == 0)
    }

    /// Splash ordinals: the first, the fifth, then every tenth. Sparser than the jibes at
    /// the bottom end — nobody wants their third swim announced.
    static func isSplashMilestone(_ n: Int) -> Bool {
        n == 1 || n == 5 || (n >= 10 && n % 10 == 0)
    }

    /// The shortest run of dry maneuvers worth calling a streak. Two in a row is not a run.
    static let minStreak = 3

    // MARK: - Building

    /// Every milestone, in time order, one line per instant.
    ///
    /// `span` is the replay's clock (`SessionDetail.timeRange`) and places the two bookends.
    /// It is optional because the engine's clean clock starts at zero, so `0 ... durationS`
    /// is the right answer whenever the caller has nothing better — but a caller that has
    /// the timeline should pass it, since a bookend outside the slider's range is a comment
    /// the playhead can never reach.
    ///
    /// `place` and `startedAt` are the caller's: deriving a readable session name from a
    /// filename is presentation the kit has no business owning (the same split
    /// `ShareCardStats.make` draws). Without them the opening line degrades to "Session
    /// start" rather than inventing a location.
    public static func make(_ analysis: SessionAnalysis,
                            span: ClosedRange<Double>? = nil,
                            place: String? = nil,
                            startedAt: Date? = nil,
                            timeZone: TimeZone = .current) -> [ReplayMilestone] {
        var out: [ReplayMilestone] = []
        let clock = span ?? 0 ... max(analysis.summary.durationS, 0)

        // MARK: bookends
        //
        // Only on a recording that has a span. A start and an end at the same instant would
        // be two captions fighting over one frame of a session that never happened.
        if clock.upperBound > clock.lowerBound {
            out.append(ReplayMilestone(id: "start", t: clock.lowerBound, kind: .sessionStart,
                                       text: startLine(place: place, startedAt: startedAt,
                                                       timeZone: timeZone)))
            out.append(ReplayMilestone(id: "end", t: clock.upperBound, kind: .sessionEnd,
                                       text: endLine(analysis.summary)))
        }

        // MARK: the first takeoff
        if let first = analysis.takeoffs.min(by: { $0.startTs < $1.startTs }) {
            out.append(ReplayMilestone(id: "flying", t: first.startTs, kind: .firstTakeoff,
                                       text: "Flying!"))
        }

        // MARK: jibes, and the streaks they build
        //
        // **Dry** jibes, which is `SessionSummarizer.dryJibeTimes` — counted, named a jibe,
        // and not swum out of. Two rules in one:
        //
        // * Counted only. A bear-away is a course change with no verdict in it, the same
        //   rule the map's markers and the beat bar follow.
        // * Dry only, the JPH numerator (engine 0.7.0): a jibe he swam out of is one he did
        //   not make, and a running count that a fall advanced would let the commentary
        //   congratulate a rider for falling. The fall is not lost — its splash line says
        //   so, on the same channel WPH counts.
        //
        // The wording carries the unit for the same reason `KeyMetrics` labels JPH "dry
        // jibes per hour": "10 jibes" over a count that skipped two is a wrong number, and
        // only the word "dry" makes it a right one.
        let jibes = analysis.turns.enumerated()
            .filter {
                $0.element.counted && $0.element.type == "jibe"
                    && TurnOutcomeKind($0.element.outcome) != .fellIn
            }
            .sorted { $0.element.ts < $1.element.ts }
        for (ordinal, entry) in jibes.enumerated() {
            let n = ordinal + 1
            guard isJibeMilestone(n) else { continue }
            let outcome = TurnOutcomeKind(entry.element.outcome)
            out.append(ReplayMilestone(
                id: "jibe-\(n)", t: entry.element.ts, kind: .jibe(n),
                // The first needs no unit: the first dry jibe is by definition the first
                // one he came out of sailing, and the outcome is right there in the line.
                text: n == 1 ? "First jibe — \(outcome.label)" : "\(n) dry jibes"))
        }
        out.append(contentsOf: streakMilestones(analysis))

        // MARK: splashes
        //
        // The **flight-end** `fell_in` channel, which is the one WPH counts: a swim out of a
        // jibe and a swim in a straight line are the same wet rider, and the turn ladder
        // alone would miss every fall that happened outside a maneuver.
        let swims = analysis.flightEnds
            .filter { TurnOutcomeKind($0.outcome) == .fellIn }
            .map(\.ts)
            .sorted()
        for (index, t) in swims.enumerated() {
            let n = index + 1
            guard isSplashMilestone(n) else { continue }
            out.append(ReplayMilestone(id: "splash-\(n)", t: t, kind: .splash(n),
                                       text: n == 1 ? "First splash" : "\(n) splashes"))
        }

        // MARK: the two superlatives
        //
        // The same two `ReplayBeats` marks, said in full: the 2 s peak only when the engine
        // gave it a window to point at, and the longest flight by *time*, ties to the
        // earlier one so the choice does not depend on array order.
        if let window = analysis.records.windows[RecordWindowSelection.defaultKey],
           let best = analysis.records.best2sKn, best > 0 {
            out.append(ReplayMilestone(
                id: "top-speed", t: window.startTs, kind: .topSpeed,
                // Not "Top speed — 13.47 kn" full stop: the number is a two-second window,
                // and `KeyMetrics` refuses to call it a top speed for exactly that reason.
                // Naming the window keeps the rider's word without making his claim bigger.
                text: "Top speed — \(KeyMetrics.knots(best)) over \(RecordKind.best2s.label)"))
        }
        if let longest = analysis.flights.enumerated().max(by: {
            let (a, b) = ($0.element, $1.element)
            let (da, db) = (a.endTs - a.startTs, b.endTs - b.startTs)
            return da == db ? a.startTs > b.startTs : da < db
        }), longest.element.endTs > longest.element.startTs {
            let seconds = longest.element.endTs - longest.element.startTs
            out.append(ReplayMilestone(
                id: "longest-flight", t: longest.element.startTs, kind: .longestFlight,
                text: "Longest flight — \(FlightPairing.clock(seconds))"))
        }

        // Anything outside the replay's own clock is a caption the playhead can never reach.
        // It can happen: a stored analysis and a re-read timeline are two measurements of
        // one afternoon, and a trimmed track is a shorter one.
        return collapse(out.filter { clock.contains($0.t) })
    }

    // MARK: - Streaks

    /// A line every time the running dry streak beats the session's own best so far.
    ///
    /// **Mirrors `TurnDetector.streaks`**, over the golden records rather than the engine's
    /// own types, and the test holds the run it ends on against `summary.turns
    /// .longestDryStreak` on the corpus so the two cannot drift. Which means it is *not* a
    /// jibe-only count: a swim in a straight line ends a run of clean jibes just as surely as
    /// a botched one does, so unowned flight ends are in the event list, and only a counted
    /// turn can lengthen a run.
    ///
    /// Two departures from the engine, both deliberate:
    ///
    /// * The events are ordered by turn **end**, as the engine orders them — a streak is
    ///   settled when the maneuver is over — but the milestone is stamped at the turn's
    ///   `ts`, because that is the instant the map's marker, the beat bar's tick and the
    ///   callout all call "that jibe". A caption eight seconds adrift of the tick it belongs
    ///   to reads as a caption about something else.
    /// * Only improvements are emitted, and only from `minStreak` up: "New streak — 1 dry
    ///   jibe" on the first maneuver of the day is not news, and a line on every jibe is not
    ///   commentary.
    private static func streakMilestones(_ analysis: SessionAnalysis) -> [ReplayMilestone] {
        /// One thing that happened to the rider, from either outcome channel.
        struct Event {
            let order: Double
            /// Where the caption goes, which is not where the streak is settled.
            let mark: Double
            let isTurn: Bool
            let fellIn: Bool
        }

        let counted = Set(analysis.turns.indices.filter { analysis.turns[$0].counted })
        var events = counted.sorted().map { i -> Event in
            let turn = analysis.turns[i]
            return Event(order: turn.endTs, mark: turn.ts, isTurn: true,
                         fellIn: TurnOutcomeKind(turn.outcome) == .fellIn)
        }
        for end in analysis.flightEnds {
            if end.truncated { continue }
            if let owner = end.ownedByTurn, counted.contains(owner) { continue }
            events.append(Event(order: end.ts, mark: end.ts, isTurn: false,
                                fellIn: TurnOutcomeKind(end.outcome) == .fellIn))
        }
        // At an identical timestamp the non-turn event applies first, so a coincident fall
        // breaks the run rather than being masked by the turn that would extend it — the
        // engine's tie-break, kept so the two walks cannot disagree.
        events.sort { $0.order == $1.order ? (!$0.isTurn && $1.isTurn) : $0.order < $1.order }

        var out: [ReplayMilestone] = []
        var running = 0, best = 0
        for event in events {
            if event.isTurn {
                running = event.fellIn ? 0 : running + 1
                guard running > best, running >= minStreak else {
                    best = max(best, running)
                    continue
                }
                best = running
                out.append(ReplayMilestone(
                    id: "streak-\(running)", t: event.mark, kind: .streak(running),
                    text: "New streak — \(running) dry jibe\(running == 1 ? "" : "s")"))
            } else if event.fellIn {
                running = 0
            }
        }
        return out
    }

    // MARK: - Collisions

    /// One caption per instant: sort, group by time, and merge each group into a line.
    ///
    /// A reader cannot read two captions in the same frame, and a session hands out plenty
    /// of coincidences — the first takeoff *is* the start of the longest flight on most
    /// sessions, and until something interrupts it the dry-jibe count and the dry streak are
    /// the same number on the same jibe.
    ///
    /// So: the group is ordered by how specific it is (`rank`), and a milestone is **dropped
    /// when a higher-ranked one at the same instant already states its number** — that is
    /// the "record beats ordinal" rule, and it is what turns "3 dry jibes · New streak — 3
    /// dry jibes" into the one line that says both. What survives is joined the other way
    /// round, plainest fact first, so the sentence reads "Flying! · Longest flight — 6:32"
    /// rather
    /// than starting with the superlative and explaining afterwards. The surviving `kind`
    /// and `id` are the top-ranked one's — that is what the caption's ink reads.
    private static func collapse(_ milestones: [ReplayMilestone]) -> [ReplayMilestone] {
        let sorted = milestones.sorted {
            $0.t == $1.t ? rank($0.kind) > rank($1.kind) : $0.t < $1.t
        }
        var out: [ReplayMilestone] = []
        var index = 0
        while index < sorted.count {
            var end = index
            while end < sorted.count && sorted[end].t == sorted[index].t { end += 1 }
            let group = sorted[index..<end]

            var kept: [ReplayMilestone] = []
            var stated: Set<Int> = []
            for milestone in group {
                if let count = count(milestone.kind), stated.contains(count) { continue }
                if let count = count(milestone.kind) { stated.insert(count) }
                kept.append(milestone)
            }
            if let lead = kept.first {
                out.append(ReplayMilestone(
                    id: lead.id, t: lead.t, kind: lead.kind,
                    text: kept.reversed().map(\.text).joined(separator: " · ")))
            }
            index = end
        }
        return out
    }

    /// Collision priority — see `collapse`. The bookends outrank everything because a
    /// session's first and last frame are about the session, not about an event in it.
    private static func rank(_ kind: ReplayMilestone.Kind) -> Int {
        switch kind {
        case .sessionEnd: 7
        case .sessionStart: 6
        case .topSpeed: 5
        case .longestFlight: 4
        case .streak: 3
        case .splash: 2
        case .jibe: 1
        case .firstTakeoff: 0
        }
    }

    /// The number a milestone puts on screen, when it puts one there at all.
    private static func count(_ kind: ReplayMilestone.Kind) -> Int? {
        switch kind {
        case .jibe(let n), .streak(let n), .splash(let n): n
        default: nil
        }
    }

    // MARK: - The two bookends

    /// "Torbole, 14:07 — session start", degrading a piece at a time.
    ///
    /// POSIX and 24-hour, like `ShareCardStats.dateLine`: this is a caption composed into a
    /// sentence, and a locale that turned it into "2:07 PM" would leave the line reading
    /// "Torbole, 2:07 PM — session start" in a half-German app.
    static func startLine(place: String?, startedAt: Date?, timeZone: TimeZone) -> String {
        var lead: [String] = []
        if let place, !place.trimmingCharacters(in: .whitespaces).isEmpty { lead.append(place) }
        if let startedAt {
            let formatter = DateFormatter()
            formatter.timeZone = timeZone
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm"
            lead.append(formatter.string(from: startedAt))
        }
        guard !lead.isEmpty else { return "Session start" }
        return lead.joined(separator: ", ") + " — session start"
    }

    /// "Session end — 10:45 · 2.6 km · 8 dry jibes".
    ///
    /// **Dry**, and it says so — the same count the ordinals ran on and the same one JPH
    /// divides by. A closing line that totalled every attempt would disagree with the
    /// commentary it just finished, and with the headline rate one screen up.
    ///
    /// The count falls back from jibes to counted turns exactly the way `KeyMetrics.tally`
    /// does, and for the same reason: a session whose wind axis never resolved has turns and
    /// no jibes at all, and closing it with "0 dry jibes" would be a verdict on a rider who
    /// jibed all afternoon. Where the session *did* name jibes, a genuine zero is left
    /// standing — "0 dry jibes" after an afternoon of swimming is the truth, and softening
    /// it would make every other number on the line suspect.
    static func endLine(_ summary: SessionSummary) -> String {
        var parts = [FlightPairing.clock(summary.durationS), KeyMetrics.km(summary.distanceKm)]
        let turns = summary.turns
        if turns.jibes > 0 {
            let dry = turns.jibeOutcomes.flewThrough + turns.jibeOutcomes.touchdown
            parts.append("\(dry) dry jibe\(dry == 1 ? "" : "s")")
        } else if turns.turnsCounted > 0 {
            parts.append("\(turns.turnsCounted) turn\(turns.turnsCounted == 1 ? "" : "s")")
        }
        return "Session end — " + parts.joined(separator: " · ")
    }

    // MARK: - Lookup

    /// The milestone the playhead has most recently passed, or nil before the first one.
    ///
    /// "Most recently passed" rather than "nearest": commentary is said *after* the thing
    /// happens, and a caption that appeared two seconds before the jibe it describes would
    /// be a spoiler on a replay whose whole point is watching the jibe.
    public static func current(at t: Double, in milestones: [ReplayMilestone])
        -> ReplayMilestone? {
        milestones.last { $0.t <= t }
    }
}
