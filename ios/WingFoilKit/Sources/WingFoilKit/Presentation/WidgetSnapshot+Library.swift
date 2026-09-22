import Foundation

/// The half of the widget snapshot that reads the library.
///
/// Split from `WidgetSnapshot.swift` so the widget extension can compile the *format*
/// without dragging GRDB and the FIT parser into an extension whose whole job is to decode
/// one small JSON blob. Only the app compiles this file.
extension WidgetSnapshot {

    /// Vertices kept for the breadcrumb behind the numbers. About 150: enough that a Garda
    /// afternoon still reads as that afternoon at 158 pt wide, few enough that the whole
    /// blob stays a couple of kilobytes. The thinning happens **here** and never in the
    /// widget — an extension with a 30 MB budget does not walk a track.
    public static let maxTrackPoints = 150

    /// How much of the recent past `recent` carries: a fortnight, so the widget can re-add
    /// its own seven-day window for any day the timeline draws.
    public static let recentDays = 14

    /// **Was this afternoon ridden?** — the newest row that answers yes is what the
    /// home screen calls "your last session".
    ///
    /// Two conditions, and both are about the same question. A *provisional* row is the
    /// watch's BLE card with no FIT behind it yet: real, kept, badged in the library, and
    /// not yet analysed, so it has no foil time to show and would print a row of dashes.
    /// And a row with no foil time at all is a dry test recording — a walk to the beach, a
    /// watch left running in the van — which is exactly what put "FOIL 0 % · FLIGHTS 0" on
    /// Jan's home screen on 14 September 2026 while the afternoon before it sat one row
    /// down.
    /// Since engine 0.19.0 this is the **strict** end of a rule the engine now owns
    /// (`SessionVerdict`, docs/algorithms/not-a-session.md "Not a session"), and the two are deliberately
    /// not the same test. *Not a session* is "no foil time **and** it went nowhere" — the
    /// beach recording; *ridden* is "there is foil time on it", which a skunked afternoon
    /// fails while remaining a session anybody would count. Ridden therefore implies a
    /// session, and the `isSession` conjunct below is redundant by construction — it is
    /// written out so the relation between the two is visible where both are read, and so
    /// that a provisional row's `no_recording` verdict is covered by the same clause.
    public static func isRidden(_ row: SessionRow) -> Bool {
        !row.isProvisional && row.isSession && foilSeconds(row) > 0
    }

    /// Seconds on the foil. `foilTimeS` is a schema-v2 column; an older row falls back to
    /// the percentage, which is the same quantity with a rounding error rather than a
    /// missing bar. 0 when the row cannot answer — never nil, because every caller here is
    /// summing or comparing it.
    public static func foilSeconds(_ row: SessionRow) -> Double {
        if let foilTimeS = row.foilTimeS { return foilTimeS }
        if let pct = row.foilPct { return row.rateSeconds * pct / 100 }
        return 0
    }

    /// Builds the snapshot from the library's summary rows.
    ///
    /// `titleForRow` is injected because a readable session name is presentation the app
    /// owns (spot name, then filename). `trackForRow` hands over the session's cached
    /// outline — the same `TrackThumbnail` the list row and the share card draw, so the
    /// widget's breadcrumb is the same picture as every other one in the app. `jibesPerHour`
    /// is JPH per session id (`LibraryStore.jibeRates`), which is a query rather than a
    /// column: the session index denormalizes CPH and not JPH, and a rate the widget made
    /// up out of `jibes` would sit beside the session page's JPH disagreeing with it.
    /// `now` is a parameter so every window here is testable.
    ///
    /// `policy` is Settings → Speed records. The widget's "Best 2 s" is an all-time claim
    /// about the rider, so it obeys the same `SpeedRecordRule` the records table does. The
    /// widget process cannot read the setting for itself, which is why the phone resolves
    /// it here and publishes the answer rather than the question.
    public static func make(sessions: [SessionRow], now: Date = Date(),
                            jibesPerHour: [String: Double] = [:],
                            policy: SpeedRecordPolicy = .preferVerified,
                            titleForRow: (SessionRow) -> String,
                            trackForRow: (SessionRow) -> TrackThumbnail? = { _ in nil })
        -> WidgetSnapshot {
        let sorted = sessions.sorted { $0.startDate < $1.startDate }
        var snapshot = WidgetSnapshot(generatedAt: now)
        // Every speed below stays in knots; this is how the home screen learns which unit
        // to *print* them in, because a widget process cannot read the app's defaults
        // (Settings → Units, docs/presentation.md).
        snapshot.speedUnit = Speed.unit.rawValue

        // The last session *ridden*, and only the newest row of all when the library holds
        // no ridden session — a rider whose library is one dry test still gets his row.
        if let latest = sorted.last(where: isRidden) ?? sorted.last {
            snapshot.lastSession = LastSession(
                id: latest.id,
                title: titleForRow(latest),
                date: latest.startDate,
                foilPct: latest.foilPct,
                best2sKn: latest.best2sKn,
                flightCount: latest.flightCount,
                // The engine's cleaned span (`rateSeconds`), the same clock the session
                // page and the library row print (docs/presentation/one-clock.md, "One clock").
                durationS: latest.rateSeconds,
                flewThrough: latest.turnsFlewThrough ?? 0,
                touchdown: latest.turnsTouchdown ?? 0,
                fellIn: latest.turnsFellIn ?? 0,
                track: trackForRow(latest).flatMap(track(from:)))
        }

        // Ridden afternoons only, in both windows: two dry test recordings are not "2
        // sessions · 0 m on the foil", they are a week with nothing in it.
        let ridden = sorted.filter(isRidden)
        let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)
        let week = ridden.filter { $0.startDate >= weekAgo && $0.startDate <= now }
        snapshot.weeklySessions = week.count
        snapshot.weeklyHours = week.reduce(0) { $0 + $1.rateSeconds } / 3600
        snapshot.weeklyFoilMinutes = week.reduce(0) { $0 + foilSeconds($1) / 60 }

        let fortnightAgo = now.addingTimeInterval(-Double(recentDays) * 24 * 3600)
        snapshot.recent = ridden.filter { $0.startDate >= fortnightAgo && $0.startDate <= now }
            .map { Day(date: $0.startDate, foilMinutes: foilSeconds($0) / 60,
                       hours: $0.rateSeconds / 3600) }

        let seasonRows = season(ridden, now: now)
        snapshot.season = seasonSummary(seasonRows.rows, label: seasonRows.label)
        snapshot.bests = bests(ridden, scope: .allTime, jibesPerHour: jibesPerHour,
                               policy: policy, titleForRow: titleForRow)
        snapshot.facts = rotation(season: seasonRows.rows, all: ridden, now: now,
                                  jibesPerHour: jibesPerHour, policy: policy,
                                  titleForRow: titleForRow,
                                  allTime: snapshot.bests ?? [])
        return snapshot
    }

    // MARK: - The track behind the numbers

    /// Thins a cached thumbnail down to the widget's budget and drops everything a
    /// breadcrumb does not draw — the phase of each vertex, the marks, the sparkline.
    ///
    /// The geometry is *not* re-derived: the thumbnail's vertices are already in the unit
    /// box the app's own projection put them in, so the widget's outline and the list row's
    /// are the same shape. Coordinates are rounded to four decimals, which is about a
    /// tenth of a pixel at widget size and roughly halves the JSON.
    public static func track(from thumbnail: TrackThumbnail) -> Track? {
        let points = thumbnail.points
        guard points.count >= 2 else { return nil }
        // **Evenly spaced, not every nth.** A stride would turn the thumbnail's own 165
        // vertices into 83 — half the outline thrown away to respect a budget it was
        // already inside. This picks exactly `maxTrackPoints` indices across the track,
        // first and last included, so a longer recording loses detail and a shorter one
        // loses nothing.
        let kept: [TrackThumbnail.Point]
        if points.count <= maxTrackPoints {
            kept = points
        } else {
            let last = Double(points.count - 1)
            let steps = Double(maxTrackPoints - 1)
            kept = (0..<maxTrackPoints).map { points[Int((Double($0) * last / steps).rounded())] }
        }
        guard kept.count >= 2 else { return nil }

        func round4(_ value: Double) -> Double { (value * 10_000).rounded() / 10_000 }
        var xy: [Double] = []
        xy.reserveCapacity(kept.count * 2)
        for point in kept {
            xy.append(round4(point.x))
            xy.append(round4(point.y))
        }
        let xs = xy.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
        let ys = xy.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
        return Track(xy: xy,
                     minX: xs.min() ?? 0, minY: ys.min() ?? 0,
                     maxX: xs.max() ?? 1, maxY: ys.max() ?? 1,
                     spanM: thumbnail.bounds?.spanM ?? 0)
    }

    // MARK: - The season

    /// The season `now` falls in, and the rows of it — the app's own season, 1 April →
    /// 31 March (`PeriodRules`), so a February afternoon still counts towards the winter it
    /// belongs to. The label is the Periods screen's, spelled by the same function, because
    /// two names for one season is two seasons to a reader.
    static func season(_ rows: [SessionRow], now: Date) -> (rows: [SessionRow], label: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current              // "this season" is the reader's calendar
        let today = calendar.dateComponents([.year, .month], from: now)
        guard let year = today.year, let month = today.month else { return ([], "") }
        let startYear = PeriodRules.seasonYear(year: year, month: month)

        var crosses = false
        let members = rows.filter { row in
            let day = LibraryStore.localDay(row)
            guard let rowYear = day.year, let rowMonth = day.month else { return false }
            guard PeriodRules.seasonYear(year: rowYear, month: rowMonth) == startYear else {
                return false
            }
            crosses = crosses || rowYear > startYear
            return true
        }
        return (members, PeriodRules.seasonLabel(startYear: startYear, crossesYear: crosses))
    }

    static func seasonSummary(_ rows: [SessionRow], label: String) -> Season {
        Season(label: label,
               sessions: rows.count,
               foilHours: rows.reduce(0) { $0 + foilSeconds($1) } / 3600,
               cleanJibes: rows.reduce(0) { $0 + ($1.jibesSuccessful ?? 0) })
    }

    // MARK: - Facts

    /// The three all-time personal bests the widget shows. **Rates are additive**
    /// (CLAUDE.md): JPH is here beside the speed and the flight, and it displaces nothing —
    /// CPH keeps its own row on the Records screen.
    static func bests(_ rows: [SessionRow], scope: FactScope,
                      jibesPerHour: [String: Double],
                      policy: SpeedRecordPolicy = .preferVerified,
                      titleForRow: (SessionRow) -> String) -> [Fact] {
        [FactKind.best2s, .longestFlight, .bestJph].compactMap {
            best(rows, kind: $0, scope: scope, jibesPerHour: jibesPerHour,
                 policy: policy, titleForRow: titleForRow)
        }
    }

    /// The rotation the weekly widget falls back to in a week with no session: the season's
    /// own bests while there is a season to speak of, the all-time ones before the first
    /// afternoon of a new one, and "on this day" whenever an earlier year has an answer.
    static func rotation(season: [SessionRow], all: [SessionRow], now: Date,
                         jibesPerHour: [String: Double],
                         policy: SpeedRecordPolicy = .preferVerified,
                         titleForRow: (SessionRow) -> String,
                         allTime: [Fact]) -> [Fact] {
        var facts: [Fact] = []
        if !season.isEmpty {
            facts = ([FactKind.best2s, .longestFlight, .bestJph, .longestDryStreak]).compactMap {
                best(season, kind: $0, scope: .season, jibesPerHour: jibesPerHour,
                     policy: policy, titleForRow: titleForRow)
            }
        } else {
            facts = allTime
        }
        if let then = onThisDay(all, now: now, titleForRow: titleForRow) { facts.append(then) }
        return facts
    }

    /// The best row for one kind, or nil when nobody has a positive value for it — absent
    /// rather than a dash, the rule `LibraryStore.sessionRecords` follows.
    ///
    /// The speed kind goes through `SpeedRecordRule` first, once, for the one kind it is
    /// about — the same call the records table makes per record kind. Every other kind
    /// takes the whole list: how many jibes an afternoon held is not a claim its speed
    /// channel makes (`SessionRecordKind`).
    static func best(_ rows: [SessionRow], kind: FactKind, scope: FactScope,
                     jibesPerHour: [String: Double],
                     policy: SpeedRecordPolicy = .preferVerified,
                     titleForRow: (SessionRow) -> String) -> Fact? {
        let rows = kind == .best2s
            ? SpeedRecordRule.eligible(rows, policy: policy) { $0.sourceClass != "c" }
            : rows
        var best: (Double, SessionRow)?
        for row in rows {
            guard let value = value(kind, in: row, jibesPerHour: jibesPerHour), value > 0
            else { continue }
            if best == nil || value > best!.0 { best = (value, row) }
        }
        guard let (value, row) = best else { return nil }
        return Fact(kind: kind, value: value, spot: titleForRow(row), date: row.startDate,
                    scope: scope)
    }

    static func value(_ kind: FactKind, in row: SessionRow,
                      jibesPerHour: [String: Double]) -> Double? {
        switch kind {
        // No certification filter here any more: which rows may hold the speed record is
        // the rider's setting, and `best(_:kind:…)` above asks `SpeedRecordRule` once for
        // the whole candidate list rather than row by row.
        case .best2s: row.best2sKn
        case .longestFlight: row.longestFlightS
        // The same floor "Best CPH" takes, for the same reason: a rate a rider can set by
        // going home early is not a personal best (`SessionRecordKind.cphMinDurationS`).
        case .bestJph:
            row.rateSeconds >= SessionRecordKind.cphMinDurationS ? jibesPerHour[row.id] : nil
        case .longestDryStreak: row.longestDryStreak.map(Double.init)
        case .onThisDay: nil
        }
    }

    /// **This week, in an earlier year.** The same ISO week — Monday-based, the week rule
    /// the Trends chart and `LibraryStore.isoCalendar` already share — one or more years
    /// back; the most recent such afternoon wins.
    ///
    /// A week rather than a day because a wingfoiler's calendar is weather, not dates:
    /// nothing at all happened on 14 September last year, and the Garda week either side of
    /// it is what the rider remembers.
    static func onThisDay(_ rows: [SessionRow], now: Date,
                          titleForRow: (SessionRow) -> String) -> Fact? {
        let calendar = LibraryStore.isoCalendar          // the reader's own week
        let today = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: now)
        guard let week = today.weekOfYear, let year = today.yearForWeekOfYear else { return nil }

        var best: (Int, SessionRow)?
        for row in rows {
            var rowCalendar = calendar
            rowCalendar.timeZone = row.displayZone       // the week the *rider* had
            let parts = rowCalendar.dateComponents([.weekOfYear, .yearForWeekOfYear],
                                                   from: row.startDate)
            guard parts.weekOfYear == week, let rowYear = parts.yearForWeekOfYear,
                  rowYear < year else { continue }
            if best == nil || row.startDate > best!.1.startDate { best = (rowYear, row) }
        }
        guard let (rowYear, row) = best else { return nil }
        return Fact(kind: .onThisDay, value: Double(row.flightCount ?? 0),
                    spot: titleForRow(row), date: row.startDate, scope: .allTime,
                    yearsAgo: year - rowYear, best2sKn: row.best2sKn,
                    flights: row.flightCount)
    }
}
