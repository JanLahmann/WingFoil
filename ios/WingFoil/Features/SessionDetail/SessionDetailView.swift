import SwiftUI
import WingFoilKit

struct SessionDetailView: View {
    let sessionID: String
    @Environment(SessionStore.self) private var store

    @State private var detail: SessionDetail?
    @State private var failure: String?
    /// Engine window key of the GP3S effort highlighted on the map and chart.
    @State private var selectedEffort: String? = "best2s"

    private var row: SessionRow? { store.session(id: sessionID) }

    private var effort: SessionDetail.RecordEffort? {
        guard let detail, let selectedEffort else { return nil }
        return detail.efforts.first { $0.id == selectedEffort }
    }

    var body: some View {
        ScrollView {
            ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 20) {
                header
                if let detail {
                    if !detail.divergences.isEmpty {
                        DivergenceBanner(divergences: detail.divergences)
                    }
                    if detail.segments.isEmpty {
                        noTrackNote
                    } else {
                        TrackMapView(detail: detail, effort: effort)
                        NavigationLink {
                            FullScreenMapView(detail: detail, effort: effort)
                        } label: {
                            Label("Open map full screen", systemImage: "map")
                                .font(.footnote)
                        }
                    }
                    SpeedChartView(detail: detail, effort: effort)
                    SummaryGrid(detail: detail, selectedEffort: $selectedEffort)
                        .id("summary")
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
            #if DEBUG && targetEnvironment(simulator)
            // Headless-driving hook (see LibraryView): `simctl launch` cannot scroll, so
            // `UI_SCROLL_TO=<anchor>` parks the page on a card section for a screenshot
            // ("summary" for the whole grid, "takeoff" for the pumping card).
            .onChange(of: detail == nil) {
                guard detail != nil,
                      let anchor = ProcessInfo.processInfo.environment["UI_SCROLL_TO"]
                else { return }
                proxy.scrollTo(anchor, anchor: .top)
            }
            #endif
            }
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
            VStack(alignment: .leading, spacing: 6) {
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
                if let detail { WindRow(detail: detail) }
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

/// The estimated wind axis, plus the rider's own value from session dev field 39 when the
/// watch wrote one. Below `windMinConfidence` the estimate is shown but explicitly hedged —
/// that is exactly the case where turns stay unnamed rather than being called tacks/jibes.
private struct WindRow: View {
    let detail: SessionDetail

    var body: some View {
        if detail.analysis.wind != nil || detail.windDirUserDeg != nil {
            HStack(spacing: 8) {
                Image(systemName: "wind")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var text: String {
        var parts: [String] = []
        if let wind = detail.analysis.wind {
            let confidence = Int((wind.confidence * 100).rounded())
            let qualifier = wind.usable ? "" : " (too weak to name turns)"
            parts.append("Wind from \(compass(wind.dirDeg)) "
                         + "\(Int(wind.dirDeg.rounded()))° · \(confidence) % confident"
                         + qualifier)
        }
        if let user = detail.windDirUserDeg {
            parts.append("set on watch \(Int(user.rounded()))°")
        }
        return parts.joined(separator: " · ")
    }

    private func compass(_ deg: Double) -> String {
        let names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                     "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int(((deg.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360) / 22.5).rounded()) % 16
        return names[index]
    }
}

/// Watch-vs-phone divergence banner (docs/plan.md §5, thresholds in docs/algorithms.md).
/// A standing field-regression alarm on every class-(a) import: the phone recompute is
/// authoritative, so a divergence is a tuning issue to file against the session fixture,
/// not an error the rider has to act on.
private struct DivergenceBanner: View {
    let divergences: [Divergence]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Watch and phone disagree on \(list)")
                        .font(.footnote.weight(.medium))
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(divergences) { d in
                        HStack {
                            Text(d.metric).frame(width: 120, alignment: .leading)
                            Text(d.watch).frame(width: 70, alignment: .trailing)
                            Text("→")
                            Text(d.phone).frame(width: 70, alignment: .trailing)
                            Text(d.delta).foregroundStyle(.orange)
                            Spacer()
                        }
                        .font(.caption2.monospacedDigit())
                    }
                    Text("The phone recompute is authoritative — file this against the "
                         + "session fixture as a tuning issue.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 12))
    }

    private var list: String {
        let names = divergences.map(\.metric)
        if names.count <= 2 { return names.joined(separator: " and ").lowercased() }
        return names.prefix(2).joined(separator: ", ").lowercased()
            + " and \(names.count - 2) more"
    }
}
