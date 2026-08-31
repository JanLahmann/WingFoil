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
///
/// **Zoom is a pinch, deliberately.** An 80-minute session puts a couple of hundred marks
/// across 350 points of screen and they stop being readable; showing fewer seconds is the
/// only fix, and the declutter comes free with it (a mark outside the window is not drawn).
/// But one-finger drag is already the scrubber and that is the gesture worth keeping, so
/// zoom takes the two-finger one — the two can coexist because they are told apart by finger
/// count rather than by a mode. The visible window itself lives in `TimelineWindow`.
struct SpeedChartView: View {
    let detail: SessionDetail
    let effort: SessionDetail.RecordEffort?
    @Binding var playhead: Double?
    /// The legend chips filter the chart too — the map and the chart are two readings of
    /// one session, and an outcome dot present in one but missing from the other would
    /// make the pair unreadable.
    let visibility: MapLayerVisibility
    /// The flight a tap on the map asked about, if any. The chart frames it — one tap, two
    /// figures (docs/presentation.md, "Pairing").
    let flightFocus: SessionDetail.FlightFocus?

    /// The visible time window. Transient by design — zoom is how you are looking at the
    /// session that is open, not a preference about sessions — but owned by
    /// `SessionDetailView` rather than by this view, because the tab bar can take the chart
    /// off screen and bring it back. A `@State` here would silently reset the window on
    /// every trip to the Turns tab, and "reset my zoom because I looked at something else"
    /// is not what a transient window means. Nil until something moves it.
    @Binding var zoom: TimelineWindow?
    /// The window as the pinch found it. A magnification is cumulative from the start of the
    /// gesture, so it has to be applied to a fixed base or the chart accelerates away.
    @State private var pinchBase: TimelineWindow?
    @State private var pinchAnchor: Double?

    private var showsEffort: Bool { effort != nil && visibility.isVisible(.effort) }

    /// The session's whole span. `timeRange` is the scrubber's clock, which is the one the
    /// playhead rides on; the speed series is only the fallback for a recording with no
    /// usable timeline at all.
    private var fullRange: ClosedRange<Double> {
        if let range = detail.timeRange { return range }
        guard let first = detail.speed.first?.t, let last = detail.speed.last?.t,
              last > first else { return 0...1 }
        return first...last
    }

    private var window: TimelineWindow { zoom ?? TimelineWindow(full: fullRange) }

    private func update(_ change: (inout TimelineWindow) -> Void) {
        var next = window
        change(&next)
        zoom = next
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Speed").font(.headline)
                HelpButton(topic: .recordSet, size: .footnote)
                Spacer()
                if window.isZoomed {
                    resetChip
                } else if !detail.timeline.isEmpty {
                    Text("pinch to zoom · drag to scrub")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if detail.speed.isEmpty {
                Text("No speed channel in this recording.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                chart
                if window.isZoomed { rangeBar }
                HStack(spacing: 14) {
                    if visibility.isVisible(.flying) {
                        swatch(color: DesignTokens.Phase.flying.opacity(0.35), label: "flights")
                    }
                    if !detail.pumpSpans.isEmpty, visibility.isVisible(.pumping) {
                        swatch(color: EventMarkerStyle.pumping.opacity(0.45), label: "pumping")
                    }
                    if let effort, showsEffort {
                        swatch(color: DesignTokens.Effort.window.opacity(0.6),
                                label: effort.label.lowercased())
                    }
                    Spacer()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The window follows the playhead out of view rather than letting the rider lose it:
        // this is what makes replay watchable while zoomed, and it is also the "drag to the
        // edge and the chart comes with you" behaviour, written once.
        .onChange(of: playhead) {
            guard let playhead, pinchBase == nil, window.isZoomed else { return }
            update { $0.reveal(playhead) }
        }
        // A flight tapped on the map frames itself here, with its approach and its landing
        // either side of it. The reset chip the zoom already has is the way back out.
        .onChange(of: flightFocus) {
            guard let flightFocus else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                var next = TimelineWindow(full: fullRange)
                next.focus(on: flightFocus.span)
                zoom = next
            }
        }
        #if DEBUG && targetEnvironment(simulator)
        .onAppear(perform: stageZoomForScreenshot)
        #endif
    }

    /// Only while zoomed, like the legend's "show all": an always-present control would be
    /// clutter, and while it is there it is the one tap back to the whole session.
    private var resetChip: some View {
        Button { withAnimation(.easeOut(duration: 0.18)) { zoom = nil } } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.left.and.right")
                Text(String(format: "%.0f×", window.factor))
                    .monospacedDigit()
                Text("reset")
            }
            .font(.caption2.weight(.medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .accessibilityLabel("Reset zoom, showing the whole session")
    }

    /// Where the window sits in the session. Zoomed in, the chart's own axis no longer says
    /// which part of the ride you are looking at, and this is the cheapest thing that does.
    private var rangeBar: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.16))
                Capsule()
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: max(4, width * (window.endFraction - window.startFraction)))
                    .offset(x: width * window.startFraction)
            }
        }
        .frame(height: 3)
        .accessibilityLabel("Showing \(Fmt.clock(window.visible.lowerBound - fullRange.lowerBound))"
                            + " to \(Fmt.clock(window.visible.upperBound - fullRange.lowerBound))")
    }

    private var chart: some View {
        Chart {
            // The flight shading is the chart's rendering of the "flying" category, so it
            // answers to the same chip the map's teal track does. Clipped to the window
            // rather than dropped: a flight that started before it still covers the water.
            if visibility.isVisible(.flying) {
                ForEach(clip(detail.flightBands)) { band in
                    RectangleMark(xStart: .value("Flight start", band.start),
                                  xEnd: .value("Flight end", band.end))
                        .foregroundStyle(DesignTokens.Phase.flying.opacity(0.16))
                }
            }
            // Pumping is a span, so the chart draws it the way it draws flights: a band,
            // not a dot. On the speed trace it is the ramp *into* every takeoff, which is
            // exactly where the reader wants it.
            if visibility.isVisible(.pumping) {
                ForEach(clip(detail.pumpSpans.map(\.band))) { band in
                    RectangleMark(xStart: .value("Pump start", band.start),
                                  xEnd: .value("Pump end", band.end))
                        .foregroundStyle(EventMarkerStyle.pumping.opacity(0.28))
                }
            }
            if let effort, showsEffort, let band = clip([effort.band]).first {
                RectangleMark(xStart: .value("Best start", band.start),
                              xEnd: .value("Best end", band.end))
                    .foregroundStyle(DesignTokens.Effort.window.opacity(0.55))
            }
            ForEach(visibleSpeed) { point in
                LineMark(x: .value("Time", point.t), y: .value("Speed", point.kn))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.4))
                    .foregroundStyle(Color.accentColor)
            }
            ForEach(detail.visibleMarkers(visibility).filter { window.contains($0.t) }) { marker in
                PointMark(x: .value("Time", marker.t),
                          y: .value("Speed", markerSpeed(at: marker.t)))
                    .symbol {
                        EventMarkerStyle.dot(marker, size: 8)
                    }
            }
            // The chip filters the chart as well as the map: a takeoff visible on one and
            // missing from the other would make the pair unreadable.
            if visibility.isVisible(.takeoff) {
                ForEach(detail.takeoffMarks.filter { window.contains($0.t) }) { mark in
                    PointMark(x: .value("Time", mark.t),
                              y: .value("Speed", markerSpeed(at: mark.t)))
                        .symbol { EventMarkerStyle.takeoffMark(mark, size: 10) }
                }
            }
            if visibility.isVisible(.splash) {
                ForEach(detail.splashMarks.filter { window.contains($0.t) }) { mark in
                    PointMark(x: .value("Time", mark.t),
                              y: .value("Speed", markerSpeed(at: mark.t)))
                        .symbol { EventMarkerStyle.splashMark(size: 9) }
                }
            }
            // Declared last and given an explicit z-index: the outcome dots are dense on a
            // long session and the playhead has to be readable *through* them.
            if let playhead, let moment = detail.moment(at: playhead),
               window.contains(moment.t) {
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
        .chartXScale(domain: window.visible)
        // Round times, not equal fifths of the domain: `.automatic` labelled this axis
        // `0:00 · 33:20 · 66:40 · 100:00` (app-ui-review.md §1.5). `TimeAxisTicks` is the
        // rule, in the kit, so the HR-cost chart below cannot drift away from it.
        .chartXAxis {
            AxisMarks(values: TimeAxisTicks.values(for: window.visible, desiredCount: 5)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(Fmt.clock(seconds))
                    }
                }
            }
        }
        .chartYScale(domain: 0...(max(detail.maxSpeedKn * 1.1, 5)))
        .chartOverlay { proxy in gestureSurface(proxy) }
        .figureHeight(regular: 190, compact: 150)
    }

    // MARK: - Marks inside the window
    //
    // Everything the chart draws is filtered here rather than left to the scale to clip:
    // fewer marks is the *point* of zooming, and marks the reader cannot see should not be
    // laid out either.

    private var visibleSpeed: [SessionDetail.SpeedPoint] {
        guard window.isZoomed else { return detail.speed }
        var out: [SessionDetail.SpeedPoint] = []
        for (index, point) in detail.speed.enumerated() {
            if window.contains(point.t) {
                // One point beyond each edge, so the trace reaches the frame instead of
                // stopping short of it.
                if out.isEmpty, index > 0 { out.append(detail.speed[index - 1]) }
                out.append(point)
            } else if !out.isEmpty {
                out.append(point)
                break
            }
        }
        return out
    }

    private func clip(_ bands: [SessionDetail.Band]) -> [SessionDetail.Band] {
        bands.compactMap { band in
            guard let range = window.clipped(start: band.start, end: band.end) else { return nil }
            return SessionDetail.Band(id: band.id, start: range.lowerBound,
                                      end: range.upperBound)
        }
    }

    // MARK: - Gestures

    /// A transparent surface over the plot area carrying both handles on the chart.
    ///
    /// One finger scrubs (`minimumDistance: 0` so a tap works as well as a drag — tapping a
    /// spike to see what it was is the common case). Two fingers zoom. They are attached
    /// simultaneously and separated by `pinchBase`: a pinch also delivers a drag centroid,
    /// and without the guard every zoom would fling the playhead across the session on its
    /// way in.
    private func gestureSurface(_ proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            if let plotFrame = proxy.plotFrame {
                let frame = geometry[plotFrame]
                Rectangle()
                    .fill(.clear)
                    .contentShape(.rect)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard pinchBase == nil else { return }
                                guard let t = time(proxy, x: value.location.x - frame.origin.x)
                                else { return }
                                playhead = window.clamp(t)
                            })
                    .simultaneousGesture(
                        MagnifyGesture(minimumScaleDelta: 0.02)
                            .onChanged { value in
                                let base = pinchBase ?? window
                                if pinchBase == nil {
                                    pinchBase = base
                                    // The time under the pinch centre, held still while the
                                    // window grows and shrinks around it.
                                    pinchAnchor = time(proxy,
                                                       x: value.startLocation.x - frame.origin.x)
                                        ?? base.visible.lowerBound + base.span / 2
                                }
                                guard let anchor = pinchAnchor else { return }
                                var next = base
                                next.magnify(by: value.magnification, around: anchor)
                                zoom = next
                            }
                            .onEnded { _ in
                                pinchBase = nil
                                pinchAnchor = nil
                            })
            }
        }
    }

    private func time(_ proxy: ChartProxy, x: CGFloat) -> Double? {
        guard let t: Double = proxy.value(atX: x) else { return nil }
        return t
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

    #if DEBUG && targetEnvironment(simulator)
    /// Screenshot hook, same family as `UI_HIDE_LAYERS`: `simctl` has no fingers, so
    /// `UI_CHART_ZOOM=<factor>` opens the chart already zoomed. It centres on `UI_PLAYHEAD`
    /// when one is set, which is the only way to photograph a *busy* stretch on purpose
    /// rather than whatever happens to be mid-session.
    private func stageZoomForScreenshot() {
        let environment = ProcessInfo.processInfo.environment
        guard let factor = environment["UI_CHART_ZOOM"].flatMap(Double.init), factor > 1
        else { return }
        let fraction = environment["UI_PLAYHEAD"].flatMap(Double.init) ?? 0.5
        let range = fullRange
        let center = range.lowerBound
            + (range.upperBound - range.lowerBound) * min(max(fraction, 0), 1)
        update { $0.zoom(to: factor, centeredOn: center) }
    }
    #endif
}
