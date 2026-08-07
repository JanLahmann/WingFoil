import Charts
import SwiftUI

/// Speed over time in knots, with the detected flights shaded and the best-2 s window
/// (record provenance) marked.
struct SpeedChartView: View {
    let detail: SessionDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speed").font(.headline)

            if detail.speed.isEmpty {
                Text("No speed channel in this recording.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(detail.flightBands) { band in
                        RectangleMark(xStart: .value("Flight start", band.start),
                                      xEnd: .value("Flight end", band.end))
                            .foregroundStyle(Color.teal.opacity(0.16))
                    }
                    if let window = detail.bestWindow {
                        RectangleMark(xStart: .value("Best start", window.start),
                                      xEnd: .value("Best end", window.end))
                            .foregroundStyle(Color.orange.opacity(0.55))
                    }
                    ForEach(detail.speed) { point in
                        LineMark(x: .value("Time", point.t), y: .value("Speed", point.kn))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 1.4))
                            .foregroundStyle(Color.accentColor)
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

                HStack(spacing: 14) {
                    swatch(color: .teal.opacity(0.35), label: "flights")
                    swatch(color: .orange.opacity(0.6), label: "best 2 s window")
                    Spacer()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func swatch(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 10)
            Text(label)
        }
    }
}
