import SwiftUI
import WidgetKit

/// The home-screen widgets: the last session ridden, the week (or what has happened since
/// it, when the week is empty), and the all-time personal bests.
///
/// The extension deliberately does **not** link `WingFoilKit` — it compiles one shared
/// source file (`WidgetSnapshot.swift`) and reads a JSON blob the app publishes. A widget
/// that had to open the library database would need the app group *and* SQLite in a
/// 30 MB-memory-limited process, to draw four numbers. Everything that needs a library row
/// — which session was ridden, the track behind the numbers, the season, the facts — is
/// decided in the app and arrives here already answered.
@main
struct WingFoilWidgetBundle: WidgetBundle {
    var body: some Widget {
        LastSessionWidget()
        WeeklyFoilWidget()
        PersonalBestsWidget()
    }
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    /// True when the app cannot reach the shared container, so the widget can say *why*
    /// it is empty instead of pretending the rider has never been on the water.
    let unreachable: Bool
}

/// Reads the published snapshot. Shared by both providers below.
enum SnapshotSource {

    static func entry(at date: Date = Date()) -> SnapshotEntry {
        if let snapshot = WidgetSnapshotStore.read() {
            return SnapshotEntry(date: date, snapshot: snapshot, unreachable: false)
        }
        return SnapshotEntry(date: date, snapshot: nil,
                             unreachable: !WidgetSnapshotStore.appGroupAvailable)
    }
}

struct SnapshotProvider: TimelineProvider {

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .preview, unreachable: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotSource.entry())
    }

    /// One entry, refreshed hourly. The library only changes when the rider imports, and
    /// the app reloads the timelines itself when that happens — the hourly policy is just
    /// a floor so "3 days ago" does not go stale on a phone that never opens the app.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let next = Date().addingTimeInterval(3600)
        completion(Timeline(entries: [SnapshotSource.entry()], policy: .after(next)))
    }
}

/// **One entry per day**, for the two things that change with the day rather than with the
/// library: the count of days since the last session, and which fact of the rotation is
/// today's. The snapshot is read once and drawn seven times at seven different dates —
/// nothing is recomputed by the app in between, and the widget needs no refresh budget to
/// turn "11 days" into "12 days" at midnight.
struct DailySnapshotProvider: TimelineProvider {

    /// A week of entries. Long enough that a phone which never gets a refresh window still
    /// counts correctly for days; short enough that a session imported meanwhile (which
    /// reloads the timeline anyway) is never more than a week of stale entries behind.
    static let days = 7

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .preview, unreachable: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotSource.entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let base = SnapshotSource.entry(at: now)
        var entries = [base]
        let calendar = Calendar.current
        var cursor = calendar.startOfDay(for: now)
        for _ in 0..<Self.days {
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            entries.append(SnapshotEntry(date: cursor, snapshot: base.snapshot,
                                         unreachable: base.unreachable))
        }
        completion(Timeline(entries: entries, policy: .after(cursor)))
    }
}

// MARK: - Widgets

struct LastSessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "de.lahmann.wingfoil.widget.lastSession",
                            provider: SnapshotProvider()) { entry in
            LastSessionView(entry: entry)
                .containerBackground(WidgetPalette.background, for: .widget)
        }
        .configurationDisplayName("Last session")
        .description("The last afternoon you rode: where it was, the foil share, "
                     + "the best 2 s and how the turns went.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct WeeklyFoilWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "de.lahmann.wingfoil.widget.weekly",
                            provider: DailySnapshotProvider()) { entry in
            WeeklyFoilView(entry: entry)
                .containerBackground(WidgetPalette.background, for: .widget)
        }
        .configurationDisplayName("This week")
        .description("Time actually spent on the foil over the last seven days — and, in a "
                     + "week off the water, the season so far and one thing you did.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PersonalBestsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "de.lahmann.wingfoil.widget.bests",
                            provider: SnapshotProvider()) { entry in
            PersonalBestsView(entry: entry)
                .containerBackground(WidgetPalette.background, for: .widget)
        }
        .configurationDisplayName("Personal bests")
        .description("Best 2 s, longest flight and best JPH, with where and when.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Last session

struct LastSessionView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let session = entry.snapshot?.lastSession {
            ZStack {
                if let track = session.track, !track.isEmpty, trackOpacity > 0 {
                    TrackOutline(track: track)
                        .stroke(WidgetPalette.green.opacity(trackOpacity),
                                style: StrokeStyle(lineWidth: family == .systemSmall ? 1 : 1.4,
                                                   lineCap: .round, lineJoin: .round))
                        .padding(.vertical, family == .systemLarge ? 24 : 8)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    header(session)
                    Spacer(minLength: 0)
                    if family == .systemSmall {
                        WidgetStat(label: "FOIL", value: WidgetFormat.pct(session.foilPct),
                                   big: true)
                        WidgetStat(label: "BEST 2 S", value: WidgetFormat.knots(session.best2sKn))
                    } else {
                        HStack(spacing: 10) {
                            WidgetStat(label: "FOIL", value: WidgetFormat.pct(session.foilPct),
                                       big: true)
                            WidgetStat(label: "BEST 2 S",
                                       value: WidgetFormat.knots(session.best2sKn), big: true)
                            WidgetStat(label: "FLIGHTS",
                                       value: session.flightCount.map(String.init) ?? "—",
                                       big: true)
                        }
                    }
                    if session.hasTurnTally { tally(session) }
                }
            }
        } else {
            EmptyStateView(unreachable: entry.unreachable)
        }
    }

    /// The breadcrumb sits *behind* the numbers, so it is drawn at the weight a background
    /// gets: legible as the shape of an afternoon on the two families with room for it,
    /// and a hint on the small one, where the numbers own every pixel.
    private var trackOpacity: Double {
        switch family {
        case .systemSmall: 0.16
        case .systemLarge: 0.45
        default: 0.38
        }
    }

    private func header(_ session: WidgetSnapshot.LastSession) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(session.title)
                .font(.system(size: family == .systemLarge ? 17 : 13, weight: .bold,
                              design: .rounded))
                .foregroundStyle(WidgetPalette.paper)
                .lineLimit(1)
            Text(WidgetFormat.shortDate(session.date, relativeTo: entry.date))
                .font(.system(size: 10))
                .foregroundStyle(WidgetPalette.paper.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tally(_ session: WidgetSnapshot.LastSession) -> some View {
        HStack(spacing: 3) {
            Text("\(session.flewThrough)").foregroundStyle(.green)
            Text("·").foregroundStyle(WidgetPalette.paper.opacity(0.4))
            Text("\(session.touchdown)").foregroundStyle(.orange)
            Text("·").foregroundStyle(WidgetPalette.paper.opacity(0.4))
            Text("\(session.fellIn)").foregroundStyle(.red)
            Text("turns")
                .font(.system(size: 9))
                .foregroundStyle(WidgetPalette.paper.opacity(0.55))
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .accessibilityLabel("\(session.flewThrough) flew through, \(session.touchdown) "
                            + "touchdowns, \(session.fellIn) falls")
    }
}

// MARK: - This week / since your last session

struct WeeklyFoilView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.isEmpty {
            if snapshot.hasRiddenWeek(endingOn: entry.date) {
                week(snapshot)
            } else {
                sinceLastSession(snapshot)
            }
        } else {
            EmptyStateView(unreachable: entry.unreachable)
        }
    }

    // MARK: the week that happened

    private func week(_ snapshot: WidgetSnapshot) -> some View {
        // Re-added for the day this entry is *drawn* on where the snapshot carries the
        // days; the stored window is the fallback for a blob written by an older build.
        let totals = snapshot.week(endingOn: entry.date)
            ?? (sessions: snapshot.weeklySessions, foilMinutes: snapshot.weeklyFoilMinutes,
                hours: snapshot.weeklyHours)
        return VStack(alignment: .leading, spacing: 4) {
            sectionLabel("THIS WEEK")
            Spacer(minLength: 0)
            Text(WidgetFormat.foilTime(totals.foilMinutes))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetPalette.paper)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("on the foil")
                .font(.system(size: 11))
                .foregroundStyle(WidgetPalette.paper.opacity(0.65))
            Spacer(minLength: 0)
            Text("\(totals.sessions) session" + (totals.sessions == 1 ? "" : "s")
                 + " · " + WidgetFormat.hours(totals.hours) + " out")
                .font(.system(size: 10))
                .foregroundStyle(WidgetPalette.paper.opacity(0.55))
                .lineLimit(1)
        }
    }

    // MARK: the week that did not

    private func sinceLastSession(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("SINCE YOUR LAST SESSION")
            if let days = snapshot.daysSinceLastSession(on: entry.date) {
                Text(WidgetFormat.days(days))
                    .font(.system(size: family == .systemSmall ? 26 : 30,
                                  weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetPalette.paper)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            // Where it was, on the two families with a line to spare: the small one has
            // 130 pt of height and four things to say, and the fact below names a place of
            // its own.
            if let last = snapshot.lastSession, family != .systemSmall {
                Text(last.title + " · " + WidgetFormat.shortDate(last.date,
                                                                 relativeTo: entry.date))
                    .font(.system(size: 10))
                    .foregroundStyle(WidgetPalette.paper.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let season = snapshot.season, season.sessions > 0 {
                seasonLine(season)
            }
            if let fact = snapshot.fact(on: entry.date),
               let copy = FactCopy(fact, today: entry.date) {
                Divider().overlay(WidgetPalette.paper.opacity(0.15))
                FactView(copy: copy, compact: family == .systemSmall)
            }
        }
    }

    private func seasonLine(_ season: WidgetSnapshot.Season) -> some View {
        // Built as a string first: a SwiftUI body full of `+` and `?:` is exactly the shape
        // the type checker gives up on, and it gives up as a build failure.
        var parts: [String] = []
        parts.append("\(season.sessions) session" + (season.sessions == 1 ? "" : "s"))
        parts.append(WidgetFormat.hours(season.foilHours) + " on the foil")
        if family != .systemSmall {
            parts.append("\(season.cleanJibes) clean jibe"
                         + (season.cleanJibes == 1 ? "" : "s"))
        }
        return VStack(alignment: .leading, spacing: 0) {
            Text("SEASON \(season.label)")
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(WidgetPalette.green)
            Text(parts.joined(separator: " · "))
                .font(.system(size: 10))
                .foregroundStyle(WidgetPalette.paper.opacity(0.75))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(WidgetPalette.green)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

// MARK: - Personal bests

struct PersonalBestsView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let bests = entry.snapshot?.bests ?? []
        if bests.isEmpty {
            EmptyStateView(unreachable: entry.unreachable)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("PERSONAL BESTS")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(WidgetPalette.green)
                Spacer(minLength: 0)
                if family == .systemSmall {
                    ForEach(bests) { stat($0) }
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(bests) { stat($0, big: true) }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func stat(_ fact: WidgetSnapshot.Fact, big: Bool = false) -> some View {
        let copy = FactCopy(fact, today: entry.date)
        return WidgetStat(label: copy?.tileLabel ?? "", value: copy?.value ?? "—",
                          big: big, detail: copy?.detail)
    }
}

// MARK: - One fact, in words

/// What a `Fact` reads as. The kit sends numbers and the widget spells them, so a fact on
/// the home screen says what the same number says on the session page.
struct FactCopy {
    let headline: String
    /// The short form for a tile label on the personal-bests widget ("BEST 2 S").
    let tileLabel: String
    let value: String
    let detail: String?

    init?(_ fact: WidgetSnapshot.Fact, today: Date) {
        guard let kind = fact.factKind else { return nil }
        let season = fact.factScope == .season
        let place = [fact.spot, fact.date.map { WidgetFormat.shortDate($0, relativeTo: today) }]
            .compactMap { $0 }
            .joined(separator: " · ")
        let where_ = place.isEmpty ? nil : place

        switch kind {
        case .best2s:
            headline = season ? "Season's best 2 s" : "Best 2 s"
            tileLabel = "BEST 2 S"
            value = WidgetFormat.knots(fact.value, unit: true)
            detail = where_
        case .longestFlight:
            headline = season ? "Longest flight this season" : "Longest flight"
            tileLabel = "LONGEST FLIGHT"
            value = WidgetFormat.duration(fact.value)
            detail = where_
        case .bestJph:
            // JPH keeps its own name and its own line; CPH is not a replacement for it
            // (CLAUDE.md, "Rates are additive"). The caption is the key-metrics block's.
            headline = season ? "Best JPH this season" : "Best JPH"
            tileLabel = "BEST JPH"
            value = WidgetFormat.rate(fact.value)
            detail = ["dry jibes per hour", where_].compactMap { $0 }.joined(separator: " · ")
        case .longestDryStreak:
            headline = season ? "Longest dry streak this season" : "Longest dry streak"
            tileLabel = "DRY STREAK"
            let count = Int(fact.value.rounded())
            value = "\(count) maneuver" + (count == 1 ? "" : "s")
            detail = ["in a row without a swim", where_].compactMap { $0 }
                .joined(separator: " · ")
        case .onThisDay:
            headline = WidgetFormat.yearsAgo(fact.yearsAgo ?? 1)
            tileLabel = "THAT WEEK"
            value = fact.spot ?? "On the water"
            let flights = fact.flights ?? Int(fact.value.rounded())
            detail = [flights > 0 ? "\(flights) flight" + (flights == 1 ? "" : "s") : nil,
                      fact.best2sKn.map { "best 2 s " + WidgetFormat.knots($0, unit: true) }]
                .compactMap { $0 }
                .joined(separator: " · ")
        }
    }
}

struct FactView: View {
    let copy: FactCopy
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(copy.headline.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(WidgetPalette.green)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(copy.value)
                .font(.system(size: compact ? 15 : 18, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetPalette.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let detail = copy.detail, !detail.isEmpty, !compact {
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(WidgetPalette.paper.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
