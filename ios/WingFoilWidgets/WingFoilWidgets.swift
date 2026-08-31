import SwiftUI
import WidgetKit

/// The home-screen widgets: the last session, and the week's foiling time.
///
/// The extension deliberately does **not** link `WingFoilKit` — it compiles one shared
/// source file (`WidgetSnapshot.swift`) and reads a JSON blob the app publishes. A widget
/// that had to open the library database would need the app group *and* SQLite in a
/// 30 MB-memory-limited process, to draw four numbers.
@main
struct WingFoilWidgetBundle: WidgetBundle {
    var body: some Widget {
        LastSessionWidget()
        WeeklyFoilWidget()
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

struct SnapshotProvider: TimelineProvider {

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .preview, unreachable: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(entry())
    }

    /// One entry, refreshed hourly. The library only changes when the rider imports, and
    /// the app reloads the timelines itself when that happens — the hourly policy is just
    /// a floor so "3 days ago" does not go stale on a phone that never opens the app.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let next = Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry()], policy: .after(next)))
    }

    private func entry() -> SnapshotEntry {
        if let snapshot = WidgetSnapshotStore.read() {
            return SnapshotEntry(date: Date(), snapshot: snapshot, unreachable: false)
        }
        return SnapshotEntry(date: Date(), snapshot: nil,
                             unreachable: !WidgetSnapshotStore.appGroupAvailable)
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
        .description("Foil share, best 2 s and how the turns went.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WeeklyFoilWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "de.lahmann.wingfoil.widget.weekly",
                            provider: SnapshotProvider()) { entry in
            WeeklyFoilView(entry: entry)
                .containerBackground(WidgetPalette.background, for: .widget)
        }
        .configurationDisplayName("This week")
        .description("Time actually spent on the foil over the last seven days.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Views

private struct LastSessionView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let session = entry.snapshot?.lastSession {
            VStack(alignment: .leading, spacing: 6) {
                header(session)
                Spacer(minLength: 0)
                if family == .systemSmall {
                    WidgetStat(label: "FOIL", value: percent(session.foilPct), big: true)
                    WidgetStat(label: "BEST 2 S", value: knots(session.best2sKn))
                } else {
                    HStack(spacing: 10) {
                        WidgetStat(label: "FOIL", value: percent(session.foilPct), big: true)
                        WidgetStat(label: "BEST 2 S", value: knots(session.best2sKn), big: true)
                        WidgetStat(label: "FLIGHTS",
                                   value: session.flightCount.map(String.init) ?? "—", big: true)
                    }
                }
                if session.hasTurnTally { tally(session) }
            }
        } else {
            EmptyStateView(unreachable: entry.unreachable)
        }
    }

    private func header(_ session: WidgetSnapshot.LastSession) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(session.title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetPalette.paper)
                .lineLimit(1)
            Text(session.date, format: .dateTime.day().month(.abbreviated))
                .font(.system(size: 10))
                .foregroundStyle(WidgetPalette.paper.opacity(0.65))
        }
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

    private func percent(_ value: Double?) -> String {
        value.map { String(format: "%.0f%%", $0) } ?? "—"
    }

    private func knots(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "—"
    }
}

private struct WeeklyFoilView: View {
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("THIS WEEK")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(WidgetPalette.green)
                Spacer(minLength: 0)
                Text(foilTime(snapshot.weeklyFoilMinutes))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetPalette.paper)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("on the foil")
                    .font(.system(size: 11))
                    .foregroundStyle(WidgetPalette.paper.opacity(0.65))
                Spacer(minLength: 0)
                Text("\(snapshot.weeklySessions) session"
                     + (snapshot.weeklySessions == 1 ? "" : "s")
                     + String(format: " · %.1f h out", snapshot.weeklyHours))
                    .font(.system(size: 10))
                    .foregroundStyle(WidgetPalette.paper.opacity(0.55))
                    .lineLimit(1)
            }
        } else {
            EmptyStateView(unreachable: entry.unreachable)
        }
    }

    /// Minutes below an hour, then h + m — the same shape the app uses.
    private func foilTime(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if total < 60 { return "\(total) m" }
        return "\(total / 60) h \(total % 60) m"
    }
}

/// Empty either because there is nothing yet, or because the shared container is not
/// reachable. The second case is a setup fact and is worth saying out loud.
private struct EmptyStateView: View {
    let unreachable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "water.waves")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(WidgetPalette.green)
            Text(unreachable ? "Open CleanJibe to finish setting up the widget."
                             : "No sessions yet.")
                .font(.system(size: 11))
                .foregroundStyle(WidgetPalette.paper.opacity(0.75))
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct WidgetStat: View {
    let label: String
    let value: String
    var big = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(WidgetPalette.green)
            Text(value)
                .font(.system(size: big ? 22 : 16, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetPalette.paper)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The brand palette again — the extension is a separate target and cannot see the app's
/// `Brand`, and a widget is small enough that duplicating five colours beats adding a
/// shared file for them.
enum WidgetPalette {
    static let navy = Color(red: 0.039, green: 0.118, blue: 0.188)
    static let green = Color(red: 0.180, green: 0.902, blue: 0.659)
    static let paper = Color(red: 0.957, green: 0.980, blue: 1.000)

    static let background = LinearGradient(
        colors: [Color(red: 0.047, green: 0.157, blue: 0.243), navy],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension WidgetSnapshot {
    /// The gallery placeholder. Real-looking numbers, so the widget does not advertise
    /// itself as a row of dashes.
    static var preview: WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: Date(),
            lastSession: LastSession(id: "preview", title: "Torbole", date: Date(),
                                     foilPct: 62, best2sKn: 21.4, flightCount: 23,
                                     durationS: 5400, flewThrough: 9, touchdown: 9,
                                     fellIn: 12),
            weeklyFoilMinutes: 214, weeklySessions: 3, weeklyHours: 5.6)
    }
}
