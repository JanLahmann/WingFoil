import Charts
import SwiftUI
import WingFoilKit

/// Time series over sessions (plan §3.3 "Trends: foil %, longest flight, turn success,
/// pumps-to-takeoff, port/starboard"). Everything is read from the denormalized `session`
/// columns, so a range switch is a query, not a re-analysis.
///
/// A metric a session cannot know — pumps without an accelerometer, jibe success without
/// a wind axis — is **absent**, not zero: those sessions drop out of their chart and the
/// chart says how many are missing rather than plotting a flat, flattering line.
struct TrendsView: View {
    @Environment(SessionStore.self) private var store

    @State private var filter = LibraryFilter()
    @State private var range = TrendRange.season
    @State private var points: [TrendPoint] = []
    @State private var weeks: [WeekBucket] = []

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

                    if points.isEmpty {
                        ContentUnavailableView("Nothing in this range",
                                               systemImage: "chart.xyaxis.line",
                                               description: Text("Widen the range or clear the "
                                                                 + "spot and gear filters."))
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        summaryStrip
                        charts
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 28)
                #if DEBUG && targetEnvironment(simulator)
                // Same hook family as the session page's: `simctl` cannot scroll, so
                // `UI_SCROLL_TO=sideSuccess` parks the screen on the port/starboard
                // success chart, which is several charts below the fold.
                .onChange(of: points.isEmpty) {
                    guard !points.isEmpty,
                          let anchor = ProcessInfo.processInfo.environment["UI_SCROLL_TO"]
                    else { return }
                    proxy.scrollTo(anchor, anchor: .top)
                }
                #endif
                }
            }
            .navigationTitle("Trends")
            .refreshable { await reload() }
            .task(id: reloadKey) { await reload() }
        }
    }

    private var reloadKey: String {
        "\(range.rawValue)|\(filter.spotId ?? "-")|\(filter.gearId ?? "-")|\(store.libraryGeneration)"
    }

    private func reload() async {
        var scoped = filter
        scoped.since = range.since()
        points = (try? await store.library.trend(scoped)) ?? []
        weeks = (try? await store.library.weeks(scoped)) ?? []
    }

    // MARK: - Headline numbers

    private var summaryStrip: some View {
        let hours = points.reduce(0) { $0 + $1.durationS } / 3600
        let distance = points.reduce(0.0) { $0 + ($1.distanceKm ?? 0) }
        let flights = points.reduce(0) { $0 + ($1.flightCount ?? 0) }
        return HStack(spacing: 0) {
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
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Charts

    @ViewBuilder
    private var charts: some View {
        TrendChart(title: "Foil time", unit: "%", points: points, tone: .teal,
                   value: \.foilPct, domain: 0...100)
        TrendChart(title: "Longest flight", unit: "min", points: points, tone: .blue,
                   value: { $0.longestFlightS.map { $0 / 60 } })
        TrendChart(title: "Jibes flown through", unit: "%", points: points, tone: .green,
                   value: \.jibeFlewThroughPct, domain: 0...100,
                   note: "Share of jibes that never touched down.")
        TrendChart(title: "Pumps to takeoff", unit: "strokes", points: points, tone: .orange,
                   value: \.avgPumpsToTakeoff,
                   note: "Needs the wrist accelerometer — only our own CIQ recordings "
                       + "carry it.")
        TrendChart(title: "Port / starboard", unit: "% port", points: points, tone: .purple,
                   value: \.portSharePct, domain: 0...100, reference: 50,
                   note: "50 % is symmetric; the gap is the side you avoid.")
        sideSuccessChart
        weeklyChart
    }

    /// Turn success split by the tack he *entered* on — the "am I one-sided?" chart that
    /// the share chart above can only hint at.
    ///
    /// Two series rather than one difference line: a rider whose port jibes are at 40 %
    /// and starboard at 20 % and one at 80/60 have the same gap and completely different
    /// seasons, and the pair shows both at once. A session that never entered a turn on
    /// one tack contributes no point on that side — absent, not 0 %, the same rule the
    /// rest of this screen follows.
    private var sideSuccessChart: some View {
        let series: [(side: String, tone: Color, values: [(date: Date, value: Double)])] = [
            ("Port entry", .blue,
             points.compactMap { p in p.portFlewThroughPct.map { (p.date, $0) } }),
            ("Starboard entry", .green,
             points.compactMap { p in p.starboardFlewThroughPct.map { (p.date, $0) } }),
        ]
        let total = series.reduce(0) { $0 + $1.values.count }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Turn success by entry tack").font(.subheadline.weight(.semibold))
                Spacer()
                Text("% flew through").font(.caption).foregroundStyle(.secondary)
            }
            if total == 0 {
                Text("No session in this range has turns with a usable entry tack — that "
                     + "needs a wind axis the engine trusts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            } else {
                Chart {
                    ForEach(series, id: \.side) { line in
                        ForEach(line.values, id: \.date) { item in
                            LineMark(x: .value("Date", item.date),
                                     y: .value("Flew through", item.value),
                                     series: .value("Entry tack", line.side))
                                .foregroundStyle(by: .value("Entry tack", line.side))
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Date", item.date),
                                      y: .value("Flew through", item.value))
                                .symbolSize(18)
                                .foregroundStyle(by: .value("Entry tack", line.side))
                        }
                    }
                }
                .chartForegroundStyleScale(["Port entry": Color.blue,
                                            "Starboard entry": Color.green])
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(position: .leading) }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 150)
                Text("Entry tack is the tack you came into the turn on, not the rotation "
                     + "direction. Course changes are excluded.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .id("sideSuccess")
    }

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sessions per week").font(.subheadline.weight(.semibold))
            Chart(weeks) { week in
                BarMark(x: .value("Week", week.weekStart, unit: .weekOfYear),
                        y: .value("Sessions", week.count))
                    .foregroundStyle(Color.accentColor.opacity(week.count == 0 ? 0.15 : 0.85))
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 140)
            Text("\(weeks.filter { $0.count > 0 }.count) of \(weeks.count) weeks on the water")
                .font(.caption2)
                .foregroundStyle(.secondary)
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

    init(title: String, unit: String, points: [TrendPoint], tone: Color,
         value: @escaping (TrendPoint) -> Double?, domain: ClosedRange<Double>? = nil,
         reference: Double? = nil, note: String? = nil) {
        self.title = title
        self.unit = unit
        self.points = points
        self.tone = tone
        self.value = value
        self.domain = domain
        self.reference = reference
        self.note = note
    }

    private var series: [(date: Date, value: Double)] {
        points.compactMap { point in value(point).map { (point.date, $0) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                if let last = series.last {
                    Text(format(last.value) + " \(unit)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if series.isEmpty {
                Text(note ?? "No session in this range reports \(title.lowercased()).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            } else {
                chart
                if series.count < points.count {
                    Text("\(points.count - series.count) of \(points.count) sessions cannot "
                         + "report this" + (note.map { " · \($0)" } ?? ""))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let note {
                    Text(note).font(.caption2).foregroundStyle(.secondary)
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
    }

    private func format(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}
