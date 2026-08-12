import Charts
import SwiftUI
import UIKit
import WingFoilKit

/// All-time GP3S personal bests in knots (plan §3.3 "Records: all-time/per-spot/per-gear,
/// kn"), each row backed by the `record_effort` history: the sparkline is every session's
/// effort for that kind, the highlighted step is the PB that stands today.
///
/// A record beaten by the most recent import arrives here flagged, and gets the one
/// celebration the app has: a confetti burst and a haptic, once, on the screen where the
/// number actually lives.
struct RecordsView: View {
    @Environment(SessionStore.self) private var store

    @State private var filter = LibraryFilter()
    @State private var records: [RecordBest] = []
    @State private var loaded = false
    @State private var confetti: Int?
    /// Kinds beaten by the last import, so their rows can say so.
    @State private var freshlyBeaten: Set<RecordKind> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LibraryFilterBar(filter: $filter)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listRowBackground(Color.clear)

                if records.isEmpty {
                    emptyState
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(records) { best in
                            NavigationLink(value: best.sessionId) {
                                RecordRowView(best: best, title: title(of: best.sessionId),
                                              isNew: freshlyBeaten.contains(best.kind))
                            }
                        }
                    } footer: {
                        Text(footnote)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Records")
            .navigationDestination(for: String.self) { SessionDetailView(sessionID: $0) }
            .refreshable { await reload() }
            .task(id: reloadKey) { await reload() }
            .task(id: store.celebration.count) { celebrateIfNeeded() }
            .overlay { ConfettiBurst(trigger: confetti) }
            #if DEBUG && targetEnvironment(simulator)
            // Headless-driving hook: a real burst needs an import that beats a standing
            // record, which an automated screenshot run cannot stage. `UI_CONFETTI=1`
            // fires the same burst against the first two records.
            .task {
                guard ProcessInfo.processInfo.environment["UI_CONFETTI"] == "1" else { return }
                // Wait for the query rather than guessing at a delay, or the burst races
                // the reload and fires against an empty record list.
                for _ in 0..<40 where records.isEmpty {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
                freshlyBeaten = Set(records.prefix(2).map(\.kind))
                confetti = (confetti ?? 0) + 1
            }
            #endif
        }
    }

    /// Any of these changing means the query has to run again.
    private var reloadKey: String {
        "\(filter.spotId ?? "-")|\(filter.gearId ?? "-")|\(store.libraryGeneration)"
    }

    /// One burst per import, on arrival at the screen that owns the number.
    private func celebrateIfNeeded() {
        let beaten = store.celebration
        guard !beaten.isEmpty else { return }
        freshlyBeaten = Set(beaten.map(\.kind))
        confetti = (confetti ?? 0) + 1
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        store.clearCelebration()
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(loaded ? "No records yet" : "Loading…", systemImage: "trophy")
        } description: {
            Text(store.sessions.isEmpty
                 ? "Import or sync a session and its speed records appear here."
                 : "No qualifying speed window under this filter.")
        }
    }

    private var footnote: String {
        let certified = records.filter(\.certified).count
        return "Doppler speed, GP3S windows. \(certified) of \(records.count) from certified "
            + "sources (device FIT); class (c) sources are marked. The medal shows how fresh "
            + "a record is — gold within a month, silver within the season, bronze older."
    }

    private func title(of sessionID: String) -> String {
        store.session(id: sessionID).map(SessionDisplay.title) ?? "Session"
    }

    private func reload() async {
        records = (try? await store.library.records(filter)) ?? []
        loaded = true
    }
}

private struct RecordRowView: View {
    let best: RecordBest
    let title: String
    var isNew = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RecordMedal(kind: best.kind, age: Medal.of(best.achievedAt))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(best.kind.label)
                        .font(.subheadline.weight(.semibold))
                    if isNew {
                        Text("NEW")
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.22), in: .capsule)
                            .foregroundStyle(Color.accentColor)
                    }
                    if !best.certified {
                        Text("uncertified")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18), in: .capsule)
                            .foregroundStyle(.orange)
                    }
                }
                Text(Fmt.kn(best.valueKn))
                    .font(.title2.weight(.bold).monospacedDigit())
                HStack(spacing: 5) {
                    Text(Fmt.shortDate(best.achievedAt))
                    Text("·")
                    Text(title).lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let previous = best.previousBest {
                    Text(String(format: "+%.2f kn on the previous best", best.valueKn - previous))
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else if best.history.count == 1 {
                    Text("First session with this record")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            PBSparkline(best: best)
                .frame(width: 74, height: 40)
        }
        .padding(.vertical, 4)
    }
}

/// How fresh a standing record is. The metal answers "which of my PBs still mean
/// something" — a 2 s from three seasons ago is a fact about a day, not about form.
enum Medal {
    case gold, silver, bronze

    static func of(_ achievedAt: Date, now: Date = Date()) -> Medal {
        let days = now.timeIntervalSince(achievedAt) / 86400
        if days <= 30 { return .gold }
        if days <= 183 { return .silver }
        return .bronze
    }

    var colors: [Color] {
        switch self {
        case .gold: [Color(red: 1.00, green: 0.86, blue: 0.42),
                     Color(red: 0.85, green: 0.62, blue: 0.12)]
        case .silver: [Color(red: 0.92, green: 0.94, blue: 0.96),
                       Color(red: 0.62, green: 0.66, blue: 0.71)]
        case .bronze: [Color(red: 0.87, green: 0.66, blue: 0.47),
                       Color(red: 0.61, green: 0.40, blue: 0.24)]
        }
    }

    var label: String {
        switch self {
        case .gold: "set within the last month"
        case .silver: "set this season"
        case .bronze: "older than six months"
        }
    }
}

/// The medal disc: a brushed-metal gradient with the record's own short label struck into
/// it, so the row is scannable without reading the numbers.
private struct RecordMedal: View {
    let kind: RecordKind
    let age: Medal

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: age.colors,
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .stroke(.white.opacity(0.55), lineWidth: 1)
                .padding(3)
            Text(kind.label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.black.opacity(0.72))
                .minimumScaleFactor(0.5)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(4)
        }
        .frame(width: 44, height: 44)
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        .accessibilityLabel("\(kind.label) record, \(age.label)")
    }
}

/// Every session's effort for one record kind (faint line) with the PB step curve on top
/// and the standing best as a filled point.
struct PBSparkline: View {
    let best: RecordBest

    var body: some View {
        if best.history.count < 2 {
            Image(systemName: "trophy.fill")
                .foregroundStyle(.yellow)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart {
                ForEach(best.history, id: \.sessionId) { effort in
                    LineMark(x: .value("When", effort.achievedAt),
                             y: .value("Speed", effort.valueKn),
                             series: .value("Series", "efforts"))
                        .foregroundStyle(.secondary.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
                ForEach(best.personalBests, id: \.sessionId) { effort in
                    LineMark(x: .value("When", effort.achievedAt),
                             y: .value("Speed", effort.valueKn),
                             series: .value("Series", "pbs"))
                        .foregroundStyle(Color.accentColor)
                        .interpolationMethod(.stepEnd)
                }
                PointMark(x: .value("When", best.achievedAt),
                          y: .value("Speed", best.valueKn))
                    .symbolSize(24)
                    .foregroundStyle(Color.accentColor)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .accessibilityLabel("Personal best history, \(best.history.count) sessions")
        }
    }
}
