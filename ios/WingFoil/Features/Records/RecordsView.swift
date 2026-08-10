import Charts
import SwiftUI
import WingFoilKit

/// All-time GP3S personal bests in knots (plan §3.3 "Records: all-time/per-spot/per-gear,
/// kn"), each row backed by the `record_effort` history: the sparkline is every session's
/// effort for that kind, the highlighted step is the PB that stands today.
struct RecordsView: View {
    @Environment(SessionStore.self) private var store

    @State private var filter = LibraryFilter()
    @State private var records: [RecordBest] = []
    @State private var loaded = false

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
                                RecordRowView(best: best, title: title(of: best.sessionId))
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
        }
    }

    /// Any of these changing means the query has to run again.
    private var reloadKey: String {
        "\(filter.spotId ?? "-")|\(filter.gearId ?? "-")|\(store.libraryGeneration)"
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
            + "sources (device FIT); class (c) sources are marked."
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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(best.kind.label)
                        .font(.subheadline.weight(.semibold))
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
                .frame(width: 84, height: 40)
        }
        .padding(.vertical, 4)
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
