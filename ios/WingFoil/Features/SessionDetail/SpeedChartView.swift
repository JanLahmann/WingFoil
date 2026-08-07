import Charts
import SwiftUI

/// Speed over time in knots: detected flights shaded, the selected GP3S window marked
/// (record provenance), and every maneuver / straight-line flight end dotted at the
/// speed it happened, coloured by outcome.
struct SpeedChartView: View {
    let detail: SessionDetail
    let effort: SessionDetail.RecordEffort?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speed").font(.headline)

            if detail.speed.isEmpty {
                Text("No speed channel in this recording.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                chart
                HStack(spacing: 14) {
                    swatch(color: .teal.opacity(0.35), label: "flights")
                    if let effort {
                        swatch(color: .orange.opacity(0.6), label: effort.label.lowercased())
                    }
                    Spacer()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chart: some View {
        Chart {
            ForEach(detail.flightBands) { band in
                RectangleMark(xStart: .value("Flight start", band.start),
                              xEnd: .value("Flight end", band.end))
                    .foregroundStyle(Color.teal.opacity(0.16))
            }
            if let effort {
                RectangleMark(xStart: .value("Best start", effort.band.start),
                              xEnd: .value("Best end", effort.band.end))
                    .foregroundStyle(Color.orange.opacity(0.55))
            }
            ForEach(detail.speed) { point in
                LineMark(x: .value("Time", point.t), y: .value("Speed", point.kn))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.4))
                    .foregroundStyle(Color.accentColor)
            }
            ForEach(detail.markers) { marker in
                PointMark(x: .value("Time", marker.t),
                          y: .value("Speed", markerSpeed(at: marker.t)))
                    .symbol {
                        EventMarkerStyle.dot(marker, size: 8)
                    }
            }
        }
        .chartYAxisLabel("kn")
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(Fmt.clock(seconds))
                    }
                }
            }
        }
        .chartYScale(domain: 0...(max(detail.maxSpeedKn * 1.1, 5)))
        .frame(height: 190)
    }

    /// The plotted speed nearest the event, so a marker sits on the trace rather than
    /// floating above it.
    private func markerSpeed(at t: Double) -> Double {
        guard !detail.speed.isEmpty else { return 0 }
        var best = detail.speed[0]
        var bestDelta = Double.infinity
        for point in detail.speed {
            let delta = abs(point.t - t)
            if delta < bestDelta {
                bestDelta = delta
                best = point
            }
            if point.t > t { break }
        }
        return best.kn
    }

    private func swatch(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 10)
            Text(label)
        }
    }
}
