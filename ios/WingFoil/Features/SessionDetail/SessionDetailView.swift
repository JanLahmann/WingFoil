import SwiftUI
import WingFoilKit

struct SessionDetailView: View {
    let sessionID: String
    @Environment(SessionStore.self) private var store

    @State private var detail: SessionDetail?
    @State private var failure: String?

    private var row: SessionRow? { store.session(id: sessionID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let detail {
                    if detail.segments.isEmpty {
                        noTrackNote
                    } else {
                        TrackMapView(detail: detail)
                        NavigationLink { FullScreenMapView(detail: detail) } label: {
                            Label("Open map full screen", systemImage: "map")
                                .font(.footnote)
                        }
                    }
                    SpeedChartView(detail: detail)
                    SummaryGrid(detail: detail)
                    footer(detail)
                } else if let failure {
                    ContentUnavailableView("Could not open this session",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(failure))
                } else {
                    ProgressView("Analyzing…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationTitle(row.map(SessionDisplay.title) ?? "Session")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: sessionID) { await load() }
    }

    private func load() async {
        guard detail == nil, let row else { return }
        do {
            detail = try await store.detail(for: row)
        } catch {
            failure = "\(error)"
        }
    }

    @ViewBuilder
    private var header: some View {
        if let row {
            VStack(alignment: .leading, spacing: 4) {
                Text(Fmt.date(row.startDate)).font(.title3.weight(.semibold))
                HStack(spacing: 8) {
                    Text(SessionDisplay.badge(row))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(SessionDisplay.badgeColor(row).opacity(0.16), in: .capsule)
                        .foregroundStyle(SessionDisplay.badgeColor(row))
                    Text(Fmt.duration(row.durationS))
                    Text("·")
                    Text(Fmt.km(row.distanceKm))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var noTrackNote: some View {
        Label("This recording has no GPS positions — chart and records only.",
              systemImage: "location.slash")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footer(_ detail: SessionDetail) -> some View {
        let rate = String(format: "%.1f", detail.analysis.capabilities.sampleRateHz)
        let provenance = "Engine \(detail.analysis.engineVersion) · \(rate) Hz · "
            + "sport \(SessionDisplay.sportLabel(detail.row.sport))"
            + (detail.row.importSource.map { " · via \($0)" } ?? "")
        return VStack(alignment: .leading, spacing: 4) {
            Text(SessionDisplay.sourceClassNote(detail.row.sourceClass))
            Text(provenance)
            if let file = detail.row.originalFilename { Text(file) }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
