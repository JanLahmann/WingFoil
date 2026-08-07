import SwiftUI
import WingFoilKit

/// Foil/flight summary plus the GP3S record set. Records that the session could not
/// produce (no qualifying run) stay visible with an explicit placeholder rather than
/// disappearing — the absence is information.
struct SummaryGrid: View {
    let detail: SessionDetail

    private var summary: SessionSummary { detail.analysis.summary }
    private var records: GP3SRecords { detail.analysis.records }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            section("Foil") {
                StatCard(title: "Foil time", value: Fmt.pct(summary.foilPct),
                         caption: Fmt.duration(summary.foilTimeS))
                StatCard(title: "Flights", value: "\(summary.flightCount)",
                         caption: summary.flightCount == 0 ? "none detected" : "detected")
                StatCard(title: "Longest flight",
                         value: Fmt.duration(summary.longestFlightS),
                         caption: Fmt.meters(summary.longestFlightM))
                StatCard(title: "Distance", value: Fmt.km(summary.distanceKm),
                         caption: Fmt.duration(detail.durationS) + " elapsed")
            }

            section("Speed records") {
                record("Best 2 s", records.best2sKn, window: "best2s")
                record("Best 10 s", records.best10sKn, window: "best10s")
                record("5 × 10 s", records.best5x10sKn, window: "best5x10s")
                record("Best 500 m", records.best500mKn, window: "best500m")
                record("Alpha 500", records.alpha500Kn, window: "alpha500")
                record("Best 1 NM", records.bestNmKn, window: "bestNm")
            }
        }
    }

    private func section(_ title: String,
                         @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            LazyVGrid(columns: columns, spacing: 12) { content() }
        }
    }

    private func record(_ title: String, _ value: Double?, window: String) -> some View {
        StatCard(title: title,
                 value: Fmt.kn(value),
                 caption: value == nil ? "no qualifying run"
                                       : caption(for: records.windows[window]),
                 dimmed: value == nil)
    }

    private func caption(for window: RecordWindow?) -> String {
        guard let window else { return " " }
        return "at \(Fmt.clock(window.startTs)) · \(Fmt.duration(window.durS))"
    }
}

struct StatCard: View {
    let title: String
    let value: String
    var caption: String = " "
    var dimmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(dimmed ? .secondary : .primary)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
    }
}
