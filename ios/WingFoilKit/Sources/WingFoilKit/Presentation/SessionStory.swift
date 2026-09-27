import Foundation

/// **The session tells its own story** (UX review 26 Sep 2026, fixes 2 and 3; Jan, 27 Sep).
///
/// One Coach line over the key metrics — "14 dry jibes, 9 clean, your fastest 2 s this
/// month." — and the records the session holds against the rider's own history, so the page,
/// the card and the replay can celebrate where the afternoon happened instead of on the
/// Records tab the next time somebody opens it.
///
/// docs/voice.md names "the end of a session" as one of the four places register 2 (Coach)
/// is allowed, and promised a line there that nothing rendered. This is that line, in one
/// home: the session page draws it above the block, the share caption leads with it and the
/// replay closes on it.
///
/// **The rules, in order** (docs/presentation/key-metrics.md, "The session tells its story"):
///
/// 1. The tally first, in the rider's words: dry jibes, then the clean ones. Falls are never
///    named — a session where every jibe went in reads as "12 jibes", not as its swims.
/// 2. Then the **one best true thing**: a first clean jibe ever beats everything; then an
///    all-time best, then a season best, then a month best — clean jibes, then best 2 s, then
///    the dry streak inside each scope.
/// 3. Nothing to celebrate: the plain tally, and that is the whole line.
///
/// **What "best" means here.** The session holds the record in a scope when it beats every
/// other session of the rider's in that scope, with the Records table's tie rule (the earlier
/// afternoon keeps it) and its speed rule (`SpeedRecordRule`, the rider's setting). A scope
/// with no other session in it holds nothing: "your fastest this month" over the month's only
/// afternoon is not a claim anybody would make at the van.
///
/// Deterministic: `now` decides only whether a scope reads "this month" or "that month".
public struct SessionStory: Sendable, Equatable {

    /// The Coach line, capitalised and closed with a full stop. At most about 15 words.
    public let line: String
    /// The widest record the session holds per kind, in `SessionHonour.Kind` order.
    public let honours: [SessionHonour]
    /// Clean jibes, and none in any earlier session the rider measured jibes in.
    public let firstCleanJibe: Bool

    public init(line: String, honours: [SessionHonour], firstCleanJibe: Bool) {
        self.line = line
        self.honours = honours
        self.firstCleanJibe = firstCleanJibe
    }

    /// The honour a key-metrics cell wears, by the cell's document key.
    public func honour(forCell key: String) -> SessionHonour? {
        honours.first { $0.kind.cellKey == key && $0.scope >= .season }
    }

    /// The chip on a key-metrics cell: "Best ever" or "Season best". Month bests stay in the
    /// line only — a chip on every cell of a good week is wallpaper.
    public func chip(forCell key: String) -> String? {
        honour(forCell: key)?.chip
    }

    /// The share card's ribbon, "Best ever · clean jibes": the widest record, nil without an
    /// all-time or season one.
    public var cardBadge: String? {
        let top = honours.filter { $0.scope >= .season }
            .max { $0.scope == $1.scope ? $0.kind.rank > $1.kind.rank : $0.scope < $1.scope }
        return top.map { $0.chip + " · " + $0.kind.noun }
    }

    /// Whether the session holds an all-time record of any kind.
    public var holdsAllTimeRecord: Bool { honours.contains { $0.scope == .allTime } }

    // MARK: - Building

    /// Whether a row is the rider's own ridden session — the same rule the Records table and
    /// the celebration apply (`LibraryStore.clause`, `SessionStore.refreshPersonalBests`).
    public static func counts(_ row: SessionRow) -> Bool {
        !row.isExample && !row.isProvisional && row.isSession && row.rider == nil
    }

    /// The story of `session` against `history` (the library; the session itself and every
    /// row that is not the rider's own are ignored). nil where there is nothing to say: no
    /// turn and no flight.
    public static func make(session: SessionRow, history: [SessionRow],
                            now: Date = Date(),
                            policy: SpeedRecordPolicy = .preferVerified) -> SessionStory? {
        guard let tally = tallyPhrase(session) else { return nil }
        let others = counts(session)
            ? history.filter { $0.id != session.id && counts($0) } : []
        // Each afternoon's local day once, not once per kind and scope.
        let days = Dictionary(others.map { ($0.id, LibraryStore.localDay($0)) },
                              uniquingKeysWith: { a, _ in a })
        let honours = others.isEmpty ? [] : SessionHonour.Kind.allCases.compactMap {
            widest($0, session: session, others: others, days: days, policy: policy)
        }
        let first = counts(session) && isFirstClean(session, others: others)

        var phrase: String?
        if first {
            phrase = (session.jibesSuccessful ?? 0) == 1 ? "your first clean jibe ever"
                                                         : "your first clean jibes ever"
        } else if let best = honours.filter({ $0.kind.inLine })
            .max(by: { $0.scope == $1.scope ? $0.kind.rank > $1.kind.rank
                                            : $0.scope < $1.scope }) {
            phrase = best.kind.linePhrase + " "
                + best.scope.words(session: session, now: now)
        }
        let body = [tally, phrase].compactMap { $0 }.joined(separator: ", ")
        return SessionStory(line: body.prefix(1).uppercased() + body.dropFirst() + ".",
                            honours: honours, firstCleanJibe: first)
    }

    /// "14 dry jibes, 9 clean" — or the turns, or the flights, on a session with fewer words
    /// to say. Never a fall.
    static func tallyPhrase(_ row: SessionRow) -> String? {
        let jibes = row.jibes ?? 0
        if jibes > 0 {
            let dry = row.jibesFellIn.map { jibes - $0 }
                ?? ((row.jibesFlewThrough ?? 0) + (row.jibesTouchdown ?? 0))
            let clean = row.jibesSuccessful ?? 0
            guard dry > 0 else { return plural(jibes, "jibe") }
            return plural(dry, "dry jibe") + (clean > 0 ? ", \(clean) clean" : "")
        }
        let turns = row.turnsCounted ?? 0
        if turns > 0 {
            let dry = row.turnsFellIn.map { turns - $0 } ?? 0
            return dry > 0 ? plural(dry, "dry turn") : plural(turns, "turn")
        }
        if let flights = row.flightCount, flights > 0 {
            guard let foil = row.foilTimeS, foil >= 60 else { return plural(flights, "flight") }
            return plural(flights, "flight") + ", " + KeyMetrics.listDuration(foil)
                + " on the foil"
        }
        return nil
    }

    static func plural(_ n: Int, _ word: String) -> String {
        "\(n) " + word + (n == 1 ? "" : "s")
    }

    /// Clean jibes today, and every earlier session with jibes in it measured none. An earlier
    /// row with no clean count at all (read before engine 0.10.0) makes the claim unknowable,
    /// so it is not made.
    static func isFirstClean(_ session: SessionRow, others: [SessionRow]) -> Bool {
        guard (session.jibesSuccessful ?? 0) > 0 else { return false }
        let earlier = others.filter { $0.startDate < session.startDate && ($0.jibes ?? 0) > 0 }
        guard !earlier.isEmpty else { return false }
        return earlier.allSatisfy { $0.jibesSuccessful == 0 }
    }

    /// The widest scope in which `session` holds `kind`, or nil.
    static func widest(_ kind: SessionHonour.Kind, session: SessionRow,
                       others: [SessionRow], days: [String: DateComponents],
                       policy: SpeedRecordPolicy) -> SessionHonour? {
        guard kind.value(session) != nil else { return nil }
        let day = LibraryStore.localDay(session)
        for scope in SessionHonour.Scope.allCases.reversed() {
            let rivals = others.filter { scope.contains(days[$0.id] ?? day, day: day) }
            if holds(kind, session: session, rivals: rivals, policy: policy) {
                return SessionHonour(kind: kind, scope: scope)
            }
        }
        return nil
    }

    /// Beats every rival with a value; the earlier afternoon keeps a tie. Speeds go through
    /// the rider's Speed records setting first, over the session and its rivals together.
    static func holds(_ kind: SessionHonour.Kind, session: SessionRow,
                      rivals: [SessionRow], policy: SpeedRecordPolicy) -> Bool {
        var field = ([session] + rivals).filter { kind.value($0) != nil }
        if kind.isSpeed {
            field = SpeedRecordRule.eligible(field, policy: policy) { $0.sourceClass != "c" }
        }
        guard let mine = kind.value(session), field.contains(where: { $0.id == session.id }),
              field.count >= 2 else { return false }
        return field.allSatisfy { other in
            guard other.id != session.id, let theirs = kind.value(other) else { return true }
            return theirs < mine || (theirs == mine && other.startDate > session.startDate)
        }
    }
}

/// One record a session holds: what, and how widely.
public struct SessionHonour: Sendable, Equatable, Hashable {

    public enum Kind: String, CaseIterable, Sendable {
        case cleanJibes, best2s, dryStreak, cph, alpha500, best5x10s, distance, duration

        /// The key-metrics cell the chip sits on (the document's cell keys).
        public var cellKey: String {
            switch self {
            case .cleanJibes: "cleanJibes"
            case .best2s: "max2s"
            case .dryStreak: "streaks"
            case .cph: "cph"
            case .alpha500: "alpha500"
            case .best5x10s: "best5x10s"
            case .distance: "distance"
            case .duration: "duration"
            }
        }

        /// What the card's ribbon calls it, after "Best ever · ".
        public var noun: String {
            switch self {
            case .cleanJibes: "clean jibes"
            case .best2s: "best 2 s"
            case .dryStreak: "dry streak"
            case .cph: "CPH"
            case .alpha500: "alpha 500"
            case .best5x10s: "5×10 s"
            case .distance: "distance"
            case .duration: "longest session"
            }
        }

        /// Only the three a rider quotes make the line; the rest wear a chip.
        var inLine: Bool { self == .cleanJibes || self == .best2s || self == .dryStreak }

        /// Lower is told first, inside one scope.
        var rank: Int { Kind.allCases.firstIndex(of: self) ?? 0 }

        var linePhrase: String {
            switch self {
            case .cleanJibes: "your most clean jibes"
            case .best2s: "your fastest 2 s"
            case .dryStreak: "your longest dry streak"
            default: "your best " + noun
            }
        }

        var isSpeed: Bool { self == .best2s || self == .alpha500 || self == .best5x10s }

        /// The session's value, nil where it has none worth a record. A streak under three is
        /// not a run (`ReplayCommentary.minStreak`).
        func value(_ row: SessionRow) -> Double? {
            let v: Double? = switch self {
            case .cleanJibes: row.jibesSuccessful.map(Double.init)
            case .best2s: row.best2sKn
            case .dryStreak: row.longestDryStreak.flatMap { $0 >= 3 ? Double($0) : nil }
            case .cph: SessionRecordKind.bestCph.value(in: row)
            case .alpha500: row.alpha500Kn
            case .best5x10s: row.best5x10sKn
            case .distance: row.distanceKm
            case .duration: row.rateSeconds
            }
            return v.flatMap { $0 > 0 ? $0 : nil }
        }
    }

    public enum Scope: Int, CaseIterable, Comparable, Sendable {
        case month, season, allTime

        public static func < (a: Scope, b: Scope) -> Bool { a.rawValue < b.rawValue }

        func contains(_ theirs: DateComponents, day: DateComponents) -> Bool {
            switch self {
            case .allTime: return true
            case .season: return Self.season(theirs) == Self.season(day)
            case .month: return theirs.year == day.year && theirs.month == day.month
            }
        }

        static func season(_ day: DateComponents) -> Int {
            PeriodRules.seasonYear(year: day.year ?? 0, month: day.month ?? 1)
        }

        /// "ever", "this season" / "that season", "this month" / "that month".
        func words(session: SessionRow, now: Date) -> String {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = session.displayZone
            let today = calendar.dateComponents([.year, .month], from: now)
            let day = LibraryStore.localDay(session)
            switch self {
            case .allTime: return "ever"
            case .season: return Self.season(today) == Self.season(day) ? "this season"
                                                                        : "that season"
            case .month:
                return today.year == day.year && today.month == day.month ? "this month"
                                                                          : "that month"
            }
        }
    }

    public let kind: Kind
    public let scope: Scope

    public init(kind: Kind, scope: Scope) {
        self.kind = kind
        self.scope = scope
    }

    /// "Best ever", "Season best", "Month best".
    public var chip: String {
        switch scope {
        case .allTime: "Best ever"
        case .season: "Season best"
        case .month: "Month best"
        }
    }
}
