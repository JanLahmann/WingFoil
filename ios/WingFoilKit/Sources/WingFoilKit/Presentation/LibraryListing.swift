import Foundation

/// **The session list, grouped and narrowed** — the two controls at the top of the Sessions
/// tab, as rules a test can call.
///
/// The library grew past the length a flat newest-first list answers questions on: "how many
/// afternoons in August", "everything at Torbole", "what came in from Strava" are all
/// questions about a *set* of sessions, and a rider was scrolling for them. Two controls
/// answer them — **group by** (all · month · year · spot) and one **filter** menu (spot,
/// source, discipline, a date window) — and both live here rather than in the view, for the
/// reason every other file in this folder exists: the decision "which month is this session
/// in" is a calendar question with a zone in it, and a zone question settled inside a
/// `ForEach` is a zone question settled differently on the next screen.
///
/// **The filter narrows the list, never the records** (docs/decisions.md ADR-025). Records,
/// Trends, Periods and the widget keep reading the whole library through `LibraryFilter`,
/// the SQL-side filter that has always been theirs. This one is a *view* of the Sessions
/// tab and is deliberately a separate type: a chip that hides half the list must never be
/// able to hide half a personal best.
///
/// Every date here is read on **the session's own clock** where it has one
/// (`SessionRow.displayZone`) — an evening session either side of midnight belongs to the
/// month the rider had, not to the month the reader's phone is in. The one exception is the
/// custom range, whose two ends are days the reader picked off *his* calendar; that is the
/// same split `PeriodsView` makes for the same reason.

// MARK: - The filter

/// Which of the four narrowings a chip stands for, so tapping one can clear exactly it.
public enum LibraryFilterField: String, Sendable, CaseIterable, Identifiable {
    case spot, source, discipline, dateRange

    public var id: String { rawValue }
}

/// One active narrowing, in the rider's words — "Nago-Torbole", "Strava", "2025",
/// "12 Jul – 3 Aug".
public struct LibraryFilterChip: Sendable, Equatable, Identifiable {
    public let field: LibraryFilterField
    public let label: String

    public var id: String { field.rawValue }

    public init(field: LibraryFilterField, label: String) {
        self.field = field
        self.label = label
    }
}

/// What the Sessions tab is currently showing. Every narrowing is optional and they compose
/// (`nil` = no restriction), the same shape `LibraryFilter` has on the aggregate screens.
public struct LibraryListFilter: Sendable, Equatable {

    /// A spot id; a session filed under any other spot, or under none, is out.
    public var spotId: String?

    /// A door the session came in by. `session.importSource` is a `+`-joined **set**
    /// ("file+icu" for a session that arrived twice), so this is containment and never
    /// equality — see `ImportSource.isNamed(in:)`, which is the one implementation of it.
    public var source: ImportSource?

    /// The preset the session is *analysed* under (`SessionRow.analysisDiscipline`), which
    /// is the rider's override first and the recording's own tag second. Not the raw
    /// `discipline` column, which is only the second of those two.
    public var discipline: Discipline?

    /// A closed range of days, **inclusive at both ends**. Only the calendar day of each
    /// end is read, so the time of day a `DatePicker` happens to carry is irrelevant — the
    /// same "both dates count" the Periods screen's own range has.
    public var dateRange: ClosedRange<Date>?

    public init(spotId: String? = nil, source: ImportSource? = nil,
                discipline: Discipline? = nil, dateRange: ClosedRange<Date>? = nil) {
        self.spotId = spotId
        self.source = source
        self.discipline = discipline
        self.dateRange = dateRange
    }

    public var isActive: Bool {
        spotId != nil || source != nil || discipline != nil || dateRange != nil
    }

    /// Does this session survive the filter? All four clauses are ANDed.
    public func matches(_ row: SessionRow, calendar: Calendar = .current) -> Bool {
        if let spotId, row.spotId != spotId { return false }
        if let source, !source.isNamed(in: row.importSource) { return false }
        if let discipline, row.analysisDiscipline != discipline { return false }
        if let dateRange {
            let day = LibraryListing.dayKey(row, calendar: calendar)
            let from = LibraryListing.dayKey(dateRange.lowerBound, calendar: calendar)
            let to = LibraryListing.dayKey(dateRange.upperBound, calendar: calendar)
            if day < from || day > to { return false }
        }
        return true
    }

    public func apply(to rows: [SessionRow], calendar: Calendar = .current) -> [SessionRow] {
        isActive ? rows.filter { matches($0, calendar: calendar) } : rows
    }

    public mutating func clear(_ field: LibraryFilterField) {
        switch field {
        case .spot: spotId = nil
        case .source: source = nil
        case .discipline: discipline = nil
        case .dateRange: dateRange = nil
        }
    }

    /// The chip row under the title, in the order the menu lists the narrowings.
    ///
    /// `spotName` is asked rather than looked up: only the app holds the spot table, and a
    /// spot that has since been deleted must still name its own chip rather than leave a
    /// blank capsule the rider cannot aim at.
    public func chips(spotName: (String) -> String?,
                      calendar: Calendar = .current) -> [LibraryFilterChip] {
        var out: [LibraryFilterChip] = []
        if let spotId {
            out.append(LibraryFilterChip(field: .spot, label: spotName(spotId) ?? "Spot"))
        }
        if let source {
            out.append(LibraryFilterChip(field: .source, label: source.libraryFilterLabel))
        }
        if let discipline {
            out.append(LibraryFilterChip(field: .discipline, label: discipline.title))
        }
        if let dateRange {
            out.append(LibraryFilterChip(
                field: .dateRange,
                label: LibraryListing.rangeLabel(dateRange, calendar: calendar)))
        }
        return out
    }
}

extension ImportSource {

    /// The door in the rider's words — what the filter menu and the chip say.
    ///
    /// Three of these have "watch" somewhere in their story and mean different things by it,
    /// so all three are spelled out: a Garmin summary card, the CleanJibe watch app's own
    /// recording, and a workout Apple's Workout app wrote into Health.
    public var libraryFilterLabel: String {
        switch self {
        case .icu: "intervals.icu"
        case .file: "File"
        case .gdpr: "Garmin export"
        case .airdrop: "AirDrop"
        // Dev and demo rows. They are hidden from the menu unless the library actually
        // holds one, and when it does the rider's word for it is "example" — "fixtures"
        // is a thing this repository has, not a thing he imported.
        case .fixtures, .example: "Example"
        case .watch: "Garmin watch"
        case .appleWatch: "Apple Watch"
        case .appleHealth: "Apple Health"
        case .strava: "Strava"
        }
    }

    /// Whether the source is offered in the filter menu without the library holding one.
    /// False for the two demo doors: a fresh install would otherwise offer to filter down
    /// to a kind of session it has never seen.
    public var isOfferedUnconditionally: Bool { self != .fixtures && self != .example }
}

// MARK: - Grouping

/// One `Section` of the session list: the heading, the count line beside it, and its rows.
public struct LibraryGroup: Sendable, Equatable, Identifiable {

    /// Stable across a redraw: `2026-08`, `2026`, a spot id, `nospot`, or `all` for the
    /// ungrouped list.
    public let key: String

    /// The heading alone — "August 2026", "2026", "Nago-Torbole", "No spot". **Empty for
    /// the ungrouped list**, which is how a view knows to draw no header at all.
    public let heading: String

    /// Rows, newest first, like the list they came from.
    public let rows: [SessionRow]

    public var id: String { key }

    public init(key: String, heading: String, rows: [SessionRow]) {
        self.key = key
        self.heading = heading
        self.rows = rows
    }

    /// **"August 2026 · 9 sessions"** — what the section header prints. `·` separates, as
    /// everywhere else in the app.
    ///
    /// The count is of *sessions*, which is not `rows.count`: the group may also hold a
    /// recording that is not one (engine 0.19.0, `LibraryListing.riddenCount`). Such a row
    /// is listed — it is the rider's recording and he has to be able to find it — and it is
    /// not counted, the same rule the totals, the trends and the records keep.
    public var title: String {
        heading.isEmpty ? "" : "\(heading) · \(LibraryListing.sessionCount(rows))"
    }
}

/// How the session list divides itself.
public enum LibraryGrouping: String, Sendable, CaseIterable, Identifiable {
    case none, month, year, spot

    public var id: String { rawValue }

    /// The segmented control's four words. The ungrouped case is called **"All"** rather
    /// than "None" (Jan, 14 Sep 2026): the segment beside Month and Year is not the absence
    /// of a list, it is the whole library in one piece, and "None" read as "nothing shown".
    /// The raw value stays `none` — it is what `library.groupBy.v1` already holds on every
    /// phone, and what `UI_GROUP_BY` takes.
    public var title: String {
        switch self {
        case .none: "All"
        case .month: "Month"
        case .year: "Year"
        case .spot: "Spot"
        }
    }

    /// **Month from twenty sessions up.** Below that the whole library is a screen or two
    /// and headings are furniture; above it the rider is already scrolling for a month.
    /// The count is the *unfiltered* library, deliberately: the default is a fact about how
    /// much he has, not about what he is looking at this second, and a list that ungrouped
    /// itself because a chip narrowed it to nineteen would be answering a different
    /// question every tap.
    public static let monthByDefaultFrom = 20

    public static func `default`(librarySize: Int) -> LibraryGrouping {
        librarySize >= monthByDefaultFrom ? .month : .none
    }

    /// The list as sections: **newest group first, newest session first inside it**, and
    /// "No spot" last whatever its dates say.
    ///
    /// `spotName` answers "what is this spot called" for the row's `spotId` — nil for a
    /// session that has no spot, and nil for one whose spot the table can no longer name,
    /// which are the same thing as far as a heading is concerned.
    public func groups(_ rows: [SessionRow],
                       spotName: (String?) -> String?,
                       calendar: Calendar = .current) -> [LibraryGroup] {
        let sorted = rows.sorted { $0.startDate > $1.startDate }
        guard self != .none else {
            return sorted.isEmpty ? [] : [LibraryGroup(key: "all", heading: "", rows: sorted)]
        }

        var order: [String] = []
        var buckets: [String: [SessionRow]] = [:]
        var headings: [String: String] = [:]
        for row in sorted {
            let bucket = key(for: row, spotName: spotName, calendar: calendar)
            if buckets[bucket.key] == nil {
                order.append(bucket.key)
                headings[bucket.key] = bucket.heading
            }
            buckets[bucket.key, default: []].append(row)
        }
        // `sorted` was already newest first, so `order` is newest-group-first by
        // construction; the only move is the spotless bucket, which is not a place and
        // therefore not a place in the sequence either.
        if self == .spot, let index = order.firstIndex(of: LibraryListing.noSpotKey) {
            order.append(order.remove(at: index))
        }
        return order.map {
            LibraryGroup(key: $0, heading: headings[$0] ?? "", rows: buckets[$0] ?? [])
        }
    }

    private func key(for row: SessionRow, spotName: (String?) -> String?,
                     calendar: Calendar) -> (key: String, heading: String) {
        switch self {
        case .none:
            return ("all", "")
        case .month:
            let c = LibraryListing.components(row, calendar: calendar)
            let month = LibraryStore.monthsLong[max(1, min(12, c.month ?? 1)) - 1]
            return (String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0),
                    month + " " + String(c.year ?? 0))
        case .year:
            let c = LibraryListing.components(row, calendar: calendar)
            return (String(format: "%04d", c.year ?? 0), "\(c.year ?? 0)")
        case .spot:
            guard let id = row.spotId, let name = spotName(id) else {
                return (LibraryListing.noSpotKey, "No spot")
            }
            return (id, name)
        }
    }
}

// MARK: - The date window

/// The four entries of the filter menu's date section. The window a rider picks is stored
/// as the range it resolves to (`LibraryListFilter.dateRange`), not as the word — "this
/// year" is a sentence about a calendar and the calendar is where it should be settled,
/// once, at the moment he taps it.
public enum LibraryDateWindow: String, Sendable, CaseIterable, Identifiable {
    case allTime, thisYear, lastYear, custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .allTime: "All time"
        case .thisYear: "This year"
        case .lastYear: "Last year"
        case .custom: "Custom range…"
        }
    }

    /// 1 January to 31 December of one year, on the reader's calendar. A whole calendar
    /// year rather than a season: the Sessions tab is a list of afternoons by date, and the
    /// season cut (`PeriodRules.seasonStartMonth`) belongs to the screen that names seasons.
    public static func year(_ year: Int, calendar: Calendar = .current) -> ClosedRange<Date>? {
        guard let first = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let last = calendar.date(from: DateComponents(year: year, month: 12, day: 31))
        else { return nil }
        return first...last
    }

    /// Which entry a stored range reads as, so the menu can tick its own row. A range that
    /// is exactly one calendar year *is* that year — there is no second way to have picked
    /// it, and a rider who typed 1 Jan to 31 Dec meant the year.
    public static func window(for range: ClosedRange<Date>?, now: Date = Date(),
                              calendar: Calendar = .current) -> LibraryDateWindow {
        guard let range else { return .allTime }
        let thisYear = calendar.component(.year, from: now)
        if range == year(thisYear, calendar: calendar) { return .thisYear }
        if range == year(thisYear - 1, calendar: calendar) { return .lastYear }
        return .custom
    }
}

// MARK: - Words and days

/// The small shared pieces: the day a session belongs to, the count line, the chip's words.
public enum LibraryListing {

    /// The bucket a session with no spot falls in. Not a spot id — no spot has one.
    public static let noSpotKey = "nospot"

    /// **"9 sessions"**, "1 session".
    public static func sessionCount(_ n: Int) -> String {
        let noun = n == 1 ? " session" : " sessions"
        return String(n) + noun
    }

    /// **"9 sessions"** over a list of rows — counting the ones that *are* sessions.
    ///
    /// The list and the count answer two different questions, and since engine 0.19.0 they
    /// can disagree: the list shows every recording the rider has, the count says how many
    /// afternoons he rode. Jan's library read "44 sessions" on 14 September 2026 with
    /// thirteen 0:00–0:24 min test recordings inside the number.
    public static func sessionCount(_ rows: [SessionRow]) -> String {
        sessionCount(riddenCount(rows))
    }

    /// How many of these rows are sessions — the count every "N sessions" line should show.
    ///
    /// A provisional row is one too: the watch says the afternoon happened, and the rider
    /// counting his week does not care that its recording is still in the air. What is not
    /// counted is a recording the engine says was never a session (`SessionRow.isSession`,
    /// docs/algorithms.md "Not a session"); a provisional row's own `no_recording` verdict is
    /// therefore read past here, and only here.
    public static func riddenCount(_ rows: [SessionRow]) -> Int {
        rows.filter { $0.isSession || $0.isProvisional }.count
    }

    /// The calendar day a session belongs to, on **its own** clock where it recorded one
    /// and on the caller's calendar where it did not (`SessionRow.displayZone`).
    static func components(_ row: SessionRow, calendar: Calendar) -> DateComponents {
        var calendar = calendar
        if row.hasKnownZone { calendar.timeZone = row.displayZone }
        return calendar.dateComponents([.year, .month, .day], from: row.startDate)
    }

    static func dayKey(_ row: SessionRow, calendar: Calendar) -> String {
        LibraryStore.dayKey(components(row, calendar: calendar))
    }

    /// A date the *reader* picked, as his own day. The other half of the split this file's
    /// header describes.
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        LibraryStore.dayKey(calendar.dateComponents([.year, .month, .day], from: date))
    }

    /// The date chip's words: **"2025"** for a whole calendar year, **"12 Jul – 3 Aug"**
    /// for anything else — the Periods screen's own short span, so one range reads the same
    /// on both screens.
    static func rangeLabel(_ range: ClosedRange<Date>, calendar: Calendar) -> String {
        let first = calendar.dateComponents([.year, .month, .day], from: range.lowerBound)
        let last = calendar.dateComponents([.year, .month, .day], from: range.upperBound)
        if first.year == last.year, first.month == 1, first.day == 1,
           last.month == 12, last.day == 31 {
            return "\(first.year ?? 0)"
        }
        return LibraryStore.spanShort(first, last)
    }
}
