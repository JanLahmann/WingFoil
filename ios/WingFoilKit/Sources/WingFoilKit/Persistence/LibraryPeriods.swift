import Foundation
import GRDB

/// Periods — a month, a season, a trip, or a range the rider typed.
///
/// Four ways of naming a *set of afternoons*, all described by one aggregate block
/// (`PeriodBlock`). The rules are stated in docs/presentation.md and implemented twice: here
/// and in the analyzer's `web/lab_bundle/library.py`, which is the reference. The two are
/// pinned against `fixtures/periods/periods.expected.json`, so a rule that changed on one
/// side is a failing test rather than a rider reading two different holidays.
public enum PeriodRules {

    /// How far apart two afternoons can be and still be one holiday. Three days: a trip has
    /// rest days, blown-out days and travel days in it, and a Tuesday off does not end a week
    /// at Garda. Four days apart is a second visit.
    public static let tripGapDays = 3

    /// One afternoon somewhere is a session, not a trip. A heading has to be worth a heading.
    public static let tripMinSessions = 2

    /// Spot radius for the trip clusterer, and deliberately looser than `SpotClusterer`'s own
    /// 500 m default, because it is not the same question. The spot table is naming *launches*
    /// and wants the beach; a trip is asking whether two afternoons were the same holiday, and
    /// Torbole and Malcesine are one week at Garda and 15 km apart. 3 km keeps a lake's north
    /// shore together and still separates two spots in one city.
    public static let tripRadiusM: Double = 3000

    /// The season cut: **1 April → 31 March**, one Northern-hemisphere water year, so a
    /// February afternoon still counts towards the winter it belongs to. The same cut the
    /// Trends range picker has always used; stated here rather than invented a second time.
    public static let seasonStartMonth = 4

    /// Which season a local day belongs to, named by the calendar year it opened in.
    public static func seasonYear(year: Int, month: Int) -> Int {
        month >= seasonStartMonth ? year : year - 1
    }

    /// `2026/27` once the season has reached January, `2026` while it has not.
    public static func seasonLabel(startYear: Int, crossesYear: Bool) -> String {
        crossesYear ? String(format: "%d/%02d", startYear, (startYear + 1) % 100)
                    : String(startYear)
    }
}

public enum PeriodKind: String, Sendable, Codable, CaseIterable {
    case trip, month, season, custom
}

/// One period, headed and blocked — everything a row on the Periods screen and a period card
/// need, resolved once.
public struct Period: Sendable, Equatable, Identifiable {
    public let kind: PeriodKind
    /// Stable id: `trip:<first session id>`, `2026-08`, `2026`, or `custom:<from>:<to>`.
    public let key: String
    /// The heading — "Nago Torbole · 31 Jul – 6 Aug", "August 2026", "Season 2026/27".
    public let title: String
    /// The spot a trip is at, for the heading and for a card that wants to name it. nil on
    /// every other kind, which is about a calendar rather than a place.
    public let spot: String?
    /// The span in words, en-GB — "31 July – 6 August 2026". The card's date line.
    public let dateLine: String
    /// The same span short — "31 Jul – 6 Aug". What a trip heading hangs off its spot's name.
    public let spanShort: String
    /// First and last **local** calendar day, `YYYY-MM-DD`, or nil for an empty period.
    public let startDate: String?
    public let endDate: String?
    public let sessionIds: [String]
    public let sessions: Int
    /// Whether the card may offer a **map background** under this period.
    ///
    /// A period is a set of afternoons and they need not have happened anywhere near one
    /// another, so "which rectangle of the earth?" has no answer a card can take for granted:
    /// the union box of a month split between Garda and the Rhine is mostly the motorway
    /// between them. The ground is therefore offered exactly when the period is one place —
    /// every session inside a single `PeriodRules.tripRadiusM` cluster, and every one of them
    /// placed by a fix rather than by the spot it was filed under. Otherwise the switch is not
    /// offered at all, rather than offered and inert (docs/presentation.md, "The period card").
    ///
    /// The analyzer decides the same thing in `library._map_ground`, and the two are pinned
    /// against the shared fixture like every other field here.
    public let mapGround: Bool
    public let block: [PeriodBlock.Entry]

    public var id: String { key }
}

/// Every period a library implies: trips, then months, then seasons — the order the screens
/// list them in, each newest first, because the last holiday is the one being looked for.
public struct PeriodSet: Sendable, Equatable {
    public var trips: [Period] = []
    public var months: [Period] = []
    public var seasons: [Period] = []

    public var isEmpty: Bool { trips.isEmpty && months.isEmpty && seasons.isEmpty }

    public init(trips: [Period] = [], months: [Period] = [], seasons: [Period] = []) {
        self.trips = trips
        self.months = months
        self.seasons = seasons
    }
}

// MARK: - Queries

extension LibraryStore {

    /// Every trip, month and season under the filter. The same `LibraryFilter` the records
    /// and trends screens use, so a spot or a gear restriction narrows a holiday too.
    public func periods(_ filter: LibraryFilter = LibraryFilter()) async throws -> PeriodSet {
        try await database.writer.read { db in
            Self.periods(try Self.sessions(filter, db: db),
                         spotNames: try Self.spotNames(db: db))
        }
    }

    /// One custom range, inclusive on both ends, in **local** calendar days.
    ///
    /// Inclusive because two date fields are read as "from this day to that day", which is
    /// what a person means by them; an exclusive end would silently drop the last afternoon of
    /// a holiday, which is usually the best one. Either end may be nil, which is open.
    public func periodBlock(_ filter: LibraryFilter = LibraryFilter(),
                            from: String? = nil, to: String? = nil) async throws -> Period {
        try await database.writer.read { db in
            Self.customPeriod(try Self.sessions(filter, db: db),
                              spotNames: try Self.spotNames(db: db), from: from, to: to)
        }
    }

    static func spotNames(db: Database) throws -> [String: String] {
        var out: [String: String] = [:]
        for spot in try SpotRow.fetchAll(db) { out[spot.id] = spot.name }
        return out
    }

    // MARK: - The rules, as pure functions

    /// `rows` is oldest-first, which is what every "ties go to the earliest" and every
    /// "the first name the place was given" below depends on.
    static func periods(_ rows: [SessionRow], spotNames: [String: String]) -> PeriodSet {
        PeriodSet(trips: trips(rows, spotNames: spotNames),
                  months: months(rows, spotNames: spotNames),
                  seasons: seasons(rows, spotNames: spotNames))
    }

    /// The calendar day the **rider** had, as `(y, m, d)`.
    ///
    /// `row.displayZone` and nothing else: a session that starts at 00:30 in Torbole is a
    /// 22:30 UTC session on the previous day, and a month bucketed on the UTC instant would
    /// file that evening under the month before it happened. The reader's own clock is right
    /// for a week histogram he scans against *this* week and wrong for this, which is about
    /// which afternoon belongs to which August.
    static func localDay(_ row: SessionRow) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = row.displayZone
        return calendar.dateComponents([.year, .month, .day], from: row.startDate)
    }

    static func dayKey(_ c: DateComponents) -> String {
        String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Days between two local calendar days, ignoring clocks entirely — the gap rule is about
    /// dates on a wall calendar, not about elapsed hours, so a 23-hour gap over a DST boundary
    /// is still one day and an afternoon-then-morning pair is still zero.
    static func dayGap(_ a: DateComponents, _ b: DateComponents) -> Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let from = utc.date(from: DateComponents(year: a.year, month: a.month, day: a.day)),
              let to = utc.date(from: DateComponents(year: b.year, month: b.month, day: b.day))
        else { return 0 }
        return Int(((to.timeIntervalSince(from)) / 86_400).rounded())
    }

    // MARK: Places

    /// Group the rows into places, as index lists into `rows`.
    ///
    /// `SpotClusterer.cluster` does the work — the same greedy single-link assignment against a
    /// moving centroid the spot table is built with, at the trip radius rather than the spot
    /// one. A row with **no** start fix cannot be placed, so it falls back to the spot it was
    /// already assigned to: it joins a cluster whose members share that `spotId`, and otherwise
    /// seeds one of its own. The analyzer does the same thing keyed on the filename-derived
    /// spot *name*, which is the only handle a digest has.
    static func spotClusters(_ rows: [SessionRow]) -> [[Int]] {
        var fixes: [SpotClusterer.Fix] = []
        var unplaced: [Int] = []
        for (index, row) in rows.enumerated() {
            guard let lat = row.startLat, let lon = row.startLon else {
                unplaced.append(index)
                continue
            }
            fixes.append(SpotClusterer.Fix(sessionId: String(index), lat: lat, lon: lon))
        }
        var clusters = SpotClusterer.cluster(fixes, radiusM: PeriodRules.tripRadiusM)
            .map { $0.sessionIds.compactMap(Int.init) }

        for index in unplaced {
            let spotId = rows[index].spotId
            let home = clusters.firstIndex { members in
                spotId != nil && members.contains { rows[$0].spotId == spotId }
            }
            if let home {
                clusters[home].append(index)
            } else {
                clusters.append([index])
            }
        }
        return clusters.map { $0.sorted() }
    }

    /// What to call a cluster: the spot name most of its afternoons carry, ties to the
    /// earliest — the first name a place was given is the one the rider has been reading ever
    /// since. "Session" when nothing in it has been named at all, which is the analyzer's
    /// word for the same hole.
    static func clusterName(_ rows: [SessionRow], members: [Int],
                            spotNames: [String: String]) -> String {
        var counts: [String: Int] = [:]
        for index in members {
            guard let id = rows[index].spotId, let name = spotNames[id], !name.isEmpty
            else { continue }
            counts[name, default: 0] += 1
        }
        guard let best = counts.values.max() else { return "Session" }
        for index in members {                                  // oldest first
            guard let id = rows[index].spotId, let name = spotNames[id] else { continue }
            if counts[name] == best { return name }
        }
        return "Session"
    }

    /// Split one place's afternoons into visits on the gap rule. A row whose day cannot be
    /// read is left out — a trip is a span, and a session that cannot say which day it was on
    /// cannot be inside one.
    static func visits(_ rows: [SessionRow], members: [Int]) -> [[Int]] {
        let dated = members
            .map { ($0, localDay(rows[$0])) }
            .filter { $0.1.year != nil }
            .sorted { dayKey($0.1) < dayKey($1.1) }
        var out: [[Int]] = []
        var run: [Int] = []
        var previous: DateComponents?
        for (index, day) in dated {
            if let previous, dayGap(previous, day) > PeriodRules.tripGapDays {
                out.append(run)
                run = []
            }
            run.append(index)
            previous = day
        }
        if !run.isEmpty { out.append(run) }
        return out
    }

    // MARK: The three groups

    static func trips(_ rows: [SessionRow], spotNames: [String: String]) -> [Period] {
        var out: [Period] = []
        for members in spotClusters(rows) {
            let name = clusterName(rows, members: members, spotNames: spotNames)
            for run in visits(rows, members: members)
            where run.count >= PeriodRules.tripMinSessions {
                let first = localDay(rows[run[0]]), last = localDay(rows[run[run.count - 1]])
                out.append(period(.trip, key: "trip:\(rows[run[0]].id)",
                                  title: "\(name) · \(spanShort(first, last))",
                                  rows: rows, members: run, spot: name))
            }
        }
        // Newest first, and the title breaks a same-day tie so the order is total: two trips
        // that started on one day would otherwise depend on the clusterer's arrival order.
        out.sort { ($0.startDate ?? "", $0.title) > ($1.startDate ?? "", $1.title) }
        return out
    }

    static func months(_ rows: [SessionRow], spotNames: [String: String]) -> [Period] {
        var buckets: [String: [Int]] = [:]
        for (index, row) in rows.enumerated() {
            let day = localDay(row)
            guard let year = day.year, let month = day.month else { continue }
            buckets[String(format: "%04d-%02d", year, month), default: []].append(index)
        }
        return buckets.keys.sorted(by: >).map { key in
            let month = Int(key.suffix(2)) ?? 1
            return period(.month, key: key,
                          title: "\(Self.monthsLong[month - 1]) \(key.prefix(4))",
                          rows: rows, members: buckets[key] ?? [])
        }
    }

    static func seasons(_ rows: [SessionRow], spotNames: [String: String]) -> [Period] {
        var buckets: [Int: [Int]] = [:]
        var crosses: [Int: Bool] = [:]
        for (index, row) in rows.enumerated() {
            let day = localDay(row)
            guard let year = day.year, let month = day.month else { continue }
            let season = PeriodRules.seasonYear(year: year, month: month)
            buckets[season, default: []].append(index)
            crosses[season] = (crosses[season] ?? false) || year > season
        }
        return buckets.keys.sorted(by: >).map { year in
            let label = PeriodRules.seasonLabel(startYear: year,
                                                crossesYear: crosses[year] ?? false)
            return period(.season, key: String(year), title: "Season \(label)",
                          rows: rows, members: buckets[year] ?? [])
        }
    }

    static func customPeriod(_ rows: [SessionRow], spotNames: [String: String],
                             from: String?, to: String?) -> Period {
        var members: [Int] = []
        for (index, row) in rows.enumerated() {
            let day = localDay(row)
            guard day.year != nil else { continue }
            let key = dayKey(day)
            if let from, key < from { continue }
            if let to, key > to { continue }
            members.append(index)
        }
        let days = members.map { localDay(rows[$0]) }
        var title = "No sessions in this range"
        if let first = days.min(by: { dayKey($0) < dayKey($1) }),
           let last = days.max(by: { dayKey($0) < dayKey($1) }) {
            title = spanShort(first, last)
            if first.year == last.year { title += " \(last.year ?? 0)" }
        }
        return period(.custom, key: "custom:\(from ?? ""):\(to ?? "")", title: title,
                      rows: rows, members: members)
    }

    // MARK: Assembly

    static func period(_ kind: PeriodKind, key: String, title: String,
                       rows: [SessionRow], members: [Int], spot: String? = nil) -> Period {
        let picked = members.map { rows[$0] }
        let days = members.map { localDay(rows[$0]) }.filter { $0.year != nil }
        let first = days.min { dayKey($0) < dayKey($1) }
        let last = days.max { dayKey($0) < dayKey($1) }
        let f = facts(picked)
        // One place, and every afternoon of it placed by a fix: a row the clusterer had to
        // file by its spot rather than by coordinates cannot be said to be *at* the beach the
        // camera would point at. The twin of `library._map_ground`.
        let anchored = !picked.isEmpty
            && picked.allSatisfy { $0.startLat != nil && $0.startLon != nil }
        return Period(
            kind: kind, key: key, title: title, spot: spot,
            dateLine: first.map { spanLine($0, last ?? $0) } ?? "",
            spanShort: first.map { spanShort($0, last ?? $0) } ?? "",
            startDate: first.map(dayKey), endDate: last.map(dayKey),
            sessionIds: picked.map(\.id), sessions: picked.count,
            mapGround: anchored && f.spots == 1,
            block: PeriodBlock.entries(f))
    }

    /// Every number the block prints, summed the way the metric means it.
    ///
    /// **Rates use the summed denominators, never the mean of the per-session rates.** Ten
    /// minutes with one clean jibe and three hours with three is not "6.0 and 1.0, so 3.5 an
    /// hour"; it is four clean jibes in three hours and ten minutes. The same rule already
    /// governs the gear rollup's on-foil share.
    static func facts(_ rows: [SessionRow]) -> PeriodBlock.Facts {
        func sum<T: Numeric>(_ pick: (SessionRow) -> T?) -> T? {
            let values = rows.compactMap(pick)
            return values.isEmpty ? nil : values.reduce(0, +)
        }
        var f = PeriodBlock.Facts()
        f.sessions = rows.count
        f.spots = spotClusters(rows).count

        let seconds = rows.reduce(0.0) { $0 + $1.rateSeconds }
        f.hours = seconds > 0 ? seconds / 3600 : nil
        f.distanceKm = sum { $0.distanceKm }
        f.flights = sum { $0.flightCount }
        // The engine's own denominator for its own foil share, recovered the way the analyzer
        // recovers it: dividing by elapsed time instead would report a library-wide share
        // well below every session in it.
        let foil = sum { $0.foilTimeS }
        let onWater = sum { row -> Double? in
            guard let foil = row.foilTimeS, let pct = row.foilPct, pct > 0 else { return nil }
            return foil * 100 / pct
        }
        if let foil, let onWater, onWater > 0 { f.foilPct = 100 * foil / onWater }

        let clean = sum { $0.jibesSuccessful }
        let jibes = sum { $0.jibes }
        f.cleanJibes = clean
        if let clean, let hours = f.hours { f.cph = Double(clean) / hours }
        f.turns = sum { $0.turnsCounted }
        // The same floor as the session record, over the period's own total: four clean out
        // of four is a good week, and it is still not a rate.
        if let clean, let jibes, jibes >= SessionRecordKind.minJibesForRate {
            f.cleanJibeRatePct = 100 * Double(clean) / Double(jibes)
        }
        if let wet: Int = sum({ $0.wetExits }), let hours = f.hours {
            f.wph = Double(wet) / hours
        }
        f.best2sKn = rows.compactMap(\.best2sKn).max()
        f.best10sKn = rows.compactMap(\.best10sKn).max()
        f.longestFlightS = rows.compactMap(\.longestFlightS).max()
        f.longestDryStreak = rows.compactMap(\.longestDryStreak).max()
        return f
    }

    // MARK: Words

    /// Month names written out rather than asked of a `DateFormatter`: a card is dated in
    /// en-GB wherever it is exported (`ShareCardStats.dateLine` pins the same thing for a
    /// session), and a period's heading must not change language with the device.
    static let monthsLong = ["January", "February", "March", "April", "May", "June", "July",
                             "August", "September", "October", "November", "December"]
    static let monthsShort = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// The period's dates in words. One day is one date; a span inside one month names the
    /// month once; a span inside one year names the year once. The year is always there,
    /// because a card outlives the season it was made in.
    static func spanLine(_ first: DateComponents, _ last: DateComponents) -> String {
        let fm = Self.monthsLong[(first.month ?? 1) - 1], lm = Self.monthsLong[(last.month ?? 1) - 1]
        if dayKey(first) == dayKey(last) { return "\(first.day ?? 0) \(fm) \(first.year ?? 0)" }
        if first.year == last.year && first.month == last.month {
            return "\(first.day ?? 0) – \(last.day ?? 0) \(lm) \(last.year ?? 0)"
        }
        if first.year == last.year {
            return "\(first.day ?? 0) \(fm) – \(last.day ?? 0) \(lm) \(last.year ?? 0)"
        }
        return "\(first.day ?? 0) \(fm) \(first.year ?? 0) – \(last.day ?? 0) \(lm) \(last.year ?? 0)"
    }

    /// `31 Jul – 6 Aug`, for a trip heading that already carries the spot's name. The year
    /// joins it only when the trip crosses one, where leaving it out would be a riddle.
    static func spanShort(_ first: DateComponents, _ last: DateComponents) -> String {
        let fm = Self.monthsShort[(first.month ?? 1) - 1]
        let lm = Self.monthsShort[(last.month ?? 1) - 1]
        if first.year != last.year {
            return "\(first.day ?? 0) \(fm) \(first.year ?? 0) – "
                 + "\(last.day ?? 0) \(lm) \(last.year ?? 0)"
        }
        if dayKey(first) == dayKey(last) { return "\(first.day ?? 0) \(fm)" }
        return "\(first.day ?? 0) \(fm) – \(last.day ?? 0) \(lm)"
    }
}
