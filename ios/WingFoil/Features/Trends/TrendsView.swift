import Charts
import SwiftUI
import WingFoilKit

/// Time series over sessions (plan §3.3 "Trends: foil %, longest flight, turn success,
/// pumps-to-takeoff, port/starboard"). Everything is read from the denormalized `session`
/// columns, so a range switch is a query, not a re-analysis.
///
/// A metric a session cannot know — pumps without an accelerometer, clean jibes without
/// a wind axis — is **absent**, not zero: those sessions drop out of their chart and the
/// chart says how many are missing rather than plotting a flat, flattering line.
struct TrendsView: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var filter = LibraryFilter()
    @State private var range = TrendRange.season
    @State private var points: [TrendPoint] = []
    @State private var weeks: [WeekBucket] = []
    /// The season line's own buckets and sessions, whatever the range picker says: a streak
    /// cut off at four weeks is not the rider's streak.
    @State private var seasonWeeks: [WeekBucket] = []
    @State private var seasonPoints: [TrendPoint] = []
    /// Pumps and the port/starboard pair sit under **More**, folded or open per device
    /// (UX review fix 10, 27 Sep 2026): the favourites come first, the rest one tap away.
    @AppStorage("trendsShowMore") private var showMore = false
    /// `UI_OPEN_PERIODS=1` pushes Periods for a screenshot — `simctl` cannot tap the button.
    @State private var openPeriods = false
    /// The range on screen as a period, while its card composer is open.
    @State private var sharing: Period?

    enum TrendRange: String, CaseIterable, Identifiable {
        case fourWeeks = "4 w"
        case season = "Season"
        case all = "All"

        var id: String { rawValue }

        /// `season` runs 1 April → 31 March: one Northern-hemisphere water year, so a
        /// session in February still counts towards the winter it belongs to.
        func since(now: Date = Date()) -> Date? {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            switch self {
            case .fourWeeks:
                return calendar.date(byAdding: .weekOfYear, value: -4, to: now)
            case .season:
                let year = calendar.component(.year, from: now)
                let month = calendar.component(.month, from: now)
                return calendar.date(from: DateComponents(year: month >= 4 ? year : year - 1,
                                                          month: 4, day: 1))
            case .all:
                return nil
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Range", selection: $range) {
                        ForEach(TrendRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    LibraryFilterBar(filter: $filter)

                    #if TUNING
                    // Same rule as Records: a trend line drawn on tuned thresholds is not the
                    // trend line anyone else would draw, and the charts cannot say so
                    // themselves.
                    if !store.tuning.isEmpty {
                        TunedChip(count: store.tuning.totalChangedCount)
                    }
                    #endif

                    if points.isEmpty {
                        // **Two empty screens, not one** (15 Sep 2026). "Widen the range or
                        // clear the spot and gear filters" was advice that could not work
                        // on the library the one-tap first run leaves behind: the example
                        // is kept out of trends on purpose (`LibraryStore.clause`), and no
                        // range and no filter reaches it. `ExampleOnlyNote` says that in
                        // the rider's words; the filter sentence stays for the case where
                        // a filter really is set.
                        //
                        // The example-only line names two doors, and since 9 Oct 2026 the
                        // screen offers them (rider review I1, `ExampleOnlyDoors`).
                        ContentUnavailableView {
                            Label(store.hasOnlyExampleSessions
                                      ? ExampleOnlyNote.trendsTitle
                                      : AppShellCopy.Trends.nothingInRange,
                                  systemImage: "chart.xyaxis.line")
                        } description: {
                            Text(store.hasOnlyExampleSessions
                                     ? ExampleOnlyNote.trends
                                     : AppShellCopy.Trends.widenTheRange)
                        } actions: {
                            if store.hasOnlyExampleSessions { ExampleOnlyDoors() }
                        }
                        .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        summaryStrip
                        if let line = seasonLine {
                            Text(line)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        charts
                    }
                    FeedbackFooter()
                }
                .padding(.horizontal)
                .padding(.bottom, 28)
                // The charts are read as a stack of small multiples — one metric each, the
                // same x axis down the page. A 1 366 pt wide `Chart` with eleven sessions in
                // it is a row of dots with a metre of white between them, and the range
                // picker above becomes three words lost in a long bar.
                .readableColumn()
                #if DEBUG && targetEnvironment(simulator)
                // Same hook family as the session page's: `simctl` cannot scroll, so
                // `UI_SCROLL_TO=sideSuccess` parks the screen on the port/starboard
                // success chart, which is several charts below the fold.
                .onChange(of: points.isEmpty) {
                    guard !points.isEmpty,
                          let anchor = ProcessInfo.processInfo.environment["UI_SCROLL_TO"]
                    else { return }
                    // The entry-tack chart is folded under More; the hook opens it first.
                    if anchor == "sideSuccess" { showMore = true }
                    Task { @MainActor in proxy.scrollTo(anchor, anchor: .top) }
                }
                #endif
                }
            }
            .navigationTitle("Trends")
            // The app menu, in the slot it occupies on all four tab roots (pattern M).
            .appMenuHost()
            // Periods live one push from here rather than in a fifth tab: they are the same
            // question this screen asks — how is the season going — with the afternoons
            // grouped instead of drawn one by one, and a rider looking at a chart of the last
            // four weeks is exactly the rider who wants the week at Garda summed up.
            .toolbar {
                // **Share the range you are looking at** (Jan, 28 Sep 2026): the season, the
                // last four weeks or everything, as the period card Periods would make of it.
                // Beside the calendar, because it answers the same question with a picture.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { sharing = await rangePeriod() }
                    } label: {
                        Label(AppShellCopy.Trends.share, systemImage: "square.and.arrow.up")
                    }
                    .disabled(points.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        PeriodsView()
                            .task { Usage.record(.periods) }
                    } label: {
                        Label("Periods", systemImage: "calendar")
                    }
                }
            }
            #if DEBUG && targetEnvironment(simulator)
            .navigationDestination(isPresented: $openPeriods) { PeriodsView() }
            .task { openPeriods = ProcessInfo.processInfo.environment["UI_OPEN_PERIODS"] == "1" }
            #endif
            .sheet(item: $sharing) { period in PeriodShareView(period: period) }
            #if DEBUG && targetEnvironment(simulator)
            // `UI_SHARE_RANGE=1` opens the range's card composer for a screenshot.
            .onChange(of: points.isEmpty) {
                guard !points.isEmpty, sharing == nil,
                      ProcessInfo.processInfo.environment["UI_SHARE_RANGE"] == "1" else { return }
                Task { sharing = await rangePeriod() }
            }
            #endif
            .refreshable { await reload() }
            .task(id: reloadKey) { await reload() }
        }
    }

    /// The range on screen as a period, under the same spot and gear filter.
    ///
    /// **Season** is the season Periods lists — its title, its key, its block — so the card
    /// made here and the one made there are the same card. **4 w** and **All** are ranges of
    /// the rider's own (`periodBlock`), from four weeks ago or from the first session to today.
    private func rangePeriod() async -> Period? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date()
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        func key(_ c: DateComponents) -> String {
            String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }
        switch range {
        case .season:
            let season = String(PeriodRules.seasonYear(year: today.year ?? 0,
                                                       month: today.month ?? 0))
            if let found = try? await store.library.periods(filter).seasons
                .first(where: { $0.key == season }) {
                return found
            }
            fallthrough
        case .fourWeeks:
            let since = range.since(now: now).map {
                key(calendar.dateComponents([.year, .month, .day], from: $0))
            }
            return try? await store.library.periodBlock(filter, from: since, to: key(today))
        case .all:
            return try? await store.library.periodBlock(filter, from: nil, to: nil)
        }
    }

    private var reloadKey: String {
        "\(range.rawValue)|\(filter.spotId ?? "-")|\(filter.gearId ?? "-")|\(store.libraryGeneration)|\(store.speedRecordPolicy.rawValue)"
    }

    private func reload() async {
        var scoped = filter
        scoped.since = range.since()
        points = (try? await store.library.trend(scoped, policy: store.speedRecordPolicy)) ?? []
        weeks = (try? await store.library.weeks(scoped)) ?? []
        var season = filter
        season.since = TrendRange.season.since()
        if range == .season {
            seasonWeeks = weeks
            seasonPoints = points
        } else {
            seasonWeeks = (try? await store.library.weeks(season)) ?? []
            seasonPoints = (try? await store.library.trend(season,
                                                           policy: store.speedRecordPolicy)) ?? []
        }
    }

    /// Weeks in a row and this month's clean jibes (`SeasonLine`): over the season on every
    /// range but All, and over every week on All, where the best run is the all-time one
    /// (Jan, 28 Sep 2026). `weeks` on All is already every week since the first session.
    private var seasonLine: String? {
        let calendar = Calendar.current
        let month = calendar.dateInterval(of: .month, for: Date())
        let thisMonth = seasonPoints.filter { month?.contains($0.date) ?? false }
        let counted = thisMonth.compactMap(\.cleanJibes)
        let allTime = range == .all
        return SeasonLine.text(weekCounts: (allTime ? weeks : seasonWeeks).map(\.count),
                               cleanJibesThisMonth: counted.isEmpty ? nil
                                   : counted.reduce(0, +),
                               scope: allTime ? .allTime : .season)
    }

    // MARK: - Headline numbers

    private var summaryStrip: some View {
        let hours = points.reduce(0) { $0 + $1.durationS } / 3600
        let distance = points.reduce(0.0) { $0 + ($1.distanceKm ?? 0) }
        let flights = points.reduce(0) { $0 + ($1.flightCount ?? 0) }
        // Four abreast, or two by two once a quarter of the phone no longer holds a word:
        // at AX3 "sessions" and "distance" hyphenated (release round C). The key-metrics
        // block makes the same move at the same threshold.
        let columns = typeSize.isAccessibilitySize ? 2 : 4
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0,
                                                            alignment: .top),
                                        count: columns),
                         spacing: 12) {
            stat("\(points.count)", "sessions")
            stat(String(format: "%.0f h", hours), "on the water")
            stat(String(format: "%.0f km", distance), "distance")
            stat("\(flights)", "flights")
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.10), in: .rect(cornerRadius: 12))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.readableSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Charts

    @ViewBuilder
    private var charts: some View {
        // Every tone here is a token, and each one is the vocabulary its metric belongs to
        // (docs/presentation/layers-map-colour-type.md "Colour and glyph vocabulary"): foil time and longest
        // flight are both *flight* facts and therefore the phase teal — longest flight
        // wore the takeoff blue until app-ui-review.md §5.4 — jibes-flown-through is a
        // verdict and may have the ladder's green, and the port share is a side, so it
        // takes the side ink rather than the unowned magenta of §5.3.
        // "On foil" is the *share*; "Foil time" is a duration and belongs to the number of
        // seconds (docs/presentation/labels.md, "Label table"). The web chart has always been
        // titled this; the two now plot one metric under one name.
        // **The rider's favourites first** (UX review fix 10, 27 Sep 2026): on foil, clean
        // jibes, best 2 s, longest flight. Then the flew-through rate and the three rates,
        // then the weeks. Pumps and the two port/starboard charts fold under **More**.
        // Every chart carries a one-line headline out of `TrendHeadline`: this month against
        // the one before, and "your best month yet" when it is.
        TrendChart(title: AppShellCopy.Trends.onFoil, unit: "%", points: points,
                   tone: DesignTokens.Phase.flying,
                   value: \.foilPct, domain: 0...100, headline: TrendHeadline.onFoil)
        // Clean jibes and the rates are **counts of maneuvers**, not ladder verdicts, so they
        // deliberately do not wear `Outcome.flew`: on a page where the green line already
        // means "flew through", a second green line would read as a second flew-through
        // series (the same misread app-ui-review.md §5.2 caught on the entry-tack chart).
        // A metric with no vocabulary of its own takes the app's own ink — which is what
        // the analyzer's `role: "primary"` means, and what the week chart below already does.
        TrendChart(title: AppShellCopy.Trends.cleanJibes, unit: "per session", points: points,
                   tone: Color.accentColor,
                   value: { $0.cleanJibes.map(Double.init) },
                   note: AppShellCopy.Trends.cleanJibesNote,
                   headline: TrendHeadline.cleanJibes)
        // The one speed line on the page, in the rider's unit like every other speed in
        // both apps (Settings → Units). The series itself is converted, not just the
        // caption: an axis counted in knots under a `km/h` label is the defect the setting
        // exists to remove.
        // The caption names the sessions whose speed came from positions rather than from a
        // speed channel: the point is drawn, because it is still his afternoon, and it is
        // said to be unverifiable, because that is where a high reading does the most damage
        // (the analyzer draws the same point as an open ring).
        // Settings → Speed records decides which of those points may be plotted at all
        // (`SpeedRecordRule`, the same call the Records table makes per record kind — and
        // best 2 s is one kind, so this is one call over the whole series). A point the
        // rule drops out reads as "this session cannot report this", which is the honest
        // sentence: the recording did not measure a speed.
        let speedPoints = plottableSpeedIDs
        TrendChart(title: AppShellCopy.Trends.best2s, unit: Fmt.knUnit, points: points,
                   tone: DesignTokens.Phase.flying,
                   value: { point in
                       guard speedPoints.contains(point.sessionId) else { return nil }
                       return point.best2sKn.map { Speed.value($0) }
                   },
                   uncertified: { !$0.certified },
                   note: AppShellCopy.Trends.best2sNote,
                   headline: TrendHeadline.best2s(unit: Fmt.knUnit))
            // The second screenshot anchor on this page, and the reason is the unit: this
            // is the only chart here that moves when a rider picks km/h, and it sits below
            // the fold where `simctl` cannot reach it (docs/testing.md, "A screenshot in
            // km/h").
            .id("best2s")
        // Foil time and longest flight are both *flight* facts and therefore the phase teal
        // (docs/presentation/layers-map-colour-type.md "Colour and glyph vocabulary").
        TrendChart(title: AppShellCopy.Trends.longestFlight, unit: "min", points: points,
                   tone: DesignTokens.Phase.flying,
                   value: { $0.longestFlightS.map { $0 / 60 } },
                   headline: TrendHeadline.longestFlight)
        // **"Flew-through rate", over every counted turn** — the same metric and the same
        // title the analyzer's chart carries. The stricter reading is "Clean jibes" above.
        TrendChart(title: AppShellCopy.Trends.flewThrough, unit: "%", points: points,
                   tone: DesignTokens.Outcome.flew,
                   value: \.flewThroughPct, domain: 0...100,
                   note: AppShellCopy.Trends.flewThroughNote,
                   headline: TrendHeadline.flewThrough)
        // **Rates are additive**, and the titles spell the codes out (pattern H): a rider
        // who has not met "CPH" reads what it counts, and the code stays beside it for the
        // one who has. The analyzer's charts still carry the bare codes until the web round.
        TrendChart(title: AppShellCopy.Trends.cph, unit: "clean jibes / h",
                   points: points, tone: Color.accentColor,
                   value: \.cleanJibesPerHour,
                   headline: TrendHeadline.cleanJibesPerHour)
        // **CPH, then ONE dry-turn rate** (rider review I20, 9 Oct 2026): JPH while no
        // session in the range has a tack, TPH once one does — the session page's rule over
        // a range. On a jibes-only library the two were one line drawn twice. Every rate
        // point skips a session under 20 minutes on the timer (`RateFloor`).
        switch TrendPoint.dryTurnRate(points) {
        case .jph:
            TrendChart(title: AppShellCopy.Trends.jph, unit: "jibes / h", points: points,
                       tone: Color.accentColor,
                       value: \.jibesPerHour,
                       note: AppShellCopy.Trends.jphNote,
                       headline: TrendHeadline.jibesPerHour)
        case .tph:
            TrendChart(title: AppShellCopy.Trends.tph, unit: "turns / h", points: points,
                       tone: Color.accentColor,
                       value: \.turnsPerHour,
                       note: AppShellCopy.Trends.tphNote,
                       headline: TrendHeadline.turnsPerHour)
        }
        weeklyChart
        DisclosureGroup(isExpanded: $showMore) {
            VStack(alignment: .leading, spacing: 18) {
                TrendChart(title: AppShellCopy.Trends.pumps, unit: "pumps", points: points,
                           tone: DesignTokens.Effort.window,
                           value: \.avgPumpsToTakeoff,
                           note: AppShellCopy.Trends.pumpsNote,
                           headline: TrendHeadline.pumpsToTakeoff)
                // The port share is a side, so it takes the side ink.
                TrendChart(title: AppShellCopy.Trends.portShare, unit: "% port", points: points,
                           tone: DesignTokens.Side.port,
                           value: \.portSharePct, domain: 0...100, reference: 50,
                           note: AppShellCopy.Trends.portShareNote,
                           headline: TrendHeadline.portShare)
                sideSuccessChart
            }
            .padding(.top, 12)
        } label: {
            Text("More").font(.subheadline.weight(.semibold))
        }
    }

    /// **Which sessions may hold a point on the one speed series** — the rider's Speed
    /// records setting, asked once for the one record kind this chart draws.
    ///
    /// Ids rather than filtered points, because `TrendChart` is handed the whole run: the
    /// caption under every chart counts "N of M sessions cannot report this", and a series
    /// silently shortened would make that sentence about the wrong M.
    private var plottableSpeedIDs: Set<String> {
        let candidates = points.filter { $0.best2sKn != nil }
        let eligible = SpeedRecordRule.eligible(candidates,
                                                policy: store.speedRecordPolicy) {
            $0.certified
        }
        return Set(eligible.map(\.sessionId))
    }

    /// The flew-through share split by the tack he *entered* on — the "am I one-sided?"
    /// chart that the share chart above can only hint at.
    ///
    /// **It is the outcome, per entry tack** — the two lines are the ladder's green over
    /// the entries on each side. It is not the clean-jibe rate: clean also demands the
    /// score, and it is a jibe word, where this counts every turn entered on a tack. The
    /// analyzer draws the same metric under the same title (`library._side_pct`, digest
    /// schema 8), which it did not before: it plotted the score verdict per side and
    /// called it "Clean jibes by entry tack".
    ///
    /// Two series rather than one difference line: a rider whose port jibes are at 40 %
    /// and starboard at 20 % and one at 80/60 have the same gap and completely different
    /// seasons, and the pair shows both at once. A session that never entered a turn on
    /// one tack contributes no point on that side — absent, not 0 %, the same rule the
    /// rest of this screen follows.
    ///
    /// **The two inks are `side.port` / `side.starboard` and nothing else.** This chart
    /// drew port in the takeoff blue and starboard in the ladder's *green* until
    /// app-ui-review.md §5.2 — on a chart whose subject is "% flew through", a green line
    /// reads as the flew-through line, which is exactly the misread the ladder's
    /// verdicts-only rule exists to prevent. The pair is symmetric, so its encoding is:
    /// one hue at two intensities, and starboard dashed as well, so the split survives a
    /// colour-vision check with no second hue.
    private var sideSuccessChart: some View {
        let series: [(side: String, tone: Color, values: [(date: Date, value: Double)])] = [
            ("Port entry", DesignTokens.Side.port,
             points.compactMap { p in p.portFlewThroughPct.map { (p.date, $0) } }),
            ("Starboard entry", DesignTokens.Side.starboard,
             points.compactMap { p in p.starboardFlewThroughPct.map { (p.date, $0) } }),
        ]
        let total = series.reduce(0) { $0 + $1.values.count }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(AppShellCopy.Trends.bySide).font(.subheadline.weight(.semibold))
                Spacer()
                Text("% flew through").font(.caption).foregroundStyle(.readableSecondary)
            }
            if total == 0 {
                Text(AppShellCopy.Trends.bySideEmpty)
                    .font(.caption)
                    .foregroundStyle(.readableSecondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            } else {
                Chart {
                    ForEach(series, id: \.side) { line in
                        ForEach(line.values, id: \.date) { item in
                            LineMark(x: .value("Date", item.date),
                                     y: .value("Flew through", item.value),
                                     series: .value("Entry tack", line.side))
                                .foregroundStyle(by: .value("Entry tack", line.side))
                                .lineStyle(StrokeStyle(lineWidth: 1.8,
                                                       dash: line.side == "Port entry"
                                                           ? [] : [5, 3]))
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Date", item.date),
                                      y: .value("Flew through", item.value))
                                .symbolSize(18)
                                .foregroundStyle(by: .value("Entry tack", line.side))
                        }
                    }
                }
                .chartForegroundStyleScale(["Port entry": DesignTokens.Side.port,
                                            "Starboard entry": DesignTokens.Side.starboard])
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(position: .leading) }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 150)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(series.map { line in
                    SpokenFigures.series(title: line.side + ", flew through",
                                         values: line.values.map(\.value),
                                         format: { String(format: "%.0f %%", $0) })
                }.joined(separator: ". "))
                Text(AppShellCopy.Trends.bySideNote)
                    .font(.caption2)
                    .foregroundStyle(.readableSecondary)
            }
        }
        .id("sideSuccess")
    }

    /// Sessions per week — the one chart here whose x axis is *time* rather than a list of
    /// events, because the whole point of it is the gaps between them.
    ///
    /// **The chart is handed the same calendar the buckets were cut with.** `LibraryStore`
    /// puts each session in an ISO-8601 week starting on Monday; `BarMark(…, unit:
    /// .weekOfYear)` then bins those Mondays again, and it does so under the *environment's*
    /// calendar — which on a Sunday-first locale opens its weeks a day earlier and drew
    /// every bar under the Sunday before the week it belongs to. Two calendars for one
    /// question is one calendar too many, so the environment gets the ISO one and the bar
    /// lands on the Monday the bucket is named after.
    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppShellCopy.Trends.perWeek).font(.subheadline.weight(.semibold))
            Chart(weeks) { week in
                BarMark(x: .value("Week", week.weekStart, unit: .weekOfYear),
                        y: .value("Sessions", week.count))
                    .foregroundStyle(Color.accentColor.opacity(week.count == 0 ? 0.15 : 0.85))
            }
            .environment(\.calendar, LibraryStore.isoCalendar)
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 140)
            // The caption under it already says how many weeks had a session; the chart
            // adds the busiest one.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sessions per week, busiest week "
                                + SpokenFigures.count(weeks.map(\.count).max() ?? 0,
                                                      "session", "sessions"))
            // Concise: the count. Extensive adds how a week is cut (Settings → How much
            // to say); the calendar rule itself is docs/presentation/trends-periods.md.
            ExplainedFootnote(line: AppShellCopy.fill(
                                  AppShellCopy.Trends.weeksOnTheWater,
                                  ["ridden": String(weeks.filter { $0.count > 0 }.count),
                                   "weeks": String(weeks.count)]),
                              topic: nil,
                              more: [AppShellCopy.Trends.weekRuns])
            { _ in }
                .font(.caption2)
                .foregroundStyle(.readableSecondary)
        }
        .padding(.top, 4)
    }
}

/// One metric over time: a line through the sessions that *have* the metric, points for
/// each session, and an honest note when some sessions cannot supply it.
private struct TrendChart: View {
    let title: String
    let unit: String
    let points: [TrendPoint]
    let tone: Color
    let value: (TrendPoint) -> Double?
    var domain: ClosedRange<Double>?
    var reference: Double?
    var note: String?
    /// Only a **speed** series sets this. A class-(c) recording differentiated its speed
    /// from positions, which reads high, so the chart says how many of its points came from
    /// one — the same claim, in the same word, the Records table makes about an all-time
    /// best. The points are still drawn: they are still his afternoons.
    var uncertified: ((TrendPoint) -> Bool)?
    /// How the one-line verdict above the chart sums up a month (`TrendHeadline`).
    var headline: TrendHeadline.Spec?

    init(title: String, unit: String, points: [TrendPoint], tone: Color,
         value: @escaping (TrendPoint) -> Double?, domain: ClosedRange<Double>? = nil,
         reference: Double? = nil, uncertified: ((TrendPoint) -> Bool)? = nil,
         note: String? = nil, headline: TrendHeadline.Spec? = nil) {
        self.title = title
        self.unit = unit
        self.points = points
        self.tone = tone
        self.value = value
        self.domain = domain
        self.reference = reference
        self.uncertified = uncertified
        self.note = note
        self.headline = headline
    }

    /// This month against the one before, from the points the chart draws. Hours are the
    /// session's own clock, so a rate sums up as the month's totals over its hours.
    private var headlineText: String? {
        guard let headline else { return nil }
        let samples = points.compactMap { point in
            value(point).map { TrendHeadline.Sample(date: point.date, value: $0,
                                                     hours: point.durationS / 3600) }
        }
        return TrendHeadline.line(samples, spec: headline)
    }

    private var series: [(date: Date, value: Double)] {
        points.compactMap { point in value(point).map { (point.date, $0) } }
    }

    /// How many of the points actually drawn carry a value no recording could certify.
    private var uncertifiedCount: Int {
        guard let uncertified else { return 0 }
        return points.filter { value($0) != nil && uncertified($0) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                if let last = series.last {
                    Text(format(last.value) + " \(unit)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.readableSecondary)
                }
            }
            if let headlineText {
                Text(headlineText)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if series.isEmpty {
                Text(note ?? "No session in this range can report this yet.")
                    .font(.caption)
                    .foregroundStyle(.readableSecondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            } else {
                chart
                if series.count < points.count {
                    let missing = String(points.count - series.count) + " of "
                        + String(points.count) + " sessions cannot report this"
                    let tail = note.map { " · " + $0 } ?? ""
                    Text(missing + tail)
                        .font(.caption2)
                        .foregroundStyle(.readableSecondary)
                } else if let note {
                    Text(note).font(.caption2).foregroundStyle(.readableSecondary)
                }
                if uncertifiedCount > 0 {
                    Text(String(uncertifiedCount) + " of " + String(series.count)
                         + " had no speed channel. That speed came from positions and "
                         + "reads high, so it is marked estimated.")
                        .font(.caption2)
                        .foregroundStyle(.readableSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        if let domain {
            baseChart.chartYScale(domain: domain)
        } else {
            baseChart
        }
    }

    private var baseChart: some View {
        Chart {
            if let reference {
                RuleMark(y: .value("Reference", reference))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            ForEach(series, id: \.date) { item in
                LineMark(x: .value("Date", item.date), y: .value(title, item.value))
                    .foregroundStyle(tone)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", item.date), y: .value(title, item.value))
                    .symbolSize(18)
                    .foregroundStyle(tone)
            }
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 140)
        // One sentence, not sixty dates read mark by mark (release round C).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SpokenFigures.series(title: title, values: series.map(\.value),
                                                 format: { format($0) + " " + unit }))
    }

    private func format(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}
