import Charts
import SwiftUI
import WingFoilKit

/// Speed over time in knots: detected flights shaded, the selected GP3S window marked
/// (record provenance), and every maneuver / straight-line flight end dotted at the
/// speed it happened, coloured by outcome.
///
/// The chart is also one of the two handles on the replay playhead (the map is the other):
/// touching it anywhere scrubs, and the playhead it draws is the same `Double?` the map dot
/// and the readout resolve through.
struct SpeedChartView: View {
    let detail: SessionDetail
    let effort: SessionDetail.RecordEffort?
    @Binding var playhead: Double?
    /// The legend chips filter the chart too — the map and the chart are two readings of
    /// one session, and an outcome dot present in one but missing from the other would
    /// make the pair unreadable.
    let visibility: MapLayerVisibility

    private var showsEffort: Bool { effort != nil && visibility.isVisible(.effort) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Speed").font(.headline)
                HelpButton(topic: .recordSet, size: .footnote)
                Spacer()
                if !detail.timeline.isEmpty {
                    Text("drag to scrub")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if detail.speed.isEmpty {
                Text("No speed channel in this recording.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                chart
                HStack(spacing: 14) {
                    if visibility.isVisible(.flying) {
                        swatch(color: .teal.opacity(0.35), label: "flights")
                    }
                    if !detail.pumpSpans.isEmpty, visibility.isVisible(.pumping) {
                        swatch(color: EventMarkerStyle.pumping.opacity(0.45), label: "pumping")
                    }
                    if let effort, showsEffort {
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
            // The flight shading is the chart's rendering of the "flying" category, so it
            // answers to the same chip the map's teal track does.
            if visibility.isVisible(.flying) {
                ForEach(detail.flightBands) { band in
                    RectangleMark(xStart: .value("Flight start", band.start),
                                  xEnd: .value("Flight end", band.end))
                        .foregroundStyle(Color.teal.opacity(0.16))
                }
            }
            // Pumping is a span, so the chart draws it the way it draws flights: a band,
            // not a dot. On the speed trace it is the ramp *into* every takeoff, which is
            // exactly where the reader wants it.
            if visibility.isVisible(.pumping) {
                ForEach(detail.pumpSpans) { span in
                    RectangleMark(xStart: .value("Pump start", span.band.start),
                                  xEnd: .value("Pump end", span.band.end))
                        .foregroundStyle(EventMarkerStyle.pumping.opacity(0.28))
                }
            }
            if let effort, showsEffort {
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
            ForEach(detail.visibleMarkers(visibility)) { marker in
                PointMark(x: .value("Time", marker.t),
                          y: .value("Speed", markerSpeed(at: marker.t)))
                    .symbol {
                        EventMarkerStyle.dot(marker, size: 8)
                    }
            }
            // The chip filters the chart as well as the map: a takeoff visible on one and
            // missing from the other would make the pair unreadable.
            if visibility.isVisible(.takeoff) {
                ForEach(detail.takeoffMarks) { mark in
                    PointMark(x: .value("Time", mark.t),
                              y: .value("Speed", markerSpeed(at: mark.t)))
                        .symbol { EventMarkerStyle.takeoffMark(mark, size: 10) }
                }
            }
            if visibility.isVisible(.splash) {
                ForEach(detail.splashMarks) { mark in
                    PointMark(x: .value("Time", mark.t),
                              y: .value("Speed", markerSpeed(at: mark.t)))
                        .symbol { EventMarkerStyle.splashMark(size: 9) }
                }
            }
            // Declared last and given an explicit z-index: the outcome dots are dense on a
            // long session and the playhead has to be readable *through* them.
            if let playhead, let moment = detail.moment(at: playhead) {
                RuleMark(x: .value("Playhead", moment.t))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    .foregroundStyle(Color(.label))
                    .zIndex(10)
                PointMark(x: .value("Playhead", moment.t),
                          y: .value("Speed", markerSpeed(at: moment.t)))
                    .symbol {
                        Circle()
                            .fill(Color(.label))
                            .stroke(Color(.systemBackground), lineWidth: 2)
                            .frame(width: 13, height: 13)
                    }
                    .zIndex(11)
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
        .chartOverlay { proxy in scrubSurface(proxy) }
        .frame(height: 190)
    }

    /// A transparent surface over the plot area that turns a touch into a time.
    /// `minimumDistance: 0` so a tap works as well as a drag — tapping a spike to see what
    /// it was is the common case, scrubbing is the deliberate one.
    private func scrubSurface(_ proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            if let plotFrame = proxy.plotFrame {
                let frame = geometry[plotFrame]
                Rectangle()
                    .fill(.clear)
                    .contentShape(.rect)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let x = value.location.x - frame.origin.x
                                guard let t: Double = proxy.value(atX: x),
                                      let range = detail.timeRange else { return }
                                playhead = min(max(t, range.lowerBound), range.upperBound)
                            })
            }
        }
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
